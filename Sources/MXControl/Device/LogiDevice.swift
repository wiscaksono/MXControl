import Foundation
import Observation
import os

/// Represents a single Logitech HID++ 2.0 device connected through a transport.
@Observable
class LogiDevice: Identifiable, @unchecked Sendable {

    // MARK: - Identity

    let id = UUID()
    let deviceIndex: UInt8
    let transport: HIDTransport

    // MARK: - Discovered Properties

    var name: String = "Unknown"
    var deviceKind: DeviceNameFeature.DeviceKind = .unknown
    var deviceType: DeviceType = .unknown
    var protocolMajor: UInt8 = 0
    var protocolMinor: UInt8 = 0
    var features: [FeatureSetFeature.FeatureEntry] = []

    // MARK: - Feature Index Cache

    let featureIndexCache = FeatureIndexCache()

    // MARK: - State

    var isInitialized: Bool = false
    var initError: String?

    // MARK: - Init

    init(deviceIndex: UInt8, transport: HIDTransport) {
        self.deviceIndex = deviceIndex
        self.transport = transport
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

    // MARK: - Helpers

    /// Check if the device supports a given feature.
    func hasFeature(_ featureId: UInt16) -> Bool {
        features.contains { $0.featureId == featureId }
    }

    /// Log a summary of the device for debugging.
    func printSummary() {
        logger.info("========================================")
        logger.info("Device: \(self.name)")
        logger.info("  Index: \(self.deviceIndex)")
        logger.info("  Type: \(self.deviceKind.description)")
        logger.info("  Protocol: \(self.protocolMajor).\(self.protocolMinor)")
        logger.info("  Features (\(self.features.count)):")
        for feature in features {
            let knownName = DeviceRegistry.featureName(for: feature.featureId)
            let hidden = feature.isHidden ? " [hidden]" : ""
            logger.info("    [\(feature.index)] \(String(format: "0x%04X", feature.featureId))  \(knownName)\(hidden)")
        }
        logger.info("========================================")
    }
}
