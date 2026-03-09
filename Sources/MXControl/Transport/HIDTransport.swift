import Foundation

/// Protocol for sending/receiving HID++ packets to Logitech devices.
///
/// Implementations: USBTransport (IOKit HID for USB+BLE), DeviceTransportAdapter (per-device wrapper).
protocol HIDTransport: Sendable {
    /// Send a HID++ request and wait for the matching response.
    ///
    /// - Parameters:
    ///   - deviceIndex: Device index (1-6 for receiver sub-devices, 0xFF for receiver).
    ///   - featureIndex: Feature index on the device (from Root feature discovery).
    ///   - functionId: Function ID within the feature (0-15).
    ///   - softwareId: Software ID for response matching (1-15).
    ///   - params: Parameter bytes (auto-selects report type based on length).
    /// - Returns: The matching HID++ response.
    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse

    /// Open the transport and begin device communication.
    func open() async throws

    /// Close the transport and release resources.
    func close()
}

extension HIDTransport {
    /// Convenience: send with empty params.
    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8
    ) async throws -> HIDPPResponse {
        try await send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: []
        )
    }
}
