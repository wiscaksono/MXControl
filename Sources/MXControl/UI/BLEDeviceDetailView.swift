
import MXControlHIDPP
import SwiftUI

// MARK: - BLE Device Detail View

struct BLEDeviceDetailView: View {
    let info: BLEPeripheralInfo

    var body: some View {
        VStack(spacing: 12) {
            // Battery
            if let battery = info.batteryLevel {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Battery")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            BatteryIndicator(level: battery, isCharging: false)
                        }
                    }
                    .padding(.horizontal, 12)
                }

                Divider().padding(.horizontal, 12)

                // Device Information
                VStack(spacing: 6) {
                    if let manufacturer = info.manufacturer {
                        infoRow(label: "Manufacturer", value: manufacturer)
                    }
                    if let model = info.modelNumber {
                        infoRow(label: "Model", value: model)
                    }
                    if let firmware = info.firmwareRevision {
                        infoRow(label: "Firmware", value: firmware)
                    }
                    if let serial = info.serialNumber {
                        infoRow(label: "Serial", value: serial)
                    }
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                // Connection info + USB hint
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                        Text("Connected via Bluetooth LE")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("Connect via USB Bolt receiver for full control (DPI, SmartShift, backlight, etc.)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
            }
        .padding(.vertical, 10)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}
