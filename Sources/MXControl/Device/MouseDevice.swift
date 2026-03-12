import Foundation
import Observation
import os

/// MX Master 3S mouse — @Observable subclass with all mouse-specific feature state.
///
/// After base discovery (name, features), `loadMouseFeatures()` reads all settings
/// from the device. UI bindings directly mutate properties which trigger writes.
@Observable
final class MouseDevice: LogiDevice, @unchecked Sendable {

    // MARK: - Battery State

    var batteryLevel: Int = 0               // 0-100%
    var batteryCharging: Bool = false
    var batteryStatus: BatteryFeature.ChargingStatus = .discharging

    // MARK: - DPI State

    var currentDPI: Int = 1000
    var defaultDPI: Int = 1000
    var dpiMin: Int = 200
    var dpiMax: Int = 8000
    var dpiStep: Int = 50

    // MARK: - SmartShift State

    var smartShiftActive: Bool = true       // Whether auto-shift is enabled
    var smartShiftAutoDisengage: Int = 50   // Auto-disengage threshold
    var smartShiftTorque: Int = 50          // Scroll force (1-100)
    var smartShiftWheelMode: SmartShiftFeature.WheelMode = .ratchet
    var smartShiftMaxForce: Int = 100

    // MARK: - Hi-Res Scroll State

    var hiResEnabled: Bool = false
    var hiResInverted: Bool = false         // Natural scrolling

    // MARK: - Pointer Speed State

    var pointerSpeed: Int = 256             // 0-511 typical range

    // MARK: - Thumb Wheel State

    var thumbWheelInverted: Bool = false
    var thumbWheelSupportsInversion: Bool = false

    // MARK: - Button State

    var buttons: [SpecialKeysFeature.ControlInfo] = []
    /// Per-button remap targets: CID -> remapped target CID (0 = default).
    var buttonRemaps: [UInt16: UInt16] = [:]

    // MARK: - Gesture Engine

    /// Gesture engine for thumb button (click → Mission Control, drag → workspace switch).
    var gestureEngine: GestureEngine?
    /// Cached SpecialKeys (0x1B04) feature index for notification routing.
    var specialKeysFeatureIndex: UInt8?

    // MARK: - Gesture Settings (adjustable via UI, persisted)

    /// Minimum hold time (seconds) before drag detection starts. Releases within = always click.
    var gestureClickTimeLimit: Double = 0.20 {
        didSet { gestureEngine?.updateConfig(clickTimeLimit: gestureClickTimeLimit) }
    }
    /// Raw HID units of horizontal movement needed to trigger workspace switch.
    var gestureDragThreshold: Int = 200 {
        didSet { gestureEngine?.updateConfig(dragThreshold: gestureDragThreshold) }
    }

    // MARK: - Smooth Scroll Settings (adjustable via UI, persisted)

    /// Whether software smooth scrolling is enabled (intercepts scroll events via CGEventTap).
    var smoothScrollEnabled: Bool = true {
        didSet {
            ScrollInterceptor.shared.isEnabled = smoothScrollEnabled
        }
    }
    /// Scroll speed multiplier (1.0 = normal, 3.0 = default, 10.0 = max).
    var smoothScrollSpeed: Double = 3.0 {
        didSet {
            ScrollInterceptor.shared.speedMultiplier = smoothScrollSpeed
        }
    }
    /// Momentum decay factor (0.80 = short coast, 0.98 = long trackpad-like glide).
    var smoothScrollMomentum: Double = 0.92 {
        didSet {
            ScrollInterceptor.shared.momentumDecay = smoothScrollMomentum
        }
    }

    // MARK: - Host Info

    var currentHostIndex: Int = 0
    var hostCount: Int = 1
    var hosts: [HostsInfoFeature.HostEntry] = []

    // MARK: - Loading State

    var isFeaturesLoaded: Bool = false
    var featureLoadError: String?

    // MARK: - Load All Mouse Features

    /// Read all mouse-specific features from the device.
    /// Call after base `initialize()` completes.
    ///
    /// Each feature is loaded independently so a transient failure on one
    /// (e.g., battery timeout) does not prevent other features from loading.
    func loadMouseFeatures() async {
        var errors: [String] = []

        // Battery (0x1004)
        if hasFeature(BatteryFeature.featureId) {
            do { try await loadBattery() }
            catch { errors.append("Battery: \(error.localizedDescription)"); debugLog("[MouseDevice] Battery load failed: \(error)") }
        }

        // DPI (0x2201)
        if hasFeature(AdjustableDPIFeature.featureId) {
            do { try await loadDPI() }
            catch { errors.append("DPI: \(error.localizedDescription)"); debugLog("[MouseDevice] DPI load failed: \(error)") }
        }

        // SmartShift (0x2111)
        if hasFeature(SmartShiftFeature.featureId) {
            do { try await loadSmartShift() }
            catch { errors.append("SmartShift: \(error.localizedDescription)"); debugLog("[MouseDevice] SmartShift load failed: \(error)") }
        }

        // Hi-Res Scroll (0x2121)
        if hasFeature(HiResScrollFeature.featureId) {
            do { try await loadHiResScroll() }
            catch { errors.append("HiResScroll: \(error.localizedDescription)"); debugLog("[MouseDevice] HiResScroll load failed: \(error)") }
        }

        // Pointer Speed (0x2205)
        if hasFeature(PointerSpeedFeature.featureId) {
            do { try await loadPointerSpeed() }
            catch { errors.append("PointerSpeed: \(error.localizedDescription)"); debugLog("[MouseDevice] PointerSpeed load failed: \(error)") }
        }

        // Thumb Wheel (0x2150)
        if hasFeature(ThumbWheelFeature.featureId) {
            do { try await loadThumbWheel() }
            catch { errors.append("ThumbWheel: \(error.localizedDescription)"); debugLog("[MouseDevice] ThumbWheel load failed: \(error)") }
        }

        // Buttons (0x1B04)
        if hasFeature(SpecialKeysFeature.featureId) {
            do { try await loadButtons() }
            catch { errors.append("Buttons: \(error.localizedDescription)"); debugLog("[MouseDevice] Buttons load failed: \(error)") }
        }

        // Host info (0x1814 + 0x1815)
        if hasFeature(ChangeHostFeature.featureId) {
            do { try await loadHostInfo() }
            catch { errors.append("HostInfo: \(error.localizedDescription)"); debugLog("[MouseDevice] HostInfo load failed: \(error)") }
        }

        isFeaturesLoaded = true
        if errors.isEmpty {
            logger.info("[MouseDevice] All features loaded for \(self.name)")
        } else {
            featureLoadError = errors.joined(separator: "; ")
            logger.warning("[MouseDevice] Loaded with \(errors.count) error(s) for \(self.name): \(errors.joined(separator: "; "))")
        }
    }

    // MARK: - Battery

    private func loadBattery() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: BatteryFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let status = try await BatteryFeature.getStatus(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        batteryLevel = status.level
        batteryCharging = status.chargingStatus.isCharging
        batteryStatus = status.chargingStatus

        logger.info("[MouseDevice] Battery: \(status.level)% \(status.chargingStatus)")
    }

    // MARK: - DPI

    private func loadDPI() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: AdjustableDPIFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        // Get supported DPI range
        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        switch dpiList {
        case .range(let min, let max, let step):
            dpiMin = min
            dpiMax = max
            dpiStep = step
        case .list(let values):
            if let first = values.first, let last = values.last {
                dpiMin = first
                dpiMax = last
                dpiStep = values.count > 1 ? (values[1] - values[0]) : 50
            }
        }

        // Get current DPI
        let dpiInfo = try await AdjustableDPIFeature.getSensorDPI(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        currentDPI = dpiInfo.currentDPI
        defaultDPI = dpiInfo.defaultDPI

        logger.info("[MouseDevice] DPI: \(dpiInfo.currentDPI) (range \(self.dpiMin)-\(self.dpiMax), step \(self.dpiStep))")
    }

    // MARK: - SmartShift

    private func loadSmartShift() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: SmartShiftFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let caps = try await SmartShiftFeature.getCapabilities(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )
        smartShiftMaxForce = caps.maxForce

        let status = try await SmartShiftFeature.getStatus(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        smartShiftWheelMode = status.wheelMode
        smartShiftAutoDisengage = status.autoDisengage
        smartShiftActive = status.autoDisengage > 0
        smartShiftTorque = status.torque

        logger.info("[MouseDevice] SmartShift: mode=\(status.wheelMode) ad=\(status.autoDisengage) torque=\(status.torque)")
    }

    // MARK: - Hi-Res Scroll

    private func loadHiResScroll() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: HiResScrollFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let mode = try await HiResScrollFeature.getWheelMode(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        hiResEnabled = mode.hiRes
        hiResInverted = mode.inverted

        logger.info("[MouseDevice] HiRes: enabled=\(mode.hiRes) inverted=\(mode.inverted)")
    }

    // MARK: - Pointer Speed

    private func loadPointerSpeed() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: PointerSpeedFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        pointerSpeed = try await PointerSpeedFeature.getSpeed(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        logger.info("[MouseDevice] Pointer speed: \(self.pointerSpeed)")
    }

    // MARK: - Thumb Wheel

    private func loadThumbWheel() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: ThumbWheelFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let info = try await ThumbWheelFeature.getInfo(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )
        thumbWheelSupportsInversion = info.supportsInversion

        let config = try await ThumbWheelFeature.getConfig(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )
        thumbWheelInverted = config.inverted

        logger.info("[MouseDevice] Thumb wheel: inverted=\(config.inverted) supportsInversion=\(info.supportsInversion)")
    }

    // MARK: - Buttons

    private func loadButtons() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: SpecialKeysFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        buttons = try await SpecialKeysFeature.enumerateControls(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        // Read current remap state for each button
        for btn in buttons {
            let reporting = try await SpecialKeysFeature.getCtrlIdReporting(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: idx,
                controlId: btn.controlId
            )
            if reporting.remapTarget != 0 {
                buttonRemaps[btn.controlId] = reporting.remapTarget
            }
        }

        // Store feature index for notification routing
        specialKeysFeatureIndex = idx

        logger.info("[MouseDevice] Buttons: \(self.buttons.count) controls, \(self.buttonRemaps.count) remapped")

        // Divert thumb button (CID 0x00C3) for gesture recognition
        await setupThumbButtonGesture(featureIndex: idx)
    }

    /// Divert the thumb/gesture button (CID 0x00C3) and set up the gesture engine.
    private func setupThumbButtonGesture(featureIndex: UInt8) async {
        let thumbCID: UInt16 = SpecialKeysFeature.KnownCID.gestureButton.rawValue  // 0x00C3 = 195

        // Find the thumb button in our controls list
        guard let thumbButton = buttons.first(where: { $0.controlId == thumbCID }) else {
            logger.info("[MouseDevice] Thumb button CID 0x\(String(format: "%04X", thumbCID)) not found in controls")
            return
        }

        guard thumbButton.isDivertable else {
            logger.info("[MouseDevice] Thumb button is not divertable")
            return
        }

        // Request accessibility permission for CGEvent posting
        MacActions.requestAccessibilityPermission()

        // Divert the thumb button with rawXY enabled
        do {
            let hasRawXY = thumbButton.flags.contains(.rawXY)
            let canPersist = thumbButton.flags.contains(.persistDivert)
            try await SpecialKeysFeature.setCtrlIdReporting(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                controlId: thumbCID,
                divert: true,
                persistDivert: canPersist,
                rawXY: hasRawXY
            )

            // Create the gesture engine and sync current settings
            let engine = GestureEngine(thumbCID: thumbCID)
            engine.updateConfig(clickTimeLimit: gestureClickTimeLimit, dragThreshold: gestureDragThreshold)
            gestureEngine = engine
            logger.info("[MouseDevice] Thumb button diverted (rawXY=\(hasRawXY) persist=\(canPersist)), gesture engine active")
            debugLog("[MouseDevice] Thumb button diverted (rawXY=\(hasRawXY) persist=\(canPersist)), gesture engine active")

        } catch {
            logger.error("[MouseDevice] Failed to divert thumb button: \(error.localizedDescription)")
            debugLog("[MouseDevice] Failed to divert thumb button: \(error)")
        }
    }

    // MARK: - Host Info

    private func loadHostInfo() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: ChangeHostFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let hostInfo = try await ChangeHostFeature.getHostInfo(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        hostCount = hostInfo.hostCount
        currentHostIndex = hostInfo.currentHost

        if hasFeature(HostsInfoFeature.featureId) {
            let hostsIdx = try await featureIndexCache.resolve(
                featureId: HostsInfoFeature.featureId,
                transport: transport,
                deviceIndex: deviceIndex
            )

            hosts = try await HostsInfoFeature.enumerateHosts(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: hostsIdx
            )
        }

        logger.info("[MouseDevice] Host: \(hostInfo.currentHost + 1)/\(hostInfo.hostCount)")
    }

    // MARK: - Write: Set DPI

    /// Write a new DPI value to the device.
    func setDPI(_ dpi: Int) async throws {
        let clamped = max(dpiMin, min(dpiMax, dpi))
        let snapped = (clamped / dpiStep) * dpiStep

        let idx = try await featureIndexCache.resolve(
            featureId: AdjustableDPIFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await AdjustableDPIFeature.setSensorDPI(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            dpi: snapped
        )

        currentDPI = snapped
        logger.info("[MouseDevice] DPI set to \(snapped)")
    }

    // MARK: - Write: Set SmartShift

    /// Write SmartShift configuration to the device.
    func setSmartShift(
        wheelMode: SmartShiftFeature.WheelMode? = nil,
        autoDisengage: Int? = nil,
        torque: Int? = nil
    ) async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: SmartShiftFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await SmartShiftFeature.setStatus(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            wheelMode: wheelMode,
            autoDisengage: autoDisengage,
            torque: torque
        )

        if let mode = wheelMode { smartShiftWheelMode = mode }
        if let ad = autoDisengage { smartShiftAutoDisengage = ad; smartShiftActive = ad > 0 }
        if let t = torque { smartShiftTorque = t }

        logger.info("[MouseDevice] SmartShift updated: mode=\(self.smartShiftWheelMode) ad=\(self.smartShiftAutoDisengage) torque=\(self.smartShiftTorque)")
    }

    // MARK: - Write: Set Hi-Res Scroll

    /// Write hi-res scroll settings to device.
    func setHiResScroll(hiRes: Bool, inverted: Bool) async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: HiResScrollFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await HiResScrollFeature.setWheelMode(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            hiRes: hiRes,
            inverted: inverted
        )

        hiResEnabled = hiRes
        hiResInverted = inverted
        logger.info("[MouseDevice] HiRes set: enabled=\(hiRes) inverted=\(inverted)")
    }

    // MARK: - Write: Set Pointer Speed

    /// Write pointer speed to device.
    func setPointerSpeed(_ speed: Int) async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: PointerSpeedFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await PointerSpeedFeature.setSpeed(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            speed: speed
        )

        pointerSpeed = speed
        logger.info("[MouseDevice] Pointer speed set to \(speed)")
    }

    // MARK: - Write: Set Thumb Wheel

    /// Write thumb wheel inversion setting to device.
    func setThumbWheelInverted(_ inverted: Bool) async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: ThumbWheelFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await ThumbWheelFeature.setConfig(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            inverted: inverted,
            diverted: false
        )

        thumbWheelInverted = inverted
        logger.info("[MouseDevice] Thumb wheel inverted: \(inverted)")
    }

    // MARK: - Write: Remap Button

    /// Remap a button to a different action.
    func remapButton(controlId: UInt16, to target: UInt16) async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: SpecialKeysFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            controlId: controlId,
            remapTarget: target
        )

        if target == 0 {
            buttonRemaps.removeValue(forKey: controlId)
        } else {
            buttonRemaps[controlId] = target
        }

        logger.info("[MouseDevice] Button CID \(controlId) remapped to \(target)")
    }

    // MARK: - Notification Handling

    /// Handle an unsolicited HID++ notification from the device.
    /// Called by DeviceManager when the transport receives an unmatched packet for this device.
    ///
    /// - Parameters:
    ///   - featureIndex: The feature index the notification came from.
    ///   - functionId: The function/event ID within the feature.
    ///   - params: The notification payload bytes.
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        debugLog("[MouseDevice] handleNotification: feat=\(String(format: "0x%02X", featureIndex)) func=\(functionId) engine=\(gestureEngine != nil) skIdx=\(specialKeysFeatureIndex.map { String(format: "0x%02X", $0) } ?? "nil")")
        guard let engine = gestureEngine, let skIdx = specialKeysFeatureIndex else {
            debugLog("[MouseDevice] handleNotification: SKIPPED (engine=\(gestureEngine != nil) skIdx=\(specialKeysFeatureIndex != nil))")
            return
        }

        // Only handle SpecialKeys (0x1B04) notifications
        guard featureIndex == skIdx else { return }

        switch functionId {
        case 0x00:
            // Event 0: divertedButtonsEvent — button press/release
            let pressedCIDs = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
            debugLog("[MouseDevice] divertedButtonsEvent: \(pressedCIDs.map { String(format: "0x%04X", $0) })")
            engine.handleButtonEvent(pressedCIDs: pressedCIDs)

        case 0x01:
            // Event 1: rawXY — mouse movement while diverted button is held
            let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
            engine.handleRawXY(deltaX: dx, deltaY: dy)

        default:
            break
        }
    }

    // MARK: - Refresh Battery

    /// Refresh battery status only.
    func refreshBattery() async {
        do {
            try await loadBattery()
        } catch {
            logger.warning("[MouseDevice] Battery refresh failed: \(error.localizedDescription)")
        }
    }
}
