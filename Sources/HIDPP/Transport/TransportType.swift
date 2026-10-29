import Foundation

/// The transport through which a device was discovered.
public enum TransportType: String, Sendable {
    case usb = "USB"
    case ble = "BLE"
}
