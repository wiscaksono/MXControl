import Testing
import Foundation
@testable import MXControl
@testable import MXControlHIDPP

/// Minimal HIDTransport stub for tests that drive device/behavior logic
/// without performing I/O. For scripted request/response tests, use
/// `MockHIDTransport` in MXControlHIDPPTests instead.
final class StubHIDTransport: HIDTransport, @unchecked Sendable {
    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse {
        HIDPPResponse(
            reportId: .long,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: [UInt8](repeating: 0, count: 16)
        )
    }

    func open() async throws {}
    func close() {}
}

/// Shared fake-device factory.
///
/// Returns a generic `LogiDevice` with stub transport. The fixture holds
/// the device strongly for the test duration — behaviors reference their
/// device as `unowned`, so destructuring away the device will crash.
@MainActor
struct DeviceFixture {
    let device: LogiDevice
    let transport: StubHIDTransport

    /// Make a device with behaviors attached (but not loaded — no I/O).
    static func make(
        descriptor: DeviceDescriptor = DeviceDescriptors.mxKeysMini,
        deviceIndex: UInt8 = 0x01
    ) -> DeviceFixture {
        let transport = StubHIDTransport()
        let device = LogiDevice(
            deviceIndex: deviceIndex,
            transport: transport,
            descriptor: descriptor
        )
        device.attachBehaviors()
        return DeviceFixture(device: device, transport: transport)
    }
}
