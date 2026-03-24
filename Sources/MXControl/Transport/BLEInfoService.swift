import CoreBluetooth
import Foundation
import os

// MARK: - BLE Device Info

/// Information gathered from a BLE peripheral via standard GATT services.
struct BLEDeviceInfo: Sendable {
    var name: String
    var peripheralId: UUID
    var batteryLevel: Int?         // 0-100 from Battery Service
    var manufacturer: String?      // from Device Information Service
    var modelNumber: String?
    var firmwareRevision: String?
    var serialNumber: String?

    /// Guess device type from name
    var deviceType: DeviceType {
        let lower = name.lowercased()
        if lower.contains("mouse") || lower.contains("master") || lower.contains("mx anywhere")
            || lower.contains("ergo") || lower.contains("lift") || lower.contains("pebble") {
            return .mouse
        } else if lower.contains("key") || lower.contains("craft") || lower.contains("pop") {
            return .keyboard
        }
        return .unknown
    }
}

// MARK: - BLE Info Service

/// Reads battery level and device information from standard BLE GATT services.
///
/// This replaces `BLETransport` — the Logitech vendor-specific GATT service (00010000)
/// is NOT an HID++ command channel on macOS 15+. The real HID++ runs through HOGP (0x1812)
/// which is locked by the kernel. This service reads what IS accessible:
///   - Battery Service (0x180F): battery percentage + notify
///   - Device Information Service (0x180A): manufacturer, model, firmware, serial
final class BLEInfoService: NSObject, CBPeripheralDelegate, @unchecked Sendable {

    // MARK: - Standard BLE Service UUIDs

    nonisolated(unsafe) private static let batteryServiceUUID = CBUUID(string: "180F")
    nonisolated(unsafe) private static let batteryLevelCharUUID = CBUUID(string: "2A19")
    nonisolated(unsafe) private static let deviceInfoServiceUUID = CBUUID(string: "180A")

    // Device Information characteristic UUIDs
    nonisolated(unsafe) private static let manufacturerCharUUID = CBUUID(string: "2A29")
    nonisolated(unsafe) private static let modelNumberCharUUID = CBUUID(string: "2A24")
    nonisolated(unsafe) private static let firmwareRevisionCharUUID = CBUUID(string: "2A26")
    nonisolated(unsafe) private static let serialNumberCharUUID = CBUUID(string: "2A25")

    // MARK: - State

    let peripheral: CBPeripheral
    private(set) var info: BLEDeviceInfo

    /// Called when battery level or device info updates.
    var onUpdate: ((_ info: BLEDeviceInfo) -> Void)?

    /// Continuation for the initial read completion.
    private var readyContinuation: CheckedContinuation<BLEDeviceInfo, any Error>?

    /// Track pending reads to know when initial discovery is complete.
    private var pendingReads = 0
    private var initialReadComplete = false

    /// Battery level characteristic (for unsubscribe on close).
    private var batteryLevelChar: CBCharacteristic?

    // MARK: - Init

    init(peripheral: CBPeripheral, name: String) {
        self.peripheral = peripheral
        self.info = BLEDeviceInfo(name: name, peripheralId: peripheral.identifier)
        super.init()
    }

    // MARK: - Public API

    /// Discover services, read device info + battery, subscribe to battery notify.
    /// Returns the gathered device info once the initial read is complete.
    /// Times out after 10 seconds if the peripheral doesn't respond.
    func open() async throws -> BLEDeviceInfo {
        debugLog("[BLEInfo] Opening \(info.name) — discovering Battery + DeviceInfo services...")

        return try await withThrowingTaskGroup(of: BLEDeviceInfo.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.readyContinuation = continuation
                    self.peripheral.delegate = self
                    self.peripheral.discoverServices([
                        BLEInfoService.batteryServiceUUID,
                        BLEInfoService.deviceInfoServiceUUID
                    ])
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw HIDPPError.timeout
            }

            guard let result = try await group.next() else { throw HIDPPError.timeout }
            group.cancelAll()
            return result
        }
    }

    /// Unsubscribe and clean up. Resumes any pending continuation with an error.
    func close() {
        debugLog("[BLEInfo] Closing \(info.name)")

        // Resume pending continuation if still waiting (e.g. peripheral disconnected mid-discovery)
        if let continuation = readyContinuation {
            readyContinuation = nil
            continuation.resume(throwing: HIDPPError.transportError("BLE peripheral disconnected"))
        }

        if let char = batteryLevelChar {
            peripheral.setNotifyValue(false, for: char)
        }
        batteryLevelChar = nil
        peripheral.delegate = nil
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            debugLog("[BLEInfo] Service discovery failed for \(info.name): \(error)")
            readyContinuation?.resume(throwing: HIDPPError.transportError("BLE service discovery failed: \(error.localizedDescription)"))
            readyContinuation = nil
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            debugLog("[BLEInfo] No services found for \(info.name)")
            // Return info as-is (no battery/device info)
            readyContinuation?.resume(returning: info)
            readyContinuation = nil
            return
        }

        debugLog("[BLEInfo] Found \(services.count) service(s) for \(info.name)")
        for service in services {
            debugLog("[BLEInfo]   Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            debugLog("[BLEInfo] Characteristic discovery failed: \(error)")
            return
        }

        guard let chars = service.characteristics else { return }

        for char in chars {
            debugLog("[BLEInfo]   Char: \(char.uuid) in \(service.uuid)")

            if char.properties.contains(.read) {
                pendingReads += 1
                peripheral.readValue(for: char)
            }

            // Subscribe to battery level notifications
            if char.uuid == BLEInfoService.batteryLevelCharUUID && char.properties.contains(.notify) {
                batteryLevelChar = char
                peripheral.setNotifyValue(true, for: char)
                debugLog("[BLEInfo] Subscribed to battery level notify")
            }
        }

        // If no readable characteristics, resolve immediately
        if pendingReads == 0 && !initialReadComplete {
            initialReadComplete = true
            readyContinuation?.resume(returning: info)
            readyContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            debugLog("[BLEInfo] Read error for \(characteristic.uuid): \(error)")
            decrementPendingAndResolve()
            return
        }

        guard let data = characteristic.value else {
            decrementPendingAndResolve()
            return
        }

        // Parse based on characteristic UUID
        switch characteristic.uuid {
        case BLEInfoService.batteryLevelCharUUID:
            if let level = data.first {
                info.batteryLevel = Int(level)
                debugLog("[BLEInfo] Battery: \(level)%")
            }

        case BLEInfoService.manufacturerCharUUID:
            info.manufacturer = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            debugLog("[BLEInfo] Manufacturer: \(info.manufacturer ?? "?")")

        case BLEInfoService.modelNumberCharUUID:
            info.modelNumber = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            debugLog("[BLEInfo] Model: \(info.modelNumber ?? "?")")

        case BLEInfoService.firmwareRevisionCharUUID:
            info.firmwareRevision = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            debugLog("[BLEInfo] Firmware: \(info.firmwareRevision ?? "?")")

        case BLEInfoService.serialNumberCharUUID:
            info.serialNumber = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            debugLog("[BLEInfo] Serial: \(info.serialNumber ?? "?")")

        default:
            break
        }

        decrementPendingAndResolve()

        // Notify listener for updates (battery changes etc.)
        if initialReadComplete {
            onUpdate?(info)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            debugLog("[BLEInfo] Notify subscribe error: \(error)")
        }
    }

    // MARK: - Helpers

    private func decrementPendingAndResolve() {
        if pendingReads > 0 {
            pendingReads -= 1
        }
        if pendingReads == 0 && !initialReadComplete {
            initialReadComplete = true
            debugLog("[BLEInfo] Initial read complete for \(info.name): battery=\(info.batteryLevel.map(String.init) ?? "?")% model=\(info.modelNumber ?? "?")")
            readyContinuation?.resume(returning: info)
            readyContinuation = nil
        }
    }
}
