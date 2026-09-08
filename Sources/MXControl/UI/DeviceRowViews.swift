
import MXControlHIDPP
import SwiftUI

// MARK: - Device Row View

struct DeviceRowView: View {
    @Bindable var device: LogiDevice
    var transportType: TransportType?
    var onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Device icon (transport is communicated by the badge, no overlay needed)
            Image(systemName: deviceIcon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(device.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            // Transport badge
            if let transport = transportType {
                Text(transport.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(transport == .ble ? .blue : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(transport == .ble
                                ? Color.blue.opacity(0.12)
                                : Color.secondary.opacity(0.12))
                    )
            }

            Spacer()

            // Battery indicator
            BatteryIndicator(level: device.battery.level, isCharging: device.battery.charging)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            isHovered
                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                : .clear
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    private var deviceIcon: String {
        switch device.deviceType {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - BLE Device Row View

struct BLEDeviceRowView: View {
    let info: BLEPeripheralInfo
    var onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: deviceIcon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(info.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Text("BLE")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.12))
                )

            Spacer()

            if let battery = info.batteryLevel {
                BatteryIndicator(level: battery, isCharging: false)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            isHovered
                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                : .clear
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    private var deviceIcon: String {
        switch info.deviceType {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        default: return "questionmark.circle"
        }
    }
}
