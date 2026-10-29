import Foundation

/// Stable device identity. HID++ identifies a device by transport, unit id and
/// (when known) serial, so this survives reconnects — unlike a random UUID.
public struct DeviceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public var transport: TransportKind
    public var unitID: UInt8
    public var serial: String?

    public init(transport: TransportKind, unitID: UInt8, serial: String? = nil) {
        self.transport = transport
        self.unitID = unitID
        self.serial = serial
    }

    public var description: String {
        "\(transport.label)/\(unitID)" + (serial.map { "/\($0)" } ?? "")
    }
}
