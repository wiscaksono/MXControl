import SwiftUI

enum Metric {
    static let popoverWidth: CGFloat = 320
    static let horizontalPadding: CGFloat = 12
    static let groupSpacing: CGFloat = 14
    static let rowPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 10
    static let headerHeight: CGFloat = 40
    static let footerHeight: CGFloat = 30
    static let hairlineHeight: CGFloat = 1
}

extension Color {
    /// Subtle fill used for grouped rows and status cards.
    static var panelFill: Color {
        Color.primary.opacity(0.045)
    }

    static var panelStroke: Color {
        Color.primary.opacity(0.06)
    }

    static var rowHighlight: Color {
        Color.primary.opacity(0.05)
    }
}
