import Foundation

public struct SliderSpec: Equatable, Sendable {
    public var value: Double
    public var range: ClosedRange<Double>
    public var step: Double
    public var unit: String

    public init(value: Double, range: ClosedRange<Double>, step: Double = 1, unit: String = "") {
        self.value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    public var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    public var displayValue: String {
        Self.format(value, step: step) + unitSuffix
    }

    public var minimumLabel: String {
        Self.format(range.lowerBound, step: step)
    }

    public var maximumLabel: String {
        Self.format(range.upperBound, step: step)
    }

    private var unitSuffix: String {
        guard !unit.isEmpty else { return "" }
        // Percent and multipliers attach directly; other units need a space.
        if unit == "%" || unit == "x" {
            return unit
        }
        if unit.hasPrefix(" ") {
            return unit
        }
        return " \(unit)"
    }

    private static func format(_ value: Double, step: Double) -> String {
        String(format: "%.\(decimals(for: step))f", value)
    }

    /// Smallest number of decimals that can represent the step, so a 0.01
    /// step shows 0.92 instead of 0.9 and a 0.5 step shows 3.0.
    private static func decimals(for step: Double) -> Int {
        for digits in 0 ... 3 {
            let scaled = step * pow(10, Double(digits))
            if abs(scaled.rounded() - scaled) < 0.0001 {
                return digits
            }
        }
        return 2
    }
}

public enum SettingControl: Equatable, Sendable {
    case toggle(isOn: Bool)
    case slider(SliderSpec)
    case picker(options: [String], selectedIndex: Int)
    case action(detail: String?)
    case info(value: String)
}

public struct SettingItem: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var control: SettingControl
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        control: SettingControl,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.control = control
        self.isEnabled = isEnabled
    }
}

public struct SettingSection: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String?
    public var items: [SettingItem]

    public init(id: String, title: String? = nil, items: [SettingItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct DeviceDetail: Identifiable, Equatable, Sendable {
    public let id: DeviceID
    public var device: DeviceSummary
    public var connectionDetail: String
    public var sections: [SettingSection]

    public init(
        device: DeviceSummary,
        connectionDetail: String,
        sections: [SettingSection]
    ) {
        id = device.id
        self.device = device
        self.connectionDetail = connectionDetail
        self.sections = sections
    }
}
