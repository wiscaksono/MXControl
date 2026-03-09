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
    func loadKeyboardFeatures() async {
        do {
            // Battery (0x1004)
            if hasFeature(BatteryFeature.featureId) {
                try await loadBattery()
            }

            // Backlight (0x1983 or 0x1982)
            try await loadBacklight()

            // Fn Inversion (0x40A3 / 0x40A2 / 0x40A0)
            try await loadFnInversion()

            // Host info (0x1814 + 0x1815)
            if hasFeature(ChangeHostFeature.featureId) {
                try await loadHostInfo()
            }

            isFeaturesLoaded = true
            logger.info("[KeyboardDevice] All features loaded for \(self.name)")

        } catch {
            featureLoadError = error.localizedDescription
            logger.error("[KeyboardDevice] Feature load error: \(error.localizedDescription)")
            // Still mark as loaded so UI doesn't hang on spinner
            isFeaturesLoaded = true
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
