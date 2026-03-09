import Foundation
import IOKit.hid
import Observation
import os

/// The transport type through which a device was discovered.
enum TransportType: String, Sendable {
    case usb = "USB"
    case ble = "BLE"
}

/// Manages discovery and lifecycle of Logitech HID++ devices.
///
/// Uses a single IOHIDManager (via USBTransport) that discovers BOTH:
///   - USB: Bolt/Unifying receivers (UsagePage=0xFF00, Usage=0x01) → probes indices 1-6
///   - BLE: Direct BLE devices (UsagePage=0xFF43, Usage=0x0202) → deviceIndex=0x01
///
/// When the same device is found on both USB and BLE, USB is preferred (lower latency).
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

    /// Track which device names were discovered via USB (for dedup against BLE).
    private var usbDeviceNames: Set<String> = []

    /// Track transport type per device (by LogiDevice.id).
    private(set) var deviceTransportType: [UUID: TransportType] = [:]

    /// Map from IOKit device UID → LogiDevice.id, for removal routing.
    private var uidToDeviceId: [String: UUID] = [:]

    /// Map from LogiDevice.id → IOKit device UID, for send routing.
    private var deviceIdToUID: [UUID: String] = [:]

    /// BLE device UIDs currently being initialized — prevents concurrent init from re-enumeration.
    private var initializingBLEUIDs: Set<String> = []

    /// BLE device UIDs that have been successfully initialized — prevents re-init on re-enumeration.
    private var initializedBLEUIDs: Set<String> = []

    // MARK: - Init

    init() {
        // Auto-start discovery on creation
        Task { @MainActor [self] in
            self.startDiscovery()
        }
    }

    // MARK: - Discovery

    /// Start discovery via IOHIDManager (handles both USB and BLE).
    func startDiscovery() {
        guard transport == nil else { return }

        logger.info("[DeviceManager] Starting discovery (USB + BLE via IOKit)...")
        statusMessage = "Starting discovery..."
        isScanning = true

        let t = USBTransport()
        self.transport = t

        // USB receiver matched — probe sub-devices 1-6
        t.onReceiverMatched = { [weak self] info in
            logger.info("[DeviceManager] USB receiver matched: \(info.name) PID=\(String(format: "0x%04X", info.pid))")
            Task { @MainActor [weak self] in
                guard let self, !self.isProbing else {
                    debugLog("[DeviceManager] Skipping duplicate probe (isProbing=\(self?.isProbing ?? false))")
                    return
                }
                await self.probeReceiverDevices(receiverUID: info.uid)
            }
        }

        // BLE direct device matched — initialize as direct device
        t.onBLEDeviceMatched = { [weak self] info in
            logger.info("[DeviceManager] BLE device matched via IOKit: \(info.name) PID=\(String(format: "0x%04X", info.pid))")
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.initializeBLEDevice(info: info)
            }
        }

        // Device removed
        t.onDeviceRemoved = { [weak self] info in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleDeviceRemoved(info: info)
            }
        }

        Task {
            do {
                try await t.open()
                logger.info("[DeviceManager] IOHIDManager opened, scanning for Logitech devices (USB + BLE)...")
            } catch {
                logger.error("[DeviceManager] Failed to open IOHIDManager: \(error.localizedDescription)")
            }
        }
    }

    /// Stop all discovery and clean up.
    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        stopBatteryRefresh()

        transport?.close()
        transport = nil

        usbDeviceNames.removeAll()
        deviceTransportType.removeAll()
        uidToDeviceId.removeAll()
        deviceIdToUID.removeAll()
        initializingBLEUIDs.removeAll()
        initializedBLEUIDs.removeAll()
        isScanning = false
        statusMessage = "Stopped"
    }

    // MARK: - USB Receiver Probe

    /// Probe device indices 1-6 on the receiver to find connected devices.
    ///
    /// Flow:
    /// 1. Ping each index (1-6) with timeout to find active devices.
    /// 2. For each responding device, run base initialization (name + features).
    /// 3. Based on deviceType, create MouseDevice or KeyboardDevice.
    /// 4. Load device-specific features (battery, DPI, SmartShift, etc.).
    /// 5. Apply saved settings from UserDefaults.
    private func probeReceiverDevices(receiverUID: String) async {
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

        // Create an adapter targeting the receiver's IOHIDDevice
        let adapter = DeviceTransportAdapter(transport: transport, targetDeviceUID: receiverUID)

        // Probe indices 1 through 6
        for index in UInt8(1)...UInt8(6) {
            do {
                // Ping with timeout to check if device exists at this index
                let _ = try await adapter.sendWithTimeout(
                    deviceIndex: index,
                    featureIndex: 0x00,
                    functionId: 0x01,
                    params: [0x00, 0x00, 0xAA],
                    timeout: 1.5
                )

                logger.info("[DeviceManager] Device found at index \(index), initializing...")

                // First pass: discover identity using a temporary LogiDevice
                let probe = LogiDevice(deviceIndex: index, transport: adapter)
                try await probe.initialize()

                // Track USB device names for BLE dedup
                usbDeviceNames.insert(probe.name)

                // Check if this device is already connected via BLE — if so, remove the BLE version
                removeDuplicateBLEDevice(name: probe.name)

                // Promote to typed device based on discovered type
                let device: LogiDevice
                switch probe.deviceType {
                case .mouse:
                    let mouse = MouseDevice(deviceIndex: index, transport: adapter)
                    try await mouse.initialize()
                    await mouse.loadMouseFeatures()
                    await SettingsStore.applyMouseSettings(to: mouse)
                    device = mouse
                    logger.info("[DeviceManager] Promoted index \(index) to MouseDevice")

                case .keyboard:
                    let keyboard = KeyboardDevice(deviceIndex: index, transport: adapter)
                    try await keyboard.initialize()
                    await keyboard.loadKeyboardFeatures()
                    await SettingsStore.applyKeyboardSettings(to: keyboard)
                    device = keyboard
                    logger.info("[DeviceManager] Promoted index \(index) to KeyboardDevice")

                default:
                    device = probe
                    logger.info("[DeviceManager] Index \(index) is unknown type, keeping as LogiDevice")
                }

                discovered.append(device)
                uidToDeviceId["\(receiverUID):\(index)"] = device.id
                deviceIdToUID[device.id] = receiverUID

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

        // Add USB devices to list (keep any existing BLE-only devices)
        for device in discovered {
            devices.append(device)
            deviceTransportType[device.id] = .usb
        }

        isScanning = false
        updateStatus()
        logger.info("[DeviceManager] USB discovery complete: found \(discovered.count) device(s)")

        setupNotificationRouting()

        if !devices.isEmpty {
            startBatteryRefresh()
        } else {
            logger.warning("[DeviceManager] No devices found on receiver")
        }
    }

    // MARK: - BLE Direct Device Initialization

    /// Initialize a BLE device discovered via IOKit.
    /// BLE direct devices use deviceIndex=0x01 (they are their own "receiver").
    private func initializeBLEDevice(info: IOKitDeviceInfo) async {
        guard let transport else { return }

        let deviceIndex: UInt8 = 0x01

        // Guard: skip if this UID is already being initialized or was already initialized
        if initializingBLEUIDs.contains(info.uid) {
            debugLog("[DeviceManager] BLE IOKit skip \(info.name) — already initializing uid=\(info.uid)")
            return
        }
        if initializedBLEUIDs.contains(info.uid) {
            debugLog("[DeviceManager] BLE IOKit skip \(info.name) — already initialized uid=\(info.uid)")
            return
        }

        // Dedup: skip if same device name already found via USB
        if usbDeviceNames.contains(info.name) {
            debugLog("[DeviceManager] BLE IOKit skip \(info.name) — already on USB")
            logger.info("[DeviceManager] Skipping BLE device \(info.name) — already connected via USB")
            return
        }

        initializingBLEUIDs.insert(info.uid)
        defer { initializingBLEUIDs.remove(info.uid) }

        debugLog("[DeviceManager] BLE IOKit: initializing \(info.name) PID=\(String(format: "0x%04X", info.pid)) uid=\(info.uid)")
        statusMessage = "Connecting to \(info.name)..."

        // Create an adapter targeting this specific BLE device
        let adapter = DeviceTransportAdapter(transport: transport, targetDeviceUID: info.uid)

        do {
            // Ping to confirm device is responsive
            debugLog("[DeviceManager] BLE IOKit: pinging \(info.name) at deviceIndex=\(deviceIndex)...")
            let _ = try await adapter.sendWithTimeout(
                deviceIndex: deviceIndex,
                featureIndex: 0x00,
                functionId: 0x01,
                params: [0x00, 0x00, 0xBB],
                timeout: 3.0
            )

            debugLog("[DeviceManager] BLE IOKit: ping succeeded for \(info.name)!")
            logger.info("[DeviceManager] BLE device \(info.name) responded to ping")

            // First pass: discover identity
            let probe = LogiDevice(deviceIndex: deviceIndex, transport: adapter)
            try await probe.initialize()

            // Re-check dedup after initialization (name might differ from IOKit product name)
            if usbDeviceNames.contains(probe.name) {
                debugLog("[DeviceManager] BLE IOKit skip \(probe.name) — already on USB (post-init dedup)")
                return
            }

            // Promote to typed device
            let device: LogiDevice
            switch probe.deviceType {
            case .mouse:
                let mouse = MouseDevice(deviceIndex: deviceIndex, transport: adapter)
                try await mouse.initialize()
                await mouse.loadMouseFeatures()
                await SettingsStore.applyMouseSettings(to: mouse)
                device = mouse
                logger.info("[DeviceManager] BLE: Promoted \(info.name) to MouseDevice")

            case .keyboard:
                let keyboard = KeyboardDevice(deviceIndex: deviceIndex, transport: adapter)
                try await keyboard.initialize()
                await keyboard.loadKeyboardFeatures()
                await SettingsStore.applyKeyboardSettings(to: keyboard)
                device = keyboard
                logger.info("[DeviceManager] BLE: Promoted \(info.name) to KeyboardDevice")

            default:
                device = probe
                logger.info("[DeviceManager] BLE: \(info.name) is unknown type, keeping as LogiDevice")
            }

            devices.append(device)
            deviceTransportType[device.id] = .ble
            uidToDeviceId[info.uid] = device.id
            deviceIdToUID[device.id] = info.uid
            initializedBLEUIDs.insert(info.uid)

            updateStatus()
            setupNotificationRouting()

            if !devices.isEmpty {
                startBatteryRefresh()
            }

        } catch {
            debugLog("[DeviceManager] BLE IOKit init failed for \(info.name): \(error)")
            logger.warning("[DeviceManager] Failed to initialize BLE device \(info.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Device Removal

    private func handleDeviceRemoved(info: IOKitDeviceInfo) {
        debugLog("[DeviceManager] Device removed: \(info.name) uid=\(info.uid) type=\(info.transport.rawValue)")
        logger.info("[DeviceManager] Device removed: \(info.name) [\(info.transport.rawValue)]")

        switch info.transport {
        case .usb:
            // USB receiver removed — remove all USB-discovered devices
            let usbDeviceIds = deviceTransportType.filter { $0.value == .usb }.map(\.key)
            devices.removeAll { usbDeviceIds.contains($0.id) }
            for id in usbDeviceIds {
                deviceTransportType.removeValue(forKey: id)
                if let uid = deviceIdToUID.removeValue(forKey: id) {
                    uidToDeviceId.removeValue(forKey: uid)
                }
            }
            usbDeviceNames.removeAll()
            isProbing = false

        case .ble:
            // BLE device removed — remove just that device
            if let deviceId = uidToDeviceId[info.uid] {
                devices.removeAll { $0.id == deviceId }
                deviceTransportType.removeValue(forKey: deviceId)
                deviceIdToUID.removeValue(forKey: deviceId)
            }
            uidToDeviceId.removeValue(forKey: info.uid)
            initializedBLEUIDs.remove(info.uid)
        }

        if devices.isEmpty {
            statusMessage = "Device disconnected"
            stopBatteryRefresh()
        } else {
            updateStatus()
        }
    }

    // MARK: - Dedup

    /// Remove a BLE-discovered device if USB found the same device (by name).
    /// USB is preferred due to lower latency.
    private func removeDuplicateBLEDevice(name: String) {
        guard let bleDevice = devices.first(where: {
            $0.name == name && deviceTransportType[$0.id] == .ble
        }) else { return }

        debugLog("[DeviceManager] Removing BLE duplicate: \(name) (USB preferred)")
        logger.info("[DeviceManager] Removing BLE duplicate \(name) — USB connection preferred")

        devices.removeAll { $0.id == bleDevice.id }
        deviceTransportType.removeValue(forKey: bleDevice.id)
        if let uid = deviceIdToUID.removeValue(forKey: bleDevice.id) {
            uidToDeviceId.removeValue(forKey: uid)
        }
    }

    // MARK: - Notification Routing

    /// Set up notification routing from transports to the correct device.
    /// Unsolicited HID++ packets (diverted button events, rawXY, battery status changes)
    /// are forwarded to the appropriate device based on the device index in the packet.
    private func setupNotificationRouting() {
        guard let transport else { return }

        // Build a map from (senderUID + deviceIndex) → MouseDevice for routing
        var mouseMap: [String: MouseDevice] = [:]  // "uid:deviceIndex" → MouseDevice

        for device in devices {
            guard let mouse = device as? MouseDevice else { continue }
            if let uid = deviceIdToUID[device.id] {
                let transportType = deviceTransportType[device.id]
                if transportType == .usb {
                    // USB: route by receiver UID + deviceIndex
                    mouseMap["\(uid):\(mouse.deviceIndex)"] = mouse
                } else {
                    // BLE: route by device UID + deviceIndex (always 0x01)
                    mouseMap["\(uid):\(mouse.deviceIndex)"] = mouse
                }
            }
        }

        transport.notificationHandler = { [mouseMap] senderUID, deviceIndex, featureIndex, functionId, params in
            debugLog("[DeviceManager] Notification: sender=\(senderUID) dev=\(deviceIndex) feat=\(String(format: "0x%02X", featureIndex)) func=\(functionId)")
            let key = "\(senderUID):\(deviceIndex)"
            if let mouse = mouseMap[key] {
                mouse.handleNotification(featureIndex: featureIndex, functionId: functionId, params: params)
            }
        }

        let totalDevices = self.devices.count
        debugLog("[DeviceManager] Notification routing configured: \(mouseMap.count) mouse(s)")
        logger.info("[DeviceManager] Notification routing configured for \(totalDevices) device(s)")
    }

    // MARK: - Status

    private func updateStatus() {
        let usbCount = deviceTransportType.values.filter { $0 == .usb }.count
        let bleCount = deviceTransportType.values.filter { $0 == .ble }.count

        if devices.isEmpty {
            statusMessage = "No devices found"
        } else {
            var parts: [String] = []
            if usbCount > 0 { parts.append("\(usbCount) USB") }
            if bleCount > 0 { parts.append("\(bleCount) BLE") }
            statusMessage = "Found \(devices.count) device(s) (\(parts.joined(separator: ", ")))"
        }
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

    // MARK: - Public Helpers

    /// Get the transport type for a device.
    func transportType(for device: LogiDevice) -> TransportType? {
        deviceTransportType[device.id]
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
