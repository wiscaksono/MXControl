import Foundation

public enum Route: Equatable, Sendable, Hashable {
    case root
    case device(DeviceID)
    case general
}

public enum UIAction: Equatable, Sendable {
    case openDevice(DeviceID)
    case openGeneral
    case back
    case toggle(itemID: String)
    case setSlider(itemID: String, value: Double)
    case selectOption(itemID: String, index: Int)
    case activate(itemID: String)
    case resetAll
    case openPermissionSettings
    case requestPermission(PermissionKind)
    case openPermissionPane(PermissionKind)
    case relaunchApp
    case refreshPermissions
    case finishOnboarding
    case finishOnboardingWithoutBluetooth
    case refresh
    case quit
}

public struct AppState: Equatable, Sendable {
    public var route: Route
    public var devices: [DeviceSummary]
    public var details: [DeviceID: DeviceDetail]
    public var general: [SettingSection]
    public var warning: String?
    public var isScanning: Bool
    public var permissions: PermissionState
    public var showsOnboarding: Bool
    public var version: String

    public init(
        route: Route = .root,
        devices: [DeviceSummary] = [],
        details: [DeviceID: DeviceDetail] = [:],
        general: [SettingSection] = [],
        warning: String? = nil,
        isScanning: Bool = false,
        permissions: PermissionState = .allGranted,
        showsOnboarding: Bool = false,
        version: String = "0.0.0"
    ) {
        self.route = route
        self.devices = devices
        self.details = details
        self.general = general
        self.warning = warning
        self.isScanning = isScanning
        self.permissions = permissions
        self.showsOnboarding = showsOnboarding
        self.version = version
    }

    public mutating func beginScan() {
        isScanning = true
        warning = nil
    }

    public mutating func finishScan(
        devices: [DeviceSummary],
        details: [DeviceID: DeviceDetail],
        warning: String? = nil
    ) {
        self.devices = devices
        self.details = details
        self.warning = warning
        isScanning = false
    }

    /// Update a general-screen toggle, e.g. after reading the real system state.
    public mutating func setGeneralToggle(_ itemID: String, to value: Bool) {
        Self.update(in: &general, id: itemID) { item in
            guard case .toggle = item.control else { return }
            item.control = .toggle(isOn: value)
        }
    }

    public var activeDetail: DeviceDetail? {
        guard case let .device(id) = route else { return nil }
        return details[id]
    }

    public var sections: [SettingSection] {
        switch route {
        case .root: []
        case .device: activeDetail?.sections ?? []
        case .general: general
        }
    }

    /// Typed value of one setting, used to forward edits to a device service.
    public func settingValue(_ itemID: String) -> SettingValue? {
        let item = sections.flatMap(\.items).first { $0.id == itemID }
        guard let control = item?.control else { return nil }
        switch control {
        case let .toggle(isOn):
            return .bool(isOn)
        case let .slider(spec):
            return spec.step >= 1 ? .int(Int(spec.value)) : .double(spec.value)
        case let .picker(_, selectedIndex):
            return .picker(index: selectedIndex)
        case .action, .info:
            return nil
        }
    }

    public mutating func toggleItem(_ id: String) {
        updateItem(id) { item in
            guard case let .toggle(isOn) = item.control else { return }
            item.control = .toggle(isOn: !isOn)
        }
    }

    public mutating func setSlider(_ id: String, to value: Double) {
        updateItem(id) { item in
            guard case var .slider(spec) = item.control else { return }
            spec.value = min(max(value, spec.range.lowerBound), spec.range.upperBound)
            item.control = .slider(spec)
        }
    }

    public mutating func selectOption(_ id: String, index: Int) {
        updateItem(id) { item in
            guard case let .picker(options, _) = item.control, !options.isEmpty else { return }
            item.control = .picker(
                options: options,
                selectedIndex: min(max(index, 0), options.count - 1)
            )
        }
    }

    private mutating func updateItem(_ id: String, _ transform: (inout SettingItem) -> Void) {
        switch route {
        case .root:
            return
        case .general:
            Self.update(in: &general, id: id, transform)
        case let .device(deviceID):
            guard var detail = details[deviceID] else { return }
            Self.update(in: &detail.sections, id: id, transform)
            details[deviceID] = detail
        }
    }

    private static func update(
        in sections: inout [SettingSection],
        id: String,
        _ transform: (inout SettingItem) -> Void
    ) {
        for sectionIndex in sections.indices {
            let items = sections[sectionIndex].items
            guard let itemIndex = items.firstIndex(where: { $0.id == id }) else {
                continue
            }
            transform(&sections[sectionIndex].items[itemIndex])
        }
    }
}
