import Foundation

/// HID++ 2.0 Thumbwheel (0x2150) — horizontal thumb wheel on MX-line mice.
///
/// Wire format per OpenLogi `0x2150 thumbwheel` (Logitech HID++ 2.0 spec):
///
/// Functions:
///   0: getInfo()             -> resolutions, direction, capabilities, time unit
///   1: getConfig()           -> reporting mode + direction flags
///   2: setConfig(mode, inv)  -> reporting mode + direction inversion
public enum ThumbWheelFeature {

    public static let featureId: UInt16 = 0x2150

    // MARK: - Reporting Mode

    /// How thumbwheel events are reported.
    public enum ReportingMode: UInt8, Sendable {
        /// Events go to the native HID channel (normal scrolling).
        case native = 0
        /// Events go to the diverted HID++ channel (requires a listener).
        case diverted = 1
    }

    // MARK: - Info

    public struct ThumbWheelInfo: Sendable {
        /// Native resolution (counts per revolution).
        public let nativeResolution: Int
        /// Diverted counts per revolution.
        public let divertedResolution: Int
        /// Whether direction inversion is supported.
        ///
        /// The spec exposes no capability bit for inversion — direction is
        /// always settable via `setConfig` — so this is always true.
        public let supportsInversion: Bool
        /// Whether touch detection is supported.
        public let supportsTouch: Bool
        /// Whether timestamp reporting is supported.
        public let supportsTimestamp: Bool
        /// Whether proximity detection is supported.
        public let supportsProxy: Bool
        /// Whether single-tap detection is supported.
        public let supportsSingleTap: Bool
        /// Timestamp unit in microseconds (0 when unsupported).
        public let timeUnit: Int
    }

    // MARK: - Config

    public struct ThumbWheelConfig: Sendable {
        /// Whether thumb wheel direction is inverted.
        public let inverted: Bool
        /// Whether thumb wheel events are diverted to software.
        public let diverted: Bool
    }

    // MARK: - Function 0: GetInfo

    /// Get thumb wheel capabilities.
    ///
    /// Response:
    ///   param[0..1]: native resolution (big-endian)
    ///   param[2..3]: diverted resolution (big-endian)
    ///   param[4]: default direction, bit 0 only
    ///   param[5]: capabilities (bit 0 = timestamp, 1 = touch, 2 = proxy, 3 = single tap)
    ///   param[6..7]: time unit microseconds (big-endian, 0 when unsupported)
    public static func getInfo(
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
        let caps = params.count > 5 ? params[5] : 0
        let timeUnit = params.count > 7 ? (Int(params[6]) << 8) | Int(params[7]) : 0

        return ThumbWheelInfo(
            nativeResolution: nativeRes,
            divertedResolution: divertedRes,
            supportsInversion: true,
            supportsTouch: (caps & 0x02) != 0,
            supportsTimestamp: (caps & 0x01) != 0,
            supportsProxy: (caps & 0x04) != 0,
            supportsSingleTap: (caps & 0x08) != 0,
            timeUnit: timeUnit
        )
    }

    // MARK: - Function 1: GetConfig

    /// Get current thumb wheel configuration.
    ///
    /// Response:
    ///   param[0]: reporting mode (0 = native, 1 = diverted)
    ///   param[1]: flags (bit 0 = inverted, 1 = touch, 2 = proxy)
    public static func getConfig(
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

        let params = response.params
        let mode = params.count > 0 ? params[0] : 0
        let flags = params.count > 1 ? params[1] : 0
        return ThumbWheelConfig(
            inverted: (flags & 0x01) != 0,
            diverted: mode == ReportingMode.diverted.rawValue
        )
    }

    // MARK: - Function 2: SetConfig

    /// Set thumb wheel configuration.
    ///
    /// Request: `[mode, invert, 0x00]` where mode is 0 (native) or
    /// 1 (diverted) and invert is 0/1.
    ///
    /// - Parameters:
    ///   - inverted: Whether to invert direction.
    ///   - diverted: Whether to divert events to software. Keep false unless
    ///     a listener consumes the events — a diverted wheel with no listener
    ///     produces no scrolling at all.
    public static func setConfig(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        inverted: Bool,
        diverted: Bool = false
    ) async throws {
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [
                diverted ? ReportingMode.diverted.rawValue : ReportingMode.native.rawValue,
                inverted ? 0x01 : 0x00,
                0x00,
            ]
        )
    }
}
