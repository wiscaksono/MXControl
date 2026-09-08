import MXControlHIDPP
import SwiftUI

// MARK: - Shared Menu Bar Components

/// SF Symbol name for a device type.
func deviceIconName(for type: DeviceType) -> String {
    switch type {
    case .mouse: return "computermouse.fill"
    case .keyboard: return "keyboard.fill"
    default: return "questionmark.circle"
    }
}

/// USB/BLE transport badge shown next to device names.
struct TransportBadge: View {
    let type: TransportType

    var body: some View {
        Text(type.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(type == .ble ? .blue : .secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(type == .ble
                        ? Color.blue.opacity(0.12)
                        : Color.secondary.opacity(0.12))
            )
    }
}

/// Orange warning banner for permission and load failures.
struct WarningBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
