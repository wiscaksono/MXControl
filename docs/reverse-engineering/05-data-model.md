# 05 - Data Model

How Logi Options+ structures its data: devices, profiles, cards, macros, and settings.

---

## Device Model

Each device in `devices.json` has this structure:

```json
{
    "modelId": "2b034",
    "displayName": "MX Master 3S",
    "extendedDisplayName": "Wireless Mouse MX Master 3S",
    "type": "MOUSE",
    "depot": "mx_master_3s",
    "slotPrefix": "mx-master-3s-2b034",
    "thumbnail": "pipeline://logioptionsplus/thumbnails/mx_master_3s.png",
    "supportPageId": "D217",
    "isPredefinedProfilesEnabled": true,
    "capabilities": {
        "flow": { "hostCount": 3 },
        "hasBatteryStatus": true,
        "pointerSpeed": true,
        "fnInversion": true,
        "disableKeys": true,
        "hostInfos": true,
        "unified_battery": false,
        "is_action_ring_supported_device": true,
        "specialKeys": {
            "programmable": [82, 83, 86, 195, 196]
        },
        "scroll_wheel_capabilities": {
            "adjustable_speed": true,
            "high_resolution": true,
            "smartshift": true,
            "smooth_scroll": true,
            "virtual_thumbwheel": true
        },
        "mouseScrollWheelOverride": {
            "dir": "...", "isSmooth": true,
            "smartshift": { "is_enabled": true, "mode": 1, "scroll_force": 50, "sensitivity": 50 },
            "speed": 50
        },
        "mouseThumbWheelOverride": {
            "dir": "...", "isSmooth": true, "speed": 50
        },
        "backlightSettingsOverride": { "enabled": true, "power_save": true }
    },
    "modes": [{
        "interfaces": [{
            "id": "046d_4082",
            "type": "DEVIO",
            "derivatives": [...]
        }]
    }],
    "supportedApps": [
        "application_id_adobe_photoshop",
        "application_id_google_chrome",
        "..."
    ],
    "comboDevices": [{ "modelId": "10000000", "considerForOnboarding": false }]
}
```

### Device Types

```
MOUSE, KEYBOARD, TOUCHPAD, PRESENTER, HEADSET, WEBCAM, RECEIVER
```

### Special Key CIDs (Control IDs) for MX Master 3S

| CID | Default Assignment |
|-----|-------------------|
| 82 | Middle button |
| 83 | Back |
| 86 | Forward |
| 195 | Gesture button |
| 196 | Mode shift (ratchet/free-spin toggle) |

---

## Profile System

### Hierarchy

```
Profile (application-specific or Desktop)
  └── Slots (device buttons/controls)
        └── Cards (assigned actions)
              └── Macros (action definitions)
```

### Profile

```json
{
    "id": "420fd454-0c36-499d-bde4-146823b16147",
    "name": "Desktop",
    "application_id": "420fd454-0c36-499d-bde4-146823b16147",
    "base_profile_id": null,
    "slots": [...]
}
```

- Desktop profile UUID: `420fd454-0c36-499d-bde4-146823b16147` (always this UUID)
- Application-specific profiles use the `applicationId` from `applications.json`

### Slot

A slot represents a physical control on the device:

```json
{
    "id": "mx-master-3s-2b034_thumb_wheel_adapter",
    "name": "Thumb Wheel"
}
```

Slot IDs follow pattern: `{slotPrefix}_{control_name}`

### Card (Action)

Cards define what happens when a control is activated:

```json
{
    "id": "card_global_presets_osx_back",
    "name": "ASSIGNMENT_NAME_OSX_BACK",
    "attribute": "MACRO_PLAYBACK",
    "continuous": false,
    "readOnly": true,
    "tags": ["PRESET_TAG_BUTTON"],
    "macro": {
        "type": "KEYSTROKE",
        "actionName": "Cmd + [",
        "keystroke": {
            "code": 47,
            "modifiers": [227],
            "virtualKeyId": "VK_OPEN_BRACKET"
        }
    }
}
```

### Card Attributes

```
MACRO_PLAYBACK         - Single action (keystroke, media, system)
ADAPTER_CROWN          - Crown/dial rotary control (has nestedCards)
ADAPTER_GESTURE        - Gesture-based (has nestedCards for up/down/left/right)
ADAPTER_THUMB_WHEEL    - Thumb wheel adapter
```

### Nested Cards (for rotary/gesture controls)

```json
{
    "nestedCards": {
        "turn_right": { "macro": { "type": "MEDIA", "media": { "usage": "VOLUME_UP" } } },
        "turn_left": { "macro": { "type": "MEDIA", "media": { "usage": "VOLUME_DOWN" } } },
        "press_turn_right": { "macro": { "type": "MEDIA", "media": { "usage": "NEXT_TRACK" } } },
        "press_turn_left": { "macro": { "type": "MEDIA", "media": { "usage": "PREVIOUS_TRACK" } } },
        "press": { "macro": { "type": "SYSTEM", "system": { "action": "SHOW_RADIAL_MENU" } } }
    }
}
```

---

## Macro Types

| Type | Structure | Description |
|------|-----------|-------------|
| `KEYSTROKE` | `{ code, modifiers[], virtualKeyId }` | Single key combo |
| `MEDIA` | `{ usage: "VOLUME_UP" }` | Media key |
| `SYSTEM` | `{ action: "MISSION_CONTROL" }` | System action |
| `DELAY` | `{ durationMs: 1000 }` | Wait |
| `TEXT_BLOCK` | `{ text: "..." }` | Type text string |
| `INPUT_SEQUENCE` | `{ componentLists: [...] }` | Key press/release sequence |
| `APP_WINDOWS_MANAGEMENT` | `{ action: "BRING_TO_FOREGROUND" }` | App window management |
| `MOUSE` | `{ button, action }` | Mouse click |
| `DPI` | `{ ... }` | DPI change |
| `SCREEN_CAPTURE` | `{ ... }` | Screenshot |
| `LIGHTING` | `{ ... }` | Lighting control |
| `LPS_ACTION` | `{ ... }` | Plugin service action |
| `QUICK_LAUNCH` | `{ ... }` | Quick launch app |
| `AUDIO` | `{ ... }` | Audio control |
| `ARTIFICIAL_INTELLIGENCE` | `{ ... }` | AI prompt builder |

### System Actions

```
MISSION_CONTROL, APP_EXPOSE, LAUNCHPAD, SHOW_DESKTOP,
LOCK_SCREEN, SCREENSHOT_MENU, LAUNCH_SIRI, DO_NOT_DISTURB,
OPEN_FINDER, SMART_ZOOM, SWITCH_APPS, SHOW_RADIAL_MENU,
EMOJI_MENU, DICTATION, NOTIFICATION_CENTER, LOOK_UP
```

### Media Usages

```
VOLUME_UP, VOLUME_DOWN, MUTE, PLAY_PAUSE,
NEXT_TRACK, PREVIOUS_TRACK, STOP, EJECT
```

### Modifier Keycodes

```
224 = Left Control
225 = Left Shift
226 = Left Alt/Option
227 = Left Command (GUI)
228 = Right Control
229 = Right Shift
230 = Right Alt/Option
231 = Right Command (GUI)
```

---

## Predefined Macros

Multi-step sequences with categories and regional targeting:

```json
{
    "id": "macros_preset_iqiyi_break",
    "name": "MACRO_NAME_IQIYI_BREAK",
    "state": "ACTIVE",
    "originType": "PREDEFINED",
    "categories": ["LEISURE"],
    "specific_regions": ["CN", "HK"],
    "cards": [
        { "macro": { "type": "APP_WINDOWS_MANAGEMENT", "appWindowsManagement": { "action": "BRING_TO_FOREGROUND" } } },
        { "macro": { "type": "DELAY", "delay": { "durationMs": 1000 } } },
        { "macro": { "type": "KEYSTROKE", "actionName": "Cmd + T", "keystroke": { "code": 23, "modifiers": [227] } } },
        { "macro": { "type": "TEXT_BLOCK", "textBlock": { "text": "https://www.iq.com/" } } },
        { "macro": { "type": "DELAY", "delay": { "durationMs": 1000 } } },
        { "macro": { "type": "INPUT_SEQUENCE", "inputSequence": { "componentLists": [...] } } }
    ]
}
```

### Macro Categories

```
LEISURE, AI, PRODUCTIVITY, COMMUNICATION, NAVIGATION, MEDIA, CUSTOM
```

---

## Application Detection

Apps are detected by bundle path on macOS:

```json
{
    "applicationId": "application_id_google_chrome",
    "name": "Google Chrome",
    "detection": [
        { "osxBundle": { "bundlePath": "/Applications/Google Chrome.app/" } }
    ],
    "poster_url": "pipeline://logioptionsplus/applications/chrome_poster.png",
    "cards": [...]
}
```

---

## Settings Storage

### settings.db (SQLite)

```sql
CREATE TABLE data(
    _id INTEGER PRIMARY KEY,
    _date_created datetime default current_timestamp,
    file BLOB NOT NULL    -- JSON blob containing ALL user settings
);
CREATE TABLE snapshots(
    _id INTEGER PRIMARY KEY,
    _date_created datetime default current_timestamp,
    uuid TEXT NOT NULL,
    label TEXT NOT NULL,
    file BLOB NOT NULL
);
```

The `data` table has exactly 1 row. The `file` column is a 76KB JSON blob with top-level keys:

| Key Pattern | Description |
|-------------|-------------|
| `accounts_*` | Account/SSO info |
| `analytics*` | Analytics config |
| `applications` | Detected installed apps |
| `battery/{slotPrefix}/warning_notification` | Battery warning state |
| `brand` | "Logitech" |
| `dfu/{serial}/*` | Firmware info per device |
| `easy_switch` | Multi-host pairing config |
| `ever_connected_devices` | All devices ever connected |
| `profile-{uuid}` | Complete profile with all assignments |
| `profile_keys` | List of profile UUIDs |
| `schema_version` | Currently 21 |
| `slot_prefixes_ever_seen` | All device slot prefixes |
| `theme` | "DARK_MODE" or "LIGHT_MODE" |
| `use_system_theme` | boolean |
| `iconsLocalPathCache` | Cached icon paths (106 entries) |

### macros.db (SQLite)

Stores user-created macro definitions. Same schema pattern.

### config.json

```json
{
    "settings": {
        "accountLoginOpened": true,
        "appOnboardingOpened": true,
        "onboardedDevices": ["2b034", "10000000", "2b369"],
        "browserWindowSettings": { "width": 1518, "height": 860, "x": 1159, "y": 290 },
        "isSentryEnabled": false,
        "appAlreadyInstalled": true,
        "aiOnboardingCompleted": true,
        "lastSeenNewUpdateVersion": "2.0.848900"
    }
}
```

### cc_config.json

Contains Creative Console config, feature flags (40+), host ID, and device info. See `08-file-map.md` for full path.

---

## Default Assignments

Stored in `defaults_control_osx.json` and `defaults_slot_osx.json`:

### Control Defaults (by CID)

| CID | Default Card |
|-----|-------------|
| 82 | `card_global_presets_middle_button` |
| 83 | `card_global_presets_osx_back` |
| 86 | `card_global_presets_osx_forward` |
| 89 | `card_global_presets_osx_mission_control` |
| 94 | `card_global_presets_osx_smart_zoom` |
| 195 | `card_global_presets_one_of_gesture_button` |
| 196 | `card_global_presets_mode_shift` |
| 1-6 | Volume/media transport keys |

### Slot Defaults (by slot ID)

| Slot | Default Card |
|------|-------------|
| `mx-master-3*_thumb_wheel_adapter` | `card_global_presets_osx_horizontal_scroll` |
| `mx-keys-mini*_crown_adapter` | `card_global_presets_media_control_crown` |

### Per-App Overrides

Photoshop example:
| Slot | Card |
|------|------|
| `mx-master-3s*_thumb_wheel_adapter` | `card_photoshop_brushSize` |

---

## Connected Devices (Current System)

| Device | Model ID | Serial | Slot Prefix | Firmware |
|--------|----------|--------|-------------|----------|
| MX Master 3S | 2b034 | 2323LZ53QUB8 | mx-master-3s-2b034 | v22.1.6 |
| MX Keys Mini | 2b369 | 2222CE301A48 | mx-keys-mini-2b369 | v73.4.16 |
| Radial Menu (virtual) | 10000000 | - | radial-menu-virtual-device-10000000 | - |
| Software Events (virtual) | 10000001 | - | software-events-virtual-device-10000001 | - |

### Easy-Switch Hosts

| Host | OS | Name |
|------|----|------|
| 1 | Windows 11 | WISCAKSONO |
| 2 | macOS 26.3.1 | MacBook Pro M3 |
| 3 | iPadOS | Wisnu's iPad |
