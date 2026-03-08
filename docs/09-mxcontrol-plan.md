# 09 - MXControl Implementation Plan

> Native macOS menu bar app (Swift 6, macOS 15+) that talks directly to Logitech HID++ 2.0 devices via IOKit & CoreBluetooth. Zero dependency on Logi Options+.

---

## Goal

Replace Logi Options+ entirely for two devices:
- **MX Master 3S** (mouse, modelId `2b034`)
- **MX Keys Mini** (keyboard, modelId `2b369`)

Menu bar app. Lightweight. No login. No telemetry. No Electron. No Qt.

---

## Project Setup

```
~/Developer/SANDBOX/MXControl/
  Package.swift              # SPM executable, macOS 15+, Swift 6 strict concurrency
  Makefile                   # build, bundle (.app), install, run, clean
  Sources/
    Info.plist               # LSUIElement=true, BT/HID usage descriptions
    Entitlements.plist       # com.apple.security.device.usb, bluetooth
    MXControl/
      App.swift              # @main, MenuBarExtra, environment setup

      Settings/
        SettingsStore.swift   # UserDefaults per-device persistence

      UI/
        MenuBarView.swift     # Device list, settings section, quit
        DeviceDetailView.swift # Tabbed per-device controls
        Components/
          BatteryIndicator.swift   # Battery icon + percentage
          SliderRow.swift          # Label + slider + value display
          ToggleRow.swift          # Label + toggle
          ActionPicker.swift       # Button remap dropdown

      Transport/
        HIDTransport.swift    # Protocol: send/receive HID++ packets
        USBTransport.swift    # IOKit IOHIDManager + IOHIDDevice
        BLETransport.swift    # CoreBluetooth GATT HID++ (if viable on macOS)

      Protocol/
        HIDPPPacket.swift     # Packet structs, report IDs 0x10/0x11/0x12, builder/parser
        HIDPPError.swift      # Error types
        FeatureIndex.swift    # Feature ID -> index cache per device

      Features/
        RootFeature.swift           # 0x0000: ping, getFeature, protocol version
        FeatureSetFeature.swift     # 0x0001: enumerate all features
        DeviceNameFeature.swift     # 0x0005: device name + type
        BatteryFeature.swift        # 0x1000 + 0x1004: battery level + charging
        ChangeHostFeature.swift     # 0x1814: Easy-Switch
        HostsInfoFeature.swift      # 0x1815: host names, OS types
        BacklightFeature.swift      # 0x1982 + 0x1983: keyboard backlight
        SpecialKeysFeature.swift    # 0x1B04: button enumeration + divert + remap
        SmartShiftFeature.swift     # 0x2110 + 0x2111: scroll wheel mode + torque
        HiResScrollFeature.swift    # 0x2121: hi-res scroll + direction
        ThumbWheelFeature.swift     # 0x2150: thumb wheel sensitivity + inversion
        AdjustableDPIFeature.swift  # 0x2201: DPI levels
        PointerSpeedFeature.swift   # 0x2205: pointer speed
        FnInversionFeature.swift    # 0x40A0 + 0x40A3: Fn key swap

      Device/
        DeviceManager.swift    # Discovery, lifecycle, USB + BLE coordination
        LogiDevice.swift       # Base: identity, feature map, settings re-apply
        MouseDevice.swift      # Mouse-specific features & @Observable UI state
        KeyboardDevice.swift   # Keyboard-specific features & @Observable UI state
        DeviceRegistry.swift   # PID -> name/type lookup table
```

**~35 files, estimated 4000-5000 lines Swift**

---

## Architecture

```
┌──────────────────────────────┐
│  SwiftUI MenuBarExtra        │
│  MenuBarView -> DeviceDetail │
│  @Observable bindings        │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  DeviceManager               │
│  - IOHIDManager callbacks    │
│  - receiver enumeration      │
│  - BLE scanning              │
│  - manages [LogiDevice]      │
│  - SettingsStore persistence │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  LogiDevice / MouseDevice    │
│  / KeyboardDevice            │
│  - feature index cache       │
│  - @Observable published     │
│    state (battery, dpi, etc) │
│  - read/write via features   │
└──────────┬───────────────────┘
           │ async/await
           ▼
┌──────────────────────────────┐
│  Features (14 files)         │
│  - static async functions    │
│  - pure: (transport, index)  │
│    -> typed result           │
│  - no shared state           │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  HIDTransport protocol       │
│  ┌────────────┐ ┌──────────┐│
│  │USBTransport│ │BLETransp.││
│  │(IOKit HID) │ │(CoreBT)  ││
│  └────────────┘ └──────────┘│
└──────────────────────────────┘
           │
           ▼
     ┌───────────┐
     │ HID++ 2.0 │
     │ Devices   │
     └───────────┘
```

---

## Key Design Decisions

### 1. `@Observable` macro (not ObservableObject)

macOS 15+ gives us native `@Observable`. No Combine publishers, no `@Published`, no `objectWillChange`. SwiftUI views automatically track which properties they read.

```swift
@Observable
final class MouseDevice: LogiDevice {
    var dpiLevel: Int = 800
    var smartShiftEnabled: Bool = true
    var smartShiftSensitivity: Int = 50
}
```

### 2. Features as static functions

Each feature file is a namespace of static async functions. No shared state.

```swift
enum BatteryFeature {
    struct Status {
        let level: Int          // 0-100
        let charging: Bool
    }
    static func getStatus(
        transport: HIDTransport,
        featureIndex: UInt8,
        deviceIndex: UInt8
    ) async throws -> Status
}
```

### 3. Transport protocol

```swift
protocol HIDTransport: Sendable {
    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse
}
```

### 4. Receiver enumeration

For Bolt/Unifying receivers:
1. IOHIDManager matches vendor `0x046D`
2. Filter for HID++ control interface: UsagePage `0xFF00`, Usage `0x0001`
3. Check PID against known receiver PIDs (`0xC52B`, `0xC548`, etc.)
4. If receiver: probe device indices 1-6 with `RootFeature.ping()` (1.5s timeout)
5. For each responding index: create LogiDevice, discover features, promote to MouseDevice/KeyboardDevice

### 5. Button remap via fixed action picker

Predefined actions (no custom keystroke capture):

```
Back, Forward, Middle Click,
Mission Control, App Expose, Launchpad, Show Desktop,
Smart Zoom, Lock Screen,
Volume Up/Down/Mute,
Play/Pause, Next/Previous Track,
Screenshot, Do Nothing
```

### 6. Settings persistence

UserDefaults with keys like `mxcontrol.{modelId}.dpi`, `mxcontrol.{modelId}.smartshift.sensitivity`, etc. Re-applied on device connect/reconnect.

---

## HID++ Report Format

```
Byte 0:    Report ID (0x10=short/7B, 0x11=long/20B, 0x12=very-long/64B)
Byte 1:    Device Index (0x01-0x06 for receiver, 0xFF for receiver itself)
Byte 2:    Feature Index (from Root feature GetFeature call)
Byte 3:    [7:4] Function ID, [3:0] Software ID
Byte 4+:   Parameters
```

Software ID must be unique per host app. Pick 0x01-0x0F, auto-switch on collision.

---

## Feature Map

### Mouse (MX Master 3S) -- 10 features

| UI Control | Feature ID | Notes |
|------------|-----------|-------|
| Battery | 0x1004 | Unified Battery. Level %, charging state |
| DPI | 0x2201 | Range 200-8000. Per-sensor |
| SmartShift | 0x2111 | v2 with tunable torque. Sensitivity 0-100, scrollForce 1-100 |
| Hi-Res Scroll | 0x2121 | Toggle hi-res, natural/inverted direction |
| Thumb Wheel | 0x2150 | Sensitivity + direction inversion |
| Pointer Speed | 0x2205 | Raw speed value |
| Button Remap | 0x1B04 | CIDs: 82, 83, 86, 195, 196. Divert + CGEvent |
| Easy-Switch | 0x1814 | Read-only host index |
| Hosts Info | 0x1815 | Host names, OS types |
| Device Name | 0x0005 | Init-time only |

#### Button CIDs

| CID | Button | Default |
|-----|--------|---------|
| 82 | Middle click | Middle Click |
| 83 | Back (side) | Back |
| 86 | Forward (side) | Forward |
| 195 | Gesture (thumb) | Mission Control |
| 196 | Mode shift (wheel) | Toggle ratchet/free-spin |

### Keyboard (MX Keys Mini) -- 5 features

| UI Control | Feature ID | Notes |
|------------|-----------|-------|
| Battery | 0x1004 | Same as mouse |
| Backlight | 0x1982/0x1983 | Level, auto-brightness |
| Fn Inversion | 0x40A0/0x40A3 | Probe both, use whichever exists |
| Easy-Switch | 0x1814 + 0x1815 | Read-only |
| Device Name | 0x0005 | Init-time only |

---

## Known Receiver PIDs

```
0xC52B  Unifying
0xC52D  Unifying (alt)
0xC534  Nano
0xC539  Lightspeed
0xC53A  Lightspeed (alt)
0xC547  Bolt (alt)
0xC548  Bolt
0xC549  Bolt (alt)
0xC52E  Unifying (alt)
```

Filter: only open interface with UsagePage `0xFF00`, Usage `0x0001`.

---

## BLE Notes

Logitech BLE service: `00010000-0000-1000-8000-011F2000046D`

macOS BLE HID driver may seize devices, blocking userspace GATT. If so, USB via receiver is the only path. Log clearly, fall back gracefully.

---

## Implementation Phases

### Phase 1: Foundation (~16 files)

Package.swift, Makefile, plists, HIDPPPacket, HIDPPError, HIDTransport, USBTransport, FeatureIndex, RootFeature, FeatureSetFeature, DeviceNameFeature, DeviceRegistry, LogiDevice, DeviceManager, App.swift (placeholder MenuBarExtra).

**Milestone**: Build succeeds. App discovers devices, prints names and feature lists.

### Phase 2: Mouse Core (~6 files)

BatteryFeature, AdjustableDPIFeature, SmartShiftFeature, SpecialKeysFeature, MouseDevice, initial DeviceDetailView.

**Milestone**: See MX Master 3S in menu bar with battery %. Change DPI and SmartShift live.

### Phase 3: Keyboard + Extended Mouse (~8 files)

BacklightFeature, FnInversionFeature, KeyboardDevice, PointerSpeedFeature, ThumbWheelFeature, HiResScrollFeature, ChangeHostFeature, HostsInfoFeature.

**Milestone**: Full feature set for both devices.

### Phase 4: UI + Polish (~9 files)

MenuBarView, complete DeviceDetailView, BatteryIndicator, SliderRow, ToggleRow, ActionPicker, SettingsStore, BLETransport, SMAppService + UNNotification.

**Milestone**: Complete app. Uninstall Logi Options+. Everything works.

---

## Build & Distribution

```makefile
build:     swift build -c release
bundle:    .app from binary + Info.plist + codesign w/ entitlements
install:   cp to /Applications/MXControl.app
```

No App Store (IOKit needs unsandboxed). Distribute as .app or DMG.

TCC: Input Monitoring required (macOS prompts on first launch).

---

## Reference

| Topic | File |
|-------|------|
| HID++ protocol, feature IDs | `03-hidpp-protocol.md` |
| Device discovery | `06-device-discovery.md` |
| Data model, CIDs, defaults | `05-data-model.md` |
| File paths, devices.json | `08-file-map.md` |
| External specs | https://lekensteyn.nl/files/logitech/ |
