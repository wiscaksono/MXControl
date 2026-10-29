import AppCore
import ApplicationServices
import CoreBluetooth
import CoreGraphics
import Foundation
import IOKit.hid

/// Real permission probes. Nothing here prompts until the user asks for a
/// specific permission.
public struct SystemPermissions: PermissionsService {
    public init() {}

    public func status() async -> PermissionState {
        PermissionState(
            inputMonitoring: Self.inputMonitoring,
            accessibility: Self.accessibility,
            bluetooth: Self.bluetooth
        )
    }

    public func request(_ kind: PermissionKind) async {
        switch kind {
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .accessibility:
            // Registers the app in the Accessibility list as a side effect.
            // Without this call a fresh install may not appear there at all.
            UserDefaults.standard.set(true, forKey: Self.accessibilityRequestedKey)
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .bluetooth:
            await MainActor.run {
                BluetoothPrompter.shared.prompt()
            }
        }
    }

    private static let accessibilityRequestedKey = "accessibilityRequested"

    private static var accessibility: PermissionStatus {
        if AXIsProcessTrusted() { return .granted }
        // AX trust is live, so this only distinguishes "never asked" from
        // "asked and denied". It lets the first step show Enable instead of
        // sending the user to a Settings list the app has not joined yet.
        return UserDefaults.standard.bool(forKey: accessibilityRequestedKey) ? .denied : .unknown
    }

    private static var inputMonitoring: PermissionStatus {
        // A TCC grant only takes effect for a process that starts afterwards.
        // IOHIDCheckAccess is the process-level truth; CGPreflight is the TCC
        // record. Both must agree before we call this granted.
        let effective = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch effective {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            // TCC has the grant but this process still cannot listen.
            return CGPreflightListenEventAccess() ? .needsRelaunch : .denied
        default:
            return CGPreflightListenEventAccess() ? .needsRelaunch : .unknown
        }
    }

    private static var bluetooth: PermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }
}


/// CoreBluetooth only shows its prompt when a central manager is created, so
/// the Bluetooth step asks through this short-lived manager instead of waiting
/// for the device scanner to start.
@MainActor
private final class BluetoothPrompter: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothPrompter()

    private var manager: CBCentralManager?

    func prompt() {
        guard manager == nil else { return }
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}
