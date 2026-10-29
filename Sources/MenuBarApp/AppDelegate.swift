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
        menuBar = MenuBarController(model: AppModel.shared)

        Task { @MainActor in
            AppModel.shared.handle(.refresh)
        }
    }

    private func syncGeneralSettings() {
        AppModel.shared.syncGeneralToggle(
            "general.launchAtLogin",
            to: SMAppService.mainApp.status == .enabled
        )
        AppModel.shared.syncGeneralToggle(
            "general.hideFromDock",
            to: NSApp.activationPolicy() == .accessory
        )
    }
}
