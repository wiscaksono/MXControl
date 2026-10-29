import Foundation

/// HID++ 2.0 SmartShift v1 (0x2110) — original scroll wheel mode control.
///
/// Wire format per OpenLogi `0x2110 smartShift` (Logitech HID++ 2.0):
/// getStatus (fn 0) returns `[mode, autoDisengage, autoDisengageDefault]`.
/// setStatus (fn 1) sends `[mode, autoDisengage, autoDisengageDefault]`
/// with absent fields encoded as 0 ("do not change").
///
/// Wheel modes are shared with `SmartShiftFeature.WheelMode` (1/2).
///
/// Functions:
///   0: getStatus() -> current mode, auto-disengage, factory default
///   1: setStatus() -> set mode, auto-disengage, factory default
public enum SmartShiftV1Feature {

    public static let featureId: UInt16 = 0x2110

    // MARK: - Status

    public struct Status: Sendable {
        /// Current wheel mode.
        public let wheelMode: SmartShiftFeature.WheelMode
        /// Auto-disengage threshold (0xFF = permanent ratchet).
        public let autoDisengage: Int
        /// Factory-default threshold.
        public let autoDisengageDefault: Int
    }

    // MARK: - Function 0: GetStatus

    /// Get current SmartShift v1 status.
    ///
    /// Response format:
    ///   param[0]: wheel mode (1=freespin, 2=ratchet)
    ///   param[1]: auto-disengage threshold
    ///   param[2]: factory-default threshold
    public static func getStatus(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Status {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        let params = response.params
        guard params.count >= 1 else {
            throw HIDPPError.transportError("Truncated SmartShift v1 status (\(params.count) bytes)")
        }
        let mode = SmartShiftFeature.WheelMode(rawValue: params[0]) ?? .ratchet

        return Status(
            wheelMode: mode,
            autoDisengage: params.count > 1 ? Int(params[1]) : 0,
            autoDisengageDefault: params.count > 2 ? Int(params[2]) : 0
        )
    }

    // MARK: - Function 1: SetStatus

    /// Set SmartShift v1 configuration.
    ///
    /// - Parameters:
    ///   - wheelMode: Scroll mode. Pass nil to keep current.
    ///   - autoDisengage: Threshold (0 historically disables). Pass nil to keep current.
    ///   - autoDisengageDefault: Factory default slot. Pass nil to keep current.
    ///
    /// Param format (absent fields encoded as 0 = no change):
    ///   param[0]: wheel mode (0=no change, 1=freespin, 2=ratchet)
    ///   param[1]: auto-disengage
    ///   param[2]: factory default
    ///
    /// - Returns: The device-echoed resulting status. Callers update UI
    ///   state from the echo so a silently-ignored write cannot desync the UI.
    @discardableResult
    public static func setStatus(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        wheelMode: SmartShiftFeature.WheelMode? = nil,
        autoDisengage: Int? = nil,
        autoDisengageDefault: Int? = nil
    ) async throws -> Status {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [
                wheelMode?.rawValue ?? 0,
                autoDisengage.map { UInt8(clamping: $0) } ?? 0,
                autoDisengageDefault.map { UInt8(clamping: $0) } ?? 0,
            ]
        )
        let params = response.params
        guard params.count >= 1 else {
            throw HIDPPError.transportError("Truncated SmartShift v1 echo (\(params.count) bytes)")
        }
        let mode = SmartShiftFeature.WheelMode(rawValue: params[0]) ?? .ratchet
        return Status(
            wheelMode: mode,
            autoDisengage: params.count > 1 ? Int(params[1]) : 0,
            autoDisengageDefault: params.count > 2 ? Int(params[2]) : 0
        )
    }
}
