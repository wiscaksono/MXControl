import AppKit

/// Logitech-style glyph for the status item. Falls back to the repo copy so the
/// snapshot target renders the same icon, and to an SF Symbol when neither is
/// available.
public enum BrandIcon {
    public static let menuBar = make(size: 18)

    private static func make(size: CGFloat) -> NSImage {
        let image = loadLogo() ?? symbolFallback()
        image.isTemplate = true
        image.size = NSSize(width: size, height: size)
        image.accessibilityDescription = "MXControl"
        return image
    }

    private static func loadLogo() -> NSImage? {
        if let url = Bundle.main.url(forResource: "logi-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        // `swift run` has no app bundle; the snapshot target runs from the repo.
        let repoPath = URL(fileURLWithPath: "Sources/Resources/logi-logo.png")
        return NSImage(contentsOf: repoPath)
    }

    private static func symbolFallback() -> NSImage {
        NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MXControl")
            ?? NSImage()
    }
}
