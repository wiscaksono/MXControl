import os
import SwiftUI

/// Global logger for MXControl.
let logger = Logger(subsystem: "com.mxcontrol.app", category: "general")

@main
struct MXControlApp: App {
    @State private var deviceManager = DeviceManager()

    var body: some Scene {
        MenuBarExtra("MXControl", systemImage: "computermouse.fill") {
            MenuBarView(deviceManager: deviceManager)
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @Bindable var deviceManager: DeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("MXControl")
                    .font(.headline)
                Spacer()
                Text("v0.1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Status
            HStack {
                Circle()
                    .fill(deviceManager.isScanning ? .orange : (deviceManager.devices.isEmpty ? .red : .green))
                    .frame(width: 8, height: 8)
                Text(deviceManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Device list
            if deviceManager.devices.isEmpty {
                Text("No devices found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(deviceManager.devices) { device in
                    DeviceRow(device: device)
                }
            }

            Divider()

            // Actions
            Button("Rescan") {
                deviceManager.stopDiscovery()
                deviceManager.devices.removeAll()
                deviceManager.startDiscovery()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button("Quit") {
                deviceManager.stopDiscovery()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(width: 280)
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: LogiDevice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.deviceType == .mouse ? "computermouse.fill" : "keyboard.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(device.deviceKind.description)
                    Text("\u{00B7}")
                    Text("HID++ \(device.protocolMajor).\(device.protocolMinor)")
                    Text("\u{00B7}")
                    Text("\(device.features.count) features")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
