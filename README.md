# MenuBarApp

macOS menubar app for Logitech MX devices. SwiftPM only, no Xcode project.

The shell is `NSStatusItem` + `NSPopover` hosting SwiftUI. Device logic is
ported from MXControl: HID++ 2.0 protocol, discovery over USB receivers and
Bluetooth, capability handlers, scroll smoothing, thumb gestures, and mic mute.

## Commands

| Command | Does |
| --- | --- |
| `make build` | `swift build` |
| `make test` | all tests (protocol, device core, app model, state) |
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
├── HIDPP/         HID++ 2.0 protocol, features, transports, tests (vendored)
├── DeviceCore/    discovery, capability handlers, behaviors, settings store
├── AppCore/       DeviceID, snapshots, presentation models, AppState
├── AppRuntime/    AppModel, talks to a DeviceService
├── MenuBarUI/     screens and custom-drawn controls
├── MenuBarApp/    status item, popover, mic mute overlay, alerts
└── Snapshot/      renders fixtures offscreen to PNG
```

Views only see `AppState` and emit `UIAction`. `AppModel` forwards edits to
`DeviceService`; `HIDPPDeviceService` turns live devices into `DeviceSnapshot`.
The dummy service and fixtures keep screenshots and tests hardware-free.

## Permissions

- **Bluetooth** — required for direct BLE devices.
- **Input Monitoring** — required for scroll interception and diverted keys.
- **Microphone** — only for the mic mute HUD (no audio is recorded).

Grant them in System Settings after the first launch; the permission warning
in the popover links straight to the right pane.

## Settings

Stored in UserDefaults under `mxcontrol.{descriptor}.{unit}.{setting}`. Device
identity is the descriptor id plus the HID++ unit id, never the device name or
a random UUID, so settings survive reconnects.

## Notes

- Bundle id: `com.wiscaksono.mxcontrol`. Entitlements: USB, Bluetooth, HID.
- `LSUIElement` keeps the app out of the Dock; the activation policy is always
  `.accessory`.
- Ad-hoc signing is enough locally. Changing the signing identity resets the
  Input Monitoring grant, so pick the final identity before testing scroll.
- `HIDPP` and `DeviceCore` are vendored from MXControl and excluded from
  `swiftformat`/`swiftlint` to keep diffs honest.
