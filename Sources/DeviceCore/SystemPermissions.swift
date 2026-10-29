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
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            bluetooth: Self.bluetooth
        )
    }

    public func request(_ kind: PermissionKind) async {
        switch kind {
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .bluetooth:
            await MainActor.run {
                BluetoothPrompter.shared.prompt()
            }
        }
    }

    private static var inputMonitoring: PermissionStatus {
        // CGPreflight updates as soon as TCC records the grant; IOHIDCheckAccess
        // can stay denied until the process restarts, so it only refines the
        // "never asked" case.
        if CGPreflightListenEventAccess() {
            return .granted
        }
        return switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
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
