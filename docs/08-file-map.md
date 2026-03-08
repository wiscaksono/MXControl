# 08 - File Map

Complete inventory of Logi Options+ files on disk.

---

## Application Bundles

| Path | Bundle ID | Description |
|------|-----------|-------------|
| `/Applications/logioptionsplus.app` | `com.logi.optionsplus` | Main Electron UI |
| `/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app` | `com.logi.cp-dev-mgr` | Device management agent |
| `...agent.app/Contents/Frameworks/logioptionsplus_updater.app` | `com.logi.optionsplus.updater` | Auto-updater (nested in agent) |
| `/Library/Application Support/Logitech.localized/LogiOptionsPlus/logi_ai_prompt_builder/Logi AI Prompt Builder.app` | `com.logitech.logiaipromptbuilder` | AI text assistant (Flutter) |
| `/Library/Application Support/Logitech.localized/LogiRightSightForWebcams/LogiRightSight.app` | `com.logitech.LogiRightSight` | Webcam AI framing |
| `/Applications/LogiFree.app` | `com.logifree.app` | Lightweight BLE/HID utility |

---

## Launch Configs

```
/Library/LaunchAgents/com.logi.optionsplus.plist            -> Agent (user, at login)
/Library/LaunchDaemons/com.logi.optionsplus.updater.plist   -> Updater (root, always)
/Library/LaunchAgents/com.logitech.LogiRightSight.Agent.plist -> RightSight (USB trigger)
```

---

## Agent Data Files

Base: `/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app/Contents/Resources/data/`

```
applications.json                    # 11,640 lines - app-specific shortcuts
DeviceCompatibility.json             # Device pairing/DFU compatibility
options_devices.json                 # Legacy device catalog (13 devices)
guru_devices.json                    # Additional device catalog
firmware.pem                         # Firmware signing certificate
logitech-lap-public.pem             # Logitech public key

defaults/
  defaults_control_osx.json          # 2,469 lines - default button mappings
  defaults_control_win.json          # 2,408 lines
  defaults_slot_osx.json             # 1,384 lines - default slot mappings
  defaults_slot_win.json             # 1,238 lines

macros/
  predefined_osx.json                # 7,291 lines - predefined macro recipes
  predefined_win.json
  common_application_cards_osx.json  # Common app action cards
  common_application_cards_win.json
  devices_predefined_map_osx.json    # Device-to-macro mapping
  devices_predefined_map_win.json
  extended_application_cards_map_osx.json
  extended_application_cards_map_win.json

overlay/                             # OSD notification resources + icons
strings/                             # 18 language YAML files (en-US.yaml, etc.)
migration/                           # Settings migration from older Logi Options
rap/                                 # Recommendation engine data
tray/icons/mute_icon.png
tray_osx.icns
```

---

## System-Level Config

```
/Library/Application Support/Logitech.localized/LogiOptionsPlus/
  app_permissions.json               # Feature flags (analytics, flow, SSO, etc.)
  card_presets/
    card_presets_osx.json            # 6,308 lines - action card presets
    card_presets_virtual_device.json
    card_presets_logi_ai_prompt_builder.json
  Plugins/                           # Adobe integration plugins
    AIP/                             # Adobe Illustrator
    CEP/                             # Common Extensibility Platform
    UXP/                             # Unified Extensibility Platform
    ExManCmd_Mac/                    # Extension Manager CLI
    LightroomClassic/                # Lightroom Classic
    PlugInInstallerUtility           # Plugin installer binary
    public.pem                       # Plugin verification key
  integrations/
    plugin_illustrator/
    plugin_indesign/
    plugin_lightroom_classic/
    plugin_photoshop/
    plugin_premiere_pro/
```

---

## Updater Data

```
/Library/Application Support/Logi/LogiOptionsPlus/
  current.json                       # Current install manifest
  devices.json                       # 23,747 lines - MASTER device database
  features_cache.json                # Cached feature flags
  groups.json
  installation.json                  # File manifest with SHA256 hashes
  keys.json
  next.json
  periodic_check.json
  cache/
  depots/                            # Downloaded update depots
```

---

## User Data

```
~/Library/Application Support/LogiOptionsPlus/
  config.json                        # App settings (window pos, onboarding)
  cc_config.json                     # Creative Console config + 40+ feature flags
  permissions.json                   # {"macOSPermissionsGranted": true}
  settings.db                        # SQLite - ALL user settings (76KB JSON blob)
  macros.db                          # SQLite - macro definitions
  logi_voice_settings.db             # SQLite - voice/dictation settings
  privacy_settings.db                # SQLite - privacy preferences
  CrossSupportedDevices.json
  Cookies / Cookies-journal          # Electron cookies
  DIPS                               # Data integrity
  Preferences                        # Electron preferences
  flow/                              # Logitech Flow data
  dfu/                               # Firmware update storage
  devio_cache/                       # Device I/O cache
  icon_cache/                        # Icon asset cache
  blob_storage/
  Cache/ / Code Cache/ / GPUCache/
  DawnGraphiteCache/ / DawnWebGPUCache/
  IndexedDB/
  Local Storage/ / Session Storage/ / WebStorage/
  Network Persistent State
  Shared Dictionary/ / SharedStorage
  TransportSecurity
  Trust Tokens / Trust Tokens-journal
```

---

## Plugin Service Data

```
~/Library/Application Support/Logi/LogiPluginService/
  Applications/
    Loupedeck70/ / Loupedeck71/ / Loupedeck72/
  Applications.Backups/
  LogiPluginService.lock
  Logs/
  LoupedeckSettings.ini
  Media/
  Temp/
```

---

## Preferences (plists)

```
~/Library/Preferences/
  com.logi.optionsplus.plist              # UI direction, fullscreen
  com.logi.cp-dev-mgr.plist              # Agent preferences (empty)
  com.logi.lps.settings.plist            # Plugin service settings
  com.logi.optionsplus.driverhost.plist  # Driver host settings
  com.logi.pluginservice.plist           # Plugin service visibility
  com.logitech.logiaipromptbuilder.plist # AI prompt builder settings
  com.logifree.app.plist                 # LogiFree BLE peripherals
```

---

## Analytics / Logs

```
/Library/Application Support/Logi/.logishrd/LogiOptionsPlus/
  analytics_stash_app_events/
  analytics/

~/Library/Caches/com.logi.optionsplus.installer/
  io.sentry/                             # Sentry crash reporting cache

~/Library/Logs/xlog_logitech/            # Logging target (empty)

/tmp/logi.optionsplus.updater.log        # Updater stderr log

~/Library/HTTPStorages/LogiPluginServiceNative/  # SQLite HTTP storage
```

---

## Runtime Sockets

```
/tmp/logitech_kiros_agent-{MD5(username)}      # Main agent socket
/tmp/logitech_kiros_logivoice-{MD5(username)}  # Voice agent socket
/tmp/LogiPluginService                          # Plugin service socket
/tmp/logitech_kiros_updater                     # Updater socket (root)
```

---

## Electron App Contents

```
/Applications/logioptionsplus.app/Contents/
  MacOS/logioptionsplus                  # Main Electron binary
  Resources/
    app.asar                             # Bundled Electron app (React + Redux)
    loadBackend.sh                       # Start agent via launchctl
    unloadBackend.sh                     # Stop agent via launchctl
    electron.icns                        # App icon
    icon_kiros.png                       # Kiros icon
    22 localization .lproj/ dirs
  Frameworks/
    Electron Framework.framework/
    logioptionsplus Helper.app/
    logioptionsplus Helper (GPU).app/
    logioptionsplus Helper (Renderer).app/
    logioptionsplus Helper (Plugin).app/
    Squirrel.framework/                  # Auto-updater
    Mantle.framework/                    # ObjC model layer
    ReactiveObjC.framework/              # Reactive extensions
```

---

## Key Files for Swift Native App

If building a Swift app that talks to the existing agent:

1. **Read**: `~/Library/Application Support/LogiOptionsPlus/settings.db` (user settings)
2. **Read**: `/Library/Application Support/Logi/LogiOptionsPlus/devices.json` (device catalog)
3. **Read**: `card_presets_osx.json` (available actions)
4. **Connect**: `/tmp/logitech_kiros_agent-{MD5(username)}` (agent socket)
5. **Reference**: `defaults_control_osx.json` + `defaults_slot_osx.json` (default mappings)

If building a fully standalone Swift app (bypassing agent):

1. **Use**: IOKit.framework for USB HID (vendor 0x046D)
2. **Use**: CoreBluetooth.framework for BLE (service UUID `00010000-...046D`)
3. **Implement**: HID++ 2.0 protocol (see `03-hidpp-protocol.md`)
4. **Store**: Settings in your own CoreData/SQLite/UserDefaults
