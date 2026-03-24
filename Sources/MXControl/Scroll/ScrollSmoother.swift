import CoreGraphics
import os

/// Scroll wheel mode hint — affects smoothing and momentum parameters.
/// Ratchet mode uses snappier settings; free-spin mode uses glidier, longer-coast settings.
enum ScrollWheelMode: Sendable {
    case ratchet
    case freeSpin
}

/// Smooth scroll engine using a high-frequency timer for interpolation.
///
/// Receives raw scroll deltas from ScrollInterceptor and produces smooth,
/// pixel-based scroll events using exponential decay at ~120Hz.
///
/// Thread safety: accumulate() is called from the CGEventTap thread,
/// the timer fires on a dedicated serial queue. Shared state is protected
/// by os_unfair_lock.
///
/// Design notes (v2 — simplified from CVDisplayLink + phase state machine):
///   - DispatchSourceTimer replaces CVDisplayLink (no deprecation warnings)
///   - Phase simulation removed — apps handle non-phase pixel scroll fine
///   - Events posted directly from timer thread (no postQueue indirection)
///   - Relative delta model: buffer resets to 0 after animation completes
final class ScrollSmoother: @unchecked Sendable {

    // MARK: - Configuration (lock-protected)

    private var _speedMultiplier: Double = 1.0
    var speedMultiplier: Double {
        get { withLock { _speedMultiplier } }
        set { withLock { _speedMultiplier = newValue } }
    }

    /// Momentum decay factor applied each frame after input stops.
    /// Higher = longer coast (0.80 = short, 0.98 = long trackpad-like glide).
    private var _momentumDecay: Double = 0.92
    var momentumDecay: Double {
        get { withLock { _momentumDecay } }
        set { withLock { _momentumDecay = newValue } }
    }

    /// Scroll wheel mode — affects smoothness and momentum behavior.
    /// Ratchet = snappier response; free-spin = glidier, longer coast.
    /// Set by MouseDevice when SmartShift wheel mode changes.
    private var _wheelMode: ScrollWheelMode = .ratchet
    var wheelMode: ScrollWheelMode {
        get { withLock { _wheelMode } }
        set { withLock { _wheelMode = newValue } }
    }

    // MARK: - Internal State (lock-protected)

    private let lock = OSAllocatedUnfairLock()

    /// Remaining scroll distance to animate (target delta, decays to 0).
    private var remainY: Double = 0
    private var remainX: Double = 0

    /// Sub-pixel accumulator: carries fractional pixels lost to integer rounding.
    /// Without this, slow scrolling loses pixels every frame and feels janky.
    private var subPixelY: Double = 0
    private var subPixelX: Double = 0

    /// Frames since last real input — used to detect end of gesture.
    private var framesSinceInput: Int = 0

    /// Whether we have residual scroll to animate.
    private var isAnimating: Bool = false

    // MARK: - Timer

    private var timer: DispatchSourceTimer?

    /// Whether the high-frequency timer is currently running.
    /// The timer starts on-demand when scroll input arrives and stops
    /// automatically when the animation completes — zero wakeups while idle.
    private var timerRunning: Bool = false

    /// Dedicated serial queue for the scroll timer (userInteractive for low latency).
    private let timerQueue = DispatchQueue(
        label: "com.mxcontrol.scroll.timer",
        qos: .userInteractive
    )

    /// Current timer interval in nanoseconds, derived from display refresh rate.
    private var timerIntervalNs: UInt64 = 8_333_333  // default ~120Hz

    /// Fallback interval when display refresh rate can't be determined.
    private static let fallbackIntervalNs: UInt64 = 8_333_333  // 120Hz

    /// Cached CGEventSource — reused across all frames to avoid creating kernel-side
    /// resources (Mach ports, private event state tables) at 120Hz. Creating a new
    /// CGEventSource per frame caused gradual memory growth as kernel cleanup lagged
    /// behind allocation rate.
    private var eventSource: CGEventSource?

    // MARK: - Constants

    /// Stop animating when remaining distance is below this (pixels).
    private static let deadZone: Double = 0.1

    /// Stop animating during momentum when remaining distance is below this (pixels).
    /// Higher than deadZone to eliminate sub-pixel oscillation (0-1-0-1 jitter) in
    /// the animation tail. The ~2px discarded at the end is imperceptible.
    private static let momentumDeadZone: Double = 2.0

    /// Frames without input before we let the animation coast to a stop.
    /// Dynamically scaled based on refresh rate so the time window stays ~50ms.
    private var inputStopFrames: Int = 6

    // MARK: - Lock Helper

    @inline(__always)
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Lifecycle

    deinit {
        // Safety net: unregister the display reconfiguration callback (which holds
        // a raw Unmanaged pointer to self) and stop the timer to prevent dangling
        // pointer dereference and resource leak.
        CGDisplayRemoveReconfigurationCallback(
            Self.displayReconfigCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        timer?.cancel()
        timer = nil
        eventSource = nil
    }

    // MARK: - Display Refresh Rate

    /// Query the main display's refresh rate and compute timer interval.
    private func updateTimerInterval() {
        let displayID = CGMainDisplayID()
        var refreshRate: Double = 0

        if let mode = CGDisplayCopyDisplayMode(displayID) {
            refreshRate = mode.refreshRate
        }

        // refreshRate == 0 means "unknown" (e.g. some external displays)
        if refreshRate < 30 {
            refreshRate = 120  // safe fallback
        }

        timerIntervalNs = UInt64(1_000_000_000.0 / refreshRate)

        // Scale inputStopFrames so the time window is always ~50ms
        // e.g. 60Hz → 3 frames, 120Hz → 6 frames, 240Hz → 12 frames
        inputStopFrames = max(3, Int((refreshRate * 0.05).rounded()))

        logger.info("[ScrollSmoother] Display refresh rate: \(Int(refreshRate))Hz, timer interval: \(self.timerIntervalNs / 1_000_000)ms, stopFrames: \(self.inputStopFrames)")
    }

    /// Callback registered for display reconfiguration events.
    /// Updates timer interval when display config changes (e.g. monitor switch,
    /// ProMotion rate change, external display connected).
    private static let displayReconfigCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard flags.contains(.setModeFlag) || flags.contains(.addFlag) else { return }
        guard let userInfo else { return }
        let smoother = Unmanaged<ScrollSmoother>.fromOpaque(userInfo).takeUnretainedValue()
        smoother.rescheduleTimer()
    }

    /// Re-query refresh rate and reschedule the timer with the new interval.
    /// Only reschedules if the timer is currently running (on-demand model).
    private func rescheduleTimer() {
        updateTimerInterval()
        guard timerRunning, let source = timer else { return }
        source.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Int(timerIntervalNs)),
            leeway: .nanoseconds(500_000)
        )
        debugLog("[ScrollSmoother] Timer rescheduled for new refresh rate")
    }

    // MARK: - Start / Stop

    func start() {
        updateTimerInterval()

        // Register for display reconfiguration events (updates timer interval on monitor change).
        // The timer itself is NOT started here — it starts on-demand when scroll input arrives.
        CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )

        debugLog("[ScrollSmoother] Ready (on-demand timer, \(1_000_000_000 / timerIntervalNs)Hz)")
    }

    func stop() {
        // Unregister display reconfiguration callback
        CGDisplayRemoveReconfigurationCallback(
            Self.displayReconfigCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )

        stopTimer()

        // Release cached event source to free kernel resources
        eventSource = nil

        withLock {
            remainY = 0
            remainX = 0
            subPixelY = 0
            subPixelX = 0
            isAnimating = false
            framesSinceInput = 0
        }

        debugLog("[ScrollSmoother] Stopped")
    }

    // MARK: - On-Demand Timer Lifecycle

    /// Start the high-frequency timer. Called when scroll input arrives and no timer is running.
    private func startTimer() {
        lock.lock()
        guard !timerRunning else { lock.unlock(); return }
        timerRunning = true
        lock.unlock()
        DiagnosticCounters.incrementScrollTimerStart()

        let source = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        source.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Int(timerIntervalNs)),
            leeway: .nanoseconds(500_000)  // 0.5ms leeway
        )
        source.setEventHandler { [weak self] in
            self?.processFrame()
        }
        source.resume()
        timer = source

        debugLog("[ScrollSmoother] Timer started on-demand (\(1_000_000_000 / timerIntervalNs)Hz)")
    }

    /// Stop the high-frequency timer. Called when animation completes (no more scroll to process).
    private func stopTimer() {
        lock.lock()
        guard timerRunning else { lock.unlock(); return }
        timerRunning = false
        lock.unlock()
        timer?.cancel()
        timer = nil

        debugLog("[ScrollSmoother] Timer stopped (idle)")
    }

    // MARK: - Accumulate (called from CGEventTap thread)

    func accumulate(deltaY: Double, deltaX: Double) {
        lock.lock()

        let scaledY = deltaY * _speedMultiplier
        let scaledX = deltaX * _speedMultiplier

        // Direction change on Y — discard old residual for snappy reversal
        if scaledY != 0 && remainY != 0 && (scaledY > 0) != (remainY > 0) {
            remainY = scaledY
            subPixelY = 0
        } else {
            remainY += scaledY
        }

        // Direction change on X
        if scaledX != 0 && remainX != 0 && (scaledX > 0) != (remainX > 0) {
            remainX = scaledX
            subPixelX = 0
        } else {
            remainX += scaledX
        }

        framesSinceInput = 0
        isAnimating = true

        let needsTimer = !timerRunning
        lock.unlock()

        // Start the timer outside the lock to avoid potential deadlock
        // (startTimer touches DispatchSource which should not be called under os_unfair_lock)
        if needsTimer {
            startTimer()
        }
    }

    // MARK: - Process Frame (called from timer queue at ~120Hz)

    private func processFrame() {
        lock.lock()

        guard isAnimating else {
            lock.unlock()
            return
        }

        framesSinceInput += 1
        let inputStopped = framesSinceInput > self.inputStopFrames

        // Wheel-mode-aware parameters:
        // Ratchet  = snappier (higher smoothness factor, base momentum)
        // Free-spin = glidier (lower smoothness factor, boosted momentum for longer coast)
        // With HID++ hi-res input (8× data points), smoothness can be higher since
        // the input data is naturally smooth — no need for aggressive low values.
        let smoothness: Double = _wheelMode == .freeSpin ? 0.16 : 0.22
        let effectiveDecay: Double = _wheelMode == .freeSpin
            ? min(_momentumDecay + 0.06, 0.98)
            : _momentumDecay

        // MOMENTUM PHASE: after input stops, decay the remaining buffer each frame.
        // This gives a natural "coast to stop" feel like trackpad inertia.
        if inputStopped {
            remainY *= effectiveDecay
            remainX *= effectiveDecay
        }

        let absRemainY = abs(remainY)
        let absRemainX = abs(remainX)

        // Check if we're done — use higher dead zone during momentum to eliminate
        // sub-pixel oscillation (0-1-0-1 jitter) in the animation tail.
        let effectiveDeadZone = inputStopped ? Self.momentumDeadZone : Self.deadZone
        let isDead = absRemainY < effectiveDeadZone && absRemainX < effectiveDeadZone
        if isDead && inputStopped {
            remainY = 0
            remainX = 0
            subPixelY = 0
            subPixelX = 0
            isAnimating = false
            lock.unlock()
            // Stop the timer — no more work to do. It will restart on next accumulate().
            stopTimer()
            return
        }

        // Adaptive smoothness: for small remaining distances, increase the lerp factor
        // so each frame emits at least ~1px. Prevents many near-zero frames that cause
        // visible stutter during slow scrolling.
        let adaptiveY = absRemainY > 1.0 ? smoothness : max(smoothness, min(1.0, 1.0 / max(absRemainY, 0.01)))
        let adaptiveX = absRemainX > 1.0 ? smoothness : max(smoothness, min(1.0, 1.0 / max(absRemainX, 0.01)))

        // Exponential interpolation with adaptive factor
        let frameY = remainY * adaptiveY
        let frameX = remainX * adaptiveX

        // Subtract what we're about to emit
        remainY -= frameY
        remainX -= frameX

        // Sub-pixel accumulation: add fractional pixels to accumulator,
        // only emit the integer part. Carry remainder to next frame.
        // This preserves total scroll distance and eliminates jitter from rounding.
        subPixelY += frameY
        subPixelX += frameX

        let emitY = subPixelY.rounded()
        let emitX = subPixelX.rounded()

        subPixelY -= emitY
        subPixelX -= emitX

        lock.unlock()

        // Only post if we have at least 1 integer pixel to emit on either axis
        if emitY == 0 && emitX == 0 { return }

        // Post the scroll event directly from this thread
        postScrollEvent(intY: Int32(emitY), intX: Int32(emitX), preciseY: frameY, preciseX: frameX)
    }

    // MARK: - Scroll Event Dispatch

    private func postScrollEvent(intY: Int32, intX: Int32, preciseY: Double, preciseX: Double) {
        // Lazily create and cache the event source to avoid allocating kernel resources
        // (Mach ports, private event state tables) on every frame at 120Hz.
        if eventSource == nil {
            eventSource = CGEventSource(stateID: .privateState)
            logger.info("[ScrollSmoother] CGEventSource created (cached, reused for all future frames)")
        }
        guard let source = eventSource else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: intY,
            wheel2: intX,
            wheel3: 0
        ) else { return }

        // Apply current modifier flags so Cmd+Scroll = smooth zoom, etc.
        event.flags = CGEventSource.flagsState(.combinedSessionState)

        // Set sub-pixel precision for apps that support it (e.g. Safari, native AppKit).
        // Set both PointDelta and FixedPtDelta for maximum app compatibility —
        // some apps read PointDelta, others read FixedPtDelta.
        event.setDoubleValueField(CGEventField.scrollWheelEventPointDeltaAxis1, value: preciseY)
        event.setDoubleValueField(CGEventField.scrollWheelEventPointDeltaAxis2, value: preciseX)
        event.setDoubleValueField(CGEventField.scrollWheelEventFixedPtDeltaAxis1, value: preciseY)
        event.setDoubleValueField(CGEventField.scrollWheelEventFixedPtDeltaAxis2, value: preciseX)

        // Mark as continuous (pixel-based) so apps treat it like trackpad input
        event.setDoubleValueField(CGEventField.scrollWheelEventIsContinuous, value: 1.0)

        // Mark as synthetic to prevent re-entry in our event tap
        event.setIntegerValueField(CGEventField.eventSourceUserData, value: ScrollInterceptor.syntheticMarker)

        event.post(tap: CGEventTapLocation.cgSessionEventTap)
    }
}
