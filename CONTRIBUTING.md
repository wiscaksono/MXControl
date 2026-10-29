# Contributing to MXControl

## Prerequisites

- macOS 15+ and Xcode 26+ (Swift 6.2 or newer).
- `swiftformat` and `swiftlint` for `make verify`.
- `imagemagick` only if you regenerate README screenshots.
- A Logitech HID++ 2.0 device if you touch hardware code. Unit tests need no
  hardware.

## Workflow

```sh
make verify      # build + tests + self-check + snapshots + lint; the gate
make build
make test
make snapshot    # write build/snapshots/*.png
make screenshots # regenerate docs/images from the snapshot fixtures
make install     # release build, copy to /Applications, launch
make dmg         # build/MXControl.dmg
```

`make verify` must pass before a pull request. Do not commit a red tree.

## Layout and rules

- `HIDPP` is the protocol layer. No app types, no UI.
- `DeviceCore` is discovery, capabilities, behaviors, and transports. Views
  must never import it.
- `AppCore` has no SwiftUI/AppKit imports and stays `Sendable`.
- `AppRuntime` owns the only state mutation point (`AppModel`), behind
  `DeviceService`.
- `MenuBarUI` takes `AppState` and emits `UIAction`. No view reads a service or
  hardware.
- `MXControl` owns the status item, popover, and process-level services.
- `Snapshot` renders fixtures offscreen for layout verification.

Read `AGENTS.md` before changing behavior. It lists the invariants: device
identity, settings keys, permission ordering, discovery only on user action,
and the no-AppKit-controls snapshot rule.

## Hardware changes

Only MX Master 3S and MX Keys Mini are validated. Do not add descriptors for
hardware nobody can test.

Run the manual checklist in `docs/QA.md` for anything that touches HID++, TCC,
scroll, gestures, or termination. Agents must not use GUI automation; write the
steps down instead.

## Screenshots

The README images are generated, not hand-taken:

```sh
make screenshots
```

This renders the `root-clean`, `device-mouse`, `device-keyboard`, and
`onboarding` fixtures and crops them into `docs/images/`. Regenerate them when
the UI changes.

## Adding a device

1. Add a descriptor in
   `Sources/DeviceCore/Devices/Descriptors/DeviceDescriptors.swift`.
2. Add tests with the stub transports; no hardware in unit tests.
3. Verify on hardware: discovery, capability load, settings persist and
   re-apply, divert re-arm after a BLE reconnect.

## Pull requests

- One concern per PR. Keep the diff reviewable.
- `make verify` green.
- New logic with branches, loops, parsing, or security leaves a small test or
  assert-based self-check.
- Commit messages are imperative sentences with a body that explains why. No
  prefixes required.
- Do not add dependencies, abstractions, or architectural layers without a
  concrete failure they remove.

## Release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `scripts/Info.plist`, plus the fallback in `Sources/AppCore/AppVersion.swift`
   and `DummyData.version`.
2. `make verify`.
3. `make dmg`.
4. Tag `vX.Y.Z` and publish the DMG with notes from `CHANGELOG.md`.
