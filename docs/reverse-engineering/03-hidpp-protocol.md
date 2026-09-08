# 03 - HID++ Protocol

Logitech HID++ is the proprietary protocol used between the host computer and Logitech peripherals. The agent speaks HID++ over USB HID reports and BLE GATT characteristics.

---

## Protocol Versions

| Version | Usage | Report Types |
|---------|-------|-------------|
| **HID++ 1.0** | Receivers (Unifying/Bolt), legacy devices | Register-based read/write |
| **HID++ 2.0** | Modern peripherals (MX series, etc.) | Feature-based with indexed functions |

## Report Format

### Report IDs

| Report ID | Name | Total Size | Payload Size |
|-----------|------|------------|-------------|
| `0x10` | Short | 7 bytes | 4 bytes |
| `0x11` | Long | 20 bytes | 17 bytes |
| `0x12` | Very Long (VLP) | 64 bytes | 61 bytes |

### HID++ 2.0 Report Structure

```
Byte 0:    Report ID (0x10, 0x11, or 0x12)
Byte 1:    Device Index (0x01-0x06 for receiver-attached, 0xFF for receiver itself)
Byte 2:    Feature Index (mapped from feature ID via Root feature 0x0000)
Byte 3:    [7:4] Function ID, [3:0] Software ID (swid)
Byte 4+:   Function parameters (payload)
```

### Software ID (swid)

The agent uses a software ID to multiplex HID++ traffic. If another application uses the same swid, the agent detects it and switches:

```
"setting swid to 0x%x"
"changing swid from 0x%x to 0x%x"
"Report is a feature response from other SW using swid 0x%x"
```

---

## Root Feature (0x0000)

Every HID++ 2.0 device implements feature 0x0000. It is always at index 0.

| Function | ID | Parameters | Returns |
|----------|-----|-----------|---------|
| GetFeature | 0 | featureId (2 bytes) | index, type (software/hidden/obsolete), version |
| Ping | 1 | pingData (1 byte) | same pingData echoed back + protocol version |
| GetProtocolVersion | - | via Ping response | protocol major, minor, target software |
| GetCount | 2 | - | number of features |
| GetFeatureId | 3 | index (1 byte) | featureId (2 bytes) |

**Flow**: To use any feature, first call `GetFeature(featureId)` to get its index. Then use that index in byte 2 of all subsequent reports.

---

## Complete HID++ 2.0 Feature Map (97+ features)

### Core / System

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x0000 | Root | Ping, feature discovery, protocol version |
| 0x0001 | FeatureSet | Enumerate all features on device |
| 0x0003 | FirmwareInfo | Firmware version, build info |
| 0x0005 | DeviceNameType | Device model name and type |
| 0x0007 | DeviceFriendlyName | User-settable friendly name |
| 0x0008 | SwitchAndKeepAlive | Deep sleep prevention, keep-alive |
| 0x0009 | Subdevices | Enumerate sub-devices |
| 0x0011 | PropertyAccess | Read/write device properties |
| 0x0020 | ConfigChange | Configuration change detection (cookie) |
| 0x0021 | CryptoIdentifier | Cryptographic device identity |

### Battery

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x1000 | BatteryUnifiedLevelStatus | Legacy battery level + charging status |
| 0x1001 | BatteryVoltage | Raw battery voltage |
| 0x1004 | UnifiedBattery | Modern battery (level %, charging state, SoC) |
| 0x1010 | ChargingControl | Charging control parameters |
| 0x0104 | BatterySOC (Centurion) | State of charge (Centurion protocol) |

### Mouse

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x2110 | SmartShift | Scroll wheel auto-shift (ratchet <-> free-spin) |
| 0x2111 | SmartShiftWithTunableTorque | SmartShift v2 with adjustable torque |
| 0x2121 | HiResWheel | Hi-resolution scroll wheel |
| 0x2130 | RatchetWheel | Ratchet wheel mode control |
| 0x2150 | Thumbwheel | Thumb wheel settings |
| 0x2201 | AdjustableDPI | DPI settings (levels, range) |
| 0x2202 | ExtendedAdjustableDPI | Extended DPI with more granularity |
| 0x2205 | PointerMotionScaling | Pointer speed/acceleration |
| 0x2230 | AngleSnapping | Angle snapping toggle |
| 0x2240 | SurfaceTuning | Mouse surface calibration |
| 0x2250 | AnalysisMode | Sensor analysis mode |
| 0x2400 | HybridTracking | Hybrid tracking engine |
| 0x2005 | ButtonSwapCancel | Primary/secondary button swap |
| 0x2006 | PointerAxesOrientation | Pointer axis orientation |

### Keyboard

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x40A0 | FnInversion v0 | Fn key inversion |
| 0x40A2 | FnInversion v2 | Fn key inversion v2 |
| 0x40A3 | FnInversion v3 | Fn key inversion v3 + host info |
| 0x4220 | LockKeyState | Caps/Num/Scroll lock state |
| 0x4521 | DisableKeys | Disable specific keys |
| 0x4522 | DisableKeysByUsage | Disable keys by HID usage |
| 0x4530 | DualPlatform | Dual platform support |
| 0x4531 | MultiPlatform | Multi-platform keyboard |
| 0x4540 | KBLayout | Keyboard layout detection |

### Key/Button Remapping

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x1B00 | SpecialKeys v0 | Special keys (legacy) |
| 0x1B03 | SpecialKeys v3 | Special keys v3 |
| 0x1B04 | SpecialKeys v4 | Special keys and mouse buttons (most common) |
| 0x1B06 | SpecialKeysAndButtons v6 | Latest special keys |
| 0x1B10 | ControlList | Control list enumeration |
| 0x1BC0 | ReportHIDUsages | Report HID usage values |
| 0x1C00 | PersistentRemappableAction | Persistent remappable actions |

### Button Remapping Protocol Detail (0x1B04)

```
Functions:
  GetCount()          -> number of remappable controls
  GetCtrlIdInfo(idx)  -> control ID (cid), task ID, flags, position, group, gmask
  GetCtrlIdReporting(cid)  -> divert state, remap target, raw XY, raw wheel flags

Operations:
  _divert(cid)        -> Divert button events to software (agent handles them)
  _undivert(cid)      -> Return button to default hardware behavior
  _remap(cid, target) -> Remap button to another control ID

Events:
  onKeyChange(state, ctrl_id)  -> Button press/release
  onRawXY(x, y)               -> Raw pointer movement (when diverted)
  onRawWheel(hi_res, period, deltaV) -> Raw scroll data (when diverted)
```

### Backlight / LED

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x1300 | LEDControl | Basic LED on/off |
| 0x1981 | KeyboardBacklight v1 | Keyboard backlight |
| 0x1982 | Backlight v2 | Backlight with levels |
| 0x1983 | KeyboardBacklight v3 | Latest keyboard backlight |
| 0x1990 | IlluminationLight | Desk lamp / illumination |
| 0x18A1 | LEDState | LED state reporting |
| 0x8040 | BrightnessControl | Brightness control |
| 0x8070 | ColorLEDEffects | Color LED effects |
| 0x8071 | RGBEffects | RGB lighting effects |
| 0x8080 | PerKeyLighting v1 | Per-key RGB |
| 0x8081 | PerKeyLighting v2 | Per-key RGB v2 |
| 0x8088 | MultiLightbar | Multi-lightbar control |

### Host/Connection

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x1814 | ChangeHost | Easy-Switch (change connected host) |
| 0x1815 | HostsInfos | Information about paired hosts |
| 0x1816 | BleProPrepairing | BLE Pro pre-pairing |
| 0x0305 | BtHostInfo | Bluetooth host info |
| 0x0309 | LightSpeedPairing | LightSpeed receiver pairing |
| 0x030A | BTGamingMode | Bluetooth gaming mode |
| 0x1500 | ForcePairing | Force pairing mode |
| 0x1D4B | WirelessStatus | Wireless connection status |

### Haptic / Force

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x19B0 | HapticFeedback | Haptic feedback control |
| 0x19C0 | ForceSensingButton | Force sensing button config |

### Crown / Dial

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x4600 | Crown | MX Creative Dial / Crown |
| 0x4610 | MultiRoller | Multi-roller support |

### Touchpad / Gestures

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x6010 | Gestures v1 | Gesture recognition |
| 0x6012 | Gestures v2 | Gesture recognition v2 |
| 0x6100 | TouchPadRawXY | Raw touchpad XY data |
| 0x6500 | Gestures v3 | Gesture recognition v3 |
| 0x6501 | Gestures v4 | Latest gesture recognition |

### DFU (Firmware Update)

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x00C0 | DFUControl v0 | DFU control (enter DFU mode) |
| 0x00C1 | DFUControl v1 | DFU control v1 |
| 0x00C2 | DFUControl v2 | DFU control v2 |
| 0x00C3 | DFUControl v3 | DFU control v3 |
| 0x00D0 | DFU | Firmware data transfer |
| 0x00D1 | ResumableDFU | Resumable firmware transfer |

### Presenter

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x1A00 | PresenterControl | Spotlight/presenter control |
| 0x4303 | LuxReport | Ambient light sensor (lux) |

### Gaming (G-series)

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x8010 | Gkey | G-key support |
| 0x8020 | Mkeys | M-key support |
| 0x8030 | MR | Macro record key |
| 0x8060 | ReportRate | Polling rate |
| 0x8061 | ExtendedReportRate | Extended polling rate |
| 0x8090 | ModeStatus | Mode status |
| 0x8100 | OnboardProfiles | Onboard profile management |
| 0x8110 | MouseButtonSpy | Mouse button spy mode |
| 0x8111 | LatencyMonitoring | Latency monitoring |

### Sim Racing

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x8120 | GamingAttachments | Attachments detection |
| 0x8123 | ForceFeedback | Force feedback (wheels) |
| 0x8127 | DualClutch | Dual clutch paddles |
| 0x812C | WheelCenterPosition | Wheel centering |
| 0x8131 | CenterSpring | Center spring force |
| 0x8132 | AxisMapping | Axis mapping |
| 0x8133 | GlobalDamping | Global damping |
| 0x8134 | BrakeForce | Brake force settings |
| 0x8135 | PedalStatus | Pedal status |
| 0x8136 | TorqueLimit | Torque limit |
| 0x807A | RpmIndicator | RPM indicator LEDs |
| 0x80A4 | AxisResponseCurve | Response curve |
| 0x80D0 | CombinedPedals | Combined pedals mode |

### Audio (Headsets)

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x8300 | Sidetone | Sidetone level |
| 0x8305 | BassTone | Bass adjustment |
| 0x8310 | Equalizer | EQ settings |
| 0x8320 | JackDetection | Audio jack detection |
| 0x8330 | MicPolarPattern | Microphone polar pattern |
| 0x8350 | MicBlendAdjust | Mic blend adjustment |
| 0x8360 | MicHeadphoneAdjust | Mic/headphone adjustment |
| 0x8370 | MicGainAdjust | Mic gain adjustment |

### TWS / Earbuds

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x0631 | DoNotDisturb (TIFA) | Do not disturb mode |
| 0x0700 | FitsMolding | FITS ear tip molding |
| 0x0701 | TWBudsTapControl | Tap gesture control |

### Testing / Manufacturing

| Feature ID | Name | Description |
|------------|------|-------------|
| 0x0002 | EngTest | Engineering test |
| 0x1800 | GenericTest | Generic test |
| 0x1801 | ManufacturingMode | Manufacturing mode |
| 0x1802 | DeviceReset | Factory reset |
| 0x1805 | OOBState | Out-of-box state |
| 0x1890 | RfTest | RF test |
| 0x1E00 | EnableHiddenFeatures | Enable hidden features |
| 0x1F1F | FirmwareProperties | Firmware properties |
| 0x1F20 | ADCMeasurement | ADC measurement |
| 0x9001 | TestPMW3816 | PMW3816 sensor test |

---

## HID++ 1.0 Register Protocol (Receivers)

Used for Unifying and Bolt receivers.

### Commands

| Command | Description |
|---------|-------------|
| `read_receiver_connection_state` | Check receiver connection |
| `set_receiver_connection_state` | Open/close pairing mode |
| `read_receiver_paired_device_name` | Get paired device name |
| `read_pairing_info` | Read pairing information |
| `ble_pro_read_pairing_info` | BLE Pro pairing info |
| `read_dfu_control` / `set_dfu_control` | DFU control |

### Error Codes

```
Hpp10Success, Hpp10Busy, Hpp10AlreadyExists, Hpp10ConnectFail,
Hpp10InvalidAddress, Hpp10InvalidParamValue, Hpp10InvalidSubid,
Hpp10InvalidValue, Hpp10RequestUnavailable, Hpp10ResourceError,
Hpp10TooManyDevices, Hpp10UnknownDevice, Hpp10UnknownError,
Hpp10WrongPinCode
```

---

## SmartShift Detail (0x2110 / 0x2111)

```
Settings: {
    mode: int,          // scroll mode
    sensitivity: int,   // 0-100
    enabled: bool,
    autoDisengage: int, // auto-disengage threshold
    tunableTorque: int  // torque value (0x2111 only)
}

Validation:
    scrollForce:  range [1..100]
    sensitivity:  range [0..100]

Info fields:
    has_tunable_torque, auto_disengage_default,
    default_tunable_torque, max_force
```

---

## Centurion Protocol

Separate protocol stack for wired Centurion devices (USB-wired gaming/webcam peripherals):

| Feature | Description |
|---------|-------------|
| 0x0100 | DeviceInfo |
| 0x0101 | DeviceName |
| 0x0102 | Root |
| 0x0103 | FeatureSet + Memfault |
| 0x0104 | BatterySOC |
| 0x0003 | CentPPBridge |

---

## Key Features for MX Master 3S (modelId: 2b034)

Based on device capabilities:

| Feature | ID | Usage |
|---------|----|-------|
| UnifiedBattery | 0x1004 | Battery level, charging state |
| SpecialKeys v4 | 0x1B04 | Remap 5 buttons (CIDs: 82, 83, 86, 195, 196) |
| SmartShift v2 | 0x2111 | Scroll wheel mode with tunable torque |
| AdjustableDPI | 0x2201 | DPI settings |
| HiResWheel | 0x2121 | Hi-res scrolling |
| Thumbwheel | 0x2150 | Horizontal scroll wheel |
| ChangeHost | 0x1814 | Easy-Switch between 3 hosts |
| HostsInfos | 0x1815 | Host names and connection info |
| HapticFeedback | 0x19B0 | Scroll wheel haptics |

## Key Features for MX Keys Mini (modelId: 2b369)

| Feature | ID | Usage |
|---------|----|-------|
| UnifiedBattery | 0x1004 | Battery level |
| KeyboardBacklight v3 | 0x1983 | Backlight control |
| FnInversion | 0x40A2 | Fn key behavior |
| DisableKeys | 0x4521 | Disable specific keys |
| ChangeHost | 0x1814 | Easy-Switch |
| MultiPlatform | 0x4531 | OS layout switching |
