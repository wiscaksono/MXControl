import Foundation

/// Everything a scan yields. Kept as one value so a service can hand back a
/// consistent snapshot instead of the UI re-querying mid-update.
public struct DeviceSnapshot: Equatable, Sendable {
    public var devices: [DeviceSummary]
    public var details: [DeviceID: DeviceDetail]
    /// Set when discovery hit a permission or transport problem.
    public var warning: String?

    public init(
        devices: [DeviceSummary] = [],
        details: [DeviceID: DeviceDetail] = [:],
        warning: String? = nil
    ) {
        self.devices = devices
        self.details = details
        self.warning = warning
    }
}

/// Typed value for a setting change heading to hardware.
public enum SettingValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case picker(index: Int)
}

/// One edit the UI wants applied to a device.
public struct DeviceChange: Equatable, Sendable {
    public var deviceID: DeviceID
    public var itemID: String
    public var value: SettingValue

    public init(deviceID: DeviceID, itemID: String, value: SettingValue) {
        self.deviceID = deviceID
        self.itemID = itemID
        self.value = value
    }
}

/// The seam between the UI layer and real hardware. Views never import HID++.
public protocol DeviceService: Sendable {
    func scan() async -> DeviceSnapshot
    /// Fresh state without a discovery round trip.
    func refresh() async -> DeviceSnapshot?
    /// Returns a fresh snapshot after the write, when the service can provide
    /// one. Dummy services return nil.
    func apply(_ change: DeviceChange) async -> DeviceSnapshot?
    /// Drops every saved preference and reloads device defaults.
    func clearSettings() async -> DeviceSnapshot?
}

public extension DeviceService {
    func refresh() async -> DeviceSnapshot? {
        nil
    }

    func apply(_ change: DeviceChange) async -> DeviceSnapshot? {
        nil
    }

    func clearSettings() async -> DeviceSnapshot? {
        nil
    }
}

/// In-memory service backed by the fixture data. Used by the app until the
/// HID++ service lands, and by the snapshot target forever.
public struct DummyDeviceService: DeviceService {
    public init() {}

    public func scan() async -> DeviceSnapshot {
        DeviceSnapshot(devices: DummyData.devices, details: DummyData.details)
    }
}
