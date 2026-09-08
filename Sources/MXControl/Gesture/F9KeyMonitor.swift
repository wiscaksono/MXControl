import CoreGraphics
import AppKit
import os

/// Global F9 key monitor — fallback trigger for mic mute.
///
/// Used when the keyboard does not expose a divertable mic-mute control via
/// HID++ `0x1B04` (the primary path). Intercepts F9 keyDown/keyUp at the
/// session level regardless of Fn-lock state, since both plain F9 and Fn+F9
/// arrive as keycode `0x63`.
///
/// Only enabled while at least one MX keyboard with mic-mute enabled is
/// connected and no HID++ divert is active (see `DeviceManager`).
/// Requires Accessibility permission, like `ScrollInterceptor` and `MacActions`.
final class F9KeyMonitor: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = F9KeyMonitor()

    /// F9 virtual keycode (kVK_F9).
    static let f9KeyCode: Int64 = 0x63

    // MARK: - State

    /// Guards _isEnabled, _isRunning, and the tap lifecycle (machPort, source,
    /// thread, runloop). The tap callback fires on the tap thread while
    /// start/stop run on MainActor, so all of it must be synchronized.
    /// NSLock (not OSAllocatedUnfairLock) because withLock's @Sendable closure
    /// cannot capture non-Sendable CF types like CFMachPort.
    private let lock = NSLock()

    private var _isRunning = false
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    fileprivate var machPort: CFMachPort? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _machPort
        }
        set {
            lock.lock()
            _machPort = newValue
            lock.unlock()
        }
    }
    private var _machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    /// Lifecycle generation: incremented on every start/stop so a late tap
    /// install from a previous start can never leak past a stop.
    private var _generation = 0

    /// Fired on F9 keyDown (press edge only, not repeat, not release).
    var onF9Pressed: (() -> Void)?

    /// Whether F9 interception is enabled. When false, all events pass through.
    /// Setting true while a previous start failed (e.g. permission denied)
    /// retries the start, so granting Accessibility later recovers automatically.
    private var _isEnabled = false
    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            _isEnabled = newValue
            let shouldStart = newValue && !_isRunning
            lock.unlock()
            if shouldStart {
                start()
            } else if !newValue {
                stop()
            }
        }
    }

    /// Retry a pending start (e.g. after the user grants Accessibility).
    /// No-op unless enabled but not running.
    func retryIfNeeded() {
        lock.lock()
        let shouldStart = _isEnabled && !_isRunning
        lock.unlock()
        if shouldStart { start() }
    }

    private init() {}

    // MARK: - Start / Stop

    func start() {
        lock.lock()
        guard !_isRunning else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard AXIsProcessTrusted() else {
            logger.warning("[F9KeyMonitor] Cannot start: Accessibility permission not granted")
            MacActions.requestAccessibilityPermission()
            return
        }

        lock.lock()
        _isRunning = true
        _generation += 1
        let generation = _generation
        lock.unlock()

        let thread = Thread { [weak self] in
            guard let self else { return }
            // Only run the runloop if this generation's tap installed.
            // Otherwise the thread would spin forever on a dead tap.
            if self.setupEventTap(generation: generation) {
                CFRunLoopRun()
            }
        }
        thread.name = "MXControl.F9KeyMonitor"
        thread.qualityOfService = .userInteractive
        thread.start()
        lock.lock()
        self.tapThread = thread
        lock.unlock()

        logger.info("[F9KeyMonitor] Started")
    }

    func stop() {
        lock.lock()
        guard _isRunning else {
            lock.unlock()
            return
        }
        // Invalidate the generation first so a concurrent late install
        // from setupEventTap cleans itself up instead of leaking.
        _generation += 1
        let port = _machPort
        let source = runLoopSource
        let runLoop = tapRunLoop
        lock.unlock()

        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
        if let port {
            CFMachPortInvalidate(port)
        }
        if let rl = runLoop {
            CFRunLoopStop(rl)
        }

        lock.lock()
        _machPort = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        _isRunning = false
        lock.unlock()
        logger.info("[F9KeyMonitor] Stopped")
    }

    // MARK: - Event Tap Setup

    /// Install the tap for the given start generation. Returns false when this
    /// generation is already stale (stop raced start) or creation failed, in
    /// which case the caller must NOT run the runloop.
    private func setupEventTap(generation: Int) -> Bool {
        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: f9EventCallback,
            userInfo: refcon
        ) else {
            logger.error("[F9KeyMonitor] Failed to create CGEventTap — check Accessibility permission")
            lock.lock()
            // Only clear running state if no newer start/stop superseded us.
            if _generation == generation {
                _isRunning = false
            }
            lock.unlock()
            return false
        }

        lock.lock()
        guard _generation == generation && _isRunning else {
            lock.unlock()
            // Stale: stop() already ran. Tear down immediately so nothing leaks.
            CFMachPortInvalidate(port)
            return false
        }
        _machPort = port
        lock.unlock()

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        lock.lock()
        guard _generation == generation && _isRunning else {
            lock.unlock()
            CFMachPortInvalidate(port)
            return false
        }
        runLoopSource = source
        lock.unlock()

        lock.lock()
        tapRunLoop = CFRunLoopGetCurrent()
        lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)

        debugLog("[F9KeyMonitor] Event tap installed")
        return true
    }
}

// MARK: - CGEventTap Callback (C function)

/// Plain C function — no captures. Recovers `self` from userInfo.
private func f9EventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let monitor = Unmanaged<F9KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let port = monitor.machPort {
                CGEvent.tapEnable(tap: port, enable: true)
                debugLog("[F9KeyMonitor] Re-enabled event tap after timeout")
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<F9KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    guard monitor.isEnabled else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    guard keyCode == F9KeyMonitor.f9KeyCode else {
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        // Ignore auto-repeat — only the initial press toggles.
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat {
            debugLog("[F9KeyMonitor] F9 pressed — toggling mic mute")
            monitor.onF9Pressed?()
        }
    }

    // Suppress the original F9 event while the fallback is active. Baseline F9
    // does nothing on macOS (verified), and swallowing avoids triggering
    // Mission Control when the key arrives as plain F9 in the non-media
    // Fn-lock state. Tradeoff: while the fallback runs, F9 is unavailable to
    // other apps — disable "Mic Mute on F9" in the UI to restore it.
    return nil
}
