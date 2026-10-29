import Foundation

/// Typed payload for `MXControl --self-check`.
public struct SelfCheckReport: Codable, Equatable, Sendable {
    public var app: String
    public var status: String
    public var route: String
    public var devices: Int
    public var detailSections: Int
    public var generalSections: Int
    public var version: String

    public init(
        app: String,
        status: String,
        route: String,
        devices: Int,
        detailSections: Int,
        generalSections: Int,
        version: String
    ) {
        self.app = app
        self.status = status
        self.route = route
        self.devices = devices
        self.detailSections = detailSections
        self.generalSections = generalSections
        self.version = version
    }
}

/// Headless verification path: `MXControl --self-check`.
/// Prints one JSON line describing the current dummy state, no AppKit.
public enum SelfCheck {
    public static func run() {
        print(payload())
    }

    public static func report() -> SelfCheckReport {
        let state = DummyData.initialState()
        return SelfCheckReport(
            app: "MXControl",
            status: "ok",
            route: "root",
            devices: state.devices.count,
            detailSections: state.details.values.reduce(0) { $0 + $1.sections.count },
            generalSections: state.general.count,
            version: state.version
        )
    }

    public static func payload() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(report()),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"app":"MXControl","status":"error"}"#
        }
        return json
    }
}
