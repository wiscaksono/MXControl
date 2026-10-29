import AppCore
import HIDPP
import Foundation
import UserNotifications
import os

/// Sends native macOS notifications when device battery drops below thresholds.
///
/// Two levels:
///   - **Warning** at the General screen threshold (default 20%)
///   - **Critical** at 10%
///
/// Notifications are deduplicated per device per charge cycle.
/// Once a level triggers, it won't fire again until the device starts charging
/// (which resets the notification state).
enum BatteryNotifier {

    // MARK: - Thresholds

    static let criticalThreshold = 10

    // MARK: - Notification State

    /// Tracks which notifications have been sent per device to avoid spam.
    struct NotificationState {
        var warningSent: Bool = false
        var criticalSent: Bool = false
    }

    /// Per-device notification state, keyed by the stable setting scope (or
    /// peripheral UUID for CoreBluetooth-only devices). Reset when charging.
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
    ///   - scope: Stable per-device key (setting scope or peripheral UUID)
    ///   - deviceName: Human-readable device name (e.g., "MX Master 3S")
    ///   - level: Battery percentage (0-100)
    ///   - isCharging: Whether the device is currently charging
    @MainActor
    static func checkAndNotify(scope: String, deviceName: String, level: Int, isCharging: Bool) {
        guard GeneralSettings.batteryAlertsEnabled else { return }

        let warningThreshold = GeneralSettings.batteryThreshold
        let criticalThreshold = min(Self.criticalThreshold, warningThreshold)
        var deviceState = state[scope] ?? NotificationState()

        // Reset notification state when charging starts (allows re-notify on next discharge)
        if isCharging {
            if deviceState.warningSent || deviceState.criticalSent {
                logger.debug("[BatteryNotifier] \(deviceName) charging — reset notification state")
            }
            deviceState.warningSent = false
            deviceState.criticalSent = false
            state[scope] = deviceState
            return
        }

        // Critical: fixed 10% (or the configured threshold if lower)
        if level <= criticalThreshold && !deviceState.criticalSent {
            sendNotification(
                title: "Battery Critical",
                body: "\(deviceName) battery is at \(level)%. Charge soon.",
                identifier: "\(scope)-critical"
            )
            deviceState.criticalSent = true
            deviceState.warningSent = true  // Don't also fire warning
            logger.info("[BatteryNotifier] \(deviceName) critical notification sent (\(level)%)")
        }
        // Warning: configured threshold
        else if level <= warningThreshold && !deviceState.warningSent {
            sendNotification(
                title: "Battery Low",
                body: "\(deviceName) battery is at \(level)%.",
                identifier: "\(scope)-warning"
            )
            deviceState.warningSent = true
            logger.info("[BatteryNotifier] \(deviceName) warning notification sent (\(level)%)")
        }

        state[scope] = deviceState
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
