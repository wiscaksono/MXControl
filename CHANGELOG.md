# Changelog

All notable changes to MXControl. Format follows Keep a Changelog.

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
