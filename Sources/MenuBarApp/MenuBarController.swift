import AppCore
import AppKit
import AppRuntime
import DeviceCore
import MenuBarUI
import ServiceManagement
import SwiftUI

final class MenuBarController: NSObject {
    private let model: AppModel
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hostingController: NSHostingController<PopoverHost>?

    init(model: AppModel) {
        self.model = model
        super.init()
        configureStatusItem()
        configurePopover()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = BrandIcon.menuBar
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(
            width: PopoverView.preferredWidth,
            height: PopoverView.chromeHeight + PopoverSizing.fallbackViewport
        )

        let host = NSHostingController(rootView: makeRoot())
        hostingController = host
        popover.contentViewController = host
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        // The user may have just granted Accessibility; a failed tap start can
        // recover without relaunching.
        DeviceCoreRuntime.shared.retryScrollIfNeeded()
        // Rebuild so the viewport cap comes from the screen holding the item.
        hostingController?.rootView = makeRoot()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func makeRoot() -> PopoverHost {
        PopoverHost(
            model: model,
            maxContentHeight: maxViewportHeight,
            onAction: { [weak self] action in self?.handle(action) },
            onHeightChange: { [weak self] height in self?.resize(to: height) }
        )
    }

    /// `NSScreen.main` follows the key window, which is not necessarily the
    /// display whose menu bar holds the status item.
    private var maxViewportHeight: CGFloat {
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        return PopoverSizing.maxViewport(screenHeight: screen?.visibleFrame.height ?? 900)
    }

    /// NSPopover re-anchors itself when `contentSize` changes, so changing
    /// screens grows and shrinks it without the panel drifting off the item.
    private func resize(to height: CGFloat) {
        guard height > 1 else { return }
        let size = NSSize(width: PopoverView.preferredWidth, height: height)
        guard abs(popover.contentSize.height - size.height) > 0.5 else { return }

        // Called from SwiftUI's layout pass; resizing inline re-enters layout.
        Task { @MainActor in
            guard abs(self.popover.contentSize.height - size.height) > 0.5 else { return }
            self.popover.contentSize = size
        }
    }

    private func handle(_ action: UIAction) {
        switch action {
        case .quit:
            NSApp.terminate(nil)
        case .openPermissionSettings:
            openPermissionSettings()
        case let .activate(itemID) where itemID == "general.reset":
            confirmReset()
        case let .toggle(itemID) where itemID == "general.launchAtLogin":
            model.handle(action)
            applyLaunchAtLogin()
        case let .toggle(itemID) where itemID == "general.hideFromDock":
            model.handle(action)
            applyDockVisibility()
        default:
            model.handle(action)
        }
    }

    private func applyLaunchAtLogin() {
        let enabled = model.state.settingValue("general.launchAtLogin") == .bool(true)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger
                .error(
                    "[App] Launch at login failed: \(error.localizedDescription, privacy: .public)"
                )
            // Reflect the real state instead of leaving the switch lying.
            let actual = SMAppService.mainApp.status == .enabled
            model.syncGeneralToggle("general.launchAtLogin", to: actual)
        }
    }

    private func applyDockVisibility() {
        let hidden = model.state.settingValue("general.hideFromDock") == .bool(true)
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }

    private func confirmReset() {
        popover.performClose(nil)

        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = "Every toggle, slider, and picker goes back to its default."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.handle(.resetAll)
    }

    private func openPermissionSettings() {
        let target = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PopoverHost: View {
    let model: AppModel
    let maxContentHeight: CGFloat
    let onAction: (UIAction) -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        PopoverView(
            state: model.state,
            scrollable: true,
            maxContentHeight: maxContentHeight,
            onAction: onAction,
            onHeightChange: onHeightChange
        )
    }
}
