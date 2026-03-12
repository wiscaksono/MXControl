import CoreBluetooth
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

    // MARK: - CoreBluetooth BLE (read-only: battery + device info)

    /// CoreBluetooth scanner for BLE Logitech devices.
    private var bleScanner: BLEScanner?

    /// Active BLEInfoService instances, keyed by CBPeripheral UUID.
    private var bleInfoServices: [UUID: BLEInfoService] = [:]

    /// BLE-only devices discovered via CoreBluetooth (battery + device info only).
    /// These are NOT full LogiDevice instances — HID++ is inaccessible via BLE.
    var bleDevices: [BLEDeviceInfo] = []

    /// CBPeripheral UUIDs currently being initialized — prevents concurrent init.
    private var initializingCBPeripherals: Set<UUID> = []

    /// CBPeripheral UUIDs that have been successfully initialized.
    private var initializedCBPeripherals: Set<UUID> = []

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
            logger.info("[DeviceManager] USB receiver matched: \(info.name, privacy: .public) PID=\(String(format: "0x%04X", info.pid), privacy: .public)")
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
            logger.info("[DeviceManager] BLE device matched via IOKit: \(info.name, privacy: .public) PID=\(String(format: "0x%04X", info.pid), privacy: .public)")
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

        // BLE device successfully opened after retry (was previously in receive-only mode)
        t.onBLEDeviceOpened = { [weak self] info in
            logger.info("[DeviceManager] BLE device opened after retry: \(info.name, privacy: .public)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Allow re-initialization by clearing the previous state
                self.initializedBLEUIDs.remove(info.uid)
                await self.initializeBLEDevice(info: info)
            }
        }

        // BLE device re-acquired after IOKit re-enumeration — re-arm volatile state
        t.onBLEDeviceReconnected = { [weak self] uid in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleBLEDeviceReconnected(uid: uid)
            }
        }

        Task {
            do {
                try await t.open()
                logger.info("[DeviceManager] IOHIDManager opened, scanning for Logitech devices (USB + BLE)...")
            } catch HIDPPError.tccDenied {
                logger.error("[DeviceManager] TCC denied — Input Monitoring permission not granted")
                self.transport = nil
                self.isScanning = false
                self.statusMessage = "Input Monitoring permission required"
            } catch {
                logger.error("[DeviceManager] Failed to open IOHIDManager: \(error.localizedDescription, privacy: .public)")
                // Reset state so startDiscovery() can be called again (e.g. via Rescan button)
                self.transport = nil
                self.isScanning = false
                self.statusMessage = "Failed to open HID manager"
            }
        }

        // Start CoreBluetooth scanner in parallel — handles BLE devices that IOKit can't access
        startBLEScanner()
    }

    /// Stop all discovery and clean up.
    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        stopBatteryRefresh()

        transport?.close()
        transport = nil

        // Stop CoreBluetooth scanner and close all BLE info services
        bleScanner?.stopScanning()
        bleScanner = nil
        for (_, svc) in bleInfoServices { svc.close() }
        bleInfoServices.removeAll()
        bleDevices.removeAll()
        initializingCBPeripherals.removeAll()
        initializedCBPeripherals.removeAll()

        usbDeviceNames.removeAll()
        deviceTransportType.removeAll()
        uidToDeviceId.removeAll()
        deviceIdToUID.removeAll()
        initializingBLEUIDs.removeAll()
        initializedBLEUIDs.removeAll()
        BatteryNotifier.reset()
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

                // Discover identity and create typed device (mouse/keyboard)
                let probe = LogiDevice(deviceIndex: index, transport: adapter)
                try await probe.initialize()

                // Track USB device names for BLE dedup
                usbDeviceNames.insert(probe.name)

                // Check if this device is already connected via BLE — if so, remove the BLE version
                removeDuplicateBLEDevice(name: probe.name)

                let device = await createTypedDevice(from: probe, adapter: adapter)

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
                    logger.warning("[DeviceManager] Error probing index \(index): \(error.localizedDescription, privacy: .public)")
                }
                continue
            } catch {
                logger.warning("[DeviceManager] Error probing index \(index): \(error, privacy: .public)")
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

    // MARK: - Typed Device Creation

    /// Create a typed device (MouseDevice/KeyboardDevice) from a probe, reusing its
    /// discovered identity and feature cache to avoid redundant HID++ round-trips.
    private func createTypedDevice(
        from probe: LogiDevice,
        adapter: DeviceTransportAdapter
    ) async -> LogiDevice {
        switch probe.deviceType {
        case .mouse:
            let mouse = MouseDevice(deviceIndex: probe.deviceIndex, transport: adapter)
            await mouse.transferIdentity(from: probe)
            await mouse.loadMouseFeatures()
            await SettingsStore.applyMouseSettings(to: mouse)
            logger.info("[DeviceManager] Promoted \(probe.name) to MouseDevice")
            return mouse

        case .keyboard:
            let keyboard = KeyboardDevice(deviceIndex: probe.deviceIndex, transport: adapter)
            await keyboard.transferIdentity(from: probe)
            await keyboard.loadKeyboardFeatures()
            await SettingsStore.applyKeyboardSettings(to: keyboard)
            logger.info("[DeviceManager] Promoted \(probe.name) to KeyboardDevice")
            return keyboard

        default:
            logger.info("[DeviceManager] \(probe.name) is unknown type, keeping as LogiDevice")
            return probe
        }
    }

    // MARK: - BLE Direct Device Initialization

    /// Initialize a BLE device discovered via IOKit.
    /// BLE direct devices use deviceIndex=0x01 (they are their own "receiver").
    private func initializeBLEDevice(info: IOKitDeviceInfo) async {
        guard let transport else { return }

        let deviceIndex: UInt8 = 0x01

        // Guard: skip if this UID is already being initialized, was already initialized, or permanently failed
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
            logger.info("[DeviceManager] Skipping BLE device \(info.name, privacy: .public) — already connected via USB")
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
                timeout: 5.0
            )

            debugLog("[DeviceManager] BLE IOKit: ping succeeded for \(info.name)!")
            logger.info("[DeviceManager] BLE device \(info.name, privacy: .public) responded to ping")

            // Discover identity
            let probe = LogiDevice(deviceIndex: deviceIndex, transport: adapter)
            try await probe.initialize()

            // Re-check dedup after initialization (name might differ from IOKit product name)
            if usbDeviceNames.contains(probe.name) {
                debugLog("[DeviceManager] BLE IOKit skip \(probe.name) — already on USB (post-init dedup)")
                return
            }

            let device = await createTypedDevice(from: probe, adapter: adapter)

            devices.append(device)
            deviceTransportType[device.id] = .ble
            uidToDeviceId[info.uid] = device.id
            deviceIdToUID[device.id] = info.uid
            initializedBLEUIDs.insert(info.uid)

            // Remove duplicate CB BLEDeviceInfo (if CoreBluetooth scanner already read battery)
            if let idx = bleDevices.firstIndex(where: { $0.name == device.name }) {
                let peripheralId = bleDevices[idx].peripheralId
                debugLog("[DeviceManager] Removing CB duplicate for \(device.name) — IOKit HID++ preferred")
                bleDevices.remove(at: idx)
                if let svc = bleInfoServices.removeValue(forKey: peripheralId) {
                    svc.close()
                }
                initializedCBPeripherals.remove(peripheralId)
            }

            isScanning = false
            updateStatus()
            setupNotificationRouting()

            if !devices.isEmpty {
                startBatteryRefresh()
            }

        } catch HIDPPError.exclusiveAccess {
            debugLog("[DeviceManager] BLE IOKit exclusive access for \(info.name) — transport will retry in background")
            logger.warning("[DeviceManager] BLE device \(info.name, privacy: .public): exclusive access denied — retry in progress")
            isScanning = false
            statusMessage = "BLE access restricted — retrying..."
        } catch {
            debugLog("[DeviceManager] BLE IOKit init failed for \(info.name): \(error)")
            logger.warning("[DeviceManager] Failed to initialize BLE device \(info.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            isScanning = false
        }
    }

    // MARK: - CoreBluetooth BLE Discovery

    /// Start the CoreBluetooth scanner for BLE HID++ devices.
    private func startBLEScanner() {
        guard bleScanner == nil else { return }

        let scanner = BLEScanner()
        self.bleScanner = scanner

        scanner.onPeripheralConnected = { [weak self] peripheral, name in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.initializeBLEDeviceViaCB(peripheral: peripheral, name: name)
            }
        }

        scanner.onPeripheralDisconnected = { [weak self] peripheralId, name in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleCBPeripheralDisconnected(peripheralId: peripheralId, name: name)
            }
        }

        scanner.startScanning()
        debugLog("[DeviceManager] CoreBluetooth BLE scanner started")
        logger.info("[DeviceManager] CoreBluetooth BLE scanner started")
    }

    /// Initialize a BLE device discovered via CoreBluetooth — read-only (battery + device info).
    ///
    /// HID++ is NOT accessible via BLE on macOS (kernel locks HOGP). This reads standard
    /// GATT services only: Battery Service (0x180F) and Device Information (0x180A).
    private func initializeBLEDeviceViaCB(peripheral: CBPeripheral, name: String) async {
        let peripheralId = peripheral.identifier

        // Guards
        if initializingCBPeripherals.contains(peripheralId) {
            debugLog("[DeviceManager] CB skip \(name) — already initializing")
            return
        }
        if initializedCBPeripherals.contains(peripheralId) {
            debugLog("[DeviceManager] CB skip \(name) — already initialized")
            return
        }
        if usbDeviceNames.contains(name) {
            debugLog("[DeviceManager] CB skip \(name) — already on USB")
            return
        }
        // Dedup: skip if already initialized via IOKit BLE (full HID++)
        if devices.contains(where: { $0.name == name }) {
            debugLog("[DeviceManager] CB skip \(name) — already initialized via IOKit (full HID++)")
            return
        }

        initializingCBPeripherals.insert(peripheralId)
        defer { initializingCBPeripherals.remove(peripheralId) }

        debugLog("[DeviceManager] CB: reading battery + info for \(name) via GATT...")
        statusMessage = "Reading \(name) via BLE..."

        let infoService = BLEInfoService(peripheral: peripheral, name: name)

        do {
            let info = try await infoService.open()

            // Dedup: skip if same device already found via USB
            if usbDeviceNames.contains(info.name) {
                debugLog("[DeviceManager] CB skip \(info.name) — already on USB (post-read dedup)")
                infoService.close()
                return
            }

            // Also check if already in BLE device list
            if bleDevices.contains(where: { $0.peripheralId == peripheralId }) {
                debugLog("[DeviceManager] CB skip \(info.name) — already in BLE list")
                infoService.close()
                return
            }

            debugLog("[DeviceManager] CB: \(info.name) battery=\(info.batteryLevel.map(String.init) ?? "?")% model=\(info.modelNumber ?? "?")")
            logger.info("[DeviceManager] CB: BLE device \(info.name, privacy: .public) — battery=\(info.batteryLevel.map(String.init) ?? "?", privacy: .public)%")

            // Subscribe to battery updates
            infoService.onUpdate = { [weak self] updatedInfo in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let idx = self.bleDevices.firstIndex(where: { $0.peripheralId == peripheralId }) {
                        self.bleDevices[idx] = updatedInfo
                        debugLog("[DeviceManager] CB: battery update for \(updatedInfo.name): \(updatedInfo.batteryLevel.map(String.init) ?? "?")%")
                    }
                }
            }

            bleDevices.append(info)
            bleInfoServices[peripheralId] = infoService
            initializedCBPeripherals.insert(peripheralId)

            isScanning = false
            updateStatus()

        } catch {
            debugLog("[DeviceManager] CB info read failed for \(name): \(error)")
            logger.warning("[DeviceManager] CB: Failed to read \(name, privacy: .public) via GATT: \(error.localizedDescription, privacy: .public)")
            infoService.close()
        }
    }

    /// Handle CoreBluetooth peripheral disconnection.
    private func handleCBPeripheralDisconnected(peripheralId: UUID, name: String) {
        debugLog("[DeviceManager] CB: peripheral disconnected: \(name) id=\(peripheralId)")
        logger.info("[DeviceManager] CB: BLE device disconnected: \(name, privacy: .public)")

        // Clean up info service
        if let svc = bleInfoServices.removeValue(forKey: peripheralId) {
            svc.close()
        }

        // Remove from BLE device list
        bleDevices.removeAll { $0.peripheralId == peripheralId }
        initializedCBPeripherals.remove(peripheralId)

        updateStatus()
    }

    // MARK: - Device Removal

    private func handleDeviceRemoved(info: IOKitDeviceInfo) {
        debugLog("[DeviceManager] Device removed: \(info.name) uid=\(info.uid) type=\(info.transport.rawValue)")
        logger.info("[DeviceManager] Device removed: \(info.name, privacy: .public) [\(info.transport.rawValue, privacy: .public)]")

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

            // Clear BLE dedup guards so BLE can take over for devices
            // previously skipped because they were on USB.
            initializedBLEUIDs.removeAll()
            initializedCBPeripherals.removeAll()

            // Reset BLE notification state in transport so onBLEDeviceMatched fires again
            // on the next IOKit re-enumeration cycle.
            transport?.resetNotifiedBLEDevices()

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

    // MARK: - BLE Reconnection

    /// Handle BLE device re-acquisition after IOKit re-enumeration.
    /// Re-arms volatile state like thumb button divert that may be lost when the
    /// BLE connection cycles. This is called when the device was already fully
    /// initialized but the IOHIDDevice pointer changed.
    private func handleBLEDeviceReconnected(uid: String) {
        guard let deviceId = uidToDeviceId[uid] else {
            debugLog("[DeviceManager] BLE reconnected for unknown uid=\(uid)")
            return
        }

        guard let mouse = devices.first(where: { $0.id == deviceId }) as? MouseDevice else {
            debugLog("[DeviceManager] BLE reconnected for uid=\(uid) but device is not a mouse")
            return
        }

        debugLog("[DeviceManager] BLE reconnected for \(mouse.name) — re-arming thumb divert")
        logger.info("[DeviceManager] BLE device \(mouse.name, privacy: .public) reconnected — re-arming divert")

        Task {
            await mouse.rearmThumbDivert()
        }
    }

    // MARK: - Dedup

    /// Remove a BLE-discovered device if USB found the same device (by name).
    /// USB is preferred due to lower latency.
    private func removeDuplicateBLEDevice(name: String) {
        // Remove from IOKit BLE devices
        if let bleDevice = devices.first(where: {
            $0.name == name && deviceTransportType[$0.id] == .ble
        }) {
            debugLog("[DeviceManager] Removing BLE (IOKit) duplicate: \(name) (USB preferred)")
            devices.removeAll { $0.id == bleDevice.id }
            deviceTransportType.removeValue(forKey: bleDevice.id)
            if let uid = deviceIdToUID.removeValue(forKey: bleDevice.id) {
                uidToDeviceId.removeValue(forKey: uid)
            }
        }

        // Remove from CoreBluetooth BLE devices
        if let idx = bleDevices.firstIndex(where: { $0.name == name }) {
            let peripheralId = bleDevices[idx].peripheralId
            debugLog("[DeviceManager] Removing BLE (CB) duplicate: \(name) (USB preferred)")
            bleDevices.remove(at: idx)
            if let svc = bleInfoServices.removeValue(forKey: peripheralId) {
                svc.close()
            }
            initializedCBPeripherals.remove(peripheralId)
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
                    // BLE: route by device UID + deviceIndex (0x01)
                    mouseMap["\(uid):\(mouse.deviceIndex)"] = mouse
                    // BLE notifications arrive with deviceIndex=0xFF (broadcast/self-address)
                    mouseMap["\(uid):255"] = mouse
                }
            }
        }

        transport.notificationHandler = { [mouseMap] senderUID, deviceIndex, featureIndex, functionId, params in
            debugLog("[DeviceManager] Notification: sender=\(senderUID) dev=\(deviceIndex) feat=\(String(format: "0x%02X", featureIndex)) func=\(functionId)")
            let key = "\(senderUID):\(deviceIndex)"
            if let mouse = mouseMap[key] {
                // Dispatch to MainActor since MouseDevice is @MainActor isolated
                Task { @MainActor in
                    mouse.handleNotification(featureIndex: featureIndex, functionId: functionId, params: params)
                }
            }
        }

        let totalDevices = self.devices.count
        debugLog("[DeviceManager] Notification routing configured: \(mouseMap.count) mouse(s)")
        logger.info("[DeviceManager] Notification routing configured for \(totalDevices) device(s)")
    }

    // MARK: - Status

    private func updateStatus() {
        let usbCount = deviceTransportType.values.filter { $0 == .usb }.count
        let bleIOKitCount = deviceTransportType.values.filter { $0 == .ble }.count
        let bleCBCount = bleDevices.count
        let totalBLE = bleIOKitCount + bleCBCount
        let total = devices.count + bleCBCount

        if total == 0 {
            statusMessage = "No devices found"
        } else {
            var parts: [String] = []
            if usbCount > 0 { parts.append("\(usbCount) USB") }
            if totalBLE > 0 { parts.append("\(totalBLE) BLE") }
            statusMessage = "Found \(total) device(s) (\(parts.joined(separator: ", ")))"
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
                        BatteryNotifier.checkAndNotify(
                            deviceName: mouse.name,
                            level: mouse.batteryLevel,
                            isCharging: mouse.batteryCharging
                        )
                    } else if let keyboard = device as? KeyboardDevice {
                        await keyboard.refreshBattery()
                        BatteryNotifier.checkAndNotify(
                            deviceName: keyboard.name,
                            level: keyboard.batteryLevel,
                            isCharging: keyboard.batteryCharging
                        )
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

}
