import Testing
import AppKit
@testable import MXControl

/// Pure frame math for the mic-mute pill. No hardware or screens needed:
/// dual-monitor geometry is expressed as plain rects.
@Suite("MicMuteOverlay Frames")
struct MicMuteOverlayFrameTests {

    // Laptop 1512x982 at origin + 1920x1080 external to the right,
    // top-aligned with a 100pt vertical offset (dead zone beside laptop).
    private let laptop = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = NSRect(x: 1512, y: -98, width: 1920, height: 1080)
    private var frames: [NSRect] { [laptop, external] }

    @Test func dockFramePinsToTopRight() {
        let visible = NSRect(x: 1512, y: -98, width: 1920, height: 1056)
        let dock = MicMuteOverlay.dockFrame(visible: visible)
        #expect(dock.width == 48)
        #expect(dock.height == 48)
        // EXPERIMENT B: fully onscreen, no overhang past the screen edge.
        #expect(dock.maxX == visible.maxX)
        #expect(dock.maxY == visible.maxY - 10)
    }

    @Test func offscreenFrameIsSymmetric() {
        let dock = MicMuteOverlay.dockFrame(visible: external)
        let off = MicMuteOverlay.offscreenFrame(from: dock)
        #expect(off.origin.x == dock.maxX)
        #expect(off.origin.y == dock.origin.y)
        // Hide travels exactly the distance show entered with.
        #expect(off.origin.x - dock.origin.x == dock.width)
    }

    @Test func screenIndexPicksContainingScreen() {
        #expect(MicMuteOverlay.screenIndex(containing: NSPoint(x: 100, y: 100), in: frames) == 0)
        #expect(MicMuteOverlay.screenIndex(containing: NSPoint(x: 2000, y: 500), in: frames) == 1)
    }

    @Test func screenIndexPicksNearestInDeadZone() {
        // Above the laptop (y=1000) but left of the external: no frame
        // contains it — must fall back to nearest, never a hardcoded main.
        let dead = NSPoint(x: 100, y: 1050)
        #expect(NSMouseInRect(dead, laptop, false) == false)
        #expect(NSMouseInRect(dead, external, false) == false)
        #expect(MicMuteOverlay.screenIndex(containing: dead, in: frames) == 0)
    }

    @Test func screenIndexEmptyIsNil() {
        #expect(MicMuteOverlay.screenIndex(containing: .zero, in: []) == nil)
    }
}
