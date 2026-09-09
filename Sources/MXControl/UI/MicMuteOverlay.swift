import MXControlHIDPP
import AppKit
import QuartzCore
import SwiftUI

/// Compact mic-muted indicator, native OSD style.
///
/// Small translucent pill pinned to the top-right of the active screen
/// (below the date/time and Control Center). Shown persistently while the
/// microphone is muted, hidden immediately on unmute — no "mic on" overlay.
@MainActor
final class MicMuteOverlay: NSObject {
    static let shared = MicMuteOverlay()

    private enum Layout {
        static let width: CGFloat = 48
        static let height: CGFloat = 48
        static let marginTop: CGFloat = 10
        static let cornerRadius: CGFloat = 12
        /// Glass overflow past the window's right edge, clipped by the window.
        /// Cuts the right curve so the pill reads flush against the screen
        /// edge. Icon padding compensates so it stays centered.
        /// NOTE: the window itself must stay fully onscreen — parking it past
        /// the screen edge makes the window server teleport it on multi-monitor
        /// setups. Never re-add screen overhang here.
        static let rightClip: CGFloat = 10
        /// Show animation: short slide in from off-screen right.
        static let slideInDuration: TimeInterval = 0.3
        /// Hide animation: short slide out to off-screen right.
        static let slideOutDuration: TimeInterval = 0.3
    }

    /// In-flight slide state. Interpolation is X-only with Y locked to the
    /// dock, so a stale start frame can never drag the pill diagonally
    /// across monitors (the Y-10-then-40 jump on dual-monitor setups).
    private struct SlideState {
        let fromX: CGFloat
        let toX: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let fromAlpha: CGFloat
        let toAlpha: CGFloat
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let frameEasing: (Double) -> Double
        let alphaEasing: (Double) -> Double
        let generation: Int
        let completion: (() -> Void)?
    }

    private var panel: NSPanel?
    /// Which backdrop backend the panel uses. Logged on show for verification.
    private var usesGlass = false
    /// Show/hide generation: stale animation frames and hide completions are
    /// dropped when a newer show/hide supersedes them, so rapid toggles can't
    /// strand the panel mid-flight or order it out from under a new show.
    private var animationGeneration = 0
    /// Vsync driver for the active slide, bound to the target display so frames
    /// phase-match external monitors instead of juddering against their
    /// refresh. Falls back to a main-queue timer when link creation fails.
    /// Cancelled on every new animation so only one driver ever moves the panel.
    private var slide: SlideState?
    private var frameLink: CADisplayLink?
    private var slideTimer: DispatchSourceTimer?

    private override init() {
        super.init()
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
    /// No-op when hidden. Anchors to the screen the panel is currently on
    /// (not the mouse screen) so it can't teleport to another monitor.
    /// Cancels any in-flight slide so it can't fight the snap.
    private func reanchorIfVisible() {
        guard let panel, panel.isVisible else { return }
        animationGeneration += 1
        cancelSlideDriver()
        panel.alphaValue = 1
        if let screen = panelScreen(panel) {
            panel.setFrame(Self.dockFrame(visible: screen.visibleFrame), display: false)
        }
        logger.info("[MicMute] Re-anchored after screen change: \(NSStringFromRect(panel.frame), privacy: .public)")
    }

    /// Show the muted pill. Slides in from off-screen right into the
    /// right-edge dock on hidden→visible transitions; re-showing while
    /// visible just ensures full opacity.
    /// The dock frame is computed ONCE per show and reused for start and
    /// target, so rapid toggles and multi-monitor origins can't split Y.
    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        logger.info("[MicMute] Overlay backend: \(self.usesGlass ? "NSGlassEffectView (Liquid Glass)" : "NSVisualEffectView (fallback)", privacy: .public)")

        guard let screen = targetScreen() else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        let finalFrame = Self.dockFrame(visible: screen.visibleFrame)
        animationGeneration += 1
        let generation = animationGeneration

        if !panel.isVisible {
            // Start fully past the right screen edge, slide left into the dock.
            let startFrame = Self.offscreenFrame(from: finalFrame)
            logger.info("[MicMute] show: \(NSStringFromRect(startFrame), privacy: .public) → \(NSStringFromRect(finalFrame), privacy: .public) gen=\(generation, privacy: .public)")
            // Order AT the dock (fully onscreen) so the window server
            // attributes the correct display; never order at offscreen coords. Alpha is 0 so the dock frame never flashes.
            panel.alphaValue = 0
            panel.setFrame(finalFrame, display: false)
            panel.orderFrontRegardless()
            panel.setFrame(startFrame, display: false)
            animatePanel(on: screen, to: finalFrame, alpha: 1, duration: Layout.slideInDuration, frameEasing: easeOut, alphaEasing: delayedFadeIn, generation: generation)
        } else {
            // Same frame snapped then targeted: from == to, so only alpha
            // animates and no vertical drift is possible.
            panel.setFrame(finalFrame, display: false)
            animatePanel(on: screen, to: finalFrame, alpha: 1, duration: 0.18, frameEasing: easeOut, alphaEasing: easeOut, generation: generation)
        }
    }

    /// Reflect a mute state: show the pill while muted, hide on unmute.
    /// Single funnel for all trigger paths so behavior cannot diverge.
    /// No-op on repeat state: the engine swallows debounced presses but still
    /// returns the current state, and re-running the slide would visibly
    /// restart the animation (self-inflicted stutter on rapid F9).
    private var lastReflected: Bool?
    func reflect(muted: Bool) {
        guard lastReflected != muted else { return }
        lastReflected = muted
        if muted {
            show()
        } else {
            hide()
        }
    }

    /// Hide with a slide out to off-screen right. No-op when already hidden.
    /// Slides within the panel's current screen (Y locked to its current
    /// row) so a mouse move mid-mute can't fling it to another monitor.
    func hide() {
        guard let panel, panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration
        let screen = panelScreen(panel)
        var endFrame = panel.frame
        if let screen {
            endFrame = Self.offscreenFrame(from: Self.dockFrame(visible: screen.visibleFrame))
            endFrame.origin.y = panel.frame.origin.y
        } else {
            endFrame.origin.x = panel.frame.maxX
        }
        logger.info("[MicMute] hide: \(NSStringFromRect(panel.frame), privacy: .public) → \(NSStringFromRect(endFrame), privacy: .public) gen=\(generation, privacy: .public)")
        animatePanel(on: screen, to: endFrame, alpha: 0, duration: Layout.slideOutDuration, frameEasing: easeIn, alphaEasing: quickFadeOut, generation: generation) {
            panel.orderOut(nil)
        }
    }

    /// Hide synchronously with no animation. For app termination, where the
    /// animated fade is not guaranteed to complete before exit.
    func hideImmediately() {
        animationGeneration += 1
        cancelSlideDriver()
        panel?.orderOut(nil)
    }

    // MARK: - Vsync Slide Driver

    /// Ease-out cubic.
    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    /// Ease-in cubic.
    private func easeIn(_ t: Double) -> Double { t * t * t }
    /// Delayed fade-in for show: stays transparent for the first 60% of the
    /// slide (while the pill still overlaps the neighboring monitor), then
    /// pops to full opacity at the dock. Mirror of `quickFadeOut` on hide:
    /// both are visible only around the dock, travel invisible.
    private func delayedFadeIn(_ t: Double) -> Double { max(0.0, min(1.0, (t - 0.6) / 0.4)) }
    /// Fast fade-out for hide: fully transparent 40% in. The frame eases out
    /// slowly (`easeIn`), so by the time alpha hits 0 the pill has moved only
    /// ~3px — it never visibly strolls onto the neighboring monitor on
    /// multi-display setups. The rest of the slide runs invisible.
    private func quickFadeOut(_ t: Double) -> Double { min(1.0, t * 2.5) }

    /// Stop whichever driver (DisplayLink or fallback timer) is active.
    private func cancelSlideDriver() {
        frameLink?.invalidate()
        frameLink = nil
        slideTimer?.cancel()
        slideTimer = nil
        slide = nil
    }

    /// Drive X + alpha on the target display's vsync with an explicit snap
    /// at the end. Replaces `animator().setFrame`, whose interpolation the
    /// panel does not reliably follow across rapid show/hide cycles.
    /// Completion runs only when no newer animation superseded this one.
    /// Y stays locked to the dock for the whole slide (see `SlideState`).
    private func animatePanel(
        on screen: NSScreen?,
        to frame: NSRect,
        alpha: CGFloat,
        duration: TimeInterval,
        frameEasing: @escaping (Double) -> Double,
        alphaEasing: @escaping (Double) -> Double,
        generation: Int,
        completion: (() -> Void)? = nil
    ) {
        cancelSlideDriver()
        guard let panel else { return }

        slide = SlideState(
            fromX: panel.frame.origin.x,
            toX: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height,
            fromAlpha: panel.alphaValue,
            toAlpha: alpha,
            start: CACurrentMediaTime(),
            duration: duration,
            frameEasing: frameEasing,
            alphaEasing: alphaEasing,
            generation: generation,
            completion: completion
        )
        if screen == nil || !startDisplayLink(on: screen!) {
            startFallbackTimer()
        }
    }

    /// One vsync tick. Always runs on the main queue.
    private func slideTick() {
        guard let s = slide, let panel else {
            cancelSlideDriver()
            return
        }
        guard s.generation == animationGeneration else {
            cancelSlideDriver()
            return
        }
        let t = min(1.0, (CACurrentMediaTime() - s.start) / s.duration)
        let e = CGFloat(s.frameEasing(t))
        let a = CGFloat(s.alphaEasing(t))
        let last = t >= 1.0
        // display:false mid-flight: alpha compositing is cheap, full content
        // redraws every tick are not (glass re-render on scaled externals).
        panel.setFrame(
            NSRect(
                x: s.fromX + (s.toX - s.fromX) * e,
                y: s.y,
                width: s.width,
                height: s.height
            ),
            display: last
        )
        panel.alphaValue = s.fromAlpha + (s.toAlpha - s.fromAlpha) * a
        if last {
            let completion = s.completion
            cancelSlideDriver()
            completion?()
        }
    }

    /// Bind a DisplayLink to the target display. Always succeeds in practice;
    /// false = caller falls back to the main-queue timer.
    private func startDisplayLink(on screen: NSScreen) -> Bool {
        let link = screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = false
        frameLink = link
        return true
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        slideTick()
    }

    private func startFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in self?.slideTick() }
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
        // .none: frames are driven manually on the display's vsync. A system
        // behavior (.utilityWindow) fades/scales on orderFront and fights the
        // driver, which reads as stutter on external monitors.
        panel.animationBehavior = .none

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

        // Overflow covers the right curve, its highlight, and the window clip
        // margin, so the visible right edge cuts through flat glass interior.
        let glassWidth = Layout.width + Layout.cornerRadius + Layout.rightClip
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: glassWidth, height: Layout.height))
        glass.cornerRadius = Layout.cornerRadius
        glass.style = .regular

        // Center the icon in the window: compensate the glass overflow.
        let hostingView = NSHostingView(rootView: MicMutePillView(trailingPadding: glassWidth - Layout.width))
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

    // MARK: - Screen Resolution

    /// Screen priority: focused window → mouse cursor → nearest screen.
    /// Never bare `NSScreen.main`: on multi-monitor the mouse can sit in the
    /// dead zone between differently-sized displays where no frame contains
    /// it, and the focused app may live on another screen entirely.
    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let key = NSApp.keyWindow?.screen,
           screens.contains(where: { $0 === key }) { return key }
        let frames = screens.map(\.frame)
        if let i = Self.screenIndex(containing: NSEvent.mouseLocation, in: frames) {
            return screens[i]
        }
        return nil
    }

    /// Screen the panel currently lives on, via the window server when
    /// possible, else the screen containing (or nearest to) its center.
    /// Screen the panel currently lives on, resolved PURELY from geometry
    /// (panel center via `screenIndex`). Deliberately ignores `panel.screen`:
    /// the window server attributes a straddling/offscreen pill to the wrong
    /// display, so trusting it flings hide animations across monitors.
    private func panelScreen(_ panel: NSPanel) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let i = Self.screenIndex(containing: center, in: screens.map(\.frame)) {
            return screens[i]
        }
        return nil
    }

    /// Index of the frame containing p, else the nearest by edge distance.
    /// Pure (takes rects, not screens) so dual-monitor geometry is unit
    /// testable without hardware. Internal for @testable access.
    nonisolated static func screenIndex(containing p: NSPoint, in frames: [NSRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let i = frames.firstIndex(where: { NSMouseInRect(p, $0, false) }) { return i }
        return frames.indices.min(by: { edgeDistance2(p, frames[$0]) < edgeDistance2(p, frames[$1]) })
    }

    nonisolated private static func edgeDistance2(_ p: NSPoint, _ r: NSRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    /// Dock rect for a visibleFrame: flush to the right edge, below the
    /// menu bar (`visibleFrame` already excludes it, clear of the notch).
    /// Fully onscreen by design: parking past the screen edge makes the
    /// window server teleport the pill on multi-monitor setups.
    /// Pure for tests.
    nonisolated static func dockFrame(visible: NSRect) -> NSRect {
        NSRect(
            origin: NSPoint(
                x: visible.maxX - Layout.width,
                y: visible.maxY - Layout.height - Layout.marginTop
            ),
            size: NSSize(width: Layout.width, height: Layout.height)
        )
    }

    /// Fully past the right edge of the dock's screen. Symmetric with show's
    /// start frame so hide travels the same distance show entered with.
    nonisolated static func offscreenFrame(from dock: NSRect) -> NSRect {
        var f = dock
        f.origin.x = dock.maxX
        return f
    }
}

// MARK: - Pill Content

/// Red mic-off icon. Trailing padding keeps the icon centered in the
/// window: the glass content is wider than the window by its overflow.
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
