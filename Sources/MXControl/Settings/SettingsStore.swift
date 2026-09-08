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

    // MARK: - Mouse Settings

    struct MouseSettings: Sendable {
        var dpi: Int?
        var pointerSpeed: Int?
        var smartShiftActive: Bool?
        var smartShiftTorque: Int?
        var smartShiftWheelMode: UInt8?  // raw WheelMode value
        var hiResEnabled: Bool?
        var hiResInverted: Bool?
        var thumbWheelInverted: Bool?
        var buttonRemaps: [UInt16: UInt16]?  // CID -> target CID
        var gestureClickTimeLimit: Double?   // seconds (click-first time window)
        var gestureDragThreshold: Int?       // raw HID units
        var smoothScrollEnabled: Bool?
        var smoothScrollSpeed: Double?       // 1.0 - 10.0
        var smoothScrollMomentum: Double?    // 0.80 - 0.98
        var smoothScrollThumbSpeed: Double?  // 0.5 - 5.0
    }

    /// Save mouse settings to UserDefaults.
    static func saveMouseSettings(_ settings: MouseSettings, deviceName: String) {
        let k = { (s: String) in key(deviceName, s) }

        if let dpi = settings.dpi { defaults.set(dpi, forKey: k("dpi")) }
        if let speed = settings.pointerSpeed { defaults.set(speed, forKey: k("pointer_speed")) }
        if let active = settings.smartShiftActive { defaults.set(active, forKey: k("smartshift.active")) }
        if let torque = settings.smartShiftTorque { defaults.set(torque, forKey: k("smartshift.torque")) }
        if let mode = settings.smartShiftWheelMode { defaults.set(Int(mode), forKey: k("smartshift.wheel_mode")) }
        if let hiRes = settings.hiResEnabled { defaults.set(hiRes, forKey: k("hires.enabled")) }
        if let inverted = settings.hiResInverted { defaults.set(inverted, forKey: k("hires.inverted")) }
        if let twInverted = settings.thumbWheelInverted { defaults.set(twInverted, forKey: k("thumbwheel.inverted")) }

        if let remaps = settings.buttonRemaps {
            let thumbCID = SpecialKeysFeature.KnownCID.gestureButton.rawValue  // 0x00C3
            // Filter out thumb button (managed by GestureEngine) and self-remaps (no-ops)
            let filtered = remaps.filter { $0.key != thumbCID && $0.key != $0.value }
            let dict = Dictionary(uniqueKeysWithValues: filtered.map { (String($0.key), Int($0.value)) })
            defaults.set(dict, forKey: k("button_remaps"))
        }

        if let ct = settings.gestureClickTimeLimit { defaults.set(ct, forKey: k("gesture.click_time")) }
        if let dt = settings.gestureDragThreshold { defaults.set(dt, forKey: k("gesture.drag_threshold")) }

        if let ssEnabled = settings.smoothScrollEnabled { defaults.set(ssEnabled, forKey: k("smooth_scroll.enabled")) }
        if let ssSpeed = settings.smoothScrollSpeed { defaults.set(ssSpeed, forKey: k("smooth_scroll.speed")) }
        if let ssMomentum = settings.smoothScrollMomentum { defaults.set(ssMomentum, forKey: k("smooth_scroll.momentum")) }
        if let ssThumbSpeed = settings.smoothScrollThumbSpeed { defaults.set(ssThumbSpeed, forKey: k("smooth_scroll.thumb_speed")) }

        logger.info("[SettingsStore] Saved settings for \(deviceName)")
    }

    /// Load mouse settings from UserDefaults.
    static func loadMouseSettings(deviceName: String) -> MouseSettings {
        let k = { (s: String) in key(deviceName, s) }

        var settings = MouseSettings()

        if defaults.object(forKey: k("dpi")) != nil {
            settings.dpi = defaults.integer(forKey: k("dpi"))
        }
        if defaults.object(forKey: k("pointer_speed")) != nil {
            settings.pointerSpeed = defaults.integer(forKey: k("pointer_speed"))
        }
        if defaults.object(forKey: k("smartshift.active")) != nil {
            settings.smartShiftActive = defaults.bool(forKey: k("smartshift.active"))
        }
        if defaults.object(forKey: k("smartshift.torque")) != nil {
            settings.smartShiftTorque = defaults.integer(forKey: k("smartshift.torque"))
        }
        if defaults.object(forKey: k("smartshift.wheel_mode")) != nil {
            settings.smartShiftWheelMode = UInt8(defaults.integer(forKey: k("smartshift.wheel_mode")))
        }
        if defaults.object(forKey: k("hires.enabled")) != nil {
            settings.hiResEnabled = defaults.bool(forKey: k("hires.enabled"))
        }
        if defaults.object(forKey: k("hires.inverted")) != nil {
            settings.hiResInverted = defaults.bool(forKey: k("hires.inverted"))
        }
        if defaults.object(forKey: k("thumbwheel.inverted")) != nil {
            settings.thumbWheelInverted = defaults.bool(forKey: k("thumbwheel.inverted"))
        }

        if defaults.object(forKey: k("gesture.click_time")) != nil {
            settings.gestureClickTimeLimit = defaults.double(forKey: k("gesture.click_time"))
        }
        if defaults.object(forKey: k("gesture.drag_threshold")) != nil {
            settings.gestureDragThreshold = defaults.integer(forKey: k("gesture.drag_threshold"))
        }

        if defaults.object(forKey: k("smooth_scroll.enabled")) != nil {
            settings.smoothScrollEnabled = defaults.bool(forKey: k("smooth_scroll.enabled"))
        }
        if defaults.object(forKey: k("smooth_scroll.speed")) != nil {
            settings.smoothScrollSpeed = defaults.double(forKey: k("smooth_scroll.speed"))
        }
        if defaults.object(forKey: k("smooth_scroll.momentum")) != nil {
            settings.smoothScrollMomentum = defaults.double(forKey: k("smooth_scroll.momentum"))
        }
        if defaults.object(forKey: k("smooth_scroll.thumb_speed")) != nil {
            settings.smoothScrollThumbSpeed = defaults.double(forKey: k("smooth_scroll.thumb_speed"))
        }

        if let dict = defaults.dictionary(forKey: k("button_remaps")) as? [String: Int] {
            var remaps: [UInt16: UInt16] = [:]
            for (cidStr, target) in dict {
                if let cid = UInt16(cidStr) {
                    remaps[cid] = UInt16(target)
                }
            }
            settings.buttonRemaps = remaps
        }

        return settings
    }

    // MARK: - Keyboard Settings

    struct KeyboardSettings: Sendable {
        var backlightEnabled: Bool?
        var backlightLevel: Int?
        var fnInverted: Bool?
        var micMuteEnabled: Bool?
    }

    /// Save keyboard settings to UserDefaults.
    static func saveKeyboardSettings(_ settings: KeyboardSettings, deviceName: String) {
        let k = { (s: String) in key(deviceName, s) }

        if let enabled = settings.backlightEnabled { defaults.set(enabled, forKey: k("backlight.enabled")) }
        if let level = settings.backlightLevel { defaults.set(level, forKey: k("backlight.level")) }
        if let fnInv = settings.fnInverted { defaults.set(fnInv, forKey: k("fn.inverted")) }
        if let micMute = settings.micMuteEnabled { defaults.set(micMute, forKey: k("micmute.enabled")) }

        logger.info("[SettingsStore] Saved keyboard settings for \(deviceName)")
    }

    /// Load keyboard settings from UserDefaults.
    static func loadKeyboardSettings(deviceName: String) -> KeyboardSettings {
        let k = { (s: String) in key(deviceName, s) }

        var settings = KeyboardSettings()

        if defaults.object(forKey: k("backlight.enabled")) != nil {
            settings.backlightEnabled = defaults.bool(forKey: k("backlight.enabled"))
        }
        if defaults.object(forKey: k("backlight.level")) != nil {
            settings.backlightLevel = defaults.integer(forKey: k("backlight.level"))
        }
        if defaults.object(forKey: k("fn.inverted")) != nil {
            settings.fnInverted = defaults.bool(forKey: k("fn.inverted"))
        }
        if defaults.object(forKey: k("micmute.enabled")) != nil {
            settings.micMuteEnabled = defaults.bool(forKey: k("micmute.enabled"))
        }

        return settings
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
