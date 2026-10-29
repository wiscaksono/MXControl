import AppCore
import SwiftUI

struct RootScreen: View {
    let state: AppState
    let onAction: (UIAction) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    private var strokeOpacity: Double {
        contrast == .increased ? 0.24 : 0.06
    }

    var body: some View {
        VStack(spacing: 10) {
            if !state.permissions.requiredGranted {
                PermissionBanner {
                    onAction(.resumeOnboarding)
                }
            }
            if let warning = state.warning {
                WarningBanner(text: warning) {
                    onAction(.openPermissionSettings)
                }
            }
            if state.devices.isEmpty {
                EmptyStateView(isScanning: state.isScanning) {
                    onAction(.refresh)
                }
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
                .strokeBorder(Color.primary.opacity(strokeOpacity))
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
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(.callout, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                BatteryPill(battery: device.battery)

                if device.isConnected {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, Metric.rowPadding)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(!device.isConnected)
        .opacity(device.isConnected ? 1 : 0.55)
        .background(Color.primary.opacity(isHovered && device.isConnected ? 0.045 : 0))
        .animation(.easeOut(duration: 0.08), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        if device.isConnected {
            "\(device.kind.label) · \(device.transport.label)"
        } else {
            "\(device.kind.label) · Offline"
        }
    }
}

struct PermissionBanner: View {
    let onFinishSetup: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "exclamationmark.shield")
                .font(.caption2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Permissions missing")
                    .font(.caption2.weight(.semibold))
                Text("Scroll smoothing and gestures stay off until setup is finished.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Finish", action: onFinishSetup)
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

struct WarningBanner: View {
    let text: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
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
    let isScanning: Bool
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "computermouse.fill")
                .font(.title)
                .fontWeight(.light)
                .foregroundStyle(.tertiary)
            Text("No devices found")
                .font(.system(.callout, weight: .semibold))
            Text(
                isScanning
                    ? "Looking for paired MX devices…"
                    : "Pair your MX device, then scan again."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            if isScanning {
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                Button("Scan again", action: onScan)
                    .buttonStyle(FilledButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .fill(Color.panelFill)
        )
    }
}
