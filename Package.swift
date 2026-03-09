// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MXControl",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "MXControl",
            path: "Sources/MXControl",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .testTarget(
            name: "MXControlTests",
            dependencies: ["MXControl"],
            path: "Tests/MXControlTests"
        ),
    ]
)
