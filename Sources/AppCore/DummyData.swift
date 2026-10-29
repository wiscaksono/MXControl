import Foundation

/// Fake devices and settings so the UI can be built and reviewed without
/// touching real hardware. Everything here is presentation data.
public enum DummyData {
    public static let mouseID = DeviceID(transport: .ble, unitID: 1, serial: "MX3S-0001")
    public static let keyboardID = DeviceID(transport: .usb, unitID: 2, serial: "MXKM-0002")
    public static let offlineID = DeviceID(transport: .ble, unitID: 3, serial: "MXAW-0003")

    public static let version = "0.2.0 (dummy)"

    public static let mouse = DeviceSummary(
        id: mouseID,
        name: "MX Master 3S",
        kind: .mouse,
        transport: .ble,
        battery: BatteryState(level: 75, isCharging: false)
    )

    public static let keyboard = DeviceSummary(
        id: keyboardID,
        name: "MX Keys Mini",
        kind: .keyboard,
        transport: .usb,
        battery: BatteryState(level: 65, isCharging: true)
    )

    public static let offline = DeviceSummary(
        id: offlineID,
        name: "MX Anywhere 3S",
        kind: .mouse,
        transport: .ble,
        battery: BatteryState(level: 42, isCharging: false),
        isConnected: false
    )

    public static var devices: [DeviceSummary] {
        [mouse, keyboard, offline]
    }

    public static var details: [DeviceID: DeviceDetail] {
        [mouseID: mouseDetail, keyboardID: keyboardDetail]
    }

    public static func initialState(route: Route = .root) -> AppState {
        AppState(
            route: route,
            devices: devices,
            details: details,
            general: generalSettings,
            version: version
        )
    }

    public static func emptyState() -> AppState {
        AppState(devices: [], details: [:], general: generalSettings, version: version)
    }

    public static func scanningState() -> AppState {
        var state = emptyState()
        state.isScanning = true
        return state
    }

    public static func warningState() -> AppState {
        var state = initialState()
        state.warning = "Input Monitoring permission is required for scroll interception."
        return state
    }

    // MARK: - Mouse

    public static var mouseDetail: DeviceDetail {
        DeviceDetail(
            device: mouse,
            connectionDetail: "Bluetooth · Direct",
            sections: [
                SettingSection(id: "wheel", title: "Wheel", items: [
                    SettingItem(
                        id: "wheel.smartshift",
                        title: "SmartShift",
                        subtitle: "Auto-switch between ratchet and free-spin",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "wheel.resistance",
                        title: "Ratchet resistance",
                        control: .slider(
                            SliderSpec(value: 32, range: 1 ... 100, unit: "%")
                        )
                    ),
                    SettingItem(
                        id: "wheel.disengage",
                        title: "Shift sensitivity",
                        control: .picker(
                            options: ["Off", "Standard", "Aggressive"],
                            selectedIndex: 1
                        )
                    ),
                ]),
                SettingSection(id: "pointer", title: "Pointer", items: [
                    SettingItem(
                        id: "pointer.dpi",
                        title: "DPI",
                        control: .slider(
                            SliderSpec(value: 1000, range: 200 ... 8000, step: 50, unit: "DPI")
                        )
                    ),
                    SettingItem(
                        id: "pointer.rate",
                        title: "Report rate",
                        control: .info(value: "125 Hz")
                    ),
                ]),
                SettingSection(id: "scroll", title: "Scrolling", items: [
                    SettingItem(
                        id: "scroll.smooth",
                        title: "Smooth scrolling",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "scroll.acceleration",
                        title: "Acceleration",
                        subtitle: "Match trackpad feel",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "scroll.natural",
                        title: "Natural scrolling",
                        control: .toggle(isOn: false)
                    ),
                    SettingItem(
                        id: "scroll.thumbInvert",
                        title: "Invert thumb wheel",
                        control: .toggle(isOn: false)
                    ),
                ]),
                SettingSection(id: "gestures", title: "Gestures", items: [
                    SettingItem(
                        id: "gestures.thumbButton",
                        title: "Thumb button",
                        control: .picker(
                            options: ["Mission Control", "App Exposé", "None"],
                            selectedIndex: 0
                        )
                    ),
                    SettingItem(
                        id: "gestures.workspaces",
                        title: "Workspace switching",
                        subtitle: "Hold and drag to move between desktops",
                        control: .toggle(isOn: true)
                    ),
                ]),
                SettingSection(id: "hosts", title: "Hosts", items: [
                    SettingItem(
                        id: "host.0",
                        title: "Host 1",
                        control: .info(value: "USB · Active")
                    ),
                    SettingItem(id: "host.1", title: "Host 2", control: .info(value: "Bluetooth")),
                    SettingItem(id: "host.2", title: "Host 3", control: .info(value: "Empty")),
                ]),
            ]
        )
    }

    // MARK: - Keyboard

    public static var keyboardDetail: DeviceDetail {
        DeviceDetail(
            device: keyboard,
            connectionDetail: "USB · Bolt receiver",
            sections: [
                SettingSection(id: "backlight", title: "Backlight", items: [
                    SettingItem(
                        id: "backlight.toggle",
                        title: "Keyboard backlight",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "backlight.brightness",
                        title: "Brightness",
                        control: .slider(SliderSpec(value: 60, range: 0 ... 100, unit: "%"))
                    ),
                ]),
                SettingSection(id: "keys", title: "Keys", items: [
                    SettingItem(
                        id: "keys.fnInversion",
                        title: "Fn key inversion",
                        subtitle: "Use F1–F12 without holding Fn",
                        control: .toggle(isOn: false)
                    ),
                    SettingItem(
                        id: "keys.layout",
                        title: "Layout",
                        control: .info(value: "US ANSI")
                    ),
                    SettingItem(
                        id: "fn.restoreDefault",
                        title: "Restore default",
                        control: .action(detail: nil)
                    ),
                ]),
            ]
        )
    }

    // MARK: - General

    public static var generalSettings: [SettingSection] {
        [
            SettingSection(id: "startup", title: "Startup", items: [
                SettingItem(
                    id: "general.launchAtLogin",
                    title: "Launch at login",
                    control: .toggle(isOn: true)
                ),
                SettingItem(
                    id: "general.hideFromDock",
                    title: "Hide from Dock",
                    subtitle: "Run as a menu bar only app",
                    control: .toggle(isOn: true)
                ),
            ]),
            SettingSection(id: "battery", title: "Battery", items: [
                SettingItem(
                    id: "general.batteryAlerts",
                    title: "Low battery alerts",
                    control: .toggle(isOn: true)
                ),
                SettingItem(
                    id: "general.batteryThreshold",
                    title: "Alert threshold",
                    control: .picker(options: ["10%", "20%", "30%"], selectedIndex: 1)
                ),
            ]),
            SettingSection(id: "updates", title: "Updates", items: [
                SettingItem(
                    id: "general.autoCheck",
                    title: "Check automatically",
                    control: .toggle(isOn: true)
                ),
                SettingItem(
                    id: "general.interval",
                    title: "Check interval",
                    control: .picker(options: ["Daily", "Weekly", "Monthly"], selectedIndex: 1)
                ),
            ]),
            SettingSection(id: "about", title: "About", items: [
                SettingItem(
                    id: "general.version",
                    title: "Version",
                    control: .info(value: version)
                ),
                SettingItem(
                    id: "general.protocol",
                    title: "Protocol",
                    control: .info(value: "HID++ 2.0")
                ),
                SettingItem(
                    id: "general.reset",
                    title: "Reset all settings",
                    control: .action(detail: nil)
                ),
            ]),
        ]
    }
}
