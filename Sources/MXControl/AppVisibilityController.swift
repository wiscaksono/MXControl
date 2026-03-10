import AppKit

enum AppVisibilityPreferences {
    static let hideFromDockKey = "hideFromDock"
    static let defaultHideFromDock = false

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [hideFromDockKey: defaultHideFromDock])
    }

    static func hideFromDock(using defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hideFromDockKey)
    }

    static func setHideFromDock(_ hidden: Bool, using defaults: UserDefaults = .standard) {
        defaults.set(hidden, forKey: hideFromDockKey)
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let deviceManager = DeviceManager()

    private init() {}
}

@MainActor
final class AppVisibilityController: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppVisibilityPreferences.registerDefaults(defaults)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hidden mode is session-only so a fresh app launch always restores the menu bar icon.
        restoreMenuBarIconIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        restoreMenuBarIconIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreMenuBarIconIfNeeded()
        return false
    }

    private func restoreMenuBarIconIfNeeded() {
        guard AppVisibilityPreferences.hideFromDock(using: defaults) else { return }
        AppVisibilityPreferences.setHideFromDock(false, using: defaults)
        logger.info("[App] Restored menu bar icon")
    }
}
