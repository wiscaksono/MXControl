# MenuBarApp

macOS menubar app scaffold, SwiftPM only. No Xcode project. The shell is
`NSStatusItem` + `NSPopover`, so the popover keeps its anchor and arrow while
its height changes between screens.

The current UI is a recreation of MXControl (Logitech MX device control) with
dummy data: device list, per-device settings, and a general settings screen.
No hardware, no persistence, no HID++.

## Commands

| Command | Does |
| --- | --- |
| `make build` | `swift build` |
| `make test` | headless unit tests for `AppCore` |
| `make selfcheck` | run the app binary with `--self-check`, prints JSON, no GUI |
| `make snapshot` | render every screen fixture to `build/snapshots/*.png` |
| `make verify` | build + test + selfcheck + snapshot + lint |
| `make run` | bundle `.app` and launch in background |
| `make stop` | kill the running app |
| `make dev` | watch sources, rebuild and relaunch on save |
| `make release` | universal binary + signed bundle |
| `make install` | release, copy to `/Applications`, launch |

## Structure

```
Sources/
├── AppCore/
│   ├── Models/       DeviceSummary, SettingControl, AppState, Route
│   └── DummyData     fixtures that drive every screen
├── MenuBarUI/
│   ├── Screens/      RootScreen, DeviceScreen, GeneralScreen
│   ├── Components/   SettingsGroup, rows, controls, header, footer
│   └── PopoverView   assembles a screen from AppState + UIAction
├── MenuBarApp/       NSStatusItem + NSPopover shell, AppModel (state + actions)
└── Snapshot/         renders fixtures offscreen to PNG
```

State flows one way: views get `AppState` and emit `UIAction`, `AppModel`
mutates the state. No view touches a device or a service, which is what makes
offscreen rendering possible.

## Headless checks

`MenuBarApp --self-check` prints one JSON line with dummy state counts.

`make snapshot` writes PNGs for every fixture in `Sources/Snapshot/main.swift`,
light and dark. Read the PNG files to review layout without opening the app.

## Notes

- Bundle id lives in `scripts/Info.plist` (`dev.wisnu.menubarapp`).
- `LSUIElement` hides the dock icon; `AppDelegate` also sets `.accessory` so
  `swift run` behaves.
- Controls are custom-drawn (switch, slider, segmented). Native AppKit-backed
  controls do not render in `ImageRenderer`, which would make snapshots lie.
- The popover measures its content and caps the scroll viewport to the screen
  height; `make snapshot` fails if the scrollable path ever collapses to zero.
- Ad-hoc signing is enough for local use. Distribution needs Developer ID,
  hardened runtime, and `notarytool`.
- For app extensions, login-item helpers, or Xcode previews, generate an
  `xcodeproj` with XcodeGen from the same source tree.
