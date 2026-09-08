import MXControlHIDPP
import Foundation
import os

/// Persists per-device settings to UserDefaults.
///
/// Keys follow pattern: `mxcontrol.{deviceName}.{setting}`
/// Settings are re-applied when a device reconnects.
enum SettingsStore {

    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    private static let prefix = "mxcontrol"

    // MARK: - Key Builder

    private static func key(_ deviceName: String, _ setting: String) -> String {
        "\(prefix).\(deviceName.lowercased().replacingOccurrences(of: " ", with: "_")).\(setting)"
    }

    // MARK: - Single-Value Save/Load (capability commit path)

    /// Persist one capability value. Keys reuse the historical
    /// `mxcontrol.{device}.{suffix}` format.
    static func saveValue(_ value: Bool, _ setting: String, deviceName: String) {
        defaults.set(value, forKey: key(deviceName, setting))
    }

    static func saveValue(_ value: Int, _ setting: String, deviceName: String) {
        defaults.set(value, forKey: key(deviceName, setting))
    }

    static func saveValue(_ value: Double, _ setting: String, deviceName: String) {
        defaults.set(value, forKey: key(deviceName, setting))
    }

    /// Load one capability value. Returns nil when never saved.
    /// Type-safe: a value saved as another type does not match.
    static func savedValue<T>(_ setting: String, deviceName: String) -> T? {
        defaults.object(forKey: key(deviceName, setting)) as? T
    }

    /// Remove all saved settings for a device by clearing keys with the
    /// per-device prefix. New settings are included automatically.
    static func clearSettings(for deviceName: String) {
        let devicePrefix = "\(prefix).\(deviceName.lowercased().replacingOccurrences(of: " ", with: "_"))."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(devicePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Remove all saved mouse settings for a device.
    static func clearMouseSettings(deviceName: String) {
        clearSettings(for: deviceName)
        logger.info("[SettingsStore] Cleared mouse settings for \(deviceName)")
    }

    /// Remove all saved keyboard settings for a device.
    static func clearKeyboardSettings(deviceName: String) {
        clearSettings(for: deviceName)
        logger.info("[SettingsStore] Cleared keyboard settings for \(deviceName)")
    }
}
