# MXControl

A native macOS menu bar app that controls Logitech MX devices. Built because Logi Options+ is a 500MB Electron app that needs its own login system, phones home constantly, shows you ads for other Logitech products inside a mouse driver, and somehow uses more RAM than Xcode. For a mouse. And a keyboard.

MXControl is ~2MB. It talks HID++ 2.0 directly to your devices, scroll data included. Logi Options+ still routes scroll through macOS and calls it a day. No account, no telemetry, no upsell banners, no "SmartActions" nobody asked for.

This entire thing was vibe coded. Claude wrote most of it. I pointed at things and said "fix that" until it worked. If it breaks, that's the risk you accept when a human and an LLM collectively decide they've had enough of Logi Options+.

## What it does

**Mouse (MX Master 3S)**
- Smooth scroll via HID++ hi-res data (15x resolution, skips the macOS scroll pipeline)
- Scroll acceleration that actually matches trackpad feel
- Wheel mode aware: snappy in ratchet, glidy in free-spin, auto-detects SmartShift switches
- Cmd+scroll zoom works (Figma, Chrome, the usual suspects)
- SmartShift wheel mode (ratchet/free-spin) with auto-disengage
- Natural scrolling and thumb wheel inversion
- Thumb button gestures: click for Mission Control, hold+drag for workspace switching
- Battery level and charging status
- Easy-Switch host info
- Advanced: DPI, SmartShift force, scroll tuning, gesture thresholds

**Keyboard (MX Keys Mini)**
- Backlight toggle and brightness
- Fn key inversion (media keys vs F1-F12)
- Battery level and charging status
- Easy-Switch host info

**Transport**
- USB via Bolt/Unifying receiver (auto-probes devices 1-6)
- Bluetooth Low Energy direct (no receiver needed)
- Both at the same time, USB preferred when duplicate detected

**App**
- Native SwiftUI menu bar popover
- Launch at login toggle
- Settings persist and re-apply on reconnect
- ~2MB total, runs under 20MB RAM

## What it doesn't do

- Vertical thumb gestures (up/down not mapped yet)
- Custom gesture actions (hardcoded to Mission Control and workspace switch)
- Per-app settings or "SmartActions" (and honestly, good)
- Flow notifications (you don't need your mouse driver congratulating you)
- Logitech account login (lol)

## Supported devices

Tested and working:
- MX Master 3S (mouse, USB + BLE)
- MX Keys Mini (keyboard, USB + BLE)

Other Logitech HID++ 2.0 devices connected via a Bolt or Unifying receiver will probably get discovered and show basic info. BLE direct needs the device PID registered in code, so only the two above work wirelessly without a receiver for now.

## Install

Grab `MXControl.dmg` from [Releases](https://github.com/wiscaksono/MXControl/releases), open it, drag to Applications.

Or build it yourself:

```
git clone https://github.com/wiscaksono/MXControl.git
cd MXControl
make dmg
```

Needs macOS 15+ and Xcode command line tools. After first launch, go to System Settings and grant:
- **Input Monitoring** (required for BLE HID device access)
- **Accessibility** (required for smooth scroll and gesture actions)

## Requirements

- macOS 15.0+
- Logitech MX device with HID++ 2.0 support
- Bolt/Unifying USB receiver or Bluetooth Low Energy

## License

MIT
