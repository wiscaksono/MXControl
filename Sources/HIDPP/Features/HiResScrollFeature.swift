import Foundation

/// HID++ 2.0 Hi-Res Wheel (0x2121) — hi-resolution scroll wheel settings.
///
/// Functions:
///   0: getWheelCapability() -> multiplier, capabilities
///   1: getWheelMode()       -> current hi-res, invert, target flags
///   2: setWheelMode()       -> set hi-res, invert, target flags
///
/// Events:
///   0: wheelMovement -> hi-res scroll data
public enum HiResScrollFeature {

    public static let featureId: UInt16 = 0x2121

    // MARK: - Capabilities

    public struct WheelCapability: Sendable {
        /// Hi-res multiplier (e.g., 8 means 8x resolution vs. standard).
        public let multiplier: Int
        /// Whether the device has a physical switch for the ratchet mode.
        public let hasSwitch: Bool
        /// Whether inversion is supported.
        public let hasInvert: Bool
        /// Ratchets per full wheel rotation (0 when unreported).
        public let ratchetsPerRotation: Int
        /// Nominal wheel diameter in millimeters (0 when unreported).
        public let wheelDiameter: Int
    }

    // MARK: - Wheel Mode
    //
    // Mode flags byte layout (per HID++ 2.0 / Solaar reference):
    //   bit 0 (0x01) = target   — 0 = HID (OS handles), 1 = HID++ (diverted to software)
    //   bit 1 (0x02) = hiRes    — 0 = low resolution, 1 = high resolution
    //   bit 2 (0x04) = inverted — 0 = normal, 1 = inverted scroll direction

    public struct WheelMode: Sendable {
        /// Target reporting: false = HID (OS handles), true = HID++ (diverted to software).
        public let target: Bool
        /// Whether hi-res scrolling is enabled (sub-notch resolution).
        public let hiRes: Bool
        /// Whether scroll direction is inverted (natural scrolling).
        public let inverted: Bool
    }

    // MARK: - Function 0: GetWheelCapability

    /// Get scroll wheel capabilities.
    ///
    /// Response:
    ///   param[0]: multiplier
    ///   param[1]: capability flags (bit 3 = invert, bit 2 = switch)
    ///   param[2]: ratchets per rotation (0 when unreported)
    ///   param[3]: wheel diameter in mm (0 when unreported)
    public static func getWheelCapability(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> WheelCapability {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        let params = response.params
        let multiplier = Int(params[0])
        let flags = params.count > 1 ? params[1] : 0

        return WheelCapability(
            multiplier: multiplier,
            hasSwitch: (flags & 0x04) != 0,
            hasInvert: (flags & 0x08) != 0,
            ratchetsPerRotation: params.count > 2 ? Int(params[2]) : 0,
            wheelDiameter: params.count > 3 ? Int(params[3]) : 0
        )
    }

    // MARK: - Function 1: GetWheelMode

    /// Get current scroll wheel mode.
    ///
    /// Response:
    ///   param[0]: mode flags (bit 0 = target, bit 1 = hiRes, bit 2 = invert)
    public static func getWheelMode(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> WheelMode {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01
        )

        let flags = response.params[0]
        return WheelMode(
            target: (flags & 0x01) != 0,
            hiRes: (flags & 0x02) != 0,
            inverted: (flags & 0x04) != 0
        )
    }

    // MARK: - Event Parsing

    /// Parsed wheelMovement notification (event 0).
    public struct WheelMovement: Sendable {
        /// Scroll delta in hi-res ticks (positive = up/away, negative = down/toward).
        public let deltaV: Int16
        /// Whether the device is currently in hi-res mode.
        public let hiRes: Bool
        /// Number of reporting periods accumulated in this event.
        public let periods: UInt8
    }

    /// Parse a wheelMovement notification (event 0).
    ///
    /// Byte layout:
    ///   param[0]: flags — bit 4 = hi_res active, bits 0-3 = periods
    ///   param[1..2]: delta_v — signed 16-bit big-endian scroll delta
    public static func parseWheelMovement(params: [UInt8]) -> WheelMovement? {
        guard params.count >= 3 else { return nil }
        let flags = params[0]
        let hiRes = (flags & 0x10) != 0
        let periods = flags & 0x0F
        let deltaV = Int16(bitPattern: (UInt16(params[1]) << 8) | UInt16(params[2]))
        return WheelMovement(deltaV: deltaV, hiRes: hiRes, periods: periods)
    }

    /// Parse a ratchetSwitch notification (event 1).
    ///
    /// Byte layout:
    ///   param[0]: ratchet state — 0 = free-spin, 1 = ratcheted
    ///
    /// Returns `true` if ratcheted, `false` if free-spin.
    public static func parseRatchetSwitch(params: [UInt8]) -> Bool? {
        guard !params.isEmpty else { return nil }
        return params[0] == 1
    }

    // MARK: - Function 2: SetWheelMode

    /// Set scroll wheel mode.
    ///
    /// - Parameters:
    ///   - target: Reporting target — false = HID (OS), true = HID++ (diverted).
    ///   - hiRes: Enable hi-res scrolling (sub-notch resolution).
    ///   - inverted: Enable natural (inverted) scroll direction.
    public static func setWheelMode(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        target: Bool = false,
        hiRes: Bool,
        inverted: Bool
    ) async throws {
        var flags: UInt8 = 0
        if target { flags |= 0x01 }    // bit 0 = target
        if hiRes { flags |= 0x02 }     // bit 1 = resolution
        if inverted { flags |= 0x04 }  // bit 2 = invert

        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [flags]
        )
    }
}
