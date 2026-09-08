import Foundation

// MARK: - Diagnostic Counters

/// Shared diagnostic counters written by various components, read by MemoryMonitor.
///
/// These are simple incrementing integers used for correlation analysis.
/// Accessed from multiple threads — uses os_unfair_lock for safety.
public enum DiagnosticCounters {
    nonisolated(unsafe) private static var lock = os_unfair_lock_s()
    nonisolated(unsafe) private static var _bleReEnumerationCount: Int = 0
    nonisolated(unsafe) private static var _scrollTimerStartCount: Int = 0

    public static func incrementBLEReEnumeration() {
        os_unfair_lock_lock(&lock)
        _bleReEnumerationCount += 1
        os_unfair_lock_unlock(&lock)
    }

    public static func incrementScrollTimerStart() {
        os_unfair_lock_lock(&lock)
        _scrollTimerStartCount += 1
        os_unfair_lock_unlock(&lock)
    }

    public static var bleReEnumerationCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _bleReEnumerationCount
    }

    public static var scrollTimerStartCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _scrollTimerStartCount
    }
}
