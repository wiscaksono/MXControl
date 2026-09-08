import Foundation
import MXControlHIDPP

/// A service-wiring unit attached to a generic `LogiDevice`.
///
/// Subclasses used to embed scroll interception, gesture diversion, and
/// mic-mute handling directly in device state. Behaviors extract exactly
/// that: volatile HID++ setup (diverts, notify targets), unsolicited
/// notification handling, and external service sync. Scalar settings live
/// in capability states and are loaded/committed by `CapabilityHandlers`.
///
/// Ownership invariant: the device owns its behaviors and always outlives
/// them, so behaviors may reference the device as `unowned`. Never retain
/// a behavior beyond its device.
@MainActor
protocol DeviceBehavior: AnyObject {
    /// Read device state and arm volatile wiring (diverts, targets).
    func load() async
    /// Handle an unsolicited HID++ notification already routed to our device.
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8])
    /// Re-arm volatile wiring after a BLE reconnection.
    func rearm() async
    /// HiResScroll feature index for fast-path scroll routing. Nil by default.
    var hiResScrollFeatureIndex: UInt8? { get }
}

extension DeviceBehavior {
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {}
    func rearm() async {}
    var hiResScrollFeatureIndex: UInt8? { nil }
}
