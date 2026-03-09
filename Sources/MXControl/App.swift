import AppKit
import os
import ServiceManagement
import SwiftUI

/// Global logger for MXControl.
let logger = Logger(subsystem: "com.mxcontrol.app", category: "general")

@main
struct MXControlApp: App {
    @State private var deviceManager = DeviceManager()

    /// Menu bar icon loaded from bundle Resources as a template image.
    private static let menuBarIcon: NSImage = {
        let img: NSImage
        if let url = Bundle.main.url(forResource: "logi-logo", withExtension: "png"),
           let loaded = NSImage(contentsOf: url) {
            img = loaded
        } else {
            // Fallback to SF Symbol if resource not found
            img = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MXControl")!
        }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(deviceManager)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var selectedDevice: LogiDevice?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            navHeader
            Divider()
            navContent
            Divider()
            navFooter
        }
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.15), value: selectedDevice?.id)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.warning("[App] Launch at login toggle failed: \(error.localizedDescription)")
                // Revert toggle on failure
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var navHeader: some View {
        if let device = selectedDevice {
            // Detail mode: back button + device name
            HStack(spacing: 6) {
                Button {
                    selectedDevice = nil
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Image(systemName: iconForDevice(device))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let transport = deviceManager.transportType(for: device) {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            // List mode: app title
            HStack(spacing: 6) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("MXControl")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if deviceManager.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Toggle(isOn: $launchAtLogin) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Launch at Login")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var navContent: some View {
        if let device = selectedDevice {
            DeviceDetailView(device: device)
        } else {
            deviceListContent
        }
    }

    // MARK: - Device List

    @ViewBuilder
    private var deviceListContent: some View {
        if deviceManager.devices.isEmpty {
            // Empty state
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)

                Text("No Devices Found")
                    .font(.system(size: 13, weight: .medium))

                Text("Connect a Logi Bolt receiver via USB\nor pair a device via Bluetooth")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button {
                    deviceManager.stopDiscovery()
                    deviceManager.devices.removeAll()
                    deviceManager.startDiscovery()
                } label: {
                    Text("Scan for Devices")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(deviceManager.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                    DeviceRowView(
                        device: device,
                        transportType: deviceManager.transportType(for: device)
                    ) {
                        selectedDevice = device
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var navFooter: some View {
        HStack(spacing: 8) {
            Button {
                if let device = selectedDevice {
                    // Refresh selected device battery
                    Task {
                        if let mouse = device as? MouseDevice {
                            await mouse.refreshBattery()
                        } else if let keyboard = device as? KeyboardDevice {
                            await keyboard.refreshBattery()
                        }
                    }
                } else {
                    // Rescan all
                    deviceManager.stopDiscovery()
                    deviceManager.devices.removeAll()
                    selectedDevice = nil
                    deviceManager.startDiscovery()
                }
            } label: {
                Label(
                    selectedDevice != nil ? "Refresh" : "Rescan",
                    systemImage: "arrow.clockwise"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                deviceManager.stopDiscovery()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func iconForDevice(_ device: LogiDevice) -> String {
        switch device.deviceType {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    let device: LogiDevice
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
            if let mouse = device as? MouseDevice {
                BatteryIndicator(level: mouse.batteryLevel, isCharging: mouse.batteryCharging)
            } else if let keyboard = device as? KeyboardDevice {
                BatteryIndicator(level: keyboard.batteryLevel, isCharging: keyboard.batteryCharging)
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
        switch device.deviceType {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        default: return "questionmark.circle"
        }
    }
}
