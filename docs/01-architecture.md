# 01 - Architecture Overview

> Logi Options+ v2.0.848900 on macOS. Internal codename: **Kiros**.

## System Diagram

```
┌──────────────────────────────────────────────────────────┐
│  Electron UI  (com.logi.optionsplus)                     │
│  /Applications/logioptionsplus.app                       │
│  - React 18 + Redux + TypeScript                         │
│  - 3 windows: Main, Creative Console (CC), Marketplace   │
│  - Renderer: app.min.js (10MB), cc.min.js (9MB)          │
│  - Main process: main.js (1MB)                           │
└──────┬──────────────────┬──────────────────┬─────────────┘
       │ Unix Socket      │ Unix Socket      │ Unix Socket
       │ Protocol A       │ Protocol A       │ Protocol B (LogiConn)
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌───────────────────┐
│ Agent        │  │ LogiVoice    │  │ LogiPluginService  │
│ (Qt5/C++)    │  │ (Dictation)  │  │ (Loupedeck/CC)     │
│ com.logi.    │  │              │  │                     │
│ cp-dev-mgr   │  │              │  │                     │
└──────┬───────┘  └──────────────┘  └───────────────────┘
       │
       │ IOKit HID + CoreBluetooth + IOBluetooth
       ▼
┌──────────────────────────────────┐
│  Logitech Devices (HID++ 2.0)   │
│  - USB HID (direct)             │
│  - BLE GATT (direct)            │
│  - Unifying/Bolt Receiver (USB) │
└──────────────────────────────────┘
```

## Key Binaries

| Binary | Bundle ID | Tech Stack | Role |
|--------|-----------|------------|------|
| `logioptionsplus` | `com.logi.optionsplus` | Electron 39.1.2 | UI frontend |
| `logioptionsplus_agent` | `com.logi.cp-dev-mgr` | Qt 5.15 C++ | Device management daemon |
| `logioptionsplus_updater` | `com.logi.optionsplus.updater` | Native C++ | Auto-update daemon (runs as root) |
| `Logi AI Prompt Builder` | `com.logitech.logiaipromptbuilder` | Flutter | AI text assistant |
| `LogiRightSight` | `com.logitech.LogiRightSight` | Native + OpenCV | Webcam AI framing |
| `LogiFree` | `com.logifree.app` | Native Swift | Lightweight BLE/HID utility |

## Launch Configuration

| Config | Path | Label | Run As |
|--------|------|-------|--------|
| Launch Agent | `/Library/LaunchAgents/com.logi.optionsplus.plist` | `com.logi.cp-dev-mgr` | User (GUI) |
| Launch Daemon | `/Library/LaunchDaemons/com.logi.optionsplus.updater.plist` | `com.logi.optionsplus.updater` | Root |
| Launch Agent | `/Library/LaunchAgents/com.logitech.LogiRightSight.Agent.plist` | `com.logitech.LogiRightSight.Agent` | User (USB trigger) |

The agent starts at login via `launchctl bootstrap gui/$UID`. The Electron app bootstraps/unloads the agent via shell scripts:
- `loadBackend.sh` -> `launchctl bootstrap gui/$UID /Library/LaunchAgents/com.logi.optionsplus.plist`
- `unloadBackend.sh` -> `launchctl bootout gui/$UID /Library/LaunchAgents/com.logi.optionsplus.plist`

## Agent Entitlements

```
com.apple.developer.hid.virtual.device = true    # Can create virtual HID devices
com.apple.security.automation.apple-events = true # Can send AppleEvents
com.apple.security.scripting-targets = [com.microsoft.Word]
keychain-access-groups = [
    QED4VVPZWA.com.logi.cp-dev-mgr,
    QED4VVPZWA.com.logi.optionsplus.shared_items
]
```

## Agent Linked Frameworks

Key frameworks the agent binary links against:

- **IOKit.framework** — USB HID device access
- **CoreBluetooth.framework** — BLE communication
- **IOBluetooth.framework** — Classic Bluetooth
- **Security.framework** — TLS, keychain, certificates
- **ApplicationServices.framework** — Accessibility, screen control
- **ScriptingBridge.framework** — AppleScript bridging
- **UserNotifications.framework** — System notifications
- **CoreAudio/AVFoundation** — Audio pipeline
- **CoreMediaIO** — Camera device access
- **Qt5 (5.15.13)** — QtCore, QtNetwork, QtWidgets, QtDBus, QtGui, QtConcurrent

The agent also statically links **OpenSSL** (bundles its own crypto stack) and **Google Protobuf** runtime.

## Three Communication Channels

| Channel | Socket Path (macOS) | Protocol | Reconnect |
|---------|---------------------|----------|-----------|
| Main Agent | `/tmp/logitech_kiros_agent-{MD5(username)}` | Protocol A (simple) | 100ms base |
| Voice | `/tmp/logitech_kiros_logivoice-{MD5(username)}` | Protocol A (simple) | 2s base, 10s max |
| Plugin Service | `/tmp/LogiPluginService` | Protocol B (LogiConn) | 2s base, 10s max |
| Updater | `/tmp/logitech_kiros_updater` | Unknown | Root-owned |

Socket path construction: `"/tmp/" + pipeName + "-" + CryptoJS.MD5(os.userInfo().username).toString()`

## Feature Flags

The system has 40+ feature flags stored in `cc_config.json` and `app_permissions.json`. Key flags:
- `isFlowEnabled`, `isActionsRingEnabled`, `isAIOverlayEnabled`
- `isLogiVoiceEnabled`, `isCCSupportEnabled`
- `isDeviceFirmwareUpdateEnabled`, `isHothDeepIntegrationEnabled`
- `isNewProfilesSystemEnabled`, `isUnifiedProfilesEnabled`

## For Swift Native App

To replace the Electron UI with a native Swift app, you need to:

1. **Connect to the agent's Unix socket** at `/tmp/logitech_kiros_agent-{MD5(username)}`
2. **Implement Protocol A framing** (see `02-socket-protocols.md`)
3. **Send/receive JSON messages** with `{verb, path, msgId, payload}` format
4. **Use the agent's 400+ API routes** (see `04-agent-api.md`) -- no need to reimplement HID++

To fully replace the agent as well (bypass it entirely), you'd need to:
1. **Implement HID++ 2.0** device communication via IOKit/CoreBluetooth
2. **Implement all 97+ HID++ features** (see `03-hidpp-protocol.md`)
3. **Manage device discovery** (see `06-device-discovery.md`)
