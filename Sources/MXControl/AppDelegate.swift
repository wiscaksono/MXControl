import AppKit
import AppRuntime
import DeviceCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var signalSources: [DispatchSourceSignal] = []
    private var isCleaningUp = false
    private var didCleanUp = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon, no main menu. The status item is the whole UI.
        NSApp.setActivationPolicy(.accessory)
        installTerminationHandlers()

        syncGeneralSettings()
        DeviceCoreRuntime.shared.start()
        MicMuteUI.presenter = MicMuteOverlay.shared
        // Reflect a mic that was already muted before we launched.
        MicMuteUI.presenter?.reflect(muted: DeviceCoreRuntime.shared.isMicMuted)
        menuBar = MenuBarController(model: AppModel.shared)

        Task { @MainActor in
            await AppModel.shared.start()
        }
    }

    /// The scroll wheel is diverted to HID++ while Smooth Scroll is on, so a
    /// hard exit leaves macOS without wheel input. Cleanup has to await the
    /// HID++ write before the process goes away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCleanUp else { return .terminateNow }
        guard !isCleaningUp else { return .terminateLater }
        isCleaningUp = true

        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await DeviceCoreRuntime.shared.shutdown() }
                group.addTask { try? await Task.sleep(for: .milliseconds(1500)) }
                await group.next()
                group.cancelAll()
            }
            didCleanUp = true
            isCleaningUp = false
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Last resort when the async path timed out.
        MicMuteOverlay.shared.hideImmediately()
    }

    /// `make stop` and `kill` send SIGTERM. Turn those into the normal AppKit
    /// termination path so the scroll cleanup still runs.
    private func installTerminationHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Launching the app again while it runs (Finder, Spotlight, `open -a`)
    /// lands here. That is the way back from a hidden menu bar icon.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        menuBar?.revealMenuBarIcon()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Covers the case where the app is already active when it is reopened.
        menuBar?.revealMenuBarIcon()
        DeviceCoreRuntime.shared.retryScrollIfNeeded()
        // Returning from System Settings should update the checkmarks at once.
        Task { @MainActor in
            await AppModel.shared.refreshPermissions()
        }
    }

    private func syncGeneralSettings() {
        AppModel.shared.syncGeneralToggle(
            "general.launchAtLogin",
            to: SMAppService.mainApp.status == .enabled
        )
    }
}
