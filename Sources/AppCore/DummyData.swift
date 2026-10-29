import Foundation

/// Fake devices and settings so the UI can be built and reviewed without
/// touching real hardware. Everything here is presentation data.
public enum DummyData {
    public static let mouseID = DeviceID(transport: .ble, unitID: 1, serial: "MX3S-0001")
    public static let keyboardID = DeviceID(transport: .usb, unitID: 2, serial: "MXKM-0002")
    public static let offlineID = DeviceID(transport: .ble, unitID: 3, serial: "MXAW-0003")

    public static let version = "0.4.0"

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
        name: "Logitech Device",
        kind: .other,
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

    /// Two connected devices, used for the README hero image.
    public static func connectedState(route: Route = .root) -> AppState {
        AppState(
            route: route,
            devices: [mouse, keyboard],
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

    public static func onboardingState() -> AppState {
        var state = emptyState()
        // Fresh install: nothing has been requested yet.
        state.permissions = PermissionState()
        state.showsOnboarding = true
        return state
    }

    /// Input Monitoring granted in Settings but the process still needs a restart.
    public static func onboardingRelaunchState() -> AppState {
        var state = emptyState()
        state.permissions = PermissionState(
            inputMonitoring: .needsRelaunch,
            accessibility: .granted,
            bluetooth: .unknown
        )
        state.showsOnboarding = true
        return state
    }

    public static func warningState() -> AppState {
        var state = initialState()
        state.warning = "Input Monitoring permission is required for scroll interception."
        return state
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
