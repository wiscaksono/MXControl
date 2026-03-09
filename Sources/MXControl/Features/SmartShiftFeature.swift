import Foundation

/// HID++ 2.0 SmartShift with Tunable Torque (0x2111) — scroll wheel mode control.
///
/// SmartShift allows the scroll wheel to auto-switch between ratchet (notched)
/// and free-spin modes based on scroll speed. v2 adds adjustable torque.
///
/// Functions:
///   0: getCapabilities() -> has tunable torque, auto disengage default, max force
///   1: getStatus()       -> current mode, sensitivity, torque, auto disengage
///   2: setStatus()       -> set mode, sensitivity, torque, auto disengage
enum SmartShiftFeature {

    static let featureId: UInt16 = 0x2111

    // MARK: - Scroll Mode

    /// Scroll wheel operating mode.
    enum WheelMode: UInt8, Sendable, CustomStringConvertible {
        case freeSpin = 1     // Free-spinning, no ratchet
        case ratchet = 2      // Ratchet (notched) mode

        var description: String {
            switch self {
            case .freeSpin: return "Free Spin"
            case .ratchet: return "Ratchet"
            }
        }
    }

    // MARK: - Capabilities

    struct Capabilities: Sendable {
        /// Whether the device supports tunable torque.
        let hasTunableTorque: Bool
        /// Default auto-disengage speed threshold.
        let autoDisengageDefault: Int
        /// Default tunable torque value.
        let defaultTunableTorque: Int
        /// Maximum scroll force value.
        let maxForce: Int
    }

    // MARK: - Status

    struct Status: Sendable {
        /// Whether SmartShift auto-switching is active.
        let autoDisengage: Int
        /// Default auto-disengage threshold (0 = SmartShift off).
        let autoDisengageDefault: Int
        /// Current scroll force / torque (1-100).
        let torque: Int
        /// Current wheel mode.
        let wheelMode: WheelMode
    }

    // MARK: - Function 0: GetCapabilities

    /// Get SmartShift capabilities (tunable torque, defaults, max force).
    ///
    /// Response format:
    ///   param[0]: flags (bit 0 = has tunable torque)
    ///   param[1]: auto-disengage default
    ///   param[2]: default tunable torque
    ///   param[3]: max force
    static func getCapabilities(
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
    /// Response format:
    ///   param[0]: wheel mode (1=freespin, 2=ratchet)
    ///   param[1]: auto-disengage value (0=off, 1-255=threshold)
    ///   param[2]: auto-disengage default
    ///   param[3]: torque / scroll force
    static func getStatus(
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

        let params = response.params
        let mode = WheelMode(rawValue: params[0]) ?? .ratchet

        return Status(
            autoDisengage: Int(params[1]),
            autoDisengageDefault: params.count > 2 ? Int(params[2]) : 0,
            torque: params.count > 3 ? Int(params[3]) : 50,
            wheelMode: mode
        )
    }

    // MARK: - Function 2: SetStatus

    /// Set SmartShift configuration.
    ///
    /// - Parameters:
    ///   - wheelMode: Scroll mode (freeSpin or ratchet). Pass nil to keep current.
    ///   - autoDisengage: Auto-disengage threshold (0=off). Pass nil to keep current.
    ///   - torque: Scroll force (1-100). Pass nil to keep current.
    ///
    /// Param format:
    ///   param[0]: wheel mode (0=no change, 1=freespin, 2=ratchet)
    ///   param[1]: auto-disengage (0xFF = no change)
    ///   param[2]: auto-disengage default (0xFF = no change)
    ///   param[3]: torque (0 = no change)
    static func setStatus(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        wheelMode: WheelMode? = nil,
        autoDisengage: Int? = nil,
        torque: Int? = nil
    ) async throws {
        let modeVal = wheelMode?.rawValue ?? 0
        let adVal = autoDisengage.map { UInt8(clamping: $0) } ?? 0xFF
        let torqueVal = torque.map { UInt8(clamping: $0) } ?? 0

        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [modeVal, adVal, 0xFF, torqueVal]
        )
    }
}
