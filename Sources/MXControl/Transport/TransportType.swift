import Foundation

/// The transport through which a device was discovered.
enum TransportType: String, Sendable {
    case usb = "USB"
    case ble = "BLE"
}
