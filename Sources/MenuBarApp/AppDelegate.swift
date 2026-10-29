import AppKit
import AppRuntime
import DeviceCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon, no main menu. The status item is the whole UI.
        NSApp.setActivationPolicy(.accessory)

        syncGeneralSettings()
        DeviceCoreRuntime.shared.start()
        MicMuteUI.presenter = MicMuteOverlay.shared
        // Reflect a mic that was already muted before we launched.
        MicMuteUI.presenter?.reflect(muted: DeviceCoreRuntime.shared.isMicMuted)
        menuBar = MenuBarController(model: AppModel.shared)

        Task { @MainActor in
            AppModel.shared.handle(.refresh)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DeviceCoreRuntime.shared.shutdown()
        MicMuteOverlay.shared.hideImmediately()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DeviceCoreRuntime.shared.retryScrollIfNeeded()
    }

    private func syncGeneralSettings() {
        AppModel.shared.syncGeneralToggle(
            "general.launchAtLogin",
            to: SMAppService.mainApp.status == .enabled
        )
    }
}
