import Foundation
import IOKit
import IOKit.hid
import os

// MARK: - Debug File Logger

/// Write debug log directly to file, bypassing macOS privacy filtering.
private let debugLogFile: FileHandle? = {
    let path = "/tmp/mxcontrol_debug.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

func debugLog(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    debugLogFile?.seekToEndOfFile()
    debugLogFile?.write(line.data(using: .utf8) ?? Data())
}

// MARK: - Response Waiter

/// A pending request waiting for a matching HID++ response.
private struct ResponseWaiter: Sendable {
    /// The IOKit device UID this waiter targets (for BLE disambiguation).
    /// For USB receiver, all sub-devices share one UID. For BLE, each device has its own.
    let targetDeviceUID: String?
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionId: UInt8
    let softwareId: UInt8
    let continuation: CheckedContinuation<HIDPPResponse, any Error>
}

// MARK: - IOKit Device Info

/// Metadata about a matched IOKit HID++ device.
struct IOKitDeviceInfo: Sendable {
    let uid: String
    let pid: Int
    let name: String
    let transport: TransportType  // .usb or .ble
    let usagePage: Int
    let usage: Int
}

// MARK: - IOKit Transport

/// HID++ transport over IOKit HIDManager — supports both USB receivers and BLE direct devices.
///
/// Architecture:
///   - **USB Bolt/Unifying receivers** present a HID++ control interface at UsagePage=0xFF00, Usage=0x01.
///     The receiver multiplexes up to 6 sub-devices via deviceIndex 1-6.
///   - **BLE direct devices** appear as IOHIDDevice with UsagePage=0xFF43, Usage=0x0202.
///     Each BLE device is its own IOHIDDevice with deviceIndex=0x01.
///
/// This class uses a SINGLE IOHIDManager with vendor-only matching (Logitech 0x046D)
/// and post-filters for HID++ interfaces. It maintains a map of all matched HID++ devices
/// so it can route sends to the correct IOHIDDevice and dispatch received reports accordingly.
final class USBTransport: HIDTransport, @unchecked Sendable {

    // MARK: - Constants

    static let logitechVendorId: Int = 0x046D

    /// USB receiver HID++ interface
    static let hidppUsagePage: Int = 0xFF00
    static let hidppUsage: Int = 0x0001

    /// BLE direct device HID++ interface
    static let bleHidppUsagePage: Int = 0xFF43
    static let bleHidppUsage: Int = 0x0202

    private let softwareId: UInt8 = 0x01
    private let responseTimeout: TimeInterval = 3.0

    // MARK: - State

    private var manager: IOHIDManager?

    /// All matched HID++ devices, keyed by UID.
    /// For USB receivers: typically one entry (the receiver's HID++ interface).
    /// For BLE: one entry per BLE device.
    private var openDevices: [String: IOHIDDevice] = [:]

    /// Metadata for each open device, keyed by UID.
    private var deviceInfoMap: [String: IOKitDeviceInfo] = [:]

    /// Queue protecting mutable state (waiters, device refs).
    private let stateQueue = DispatchQueue(label: "com.mxcontrol.usbtransport.state")

    /// Pending response waiters. Each waiter also tracks which device UID it targets.
    private var waiters: [ResponseWaiter] = []

    /// Map from IOHIDDevice pointer (as Int) → UID, for routing input reports to the correct device.
    private var devicePtrToUID: [Int: String] = [:]

    // MARK: - Callbacks

    /// Called when a USB Bolt/Unifying receiver is discovered.
    /// The DeviceManager should probe indices 1-6 on this device.
    var onReceiverMatched: (@Sendable (IOKitDeviceInfo) -> Void)?

    /// Called when a BLE direct HID++ device is discovered via IOKit.
    /// The DeviceManager should initialize this as a direct device (deviceIndex=0x01).
    var onBLEDeviceMatched: (@Sendable (IOKitDeviceInfo) -> Void)?

    /// Called when a device is physically removed. Provides the UID and info of the removed device.
    var onDeviceRemoved: (@Sendable (IOKitDeviceInfo) -> Void)?

    /// Callback for unsolicited HID++ notifications (diverted button events, rawXY, battery events, etc.).
    /// Called when an incoming packet does NOT match any pending waiter.
    /// Parameters: (senderUID, deviceIndex, featureIndex, functionId, params)
    var notificationHandler: (@Sendable (String, UInt8, UInt8, UInt8, [UInt8]) -> Void)?

    /// Whether we have any devices open and ready.
    var isOpen: Bool {
        stateQueue.sync { !openDevices.isEmpty }
    }

    /// UIDs of devices that have already fired their matched callback (dedup).
    private var notifiedDeviceUIDs: Set<String> = []

    /// UIDs of BLE devices that failed to open (don't retry on re-enumeration).
    private var failedBLEUIDs: Set<String> = []

    /// Debounce timers for device removal, keyed by UID.
    private var removalDebounceTasks: [String: DispatchWorkItem] = [:]
    private let removalDebounceDelay: TimeInterval = 2.0
    /// Longer debounce for BLE — IOKit re-enumerates BLE devices with gaps of 2-4 seconds.
    private let bleRemovalDebounceDelay: TimeInterval = 8.0

    // MARK: - HIDTransport Protocol

    func open() async throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // Use multiple matching dictionaries:
        // 1. USB receiver HID++ interface: VendorID=0x046D, UsagePage=0xFF00, Usage=0x01
        // 2. BLE direct HID++ interface: VendorID=0x046D (match all Logitech BLE devices)
        //    We post-filter for HID++ usage in DeviceUsagePairs.
        let usbMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.logitechVendorId,
            kIOHIDPrimaryUsagePageKey as String: Self.hidppUsagePage,
            kIOHIDPrimaryUsageKey as String: Self.hidppUsage,
        ]
        let bleMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.logitechVendorId,
            kIOHIDTransportKey as String: "Bluetooth Low Energy",
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [usbMatch, bleMatch] as CFArray)

        // Register device lifecycle callbacks
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let transport = Unmanaged<USBTransport>.fromOpaque(ctx).takeUnretainedValue()
            transport.handleDeviceMatched(device)
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let transport = Unmanaged<USBTransport>.fromOpaque(ctx).takeUnretainedValue()
            transport.handleDeviceRemoved(device)
        }, ctx)

        // Manager-level input report callback — receives reports from ALL matched & opened devices.
        // The `sender` parameter tells us which IOHIDDevice sent the report.
        IOHIDManagerRegisterInputReportCallback(
            manager,
            { ctx, _, sender, _, reportId, reportPtr, reportLength in
                guard let ctx else { return }
                let transport = Unmanaged<USBTransport>.fromOpaque(ctx).takeUnretainedValue()
                // sender is the raw IOHIDDevice pointer — use it directly
                let senderPtr = sender.map { Int(bitPattern: $0) } ?? 0
                transport.handleInputReport(senderPtr: senderPtr, reportId: reportId, report: reportPtr, length: reportLength)
            },
            ctx
        )

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            // kIOReturnExclusiveAccess (0xE00002E2) — common on macOS 15+ for BLE HID devices.
            // The manager callbacks (matching, removal, input reports) still fire even when
            // IOHIDManagerOpen fails with this code, so we can continue.
            if result == IOReturn(bitPattern: 0xE000_02E2) {
                debugLog("[USBTransport] IOHIDManagerOpen returned kIOReturnExclusiveAccess — continuing with callbacks only")
                return
            }

            // Fatal errors — cleanup and throw
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil

            // kIOReturnNotPermitted = 0xE00002C1 — TCC denied (Input Monitoring not granted)
            if result == IOReturn(bitPattern: 0xE000_02C1) {
                throw HIDPPError.tccDenied
            }
            throw HIDPPError.transportError(String(format: "IOHIDManagerOpen failed: 0x%08X", result))
        }
    }

    func close() {
        stateQueue.sync {
            for (_, device) in openDevices {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            openDevices.removeAll()
            deviceInfoMap.removeAll()
            devicePtrToUID.removeAll()
        }

        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            self.manager = nil
        }

        // Cancel all pending waiters
        stateQueue.sync {
            for waiter in waiters {
                waiter.continuation.resume(throwing: HIDPPError.transportNotOpen)
            }
            waiters.removeAll()
        }

        // Cancel all debounce timers
        for (_, task) in removalDebounceTasks {
            task.cancel()
        }
        removalDebounceTasks.removeAll()
        notifiedDeviceUIDs.removeAll()
    }

    /// Reset BLE device notification state so that `onBLEDeviceMatched` fires again
    /// on the next IOKit re-enumeration. Call this when USB is unplugged and BLE
    /// should take over for devices that were previously on USB.
    func resetNotifiedBLEDevices() {
        stateQueue.sync {
            let bleUIDs = notifiedDeviceUIDs.filter { uid in
                deviceInfoMap[uid]?.transport == .ble
            }
            for uid in bleUIDs {
                notifiedDeviceUIDs.remove(uid)
            }
            if !bleUIDs.isEmpty {
                debugLog("[USBTransport] Reset notified BLE UIDs for re-init: \(bleUIDs)")
            }
        }
    }

    /// Send a HID++ request to the specified device (by UID).
    /// If targetDeviceUID is nil, falls back to the first available device (legacy behavior).
    func sendTo(
        targetDeviceUID: String?,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse {
        let device = try stateQueue.sync { () throws -> IOHIDDevice in
            if let uid = targetDeviceUID, let dev = openDevices[uid] {
                return dev
            }
            // Fallback: use first available device
            guard let dev = openDevices.values.first else {
                throw HIDPPError.transportNotOpen
            }
            return dev
        }

        // Check if target is a BLE device — BLE only supports ReportID 0x11 (long, 20 bytes)
        let isBLE = stateQueue.sync { deviceInfoMap[targetDeviceUID ?? ""]?.transport == .ble }

        let bytes: [UInt8]
        let reportId: ReportID

        if isBLE {
            // BLE: always use long report (0x11, 20 bytes) — the HID descriptor only has ReportID 0x11
            reportId = .long
            var longBytes = [UInt8](repeating: 0, count: ReportID.long.reportLength)
            longBytes[0] = ReportID.long.rawValue
            longBytes[1] = deviceIndex
            longBytes[2] = featureIndex
            longBytes[3] = (functionId << 4) | (softwareId & 0x0F)
            for (i, byte) in params.prefix(ReportID.long.maxParams).enumerated() {
                longBytes[4 + i] = byte
            }
            bytes = longBytes
        } else {
            // USB: auto-select report type based on param length
            let request = HIDPPRequest(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionId: functionId,
                softwareId: softwareId,
                params: params
            )
            bytes = request.serialize()
            reportId = request.reportId
        }

        let outHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        debugLog("[USBTransport] OUT (\(outHex)) -> \(targetDeviceUID ?? "any")")

        // Set up response waiter before sending to avoid race
        let response: HIDPPResponse = try await withCheckedThrowingContinuation { continuation in
            let waiter = ResponseWaiter(
                targetDeviceUID: targetDeviceUID,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionId: functionId,
                softwareId: softwareId,
                continuation: continuation
            )

            stateQueue.sync {
                waiters.append(waiter)
            }

            // Send the report
            let data = Data(bytes)
            let result = data.withUnsafeBytes { rawBuf -> IOReturn in
                guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return kIOReturnBadArgument
                }
                return IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(reportId.rawValue),
                    ptr,
                    data.count
                )
            }

            if result != kIOReturnSuccess {
                // Remove waiter and fail — but only if it hasn't been consumed by a response already
                let removed = self.stateQueue.sync { () -> Bool in
                    if let idx = self.waiters.firstIndex(where: {
                        $0.deviceIndex == deviceIndex && $0.featureIndex == featureIndex
                            && $0.functionId == functionId && $0.softwareId == softwareId
                    }) {
                        self.waiters.remove(at: idx)
                        return true
                    }
                    return false
                }

                if removed {
                    debugLog("[USBTransport] SetReport failed: 0x\(String(format: "%08X", result)) for uid=\(targetDeviceUID ?? "any")")
                    let error: HIDPPError
                    if result == IOReturn(bitPattern: 0xE000_02CD) || result == IOReturn(bitPattern: 0xE000_02E2) {
                        error = .exclusiveAccess
                    } else {
                        error = .transportError(String(format: "IOHIDDeviceSetReport failed: 0x%08X", result))
                    }
                    continuation.resume(throwing: error)
                }
                // If not removed, it was already consumed by a response handler — don't double-resume
            }
        }

        return response
    }

    /// HIDTransport protocol conformance — sends to the first available device (for backward compatibility).
    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse {
        try await sendTo(
            targetDeviceUID: nil,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: params
        )
    }

    // MARK: - IOKit Callbacks

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        // Debug: log ALL Logitech devices matched by IOHIDManager (before filtering)
        let rawPid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let rawName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let rawUsagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let rawUsage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let rawTransport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
        let usagePairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        let maxInputSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        let maxOutputSize = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        debugLog("[USBTransport] RAW match: \(rawName) PID=\(String(format: "0x%04X", rawPid)) UsagePage=\(String(format: "0x%04X", rawUsagePage)) Usage=\(String(format: "0x%04X", rawUsage)) Transport=\(rawTransport) MaxIn=\(maxInputSize) MaxOut=\(maxOutputSize)")
        if let pairs = usagePairs as? [[String: Any]] {
            for pair in pairs {
                let up = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
                let u = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
                debugLog("[USBTransport]   UsagePair: UsagePage=\(String(format: "0x%04X", up)) Usage=\(String(format: "0x%04X", u))")
            }
        }

        let interfaceType = classifyInterface(device)
        guard let interfaceType else { return }

        // Skip BLE devices that previously failed to open (TCC denied)
        let rawUID = deviceUID(device)
        if interfaceType == .ble && failedBLEUIDs.contains(rawUID) {
            return
        }

        let pid = rawPid
        let name = rawName
        let uid = deviceUID(device)
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        let info = IOKitDeviceInfo(
            uid: uid,
            pid: pid,
            name: name,
            transport: interfaceType,
            usagePage: usagePage,
            usage: usage
        )

        let (alreadyOpen, wasNotified) = stateQueue.sync {
            (openDevices[uid] != nil, notifiedDeviceUIDs.contains(uid))
        }

        debugLog("[USBTransport] HID++ match: \(name) PID=\(String(format: "0x%04X", pid)) uid=\(uid) type=\(interfaceType.rawValue) alreadyOpen=\(alreadyOpen) wasNotified=\(wasNotified)")

        // Check if this is a re-enumeration (device coming back after removal debounce)
        let isReEnumeration = stateQueue.sync { removalDebounceTasks[uid] != nil }
        if isReEnumeration {
            removalDebounceTasks[uid]?.cancel()
            removalDebounceTasks.removeValue(forKey: uid)
            debugLog("[USBTransport] Re-enumeration detected for uid=\(uid) — re-acquiring silently")

            // Clean up stale pointer mapping from the old IOHIDDevice instance
            stateQueue.sync {
                // Remove old pointer → UID mapping (the old IOHIDDevice pointer is now invalid)
                devicePtrToUID = devicePtrToUID.filter { $0.value != uid }
            }
        }

        // Skip if already open and not re-enumeration
        if alreadyOpen && !isReEnumeration {
            debugLog("[USBTransport] Ignoring duplicate match for uid=\(uid)")
            return
        }

        // Open device for sending — both USB and BLE.
        // BLE HID devices on macOS are virtual devices created by BTLEServer via
        // IOHIDResourceDeviceUserClient. The vendor-specific HID++ collection (0xFF43)
        // is NOT seized by the system event driver, so non-exclusive open should work.
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            if openResult == IOReturn(bitPattern: 0xE000_02E2) {
                // kIOReturnExclusiveAccess — device truly locked by another driver
                debugLog("[USBTransport] IOHIDDeviceOpen exclusive access for uid=\(uid) — marking failed")
                if interfaceType == .ble { failedBLEUIDs.insert(uid) }
            } else if openResult == IOReturn(bitPattern: 0xE000_02CD) {
                // kIOReturnNotOpen — device not ready
                debugLog("[USBTransport] IOHIDDeviceOpen not ready for uid=\(uid)")
            } else {
                debugLog("[USBTransport] IOHIDDeviceOpen failed: 0x\(String(format: "%08X", openResult)) uid=\(uid)")
            }
            return
        }

        // Store the raw CFTypeRef pointer — must match the sender pointer in input report callbacks.
        // IOHIDDevice is a CFTypeRef; unsafeBitCast gives us the same pointer value that IOKit
        // passes as the `sender` parameter in IOHIDManagerRegisterInputReportCallback.
        let devicePtr = unsafeBitCast(device, to: Int.self)

        stateQueue.sync {
            openDevices[uid] = device
            deviceInfoMap[uid] = info
            devicePtrToUID[devicePtr] = uid
        }

        debugLog("[USBTransport] Device opened: \(name) (PID: \(String(format: "0x%04X", pid))) uid=\(uid) type=\(interfaceType.rawValue) ptr=\(String(format: "0x%lX", devicePtr))")
        logger.info("[USBTransport] Device matched: \(name, privacy: .public) (PID: \(String(format: "0x%04X", pid), privacy: .public)) [\(interfaceType.rawValue, privacy: .public)]")

        // Fire callback only once per device UID (unless it was truly removed and came back)
        if !wasNotified {
            stateQueue.sync { _ = notifiedDeviceUIDs.insert(uid) }

            switch interfaceType {
            case .usb:
                onReceiverMatched?(info)
            case .ble:
                onBLEDeviceMatched?(info)
            }
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        let uid = deviceUID(device)
        let devicePtr = unsafeBitCast(device, to: Int.self)

        let (isOurs, info) = stateQueue.sync {
            let isOurs = openDevices[uid] != nil
            let info = deviceInfoMap[uid]
            return (isOurs, info)
        }

        debugLog("[USBTransport] Device removed: uid=\(uid) isOurs=\(isOurs) name=\(info?.name ?? "?")")

        guard isOurs, let info else { return }

        if info.transport == .ble {
            // BLE devices: IOKit re-enumerates them every few seconds.
            // DON'T cancel waiters or clear the device immediately — just remove the stale
            // pointer mapping and let the debounce handle true removal. When the device
            // re-appears (handleDeviceMatched), it will silently swap the IOHIDDevice reference.
            stateQueue.sync {
                if let oldDevice = openDevices.removeValue(forKey: uid) {
                    IOHIDDeviceClose(oldDevice, IOOptionBits(kIOHIDOptionsTypeNone))
                }
                devicePtrToUID.removeValue(forKey: devicePtr)
                // Keep deviceInfoMap and notifiedDeviceUIDs — device will likely reappear
            }

            // Cancel any existing debounce for this UID
            removalDebounceTasks[uid]?.cancel()

            debugLog("[USBTransport] BLE device removed — debouncing \(bleRemovalDebounceDelay)s for uid=\(uid)")
            let debounceItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                debugLog("[USBTransport] BLE debounce expired for uid=\(uid) — device truly removed")

                // Now cancel any pending waiters for this device
                self.stateQueue.sync {
                    let indices = self.waiters.indices.reversed().filter {
                        self.waiters[$0].targetDeviceUID == uid
                    }
                    for idx in indices {
                        let waiter = self.waiters.remove(at: idx)
                        waiter.continuation.resume(throwing: HIDPPError.deviceNotFound)
                    }
                    self.notifiedDeviceUIDs.remove(uid)
                    self.deviceInfoMap.removeValue(forKey: uid)
                }
                self.removalDebounceTasks.removeValue(forKey: uid)
                self.onDeviceRemoved?(info)
            }
            removalDebounceTasks[uid] = debounceItem
            DispatchQueue.main.asyncAfter(deadline: .now() + bleRemovalDebounceDelay, execute: debounceItem)
        } else {
            // USB receiver: clear immediately and cancel all waiters
            stateQueue.sync {
                if let oldDevice = openDevices.removeValue(forKey: uid) {
                    IOHIDDeviceClose(oldDevice, IOOptionBits(kIOHIDOptionsTypeNone))
                }
                devicePtrToUID.removeValue(forKey: devicePtr)
            }

            stateQueue.sync {
                let waiterIndicesToRemove = waiters.indices.reversed().filter {
                    waiters[$0].targetDeviceUID == uid || waiters[$0].targetDeviceUID == nil
                }
                for idx in waiterIndicesToRemove {
                    let waiter = waiters.remove(at: idx)
                    waiter.continuation.resume(throwing: HIDPPError.deviceNotFound)
                }
            }

            // Cancel any existing debounce for this UID
            removalDebounceTasks[uid]?.cancel()

            debugLog("[USBTransport] USB device removed — debouncing \(removalDebounceDelay)s for uid=\(uid)")
            let debounceItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                debugLog("[USBTransport] USB debounce expired for uid=\(uid) — device truly removed")
                self.stateQueue.sync {
                    self.notifiedDeviceUIDs.remove(uid)
                    self.deviceInfoMap.removeValue(forKey: uid)
                }
                self.removalDebounceTasks.removeValue(forKey: uid)
                self.onDeviceRemoved?(info)
            }
            removalDebounceTasks[uid] = debounceItem
            DispatchQueue.main.asyncAfter(deadline: .now() + removalDebounceDelay, execute: debounceItem)
        }
    }

    private func handleInputReport(senderPtr: Int, reportId: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // Determine which device sent this report
        let senderUID = stateQueue.sync { devicePtrToUID[senderPtr] }

        // IOKit input report callback: check if report[0] already contains the report ID.
        var packet: [UInt8]
        if length > 0, let _ = ReportID(rawValue: report[0]) {
            // Report buffer already includes report ID — use as-is
            packet = [UInt8](repeating: 0, count: length)
            for i in 0..<length {
                packet[i] = report[i]
            }
        } else {
            // Report buffer does NOT include report ID — prepend it
            packet = [UInt8](repeating: 0, count: length + 1)
            packet[0] = UInt8(reportId & 0xFF)
            for i in 0..<length {
                packet[i + 1] = report[i]
            }
        }

        // Filter: only process HID++ packets (report IDs 0x10, 0x11, 0x20)
        guard packet.count >= 3, let _ = ReportID(rawValue: packet[0]) else { return }

        let hex = packet.prefix(min(packet.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        debugLog("[USBTransport] IN  (\(hex)) from=\(senderUID ?? "unknown")")

        guard let response = HIDPPResponse.parse(packet) else {
            debugLog("[USBTransport] PARSE FAIL reportId=\(String(format: "0x%02X", reportId))")
            return
        }

        debugLog("[USBTransport] PARSED dev=\(response.deviceIndex) feat=\(String(format: "0x%02X", response.featureIndex)) func=\(response.functionId) sw=\(response.softwareId) isErr=\(response.isError)")

        // Match response to a waiter.
        // For BLE devices, we also match on targetDeviceUID to prevent cross-talk between
        // two BLE devices that both use deviceIndex=0x01.
        stateQueue.sync {
            debugLog("[USBTransport] WAITERS(\(waiters.count)): \(waiters.map { "uid=\($0.targetDeviceUID ?? "any") dev=\($0.deviceIndex) feat=\(String(format: "0x%02X", $0.featureIndex)) func=\($0.functionId) sw=\($0.softwareId)" }.joined(separator: ", "))")

            /// Check if a waiter's targetDeviceUID matches the sender.
            /// - USB waiters (targetDeviceUID is a USB receiver UID) match any report from that receiver.
            /// - BLE waiters match only reports from their specific BLE device.
            /// - If senderUID is unknown (shouldn't happen after pointer fix), fall back to deviceIndex-only matching.
            func waiterMatchesSender(_ waiter: ResponseWaiter) -> Bool {
                guard let senderUID else { return true }  // unknown sender — match any
                guard let targetUID = waiter.targetDeviceUID else { return true }  // legacy — match any
                return targetUID == senderUID
            }

            // Check for error responses (featureIndex 0xFF for HID++ 2.0, 0x8F for HID++ 1.0)
            if response.isAnyError {
                if let errorFeatureIndex = response.errorFeatureIndex,
                   let idx = waiters.firstIndex(where: {
                       $0.deviceIndex == response.deviceIndex && waiterMatchesSender($0)
                   })
                {
                    let waiter = waiters.remove(at: idx)
                    let errorCode = HIDPPErrorCode(rawValue: response.errorCode ?? 0) ?? .unknown
                    debugLog("[USBTransport] ERROR MATCH -> waiter uid=\(waiter.targetDeviceUID ?? "any") dev=\(waiter.deviceIndex) feat=\(String(format: "0x%02X", waiter.featureIndex)) errFeat=\(String(format: "0x%02X", errorFeatureIndex)) errCode=\(errorCode.name)")
                    waiter.continuation.resume(throwing: HIDPPError.hidppError(
                        code: errorCode,
                        featureIndex: errorFeatureIndex
                    ))
                    return
                }
            }

            // Normal response matching — match by deviceIndex + featureIndex + functionId + softwareId + senderUID
            if let idx = waiters.firstIndex(where: {
                $0.deviceIndex == response.deviceIndex
                    && $0.featureIndex == response.featureIndex
                    && $0.functionId == response.functionId
                    && $0.softwareId == response.softwareId
                    && waiterMatchesSender($0)
            }) {
                let waiter = waiters.remove(at: idx)
                debugLog("[USBTransport] MATCH -> waiter uid=\(waiter.targetDeviceUID ?? "any") dev=\(waiter.deviceIndex)")
                waiter.continuation.resume(returning: response)
            } else {
                // Forward unmatched packets to notification handler
                let handler = self.notificationHandler
                if handler != nil {
                    let uid = senderUID ?? "unknown"
                    let devIdx = response.deviceIndex
                    let featIdx = response.featureIndex
                    let funcId = response.functionId
                    let params = response.params
                    DispatchQueue.global().async {
                        handler?(uid, devIdx, featIdx, funcId, params)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Classify a device as USB HID++ or BLE HID++, or nil if neither.
    ///
    /// USB receivers expose a dedicated IOHIDDevice with PrimaryUsagePage=0xFF00, Usage=0x01.
    /// BLE direct devices expose a single IOHIDDevice with PrimaryUsage=mouse/keyboard,
    /// but include UsagePage=0xFF43, Usage=0x0202 in their DeviceUsagePairs.
    private func classifyInterface(_ device: IOHIDDevice) -> TransportType? {
        let primaryUsagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let primaryUsage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        // USB receiver HID++ interface — dedicated device with primary usage 0xFF00/0x01
        if primaryUsagePage == Self.hidppUsagePage && primaryUsage == Self.hidppUsage {
            return .usb
        }

        // BLE direct device — check Transport property AND look for HID++ in DeviceUsagePairs
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        if transport == "Bluetooth Low Energy" {
            if let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] {
                let hasHIDPP = pairs.contains { pair in
                    let up = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
                    let u = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
                    return up == Self.bleHidppUsagePage && u == Self.bleHidppUsage
                }
                if hasHIDPP {
                    return .ble
                }
            }
        }

        return nil
    }

    /// Check if a device is any HID++ interface (USB or BLE). Legacy compatibility.
    private func isHIDPPInterface(_ device: IOHIDDevice) -> Bool {
        classifyInterface(device) != nil
    }

    /// Generate a unique identifier for a device (for dedup).
    private func deviceUID(_ device: IOHIDDevice) -> String {
        // For BLE devices, use PhysicalDeviceUniqueID if available (stable across reconnects)
        if let physUID = IOHIDDeviceGetProperty(device, "PhysicalDeviceUniqueID" as CFString) as? String {
            let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            return "phy-\(physUID)-\(pid)-\(usage)"
        }
        // Fallback: location-based UID (USB devices)
        let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        return "\(pid)-\(locationID)-\(usage)"
    }

    /// Get the product ID from a matched device.
    static func productId(of device: IOHIDDevice) -> Int {
        IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    }

    /// Get the product name from a matched device.
    static func productName(of device: IOHIDDevice) -> String {
        IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
    }

    // MARK: - Device Lookup

    /// Get info for all currently connected devices.
    func connectedDevices() -> [IOKitDeviceInfo] {
        stateQueue.sync { Array(deviceInfoMap.values) }
    }

    /// Get info for a specific device by UID.
    func deviceInfo(uid: String) -> IOKitDeviceInfo? {
        stateQueue.sync { deviceInfoMap[uid] }
    }

    /// Find the UID of a USB receiver device (first matched USB device).
    func receiverUID() -> String? {
        stateQueue.sync {
            deviceInfoMap.first(where: { $0.value.transport == .usb })?.key
        }
    }

    // MARK: - Timeout Support

    /// Send with timeout, targeting a specific device by UID.
    func sendWithTimeout(
        targetDeviceUID: String? = nil,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        params: [UInt8] = [],
        timeout: TimeInterval? = nil
    ) async throws -> HIDPPResponse {
        let effectiveTimeout = timeout ?? responseTimeout

        return try await withThrowingTaskGroup(of: HIDPPResponse.self) { group in
            group.addTask {
                try await self.sendTo(
                    targetDeviceUID: targetDeviceUID,
                    deviceIndex: deviceIndex,
                    featureIndex: featureIndex,
                    functionId: functionId,
                    softwareId: self.softwareId,
                    params: params
                )
            }

            group.addTask {
                try await Task.sleep(for: .seconds(effectiveTimeout))
                throw HIDPPError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
