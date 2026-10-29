import SwiftUI

enum Metric {
    static let popoverWidth: CGFloat = 320
    static let horizontalPadding: CGFloat = 12
    static let groupSpacing: CGFloat = 14
    static let rowPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 10
    static let controlCornerRadius: CGFloat = 6
    static let headerHeight: CGFloat = 30
    static let footerHeight: CGFloat = 30
    static let hairlineHeight: CGFloat = 1
}

extension Color {
    /// Subtle fill used for grouped rows and status cards.
    static var panelFill: Color {
        Color.primary.opacity(0.045)
    }
}

enum Motion {
    static let control = Animation.snappy(duration: 0.15)
    static let screen = Animation.snappy(duration: 0.28, extraBounce: 0)

    /// Animations are skipped entirely when the system asks for reduced motion.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
