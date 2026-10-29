import AppCore
import SwiftUI

struct DeviceScreen: View {
    let detail: DeviceDetail
    let onAction: (UIAction) -> Void

    var body: some View {
        VStack(spacing: Metric.groupSpacing) {
            statusCard
            ForEach(detail.sections) { section in
                SettingsGroup(section: section, onAction: onAction)
            }
        }
        .padding(.horizontal, Metric.horizontalPadding)
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            BatteryRing(battery: detail.device.battery)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(detail.device.battery.level)%")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(detail.device.battery.isCharging ? "Charging" : "On battery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail.connectionDetail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            TransportBadge(transport: detail.device.transport)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .fill(Color.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .strokeBorder(Color.panelStroke)
        )
    }
}
