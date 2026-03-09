import Foundation
import IOKit.hid
import Observation
import os

/// Manages discovery and lifecycle of Logitech HID++ devices.
///
/// Uses USBTransport to find Bolt/Unifying receivers, then probes
/// device indices 1-6 to discover connected peripherals.
/// Applies saved settings on reconnect and refreshes battery periodically.
@Observable
@MainActor
final class DeviceManager {

    // MARK: - Published State

    var devices: [LogiDevice] = []
    var isScanning: Bool = false
    var statusMessage: String = "Idle"

    // MARK: - Private

    private var transport: USBTransport?
    private var discoveryTask: Task<Void, Never>?
    private var batteryRefreshTask: Task<Void, Never>?
    /// Guards against multiple probeReceiverDevices() from multiple HID interface matches.
    private var isProbing: Bool = false

    /// Battery refresh interval in seconds.
    private let batteryRefreshInterval: TimeInterval = 300  // 5 minutes

    // MARK: - Init

    init() {
        // Auto-start discovery on creation
        Task { @MainActor [self] in
            self.startDiscovery()
        }
    }

    // MARK: - Discovery

    /// Start USB discovery. Sets up IOHIDManager, watches for Logitech receivers.
    func startDiscovery() {
        guard transport == nil else { return }

        logger.info("[DeviceManager] Starting USB discovery...")
        statusMessage = "Starting USB discovery..."
        isScanning = true

        let usb = USBTransport()
        self.transport = usb

        // When a device is matched, check if it's a receiver and probe sub-devices
        usb.onDeviceMatched = { [weak self] device in
            let pid = USBTransport.productId(of: device)
            let name = USBTransport.productName(of: device)

            logger.info("[DeviceManager] Matched: \(name) (PID: \(String(format: "0x%04X", pid)))")

            if DeviceRegistry.isReceiver(pid: pid) {
                logger.info("[DeviceManager] Detected Bolt/Unifying receiver, probing sub-devices...")
                Task { @MainActor [weak self] in
                    guard let self, !self.isProbing, self.devices.isEmpty else {
                        debugLog("[DeviceManager] Skipping duplicate probe (isProbing=\(self?.isProbing ?? false) devices=\(self?.devices.count ?? 0))")
                        return
                    }
                    await self.probeReceiverDevices()
                }
            } else {
                logger.debug("[DeviceManager] Not a receiver, skipping: PID \(String(format: "0x%04X", pid))")
            }
        }

        usb.onDeviceRemoved = { [weak self] in
            Task { @MainActor [weak self] in
                debugLog("[DeviceManager] Device removed, clearing device list")
                logger.info("[DeviceManager] Device removed, clearing device list")
                self?.devices.removeAll()
                self?.isProbing = false
                self?.statusMessage = "Device disconnected"
                self?.stopBatteryRefresh()
            }
        }

        Task {
            do {
                try await usb.open()
                logger.info("[DeviceManager] IOHIDManager opened, scanning for Logitech receivers...")
                statusMessage = "Scanning for Logitech receivers..."
            } catch {
                logger.error("[DeviceManager] Failed to open IOHIDManager: \(error.localizedDescription)")
                statusMessage = "Error: \(error.localizedDescription)"
                isScanning = false
            }
        }
    }

    /// Stop discovery and clean up.
    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        stopBatteryRefresh()
        transport?.close()
        transport = nil
        isScanning = false
        statusMessage = "Stopped"
    }

    // MARK: - Receiver Probe

    /// Probe device indices 1-6 on the receiver to find connected devices.
    ///
    /// Flow:
    /// 1. Ping each index (1-6) with timeout to find active devices.
    /// 2. For each responding device, run base initialization (name + features).
    /// 3. Based on deviceType, create MouseDevice or KeyboardDevice.
    /// 4. Load device-specific features (battery, DPI, SmartShift, etc.).
    /// 5. Apply saved settings from UserDefaults.
    private func probeReceiverDevices() async {
        guard let transport else { return }
        guard !isProbing else {
            debugLog("[DeviceManager] probeReceiverDevices: already probing, skipping")
            return
        }
        isProbing = true
        defer { isProbing = false }

        statusMessage = "Probing receiver for devices..."
        logger.info("[DeviceManager] Probing receiver indices 1-6...")
        var discovered: [LogiDevice] = []

        // Probe indices 1 through 6
        for index in UInt8(1)...UInt8(6) {
            do {
                // Ping with timeout to check if device exists at this index
                let _ = try await transport.sendWithTimeout(
                    deviceIndex: index,
                    featureIndex: 0x00,
                    functionId: 0x01,
                    params: [0x00, 0x00, 0xAA],
                    timeout: 1.5
                )

                logger.info("[DeviceManager] Device found at index \(index), initializing...")

                // First pass: discover identity using a temporary LogiDevice
                let probe = LogiDevice(deviceIndex: index, transport: transport)
                try await probe.initialize()

                // Promote to typed device based on discovered type
                let device: LogiDevice
                switch probe.deviceType {
                case .mouse:
                    let mouse = MouseDevice(deviceIndex: index, transport: transport)
                    try await mouse.initialize()
                    await mouse.loadMouseFeatures()
                    // Apply saved settings
                    await SettingsStore.applyMouseSettings(to: mouse)
                    device = mouse
                    logger.info("[DeviceManager] Promoted index \(index) to MouseDevice")

                case .keyboard:
                    let keyboard = KeyboardDevice(deviceIndex: index, transport: transport)
                    try await keyboard.initialize()
                    await keyboard.loadKeyboardFeatures()
                    // Apply saved settings
                    await SettingsStore.applyKeyboardSettings(to: keyboard)
                    device = keyboard
                    logger.info("[DeviceManager] Promoted index \(index) to KeyboardDevice")

                default:
                    device = probe
                    logger.info("[DeviceManager] Index \(index) is unknown type, keeping as LogiDevice")
                }

                discovered.append(device)

            } catch let error as HIDPPError {
                switch error {
                case .timeout:
                    logger.debug("[DeviceManager] No device at index \(index) (timeout)")
                case .hidppError(let code, _):
                    logger.debug("[DeviceManager] No device at index \(index) (HID++ error: \(code.name))")
                default:
                    logger.warning("[DeviceManager] Error probing index \(index): \(error.localizedDescription)")
                }
                continue
            } catch {
                logger.warning("[DeviceManager] Error probing index \(index): \(error)")
                continue
            }
        }

        self.devices = discovered
        isScanning = false
        statusMessage = "Found \(discovered.count) device(s)"
        logger.info("[DeviceManager] Discovery complete: found \(discovered.count) device(s)")

        // Set up notification routing for diverted button events, rawXY, etc.
        setupNotificationRouting()

        if discovered.isEmpty {
            logger.warning("[DeviceManager] No devices found on receiver")
        } else {
            startBatteryRefresh()
        }
    }

    // MARK: - Notification Routing

    /// Set up notification routing from the USB transport to the correct device.
    /// Unsolicited HID++ packets (diverted button events, rawXY, battery status changes)
    /// are forwarded to the appropriate device based on the device index in the packet.
    private func setupNotificationRouting() {
        guard let transport else { return }

        // Build a lookup table: deviceIndex → MouseDevice (for notification routing)
        // We only route to mice for now (gesture engine).
        let deviceMap: [UInt8: MouseDevice] = {
            var map: [UInt8: MouseDevice] = [:]
            for device in self.devices {
                if let mouse = device as? MouseDevice {
                    map[mouse.deviceIndex] = mouse
                }
            }
            return map
        }()

        transport.notificationHandler = { [deviceMap] deviceIndex, featureIndex, functionId, params in
            debugLog("[DeviceManager] Notification: dev=\(deviceIndex) feat=\(String(format: "0x%02X", featureIndex)) func=\(functionId) -> mouse=\(deviceMap[deviceIndex] != nil)")
            if let mouse = deviceMap[deviceIndex] {
                mouse.handleNotification(featureIndex: featureIndex, functionId: functionId, params: params)
            }
        }

        debugLog("[DeviceManager] Notification routing set up for \(deviceMap.count) mouse device(s): indices=\(deviceMap.keys.sorted())")
        logger.info("[DeviceManager] Notification routing set up for \(deviceMap.count) mouse device(s)")
    }

    // MARK: - Battery Refresh

    /// Start periodic battery refresh for all connected devices.
    private func startBatteryRefresh() {
        stopBatteryRefresh()

        batteryRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.batteryRefreshInterval ?? 300))
                guard !Task.isCancelled else { break }

                guard let self else { break }
                for device in self.devices {
                    if let mouse = device as? MouseDevice {
                        await mouse.refreshBattery()
                    } else if let keyboard = device as? KeyboardDevice {
                        await keyboard.refreshBattery()
                    }
                }
                logger.debug("[DeviceManager] Battery refresh complete")
            }
        }
    }

    /// Stop periodic battery refresh.
    private func stopBatteryRefresh() {
        batteryRefreshTask?.cancel()
        batteryRefreshTask = nil
    }

    // MARK: - Save Settings

    /// Save current settings for a mouse device.
    func saveMouseSettings(_ mouse: MouseDevice) {
        let settings = SettingsStore.MouseSettings(
            dpi: mouse.currentDPI,
            pointerSpeed: mouse.pointerSpeed,
            smartShiftActive: mouse.smartShiftActive,
            smartShiftTorque: mouse.smartShiftTorque,
            smartShiftWheelMode: mouse.smartShiftWheelMode.rawValue,
            hiResEnabled: mouse.hiResEnabled,
            hiResInverted: mouse.hiResInverted,
            thumbWheelInverted: mouse.thumbWheelInverted,
            buttonRemaps: mouse.buttonRemaps.isEmpty ? nil : mouse.buttonRemaps,
            gestureClickTimeLimit: mouse.gestureClickTimeLimit,
            gestureDragThreshold: mouse.gestureDragThreshold
        )
        SettingsStore.saveMouseSettings(settings, deviceName: mouse.name)
    }

    /// Save current settings for a keyboard device.
    func saveKeyboardSettings(_ keyboard: KeyboardDevice) {
        let settings = SettingsStore.KeyboardSettings(
            backlightEnabled: keyboard.backlightEnabled,
            backlightLevel: keyboard.backlightLevel,
            fnInverted: keyboard.fnInverted
        )
        SettingsStore.saveKeyboardSettings(settings, deviceName: keyboard.name)
    }
}

// MARK: - HIDPPError Equatable

extension HIDPPError: Equatable {
    static func == (lhs: HIDPPError, rhs: HIDPPError) -> Bool {
        switch (lhs, rhs) {
        case (.transportNotOpen, .transportNotOpen): return true
        case (.timeout, .timeout): return true
        case (.deviceNotFound, .deviceNotFound): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.transportError(let a), .transportError(let b)): return a == b
        case (.featureNotSupported(let a), .featureNotSupported(let b)): return a == b
        case (.unknownReportId(let a), .unknownReportId(let b)): return a == b
        case (.hidppError(let c1, let f1), .hidppError(let c2, let f2)): return c1 == c2 && f1 == f2
        default: return false
        }
    }
}
