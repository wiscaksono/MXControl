import Foundation
import MXControlHIDPP
import os

/// Load/commit logic for every capability id.
///
/// Adding a capability = one arm in `createState`, one in `load`, one in
/// `commit`. Setting keys reuse the historical
/// `mxcontrol.{device}.{suffix}` format so preferences survive upgrades.
/// Two keys were migrated (same device scope, new suffix, old suffix read
/// as fallback): `gesture.click_time` (seconds) → `gesture.click_time_ms`,
/// `fn.inverted` (protocol sense) → `fn.standard_keys` (UI sense).
@MainActor
enum CapabilityHandlers {


    // MARK: - State Creation

    /// Whether a capability applies to this device. Most capabilities map
    /// 1:1 to a feature ID; SmartShift accepts either variant (0x2111/0x2110)
    /// and hosts accepts either info source (0x1815/0x1814).
    static func isSupported(_ capability: DeviceCapability, on device: LogiDevice) -> Bool {
        switch capability.id {
        case .smartShiftWheelMode, .smartShiftActive:
            return device.hasFeature(SmartShiftFeature.featureId)
                || device.hasFeature(SmartShiftV1Feature.featureId)
        case .smartShiftTorque:
            // Torque needs v2 with tunable support; v1-only devices never show it.
            return device.hasFeature(SmartShiftFeature.featureId)
        case .hosts:
            return device.hasFeature(HostsInfoFeature.featureId)
                || device.hasFeature(ChangeHostFeature.featureId)
        default:
            guard let featureId = capability.featureId else { return true }
            return device.hasFeature(featureId)
        }
    }

    /// Create default states for the declared capabilities. States for
    /// features the device does not report are skipped so no UI renders.
    static func createStates(for capabilities: [DeviceCapability], on device: LogiDevice) {
        for capability in capabilities {
            guard isSupported(capability, on: device) else { continue }
            switch capability.kind {
            case .toggle:
                let def: Bool = switch capability.id {
                case .smoothScrollEnabled: true
                case .micMuteEnabled: true
                case .smartShiftActive: true
                case .fnStandardKeys: true
                case .backlightEnabled: true
                default: false
                }
                device.toggles[capability.id] = ToggleState(id: capability.id, label: capability.label, subtitle: capability.subtitle, value: def)

            case .intSlider:
                let (def, range, step, suffix): (Int, ClosedRange<Int>, Int, String) = switch capability.id {
                case .dpi: (1000, 200...8000, 50, " DPI")
                case .smartShiftTorque: (50, 1...100, 1, "")
                case .gestureClickMs: (200, 100...400, 10, "ms")
                case .gestureDragThreshold: (200, 50...500, 10, "")
                case .backlightLevel: (0, 0...8, 1, "")
                default: (0, 0...100, 1, "")
                }
                device.ints[capability.id] = IntSliderState(id: capability.id, label: capability.label, value: def, range: range, step: step, suffix: suffix)

            case .doubleSlider:
                let (def, range, step, format, suffix): (Double, ClosedRange<Double>, Double, String, String) = switch capability.id {
                case .smoothScrollSpeed: (3.0, 1.0...10.0, 0.5, "%.1f", "x")
                case .smoothScrollMomentum: (0.92, 0.80...0.98, 0.01, "%.2f", "")
                case .smoothScrollThumbSpeed: (1.0, 0.5...5.0, 0.5, "%.1f", "x")
                default: (1.0, 0.0...1.0, 0.1, "%.1f", "")
                }
                device.doubles[capability.id] = DoubleSliderState(id: capability.id, label: capability.label, value: def, range: range, step: step, format: format, suffix: suffix)

            case .segmented:
                device.segmented[capability.id] = SegmentedState(
                    id: capability.id,
                    label: capability.label,
                    selected: Int(SmartShiftFeature.WheelMode.ratchet.rawValue),
                    options: [
                        .init(title: "Ratchet", rawValue: Int(SmartShiftFeature.WheelMode.ratchet.rawValue)),
                        .init(title: "Free Spin", rawValue: Int(SmartShiftFeature.WheelMode.freeSpin.rawValue)),
                    ]
                )

            case .info:
                break // Battery/hosts use dedicated BatteryState/HostListState.
            }
        }
    }

    // MARK: - Load

    /// Read one capability from the device, then override with any saved
    /// preference (writing it back so reconnects restore settings).
    /// Each arm is fault-isolated: failure appends to `device.loadErrors`.
    /// Exhaustive over CapabilityID (no default) so new capabilities cannot
    /// silently skip loading.
    static func load(_ id: CapabilityID, on device: LogiDevice) async {
        do {
            switch id {
            case .battery: try await loadBattery(on: device)
            case .dpi: try await loadDPI(on: device)
            case .pointerSpeed: try await loadPointerSpeed(on: device)
            case .smartShiftWheelMode, .smartShiftActive, .smartShiftTorque:
                try await loadSmartShift(on: device)
            case .hiResEnabled, .hiResInverted:
                break // Loaded by ScrollBehavior (needs service sync ordering).
            case .thumbWheelInverted: try await loadThumbWheel(on: device)
            case .backlightEnabled, .backlightLevel:
                try await loadBacklight(on: device)
            case .fnStandardKeys: try await loadFnStandardKeys(on: device)
            case .hosts: try await loadHosts(on: device)
            case .smoothScrollEnabled, .smoothScrollSpeed,
                 .smoothScrollMomentum, .smoothScrollThumbSpeed,
                 .gestureClickMs, .gestureDragThreshold,
                 .micMuteEnabled:
                loadLocal(id, on: device)
            }
        } catch {
            device.loadErrors.append("\(id.rawValue): \(error.localizedDescription)")
            debugLog("[CapabilityHandlers] Load \(id.rawValue) failed: \(error)")
        }
    }

    // MARK: - Local (persisted, no device round-trip)

    private static func loadLocal(_ id: CapabilityID, on device: LogiDevice) {
        let store = SettingsStore.self
        switch id {
        case .smoothScrollEnabled:
            if let v: Bool = store.savedValue(id, deviceName: device.name) { device.toggles[id]?.value = v }
        case .smoothScrollSpeed:
            if let v: Double = store.savedValue(id, deviceName: device.name) { device.doubles[id]?.value = v }
        case .smoothScrollMomentum:
            if let v: Double = store.savedValue(id, deviceName: device.name) { device.doubles[id]?.value = v }
        case .smoothScrollThumbSpeed:
            if let v: Double = store.savedValue(id, deviceName: device.name) { device.doubles[id]?.value = v }
        case .gestureClickMs:
            if let v: Int = store.savedValue(id, deviceName: device.name) {
                device.ints[id]?.value = v
            } else if let legacy: Double = store.savedValue("gesture.click_time", deviceName: device.name) {
                // Clamp: legacy seconds had no upper bound, the slider is 100...400ms.
                device.ints[id]?.value = min(400, max(100, Int((legacy * 1000.0).rounded())))
            }
        case .gestureDragThreshold:
            if let v: Int = store.savedValue(id, deviceName: device.name) { device.ints[id]?.value = v }
        case .micMuteEnabled:
            if let v: Bool = store.savedValue(id, deviceName: device.name) { device.toggles[id]?.value = v }
        case .battery, .dpi, .pointerSpeed,
             .smartShiftWheelMode, .smartShiftActive, .smartShiftTorque,
             .hiResEnabled, .hiResInverted, .thumbWheelInverted,
             .backlightEnabled, .backlightLevel, .fnStandardKeys, .hosts:
            break // Device-backed or behavior-loaded; never local-only.
        }
    }

    // MARK: - Device-backed Loads

    private static func batteryIndex(on device: LogiDevice) async throws -> UInt8 {
        try await device.featureIndexCache.resolve(
            featureId: BatteryFeature.featureId,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )
    }

    private static func loadBattery(on device: LogiDevice) async throws {
        let idx = try await batteryIndex(on: device)
        let status = try await BatteryFeature.getStatus(
            transport: device.transport,
            deviceIndex: device.deviceIndex,
            featureIndex: idx
        )
        device.batteryFeatureIndex = idx
        device.battery.level = status.level
        device.battery.charging = status.chargingStatus.isCharging
        device.battery.statusText = status.chargingStatus.description
        logger.info("[CapabilityHandlers] Battery: \(status.level)% \(status.chargingStatus)")
    }

    private static func loadDPI(on device: LogiDevice) async throws {
        let idx = try await device.featureIndexCache.resolve(
            featureId: AdjustableDPIFeature.featureId,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )
        switch try await AdjustableDPIFeature.getSensorDPIList(
            transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
        ) {
        case .range(let min, let max, let step):
            device.dpiMin = min; device.dpiMax = max; device.dpiStep = step
        case .list(let values):
            if let first = values.first, let last = values.last {
                device.dpiMin = first; device.dpiMax = last
                device.dpiStep = values.count > 1 ? (values[1] - values[0]) : 50
            }
        }
        let info = try await AdjustableDPIFeature.getSensorDPI(
            transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
        )
        let state = device.ints[CapabilityID.dpi]
        state?.range = device.dpiMin...device.dpiMax
        state?.step = device.dpiStep
        if let saved: Int = SettingsStore.savedValue(CapabilityID.dpi, deviceName: device.name) {
            // writeDPI snaps to step and stores the snapped value in state.
            try await writeDPI(saved, on: device, index: idx)
        } else {
            state?.value = info.currentDPI
        }
        logger.info("[CapabilityHandlers] DPI: \(state?.value ?? info.currentDPI) (range \(device.dpiMin)-\(device.dpiMax))")
    }

    private static func loadPointerSpeed(on device: LogiDevice) async throws {
        let idx = try await device.featureIndexCache.resolve(
            featureId: PointerSpeedFeature.featureId,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )
        var speed = try await PointerSpeedFeature.getSpeed(
            transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
        )
        if let saved: Int = SettingsStore.savedValue(CapabilityID.pointerSpeed, deviceName: device.name) {
            speed = saved
            try await PointerSpeedFeature.setSpeed(
                transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx, speed: speed
            )
        }
        device.pointerSpeed = speed
        logger.info("[CapabilityHandlers] Pointer speed: \(speed)")
    }

    /// Whether an auto-disengage value means SmartShift is effectively on.
    /// 0 disables, 0xFF locks permanent ratchet (also off in effect).
    private static func isSmartShiftActive(_ autoDisengage: Int) -> Bool {
        autoDisengage != 0 && autoDisengage != 0xFF
    }

    /// Resolve the SmartShift variant the device reports, preferring v2.
    /// Stores the active feature ID for commit routing.
    private static func smartShiftFeatureId(on device: LogiDevice) async throws -> UInt16 {
        if device.hasFeature(SmartShiftFeature.featureId) {
            device.smartShiftFid = SmartShiftFeature.featureId
            return SmartShiftFeature.featureId
        }
        if device.hasFeature(SmartShiftV1Feature.featureId) {
            device.smartShiftFid = SmartShiftV1Feature.featureId
            return SmartShiftV1Feature.featureId
        }
        throw HIDPPError.featureNotSupported(SmartShiftFeature.featureId)
    }

    /// Resolve the cached SmartShift index, re-resolving the variant when a
    /// previous load never completed (fid nil).
    private static func resolveSmartShiftIndex(on device: LogiDevice) async throws -> UInt8 {
        let fid: UInt16
        if let cached = device.smartShiftFid {
            fid = cached
        } else {
            fid = try await smartShiftFeatureId(on: device)
        }
        return try await device.featureIndexCache.resolve(
            featureId: fid,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )
    }

    private static func loadSmartShift(on device: LogiDevice) async throws {
        let fid = try await smartShiftFeatureId(on: device)
        let idx = try await device.featureIndexCache.resolve(
            featureId: fid,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )

        var mode: SmartShiftFeature.WheelMode = .ratchet
        var active = true
        var torque = 50

        if fid == SmartShiftFeature.featureId {
            let caps = try await SmartShiftFeature.getCapabilities(
                transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
            )
            device.smartShiftMaxForce = caps.maxForce
            if caps.hasTunableTorque, caps.maxForce > 0 {
                device.ints[CapabilityID.smartShiftTorque]?.range = 1...caps.maxForce
            } else {
                // No tunable torque: drop the slider state so no UI renders.
                device.ints.removeValue(forKey: CapabilityID.smartShiftTorque)
            }

            let status = try await SmartShiftFeature.getStatus(
                transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
            )
            mode = status.wheelMode
            active = isSmartShiftActive(status.autoDisengage)
            // Zero means unknown (truncated response), never a real torque.
            if status.torque > 0 { torque = status.torque }
        } else {
            // v1 has no tunable torque: drop the slider state so no UI renders.
            device.ints.removeValue(forKey: CapabilityID.smartShiftTorque)
            let status = try await SmartShiftV1Feature.getStatus(
                transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
            )
            mode = status.wheelMode
            active = isSmartShiftActive(status.autoDisengage)
        }

        let savedMode: Int? = SettingsStore.savedValue(CapabilityID.smartShiftWheelMode, deviceName: device.name)
        let savedActive: Bool? = SettingsStore.savedValue(CapabilityID.smartShiftActive, deviceName: device.name)
        let savedTorque: Int? = SettingsStore.savedValue(CapabilityID.smartShiftTorque, deviceName: device.name)
        // v1 has no torque setting: a stale torque pref must not trigger a write.
        // Same for v2 without tunable torque (slider state was dropped above).
        let needsWrite = savedMode != nil || savedActive != nil
            || (fid == SmartShiftFeature.featureId && device.ints[CapabilityID.smartShiftTorque] != nil && savedTorque != nil)
        if needsWrite {
            if let m = savedMode, let wm = SmartShiftFeature.WheelMode(rawValue: UInt8(m)) { mode = wm }
            if let a = savedActive { active = a }
            if fid == SmartShiftFeature.featureId, let t = savedTorque { torque = t }
            if fid == SmartShiftFeature.featureId {
                let echoed = try await SmartShiftFeature.setStatus(
                    transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx,
                    wheelMode: mode,
                    autoDisengage: active ? (savedTorque ?? 50) : 0,
                    torque: savedTorque
                )
                mode = echoed.wheelMode
                active = isSmartShiftActive(echoed.autoDisengage)
                if echoed.torque > 0 { torque = echoed.torque }
            } else {
                let echoed = try await SmartShiftV1Feature.setStatus(
                    transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx,
                    wheelMode: mode,
                    autoDisengage: active ? 50 : 0,
                    autoDisengageDefault: nil
                )
                mode = echoed.wheelMode
                active = isSmartShiftActive(echoed.autoDisengage)
            }
        }

        device.segmented[CapabilityID.smartShiftWheelMode]?.selected = Int(mode.rawValue)
        device.toggles[CapabilityID.smartShiftActive]?.value = active
        device.ints[CapabilityID.smartShiftTorque]?.value = torque
        ScrollInterceptor.shared.wheelMode = mode == .freeSpin ? .freeSpin : .ratchet
        if fid == SmartShiftFeature.featureId {
            logger.info("[CapabilityHandlers] SmartShift: mode=\(mode) active=\(active) torque=\(torque) (0x2111)")
        } else {
            logger.info("[CapabilityHandlers] SmartShift: mode=\(mode) active=\(active) (0x2110)")
        }
    }

    private static func loadThumbWheel(on device: LogiDevice) async throws {
        let idx = try await device.featureIndexCache.resolve(
            featureId: ThumbWheelFeature.featureId,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )
        let info = try await ThumbWheelFeature.getInfo(
            transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
        )
        debugLog("[CapabilityHandlers] Thumbwheel info: native=\(info.nativeResolution) diverted=\(info.divertedResolution)")
        let config = try await ThumbWheelFeature.getConfig(
            transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
        )
        // Preserve the device's reporting mode: we only manage inversion,
        // never divert the thumbwheel (no listener consumes diverted events).
        device.thumbDiverted = config.diverted
        var inverted = config.inverted
        if let saved: Bool = SettingsStore.savedValue(CapabilityID.thumbWheelInverted, deviceName: device.name) {
            inverted = saved
            try await ThumbWheelFeature.setConfig(
                transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx,
                inverted: inverted, diverted: config.diverted
            )
        }
        device.toggles[CapabilityID.thumbWheelInverted]?.value = inverted
        logger.info("[CapabilityHandlers] Thumb wheel inverted=\(inverted) diverted=\(config.diverted)")
    }

    private static func loadBacklight(on device: LogiDevice) async throws {
        for fid in [BacklightFeature.featureIdV3, BacklightFeature.featureIdV2] {
            guard device.hasFeature(fid) else { continue }
            let idx = try await device.featureIndexCache.resolve(
                featureId: fid, transport: device.transport, deviceIndex: device.deviceIndex
            )
            let config = try await BacklightFeature.getBacklightConfig(
                transport: device.transport, deviceIndex: device.deviceIndex,
                featureIndex: idx, featureId: fid
            )
            device.backlightFid = fid
            device.backlightFeatureIndex = idx
            device.backlightOptions = config.options
            device.backlightDho = config.dho
            device.backlightDhi = config.dhi
            device.backlightDpow = config.dpow
            device.backlightMode = config.mode
            var maxLevel = 8
            if fid == BacklightFeature.featureIdV2,
               let count = try? await BacklightFeature.getBacklightLevelCount(
                   transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
               ), count > 1 {
                maxLevel = count - 1
            }
            device.backlightMaxLevel = maxLevel
            device.ints[CapabilityID.backlightLevel]?.range = 0...maxLevel

            var enabled = config.enabled
            var level = config.level
            let savedEnabled: Bool? = SettingsStore.savedValue(CapabilityID.backlightEnabled, deviceName: device.name)
            let savedLevel: Int? = SettingsStore.savedValue(CapabilityID.backlightLevel, deviceName: device.name)
            if savedEnabled != nil || savedLevel != nil {
                enabled = savedEnabled ?? enabled
                level = savedLevel ?? level
                try await writeBacklight(enabled: enabled, level: level, on: device, index: idx)
            }
            device.toggles[CapabilityID.backlightEnabled]?.value = enabled
            device.ints[CapabilityID.backlightLevel]?.value = level
            logger.info("[CapabilityHandlers] Backlight: enabled=\(enabled) level=\(level)")
            return
        }
        // No backlight feature: drop the rows so no UI section renders.
        device.toggles.removeValue(forKey: CapabilityID.backlightEnabled)
        device.ints.removeValue(forKey: CapabilityID.backlightLevel)
        logger.info("[CapabilityHandlers] No backlight feature found")
    }

    private static func loadFnStandardKeys(on device: LogiDevice) async throws {
        for fid in FnInversionFeature.allFeatureIds {
            guard device.hasFeature(fid) else { continue }
            let idx = try await device.featureIndexCache.resolve(
                featureId: fid, transport: device.transport, deviceIndex: device.deviceIndex
            )
            let state = try await FnInversionFeature.getState(
                transport: device.transport, deviceIndex: device.deviceIndex,
                featureIndex: idx, featureId: fid
            )
            device.fnFid = fid
            device.fnDefaultState = state.defaultState

            // UI sense: standard F-keys primary. Protocol sense is inverted.
            var wantStandard = !state.fnInverted
            if let saved: Bool = SettingsStore.savedValue(CapabilityID.fnStandardKeys, deviceName: device.name) {
                wantStandard = saved
            } else if let legacy: Bool = SettingsStore.savedValue("fn.inverted", deviceName: device.name) {
                wantStandard = !legacy
            }
            if wantStandard != !state.fnInverted {
                try await FnInversionFeature.setState(
                    transport: device.transport, deviceIndex: device.deviceIndex,
                    featureIndex: idx, featureId: fid,
                    fnInverted: !wantStandard, defaultState: state.defaultState
                )
            }
            device.toggles[CapabilityID.fnStandardKeys]?.value = wantStandard
            logger.info("[CapabilityHandlers] Fn standard keys: \(wantStandard)")
            return
        }
        device.toggles.removeValue(forKey: CapabilityID.fnStandardKeys)
        logger.info("[CapabilityHandlers] No Fn inversion feature found")
    }

    private static func loadHosts(on device: LogiDevice) async throws {
        // Prefer 0x1815 (slot status + bus per slot); fall back to 0x1814
        // (count + current only) when 0x1815 is missing OR its enumeration
        // fails — either way the section must not take down the load.
        if device.hasFeature(HostsInfoFeature.featureId) {
            do {
                let hostsIdx = try await device.featureIndexCache.resolve(
                    featureId: HostsInfoFeature.featureId,
                    transport: device.transport,
                    deviceIndex: device.deviceIndex
                )
                let (hosts, current) = try await HostsInfoFeature.enumerateHosts(
                    transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: hostsIdx
                )
                device.hosts.hosts = hosts
                device.hosts.currentHostIndex = current
                device.hosts.hostCount = hosts.count
                logger.info("[CapabilityHandlers] Hosts: \(hosts.count) slot(s), current \(current + 1)")
                return
            } catch {
                debugLog("[CapabilityHandlers] 0x1815 enumerate failed (\(error)), trying 0x1814 count")
            }
        }

        guard device.hasFeature(ChangeHostFeature.featureId) else { return }
        let idx = try await device.featureIndexCache.resolve(
            featureId: ChangeHostFeature.featureId,
            transport: device.transport,
            deviceIndex: device.deviceIndex
        )
        let hostInfo = try await ChangeHostFeature.getHostInfo(
            transport: device.transport, deviceIndex: device.deviceIndex, featureIndex: idx
        )
        device.hosts.hostCount = hostInfo.hostCount
        device.hosts.currentHostIndex = hostInfo.currentHost
        // Count-only fallback: the active slot is connected by definition.
        device.hosts.hosts = (0..<hostInfo.hostCount).map {
            HostsInfoFeature.HostEntry(index: $0, name: "Slot \($0 + 1)", busType: .undefined, isPaired: $0 == hostInfo.currentHost)
        }
        logger.info("[CapabilityHandlers] Host: \(hostInfo.currentHost + 1)/\(hostInfo.hostCount) (count only)")
    }

    // MARK: - Commit (UI → device + persist)

    /// Write the current state value to the device and persist it.
    static func commit(_ id: CapabilityID, on device: LogiDevice) async {
        do {
            switch id {
            case .dpi:
                let state = device.ints[id]
                let idx = try await device.featureIndexCache.resolve(
                    featureId: AdjustableDPIFeature.featureId,
                    transport: device.transport, deviceIndex: device.deviceIndex
                )
                try await writeDPI(state?.value ?? 1000, on: device, index: idx)
                if let v = state?.value { SettingsStore.saveValue(v, id, deviceName: device.name) }

            case .pointerSpeed:
                let idx = try await device.featureIndexCache.resolve(
                    featureId: PointerSpeedFeature.featureId,
                    transport: device.transport, deviceIndex: device.deviceIndex
                )
                try await PointerSpeedFeature.setSpeed(
                    transport: device.transport, deviceIndex: device.deviceIndex,
                    featureIndex: idx, speed: device.pointerSpeed
                )
                SettingsStore.saveValue(device.pointerSpeed, id, deviceName: device.name)
                logger.info("[CapabilityHandlers] Pointer speed set to \(device.pointerSpeed)")

            case .smartShiftWheelMode:
                guard let mode = SmartShiftFeature.WheelMode(rawValue: UInt8(device.segmented[id]?.selected ?? 2)) else { return }
                let idx = try await resolveSmartShiftIndex(on: device)
                let echoedAD: Int
                let echoedMode: SmartShiftFeature.WheelMode
                if device.smartShiftFid == SmartShiftV1Feature.featureId {
                    let status = try await SmartShiftV1Feature.setStatus(
                        transport: device.transport, deviceIndex: device.deviceIndex,
                        featureIndex: idx, wheelMode: mode, autoDisengage: nil, autoDisengageDefault: nil
                    )
                    echoedMode = status.wheelMode
                    echoedAD = status.autoDisengage
                } else {
                    let status = try await SmartShiftFeature.setStatus(
                        transport: device.transport, deviceIndex: device.deviceIndex,
                        featureIndex: idx, wheelMode: mode, autoDisengage: nil, torque: nil
                    )
                    echoedMode = status.wheelMode
                    echoedAD = status.autoDisengage
                }
                device.segmented[id]?.selected = Int(echoedMode.rawValue)
                device.toggles[CapabilityID.smartShiftActive]?.value = isSmartShiftActive(echoedAD)
                ScrollInterceptor.shared.wheelMode = echoedMode == .freeSpin ? .freeSpin : .ratchet
                SettingsStore.saveValue(Int(echoedMode.rawValue), id, deviceName: device.name)
                logger.info("[CapabilityHandlers] SmartShift wheel mode: \(echoedMode)")

            case .smartShiftActive:
                let enabled = device.toggles[id]?.value ?? true
                let idx = try await resolveSmartShiftIndex(on: device)
                // 0xFF = permanent ratchet = SmartShift effectively off.
                let echoedActive: Bool
                if device.smartShiftFid == SmartShiftV1Feature.featureId {
                    let status = try await SmartShiftV1Feature.setStatus(
                        transport: device.transport, deviceIndex: device.deviceIndex,
                        featureIndex: idx, wheelMode: nil,
                        autoDisengage: enabled ? 50 : 0, autoDisengageDefault: nil
                    )
                    device.segmented[CapabilityID.smartShiftWheelMode]?.selected = Int(status.wheelMode.rawValue)
                    echoedActive = isSmartShiftActive(status.autoDisengage)
                } else {
                    let torque = device.ints[CapabilityID.smartShiftTorque]?.value
                    let status = try await SmartShiftFeature.setStatus(
                        transport: device.transport, deviceIndex: device.deviceIndex,
                        featureIndex: idx, wheelMode: nil,
                        autoDisengage: enabled ? (torque ?? 50) : 0, torque: nil
                    )
                    device.segmented[CapabilityID.smartShiftWheelMode]?.selected = Int(status.wheelMode.rawValue)
                    if status.torque > 0 {
                        device.ints[CapabilityID.smartShiftTorque]?.value = status.torque
                    }
                    echoedActive = isSmartShiftActive(status.autoDisengage)
                }
                device.toggles[id]?.value = echoedActive
                ScrollInterceptor.shared.wheelMode = (device.segmented[CapabilityID.smartShiftWheelMode]?.selected == 1) ? .freeSpin : .ratchet
                SettingsStore.saveValue(echoedActive, id, deviceName: device.name)

            case .smartShiftTorque:
                // v1 and untunable-v2 have no torque slider state; the commit
                // guard in LogiDevice already no-ops, this is defense in depth.
                guard device.smartShiftFid != SmartShiftV1Feature.featureId else { return }
                let torque = device.ints[id]?.value ?? 50
                let idx = try await resolveSmartShiftIndex(on: device)
                let status = try await SmartShiftFeature.setStatus(
                    transport: device.transport, deviceIndex: device.deviceIndex,
                    featureIndex: idx, wheelMode: nil, autoDisengage: nil, torque: torque
                )
                if status.torque > 0 {
                    device.ints[id]?.value = status.torque
                }
                SettingsStore.saveValue(device.ints[id]?.value ?? torque, id, deviceName: device.name)

            case .hiResEnabled, .hiResInverted:
                guard let idx = device.hiResScrollFeatureIndex else { return }
                let hiRes = device.toggles[CapabilityID.hiResEnabled]?.value ?? true
                let inverted = device.toggles[CapabilityID.hiResInverted]?.value ?? false
                try await HiResScrollFeature.setWheelMode(
                    transport: device.transport, deviceIndex: device.deviceIndex,
                    featureIndex: idx,
                    target: device.toggles[CapabilityID.smoothScrollEnabled]?.value ?? false,
                    hiRes: hiRes, inverted: inverted
                )
                SettingsStore.saveValue(hiRes, CapabilityID.hiResEnabled, deviceName: device.name)
                SettingsStore.saveValue(inverted, CapabilityID.hiResInverted, deviceName: device.name)

            case .thumbWheelInverted:
                let inverted = device.toggles[id]?.value ?? false
                let idx = try await device.featureIndexCache.resolve(
                    featureId: ThumbWheelFeature.featureId,
                    transport: device.transport, deviceIndex: device.deviceIndex
                )
                try await ThumbWheelFeature.setConfig(
                    transport: device.transport, deviceIndex: device.deviceIndex,
                    featureIndex: idx, inverted: inverted, diverted: device.thumbDiverted
                )
                SettingsStore.saveValue(inverted, id, deviceName: device.name)

            case .smoothScrollEnabled:
                let enabled = device.toggles[id]?.value ?? false
                ScrollInterceptor.shared.isEnabled = enabled
                // Cancel any in-flight toggle so the final device state
                // matches the last user intent.
                device.hiResTargetTask?.cancel()
                device.hiResTargetTask = Task { await device.scrollBehavior?.setTarget(enabled) }
                SettingsStore.saveValue(enabled, id, deviceName: device.name)

            case .smoothScrollSpeed:
                let v = device.doubles[id]?.value ?? 3.0
                ScrollInterceptor.shared.speedMultiplier = v
                SettingsStore.saveValue(v, id, deviceName: device.name)

            case .smoothScrollMomentum:
                let v = device.doubles[id]?.value ?? 0.92
                ScrollInterceptor.shared.momentumDecay = v
                SettingsStore.saveValue(v, id, deviceName: device.name)

            case .smoothScrollThumbSpeed:
                let v = device.doubles[id]?.value ?? 1.0
                ScrollInterceptor.shared.thumbSpeedMultiplier = v
                SettingsStore.saveValue(v, id, deviceName: device.name)

            case .gestureClickMs, .gestureDragThreshold:
                device.thumbGestureBehavior?.syncEngine()
                if let v = device.ints[id]?.value { SettingsStore.saveValue(v, id, deviceName: device.name) }

            case .backlightEnabled, .backlightLevel:
                guard let fid = device.backlightFid else { return }
                let idx = try await device.featureIndexCache.resolve(
                    featureId: fid, transport: device.transport, deviceIndex: device.deviceIndex
                )
                let enabled = device.toggles[CapabilityID.backlightEnabled]?.value ?? false
                let level = device.ints[CapabilityID.backlightLevel]?.value ?? 0
                try await writeBacklight(enabled: enabled, level: level, on: device, index: idx)
                SettingsStore.saveValue(enabled, CapabilityID.backlightEnabled, deviceName: device.name)
                SettingsStore.saveValue(level, CapabilityID.backlightLevel, deviceName: device.name)

            case .fnStandardKeys:
                let wantStandard = device.toggles[id]?.value ?? true
                guard let fid = device.fnFid else { return }
                let idx = try await device.featureIndexCache.resolve(
                    featureId: fid, transport: device.transport, deviceIndex: device.deviceIndex
                )
                try await FnInversionFeature.setState(
                    transport: device.transport, deviceIndex: device.deviceIndex,
                    featureIndex: idx, featureId: fid,
                    fnInverted: !wantStandard, defaultState: device.fnDefaultState
                )
                SettingsStore.saveValue(wantStandard, id, deviceName: device.name)

            case .micMuteEnabled:
                let enabled = device.toggles[id]?.value ?? false
                await device.micMuteBehavior?.setEnabled(enabled)
                SettingsStore.saveValue(enabled, id, deviceName: device.name)

            case .battery, .hosts:
                break // Display-only; nothing to write.
            }
        } catch {
            debugLog("[CapabilityHandlers] Commit \(id.rawValue) failed: \(error)")
            logger.warning("[CapabilityHandlers] Commit \(id.rawValue) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Writers

    private static func writeDPI(_ dpi: Int, on device: LogiDevice, index idx: UInt8) async throws {
        let clamped = max(device.dpiMin, min(device.dpiMax, dpi))
        let snapped = (clamped / device.dpiStep) * device.dpiStep
        try await AdjustableDPIFeature.setSensorDPI(
            transport: device.transport, deviceIndex: device.deviceIndex,
            featureIndex: idx, dpi: snapped
        )
        device.ints[CapabilityID.dpi]?.value = snapped
        logger.info("[CapabilityHandlers] DPI set to \(snapped)")
    }

    private static func writeBacklight(enabled: Bool, level: Int, on device: LogiDevice, index idx: UInt8) async throws {
        guard let fid = device.backlightFid else { return }
        var mode = device.backlightMode
        if !enabled {
            mode = .off
        } else if mode == .off {
            mode = .manual
        }
        try await BacklightFeature.setBacklightConfig(
            transport: device.transport, deviceIndex: device.deviceIndex,
            featureIndex: idx, featureId: fid,
            enabled: enabled, mode: mode, level: level,
            currentOptions: device.backlightOptions,
            dho: device.backlightDho, dhi: device.backlightDhi, dpow: device.backlightDpow
        )
        device.toggles[CapabilityID.backlightEnabled]?.value = enabled
        device.backlightMode = mode
        device.ints[CapabilityID.backlightLevel]?.value = level
        device.backlightOptions = (device.backlightOptions & 0x07) | (UInt8(mode.rawValue) << 3)
        logger.info("[CapabilityHandlers] Backlight set: enabled=\(enabled) level=\(level)")
    }
}
