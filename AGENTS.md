# AGENTS.md

Menubar app: SwiftPM, macOS 14+, `NSStatusItem` + `NSPopover` shell hosting
SwiftUI. Current UI recreates MXControl with dummy data.

## Verify

Run `make verify` (build + test + selfcheck + snapshot + lint). That is the only
verification path.

- Do not use `osascript`, `screencapture`, `cliclick`, or any GUI automation.
- Do not launch the app unless the user asks. `make run` is for the human.
- `make dev` rebuilds and relaunches on save. It is a human workflow; agents
  must not run it.
- For UI changes, run `make snapshot` and read the PNGs in `build/snapshots/`.
  Snapshots verify drawing only, not interaction or focus behavior.
- When something needs a real click, write the manual steps for the user
  instead of doing them.

## Boundaries

- `AppCore` has no SwiftUI/AppKit imports. Models, `DeviceService`, and fixture
  data live there.
- `AppRuntime` owns `AppModel`. It takes a `DeviceService` in its initializer,
  so tests drive it with a stub instead of hardware.
- Device identity is `DeviceID` (transport + unit id + serial), never a random
  UUID, so settings survive a reconnect.
- Hardware code lands behind `DeviceService`. Views must never import HID++.
- `HIDPP` and `DeviceCore` are ported from MXControl and excluded from
  `swiftformat`/`swiftlint`. Keep edits there minimal and mechanical.
- Hardware writes go through `DeviceService.apply(_:)`; never mutate a live
  device from the UI layer.
- Settings keys are `mxcontrol.{descriptor}.{unit}.{setting}`. Never key by
  device name or a random UUID.
- Views take `AppState` and emit `UIAction`. No view reads a service or device.
- `MenuBarApp` owns process-level code: status item, popover, alerts, and
  opening system settings.
- New screen or state: add a fixture in `Sources/Snapshot/main.swift`.
- Scroll viewport height is measured from content and capped by screen height.
  Keep the `viewport ok` guard in the snapshot target; it catches the
  zero-height collapse.
- Controls must be custom-drawn SwiftUI shapes. AppKit-backed controls
  (`Toggle`, `Slider`, `Picker`, `.borderedProminent`) do not render in
  `ImageRenderer`, so snapshots would not match the real UI.
- `MenuBarUI`, `MenuBarApp`, and `Snapshot` compile with
  `.defaultIsolation(MainActor.self)`. Do not add it to `AppCore`; models stay
  nonisolated and `Sendable`. Popover sizing rules live in
  `AppCore/PopoverSizing.swift` and are unit tested.

## Style

Existing conventions: one type per file, `@Observable` + `@MainActor` for app
state, value types for screens, semantic fonts and shared metrics in
`DesignTokens.swift`, `swiftformat` before commit.
