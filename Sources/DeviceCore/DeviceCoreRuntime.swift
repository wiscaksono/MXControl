import AppCore
import Foundation
import HIDPP

/// Owns the HID++ device manager and turns its mutable device objects into the
/// plain snapshot the UI consumes.
@MainActor
public final class DeviceCoreRuntime {
    public static let shared = DeviceCoreRuntime()

    private let manager = DeviceManager()

    public init() {}

    /// Process-level services that should run for the app's whole lifetime.
    public func start() {
        MicMuteEngine.shared.startDeviceMonitoring()
        BatteryNotifier.setup()
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

        return DeviceSnapshot(
            devices: summaries,
            details: details,
            warning: discoveryWarning
        )
    }

    /// Live battery and connection state, without rediscovering.
    public func refresh() async -> DeviceSnapshot? {
        for device in manager.devices where device.isInitialized {
            await device.refreshBattery()
        }
        return snapshot()
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
        guard let device = manager.devices.first(where: { deviceID(for: $0) == change.deviceID }),
              let capability = CapabilityID(rawValue: change.itemID)
        else {
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
            serial: device.name
        )
    }

    private func detail(for device: LogiDevice, summary: DeviceSummary) -> DeviceDetail {
        DeviceDetail(
            device: summary,
            connectionDetail: "\(summary.transport.label) · \(device.descriptor.name)",
            sections: sections(for: device)
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

        if device.battery.level > 0 {
            let batteryItem = SettingItem(
                id: "battery",
                title: "Battery",
                control: .info(
                    value: device.battery.charging
                        ? "\(device.battery.level)% · Charging"
                        : "\(device.battery.level)% · On battery"
                )
            )
            let title = "Device"
            if grouped[title] == nil {
                order.append(title)
                grouped[title] = []
            }
            grouped[title]?.append(batteryItem)
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
        switch device.deviceType {
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
