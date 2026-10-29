import AppCore
import ApplicationServices
import CoreBluetooth
import Foundation
import HIDPP
import IOKit.hid

/// Owns the HID++ device manager and turns its mutable device objects into the
/// plain snapshot the UI consumes.
@MainActor
public final class DeviceCoreRuntime {
    public static let shared = DeviceCoreRuntime()

    private let manager = DeviceManager()

    public init() {}

    /// Process-level services that should run for the app's whole lifetime.
    /// Permission prompts are deliberately not requested here; onboarding owns
    /// that so the user knows why the dialog appeared.
    public func start() {
        applyBluetoothPreference()
        MicMuteEngine.shared.startDeviceMonitoring()
    }

    private static let notificationsRequestedKey = "notificationsRequested"

    /// Bluetooth is decided in onboarding before this is called.
    public func finishOnboarding() {
        manager.useBluetooth = CBManager.authorization == .allowedAlways
    }

    private func applyBluetoothPreference() {
        // Never construct the CoreBluetooth scanner before the permission is
        // granted: creating it is what raises the system prompt.
        manager.useBluetooth = CBManager.authorization == .allowedAlways
    }

    /// Requested once, the first time the user opens Settings, so the
    /// notification prompt never stacks on top of the permission wizard.
    public func requestNotificationsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.notificationsRequestedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.notificationsRequestedKey)
        BatteryNotifier.setup()
    }

    /// Scroll interception can only start once Accessibility is granted. Retry
    /// when the user comes back after flipping the switch in System Settings.
    public func retryScrollIfNeeded() {
        ScrollInterceptor.shared.retryIfNeeded()
    }

    /// Current system mute state, synced from CoreAudio.
    public var isMicMuted: Bool {
        MicMuteEngine.shared.isMuted
    }

    /// Best-effort cleanup before the process exits. Order matters: stop
    /// synthesizing scroll events, hand the wheel back to macOS, then tear the
    /// transport down.
    public func shutdown() async {
        ScrollInterceptor.shared.isEnabled = false
        await manager.resetScrollTargetForAllDevices()
        manager.stopDiscovery()
        F9KeyMonitor.shared.isEnabled = false
        MicMuteEngine.shared.restoreForTermination()
    }

    public func scan() async -> DeviceSnapshot {
        if manager.devices.isEmpty, !manager.isScanning {
            manager.startDiscovery()
        } else if !manager.isScanning {
            manager.rescan()
        }

        // Give discovery a moment; the UI already shows a scanning state.
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
            if !manager.isScanning, !manager.devices.isEmpty { break }
        }
        return snapshot()
    }

    public func snapshot() -> DeviceSnapshot {
        var summaries: [DeviceSummary] = []
        var details: [DeviceID: DeviceDetail] = [:]

        for device in manager.devices {
            let summary = summary(for: device)
            summaries.append(summary)
            details[summary.id] = detail(for: device, summary: summary)
        }

        // CoreBluetooth sees devices whose HID++ interface cannot be opened
        // (kIOReturnExclusiveAccess on macOS 15+). List them read-only instead
        // of showing an empty popover.
        for info in manager.bleDevices where !summaries.contains(where: { $0.name == info.name }) {
            let summary = summary(for: info)
            summaries.append(summary)
            details[summary.id] = detail(for: info, summary: summary)
        }

        return DeviceSnapshot(
            devices: summaries,
            details: details,
            warning: discoveryWarning
        )
    }

    /// Live connection state, without rediscovering and without extra HID++ IO.
    /// Wheel-mode changes arrive as SmartShift notifications, which refresh the
    /// device and post `.deviceStateChanged`; polling them here was 2 HID++
    /// requests per second on the mouse and a wasted local throw on keyboards.
    public func refresh() async -> DeviceSnapshot? {
        snapshot()
    }

    /// Forget every saved preference and let the devices report their defaults.
    public func clearSettings() async -> DeviceSnapshot? {
        for device in manager.devices {
            SettingsStore.clearSettings(for: device.settingScope)
            await device.loadCapabilities()
        }
        return snapshot()
    }

    /// Discovery reports permission and transport problems through its status
    /// string; surface the ones the user can act on.
    private var discoveryWarning: String? {
        let message = manager.statusMessage
        let lowered = message.lowercased()
        let isProblem = lowered.contains("permission")
            || lowered.contains("restricted")
            || lowered.contains("failed")
        return isProblem ? message : nil
    }

    /// Apply one UI edit to the matching device, then hand back the device's
    /// own values so clamping and snapping are reflected in the UI.
    public func apply(_ change: DeviceChange) async -> DeviceSnapshot? {
        guard let device = manager.devices.first(where: { deviceID(for: $0) == change.deviceID })
        else {
            return nil
        }

        // Restore the Fn inversion state the keyboard shipped with.
        if change.itemID == "fn.restoreDefault" {
            guard device.toggles[CapabilityID.fnStandardKeys] != nil else { return nil }
            let defaultInverted = device.fnDefaultState != 0
            device.toggles[CapabilityID.fnStandardKeys]?.value = !defaultInverted
            await device.commit(CapabilityID.fnStandardKeys)
            return snapshot()
        }

        guard let capability = CapabilityID(rawValue: change.itemID) else {
            return nil
        }

        switch change.value {
        case let .bool(isOn):
            device.toggles[capability]?.value = isOn
        case let .int(value):
            device.ints[capability]?.value = value
        case let .double(value):
            device.doubles[capability]?.value = value
        case let .picker(index):
            if let state = device.segmented[capability], state.options.indices.contains(index) {
                state.selected = state.options[index].rawValue
            }
        }

        await device.commit(capability)
        return snapshot()
    }

    // MARK: - Mapping

    private func summary(for device: LogiDevice) -> DeviceSummary {
        DeviceSummary(
            id: deviceID(for: device),
            name: device.name,
            kind: deviceKind(for: device),
            transport: transportKind(for: device),
            battery: AppCore.BatteryState(
                level: device.battery.level,
                isCharging: device.battery.charging
            ),
            isConnected: device.isInitialized
        )
    }

    private func deviceID(for device: LogiDevice) -> DeviceID {
        DeviceID(
            transport: transportKind(for: device),
            unitID: device.deviceIndex,
            // Receiver / IOKit UID, not the device name: identity must survive
            // a rename and stay unique across receivers.
            serial: manager.transportUID(for: device)
        )
    }

    private func detail(for device: LogiDevice, summary: DeviceSummary) -> DeviceDetail {
        DeviceDetail(
            device: summary,
            connectionDetail: "\(summary.transport.label) · \(device.descriptor.name)",
            sections: sections(for: device)
        )
    }

    private func summary(for info: BLEPeripheralInfo) -> DeviceSummary {
        DeviceSummary(
            id: DeviceID(
                transport: .ble,
                unitID: 0xFE,
                serial: info.peripheralId.uuidString
            ),
            name: info.name,
            kind: deviceKind(for: info.deviceType),
            transport: .ble,
            battery: AppCore.BatteryState(level: info.batteryLevel ?? 0, isCharging: false),
            isConnected: true
        )
    }

    /// GATT only exposes identity and battery, so this screen is read-only
    /// until the HID++ interface can be opened.
    private func detail(for info: BLEPeripheralInfo, summary: DeviceSummary) -> DeviceDetail {
        var items: [SettingItem] = [
            SettingItem(id: "ble.model", title: "Model", control: .info(value: info.modelNumber ?? info.name)),
            SettingItem(id: "ble.serial", title: "Serial", control: .info(value: info.serialNumber ?? "Unknown")),
            SettingItem(id: "ble.firmware", title: "Firmware", control: .info(value: info.firmwareRevision ?? "Unknown")),
        ]
        if let battery = info.batteryLevel {
            items.append(
                SettingItem(id: "ble.battery", title: "Battery", control: .info(value: "\(battery)%"))
            )
        }

        return DeviceDetail(
            device: summary,
            connectionDetail: "Bluetooth · Read-only",
            sections: [SettingSection(id: "device", title: "Device", items: items)]
        )
    }

    private func sections(for device: LogiDevice) -> [SettingSection] {
        var grouped: [String: [SettingItem]] = [:]
        var order: [String] = []

        for capability in CapabilityID.allCases {
            // Hidden capabilities (e.g. pointer speed) are loaded and saved but
            // never rendered.
            let isHidden = device.descriptor.capabilities
                .first { $0.id == capability }?.hidden ?? false
            if isHidden { continue }

            guard let item = item(for: capability, on: device) else { continue }
            let title = sectionTitle(for: capability)
            if grouped[title] == nil {
                order.append(title)
                grouped[title] = []
            }
            grouped[title]?.append(item)
        }

        if device.toggles[CapabilityID.fnStandardKeys] != nil {
            let item = SettingItem(
                id: "fn.restoreDefault",
                title: "Restore default",
                control: .action(detail: nil)
            )
            if grouped["Keys"] == nil {
                order.append("Keys")
                grouped["Keys"] = []
            }
            grouped["Keys"]?.append(item)
        }

        // Easy-Switch slots, read-only: switching hosts moves the connection.
        let hosts = device.hosts
        if !hosts.hosts.isEmpty {
            let items = hosts.hosts.map { host in
                var detail = host.isPaired ? host.busType.description : "Empty"
                if host.index == hosts.currentHostIndex {
                    detail += " · Active"
                }
                return SettingItem(
                    id: "host.\(host.index)",
                    title: host.name,
                    control: .info(value: detail)
                )
            }
            order.append("Hosts")
            grouped["Hosts"] = items
        }

        return order.map { title in
            SettingSection(
                id: title.lowercased(),
                title: title,
                items: grouped[title] ?? []
            )
        }
    }

    private func item(for capability: CapabilityID, on device: LogiDevice) -> SettingItem? {
        if let state = device.toggles[capability] {
            // Natural scrolling inverts the events we synthesize, so it has no
            // meaning while the wheel is on the macOS HID path.
            if capability == .hiResInverted {
                let smoothScrolling = device.toggles[CapabilityID.smoothScrollEnabled]?.value ?? true
                return SettingItem(
                    id: capability.rawValue,
                    title: state.label,
                    subtitle: smoothScrolling ? state.subtitle : "Requires smooth scrolling",
                    control: .toggle(isOn: state.value),
                    isEnabled: smoothScrolling
                )
            }

            return SettingItem(
                id: capability.rawValue,
                title: state.label,
                subtitle: state.subtitle,
                control: .toggle(isOn: state.value)
            )
        }
        if let state = device.ints[capability] {
            return SettingItem(
                id: capability.rawValue,
                title: state.label,
                control: .slider(
                    SliderSpec(
                        value: Double(state.value),
                        range: Double(state.range.lowerBound) ... Double(state.range.upperBound),
                        step: Double(state.step),
                        unit: state.suffix
                    )
                )
            )
        }
        if let state = device.doubles[capability] {
            return SettingItem(
                id: capability.rawValue,
                title: state.label,
                control: .slider(
                    SliderSpec(
                        value: state.value,
                        range: state.range,
                        step: state.step,
                        unit: state.suffix
                    )
                )
            )
        }
        if let state = device.segmented[capability] {
            let options = state.options.map(\.title)
            let index = state.options.firstIndex { $0.rawValue == state.selected } ?? 0
            return SettingItem(
                id: capability.rawValue,
                title: state.label,
                control: .picker(options: options, selectedIndex: index)
            )
        }
        return nil
    }

    private func sectionTitle(for capability: CapabilityID) -> String {
        switch capability {
        case .dpi, .pointerSpeed:
            "Pointer"
        case .smartShiftActive, .smartShiftWheelMode, .smartShiftTorque:
            "Wheel"
        case .hiResEnabled, .hiResInverted, .thumbWheelInverted,
             .smoothScrollEnabled, .smoothScrollSpeed, .smoothScrollMomentum, .smoothScrollThumbSpeed:
            "Scrolling"
        case .gestureClickMs, .gestureDragThreshold:
            "Gestures"
        case .backlightEnabled, .backlightLevel:
            "Backlight"
        case .fnStandardKeys, .micMuteEnabled:
            "Keys"
        case .battery, .hosts:
            "Device"
        }
    }

    private func transportKind(for device: LogiDevice) -> TransportKind {
        switch manager.transportType(for: device) {
        case .ble: .ble
        default: .usb
        }
    }

    private func deviceKind(for device: LogiDevice) -> DeviceKind {
        deviceKind(for: device.deviceType)
    }

    private func deviceKind(for type: DeviceType) -> DeviceKind {
        switch type {
        case .mouse: .mouse
        case .keyboard: .keyboard
        default: .other
        }
    }
}

/// `DeviceService` backed by real HID++ discovery.
public struct HIDPPDeviceService: DeviceService {
    public init() {}

    public func scan() async -> DeviceSnapshot {
        await DeviceCoreRuntime.shared.scan()
    }

    public func refresh() async -> DeviceSnapshot? {
        await DeviceCoreRuntime.shared.refresh()
    }

    public func apply(_ change: DeviceChange) async -> DeviceSnapshot? {
        await DeviceCoreRuntime.shared.apply(change)
    }

    public func clearSettings() async -> DeviceSnapshot? {
        await DeviceCoreRuntime.shared.clearSettings()
    }
}
