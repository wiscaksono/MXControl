import Foundation
import os

// MARK: - Diagnostic Counters

/// Shared diagnostic counters written by various components, read by MemoryMonitor.
///
/// These are simple incrementing integers used for correlation analysis.
/// Accessed from multiple threads — uses os_unfair_lock for safety.
enum DiagnosticCounters {
    nonisolated(unsafe) private static var lock = os_unfair_lock_s()
    nonisolated(unsafe) private static var _bleReEnumerationCount: Int = 0
    nonisolated(unsafe) private static var _scrollTimerStartCount: Int = 0

    static func incrementBLEReEnumeration() {
        os_unfair_lock_lock(&lock)
        _bleReEnumerationCount += 1
        os_unfair_lock_unlock(&lock)
    }

    static func incrementScrollTimerStart() {
        os_unfair_lock_lock(&lock)
        _scrollTimerStartCount += 1
        os_unfair_lock_unlock(&lock)
    }

    static var bleReEnumerationCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _bleReEnumerationCount
    }

    static var scrollTimerStartCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _scrollTimerStartCount
    }
}

// MARK: - Memory Monitor

/// Periodic memory footprint reporter for diagnosing memory growth.
///
/// Logs RSS, virtual memory size, and correlated counters (BLE re-enumeration cycles,
/// scroll timer starts) every `interval` seconds via os.Logger. Output is visible in
/// Console.app and `log show --predicate 'subsystem == "com.mxcontrol.app"'` — even
/// in release builds.
///
/// Usage:
///     MemoryMonitor.shared.start()
final class MemoryMonitor: @unchecked Sendable {

    static let shared = MemoryMonitor()

    private let interval: TimeInterval = 300  // 5 minutes
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.mxcontrol.memorymonitor", qos: .utility)

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .seconds(5)
        )
        source.setEventHandler { [weak self] in
            self?.report()
        }
        source.resume()
        timer = source

        // Log initial baseline immediately
        report()
        logger.info("[MemoryMonitor] Started (interval: \(Int(self.interval))s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Report

    private func report() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }

        let rss: Double
        let virt: Double
        if result == KERN_SUCCESS {
            rss = Double(info.resident_size) / 1_048_576.0
            virt = Double(info.virtual_size) / 1_048_576.0
        } else {
            rss = -1
            virt = -1
        }

        let bleCount = DiagnosticCounters.bleReEnumerationCount
        let scrollStarts = DiagnosticCounters.scrollTimerStartCount

        logger.info("[MemoryMonitor] RSS: \(String(format: "%.1f", rss), privacy: .public)MB | Virtual: \(String(format: "%.0f", virt), privacy: .public)MB | BLE re-enum: \(bleCount) | Scroll timer starts: \(scrollStarts)")
    }
}
