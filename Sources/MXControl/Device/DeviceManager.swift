import Foundation
import IOKit.hid
import Observation
import os

/// Manages discovery and lifecycle of Logitech HID++ devices.
///
/// Uses USBTransport to find Bolt/Unifying receivers, then probes
/// device indices 1-6 to discover connected peripherals.
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
                    await self?.probeReceiverDevices()
                }
            } else {
                logger.debug("[DeviceManager] Not a receiver, skipping: PID \(String(format: "0x%04X", pid))")
            }
        }

        usb.onDeviceRemoved = { [weak self] in
            Task { @MainActor [weak self] in
                logger.info("[DeviceManager] Device removed, clearing device list")
                self?.devices.removeAll()
                self?.statusMessage = "Device disconnected"
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
        transport?.close()
        transport = nil
        isScanning = false
        statusMessage = "Stopped"
    }

    // MARK: - Receiver Probe

    /// Probe device indices 1-6 on the receiver to find connected devices.
    private func probeReceiverDevices() async {
        guard let transport else { return }

        statusMessage = "Probing receiver for devices..."
        logger.info("[DeviceManager] Probing receiver indices 1-6...")
        var discovered: [LogiDevice] = []

        // Probe indices 1 through 6
        for index in UInt8(1)...UInt8(6) {
            do {
                let device = LogiDevice(deviceIndex: index, transport: transport)

                // Ping with timeout to check if device exists at this index
                let _ = try await transport.sendWithTimeout(
                    deviceIndex: index,
                    featureIndex: 0x00,
                    functionId: 0x01,
                    params: [0x00, 0x00, 0xAA],
                    timeout: 1.5
                )

                logger.info("[DeviceManager] Device found at index \(index), initializing...")

                // Device responded — initialize it fully
                try await device.initialize()
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

        if discovered.isEmpty {
            logger.warning("[DeviceManager] No devices found on receiver")
        }
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
