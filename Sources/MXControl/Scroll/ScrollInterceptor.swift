import CoreGraphics
import AppKit
import os

/// Intercepts macOS scroll wheel events via CGEventTap and applies smooth scrolling.
///
/// Architecture:
/// 1. CGEventTap captures all scroll wheel events at the session level
/// 2. Trackpad events are passed through untouched (detected via phase fields)
/// 3. Mouse scroll events are suppressed and forwarded to ScrollSmoother
/// 4. ScrollSmoother interpolates and dispatches smooth pixel-based events
///
/// Requires Accessibility permission (same as gesture engine).
final class ScrollInterceptor: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = ScrollInterceptor()

    // MARK: - State

    private var _isRunning = false
    var isRunning: Bool { _isRunning }

    fileprivate var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    /// The smoother that processes intercepted scroll deltas.
    let smoother = ScrollSmoother()

    /// Whether smooth scrolling is enabled. When false, events pass through unmodified.
    private var _isEnabled = false
    var isEnabled: Bool {
        get { _isEnabled }
        set {
            _isEnabled = newValue
            if newValue && !_isRunning {
                start()
            } else if !newValue && _isRunning {
                stop()
            }
        }
    }

    /// Scroll speed multiplier (0.5 = half speed, 3.0 = triple).
    var speedMultiplier: Double {
        get { smoother.speedMultiplier }
        set { smoother.speedMultiplier = newValue }
    }

    /// Momentum decay factor (0.80 = short coast, 0.98 = long trackpad-like glide).
    var momentumDecay: Double {
        get { smoother.momentumDecay }
        set { smoother.momentumDecay = newValue }
    }

    // MARK: - Marker to Identify Synthetic Events

    /// Magic value set on eventSourceUserData to prevent re-entry.
    /// "MXSMOOTH" in ASCII hex.
    static let syntheticMarker: Int64 = 0x4D58534D4F4F5448

    // MARK: - Init

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard !_isRunning else { return }

        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            logger.warning("[ScrollInterceptor] Cannot start: Accessibility permission not granted")
            MacActions.requestAccessibilityPermission()
            return
        }

        _isRunning = true
        smoother.start()

        // Create the event tap on a dedicated background thread
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.setupEventTap()
            // Keep the thread alive via its run loop
            CFRunLoopRun()
        }
        thread.name = "MXControl.ScrollInterceptor"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread

        logger.info("[ScrollInterceptor] Started")
    }

    func stop() {
        guard _isRunning else { return }

        smoother.stop()

        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        if let port = machPort {
            CFMachPortInvalidate(port)
        }
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }

        machPort = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread?.cancel()
        tapThread = nil

        _isRunning = false
        logger.info("[ScrollInterceptor] Stopped")
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        // Store self in a raw pointer for the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: scrollEventCallback,
            userInfo: refcon
        ) else {
            logger.error("[ScrollInterceptor] Failed to create CGEventTap — check Accessibility permission")
            _isRunning = false
            return
        }

        machPort = port

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source

        tapRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)

        debugLog("[ScrollInterceptor] Event tap installed")
    }
}

// MARK: - CGEventTap Callback (C function)

/// The callback must be a plain C function — no captures allowed.
/// We recover `self` from the userInfo pointer.
private func scrollEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Handle tap disabled by timeout — re-enable it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let interceptor = Unmanaged<ScrollInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            if let port = interceptor.machPort {
                CGEvent.tapEnable(tap: port, enable: true)
                debugLog("[ScrollInterceptor] Re-enabled event tap after timeout")
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // Only process scroll wheel events
    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let interceptor = Unmanaged<ScrollInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    // Skip if smooth scrolling is disabled
    guard interceptor.isEnabled else {
        return Unmanaged.passUnretained(event)
    }

    // Skip our own synthetic events (prevent re-entry)
    let userData = event.getIntegerValueField(.eventSourceUserData)
    if userData == ScrollInterceptor.syntheticMarker {
        return Unmanaged.passUnretained(event)
    }

    // Skip trackpad events — they already have native smooth scrolling
    if isTrackpadEvent(event) {
        return Unmanaged.passUnretained(event)
    }

    // Use integer line deltas — these are consistent across all mice and
    // macOS acceleration settings. Scale to pixels (1 line ≈ 10px matches
    // macOS default scroll distance). The speed multiplier in ScrollSmoother
    // provides user-configurable scaling on top.
    let lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
    let lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))

    let scrollY = lineY * 10.0
    let scrollX = lineX * 10.0

    // Nothing to smooth
    if scrollY == 0 && scrollX == 0 {
        return Unmanaged.passUnretained(event)
    }

    // Feed the delta into the smoother
    interceptor.smoother.accumulate(
        deltaY: scrollY,
        deltaX: scrollX
    )

    // Suppress the original event — the smoother will generate smooth replacements
    return nil
}

// MARK: - Trackpad Detection

/// Detect whether a scroll event came from a trackpad (vs. a mouse).
/// Trackpad events have phase fields set; mouse scroll events don't.
private func isTrackpadEvent(_ event: CGEvent) -> Bool {
    let scrollPhase = event.getDoubleValueField(.scrollWheelEventScrollPhase)
    let momentumPhase = event.getDoubleValueField(.scrollWheelEventMomentumPhase)

    // If either phase field is non-zero, it's a trackpad gesture
    if scrollPhase != 0.0 || momentumPhase != 0.0 {
        return true
    }

    // Also check the continuous flag — trackpads set this
    let isContinuous = event.getDoubleValueField(.scrollWheelEventIsContinuous)
    if isContinuous != 0.0 {
        return true
    }

    return false
}
