import Foundation
import os

/// Persists per-device settings to UserDefaults.
///
/// Keys follow pattern: `mxcontrol.{deviceName}.{setting}`
/// Settings are re-applied when a device reconnects.
enum SettingsStore {

    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    private static let prefix = "mxcontrol"

    // MARK: - Retry Helper

    /// Retry an async operation for transient HID++ errors (timeout, busy, hardware).
    /// Used during settings application on reconnect when the device may still be waking up.
    private static func withRetry(
        _ label: String,
        maxAttempts: Int = 3,
        operation: @Sendable () async throws -> Void
    ) async throws {
        var lastError: (any Error)?
        for attempt in 1...max(1, maxAttempts) {
            do {
                try await operation()
                return
            } catch let error as HIDPPError where error.isTransient {
                lastError = error
                debugLog("[SettingsStore] \(label) transient error (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription)")
                if attempt < maxAttempts {
                    try await Task.sleep(for: .milliseconds(150 * attempt))
                }
            }
        }
        throw lastError ?? HIDPPError.transportError("All retry attempts exhausted for \(label)")
    }

    // MARK: - Key Builder

    private static func key(_ deviceName: String, _ setting: String) -> String {
        "\(prefix).\(deviceName.lowercased().replacingOccurrences(of: " ", with: "_")).\(setting)"
    }

    // MARK: - Clear Settings

    /// Remove all saved settings for a device by clearing keys with the per-device prefix.
    /// Uses prefix-based matching so new settings are automatically included without
    /// maintaining a separate key list.
    private static func clearSettings(for deviceName: String) {
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

    // MARK: - Save From Device

    /// Save current settings from a MouseDevice directly.
    @MainActor static func save(mouse: MouseDevice) {
        let settings = MouseSettings(
            dpi: mouse.currentDPI,
            pointerSpeed: mouse.pointerSpeed,
            smartShiftActive: mouse.smartShiftActive,
            smartShiftTorque: mouse.smartShiftTorque,
            smartShiftWheelMode: mouse.smartShiftWheelMode.rawValue,
            hiResEnabled: mouse.hiResEnabled,
            hiResInverted: mouse.hiResInverted,
            thumbWheelInverted: mouse.thumbWheelInverted,
            buttonRemaps: mouse.buttonRemaps.isEmpty ? nil : mouse.buttonRemaps,
            gestureClickTimeLimit: mouse.gestureClickTimeLimit,
            gestureDragThreshold: mouse.gestureDragThreshold
        )
        saveMouseSettings(settings, deviceName: mouse.name)
    }

    /// Save current settings from a KeyboardDevice directly.
    @MainActor static func save(keyboard: KeyboardDevice) {
        let settings = KeyboardSettings(
            backlightEnabled: keyboard.backlightEnabled,
            backlightLevel: keyboard.backlightLevel,
            fnInverted: keyboard.fnInverted
        )
        saveKeyboardSettings(settings, deviceName: keyboard.name)
    }

    // MARK: - Apply Saved Settings

    /// Apply saved mouse settings to a MouseDevice (on reconnect).
    ///
    /// Each setting is applied independently — a failure on one does not block others.
    @MainActor static func applyMouseSettings(to mouse: MouseDevice) async {
        let saved = loadMouseSettings(deviceName: mouse.name)
        var applied = 0
        var failed = 0

        if let dpi = saved.dpi {
            do { try await withRetry("DPI") { try await mouse.setDPI(dpi) }; applied += 1 }
            catch { failed += 1; logger.warning("[SettingsStore] Failed to restore DPI \(dpi): \(error.localizedDescription)") }
        }
        if let speed = saved.pointerSpeed, mouse.hasFeature(PointerSpeedFeature.featureId) {
            do { try await withRetry("PointerSpeed") { try await mouse.setPointerSpeed(speed) }; applied += 1 }
            catch { failed += 1; logger.warning("[SettingsStore] Failed to restore pointer speed \(speed): \(error.localizedDescription)") }
        }
        if let mode = saved.smartShiftWheelMode, let active = saved.smartShiftActive {
            do {
                try await withRetry("SmartShift") {
                    try await mouse.setSmartShift(
                        wheelMode: SmartShiftFeature.WheelMode(rawValue: mode),
                        autoDisengage: active ? (saved.smartShiftTorque ?? 50) : 0,
                        torque: saved.smartShiftTorque
                    )
                }
                applied += 1
            } catch { failed += 1; logger.warning("[SettingsStore] Failed to restore SmartShift: \(error.localizedDescription)") }
        }
        if let hiRes = saved.hiResEnabled, let inverted = saved.hiResInverted {
            do { try await withRetry("HiResScroll") { try await mouse.setHiResScroll(hiRes: hiRes, inverted: inverted) }; applied += 1 }
            catch { failed += 1; logger.warning("[SettingsStore] Failed to restore HiRes scroll: \(error.localizedDescription)") }
        }
        if let twInverted = saved.thumbWheelInverted, mouse.hasFeature(ThumbWheelFeature.featureId) {
            do { try await withRetry("ThumbWheel") { try await mouse.setThumbWheelInverted(twInverted) }; applied += 1 }
            catch { failed += 1; logger.warning("[SettingsStore] Failed to restore thumb wheel inversion: \(error.localizedDescription)") }
        }
        if let remaps = saved.buttonRemaps {
            let thumbCID = SpecialKeysFeature.KnownCID.gestureButton.rawValue  // 0x00C3
            for (cid, target) in remaps {
                // Skip thumb button — managed by GestureEngine, not remaps
                guard cid != thumbCID else { continue }
                // Skip self-remaps (no-ops that could clear flags)
                guard cid != target else { continue }
                do { try await withRetry("ButtonRemap(\(cid))") { try await mouse.remapButton(controlId: cid, to: target) }; applied += 1 }
                catch { failed += 1; logger.warning("[SettingsStore] Failed to restore button remap CID=\(cid)->CID=\(target): \(error.localizedDescription)") }
            }
        }

        if let ct = saved.gestureClickTimeLimit {
            mouse.gestureClickTimeLimit = ct
        }
        if let dt = saved.gestureDragThreshold {
            mouse.gestureDragThreshold = dt
        }

        if failed == 0 {
            logger.info("[SettingsStore] Applied \(applied) saved mouse settings for \(mouse.name)")
        } else {
            logger.warning("[SettingsStore] Applied \(applied) settings, \(failed) failed for \(mouse.name)")
        }
    }

    /// Apply saved keyboard settings to a KeyboardDevice (on reconnect).
    ///
    /// Each setting is applied independently — a failure on one does not block others.
    @MainActor static func applyKeyboardSettings(to keyboard: KeyboardDevice) async {
        let saved = loadKeyboardSettings(deviceName: keyboard.name)
        var applied = 0
        var failed = 0

        if let enabled = saved.backlightEnabled, let level = saved.backlightLevel {
            do { try await withRetry("Backlight") { try await keyboard.setBacklight(enabled: enabled, level: level) }; applied += 1 }
            catch { failed += 1; logger.warning("[SettingsStore] Failed to restore backlight: \(error.localizedDescription)") }
        }
        if let fnInv = saved.fnInverted {
            do { try await withRetry("FnInversion") { try await keyboard.setFnInversion(fnInv) }; applied += 1 }
            catch { failed += 1; logger.warning("[SettingsStore] Failed to restore Fn inversion: \(error.localizedDescription)") }
        }

        if failed == 0 {
            logger.info("[SettingsStore] Applied \(applied) saved keyboard settings for \(keyboard.name)")
        } else {
            logger.warning("[SettingsStore] Applied \(applied) settings, \(failed) failed for \(keyboard.name)")
        }
    }
}
