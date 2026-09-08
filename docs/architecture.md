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
SwiftUI views (UI/, capability sections)
  → generic @Observable device (Devices/LogiDevice + capability states)
  → capability handlers + behaviors (Devices/)
  → static feature namespaces (MXControlHIDPP/Features/)
  → HIDTransport protocol (MXControlHIDPP/Transport/)
  → IOKit HID / CoreBluetooth
```

Rules:

- `MXControlHIDPP` is pure: `(transport, deviceIndex, featureIndex)`.
  No imports from app layers, no singletons, no UI types.
- `Transport/` knows bytes and file descriptors, never device semantics.
- `Devices/` owns per-device state. Scalar settings live in capability
  states (`CapabilityState.swift`), loaded/committed per id by
  `CapabilityHandlers`. Volatile wiring (diverts, scroll target, engines)
  lives in `Behaviors/` (scroll, thumb gesture, mic mute).
- UI binds states via `@Bindable`, never sends HID++.
- Cross-cutting services (`Audio/`, `Gesture/`, `Scroll/`) are singletons
  with injectable callbacks so tests can observe without hardware.
- Shared logging lives in `MXControlHIDPP/Core/` (`logger`, `debugLog`),
  never inside a feature or transport file.

## Devices

Each supported device is declared as data, not a subclass:

- `Devices/Descriptors/DeviceDescriptors.swift` holds `DeviceDescriptor`
  values: PIDs, name matches, capability list, behavior specs (scroll,
  thumb gesture CID, mic-mute CID). Matched by PID then HID++ name, with
  a generic battery+hosts fallback for unknown devices.
- `LogiDevice` is generic: it loads whatever capabilities the descriptor
  declares. Adding a device = adding one descriptor value + tests.
- Capability ids double as settings keys (`mxcontrol.{device}.{id}`).
  Ids are never renamed without a migration (see `CapabilityHandlers`
  for the two historical migrations).
- Capabilities whose HID++ feature the device does not report are skipped,
  so the same descriptor degrades gracefully across firmware variants.

## Background

- `docs/reverse-engineering/` — Logi Options+ RE notes (protocol reference).
- `docs/plans/` — historical implementation plans.
