# 07 - Protobuf Schema

The agent uses Google Protocol Buffers internally. On the wire (JSON mode), messages are JSON-serialized. These are the embedded .proto definitions and message types.

---

## Proto Files (64 total)

```
logi/protocol/accounts.proto
logi/protocol/analytics.proto
logi/protocol/app_permissions.proto
logi/protocol/application.proto
logi/protocol/applications.proto
logi/protocol/audio.proto
logi/protocol/backlight.proto
logi/protocol/beta_testing.proto
logi/protocol/card_register.proto
logi/protocol/cloud.proto
logi/protocol/coupled_easy_switch_assist.proto
logi/protocol/crown.proto
logi/protocol/devices_support.proto
logi/protocol/devices.proto
logi/protocol/dfu.proto
logi/protocol/diagnostic.proto
logi/protocol/disable_keys.proto
logi/protocol/event_tracing_control.proto
logi/protocol/event_tracing.proto
logi/protocol/firmware_lighting.proto
logi/protocol/flow.proto
logi/protocol/force_sensing.proto
logi/protocol/haptics.proto
logi/protocol/highlights.proto
logi/protocol/illumination_light.proto
logi/protocol/input_tracker.proto
logi/protocol/integrations.proto
logi/protocol/keyboard.proto
logi/protocol/lighting_support.proto
logi/protocol/logging.proto
logi/protocol/logioptions.proto
logi/protocol/lps.proto
logi/protocol/lux_report.proto
logi/protocol/macos_security.proto
logi/protocol/macros_categories.proto
logi/protocol/macros.proto
logi/protocol/media.proto
logi/protocol/microphone.proto
logi/protocol/migration.proto
logi/protocol/mouse.proto
logi/protocol/notifications.proto
logi/protocol/offer.proto
logi/protocol/onboard_profiles.proto
logi/protocol/pipl.proto
logi/protocol/presentation_timers.proto
logi/protocol/presentation.proto
logi/protocol/presenter.proto
logi/protocol/radial_menu.proto
logi/protocol/rap.proto
logi/protocol/resources.proto
logi/protocol/right_sight.proto
logi/protocol/scarif.proto
logi/protocol/settings_backup.proto
logi/protocol/siminput.proto
logi/protocol/software_events.proto
logi/protocol/survey.proto
logi/protocol/system_events.proto
logi/protocol/system_settings.proto
logi/protocol/test_gestures.proto
logi/protocol/touchpad.proto
logi/protocol/unified_profiles.proto
logi/protocol/util.proto
logi/protocol/voice.proto
logi/protocol/wireless.proto
logi/common_protocol/crash_reporting.proto
```

---

## Core Message Envelope

### logi.protocol.Message

```protobuf
message Message {
    string msg_id = 1;
    Verb verb = 2;
    string path = 3;
    string origin = 4;
    google.protobuf.Any payload = 5;
    Result result = 6;

    enum Verb {
        INVALID_VERB = 0;
        GET = 1;
        SET = 2;
        SUBSCRIBE = 3;    // rejected on wire - internal only
        UNSUBSCRIBE = 4;  // rejected on wire - internal only
        REMOVE = 5;
        EVENT = 6;
    }
}
```

### logi.protocol.Result

```protobuf
message Result {
    Code code = 1;
    string what = 2;

    enum Code {
        // exact values unknown, but includes:
        // SUCCESS, ERROR, NOT_FOUND, INVALID_PARAMETER, etc.
    }
}
```

### logi.protocol.Routes.Route

```protobuf
message Route {
    string path = 1;
    string endpoint = 2;
    string payload = 3;       // payload type name
    string example_json = 4;  // example JSON for the route
}
```

---

## Utility Types (logi.protocol.util)

```
BoolValue   { bool value }
Color       { HSV hsv; RGBA rgba }
  Color.HSV  { float h, s, v }
  Color.RGBA { float r, g, b, a }
Enable      { bool enabled }
File        { bytes data; string name }
Int         { int32 value }
Number      { double value }
RangeInt    { int32 min; int32 max }
RangeUInt   { uint32 min; uint32 max }
String      { string value }
Time        { int64 timestamp }
URI         { string uri }
```

---

## Device Messages (logi.protocol.devices)

### Device.Info
```
id, display_name, model_id, firmware_version, serial_number,
path, slot_prefix, depot, thumbnail, type, state
```

### Device.Info.Basic
```
id, device_model, device_name, path, depot, slot_prefix
```

### Device.Info.FirmwareInfo
```
build, version, pid1, pid2, pid3, prefix
```

### Device.BatteryStatus
```
level (int), ChargingStatus (enum)
```

### Device.State, Device.Type, Device.Interface
```
Interface { Connection, Data, State, Status, Type }
Disconnect { Reason, secure_input_application }
```

### Device.HostInfo
```
BusType, OSType, Platform, Hosts, HostsNames
```

### Device.Capabilities
```
Flow { hostCount }
HapticForceModelType
LuxReporting
MigrationSupport
SpecialKeys { programmable[] }
```

### Receiver Messages
```
Receiver.Discovery  { Error, State, Status }
Receiver.Locking    { Error, State, Status }
Receiver.Pairing    { AuthenticationMethod, Error }
Receiver.PairingState { State, Error }
Receiver.Advertise  { device_address, name, receiver_id, thumbnail }
Receiver.PassKeyDisplay { passkey }
Receiver.PassKeyEntry { PassKeyCode, TwoButtonAuthNextClick }
Receiver.Recovery
```

---

## Mouse Messages (logi.protocol.mouse)

```
Dpi           { Info, Table, State, Shift, Indicator }
Dpi.Info      { HighResolutionSensor, Levels, Range }
Settings      { ... }
ScrollMode    { ... }
ReportRate    { ... }
PointerSpeed  { PointerSpeedValue }
PrecisionMode { ... }
AngleSnapping { ... }
SmartShiftSettings    { mode, sensitivity, enabled, autoDisengage, tunableTorque }
ScrollWheelSettings   { ... }
ThumbWheelSettings    { ... }
MouseButtonSwap       { SwapState }
VirtualThumbwheel     { ... }
```

---

## Crown Messages (logi.protocol.crown)

```
CrownMode           { RatchetMode }
Settings            { ... }
CrownGestureEvent   { device_id, device_prefix, GestureType }
CrownPressEvent     { ... }
CrownTouchEvent     { State }
CrownTurnEvent      { RotationState }
```

---

## Macro Messages (logi.protocol.macros)

### Macro Types
```
Keystroke, Mouse, Media, App, OpenWebPage, OpenFileFolder,
System, Delay, Sequence, Action, ScreenCapture, Dpi, TextBlock,
AdvancedClick, GHub, Lighting, LpsAction, QuickLaunch, Audio,
Device, DoNothing, MacroWithRules, AppWindowsManagement,
ArtificialIntelligence
```

### Other Macro Types
```
Gesture   { Action, Behavior }
Preset    { CardType, Platform }
InputSequence { componentLists[] }
Status    { State }
TriggerContext { ... }
```

---

## Profile Messages (logi.protocol.profiles_v2)

```
Profile     { id, name, application_id, base_profile_id, Slots }
Card        { id, name, application_id, State, Attribute, NestedCards, Icons, tags }
Assignment  { card_id, slot_id, tags }
Slot        { id, name }
GestureInfo { action_id, Direction, Threshold, Units, AxisInfo }
MacroInfo   { id, name, description, Category, Platform, OriginType }
```

---

## DFU Messages (logi.protocol.dfu)

```
Info           { eligible_version, release_notes }
BdfuState      { ... }
DfuStatus      { Error_Info, Evt_Info, Evt_Type, FW_Type }
Finished       { Result }
FirmwareDownloadConfig { ... }
```

---

## Audio Messages (logi.protocol.audio)

```
Volume          { Channel }
Equalizer       { Device, id, name, source_id, tag, Type }
AudioEndpoint   { audio_id, Flow, Role, friendly_name }
AudioSession    { ... }
Capabilities    { ... }
SurroundSound   { Channel, ChannelVolume, Mode }
DolbySettings   { Mode }
DTSSettings     { DTSVersion, HeadsetRoomPreset, SpeakerRoomPreset, StereoMode }
```

---

## Integration Messages (logi.protocol.integrations)

```
Integration  { guid, name, author, description, icon }
  Action     { action_id, action_icon, name, Parameter, Invoke }
  Event, EventScheme, LaunchType, IntegrationType, ConfigOption
LaunchResult { ProgressType }
PluginInstallerStatus { InstallerStatus, PluginOperation }
SDKIntegration { ... }
```

---

## LPS Messages (logi.protocol.lps)

```
Action       { name, display_name, description, icon, profile_action_type }
PluginInfo   { ... }
PluginStatus { ... }
ScreenInfo   { ... }
Watchdog     { ... }
ErrorCode    { ... }
MessageType  { ... }
Plugin.Event { ... }
```

---

## Loupedeck Messages (logi.protocol.loupedeck)

```
Message        { msg_id, origin, path, Verb }
Action         { device_id, friendly_name, description, macro_id, Type, MacroState }
Result         { Code, what }
LoupedeckDevice { name, uuid, Type }
Routes.Route   { path, endpoint, payload, example_json }
```

---

## Other Message Types

```
logi.protocol.flow.Config          { Arrangement, HostConfig, keyboard_id }
logi.protocol.haptics.Config       { HapticDeviceConfig, HapticEvent, HapticEventSource }
logi.protocol.haptics.Haptics      { HapticProperties, HapticStatus, PlayWaveFormRequest, WaveformId }
logi.protocol.highlights.Laser     { ... }
logi.protocol.highlights.Annotation { ... }
logi.protocol.highlights.Magnifier { ... }
logi.protocol.scarif.Config        { ... }
logi.protocol.scarif.Telemetry     { ... }
logi.protocol.updates.Depot        { ... }
logi.protocol.updates.Key          { ... }
logi.protocol.voice.StringList     { ... }
logi.protocol.firmware_lighting.Effect { Id, Support }
```

---

## Note for Implementation

When communicating with the agent over the Unix socket using Protocol A, messages are JSON-serialized. You don't need to use protobuf binary encoding. The agent supports both:

- `message_protocol_json` — JSON string serialization (what the Electron UI uses)
- `message_protocol_protobuf` — Binary protobuf serialization

For a Swift native app, just use JSON. The protobuf schema is useful for understanding the exact message structures and field names.
