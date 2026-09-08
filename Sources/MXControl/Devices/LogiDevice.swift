import Foundation
import MXControlHIDPP
import Observation
import os

/// A single Logitech HID++ 2.0 device.
///
/// Generic over a `DeviceDescriptor`: capabilities become observable states,
/// service wiring (scroll, gestures, mic-mute) attaches as behaviors.
/// No per-device subclasses — supporting a new device is a descriptor value.
///
/// `@MainActor` keeps all property access on the main thread.
/// `@unchecked Sendable` allows capture in `@Sendable` closures; all
/// reads/writes MUST remain on `@MainActor`.
@MainActor
@Observable
class LogiDevice: Identifiable, @unchecked Sendable {

    // MARK: - Identity

    let id = UUID()
    let deviceIndex: UInt8
    let transport: HIDTransport
    var descriptor: DeviceDescriptor

    // MARK: - Discovered Properties

    var name: String = "Unknown"
    var deviceKind: DeviceNameFeature.DeviceKind = .unknown
    var deviceType: DeviceType = .unknown
    var protocolMajor: UInt8 = 0
    var protocolMinor: UInt8 = 0
    var features: [FeatureSetFeature.FeatureEntry] = []

    // MARK: - Feature Index Cache

    let featureIndexCache = FeatureIndexCache()

    // MARK: - Capability States

    var toggles: [CapabilityID: ToggleState] = [:]
    var ints: [CapabilityID: IntSliderState] = [:]
    var doubles: [CapabilityID: DoubleSliderState] = [:]
    var segmented: [CapabilityID: SegmentedState] = [:]
    let battery = BatteryState()
    let hosts = HostListState()

    // MARK: - Session Caches (resolved per connection, not persisted)

    var dpiMin: Int = 200
    var dpiMax: Int = 8000
    var dpiStep: Int = 50
    var pointerSpeed: Int = 256
    var smartShiftMaxForce: Int = 100
    var backlightFid: UInt16?
    var backlightMode: BacklightFeature.BacklightMode = .automatic
    var backlightMaxLevel: Int = 8
    var backlightOptions: UInt8 = 0
    var backlightDho: UInt16 = 0
    var backlightDhi: UInt16 = 0
    var backlightDpow: UInt16 = 0
    var fnFid: UInt16?
    var fnGKeyState: UInt8 = 0
    var hiResScrollFeatureIndex: UInt8?
    var hiResMultiplier: Int = 8
    var specialKeysFeatureIndex: UInt8?
    var gestureEngine: GestureEngine?
    /// In-flight HID++ target toggle. Cancelled on rapid re-toggle so the
    /// final device state matches the last user intent.
    var hiResTargetTask: Task<Void, Never>?

    // MARK: - Behaviors

    var behaviors: [any DeviceBehavior] = []

    var scrollBehavior: ScrollBehavior? {
        behaviors.first { $0 is ScrollBehavior } as? ScrollBehavior
    }

    var thumbGestureBehavior: ThumbGestureBehavior? {
        behaviors.first { $0 is ThumbGestureBehavior } as? ThumbGestureBehavior
    }

    var micMuteBehavior: MicMuteBehavior? {
        behaviors.first { $0 is MicMuteBehavior } as? MicMuteBehavior
    }

    /// Whether F9 should be intercepted globally (mic wanted, no HID++ divert).
    var micMuteWantsFallback: Bool {
        guard let behavior = micMuteBehavior else { return false }
        return behavior.isEnabled && !behavior.divertActive
    }

    // MARK: - State

    var isInitialized: Bool = false
    var isFeaturesLoaded: Bool = false
    var initError: String?
    var loadErrors: [String] = []

    var featureLoadError: String? {
        loadErrors.isEmpty ? nil : loadErrors.joined(separator: "; ")
    }

    // MARK: - Init

    init(deviceIndex: UInt8, transport: HIDTransport, descriptor: DeviceDescriptor? = nil) {
        self.deviceIndex = deviceIndex
        self.transport = transport
        self.descriptor = descriptor ?? DeviceDescriptors.generic(kind: .unknown, name: "Unknown")
    }

    // MARK: - Initialization

    /// Discover device identity and enumerate features.
    ///
    /// 1. Ping to confirm device is alive and get protocol version.
    /// 2. Get device name and type via DeviceNameFeature.
    /// 3. Enumerate all features via FeatureSetFeature.
    func initialize() async throws {
        // 1. Ping
        let ping = try await RootFeature.ping(
            transport: transport,
            deviceIndex: deviceIndex
        )
        protocolMajor = ping.protocolMajor
        protocolMinor = ping.protocolMinor

        // 2. Device name & type
        let nameFeatureInfo = try await RootFeature.getFeature(
            transport: transport,
            deviceIndex: deviceIndex,
            featureId: DeviceNameFeature.featureId
        )

        if nameFeatureInfo.index != 0 {
            await featureIndexCache.set(DeviceNameFeature.featureId, index: nameFeatureInfo.index)

            name = try await DeviceNameFeature.getFullName(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: nameFeatureInfo.index
            )

            deviceKind = try await DeviceNameFeature.getType(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: nameFeatureInfo.index
            )

            // Map HID++ device kind to our DeviceType
            switch deviceKind {
            case .mouse, .trackball, .touchpad:
                deviceType = .mouse
            case .keyboard, .numpad:
                deviceType = .keyboard
            case .receiver:
                deviceType = .receiver
            default:
                deviceType = .unknown
            }
        }

        // 3. Enumerate features
        features = try await FeatureSetFeature.enumerateAll(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndexCache: featureIndexCache
        )

        isInitialized = true

        printSummary()
    }

    // MARK: - Capabilities

    /// Capability ids sharing one loader invocation.
    private static func loaderGroup(for id: CapabilityID) -> String {
        switch id {
        case .smartShiftWheelMode, .smartShiftActive,
             .smartShiftTorque:
            return "smartshift"
        case .backlightEnabled, .backlightLevel:
            return "backlight"
        case .hiResEnabled, .hiResInverted:
            return "hires"
        default:
            return id.rawValue
        }
    }

    /// Attach behaviors from the descriptor. Call once after matching.
    func attachBehaviors() {
        var attached: [any DeviceBehavior] = []
        if descriptor.scroll != nil {
            attached.append(ScrollBehavior(device: self))
        }
        if descriptor.thumbGesture != nil {
            attached.append(ThumbGestureBehavior(device: self))
        }
        if descriptor.micMute != nil {
            attached.append(MicMuteBehavior(device: self))
        }
        behaviors = attached
    }

    /// Create states and load every declared capability.
    /// Each capability loads independently so a transient failure on one
    /// does not prevent others from loading.
    func loadCapabilities() async {
        CapabilityHandlers.createStates(for: descriptor.capabilities, on: self)

        // Scalar capabilities first (services sync from their values).
        // Capabilities whose feature the device does not report are skipped.
        // Several ids share one loader (smartshift.*, backlight.*) — each
        // loader runs once.
        var loadedGroups = Set<String>()
        for capability in descriptor.capabilities {
            if let featureId = capability.featureId, !hasFeature(featureId) {
                continue
            }
            let group = Self.loaderGroup(for: capability.id)
            guard !loadedGroups.contains(group) else { continue }
            loadedGroups.insert(group)
            await CapabilityHandlers.load(capability.id, on: self)
        }

        // Behaviors last: diverts, targets, engines.
        for behavior in behaviors {
            await behavior.load()
        }
        // Local-only states (smooth scroll, gestures) were read from prefs
        // above; push them into services now that behaviors exist.
        scrollBehavior?.syncServices()
        thumbGestureBehavior?.syncEngine()

        isFeaturesLoaded = true
        if loadErrors.isEmpty {
            logger.info("[LogiDevice] All capabilities loaded for \(self.name, privacy: .public)")
        } else {
            logger.warning("[LogiDevice] Loaded with \(self.loadErrors.count) error(s) for \(self.name, privacy: .public): \(self.loadErrors.joined(separator: "; "), privacy: .public)")
        }
    }

    /// Write one capability's current state to the device and persist it.
    /// No-op when the device has no state for the id (e.g. feature missing
    /// or load failed) so a UI toggle can never persist a fallback default.
    func commit(_ id: CapabilityID) async {
        guard toggles[id] != nil || ints[id] != nil
            || doubles[id] != nil || segmented[id] != nil
        else {
            debugLog("[LogiDevice] Commit \(id.rawValue) ignored: no state")
            return
        }
        await CapabilityHandlers.commit(id, on: self)
    }

    /// Handle an unsolicited HID++ notification from the device.
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        for behavior in behaviors {
            behavior.handleNotification(featureIndex: featureIndex, functionId: functionId, params: params)
        }
    }

    /// Re-arm volatile wiring (diverts, scroll target) after a BLE reconnect.
    func rearmVolatileState() async {
        for behavior in behaviors {
            await behavior.rearm()
        }
    }

    /// Reset the HiResScroll target to HID mode (clean shutdown path).
    func resetHiResTarget() async {
        await scrollBehavior?.setTarget(false)
    }

    /// Fire the mic-mute action (UI Test button path).
    func fireMicMute() {
        micMuteBehavior?.fire()
    }

    // MARK: - Refresh Battery

    /// Refresh battery status only. Failures stay out of the load banner.
    func refreshBattery() async {
        guard hasFeature(BatteryFeature.featureId) else { return }
        let errorCount = loadErrors.count
        await CapabilityHandlers.load(.battery, on: self)
        if loadErrors.count > errorCount {
            loadErrors.removeLast(loadErrors.count - errorCount)
        }
    }

    // MARK: - Helpers

    /// Check if the device supports a given feature.
    func hasFeature(_ featureId: UInt16) -> Bool {
        features.contains { $0.featureId == featureId }
    }

    /// Log a summary of the device for debugging.
    func printSummary() {
        logger.info("========================================")
        logger.info("Device: \(self.name, privacy: .public)")
        logger.info("  Index: \(self.deviceIndex, privacy: .public)")
        logger.info("  Type: \(self.deviceKind.description, privacy: .public)")
        logger.info("  Protocol: \(self.protocolMajor, privacy: .public).\(self.protocolMinor, privacy: .public)")
        logger.info("  Descriptor: \(self.descriptor.id, privacy: .public)")
        logger.info("  Features (\(self.features.count, privacy: .public)):")
        for feature in features {
            let knownName = DeviceRegistry.featureName(for: feature.featureId)
            let hidden = feature.isHidden ? " [hidden]" : ""
            logger.info("    [\(feature.index, privacy: .public)] \(String(format: "0x%04X", feature.featureId), privacy: .public)  \(knownName, privacy: .public)\(hidden, privacy: .public)")
        }
        logger.info("========================================")
    }
}
