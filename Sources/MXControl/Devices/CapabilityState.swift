import Foundation
import MXControlHIDPP
import Observation

// MARK: - Capability State

/// Observable UI state for one capability. States are dumb: the device owns
/// loading (`loadCapabilities`) and writing (`commit`), the view only binds
/// values and calls commit on change.
@Observable
final class ToggleState: Identifiable, @unchecked Sendable {
    let id: String
    let label: String
    let subtitle: String?
    var value: Bool

    init(id: String, label: String, subtitle: String?, value: Bool) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.value = value
    }
}

@Observable
final class IntSliderState: Identifiable, @unchecked Sendable {
    let id: String
    let label: String
    var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var suffix: String

    init(id: String, label: String, value: Int, range: ClosedRange<Int>, step: Int, suffix: String = "") {
        self.id = id
        self.label = label
        self.value = value
        self.range = range
        self.step = step
        self.suffix = suffix
    }
}

@Observable
final class DoubleSliderState: Identifiable, @unchecked Sendable {
    let id: String
    let label: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: String
    var suffix: String

    init(id: String, label: String, value: Double, range: ClosedRange<Double>, step: Double, format: String = "%.1f", suffix: String = "") {
        self.id = id
        self.label = label
        self.value = value
        self.range = range
        self.step = step
        self.format = format
        self.suffix = suffix
    }
}

@Observable
final class SegmentedState: Identifiable, @unchecked Sendable {
    struct Option: Identifiable, Sendable {
        let title: String
        let rawValue: Int
        var id: Int { rawValue }
    }

    let id: String
    let label: String
    var selected: Int
    let options: [Option]

    init(id: String, label: String, selected: Int, options: [Option]) {
        self.id = id
        self.label = label
        self.selected = selected
        self.options = options
    }
}

@Observable
final class BatteryState: @unchecked Sendable {
    var level: Int
    var charging: Bool
    var statusText: String

    init(level: Int = 0, charging: Bool = false, statusText: String = "") {
        self.level = level
        self.charging = charging
        self.statusText = statusText
    }
}

@Observable
final class HostListState: @unchecked Sendable {
    var hosts: [HostsInfoFeature.HostEntry] = []
    var currentHostIndex: Int = 0
    var hostCount: Int = 1
}
