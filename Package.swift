// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MenuBarApp",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "HIDPP",
            path: "Sources/HIDPP",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .target(name: "AppCore"),
        .target(
            name: "AppRuntime",
            dependencies: ["AppCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "MenuBarUI",
            dependencies: ["AppCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "MenuBarApp",
            dependencies: ["AppCore", "AppRuntime", "MenuBarUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "Snapshot",
            dependencies: ["AppCore", "MenuBarUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .testTarget(name: "HIDPPTests", dependencies: ["HIDPP"], path: "Tests/HIDPPTests"),
        .testTarget(
            name: "AppRuntimeTests",
            dependencies: ["AppRuntime", "AppCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
