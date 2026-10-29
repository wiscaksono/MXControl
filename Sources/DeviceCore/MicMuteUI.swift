import Foundation

/// UI hook for mic-mute feedback. The device layer fires it; the app layer
/// decides what to show.
@MainActor
public protocol MicMutePresenting: AnyObject {
    func reflect(muted: Bool)
}

@MainActor
public enum MicMuteUI {
    public static weak var presenter: (any MicMutePresenting)?
}
