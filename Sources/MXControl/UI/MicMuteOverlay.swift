import MXControlHIDPP
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
        /// Points of the pill hidden past the right screen edge. Kills the
        /// right-side window shadow and glass edge highlight; top/left/bottom
        /// keep theirs. Icon padding compensates so it stays centered.
        static let rightClip: CGFloat = 10
        /// Show animation: short slide in from off-screen right.
        static let slideInDuration: TimeInterval = 0.3
        /// Hide animation: short slide out to off-screen right.
        static let slideOutDuration: TimeInterval = 0.3
    }

    private var panel: NSPanel?
    /// Which backdrop backend the panel uses. Logged on show for verification.
    private var usesGlass = false
    /// Show/hide generation: stale animation frames and hide completions are
    /// dropped when a newer show/hide supersedes them, so rapid toggles can't
    /// strand the panel mid-flight or order it out from under a new show.
    private var animationGeneration = 0
    /// Active frame-animation timer. Cancelled on every new animation so only
    /// one driver ever moves the panel.
    private var slideTimer: DispatchSourceTimer?

    private init() {
        // Re-anchor when displays reconfigure (reconnect, resolution/HDR
        // change, primary switch, menu-bar show/hide): the window server can
        // shift visibleFrame underneath a visible panel, stranding it.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reanchorIfVisible()
            }
        }
    }

    /// Snap a visible pill back to its dock after a display reconfiguration.
    /// No-op when hidden. Cancels any in-flight slide so it can't fight the snap.
    private func reanchorIfVisible() {
        guard let panel, panel.isVisible else { return }
        animationGeneration += 1
        slideTimer?.cancel()
        slideTimer = nil
        panel.alphaValue = 1
        positionTopRight(panel)
        logger.info("[MicMute] Re-anchored after screen change: \(NSStringFromRect(panel.frame), privacy: .public)")
    }

    /// Show the muted pill. Slides in from off-screen right into the
    /// right-edge dock on hidden→visible transitions; re-showing while
    /// visible just ensures full opacity.
    /// Re-showing repositions to the active screen.
    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        logger.info("[MicMute] Overlay backend: \(self.usesGlass ? "NSGlassEffectView (Liquid Glass)" : "NSVisualEffectView (fallback)", privacy: .public)")

        let finalFrame = topRightFrame()
        animationGeneration += 1
        let generation = animationGeneration

        if !panel.isVisible {
            // Start fully past the right screen edge, slide left into the dock.
            var startFrame = finalFrame
            startFrame.origin.x = finalFrame.maxX
            logger.info("[MicMute] show: \(NSStringFromRect(startFrame), privacy: .public) → \(NSStringFromRect(finalFrame), privacy: .public) gen=\(generation, privacy: .public)")
            panel.alphaValue = 0
            panel.setFrame(startFrame, display: false)
            panel.orderFrontRegardless()
            animatePanel(to: finalFrame, alpha: 1, duration: Layout.slideInDuration, frameEasing: easeOut, alphaEasing: rampedAlpha, generation: generation)
        } else {
            positionTopRight(panel)
            animatePanel(to: finalFrame, alpha: 1, duration: 0.18, frameEasing: easeOut, alphaEasing: easeOut, generation: generation)
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

    /// Hide with a slide out to off-screen right. No-op when already hidden.
    func hide() {
        guard let panel, panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration
        var endFrame = panel.frame
        endFrame.origin.x = rightOffscreenX()
        logger.info("[MicMute] hide: \(NSStringFromRect(panel.frame), privacy: .public) → \(NSStringFromRect(endFrame), privacy: .public) gen=\(generation, privacy: .public)")
        animatePanel(to: endFrame, alpha: 0, duration: Layout.slideOutDuration, frameEasing: easeIn, alphaEasing: easeIn, generation: generation) {
            panel.orderOut(nil)
        }
    }

    /// Hide synchronously with no animation. For app termination, where the
    /// animated fade is not guaranteed to complete before exit.
    func hideImmediately() {
        animationGeneration += 1
        slideTimer?.cancel()
        slideTimer = nil
        panel?.orderOut(nil)
    }

    // MARK: - Explicit Frame Driver

    /// Ease-out cubic.
    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    /// Ease-in cubic.
    private func easeIn(_ t: Double) -> Double { t * t * t }
    /// Fast alpha ramp: fully opaque 20% in so the pill is visible
    /// while it travels instead of fading in at the destination.
    private func rampedAlpha(_ t: Double) -> Double { min(1.0, t * 5.0) }

    /// Drive frame + alpha on a 60fps main-queue timer with an explicit snap
    /// at the end. Replaces `animator().setFrame`, whose interpolation the
    /// panel does not reliably follow across rapid show/hide cycles.
    /// The completion runs only when no newer animation superseded this one.
    private func animatePanel(
        to frame: NSRect,
        alpha: CGFloat,
        duration: TimeInterval,
        frameEasing: @escaping (Double) -> Double,
        alphaEasing: @escaping (Double) -> Double,
        generation: Int,
        completion: (() -> Void)? = nil
    ) {
        slideTimer?.cancel()
        slideTimer = nil
        guard let panel else { return }

        let fromFrame = panel.frame
        let fromAlpha = panel.alphaValue
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            guard let self else {
                timer.cancel()
                return
            }
            guard generation == self.animationGeneration else {
                timer.cancel()
                return
            }
            let t = min(1.0, (CACurrentMediaTime() - start) / duration)
            let e = CGFloat(frameEasing(t))
            let a = CGFloat(alphaEasing(t))
            func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
            panel.setFrame(
                NSRect(
                    x: lerp(fromFrame.origin.x, frame.origin.x),
                    y: lerp(fromFrame.origin.y, frame.origin.y),
                    width: frame.width,
                    height: frame.height
                ),
                display: true
            )
            panel.alphaValue = fromAlpha + (alpha - fromAlpha) * a
            if t >= 1.0 {
                timer.cancel()
                completion?()
            }
        }
        slideTimer = timer
        timer.resume()
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

        // Overflow covers the right curve, its highlight, plus the off-screen
        // clip, so the visible right edge cuts through flat glass interior.
        let glassWidth = Layout.width + Layout.cornerRadius + Layout.rightClip
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: glassWidth, height: Layout.height))
        glass.cornerRadius = Layout.cornerRadius
        glass.style = .regular

        // Center the icon in the visible zone (window minus right clip).
        let hostingView = NSHostingView(rootView: MicMutePillView(trailingPadding: glassWidth - (Layout.width - Layout.rightClip)))
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

        let hostingView = NSHostingView(rootView: MicMutePillView(trailingPadding: Layout.rightClip))
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
    /// The right `rightClip` points sit past the screen edge so no
    /// right-side shadow or glass edge renders.
    private func positionTopRight(_ panel: NSPanel) {
        panel.setFrame(topRightFrame(), display: false)
    }

    private func topRightFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        guard let visible = screen?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        }
        let origin = NSPoint(
            x: visible.maxX - Layout.width + Layout.rightClip,
            y: visible.maxY - Layout.height - Layout.marginTop
        )
        return NSRect(origin: origin, size: NSSize(width: Layout.width, height: Layout.height))
    }

    /// X so the pill sits fully past the right screen edge.
    private func rightOffscreenX() -> CGFloat {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let rightEdge = screen?.visibleFrame.maxX ?? 0
        return rightEdge
    }
}

// MARK: - Pill Content

/// Red mic-off icon. Trailing padding keeps the icon centered in the
/// visible zone: glass path compensates overflow + off-screen clip,
/// legacy path compensates the off-screen clip only.
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
