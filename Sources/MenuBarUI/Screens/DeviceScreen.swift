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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail.device.battery.isCharging ? "Charging" : "On battery")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(detail.connectionDetail)
                    .font(.system(size: 10))
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
