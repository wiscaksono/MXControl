# Changelog

All notable changes to MXControl. Format follows Keep a Changelog.

## [0.3.1] - 2026-09-09

### Fixed
- Mic-mute pill no longer drifts or jumps on external monitors in dual-display setups (parked fully onscreen; screens resolved from geometry).
- Mic-mute pill slide in/out stays on its own screen and no longer strolls onto the neighboring monitor.
- Rapid F9 presses no longer restart the pill animation.

## [0.3.0] - 2026-09-08

### Added
- SmartShift section on BLE (original 0x2110 variant the mouse speaks wirelessly).
- Easy-Switch host list with per-slot bus and pairing status.
- Thumb-wheel inversion toggle (was hidden by a misread capability byte).
- Live battery updates pushed by the device (no more waiting for the 5-minute poll).
- Mic-mute overlay slides in from off-screen right, out to the right; no border on the docked edge.

### Fixed
- Thumbwheel, SmartShift v2, hosts-info, battery-level, and hi-res capability wire formats aligned with the HID++ reference.
- Fn-inversion state byte correctly labeled (wire behavior unchanged).
- F9 fallback is strictly opt-in for CoreBluetooth-only keyboards.

## [0.2.0] - 2026-09-08

### Added
- F9 mic mute for MX Keys Mini: system-wide microphone mute with a
  persistent Liquid Glass pill at the top-right screen edge.
- HID++ divert of the mic-mute key (CID 0x011C) with event-tap fallback.
- CoreAudio mute across all input devices with prior-state restore.
- Smooth scroll from HID++ hi-res wheel data with wheel-mode-aware tuning.
- Global side-button fallback for Back/Forward navigation.
- Low battery notifications at 20% and 10%.
- Natural scrolling toggle, per-device settings reset, General settings screen.

### Fixed
- BLE retry with divert re-arm for reliable HID++ over BLE.
- Scroll hot-path performance and memory growth from event sources.

## [0.1.1] - 2026-03-10

### Added
- In-popover General settings screen for app-level controls.
- Launch at Login and hide-until-reopened controls.

## [0.1.0] - 2026-03-09

Initial release: menu bar control for MX Master 3S and MX Keys Mini over
USB Bolt receiver and BLE (DPI, SmartShift, backlight, Fn inversion,
battery, Easy-Switch info, thumb-button gestures).
