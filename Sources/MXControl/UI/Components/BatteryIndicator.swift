import SwiftUI

/// Battery level indicator with multicolor SF Symbol and monospaced percentage.
/// The level is clamped: corrupt HID++ reports outside 0-100 render sanely.
struct BatteryIndicator: View {
    let level: Int
    let isCharging: Bool

    private var clampedLevel: Int { min(100, max(0, level)) }

    private var batteryIcon: String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch clampedLevel {
        case 0..<10:
            return "battery.0"
        case 10..<25:
            return "battery.25"
        case 25..<50:
            return "battery.50"
        case 50..<75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryIcon)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 12))

            Text("\(clampedLevel)%")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
