import Foundation
import os

/// Gesture engine for the MX Master 3S thumb (gesture) button.
///
/// Implements Logi Options+-style behavior:
///   - **Click** → Mission Control
///   - **Hold + drag left** → Switch to RIGHT workspace
///   - **Hold + drag right** → Switch to LEFT workspace
///   - **Hold + drag up** → Mission Control
///   - **Hold + drag down** → App Exposé
///
/// Two-phase detection (click-first guarantee):
///   1. If released within `clickTimeLimit` → **always a click** (regardless of movement)
///   2. After `clickTimeLimit` elapsed, whichever axis exceeds `dragThreshold` first wins:
///      - `|deltaX| >= threshold` → horizontal workspace switch
///      - `|deltaY| >= threshold` → vertical gesture (up = MC, down = Exposé)
///   3. If released after `clickTimeLimit` but below threshold → still a click
///
/// State machine:
///   IDLE → button press → PENDING
///     PENDING → release within clickTimeLimit → CLICK
///     PENDING → elapsed > clickTimeLimit AND axis threshold met → GESTURE
///     PENDING → release with no threshold met → CLICK
///     GESTURE → release → IDLE
final class GestureEngine: @unchecked Sendable {

    // MARK: - Configuration (adjustable via UI)

    /// Minimum hold time (seconds) before drag detection activates.
    /// Releases within this window are ALWAYS treated as clicks.
    private(set) var clickTimeLimit: TimeInterval = 0.20

    /// Horizontal drag distance (raw HID units) to trigger workspace switch.
    /// Only checked after `clickTimeLimit` has elapsed.
    private(set) var dragThreshold: Int = 200

    /// Thread-safe configuration update. Acquires the lock to ensure no
    /// in-flight gesture processing reads partially-updated config.
    func updateConfig(clickTimeLimit: TimeInterval? = nil, dragThreshold: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let ct = clickTimeLimit { self.clickTimeLimit = ct }
        if let dt = dragThreshold { self.dragThreshold = dt }
    }

    // MARK: - State

    private enum State {
        case idle
        case pending     // Button pressed, accumulating movement
        case gesture     // Drag threshold exceeded, action fired
    }

    private var state: State = .idle
    private var pressTime: ContinuousClock.Instant = .now
    private var accumulatedDeltaX: Int = 0
    private var accumulatedDeltaY: Int = 0

    /// Protects state mutations from concurrent notification callbacks.
    private let lock = NSLock()

    /// The CID of the thumb/gesture button.
    let thumbCID: UInt16

    // MARK: - Action Callbacks (injectable for testing)

    /// Called when a click gesture is detected. Defaults to `MacActions.missionControl`.
    var onClick: () -> Void = { MacActions.missionControl() }

    /// Called when a drag-left gesture is detected. Defaults to `MacActions.workspaceRight`.
    var onDragLeft: () -> Void = { MacActions.workspaceRight() }

    /// Called when a drag-right gesture is detected. Defaults to `MacActions.workspaceLeft`.
    var onDragRight: () -> Void = { MacActions.workspaceLeft() }

    /// Called when a drag-up gesture is detected. Defaults to `MacActions.missionControl`.
    var onDragUp: () -> Void = { MacActions.missionControl() }

    /// Called when a drag-down gesture is detected. Defaults to `MacActions.appExpose`.
    var onDragDown: () -> Void = { MacActions.appExpose() }

    // MARK: - Init

    init(thumbCID: UInt16 = 0x00C3) {
        self.thumbCID = thumbCID
        debugLog("[GestureEngine] Initialized for CID 0x\(String(format: "%04X", thumbCID))")
    }

    // MARK: - Event Handling

    /// Handle a diverted button event.
    func handleButtonEvent(pressedCIDs: [UInt16]) {
        let isThumbPressed = pressedCIDs.contains(thumbCID)

        var action: (() -> Void)?

        lock.lock()

        switch state {
        case .idle:
            if isThumbPressed {
                state = .pending
                pressTime = .now
                accumulatedDeltaX = 0
                accumulatedDeltaY = 0
                debugLog("[GestureEngine] Thumb button PRESSED → PENDING")
            }

        case .pending:
            if !isThumbPressed {
                let elapsed = ContinuousClock.now - pressTime
                debugLog("[GestureEngine] Thumb button RELEASED in PENDING (elapsed=\(elapsed) deltaX=\(accumulatedDeltaX))")

                // If we're still in PENDING at release, gesture never fired → always click.
                debugLog("[GestureEngine] → CLICK → Mission Control")
                state = .idle
                action = onClick
            }

        case .gesture:
            if !isThumbPressed {
                debugLog("[GestureEngine] Thumb button RELEASED in GESTURE → IDLE")
                state = .idle
            }
        }

        lock.unlock()
        action?()
    }

    /// Handle raw XY movement data while thumb button is held.
    func handleRawXY(deltaX: Int16, deltaY: Int16) {
        lock.lock()
        defer { lock.unlock() }

        var action: (() -> Void)?

        guard state == .pending else { return }

        accumulatedDeltaX += Int(deltaX)
        accumulatedDeltaY += Int(deltaY)

        // Time-gate: don't check drag threshold until click time window has passed
        let elapsed = ContinuousClock.now - pressTime
        guard elapsed >= .milliseconds(Int(clickTimeLimit * 1000)) else { return }

        let absDX = abs(accumulatedDeltaX)
        let absDY = abs(accumulatedDeltaY)

        // Whichever axis exceeds the threshold first wins (prevents diagonal confusion)
        if absDX >= dragThreshold && absDX >= absDY {
            if accumulatedDeltaX < 0 {
                debugLog("[GestureEngine] DRAG LEFT (dx=\(accumulatedDeltaX)) → Workspace RIGHT")
                state = .gesture
                action = onDragLeft
            } else {
                debugLog("[GestureEngine] DRAG RIGHT (dx=\(accumulatedDeltaX)) → Workspace LEFT")
                state = .gesture
                action = onDragRight
            }
        } else if absDY >= dragThreshold && absDY > absDX {
            if accumulatedDeltaY < 0 {
                debugLog("[GestureEngine] DRAG UP (dy=\(accumulatedDeltaY)) → Mission Control")
                state = .gesture
                action = onDragUp
            } else {
                debugLog("[GestureEngine] DRAG DOWN (dy=\(accumulatedDeltaY)) → App Exposé")
                state = .gesture
                action = onDragDown
            }
        }

        lock.unlock()
        action?()
        lock.lock()
    }
}
