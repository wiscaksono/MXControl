# Contributing to MXControl

## Prerequisites

- macOS 15+, Xcode command line tools, Swift 6 toolchain.
- A Logitech HID++ 2.0 device (Bolt/Unifying receiver or BLE).

## Workflow

```sh
swift build          # debug build
swift test           # full unit suite (no hardware needed)
make deploy          # build release, install to /Applications, relaunch
make dmg             # distributable disk image
```

See `docs/architecture.md` before adding code. Follow the layer rules:
features stay pure, transports stay dumb, UI never sends HID++ directly.

## Adding a device

1. Add `Sources/MXControl/Devices/Descriptors/<Name>.swift` conforming to
   `DeviceDescriptor` (model IDs, capabilities, special CIDs, defaults).
2. Add tests with `MockHIDTransport` — no hardware in unit tests.
3. Verify on hardware: discovery, feature load, settings persist + re-apply,
   divert re-arm after BLE reconnect.

## Pull requests

- One concern per PR, green CI required (`swift build` + `swift test`).
- Setting key format `mxcontrol.{device}.{setting}` is stable — never
  rename keys without a migration.
- Write so the reader can follow without running the app: small diffs,
  plain commit messages (`feat/fix/chore(scope): ...`).
