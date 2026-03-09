import CoreBluetooth
import Foundation
import os

/// Manages CoreBluetooth central scanning and connection for Logitech BLE devices.
///
/// Discovers paired Logitech peripherals via their vendor-specific GATT service,
/// connects them, and notifies the DeviceManager. The DeviceManager then creates
/// a `BLEInfoService` to read battery + device information.
final class BLEScanner: NSObject, @unchecked Sendable {

    // MARK: - Logitech BLE Service UUID (for device discovery)

    /// Logitech vendor-specific HID++ GATT service — used to identify Logitech BLE peripherals.
    nonisolated(unsafe) static let logiServiceUUID = CBUUID(string: "00010000-0000-1000-8000-011F2000046D")

    // MARK: - Callbacks

    /// Called when a Logitech peripheral is connected. DeviceManager creates a BLEInfoService.
    var onPeripheralConnected: ((_ peripheral: CBPeripheral, _ name: String) -> Void)?

    /// Called when a peripheral disconnects.
    var onPeripheralDisconnected: ((_ peripheralId: UUID, _ name: String) -> Void)?

    // MARK: - State

    private var centralManager: CBCentralManager?

    /// Peripherals we're currently connecting to (retain to prevent dealloc).
    private var pendingPeripherals: [UUID: CBPeripheral] = [:]

    /// Connected peripherals.
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]

    /// Whether scanning is active.
    private(set) var isScanning = false

    // MARK: - Public API

    /// Start scanning for Logitech BLE devices.
    func startScanning() {
        guard centralManager == nil else {
            debugLog("[BLEScanner] Already initialized, skipping")
            return
        }

        debugLog("[BLEScanner] Initializing CBCentralManager...")
        // Use nil queue (main queue) to ensure delegate callbacks fire on the main thread.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Stop scanning and disconnect all peripherals.
    func stopScanning() {
        debugLog("[BLEScanner] Stopping...")

        if let cm = centralManager, cm.isScanning {
            cm.stopScan()
        }
        isScanning = false

        for (_, peripheral) in connectedPeripherals {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        for (_, peripheral) in pendingPeripherals {
            centralManager?.cancelPeripheralConnection(peripheral)
        }

        connectedPeripherals.removeAll()
        pendingPeripherals.removeAll()
        centralManager = nil
    }

    // MARK: - Helpers

    private func beginScan() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }

        // Check for already-connected peripherals (paired Logitech BLE devices)
        let connected = cm.retrieveConnectedPeripherals(withServices: [BLEScanner.logiServiceUUID])
        if !connected.isEmpty {
            debugLog("[BLEScanner] Found \(connected.count) already-connected peripheral(s)")
            for peripheral in connected {
                let name = peripheral.name ?? "Unknown"
                debugLog("[BLEScanner] Already-connected: \(name) id=\(peripheral.identifier)")
                if connectedPeripherals[peripheral.identifier] == nil && pendingPeripherals[peripheral.identifier] == nil {
                    pendingPeripherals[peripheral.identifier] = peripheral
                    cm.connect(peripheral, options: nil)
                }
            }
        }

        // Scan for new Logitech peripherals
        debugLog("[BLEScanner] Scanning for Logitech BLE devices...")
        cm.scanForPeripherals(
            withServices: [BLEScanner.logiServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        debugLog("[BLEScanner] Bluetooth state: \(central.state.debugDescription)")
        logger.info("[BLEScanner] Bluetooth state: \(central.state.debugDescription, privacy: .public)")

        switch central.state {
        case .poweredOn:
            beginScan()
        case .poweredOff:
            debugLog("[BLEScanner] Bluetooth is off")
        case .unauthorized:
            debugLog("[BLEScanner] Bluetooth unauthorized — check Privacy settings")
            logger.error("[BLEScanner] Bluetooth access unauthorized")
        case .unsupported:
            debugLog("[BLEScanner] Bluetooth not supported on this device")
        default:
            debugLog("[BLEScanner] Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        debugLog("[BLEScanner] Discovered: \(name) id=\(peripheral.identifier) RSSI=\(RSSI)")

        guard connectedPeripherals[peripheral.identifier] == nil,
              pendingPeripherals[peripheral.identifier] == nil else {
            return
        }

        pendingPeripherals[peripheral.identifier] = peripheral
        central.connect(peripheral, options: nil)
        debugLog("[BLEScanner] Connecting to \(name)...")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Unknown"
        debugLog("[BLEScanner] Connected to \(name) id=\(peripheral.identifier)")

        pendingPeripherals.removeValue(forKey: peripheral.identifier)
        connectedPeripherals[peripheral.identifier] = peripheral

        onPeripheralConnected?(peripheral, name)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let name = peripheral.name ?? "Unknown"
        debugLog("[BLEScanner] Failed to connect to \(name): \(error?.localizedDescription ?? "unknown")")
        pendingPeripherals.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let name = peripheral.name ?? "Unknown"
        debugLog("[BLEScanner] Disconnected from \(name): \(error?.localizedDescription ?? "clean")")

        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        pendingPeripherals.removeValue(forKey: peripheral.identifier)
        onPeripheralDisconnected?(peripheral.identifier, name)

        // Request auto-reconnect — CoreBluetooth will reconnect when the peripheral
        // becomes available again (e.g. device wakes from sleep).
        pendingPeripherals[peripheral.identifier] = peripheral
        central.connect(peripheral, options: nil)
        debugLog("[BLEScanner] Requested reconnect for \(name)")
    }
}

// MARK: - CBManagerState Debug

extension CBManagerState {
    var debugDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
