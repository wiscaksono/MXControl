import AppKit
import AppRuntime
import DeviceCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon, no main menu. The status item is the whole UI.
        NSApp.setActivationPolicy(.accessory)

        DeviceCoreRuntime.shared.start()
        menuBar = MenuBarController(model: AppModel.shared)

        Task { @MainActor in
            AppModel.shared.handle(.refresh)
        }
    }
}
