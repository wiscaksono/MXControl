
import AppKit
import MXControlHIDPP
import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    private enum MenuDestination: Equatable {
        case root
        case device(UUID)
        case ble(UUID)
        case general
    }

    @Environment(DeviceManager.self) private var deviceManager
    @State private var destination: MenuDestination = .root
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(AppVisibilityPreferences.hideFromDockKey) private var hideFromDock = AppVisibilityPreferences.defaultHideFromDock

    private var activeDevice: LogiDevice? {
        guard case .device(let id) = destination else { return nil }
        return deviceManager.devices.first { $0.id == id }
    }

    private var activeBLEDevice: BLEPeripheralInfo? {
        guard case .ble(let id) = destination else { return nil }
        return deviceManager.bleDevices.first { $0.peripheralId == id }
    }

    private var showsDetailActions: Bool {
        activeDevice != nil || activeBLEDevice != nil
    }

    private var footerActionTitle: String {
        showsDetailActions ? "Refresh" : "Rescan"
    }

    /// Header icon loaded from bundle Resources as a template image.
    private static let headerIcon: NSImage = {
        let img: NSImage
        if let url = Bundle.main.url(forResource: "logi-logo", withExtension: "png"),
           let loaded = NSImage(contentsOf: url) {
            img = loaded
        } else {
            img = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MXControl") ?? NSImage()
        }
        img.isTemplate = true
        img.size = NSSize(width: 14, height: 14)
        return img
    }()

    var body: some View {
        VStack(spacing: 0) {
            navHeader
            Divider()
            navContent
            Divider()
            navFooter
        }
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.15), value: destination)
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
        .onChange(of: deviceManager.devices.map(\.id)) { _, currentIds in
            if case .device(let id) = destination, !currentIds.contains(id) {
                destination = .root
            }
        }
        .onChange(of: deviceManager.bleDevices.map(\.peripheralId)) { _, currentIds in
            if case .ble(let id) = destination, !currentIds.contains(id) {
                destination = .root
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var navHeader: some View {
        if let device = activeDevice {
            deviceHeader(for: device)
        } else if let bleDevice = activeBLEDevice {
            bleHeader(for: bleDevice)
        } else if destination == .general {
            generalHeader
        } else {
            rootHeader
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var navContent: some View {
        if let device = activeDevice {
            DeviceDetailView(device: device)
        } else if let bleDevice = activeBLEDevice {
            BLEDeviceDetailView(info: bleDevice)
        } else if destination == .general {
            GeneralSettingsView(
                launchAtLogin: $launchAtLogin,
                hideAppUntilReopened: $hideFromDock
            )
        } else {
            deviceListContent
        }
    }

    // MARK: - Device List

    @ViewBuilder
    private var deviceListContent: some View {
        if deviceManager.devices.isEmpty && deviceManager.bleDevices.isEmpty {
            // Empty state — context-aware guidance
            VStack(spacing: 8) {
                if deviceManager.statusMessage.contains("Input Monitoring") {
                    // TCC: Input Monitoring not granted
                    Image(systemName: "lock.shield")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)

                    Text("Permission Required")
                        .font(.system(size: 13, weight: .medium))

                    Text("MXControl needs Input Monitoring access.\nGrant it in System Settings > Privacy\n& Security > Input Monitoring.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Open System Settings")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)

                    retryButton

                } else if deviceManager.statusMessage.contains("BLE access restricted") {
                    // BLE exclusive access — macOS blocking direct HID
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)

                    Text("BLE Access Restricted")
                        .font(.system(size: 13, weight: .medium))

                    Text("macOS is blocking direct BLE HID access.\nConnect via USB Bolt receiver instead,\nor quit Logi Options+ and retry.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    retryButton

                } else {
                    // Default: no devices found
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
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 0) {
                // USB/IOKit devices (full HID++ control)
                ForEach(Array(deviceManager.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                    DeviceRowView(
                        device: device,
                        transportType: deviceManager.transportType(for: device)
                    ) {
                        destination = .device(device.id)
                    }
                }

                // BLE-only devices (battery + info only)
                ForEach(Array(deviceManager.bleDevices.enumerated()), id: \.element.peripheralId) { index, bleDevice in
                    if !deviceManager.devices.isEmpty || index > 0 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                    BLEDeviceRowView(info: bleDevice) {
                        destination = .ble(bleDevice.peripheralId)
                    }
                }
            }
        }
    }

    // MARK: - Retry Button

    private var retryButton: some View {
        Button {
            deviceManager.stopDiscovery()
            deviceManager.devices.removeAll()
            deviceManager.startDiscovery()
        } label: {
            Text("Retry")
                .font(.system(size: 11))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var navFooter: some View {
        HStack(spacing: 8) {
            Button {
                if let device = activeDevice {
                    // Refresh selected device battery.
                    Task { [device] in
                        await device.refreshBattery()
                    }
                } else if activeBLEDevice != nil {
                    // BLE device: no HID++ refresh available, just a no-op.
                    // Battery updates come via GATT notify subscription automatically.
                } else {
                    rescanDevices()
                }
            } label: {
                Label(footerActionTitle, systemImage: "arrow.clockwise")
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

    private var rootHeader: some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.headerIcon)
                .foregroundStyle(.secondary)

            Text("MXControl")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if deviceManager.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Button {
                destination = .general
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("General Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var generalHeader: some View {
        HStack(spacing: 6) {
            backButton {
                destination = .root
            }

            Spacer()

            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("General")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func deviceHeader(for device: LogiDevice) -> some View {
        HStack(spacing: 6) {
            backButton {
                destination = .root
            }

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
    }

    private func bleHeader(for bleDevice: BLEPeripheralInfo) -> some View {
        HStack(spacing: 6) {
            backButton {
                destination = .root
            }

            Spacer()

            Image(systemName: iconForBLEDevice(bleDevice))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text(bleDevice.name)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func rescanDevices() {
        deviceManager.stopDiscovery()
        deviceManager.devices.removeAll()
        deviceManager.startDiscovery()
    }

    private func iconForDevice(_ device: LogiDevice) -> String {
        switch device.deviceType {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        default: return "questionmark.circle"
        }
    }

    private func iconForBLEDevice(_ info: BLEPeripheralInfo) -> String {
        switch info.deviceType {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        default: return "questionmark.circle"
        }
    }
}
