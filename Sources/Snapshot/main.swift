import AppCore
import MenuBarUI
import SwiftUI

struct Fixture {
    let id: String
    let state: AppState
}

let fixtures: [Fixture] = [
    Fixture(id: "root", state: DummyData.initialState()),
    Fixture(id: "root-clean", state: DummyData.connectedState()),
    Fixture(id: "onboarding", state: DummyData.onboardingState()),
    Fixture(id: "onboarding-relaunch", state: DummyData.onboardingRelaunchState()),
    Fixture(id: "root-empty", state: DummyData.emptyState()),
    Fixture(id: "root-scanning", state: DummyData.scanningState()),
    Fixture(id: "root-warning", state: DummyData.warningState()),
    Fixture(id: "device-mouse", state: DummyData.initialState(route: .device(DummyData.mouseID))),
    Fixture(
        id: "device-keyboard",
        state: DummyData.initialState(route: .device(DummyData.keyboardID))
    ),
    Fixture(id: "general", state: DummyData.initialState(route: .general)),
]

let arguments = CommandLine.arguments
let outDir = arguments.firstIndex(of: "--out")
    .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    .map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: "build/snapshots")

// AppKit must exist for font and color resolution, but the app must never run
// a loop or take focus.
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Drop stale PNGs from previous runs so the directory always reflects the
/// current fixture list.
let stale = (try? FileManager.default.contentsOfDirectory(
    at: outDir,
    includingPropertiesForKeys: nil
))?.filter { $0.pathExtension == "png" } ?? []
for url in stale {
    try? FileManager.default.removeItem(at: url)
}

var failures: [String] = []

for fixture in fixtures {
    for scheme in [ColorScheme.light, .dark] {
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(
            content: PopoverView(state: fixture.state, scrollable: false)
                .environment(\.colorScheme, scheme)
        )
        renderer.scale = 2
        renderer.isOpaque = true

        let name = "\(fixture.id)-\(scheme == .dark ? "dark" : "light").png"
        let url = outDir.appending(path: name)

        guard
            let cgImage = renderer.cgImage,
            let data = NSBitmapImageRep(cgImage: cgImage).representation(
                using: .png,
                properties: [:]
            )
        else {
            failures.append(name)
            continue
        }

        do {
            try data.write(to: url)
            print("snapshot \(url.path)")
        } catch {
            failures.append(name)
        }
    }
}

if !failures.isEmpty {
    FileHandle.standardError.write(Data("failed: \(failures.joined(separator: ", "))\n".utf8))
    exit(EXIT_FAILURE)
}

/// Regression guard: the scrollable path must never collapse. A ScrollView with
/// only a maxHeight renders at zero height inside the auto-sizing menu bar
/// window, which shows up as header + footer with nothing in between.
let viewportRenderer = ImageRenderer(
    content: PopoverView(state: DummyData.initialState(), scrollable: true)
)
if let image = viewportRenderer.cgImage, image.height >= 120 {
    print("viewport ok \(image.width)x\(image.height)")
} else {
    FileHandle.standardError.write(Data("viewport collapsed\n".utf8))
    exit(EXIT_FAILURE)
}
