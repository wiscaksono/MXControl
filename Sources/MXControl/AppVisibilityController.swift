import MXControlHIDPP
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

    private init() {
        MemoryMonitor.shared.start()
    }
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
        // Retry pending event-tap starts: the user may have granted
        // Accessibility after an earlier failed start while enabled stayed on.
        F9KeyMonitor.shared.retryIfNeeded()
        ScrollInterceptor.shared.retryIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reset HiResScroll target to HID mode so the scroll wheel works via macOS
        // after the app exits. The target flag is volatile (resets on device reconnect),
        // but we reset explicitly for clean shutdown.
        //
        // We pump the main RunLoop instead of blocking with a semaphore — the reset
        // calls @MainActor-isolated methods, so blocking the main thread would deadlock.
        let resetDone = DispatchGroup()
        resetDone.enter()
        Task.detached {
            await AppRuntime.shared.deviceManager.resetScrollTargetForAllDevices()
            resetDone.leave()
        }
        let deadline = Date(timeIntervalSinceNow: 2.0)
        while resetDone.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        ScrollInterceptor.shared.stop()
        F9KeyMonitor.shared.stop()
        MicMuteEngine.shared.stopDeviceMonitoring()
        Task { @MainActor in
            // Synchronous order-out: the animated fade is best-effort here
            // and may not complete before the process exits.
            MicMuteOverlay.shared.hideImmediately()
        }
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
