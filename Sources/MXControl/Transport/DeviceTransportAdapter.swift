import Foundation

/// A thin adapter that routes HIDTransport calls to a specific device on the shared IOKit transport.
///
/// Each LogiDevice holds an `HIDTransport` reference. For USB receiver sub-devices, the adapter
/// routes to the receiver's IOHIDDevice. For BLE direct devices, it routes to that device's
/// specific IOHIDDevice — all going through the same underlying `USBTransport` (IOHIDManager).
final class DeviceTransportAdapter: HIDTransport, @unchecked Sendable {

    private let transport: USBTransport
    let targetDeviceUID: String

    init(transport: USBTransport, targetDeviceUID: String) {
        self.transport = transport
        self.targetDeviceUID = targetDeviceUID
    }

    func open() async throws {
        // No-op — the shared USBTransport is already open
    }

    func close() {
        // No-op — the shared USBTransport manages device lifecycle
    }

    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse {
        try await transport.sendTo(
            targetDeviceUID: targetDeviceUID,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: params
        )
    }

    /// Send with timeout, delegating to the shared transport.
    func sendWithTimeout(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        params: [UInt8] = [],
        timeout: TimeInterval? = nil
    ) async throws -> HIDPPResponse {
        try await transport.sendWithTimeout(
            targetDeviceUID: targetDeviceUID,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            params: params,
            timeout: timeout
        )
    }
}
