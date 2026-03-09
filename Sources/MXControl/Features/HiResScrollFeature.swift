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
enum HiResScrollFeature {

    static let featureId: UInt16 = 0x2121

    // MARK: - Capabilities

    struct WheelCapability: Sendable {
        /// Hi-res multiplier (e.g., 8 means 8x resolution vs. standard).
        let multiplier: Int
        /// Whether the device supports ratchet/free-spin mode switching.
        let hasRatchet: Bool
        /// Whether inversion is supported.
        let hasInvert: Bool
    }

    // MARK: - Wheel Mode

    struct WheelMode: Sendable {
        /// Whether hi-res scrolling is enabled.
        let hiRes: Bool
        /// Whether scroll direction is inverted (natural scrolling).
        let inverted: Bool
        /// Whether the wheel is in ratchet mode (vs. free-spin).
        /// Only applicable if hasRatchet capability is true.
        let ratchet: Bool
        /// Target reporting: 0 = HID, 1 = HID++
        let target: Bool
    }

    // MARK: - Function 0: GetWheelCapability

    /// Get scroll wheel capabilities.
    ///
    /// Response:
    ///   param[0]: multiplier
    ///   param[1]: capability flags (bit 2 = invert, bit 3 = ratchet switch)
    static func getWheelCapability(
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
            hasRatchet: (flags & 0x08) != 0,
            hasInvert: (flags & 0x04) != 0
        )
    }

    // MARK: - Function 1: GetWheelMode

    /// Get current scroll wheel mode.
    ///
    /// Response:
    ///   param[0]: mode flags (bit 0 = hi-res, bit 2 = invert, bit 3 = ratchet target)
    static func getWheelMode(
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
            hiRes: (flags & 0x01) != 0,
            inverted: (flags & 0x04) != 0,
            ratchet: (flags & 0x02) != 0,
            target: (flags & 0x08) != 0
        )
    }

    // MARK: - Function 2: SetWheelMode

    /// Set scroll wheel mode.
    ///
    /// - Parameters:
    ///   - hiRes: Enable hi-res scrolling.
    ///   - inverted: Enable natural (inverted) scroll direction.
    ///   - ratchet: Enable ratchet mode (vs free-spin).
    ///   - target: Reporting target.
    static func setWheelMode(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        hiRes: Bool,
        inverted: Bool,
        ratchet: Bool = false,
        target: Bool = false
    ) async throws {
        var flags: UInt8 = 0
        if hiRes { flags |= 0x01 }
        if ratchet { flags |= 0x02 }
        if inverted { flags |= 0x04 }
        if target { flags |= 0x08 }

        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [flags]
        )
    }
}
