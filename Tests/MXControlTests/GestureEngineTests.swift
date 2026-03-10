import Testing
import Foundation
@testable import MXControl

@Suite("GestureEngine")
struct GestureEngineTests {

    /// Helper: create a GestureEngine with spy callbacks and a short click time for fast tests.
    private func makeEngine(
        clickTimeLimit: TimeInterval = 0.01,
        dragThreshold: Int = 100
    ) -> (engine: GestureEngine, actions: ActionSpy) {
        let spy = ActionSpy()
        let engine = GestureEngine(thumbCID: 0x00C3)
        engine.updateConfig(clickTimeLimit: clickTimeLimit, dragThreshold: dragThreshold)
        engine.onClick = { spy.record(.click) }
        engine.onDragLeft = { spy.record(.dragLeft) }
        engine.onDragRight = { spy.record(.dragRight) }
        engine.onDragUp = { spy.record(.dragUp) }
        engine.onDragDown = { spy.record(.dragDown) }
        return (engine, spy)
    }

    /// Wait for the click time window to elapse.
    private func waitPastClickTime(_ limit: TimeInterval = 0.01) {
        Thread.sleep(forTimeInterval: limit + 0.005)
    }

    // MARK: - Click Gesture

    @Test func clickOnQuickRelease() {
        let (engine, spy) = makeEngine()

        // Press thumb button
        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        // Release immediately (within clickTimeLimit)
        engine.handleButtonEvent(pressedCIDs: [])

        #expect(spy.actions == [.click])
    }

    @Test func clickOnReleaseWithoutThreshold() {
        let (engine, spy) = makeEngine()

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Move a little but not enough to cross threshold
        engine.handleRawXY(deltaX: 10, deltaY: 5)

        // Release — should still be click since threshold not met
        engine.handleButtonEvent(pressedCIDs: [])

        #expect(spy.actions == [.click])
    }

    // MARK: - Horizontal Gestures

    @Test func dragLeftTriggersWorkspaceRight() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Drag left (negative deltaX)
        engine.handleRawXY(deltaX: -50, deltaY: 0)
        engine.handleRawXY(deltaX: -60, deltaY: 0)  // total: -110, exceeds 100

        #expect(spy.actions == [.dragLeft])

        // Release should not trigger click
        engine.handleButtonEvent(pressedCIDs: [])
        #expect(spy.actions == [.dragLeft])
    }

    @Test func dragRightTriggersWorkspaceLeft() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        engine.handleRawXY(deltaX: 60, deltaY: 0)
        engine.handleRawXY(deltaX: 50, deltaY: 0)  // total: 110

        #expect(spy.actions == [.dragRight])
    }

    // MARK: - Vertical Gestures

    @Test func dragUpTriggersMissionControl() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Drag up (negative deltaY)
        engine.handleRawXY(deltaX: 0, deltaY: -60)
        engine.handleRawXY(deltaX: 0, deltaY: -50)  // total: -110

        #expect(spy.actions == [.dragUp])
    }

    @Test func dragDownTriggersAppExpose() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Drag down (positive deltaY)
        engine.handleRawXY(deltaX: 0, deltaY: 60)
        engine.handleRawXY(deltaX: 0, deltaY: 50)  // total: 110

        #expect(spy.actions == [.dragDown])
    }

    // MARK: - Axis Dominance

    @Test func diagonalResolvesToDominantHorizontal() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Diagonal with stronger horizontal component
        engine.handleRawXY(deltaX: -80, deltaY: 40)
        engine.handleRawXY(deltaX: -40, deltaY: 20)  // dx=-120, dy=60 → horizontal wins

        #expect(spy.actions == [.dragLeft])
    }

    @Test func diagonalResolvesToDominantVertical() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Diagonal with stronger vertical component
        engine.handleRawXY(deltaX: 30, deltaY: -70)
        engine.handleRawXY(deltaX: 20, deltaY: -50)  // dx=50, dy=-120 → vertical wins

        #expect(spy.actions == [.dragUp])
    }

    @Test func tieBreakFavorsHorizontal() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Equal magnitudes: |dx| == |dy| == 110 → horizontal wins (absDX >= absDY)
        engine.handleRawXY(deltaX: -110, deltaY: -110)

        #expect(spy.actions == [.dragLeft])
    }

    // MARK: - Click-First Guarantee

    @Test func movementDuringClickWindowIgnored() {
        let (engine, spy) = makeEngine(clickTimeLimit: 0.05, dragThreshold: 50)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])

        // Massive movement DURING click time window
        engine.handleRawXY(deltaX: -500, deltaY: 0)

        // Release within click time → should be click, not drag
        engine.handleButtonEvent(pressedCIDs: [])

        #expect(spy.actions == [.click])
    }

    // MARK: - No Double-Fire

    @Test func gestureDoesNotFireTwice() {
        let (engine, spy) = makeEngine(dragThreshold: 100)

        engine.handleButtonEvent(pressedCIDs: [0x00C3])
        waitPastClickTime()

        // Cross threshold
        engine.handleRawXY(deltaX: -120, deltaY: 0)
        #expect(spy.actions == [.dragLeft])

        // Keep moving — should NOT fire again
        engine.handleRawXY(deltaX: -200, deltaY: 0)
        #expect(spy.actions == [.dragLeft])

        // Release — should NOT fire click
        engine.handleButtonEvent(pressedCIDs: [])
        #expect(spy.actions == [.dragLeft])
    }

    // MARK: - Ignores Other CIDs

    @Test func ignoresNonThumbButton() {
        let (engine, spy) = makeEngine()

        // Press a different button (middle click CID=82)
        engine.handleButtonEvent(pressedCIDs: [82])
        engine.handleButtonEvent(pressedCIDs: [])

        #expect(spy.actions.isEmpty)
    }
}

// MARK: - Test Helpers

private final class ActionSpy: @unchecked Sendable {
    enum Action: Equatable, CustomStringConvertible {
        case click, dragLeft, dragRight, dragUp, dragDown

        var description: String {
            switch self {
            case .click: "click"
            case .dragLeft: "dragLeft"
            case .dragRight: "dragRight"
            case .dragUp: "dragUp"
            case .dragDown: "dragDown"
            }
        }
    }

    private let lock = NSLock()
    private var _actions: [Action] = []

    var actions: [Action] {
        lock.lock()
        defer { lock.unlock() }
        return _actions
    }

    func record(_ action: Action) {
        lock.lock()
        defer { lock.unlock() }
        _actions.append(action)
    }
}
