# Hardware QA

Run `make run` on a Mac with the devices paired. These checks need a human;
everything else is covered by `make verify`.

## First launch

- [ ] App has no Dock icon, menu bar item shows the Logitech glyph.
- [ ] Bluetooth permission prompt appears once and is granted.
- [ ] Popover opens under the icon, arrow points at it.
- [ ] If Input Monitoring is missing, the warning banner shows and
      "Open Settings" lands on the right pane.

## Devices

- [ ] MX Master 3S appears with the right name, `Mouse · BLE` (or USB), battery.
- [ ] MX Keys Mini appears with `Keyboard · USB`, charging state correct.
- [ ] Unplug the receiver: the row goes Offline and cannot be opened.
- [ ] Rescan shows "Scanning…" then restores the list.

## Settings that touch hardware

- [ ] Toggle SmartShift: the mouse wheel physically switches mode.
- [ ] Drag DPI: pointer speed changes; reopening keeps the value.
- [ ] Thumb wheel invert and natural scrolling behave as labelled.
- [ ] Keyboard backlight toggle and brightness change the keys.
- [ ] Fn inversion flips the top row between media keys and F1–F12.
- [ ] Press the mic mute key: the pill appears top-right, unmute hides it.
- [ ] Scroll smoothing: wheel is smooth, Cmd+scroll still zooms.
- [ ] Thumb button click opens Mission Control; hold+drag switches desktops.

## App behaviour

- [ ] Quit from the popover terminates the app.
- [ ] Launch at login registers and survives a reboot.
- [ ] Reset all settings asks for confirmation first.
- [ ] Reconnect the mouse: saved settings come back without touching the UI.

## Known gaps

- Natural scrolling inverts the HID++ events we synthesize, so it is disabled
  while smooth scrolling is off (the wheel then follows the macOS setting).
- Update check rows are placeholders; there is no updater yet.
- BLE devices discovered through CoreBluetooth are read-only (battery/info).
- Device names are used only for display; settings keys use descriptor + unit.
