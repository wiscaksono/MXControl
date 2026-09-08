import Foundation
import Observation
import os

/// MX Keys Mini keyboard — @Observable subclass with battery, backlight, Fn inversion, host info.
@Observable
final class KeyboardDevice: LogiDevice, @unchecked Sendable {

    // MARK: - Battery State

    var batteryLevel: Int = 0               // 0-100%
    var batteryCharging: Bool = false
    var batteryStatus: BatteryFeature.ChargingStatus = .discharging

    // MARK: - Backlight State

    var backlightEnabled: Bool = true
    var backlightLevel: Int = 0
    var backlightMode: BacklightFeature.BacklightMode = .automatic
    var backlightMaxLevel: Int = 8          // default, updated from device

    /// Which backlight feature ID is active (0x1983 or 0x1982), nil if none.
    var backlightFeatureId: UInt16?

    /// Raw fields from 0x1982 response — must be preserved for write-back.
    private var backlightOptions: UInt8 = 0
    private var backlightDho: UInt16 = 0
    private var backlightDhi: UInt16 = 0
    private var backlightDpow: UInt16 = 0

    // MARK: - Fn Inversion State

    var fnInverted: Bool = false
    /// Which Fn inversion feature ID is active, nil if none.
    var fnInversionFeatureId: UInt16?
    /// G-key state byte from 0x40A3 enhanced protocol — must be preserved for writes.
    private var fnGKeyState: UInt8 = 0

    // MARK: - Mic Mute State (F9)

    /// Master switch for F9 mic mute. Persisted per-device, default true.
    var micMuteEnabled: Bool = true
    /// Whether the mic-mute CID is currently diverted via HID++ (primary path).
    /// When false, the F9KeyMonitor event tap acts as fallback.
    var micMuteDivertActive: Bool = false
    /// CID of the mic-mute control, once identified via discovery. Nil until then.
    var micMuteCID: UInt16?
    /// Cached SpecialKeys (0x1B04) feature index for notification routing.
    var specialKeysFeatureIndex: UInt8?
    /// Last press state of the diverted mic-mute CID, for press-edge detection.
    private var lastMicMutePressed: Bool = false

    /// Injectable mic-mute action for tests. Defaults to engine + overlay.
    var onMicMuteKeypress: (() -> Void)?

    // MARK: - Host Info

    var currentHostIndex: Int = 0
    var hostCount: Int = 1
    var hosts: [HostsInfoFeature.HostEntry] = []

    // MARK: - Loading State

    var isFeaturesLoaded: Bool = false
    var featureLoadError: String?

    // MARK: - Load All Keyboard Features

    /// Read all keyboard-specific features from the device.
    /// Call after base `initialize()` completes.
    ///
    /// Each feature is loaded independently so a transient failure on one
    /// does not prevent other features from loading.
    func loadKeyboardFeatures() async {
        var errors: [String] = []

        // Battery (0x1004)
        if hasFeature(BatteryFeature.featureId) {
            do { try await loadBattery() }
            catch { errors.append("Battery: \(error.localizedDescription)"); debugLog("[KeyboardDevice] Battery load failed: \(error)") }
        }

        // Backlight (0x1983 or 0x1982)
        do { try await loadBacklight() }
        catch { errors.append("Backlight: \(error.localizedDescription)"); debugLog("[KeyboardDevice] Backlight load failed: \(error)") }

        // Fn Inversion (0x40A3 / 0x40A2 / 0x40A0)
        do { try await loadFnInversion() }
        catch { errors.append("FnInversion: \(error.localizedDescription)"); debugLog("[KeyboardDevice] FnInversion load failed: \(error)") }

        // Host info (0x1814 + 0x1815)
        if hasFeature(ChangeHostFeature.featureId) {
            do { try await loadHostInfo() }
            catch { errors.append("HostInfo: \(error.localizedDescription)"); debugLog("[KeyboardDevice] HostInfo load failed: \(error)") }
        }

        // Mic mute (0x1B04 divert if available, else F9KeyMonitor fallback)
        await loadMicMute()

        isFeaturesLoaded = true
        if errors.isEmpty {
            logger.info("[KeyboardDevice] All features loaded for \(self.name)")
        } else {
            featureLoadError = errors.joined(separator: "; ")
            logger.warning("[KeyboardDevice] Loaded with \(errors.count) error(s) for \(self.name): \(errors.joined(separator: "; "))")
        }
    }

    // MARK: - Battery

    private func loadBattery() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: BatteryFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let status = try await BatteryFeature.getStatus(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        batteryLevel = status.level
        batteryCharging = status.chargingStatus.isCharging
        batteryStatus = status.chargingStatus

        logger.info("[KeyboardDevice] Battery: \(status.level)% \(status.chargingStatus)")
    }

    // MARK: - Backlight

    private func loadBacklight() async throws {
        // Try v3 first, then v2
        for fid in [BacklightFeature.featureIdV3, BacklightFeature.featureIdV2] {
            guard hasFeature(fid) else { continue }

            let idx = try await featureIndexCache.resolve(
                featureId: fid,
                transport: transport,
                deviceIndex: deviceIndex
            )

            let config = try await BacklightFeature.getBacklightConfig(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: idx,
                featureId: fid
            )

            backlightEnabled = config.enabled
            backlightLevel = config.level
            backlightMode = config.mode
            backlightFeatureId = fid

            // Store raw fields for write-back (0x1982)
            backlightOptions = config.options
            backlightDho = config.dho
            backlightDhi = config.dhi
            backlightDpow = config.dpow

            // Try to get level count for v2
            if fid == BacklightFeature.featureIdV2 {
                do {
                    let levelCount = try await BacklightFeature.getBacklightLevelCount(
                        transport: transport,
                        deviceIndex: deviceIndex,
                        featureIndex: idx
                    )
                    if levelCount > 1 {
                        backlightMaxLevel = levelCount - 1
                    }
                } catch {
                    // Not all firmware versions support func 0x02
                    logger.info("[KeyboardDevice] Backlight level count query failed, using default")
                }
            }

            logger.info("[KeyboardDevice] Backlight: enabled=\(config.enabled) mode=\(config.mode.rawValue) level=\(config.level) maxLevel=\(self.backlightMaxLevel) (feature \(String(format: "0x%04X", fid)))")
            return
        }

        logger.info("[KeyboardDevice] No backlight feature found")
    }

    // MARK: - Fn Inversion

    private func loadFnInversion() async throws {
        for fid in FnInversionFeature.allFeatureIds {
            guard hasFeature(fid) else { continue }

            let idx = try await featureIndexCache.resolve(
                featureId: fid,
                transport: transport,
                deviceIndex: deviceIndex
            )

            let state = try await FnInversionFeature.getState(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: idx,
                featureId: fid
            )

            fnInverted = state.fnInverted
            fnGKeyState = state.gKeyState
            fnInversionFeatureId = fid

            logger.info("[KeyboardDevice] Fn Inversion: \(state.fnInverted) gKeyState=\(state.gKeyState) (feature \(String(format: "0x%04X", fid)))")
            return
        }

        logger.info("[KeyboardDevice] No Fn inversion feature found")
    }

    // MARK: - Host Info

    private func loadHostInfo() async throws {
        let idx = try await featureIndexCache.resolve(
            featureId: ChangeHostFeature.featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        let hostInfo = try await ChangeHostFeature.getHostInfo(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx
        )

        hostCount = hostInfo.hostCount
        currentHostIndex = hostInfo.currentHost

        // Get host names if HostsInfo feature is available
        if hasFeature(HostsInfoFeature.featureId) {
            let hostsIdx = try await featureIndexCache.resolve(
                featureId: HostsInfoFeature.featureId,
                transport: transport,
                deviceIndex: deviceIndex
            )

            hosts = try await HostsInfoFeature.enumerateHosts(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: hostsIdx
            )
        }

        logger.info("[KeyboardDevice] Host: \(hostInfo.currentHost + 1)/\(hostInfo.hostCount)")
    }

    // MARK: - Write: Set Backlight

    /// Write backlight settings to device.
    func setBacklight(enabled: Bool, mode: BacklightFeature.BacklightMode, level: Int) async throws {
        guard let fid = backlightFeatureId else {
            debugLog("[KeyboardDevice] setBacklight: NO backlightFeatureId — aborting")
            return
        }
        debugLog("[KeyboardDevice] setBacklight: enabled=\(enabled) mode=\(mode.rawValue) level=\(level) featureId=\(String(format: "0x%04X", fid))")

        let idx = try await featureIndexCache.resolve(
            featureId: fid,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await BacklightFeature.setBacklightConfig(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            featureId: fid,
            enabled: enabled,
            mode: mode,
            level: level,
            currentOptions: backlightOptions,
            dho: backlightDho,
            dhi: backlightDhi,
            dpow: backlightDpow
        )

        backlightEnabled = enabled
        backlightMode = mode
        backlightLevel = level
        // Update stored options with new mode
        backlightOptions = (backlightOptions & 0x07) | (UInt8(mode.rawValue) << 3)

        logger.info("[KeyboardDevice] Backlight set: enabled=\(enabled) mode=\(mode.rawValue) level=\(level)")
    }

    /// Convenience: set backlight enabled + level, preserving current mode.
    /// If disabling, sets mode to .off. If enabling and mode was .off, sets to .manual.
    func setBacklight(enabled: Bool, level: Int) async throws {
        var mode = backlightMode
        if !enabled {
            mode = .off
        } else if mode == .off {
            mode = .manual
        }
        try await setBacklight(enabled: enabled, mode: mode, level: level)
    }

    // MARK: - Write: Set Fn Inversion

    /// Write Fn inversion state to device.
    func setFnInversion(_ inverted: Bool) async throws {
        guard let fid = fnInversionFeatureId else {
            debugLog("[KeyboardDevice] setFnInversion: NO fnInversionFeatureId — aborting")
            return
        }
        debugLog("[KeyboardDevice] setFnInversion: inverted=\(inverted) featureId=\(String(format: "0x%04X", fid)) gKeyState=\(fnGKeyState)")

        let idx = try await featureIndexCache.resolve(
            featureId: fid,
            transport: transport,
            deviceIndex: deviceIndex
        )

        try await FnInversionFeature.setState(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: idx,
            featureId: fid,
            fnInverted: inverted,
            gKeyState: fnGKeyState
        )

        fnInverted = inverted
        logger.info("[KeyboardDevice] Fn inversion set to \(inverted)")
    }

    // MARK: - Mic Mute (F9)

    /// Enumerate remappable controls and divert the mic-mute CID when found.
    ///
    /// v1: enumerates and logs every control (CID/TID/flags with public privacy
    /// so discovery is visible in unified logs), then diverts only a positively
    /// identified mic-mute CID. Until the CID is known, the F9KeyMonitor event
    /// tap acts as fallback — see `DeviceManager.refreshMicMuteState()`.
    func loadMicMute() async {
        micMuteEnabled = SettingsStore.loadKeyboardSettings(deviceName: name).micMuteEnabled ?? true
        guard micMuteEnabled else {
            debugLog("[KeyboardDevice] Mic mute disabled for \(name) — skipping")
            return
        }
        await setupMicMuteDivert()
    }

    /// Enumerate controls and divert the mic-mute CID when identified.
    /// Trusts the live `micMuteEnabled` flag (already resolved by the caller).
    func setupMicMuteDivert() async {
        guard hasFeature(SpecialKeysFeature.featureId) else {
            logger.info("[KeyboardDevice] No 0x1B04 feature — mic mute via F9KeyMonitor fallback")
            return
        }

        do {
            let idx = try await featureIndexCache.resolve(
                featureId: SpecialKeysFeature.featureId,
                transport: transport,
                deviceIndex: deviceIndex
            )
            specialKeysFeatureIndex = idx

            let controls = try await SpecialKeysFeature.enumerateControls(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: idx
            )

            for control in controls {
                debugLog("[KeyboardDevice] Control CID=\(String(format: "0x%04X", control.controlId)) TID=\(String(format: "0x%04X", control.taskId)) flags=0x\(String(format: "%04X", control.flags.rawValue)) pos=\(control.position) group=\(control.group)")
            }
            logger.info("[KeyboardDevice] Enumerated \(controls.count) controls via 0x1B04")

            if let cid = Self.micMuteCID(in: controls) {
                try await divertMicMuteCID(cid, featureIndex: idx)
            } else {
                logger.info("[KeyboardDevice] Mic-mute CID not identified — using F9KeyMonitor fallback")
                NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
            }
        } catch {
            debugLog("[KeyboardDevice] Mic mute setup failed: \(error)")
            logger.warning("[KeyboardDevice] Mic mute setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Identify the mic-mute control among enumerated controls.
    ///
    /// Discovery on MX Keys Mini (firmware v73.x, HID++ 4.5) shows F-row keys
    /// at positions 1-12 mapping to F1-F12 in order. F9 (mic icon) is position 9
    /// = CID 0x011C (divertable FN key). Verified by diverting and observing
    /// divertedButtonsEvent on F9 press.
    ///
    /// The match requires divertable + F-row position 9 + FN key flag so a
    /// firmware remap cannot silently divert the wrong key.
    static func micMuteCID(in controls: [SpecialKeysFeature.ControlInfo]) -> UInt16? {
        let candidate: UInt16 = 0x011C
        guard let match = controls.first(where: { $0.controlId == candidate }),
              match.isDivertable,
              match.position == 9,
              match.flags.contains(.fnKey)
        else {
            return nil
        }
        return match.controlId
    }

    /// Divert the mic-mute CID so presses arrive as HID++ notifications.
    private func divertMicMuteCID(_ cid: UInt16, featureIndex: UInt8) async throws {
        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            controlId: cid,
            divert: true,
            // Volatile divert so the key recovers if MXControl is not running.
            persistDivert: false
        )
        micMuteCID = cid
        micMuteDivertActive = true
        logger.info("[KeyboardDevice] Mic-mute CID 0x\(String(format: "%04X", cid), privacy: .public) diverted")
        NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
    }

    /// Clear an active mic-mute divert (e.g. when the feature is toggled off).
    private func clearMicMuteDivert() async {
        guard micMuteDivertActive, let cid = micMuteCID, let idx = specialKeysFeatureIndex else { return }
        do {
            try await SpecialKeysFeature.setCtrlIdReporting(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: idx,
                controlId: cid,
                divert: false,
                persistDivert: false
            )
        } catch {
            debugLog("[KeyboardDevice] Failed to clear mic-mute divert: \(error)")
        }
        micMuteCID = nil
        micMuteDivertActive = false
    }

    /// Enable or disable F9 mic mute at runtime (from UI toggle).
    /// Trusts the passed value — the ToggleRow binding already flipped the live
    /// flag; this only (un)arms the HID++ divert and notifies routing.
    /// Persistence is handled by the caller via `SettingsStore.save(keyboard:)`.
    func setMicMuteEnabled(_ enabled: Bool) async {
        micMuteEnabled = enabled
        if enabled {
            await setupMicMuteDivert()
        } else {
            await clearMicMuteDivert()
        }
        NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
    }

    /// Re-arm mic-mute divert after a BLE reconnection (volatile state may be lost).
    /// When the CID was never identified (nil), retry full enumeration instead
    /// of giving up — the earlier failure may have been transient.
    func rearmMicMuteDivert() async {
        guard micMuteEnabled else { return }
        if micMuteCID == nil {
            await setupMicMuteDivert()
            return
        }
        guard let cid = micMuteCID, let idx = specialKeysFeatureIndex else { return }
        do {
            try await divertMicMuteCID(cid, featureIndex: idx)
            logger.info("[KeyboardDevice] Mic-mute divert re-armed after BLE reconnection")
        } catch {
            // Divert lost and re-arm failed: mark inactive so the F9 fallback
            // tap takes over instead of leaving F9 dead.
            micMuteDivertActive = false
            NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
            debugLog("[KeyboardDevice] rearmMicMuteDivert FAILED: \(error)")
            logger.warning("[KeyboardDevice] Failed to re-arm mic-mute divert: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handle an unsolicited HID++ notification (diverted mic-mute presses).
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        guard let skIdx = specialKeysFeatureIndex, featureIndex == skIdx else { return }
        guard functionId == 0x00 else { return }  // divertedButtonsEvent only
        guard let cid = micMuteCID else { return }

        let pressed = Set(SpecialKeysFeature.parseDivertedButtonsEvent(params: params))
        let isDown = pressed.contains(cid)
        let wasDown = lastMicMutePressed
        lastMicMutePressed = isDown

        if isDown && !wasDown {
            fireMicMute()
        }
    }

    /// Fire the mic-mute action: engine toggle + persistent muted pill.
    /// The pill shows only while muted; unmute hides it with no overlay.
    func fireMicMute() {
        if let custom = onMicMuteKeypress {
            custom()
            return
        }
        let muted = MicMuteEngine.shared.toggleFromKeypress()
        MicMuteOverlay.shared.reflect(muted: muted)
    }

    // MARK: - Refresh Battery

    /// Refresh battery status only.
    func refreshBattery() async {
        do {
            try await loadBattery()
        } catch {
            logger.warning("[KeyboardDevice] Battery refresh failed: \(error.localizedDescription)")
        }
    }
}
