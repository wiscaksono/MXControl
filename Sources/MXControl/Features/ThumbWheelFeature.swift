import Foundation

/// HID++ 2.0 Thumbwheel (0x2150) — thumb wheel sensitivity and inversion.
///
/// Functions:
///   0: getInfo()       -> capabilities, native resolution, diverted mode
///   1: getConfig()     -> current sensitivity, inversion
///   2: setConfig()     -> set sensitivity, inversion
enum ThumbWheelFeature {

    static let featureId: UInt16 = 0x2150

    // MARK: - Info

    struct ThumbWheelInfo: Sendable {
        /// Native resolution (counts per revolution).
        let nativeResolution: Int
        /// Diverted counts per revolution.
        let divertedResolution: Int
        /// Whether direction inversion is supported.
        let supportsInversion: Bool
        /// Whether touch/proximity detection is supported.
        let supportsTouch: Bool
        /// Whether timestamp reporting is supported.
        let supportsTimestamp: Bool
    }

    // MARK: - Config

    struct ThumbWheelConfig: Sendable {
        /// Whether thumb wheel direction is inverted.
        let inverted: Bool
        /// Whether thumb wheel is diverted to software.
        let diverted: Bool
    }

    // MARK: - Function 0: GetInfo

    /// Get thumb wheel capabilities.
    ///
    /// Response:
    ///   param[0..1]: native resolution (big-endian)
    ///   param[2..3]: diverted resolution (big-endian)
    ///   param[4]: capability flags
    static func getInfo(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> ThumbWheelInfo {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        let params = response.params
        let nativeRes = (Int(params[0]) << 8) | Int(params[1])
        let divertedRes = params.count > 3 ? (Int(params[2]) << 8) | Int(params[3]) : nativeRes
        let flags = params.count > 4 ? params[4] : 0

        return ThumbWheelInfo(
            nativeResolution: nativeRes,
            divertedResolution: divertedRes,
            supportsInversion: (flags & 0x04) != 0,
            supportsTouch: (flags & 0x02) != 0,
            supportsTimestamp: (flags & 0x01) != 0
        )
    }

    // MARK: - Function 1: GetConfig

    /// Get current thumb wheel configuration (inversion, divert).
    ///
    /// Response:
    ///   param[0]: flags (bit 0 = inverted, bit 1 = diverted)
    static func getConfig(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> ThumbWheelConfig {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01
        )

        let flags = response.params[0]
        return ThumbWheelConfig(
            inverted: (flags & 0x01) != 0,
            diverted: (flags & 0x02) != 0
        )
    }

    // MARK: - Function 2: SetConfig

    /// Set thumb wheel configuration.
    ///
    /// - Parameters:
    ///   - inverted: Whether to invert direction.
    ///   - diverted: Whether to divert to software.
    static func setConfig(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        inverted: Bool,
        diverted: Bool
    ) async throws {
        var flags: UInt8 = 0
        if inverted { flags |= 0x01 }
        if diverted { flags |= 0x02 }

        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [flags]
        )
    }
}
