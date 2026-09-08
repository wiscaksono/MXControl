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
            Image(systemName: deviceIconName(for: device.deviceType))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(device.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            // Transport badge
            if let transportType {
                TransportBadge(type: transportType)
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
}

// MARK: - BLE Device Row View

struct BLEDeviceRowView: View {
    let info: BLEPeripheralInfo
    var onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: deviceIconName(for: info.deviceType))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(info.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            TransportBadge(type: .ble)

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
}
