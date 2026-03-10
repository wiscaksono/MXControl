import Foundation
import UserNotifications
import os

/// Sends native macOS notifications when device battery drops below thresholds.
///
/// Two levels:
///   - **Warning** at 20%: "Battery Low"
///   - **Critical** at 10%: "Battery Critical"
///
/// Notifications are deduplicated per device per charge cycle.
/// Once a level triggers, it won't fire again until the device starts charging
/// (which resets the notification state).
enum BatteryNotifier {

    // MARK: - Thresholds

    static let warningThreshold = 20
    static let criticalThreshold = 10

    // MARK: - Notification State

    /// Tracks which notifications have been sent per device to avoid spam.
    struct NotificationState {
        var warningSent: Bool = false
        var criticalSent: Bool = false
    }

    /// Per-device notification state, keyed by device name.
    /// Reset when charging is detected.
    nonisolated(unsafe) private static var state: [String: NotificationState] = [:]

    // MARK: - Setup

    /// Request notification permission. Call once at app launch.
    static func setup() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.warning("[BatteryNotifier] Permission error: \(error.localizedDescription)")
            } else {
                logger.info("[BatteryNotifier] Notification permission granted: \(granted)")
            }
        }
    }

    // MARK: - Check and Notify

    /// Check battery level and send notifications if thresholds are crossed.
    ///
    /// Call this after every battery refresh poll.
    /// - Parameters:
    ///   - deviceName: Human-readable device name (e.g., "MX Master 3S")
    ///   - level: Battery percentage (0-100)
    ///   - isCharging: Whether the device is currently charging
    @MainActor
    static func checkAndNotify(deviceName: String, level: Int, isCharging: Bool) {
        var deviceState = state[deviceName] ?? NotificationState()

        // Reset notification state when charging starts (allows re-notify on next discharge)
        if isCharging {
            if deviceState.warningSent || deviceState.criticalSent {
                logger.debug("[BatteryNotifier] \(deviceName) charging — reset notification state")
            }
            deviceState.warningSent = false
            deviceState.criticalSent = false
            state[deviceName] = deviceState
            return
        }

        // Critical: 10% or below
        if level <= criticalThreshold && !deviceState.criticalSent {
            sendNotification(
                title: "Battery Critical",
                body: "\(deviceName) battery is at \(level)%. Charge soon.",
                identifier: "\(deviceName)-critical"
            )
            deviceState.criticalSent = true
            deviceState.warningSent = true  // Don't also fire warning
            logger.info("[BatteryNotifier] \(deviceName) critical notification sent (\(level)%)")
        }
        // Warning: 20% or below
        else if level <= warningThreshold && !deviceState.warningSent {
            sendNotification(
                title: "Battery Low",
                body: "\(deviceName) battery is at \(level)%.",
                identifier: "\(deviceName)-warning"
            )
            deviceState.warningSent = true
            logger.info("[BatteryNotifier] \(deviceName) warning notification sent (\(level)%)")
        }

        state[deviceName] = deviceState
    }

    // MARK: - Send

    private static func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("[BatteryNotifier] Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    /// Clear all tracked state (e.g., when all devices disconnect).
    static func reset() {
        state.removeAll()
    }
}
