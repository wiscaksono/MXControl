import AppCore
import DeviceCore
import Foundation

/// Headless diagnostics: `MXControl --status`.
/// Prints one JSON line with the permission gate, onboarding flag, and the
/// settings that decide whether scroll and F9 can work.
enum StatusCheck {
    private struct Report: Codable {
        var app: String
        var version: String
        var accessibility: String
        var inputMonitoring: String
        var bluetooth: String
        var requiredGranted: Bool
        var accessibilityRequested: Bool
        var onboardingFinished: Bool
        var smoothScrollEnabled: Bool?
        var micMuteEnabled: Bool?
    }

    static func run() {
        let permissions = SystemPermissions.current()
        let defaults = UserDefaults.standard

        let report = Report(
            app: "MXControl",
            version: AppVersion.current,
            accessibility: name(permissions.accessibility),
            inputMonitoring: name(permissions.inputMonitoring),
            bluetooth: name(permissions.bluetooth),
            requiredGranted: permissions.requiredGranted,
            accessibilityRequested: defaults.bool(forKey: "accessibilityRequested"),
            onboardingFinished: defaults.bool(forKey: "onboardingFinished"),
            smoothScrollEnabled: defaults.object(
                forKey: "mxcontrol.mx-master-3s.1.smooth_scroll.enabled"
            ) as? Bool,
            micMuteEnabled: defaults.object(
                forKey: "mxcontrol.mx-keys-mini.1.micmute.enabled"
            ) as? Bool
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(report),
            let json = String(data: data, encoding: .utf8)
        else {
            print(#"{"app":"MXControl","status":"error"}"#)
            return
        }
        print(json)
    }

    private static func name(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "granted"
        case .needsRelaunch: "needsRelaunch"
        case .denied: "denied"
        case .unknown: "unknown"
        }
    }
}
