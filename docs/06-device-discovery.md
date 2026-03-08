# 06 - Device Discovery

How the agent finds and connects to Logitech devices.

---

## Three Discovery Paths

### 1. USB HID (IOKit)

Direct USB connection or via Unifying/Bolt receiver.

**Framework**: `IOKit.framework` -> `IOHIDManager`

**Matching criteria**: Vendor ID `0x046D` (Logitech)

**Callbacks**:
```
devio::MacOSBus::deviceMatchingCallback(void*, IOReturn, void*, IOHIDDeviceRef)
devio::MacOSBus::deviceRemovalCallback(void*, IOReturn, void*, IOHIDDeviceRef)
```

**Properties read from IOKit**:
```
kIOHIDVendorIDKey          -> Vendor ID (must be 0x046D)
kIOHIDProductIDKey         -> Product ID (used to identify device model)
kIOHIDTransportKey         -> Transport type (USB, Bluetooth)
kIOHIDLocationIDKey        -> USB location for unique identification
kIOHIDProductKey           -> Product name string
kIOHIDVersionNumberKey     -> HID version
kIOHIDMaxInputReportSizeKey   -> Max input report size
kIOHIDMaxOutputReportSizeKey  -> Max output report size
```

**Device communication**:
```
IOHIDDeviceOpen(hidDeviceRef, kIOHIDOptionsTypeNone)
IOHIDDeviceSetReport(hidDeviceRef, type, reportID, report, reportLength)
IOHIDDeviceRegisterInputReportCallback(hidDeviceRef, report, reportLength, callback, context)
```

**Swift equivalent (IOKit HID)**:
```swift
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x046D
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
```

### 2. BLE (CoreBluetooth)

Direct BLE connection to modern Logitech devices.

**Framework**: `CoreBluetooth.framework`

**Logitech BLE Service UUIDs**:
```
00010000-0000-1000-8000-011F2000046D    HID++ data (primary)
00010001-0000-1000-8000-011F2000046D    HID++ data (alt)
00050000-0000-1000-8000-011F2000046D    Control channel
00050001-0000-1000-8000-011F2000046D    Control channel (alt)
```

**Class**: `devio::BleppBus`

**Callbacks**:
```
on_device_discover        -> Device found during scan
on_device_connect         -> BLE connection established
on_device_disconnect      -> BLE connection lost
on_device_blepp           -> HID++ data received via BLE
on_device_pnp_id          -> PnP ID characteristic read
on_device_serial          -> Serial number characteristic read
on_device_did_write       -> Write to device completed
on_device_fail_to_connect -> Connection attempt failed
complete_peripheral       -> All services/characteristics discovered
```

**Flow**:
```
1. CBCentralManager.scanForPeripherals(withServices: logiServiceUUIDs)
2. centralManager:didDiscover:peripheral -> on_device_discover
3. centralManager.connect(peripheral)
4. centralManager:didConnect: -> discoverServices
5. peripheral:didDiscoverServices: -> discoverCharacteristics
6. peripheral:didDiscoverCharacteristicsForService:
7. peripheral.setNotifyValue(true, for: hidppCharacteristic)
8. peripheral:didUpdateValueForCharacteristic: -> on_device_blepp (HID++ data)
9. Write HID++: peripheral.writeValue(data, for: characteristic, type: .withResponse)
```

**Swift equivalent**:
```swift
let logiServiceUUID = CBUUID(string: "00010000-0000-1000-8000-011F2000046D")
centralManager.scanForPeripherals(withServices: [logiServiceUUID])
```

### 3. Unifying / Bolt Receiver (USB HID + DJ Protocol)

Logitech wireless receivers that pair multiple devices.

**Receiver PIDs**:
| PID | Type |
|-----|------|
| `0xC52B` | Unifying Receiver |
| `0xC548` | Bolt Receiver |

**Transport types**:
```
EQuad              - Standard wireless
EQuadGamepad       - Gamepad wireless
EQuadHighReportRate - High report rate wireless
EQuadLite          - Lite wireless
BLE_PRO            - BLE Pro (Bolt)
```

**Receiver operations**:
```
enable_receiver_notifications    -> Enable device connect/disconnect events
enumerate_devices (5 stages)     -> Discover paired devices
connect_to_receiver              -> Establish receiver communication
detect_unpairings                -> Monitor for device removal
```

**Receiver interfaces** (HID++ 1.0 registers):
```
Receiver_Discovery      -> Device discovery
Receiver_Locking        -> Pairing lock state
Receiver_Pairing        -> Pair new device
Receiver_PairingState   -> Current pairing status
Receiver_PassKeyEntry   -> Bluetooth passkey entry
Receiver_PassKeyDisplay -> Bluetooth passkey display
Receiver_Recovery       -> Error recovery
Receiver_Advertise      -> BLE advertising control
Receiver_BleProPairingInfo -> BLE Pro pairing info
Receiver_Enumerate      -> Enumerate paired devices
```

---

## Marconi Protocol (Flow / Cross-Computer)

For Logitech Flow (cross-computer mouse/keyboard sharing):

**Discovery**: LAN broadcast-based discovery

**Packet types**:
```
BeaconPacket           -> Announce presence on network
PingPacket             -> Connectivity check
HeartbeatPacket        -> Keep-alive
ClientHelloPacket      -> Initiate connection
ServerHelloPacket      -> Accept connection
ClientDeviceConnectPacket -> Connect device to remote host
ServerDeviceConnectPacket -> Acknowledge device connection
DeviceDataPacket       -> Forward device data (mouse/keyboard events)
DeviceErrorPacket      -> Error notification
GlobalDataPacket       -> Clipboard/file transfer data
InitiateDiscoveryPacket -> Start discovery
PromoteConnectionPacket -> Promote to primary connection
```

**Source path**: `logi/marconi/lib/marconi/src/`

---

## HIDIO Layer (HID Input/Output)

Separate from HID++, used for raw USB HID and webcam devices:

**macOS implementations**:
```
enumerator_hid_device_impl_osx       -> Generic HID device enumeration
enumerator_hid_mouse_device_impl_osx -> Mouse-specific HID enumeration
enumerator_raw_hid_device_impl_osx   -> Raw HID device enumeration
enumerator_raw_usb_device_impl_osx   -> Raw USB device enumeration
hid_device_impl_osx                  -> HID device communication
hidio_manager                        -> Central manager for all HID I/O
```

---

## Device Identification Flow

```
1. USB/BLE device detected (IOHIDManager callback or CBCentralManager)
2. Read Vendor ID (must be 0x046D) + Product ID
3. Determine device type:
   a. Direct device (PID matches known device)
   b. Receiver (PID = 0xC52B or 0xC548) -> enumerate sub-devices
4. HID++ 2.0 probe:
   a. Ping (feature 0x0000, function 1) -> verify HID++ 2.0 support
   b. GetProtocolVersion -> determine protocol version
   c. GetFeature(0x0001) -> get FeatureSet index
   d. Enumerate all features
5. Read device info:
   a. Feature 0x0003 -> Firmware version
   b. Feature 0x0005 -> Device name and type
   c. Feature 0x1004 -> Battery status
   d. Feature 0x1815 -> Host info
6. Match PID to devices.json catalog for full capabilities
7. Load user settings from settings.db
8. Apply profile assignments (button remaps, DPI, etc.)
```

---

## Known Product IDs (from binary)

Hardcoded PIDs found in the agent:
```
HID_046d_0919, HID_046d_091d, HID_046d_0943,
HID_046d_0944, HID_046d_0946
```

Special handling: `"using legacy HID++ collection for special pid 0x5800"`

The full PID database is in `devices.json` under each device's `modes[].interfaces[].id` field (format: `046d_XXXX`).
