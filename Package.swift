// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MXControl",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        // Pure HID++ 2.0 core: protocol encoding, feature namespaces,
        // transports. No app-layer imports (no UI, devices, or services).
        .target(
            name: "MXControlHIDPP",
            path: "Sources/MXControlHIDPP",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .executableTarget(
            name: "MXControl",
            dependencies: ["MXControlHIDPP"],
            path: "Sources/MXControl"
        ),
        .testTarget(
            name: "MXControlHIDPPTests",
            dependencies: ["MXControlHIDPP"],
            path: "Tests/MXControlHIDPPTests"
        ),
        .testTarget(
            name: "MXControlTests",
            dependencies: ["MXControl", "MXControlHIDPP"],
            path: "Tests/MXControlTests"
        ),
    ]
)
