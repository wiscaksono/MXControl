import Foundation

/// Headless verification path: `MenuBarApp --self-check`.
/// Prints one JSON line describing the current dummy state, no AppKit.
public enum SelfCheck {
    public static func run() {
        print(payload())
    }

    public static func payload() -> String {
        let state = DummyData.initialState()
        let body: [String: Any] = [
            "app": "MenuBarApp",
            "status": "ok",
            "route": "root",
            "devices": state.devices.count,
            "detailSections": state.details.values.reduce(0) { $0 + $1.sections.count },
            "generalSections": state.general.count,
            "version": state.version,
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"app":"MenuBarApp","status":"error"}"#
        }
        return json
    }
}
