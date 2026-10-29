import Foundation

/// Version shown in Settings. Reads the app bundle so it can never drift from
/// Info.plist; falls back to the shipped baseline when running unbundled.
public enum AppVersion {
    public static var current: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.isEmpty
        {
            return "\(short) (\(build))"
        }
        return short
    }
}
