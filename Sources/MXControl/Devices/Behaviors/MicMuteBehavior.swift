import Foundation
import MXControlHIDPP
import os

/// F9 mic-mute wiring via SpecialKeys divert + event-tap fallback (MX Keys Mini).
///
/// Primary path diverts the mic-mute CID so presses arrive as HID++
/// notifications. When no divert is active (CID unidentified or divert
/// unavailable), `DeviceManager` enables the global `F9KeyMonitor` fallback.
@MainActor
final class MicMuteBehavior: DeviceBehavior {
    unowned let device: LogiDevice

    /// Whether the mic-mute CID is currently diverted via HID++.
    var divertActive: Bool = false
    /// CID of the mic-mute control, once identified. Nil until then.
    var micCID: UInt16?
    /// Last press state of the diverted mic-mute CID, for press-edge detection.
    private var lastPressed: Bool = false

    /// Injectable mic-mute action for tests. Defaults to engine + overlay.
    var onMicMuteKeypress: (() -> Void)?

    init(device: LogiDevice) {
        self.device = device
    }

    var isEnabled: Bool {
        device.toggles[CapabilityID.micMuteEnabled]?.value ?? false
    }

    // MARK: - Load

    func load() async {
        guard device.descriptor.micMute != nil else { return }
        // Toggle state (default true) is created by CapabilityHandlers.
        guard isEnabled else {
            debugLog("[MicMuteBehavior] Mic mute disabled — skipping")
            return
        }
        await setupDivert()
    }

    /// Enumerate controls and divert the mic-mute CID when identified.
    func setupDivert() async {
        guard let spec = device.descriptor.micMute else { return }
        guard device.hasFeature(SpecialKeysFeature.featureId) else {
            logger.info("[MicMuteBehavior] No 0x1B04 feature — mic mute via F9KeyMonitor fallback")
            return
        }

        do {
            let idx = try await device.featureIndexCache.resolve(
                featureId: SpecialKeysFeature.featureId,
                transport: device.transport,
                deviceIndex: device.deviceIndex
            )
            device.specialKeysFeatureIndex = idx

            let controls = try await DivertService.enumerate(
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: idx
            )
            for control in controls {
                debugLog("[MicMuteBehavior] Control CID=\(String(format: "0x%04X", control.controlId)) TID=\(String(format: "0x%04X", control.taskId)) flags=0x\(String(format: "%04X", control.flags.rawValue)) pos=\(control.position) group=\(control.group)")
            }
            logger.info("[MicMuteBehavior] Enumerated \(controls.count) controls via 0x1B04")

            if let cid = Self.matchCID(in: controls, spec: spec) {
                try await divert(cid: cid, featureIndex: idx)
            } else {
                logger.info("[MicMuteBehavior] Mic-mute CID not identified — using F9KeyMonitor fallback")
                NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
            }
        } catch {
            device.loadErrors.append("MicMute: \(error.localizedDescription)")
            debugLog("[MicMuteBehavior] Setup failed: \(error)")
            logger.warning("[MicMuteBehavior] Mic mute setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Identify the mic-mute control. Requires the candidate CID plus position
    /// and FN-flag guards so a firmware remap cannot divert the wrong key.
    static func matchCID(in controls: [SpecialKeysFeature.ControlInfo], spec: MicMuteSpec) -> UInt16? {
        guard let match = controls.first(where: { $0.controlId == spec.cid }),
              match.isDivertable,
              match.position == spec.position,
              !spec.requireFnFlag || match.flags.contains(.fnKey)
        else {
            return nil
        }
        return match.controlId
    }

    // MARK: - Divert

    private func divert(cid: UInt16, featureIndex: UInt8) async throws {
        try await DivertService.divert(
            cid,
            transport: device.transport,
            deviceIndex: device.deviceIndex,
            featureIndex: featureIndex
        )
        micCID = cid
        divertActive = true
        logger.info("[MicMuteBehavior] Mic-mute CID 0x\(String(format: "%04X", cid), privacy: .public) diverted")
        NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
    }

    /// Clear an active divert (e.g. when the feature is toggled off).
    func clearDivert() async {
        guard divertActive, let cid = micCID, let idx = device.specialKeysFeatureIndex else { return }
        do {
            try await DivertService.undivert(
                cid,
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: idx
            )
        } catch {
            debugLog("[MicMuteBehavior] Failed to clear divert: \(error)")
        }
        micCID = nil
        divertActive = false
    }

    /// Enable or disable F9 mic mute at runtime (from UI toggle).
    /// Persistence is handled by the caller via the capability commit path.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            await setupDivert()
        } else {
            await clearDivert()
        }
        NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
    }

    // MARK: - Notifications

    /// Diverted mic-mute presses (press edge only).
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        guard let skIdx = device.specialKeysFeatureIndex, featureIndex == skIdx else { return }
        guard functionId == 0x00 else { return }
        guard let cid = micCID else { return }

        let pressed = Set(SpecialKeysFeature.parseDivertedButtonsEvent(params: params))
        let isDown = pressed.contains(cid)
        let wasDown = lastPressed
        lastPressed = isDown

        if isDown && !wasDown {
            fire()
        }
    }

    /// Fire the mic-mute action: engine toggle + persistent muted pill.
    func fire() {
        if let custom = onMicMuteKeypress {
            custom()
            return
        }
        let muted = MicMuteEngine.shared.toggleFromKeypress()
        MicMuteOverlay.shared.reflect(muted: muted)
    }

    // MARK: - Rearm

    func rearm() async {
        guard isEnabled else { return }
        if micCID == nil {
            // CID never identified — retry full enumeration, the earlier
            // failure may have been transient.
            await setupDivert()
            return
        }
        guard let cid = micCID, let idx = device.specialKeysFeatureIndex else { return }
        do {
            try await divert(cid: cid, featureIndex: idx)
            logger.info("[MicMuteBehavior] Divert re-armed after BLE reconnection")
        } catch {
            // Divert lost and re-arm failed: mark inactive so the F9 fallback
            // tap takes over instead of leaving F9 dead.
            divertActive = false
            NotificationCenter.default.post(name: .micMuteConfigChanged, object: nil)
            debugLog("[MicMuteBehavior] Rearm failed: \(error)")
            logger.warning("[MicMuteBehavior] Failed to re-arm divert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
