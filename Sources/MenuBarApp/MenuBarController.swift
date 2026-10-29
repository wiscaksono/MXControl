import AppCore
import AppKit
import MenuBarUI
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

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
            height: PopoverView.chromeHeight + 240
        )

        let root = PopoverHost(model: model) { [weak self] action in
            self?.handle(action)
        } onHeightChange: { [weak self] height in
            self?.resize(to: height)
        }
        popover.contentViewController = NSHostingController(rootView: root)
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// NSPopover re-anchors itself when `contentSize` changes, so changing
    /// screens grows and shrinks it without the panel drifting off the item.
    private func resize(to height: CGFloat) {
        guard height > 1 else { return }
        let size = NSSize(width: PopoverView.preferredWidth, height: height)
        guard abs(popover.contentSize.height - size.height) > 0.5 else { return }
        popover.contentSize = size
    }

    private func handle(_ action: UIAction) {
        if action == .quit {
            NSApp.terminate(nil)
        } else {
            model.handle(action)
        }
    }
}

private struct PopoverHost: View {
    let model: AppModel
    let onAction: (UIAction) -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        PopoverView(
            state: model.state,
            scrollable: true,
            onAction: onAction,
            onHeightChange: onHeightChange
        )
    }
}
