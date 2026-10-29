import AppCore
import AppKit
import MenuBarUI
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
            let image = NSImage(
                systemSymbolName: "computermouse.fill",
                accessibilityDescription: "MenuBarApp"
            )
            image?.isTemplate = true
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

        // This is called from SwiftUI's layout pass; resizing the window inline
        // re-enters layout. Hop out of the current pass first.
        Task { @MainActor in
            guard abs(self.popover.contentSize.height - size.height) > 0.5 else { return }
            self.popover.contentSize = size
        }
    }

    private func handle(_ action: UIAction) {
        if action == .quit {
            NSApp.terminate(nil)
        } else {
            model.handle(action)
        }
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
