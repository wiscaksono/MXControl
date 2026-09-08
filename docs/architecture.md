# MXControl Architecture

Native macOS menu bar app (Swift 6, macOS 15+) that talks HID++ 2.0 directly
to Logitech devices. No dependency on Logi Options+.

## Targets (SwiftPM, `Package.swift`)

| Target | Kind | Contains |
|--------|------|----------|
| `MXControlHIDPP` | library | Pure HID++ 2.0 core: `Protocol/`, `Features/`, `Transport/`, `Core/` (logging, diagnostics, device types). No app-layer imports. |
| `MXControl` | executable | App entry, UI, devices, services, settings. Depends on `MXControlHIDPP`. |
| `MXControlHIDPPTests` | test | Protocol/feature/transport tests with `MockHIDTransport` (no hardware). |
| `MXControlTests` | test | App-layer tests (gestures, settings, mic-mute, registry). |

## Layers

```
SwiftUI views (UI/)
  → @Observable device models (Device/)
  → static feature namespaces (Features/)
  → HIDTransport protocol (Transport/)
  → IOKit HID / CoreBluetooth
```

Rules:

- `Features/` are pure functions: `(transport, deviceIndex, featureIndex)`.
  No imports from app layers, no singletons, no UI types.
- `Transport/` knows bytes and file descriptors, never device semantics.
  `TransportType` lives here, not in the device manager.
- `Device/` owns per-device state and side-effect wiring (scroll engine,
  gesture engine, mic-mute). UI binds via `@Bindable`, never sends HID++.
- Cross-cutting services (`Audio/`, `Gesture/`, `Scroll/`) are singletons
  with injectable callbacks so tests can observe without hardware.
- Shared logging lives in `Core/` (`logger`, `debugLog`), never inside a
  feature or transport file.

## Devices

Each supported device is declared as data, not a subclass:

- `Devices/Descriptors/<Name>.swift` conforms to `DeviceDescriptor`:
  model IDs, display name, type, capability list, special CIDs, defaults.
- `LogiDevice` is generic: it loads whatever capabilities the descriptor
  declares. Adding a device = adding one descriptor file + tests.
- Setting keys are namespaced `mxcontrol.{device}.{setting}` and the format
  is stable across refactors so user preferences survive upgrades.

## Background

- `docs/reverse-engineering/` — Logi Options+ RE notes (protocol reference).
- `docs/plans/` — historical implementation plans.
