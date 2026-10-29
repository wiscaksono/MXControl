// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBarApp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AppCore"),
        .target(name: "MenuBarUI", dependencies: ["AppCore"]),
        .executableTarget(name: "MenuBarApp", dependencies: ["AppCore", "MenuBarUI"]),
        .executableTarget(name: "Snapshot", dependencies: ["AppCore", "MenuBarUI"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
