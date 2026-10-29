import Foundation
import HIDPP
import os

/// Persists per-device settings to UserDefaults.
///
/// Keys follow `mxcontrol.{scope}.{setting}`, where scope is the device
/// descriptor id plus HID++ unit id. Names are not unique and change with
/// the connection, so they are never used as identity.
enum SettingsStore {
    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    private static let prefix = "mxcontrol"

    // MARK: - Key Builder

    private static func key(_ scope: String, _ setting: String) -> String {
        let normalized = scope.lowercased().replacingOccurrences(of: " ", with: "_")
        return "\(prefix).\(normalized).\(setting)"
    }

    // MARK: - Single-Value Save/Load (capability commit path)

    static func saveValue(_ value: Bool, _ setting: String, scope: String) {
        defaults.set(value, forKey: key(scope, setting))
    }

    static func saveValue(_ value: Int, _ setting: String, scope: String) {
        defaults.set(value, forKey: key(scope, setting))
    }

    static func saveValue(_ value: Double, _ setting: String, scope: String) {
        defaults.set(value, forKey: key(scope, setting))
    }

    static func saveValue(_ value: Bool, _ id: CapabilityID, scope: String) {
        saveValue(value, id.rawValue, scope: scope)
    }

    static func saveValue(_ value: Int, _ id: CapabilityID, scope: String) {
        saveValue(value, id.rawValue, scope: scope)
    }

    static func saveValue(_ value: Double, _ id: CapabilityID, scope: String) {
        saveValue(value, id.rawValue, scope: scope)
    }

    /// Load one capability value. Returns nil when never saved.
    /// Type-safe: a value saved as another type does not match.
    static func savedValue<T>(_ setting: String, scope: String) -> T? {
        defaults.object(forKey: key(scope, setting)) as? T
    }

    static func savedValue<T>(_ id: CapabilityID, scope: String) -> T? {
        savedValue(id.rawValue, scope: scope)
    }

    /// Remove every saved setting for a device, including future keys.
    static func clearSettings(for scope: String) {
        let normalized = scope.lowercased().replacingOccurrences(of: " ", with: "_")
        let devicePrefix = "\(prefix).\(normalized)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(devicePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

}
