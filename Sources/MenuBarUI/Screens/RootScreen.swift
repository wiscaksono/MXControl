import AppCore
import SwiftUI

struct RootScreen: View {
    let state: AppState
    let onAction: (UIAction) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let warning = state.warning {
                WarningBanner(text: warning)
            }
            if state.devices.isEmpty {
                EmptyStateView { onAction(.refresh) }
            } else {
                deviceList
            }
        }
        .padding(.horizontal, Metric.horizontalPadding)
    }

    private var deviceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.devices.enumerated()), id: \.element.id) { index, device in
                DeviceRow(device: device) {
                    onAction(.openDevice(device.id))
                }
                if index < state.devices.count - 1 {
                    Divider()
                        .opacity(0.6)
                        .padding(.leading, 42)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .fill(Color.panelFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .strokeBorder(Color.panelStroke)
        )
    }
}

struct DeviceRow: View {
    let device: DeviceSummary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.symbolName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(.callout, weight: .medium))
                        .lineLimit(1)
                    Text("\(device.kind.label) · \(device.transport.label)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                BatteryPill(battery: device.battery)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, Metric.rowPadding)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(isHovered ? 0.045 : 0))
        .animation(.easeOut(duration: 0.08), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct WarningBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

struct EmptyStateView: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "computermouse")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No devices found")
                .font(.system(.callout, weight: .semibold))
            Text("Pair your MX device, then scan again.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Scan again", action: onScan)
                .buttonStyle(FilledButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .fill(Color.panelFill)
        )
    }
}
