import Foundation

public enum Route: Equatable, Sendable, Hashable {
    case root
    case device(UUID)
    case general
}

public enum UIAction: Equatable, Sendable {
    case openDevice(UUID)
    case openGeneral
    case back
    case toggle(itemID: String)
    case setSlider(itemID: String, value: Double)
    case selectOption(itemID: String, index: Int)
    case activate(itemID: String)
    case refresh
    case quit
}

public struct AppState: Equatable, Sendable {
    public var route: Route
    public var devices: [DeviceSummary]
    public var details: [UUID: DeviceDetail]
    public var general: [SettingSection]
    public var warning: String?
    public var version: String

    public init(
        route: Route = .root,
        devices: [DeviceSummary] = [],
        details: [UUID: DeviceDetail] = [:],
        general: [SettingSection] = [],
        warning: String? = nil,
        version: String = "0.0.0"
    ) {
        self.route = route
        self.devices = devices
        self.details = details
        self.general = general
        self.warning = warning
        self.version = version
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
