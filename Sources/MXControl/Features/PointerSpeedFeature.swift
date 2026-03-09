import Foundation

/// HID++ 2.0 Pointer Motion Scaling (0x2205) — pointer speed/acceleration.
///
/// Functions:
///   0: getSpeed()  -> current pointer speed value
///   1: setSpeed()  -> set pointer speed value
enum PointerSpeedFeature {

    static let featureId: UInt16 = 0x2205

    // MARK: - Function 0: GetSpeed

    /// Get current pointer speed value.
    ///
    /// Response: param[0..1] = speed value (big-endian, 16-bit).
    /// Typical range: 0x0000 to 0x01FF (0-511), default varies by device.
    static func getSpeed(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Int {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return (Int(response.params[0]) << 8) | Int(response.params[1])
    }

    // MARK: - Function 1: SetSpeed

    /// Set pointer speed value.
    ///
    /// - Parameter speed: Speed value (typically 0-511).
    static func setSpeed(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        speed: Int
    ) async throws {
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [
                UInt8((speed >> 8) & 0xFF),
                UInt8(speed & 0xFF),
            ]
        )
    }
}
