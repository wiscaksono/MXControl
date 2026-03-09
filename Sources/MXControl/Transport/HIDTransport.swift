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

    /// Send a HID++ request with automatic retry for transient errors (.timeout, .busy, .hardwareError).
    ///
    /// Non-transient errors are thrown immediately without retry. Retries use linear backoff
    /// (100ms * attempt number) to give the device time to become available.
    func sendWithRetry(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8] = [],
        maxAttempts: Int = 3,
        retryDelay: Duration = .milliseconds(100)
    ) async throws -> HIDPPResponse {
        let attempts = max(1, maxAttempts)
        var lastError: (any Error)?
        for attempt in 1...attempts {
            do {
                return try await send(
                    deviceIndex: deviceIndex,
                    featureIndex: featureIndex,
                    functionId: functionId,
                    softwareId: softwareId,
                    params: params
                )
            } catch let error as HIDPPError where error.isTransient {
                lastError = error
                debugLog("[HIDTransport] Transient error on attempt \(attempt)/\(attempts): \(error.localizedDescription)")
                if attempt < attempts {
                    try await Task.sleep(for: retryDelay * attempt)
                }
            }
        }
        throw lastError ?? HIDPPError.transportError("All \(attempts) retry attempts exhausted")
    }
}
