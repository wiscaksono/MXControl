import AppCore
import ApplicationServices
import CoreBluetooth
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
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .bluetooth:
            // No direct prompt API; CoreBluetooth asks when discovery starts.
            break
        }
    }

    private static var inputMonitoring: PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
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
