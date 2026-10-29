import Foundation

/// Everything a scan yields. Kept as one value so a service can hand back a
/// consistent snapshot instead of the UI re-querying mid-update.
public struct DeviceSnapshot: Equatable, Sendable {
    public var devices: [DeviceSummary]
    public var details: [DeviceID: DeviceDetail]

    public init(devices: [DeviceSummary] = [], details: [DeviceID: DeviceDetail] = [:]) {
        self.devices = devices
        self.details = details
    }
}

/// The seam between the UI layer and real hardware. Views never import HID++.
public protocol DeviceService: Sendable {
    func scan() async -> DeviceSnapshot
}

/// In-memory service backed by the fixture data. Used by the app until the
/// HID++ service lands, and by the snapshot target forever.
public struct DummyDeviceService: DeviceService {
    public init() {}

    public func scan() async -> DeviceSnapshot {
        DeviceSnapshot(devices: DummyData.devices, details: DummyData.details)
    }
}
