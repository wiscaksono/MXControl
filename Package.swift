// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MenuBarApp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AppCore"),
        .target(
            name: "MenuBarUI",
            dependencies: ["AppCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "MenuBarApp",
            dependencies: ["AppCore", "MenuBarUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "Snapshot",
            dependencies: ["AppCore", "MenuBarUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
