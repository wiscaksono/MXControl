# Hardware QA

Run `make run` on a Mac with the devices paired. These checks need a human;
everything else is covered by `make verify`.

## First launch

- [ ] App has no Dock icon, menu bar item shows the Logitech glyph.
- [ ] No permission prompt appears until the popover is opened.
- [ ] Wizard asks Accessibility, then Input Monitoring, then Bluetooth.
- [ ] After granting Input Monitoring, the wizard shows "Restart needed" and
      the Relaunch button brings the app back with the grant active.
- [ ] Popover opens under the icon, arrow points at it.

## Devices

- [ ] MX Master 3S appears with the right name, `Mouse · BLE` (or USB), battery.
- [ ] MX Keys Mini appears with `Keyboard · USB`, charging state correct.
- [ ] Unplug the receiver: the USB rows disappear after the debounce.
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

- [ ] General → Menu Bar → Hide menu bar icon: the icon disappears.
- [ ] Open MXControl again from Applications or Spotlight: the icon is back
      and the toggle is off.
- [ ] Quit from the popover terminates the app and the wheel still scrolls
      in macOS (no power cycle needed).
- [ ] `make stop` does the same: SIGTERM runs the same cleanup.
- [ ] Launch at login registers and survives a reboot.
- [ ] Reset all device settings asks for confirmation first and leaves the
      General preferences alone.
- [ ] Reconnect the mouse: saved settings come back without touching the UI,
      including the hi-res firmware bytes.

## Known gaps

- Natural scrolling is applied once: the interceptor owns the smoothed HID++
  path, macOS owns the normal HID path. The toggle is disabled while smooth
  scrolling is off.
- BLE devices discovered through CoreBluetooth are read-only (battery/info).
- Device names are used only for display; settings keys use descriptor + unit
  and routes use the transport UID.
