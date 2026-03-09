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
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionId: UInt8
    let softwareId: UInt8
    let continuation: CheckedContinuation<HIDPPResponse, any Error>
}

// MARK: - USB Transport

/// HID++ transport over USB via IOKit HIDManager.
///
/// Architecture:
///   Bolt/Unifying receivers present multiple HID interfaces on USB:
///     - UsagePage=0x01, Usage=0x02  (Mouse HID)    → managed by macOS, skip
///     - UsagePage=0x01, Usage=0x06  (Keyboard HID) → managed by macOS, skip
///     - UsagePage=0xFF00, Usage=0x01 (HID++ control)→ OUR transport
///
///   We use the IOHIDManager-level input report callback to receive HID++ reports
///   from ANY matched device. For sending, we open and retain the HID++ control
///   interface. If that interface is removed (IOKit lifecycle), we re-acquire
///   from the next matching callback.
final class USBTransport: HIDTransport, @unchecked Sendable {

    // MARK: - Constants

    static let logitechVendorId: Int = 0x046D
    static let hidppUsagePage: Int = 0xFF00
    static let hidppUsage: Int = 0x0001

    private let softwareId: UInt8 = 0x01
    private let responseTimeout: TimeInterval = 3.0

    // MARK: - State

    private var manager: IOHIDManager?
    /// The HID++ control interface used for sending reports.
    private var sendDevice: IOHIDDevice?
    /// Unique ID of the send device (to identify it across callbacks).
    private var sendDeviceUID: String?

    /// Queue protecting mutable state (waiters, device ref).
    private let stateQueue = DispatchQueue(label: "com.mxcontrol.usbtransport.state")

    /// Pending response waiters.
    private var waiters: [ResponseWaiter] = []

    /// Callback for when a Logitech receiver is first discovered.
    /// Only fires ONCE per receiver connection (deduplicated by uid).
    var onDeviceMatched: (@Sendable (IOHIDDevice) -> Void)?

    /// Callback for when the HID++ send device is physically removed.
    var onDeviceRemoved: (@Sendable () -> Void)?

    /// Callback for unsolicited HID++ notifications (diverted button events, rawXY, battery events, etc.).
    /// Called when an incoming packet does NOT match any pending waiter.
    /// Parameters: (deviceIndex, featureIndex, functionId, params)
    var notificationHandler: (@Sendable (UInt8, UInt8, UInt8, [UInt8]) -> Void)?

    /// Whether we have a device open and ready.
    var isOpen: Bool {
        stateQueue.sync { sendDevice != nil }
    }

    /// Track whether onDeviceMatched has already fired (to fire only once).
    private var hasNotifiedDeviceMatched = false

    /// Debounce timer for device removal — IOKit re-enumerates devices periodically,
    /// causing a remove+add cycle for the same device. We delay the removal callback
    /// to avoid tearing down everything on a transient re-enumeration.
    private var removalDebounceTask: DispatchWorkItem?
    private let removalDebounceDelay: TimeInterval = 2.0

    // MARK: - HIDTransport Protocol

    func open() async throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // Match Logitech vendor only
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.logitechVendorId,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

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
        // This is robust against individual device add/remove cycles.
        IOHIDManagerRegisterInputReportCallback(
            manager,
            { ctx, _, sender, _, reportId, reportPtr, reportLength in
                guard let ctx else { return }
                let transport = Unmanaged<USBTransport>.fromOpaque(ctx).takeUnretainedValue()
                transport.handleInputReport(reportId: reportId, report: reportPtr, length: reportLength)
            },
            ctx
        )

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDPPError.transportError("Failed to open IOHIDManager: \(result)")
        }
    }

    func close() {
        stateQueue.sync {
            if let device = sendDevice {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
                sendDevice = nil
                sendDeviceUID = nil
            }
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
    }

    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse {
        let device = try stateQueue.sync { () throws -> IOHIDDevice in
            guard let device = sendDevice else {
                throw HIDPPError.transportNotOpen
            }
            return device
        }

        let request = HIDPPRequest(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: params
        )

        let bytes = request.serialize()
        let reportId = request.reportId

        let outHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        debugLog("[USBTransport] OUT (\(outHex))")

        // Set up response waiter before sending to avoid race
        let response: HIDPPResponse = try await withCheckedThrowingContinuation { continuation in
            let waiter = ResponseWaiter(
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
                // Remove waiter and fail
                self.stateQueue.sync {
                    self.waiters.removeAll { $0.deviceIndex == deviceIndex && $0.featureIndex == featureIndex && $0.functionId == functionId }
                }
                continuation.resume(throwing: HIDPPError.transportError(
                    String(format: "IOHIDDeviceSetReport failed: 0x%08X", result)
                ))
            }
        }

        return response
    }

    // MARK: - IOKit Callbacks

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        // Filter for HID++ control interface
        guard isHIDPPInterface(device) else { return }

        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let uid = deviceUID(device)

        let (haveSendDevice, currentUID) = stateQueue.sync { (sendDevice != nil, sendDeviceUID) }
        debugLog("[USBTransport] HID++ match check: haveSendDevice=\(haveSendDevice) currentUID=\(currentUID ?? "nil") newUID=\(uid)")

        // Case 1: Already have a working send device — skip
        if haveSendDevice {
            debugLog("[USBTransport] Ignoring additional HID++ interface: \(name) uid=\(uid)")
            return
        }

        // Case 2: Re-enumeration — same UID coming back after removal debounce started
        let isReEnumeration = (currentUID == uid)
        if isReEnumeration {
            // Cancel the debounce timer — device came back, not a real removal
            removalDebounceTask?.cancel()
            removalDebounceTask = nil
            debugLog("[USBTransport] Re-enumeration detected for uid=\(uid) — re-acquiring sendDevice silently")
        }

        // Open device for sending
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            debugLog("[USBTransport] Failed to open HID++ device: \(String(format: "0x%08X", result))")
            return
        }

        stateQueue.sync {
            self.sendDevice = device
            self.sendDeviceUID = uid
        }

        debugLog("[USBTransport] Device matched: \(name) (PID: \(String(format: "0x%04X", pid))) uid=\(uid) reEnum=\(isReEnumeration)")
        logger.info("[USBTransport] Device matched: \(name) (PID: \(String(format: "0x%04X", pid)))")

        // Fire onDeviceMatched only ONCE per connection cycle.
        // Re-enumeration (same UID) does NOT fire the callback — devices are still valid.
        if !hasNotifiedDeviceMatched {
            hasNotifiedDeviceMatched = true
            onDeviceMatched?(device)
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        let uid = deviceUID(device)
        let isHIDPP = isHIDPPInterface(device)
        let (isOurSendDevice, currentUID) = stateQueue.sync { (sendDeviceUID == uid && sendDevice != nil, sendDeviceUID ?? "nil") }

        debugLog("[USBTransport] Device removed: uid=\(uid) isHIDPP=\(isHIDPP) isOurs=\(isOurSendDevice) currentUID=\(currentUID)")

        guard isOurSendDevice else { return }

        // Clear the send device immediately so we don't try to use a stale reference
        stateQueue.sync {
            sendDevice = nil
            // Keep sendDeviceUID so handleDeviceMatched can detect re-enumeration
        }

        // Cancel any pending debounce
        removalDebounceTask?.cancel()

        // Cancel all pending waiters — they can't succeed without a send device
        stateQueue.sync {
            for waiter in waiters {
                waiter.continuation.resume(throwing: HIDPPError.deviceNotFound)
            }
            waiters.removeAll()
        }

        // Debounce: IOKit re-enumerates devices periodically (~10-30s), causing
        // remove+add cycles for the same physical device. We delay the "real" removal
        // callback to avoid tearing down the entire device tree on transient events.
        // If handleDeviceMatched fires within the debounce window, it will cancel this
        // and silently re-acquire sendDevice.
        debugLog("[USBTransport] Send device removed — debouncing \(removalDebounceDelay)s before notifying")
        let debounceItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            debugLog("[USBTransport] Debounce expired — device truly removed, notifying")
            self.stateQueue.sync {
                self.sendDeviceUID = nil
            }
            self.hasNotifiedDeviceMatched = false
            self.onDeviceRemoved?()
        }
        removalDebounceTask = debounceItem
        DispatchQueue.main.asyncAfter(deadline: .now() + removalDebounceDelay, execute: debounceItem)
    }

    private func handleInputReport(reportId: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // IOKit input report callback: check if report[0] already contains the report ID.
        // On macOS with HID++ devices, the report buffer typically includes the report ID.
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
        debugLog("[USBTransport] IN  (\(hex))")

        guard let response = HIDPPResponse.parse(packet) else {
            debugLog("[USBTransport] PARSE FAIL reportId=\(String(format: "0x%02X", reportId))")
            return
        }

        debugLog("[USBTransport] PARSED dev=\(response.deviceIndex) feat=\(String(format: "0x%02X", response.featureIndex)) func=\(response.functionId) sw=\(response.softwareId) isErr=\(response.isError)")

        // Match response to a waiter
        stateQueue.sync {
            debugLog("[USBTransport] WAITERS(\(waiters.count)): \(waiters.map { "dev=\($0.deviceIndex) feat=\(String(format: "0x%02X", $0.featureIndex)) func=\($0.functionId) sw=\($0.softwareId)" }.joined(separator: ", "))")

            // Check for error responses (featureIndex 0xFF for HID++ 2.0, 0x8F for HID++ 1.0)
            if response.isAnyError {
                if let errorFeatureIndex = response.errorFeatureIndex,
                   let idx = waiters.firstIndex(where: {
                       $0.deviceIndex == response.deviceIndex
                   })
                {
                    let waiter = waiters.remove(at: idx)
                    let errorCode = HIDPPErrorCode(rawValue: response.errorCode ?? 0) ?? .unknown
                    debugLog("[USBTransport] ERROR MATCH -> waiter dev=\(waiter.deviceIndex) feat=\(String(format: "0x%02X", waiter.featureIndex))")
                    waiter.continuation.resume(throwing: HIDPPError.hidppError(
                        code: errorCode,
                        featureIndex: errorFeatureIndex
                    ))
                    return
                }
            }

            // Normal response matching — match by deviceIndex + featureIndex + functionId + softwareId
            if let idx = waiters.firstIndex(where: {
                $0.deviceIndex == response.deviceIndex
                    && $0.featureIndex == response.featureIndex
                    && $0.functionId == response.functionId
                    && $0.softwareId == response.softwareId
            }) {
                let waiter = waiters.remove(at: idx)
                debugLog("[USBTransport] MATCH -> waiter dev=\(waiter.deviceIndex)")
                waiter.continuation.resume(returning: response)
            } else {
                // Forward unmatched packets to notification handler
                // These include: diverted button events, rawXY, battery status changes, etc.
                let handler = self.notificationHandler
                if handler != nil {
                    let devIdx = response.deviceIndex
                    let featIdx = response.featureIndex
                    let funcId = response.functionId
                    let params = response.params
                    DispatchQueue.global().async {
                        handler?(devIdx, featIdx, funcId, params)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Check if a device is the HID++ control interface (UsagePage 0xFF00, Usage 0x0001).
    private func isHIDPPInterface(_ device: IOHIDDevice) -> Bool {
        guard let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int,
              let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
        else {
            return false
        }
        return usagePage == Self.hidppUsagePage && usage == Self.hidppUsage
    }

    /// Generate a unique identifier for a device (for dedup).
    private func deviceUID(_ device: IOHIDDevice) -> String {
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

    // MARK: - Timeout Support

    /// Send with timeout. Wraps the base send with a Task timeout.
    func sendWithTimeout(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        params: [UInt8] = [],
        timeout: TimeInterval? = nil
    ) async throws -> HIDPPResponse {
        let effectiveTimeout = timeout ?? responseTimeout

        return try await withThrowingTaskGroup(of: HIDPPResponse.self) { group in
            group.addTask {
                try await self.send(
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
