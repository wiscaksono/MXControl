import Foundation

/// Pure sizing rules for the popover, kept out of the view so they can be
/// tested without a window.
public enum PopoverSizing {
    /// Used before the first layout pass reports a real content height.
    public static let fallbackViewport: CGFloat = 240
    /// Never shrink the viewport below this, even on a tiny screen.
    public static let minimumViewport: CGFloat = 280
    /// Space left for the menu bar and the popover arrow.
    public static let screenReserve: CGFloat = 140

    public static func maxViewport(screenHeight: CGFloat) -> CGFloat {
        max(minimumViewport, screenHeight - screenReserve)
    }

    public static func viewportHeight(measured: CGFloat, maxViewport: CGFloat) -> CGFloat {
        guard measured > 1 else { return fallbackViewport }
        return min(measured, maxViewport)
    }
}
