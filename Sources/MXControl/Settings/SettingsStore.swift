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
    }

    /// Save keyboard settings to UserDefaults.
    static func saveKeyboardSettings(_ settings: KeyboardSettings, deviceName: String) {
        let k = { (s: String) in key(deviceName, s) }

        if let enabled = settings.backlightEnabled { defaults.set(enabled, forKey: k("backlight.enabled")) }
        if let level = settings.backlightLevel { defaults.set(level, forKey: k("backlight.level")) }
        if let fnInv = settings.fnInverted { defaults.set(fnInv, forKey: k("fn.inverted")) }

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

        return settings
    }

    // MARK: - Apply Saved Settings

    /// Apply saved mouse settings to a MouseDevice (on reconnect).
    static func applyMouseSettings(to mouse: MouseDevice) async {
        let saved = loadMouseSettings(deviceName: mouse.name)

        if let dpi = saved.dpi {
            try? await mouse.setDPI(dpi)
        }
        if let speed = saved.pointerSpeed, mouse.hasFeature(PointerSpeedFeature.featureId) {
            try? await mouse.setPointerSpeed(speed)
        }
        if let mode = saved.smartShiftWheelMode, let active = saved.smartShiftActive {
            try? await mouse.setSmartShift(
                wheelMode: SmartShiftFeature.WheelMode(rawValue: mode),
                autoDisengage: active ? (saved.smartShiftTorque ?? 50) : 0,
                torque: saved.smartShiftTorque
            )
        }
        if let hiRes = saved.hiResEnabled, let inverted = saved.hiResInverted {
            try? await mouse.setHiResScroll(hiRes: hiRes, inverted: inverted)
        }
        if let twInverted = saved.thumbWheelInverted, mouse.hasFeature(ThumbWheelFeature.featureId) {
            try? await mouse.setThumbWheelInverted(twInverted)
        }
        if let remaps = saved.buttonRemaps {
            let thumbCID = SpecialKeysFeature.KnownCID.gestureButton.rawValue  // 0x00C3
            for (cid, target) in remaps {
                // Skip thumb button — managed by GestureEngine, not remaps
                guard cid != thumbCID else { continue }
                // Skip self-remaps (no-ops that could clear flags)
                guard cid != target else { continue }
                try? await mouse.remapButton(controlId: cid, to: target)
            }
        }

        if let ct = saved.gestureClickTimeLimit {
            mouse.gestureClickTimeLimit = ct
        }
        if let dt = saved.gestureDragThreshold {
            mouse.gestureDragThreshold = dt
        }

        logger.info("[SettingsStore] Applied saved mouse settings for \(mouse.name)")
    }

    /// Apply saved keyboard settings to a KeyboardDevice (on reconnect).
    static func applyKeyboardSettings(to keyboard: KeyboardDevice) async {
        let saved = loadKeyboardSettings(deviceName: keyboard.name)

        if let enabled = saved.backlightEnabled, let level = saved.backlightLevel {
            try? await keyboard.setBacklight(enabled: enabled, level: level)
        }
        if let fnInv = saved.fnInverted {
            try? await keyboard.setFnInversion(fnInv)
        }

        logger.info("[SettingsStore] Applied saved keyboard settings for \(keyboard.name)")
    }
}
