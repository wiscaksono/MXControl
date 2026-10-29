import Foundation

/// HID++ 2.0 SmartShift Enhanced (0x2111) — scroll wheel mode control.
///
/// Wire format per OpenLogi `0x2111 smartShiftEnhanced` (Logitech HID++ 2.0):
/// getStatus (fn 1) returns exactly 3 bytes `[mode, autoDisengage, torque]`.
/// setStatus (fn 2) sends 3 bytes `[mode, autoDisengage, torque]` where
/// absent fields are encoded as 0 ("do not change").
///
/// Functions:
///   0: getCapabilities() -> tunable torque flag, defaults, max force
///   1: getStatus()       -> current mode, auto-disengage, torque
///   2: setStatus()       -> set mode, auto-disengage, torque
public enum SmartShiftFeature {

    public static let featureId: UInt16 = 0x2111

    // MARK: - Scroll Mode

    /// Scroll wheel operating mode.
    public enum WheelMode: UInt8, Sendable, CustomStringConvertible {
        case freeSpin = 1     // Free-spinning, no ratchet
        case ratchet = 2      // Ratchet (notched) mode

        public var description: String {
            switch self {
            case .freeSpin: return "Free Spin"
            case .ratchet: return "Ratchet"
            }
        }
    }

    // MARK: - Capabilities

    public struct Capabilities: Sendable {
        /// Whether the device supports tunable torque.
        public let hasTunableTorque: Bool
        /// Default auto-disengage speed threshold.
        public let autoDisengageDefault: Int
        /// Default tunable torque value.
        public let defaultTunableTorque: Int
        /// Maximum scroll force value.
        public let maxForce: Int
    }

    // MARK: - Status

    public struct Status: Sendable {
        /// Auto-disengage threshold (0 = off/no-change sentinel on write).
        public let autoDisengage: Int
        /// Current scroll force / torque (1-100).
        public let torque: Int
        /// Current wheel mode.
        public let wheelMode: WheelMode
    }

    // MARK: - Function 0: GetCapabilities

    /// Get SmartShift capabilities (tunable torque, defaults, max force).
    ///
    /// Response format:
    ///   param[0]: flags (bit 0 = has tunable torque)
    ///   param[1]: auto-disengage default
    ///   param[2]: default tunable torque
    ///   param[3]: max force
    public static func getCapabilities(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Capabilities {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        let params = response.params
        guard params.count >= 2 else {
            throw HIDPPError.transportError("Truncated SmartShift capabilities (\(params.count) bytes)")
        }
        return Capabilities(
            hasTunableTorque: (params[0] & 0x01) != 0,
            autoDisengageDefault: Int(params[1]),
            defaultTunableTorque: params.count > 2 ? Int(params[2]) : 50,
            maxForce: params.count > 3 ? Int(params[3]) : 100
        )
    }

    // MARK: - Function 1: GetStatus

    /// Get current SmartShift status.
    ///
    /// Response format (exactly 3 bytes):
    ///   param[0]: wheel mode (1=freespin, 2=ratchet)
    ///   param[1]: auto-disengage threshold
    ///   param[2]: current tunable torque
    public static func getStatus(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Status {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01
        )

        return try parseStatus(params: response.params)
    }

    /// Parse a 3-byte SmartShift status payload (get and set echo share it).
    /// Unknown mode bytes fall back to ratchet (established behavior for
    /// forward-compatibility with future modes).
    static func parseStatus(params: [UInt8]) throws -> Status {
        guard params.count >= 2 else {
            throw HIDPPError.transportError("Truncated SmartShift status (\(params.count) bytes)")
        }
        let mode = WheelMode(rawValue: params[0]) ?? .ratchet
        return Status(
            autoDisengage: Int(params[1]),
            torque: params.count > 2 ? Int(params[2]) : 0,
            wheelMode: mode
        )
    }

    // MARK: - Function 2: SetStatus

    /// Set SmartShift configuration.
    ///
    /// - Parameters:
    ///   - wheelMode: Scroll mode (freeSpin or ratchet). Pass nil to keep current.
    ///   - autoDisengage: Auto-disengage threshold. Pass nil to keep current.
    ///     Note: 0 historically disables SmartShift; the spec reserves 0 as
    ///     "do not change" and 0xFF as permanent ratchet.
    ///   - torque: Scroll force (1-100). Pass nil to keep current.
    ///
    /// Param format (exactly 3 bytes, absent fields encoded as 0):
    ///   param[0]: wheel mode (0=no change, 1=freespin, 2=ratchet)
    ///   param[1]: auto-disengage (0=no change)
    ///   param[2]: torque (0=no change)
    ///
    /// - Returns: The device-echoed resulting status. Callers update UI
    ///   state from the echo so a silently-ignored write cannot desync the UI.
    @discardableResult
    public static func setStatus(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        wheelMode: WheelMode? = nil,
        autoDisengage: Int? = nil,
        torque: Int? = nil
    ) async throws -> Status {
        let modeVal = wheelMode?.rawValue ?? 0
        let adVal = autoDisengage.map { UInt8(clamping: $0) } ?? 0
        let torqueVal = torque.map { UInt8(clamping: $0) } ?? 0

        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [modeVal, adVal, torqueVal]
        )
        return try parseStatus(params: response.params)
    }
}
