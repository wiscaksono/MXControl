import AppKit
import SwiftUI

/// Compact mic-muted indicator, native OSD style.
///
/// Small translucent pill pinned to the top-right of the active screen
/// (below the date/time and Control Center). Shown persistently while the
/// microphone is muted, hidden immediately on unmute — no "mic on" overlay.
@MainActor
final class MicMuteOverlay {
    static let shared = MicMuteOverlay()

    private enum Layout {
        static let width: CGFloat = 48
        static let height: CGFloat = 48
        static let marginTop: CGFloat = 10
        static let cornerRadius: CGFloat = 12
    }

    private var panel: NSPanel?
    /// Which backdrop backend the panel uses. Logged on show for verification.
    private var usesGlass = false
    /// Show/hide generation: a hide completion only orders out when no newer
    /// show superseded it, so rapid toggles can't strand a visible alpha-0 panel.
    private var animationGeneration = 0

    private init() {}

    /// Show the muted pill. Re-showing repositions to the active screen.
    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        logger.info("[MicMute] Overlay backend: \(self.usesGlass ? "NSGlassEffectView (Liquid Glass)" : "NSVisualEffectView (fallback)", privacy: .public)")

        positionTopRight(panel)

        animationGeneration += 1

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    /// Reflect a mute state: show the pill while muted, hide on unmute.
    /// Single funnel for all trigger paths so behavior cannot diverge.
    func reflect(muted: Bool) {
        if muted {
            show()
        } else {
            hide()
        }
    }

    /// Hide immediately with a quick fade. No-op when already hidden.
    func hide() {
        guard let panel, panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            guard generation == self.animationGeneration else { return }
            panel.orderOut(nil)
        }
    }

    /// Hide synchronously with no animation. For app termination, where the
    /// animated fade is not guaranteed to complete before exit.
    func hideImmediately() {
        animationGeneration += 1
        panel?.orderOut(nil)
    }

    // MARK: - Panel Setup

    private func makePanel() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow

        // Background: real Liquid Glass (NSGlassEffectView) on macOS 26+.
        // SwiftUI .glassEffect degrades to plain blur when our LSUIElement app
        // is not focused (always, for an F9 overlay) — AppKit glass does not.
        // Otherwise fall back to classic blur.
        if #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            panel.hasShadow = true
            // Container fills the window (fixed 48x48); the glass inside it
            // overflows right past the window edge and is clipped by the window.
            panel.contentView = makeGlassView()
            usesGlass = true
        } else {
            panel.hasShadow = false
            panel.contentView = makeLegacyEffectView(frame: rect)
            usesGlass = false
        }

        return panel
    }

    /// Real Liquid Glass backdrop hosting the pill icon.
    ///
    /// Asymmetric shape (rounded left, square right) via geometry, not masking:
    /// the glass view is wider than the window by one corner radius, so its
    /// right curve falls outside the window and is clipped. The glass itself
    /// renders untouched (masks break the render per Apple guidance).
    @available(macOS 26, *)
    private func makeGlassView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        // Explicit clip: the glass overflows right by design (see below), so
        // the window frame is not the only thing trimming it. Window clipping
        // alone is undocumented behavior; masksToBounds makes it deterministic.
        container.layer?.masksToBounds = true

        let glassWidth = Layout.width + Layout.cornerRadius
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: glassWidth, height: Layout.height))
        glass.cornerRadius = Layout.cornerRadius
        glass.style = .regular

        let hostingView = NSHostingView(rootView: MicMutePillView(trailingPadding: Layout.cornerRadius))
        glass.contentView = hostingView

        container.addSubview(glass)
        return container
    }

    /// Classic HUD blur for macOS <26 or Reduce Transparency.
    private func makeLegacyEffectView(frame rect: NSRect) -> NSVisualEffectView {
        // Native HUD material as the pill background.
        let effectView = NSVisualEffectView(frame: rect)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Layout.cornerRadius
        // Flush against the right screen edge: round left corners only.
        effectView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        // Layer shadow follows the masked (left-rounded) shape, since it derives
        // from the rendered alpha. Window shadow would stay square, so it is off.
        effectView.layer?.shadowColor = NSColor.black.cgColor
        effectView.layer?.shadowOpacity = 0.35
        effectView.layer?.shadowRadius = 10
        effectView.layer?.shadowOffset = NSSize(width: 0, height: -2)

        let hostingView = NSHostingView(rootView: MicMutePillView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        return effectView
    }

    /// Pin flush to the right edge of the screen containing the mouse cursor.
    /// `visibleFrame` already excludes the menu bar, so the pill lands
    /// below the date/time and Control Center, clear of the notch.
    private func positionTopRight(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.maxX - Layout.width,
            y: visible.maxY - Layout.height - Layout.marginTop
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: Layout.width, height: Layout.height)), display: false)
    }
}

// MARK: - Pill Content

/// Red mic-off icon. Trailing padding matches the glass overflow so the icon
/// stays centered in the visible 48pt zone (glass is 60 wide, 12 clipped).
/// Legacy path passes 0 (no overflow there).
struct MicMutePillView: View {
    var trailingPadding: CGFloat = 0

    var body: some View {
        Image(systemName: "mic.slash.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, trailingPadding)
            .background(Color.clear)
    }
}
