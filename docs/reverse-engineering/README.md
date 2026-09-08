# Logi Options+ Reverse Engineering

Reverse engineered from Logi Options+ v2.0.848900 on macOS. Internal codename: **Kiros**.

---

## Documents

| File | Content |
|------|---------|
| [01-architecture.md](01-architecture.md) | System diagram, binaries, launch config, entitlements |
| [02-socket-protocols.md](02-socket-protocols.md) | Wire protocols (Protocol A + LogiConn), FNV hash, JSON message format |
| [03-hidpp-protocol.md](03-hidpp-protocol.md) | HID++ 2.0 feature map (97+ features), report format, key remapping |
| [04-agent-api.md](04-agent-api.md) | 400+ REST-like API routes with verbs and subscription markers |
| [05-data-model.md](05-data-model.md) | Device registry, profiles, cards, macros, settings storage |
| [06-device-discovery.md](06-device-discovery.md) | USB (IOKit), BLE (CoreBluetooth), Unifying/Bolt receivers |
| [07-protobuf-schema.md](07-protobuf-schema.md) | 64 proto files, all message types and fields |
| [08-file-map.md](08-file-map.md) | Complete file/path inventory on disk |

---

## Quick Reference

### Connect to agent (simplest approach)

```swift
import Foundation
import CryptoKit

// 1. Compute socket path
let username = NSUserName()
let hash = Insecure.MD5.hash(data: username.data(using: .utf8)!)
    .map { String(format: "%02x", $0) }.joined()
let socketPath = "/tmp/logitech_kiros_agent-\(hash)"

// 2. Connect Unix domain socket
// 3. Send Protocol A frame (see 02-socket-protocols.md)
// 4. Send JSON: { "verb": "GET", "path": "/devices/list", "msgId": "1" }
```

### Protocol A frame (sending)

```
[4 bytes LE: inner_size] [4 bytes BE: 4] ["json"] [4 bytes BE: payload_len] [JSON payload]
where inner_size = 4 + 4 + payload_len + 8
```

### Key API routes

```
GET /devices/list                    -> All connected devices
GET /battery/{device_id}/state       -> Battery level
GET /mouse/{device_id}/info          -> Mouse DPI, speed, etc.
SET /mouse_settings/configure        -> Change mouse settings
GET /smartshift/{device_id}/params   -> SmartShift settings
SET /backlight_settings/configure    -> Keyboard backlight
GET /v2/profiles/slice               -> User profiles & assignments
GET /hosts_info/{device_id}/current  -> Easy-Switch host info
GET /routes                          -> Self-documenting: lists ALL routes
```

### Two approaches for a native Swift app

**Approach A: Client to existing agent** (recommended to start)
- Connect to Unix socket, send JSON messages
- Reuse all device management, HID++ handling from agent
- Just build a SwiftUI frontend
- See: `02-socket-protocols.md`, `04-agent-api.md`

**Approach B: Standalone (bypass agent entirely)**
- IOKit HID for USB devices (vendor 0x046D)
- CoreBluetooth for BLE (service `00010000-0000-1000-8000-011F2000046D`)
- Implement HID++ 2.0 protocol yourself
- See: `03-hidpp-protocol.md`, `06-device-discovery.md`

### Current devices on this system

| Device | Model ID | Slot Prefix |
|--------|----------|-------------|
| MX Master 3S | 2b034 | mx-master-3s-2b034 |
| MX Keys Mini | 2b369 | mx-keys-mini-2b369 |

3 Easy-Switch hosts: WISCAKSONO (Win11), MacBook Pro M3 (macOS), Wisnu's iPad
