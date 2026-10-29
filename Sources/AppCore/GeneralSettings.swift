import Foundation

/// App-wide preferences from the General screen. Device settings live in
/// `SettingsStore`; these are not scoped to a device, so they are plain
/// UserDefaults values.
public enum GeneralSettings {
    public static let batteryThresholdOptions = [10, 20, 30]

    private static let batteryAlertsKey = "general.batteryAlerts"
    private static let batteryThresholdKey = "general.batteryThreshold"

    public static var batteryAlertsEnabled: Bool {
        get {
            // Default on: absent must not read as false.
            guard UserDefaults.standard.object(forKey: batteryAlertsKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: batteryAlertsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: batteryAlertsKey) }
    }

    /// Percent at which the low-battery warning fires.
    public static var batteryThreshold: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: batteryThresholdKey)
            return batteryThresholdOptions.contains(value) ? value : 20
        }
        set { UserDefaults.standard.set(newValue, forKey: batteryThresholdKey) }
    }

    public static var batteryThresholdIndex: Int {
        batteryThresholdOptions.firstIndex(of: batteryThreshold) ?? 1
    }
}
