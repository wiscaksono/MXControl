import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon, no main menu. The status item is the whole UI.
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(model: AppModel.shared)
    }
}
