import Foundation
import MXControlHIDPP
import os

/// Smooth-scroll wiring for HiResScroll devices (MX Master 3S).
///
/// Owns the HID++ target flag (scroll data via notifications vs macOS
/// pipeline), the hi-res multiplier, and sync of capability states into the
/// shared `ScrollInterceptor`. Scalar settings (speed, momentum, toggles)
/// live in capability states; this behavior only moves values across.
@MainActor
final class ScrollBehavior: DeviceBehavior {
    unowned let device: LogiDevice

    init(device: LogiDevice) {
        self.device = device
    }

    var hiResScrollFeatureIndex: UInt8? { device.hiResScrollFeatureIndex }

    // MARK: - Load

    func load() async {
        guard device.descriptor.scroll != nil else { return }
        guard device.hasFeature(HiResScrollFeature.featureId) else { return }

        do {
            let idx = try await device.featureIndexCache.resolve(
                featureId: HiResScrollFeature.featureId,
                transport: device.transport,
                deviceIndex: device.deviceIndex
            )
            device.hiResScrollFeatureIndex = idx

            let caps = try await HiResScrollFeature.getWheelCapability(
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: idx
            )
            device.hiResMultiplier = max(caps.multiplier, 1)
            ScrollInterceptor.shared.hiResPixelsPerTick = 15.0 / Double(device.hiResMultiplier)

            let mode = try await HiResScrollFeature.getWheelMode(
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: idx
            )
            // Saved prefs win over hardware so reconnects restore settings.
            var hiRes = mode.hiRes
            var inverted = mode.inverted
            let savedHiRes: Bool? = SettingsStore.savedValue(CapabilityID.hiResEnabled, deviceName: device.name)
            let savedInverted: Bool? = SettingsStore.savedValue(CapabilityID.hiResInverted, deviceName: device.name)
            if savedHiRes != nil || savedInverted != nil {
                hiRes = savedHiRes ?? hiRes
                inverted = savedInverted ?? inverted
                try await HiResScrollFeature.setWheelMode(
                    transport: device.transport,
                    deviceIndex: device.deviceIndex,
                    featureIndex: idx,
                    target: false,
                    hiRes: hiRes,
                    inverted: inverted
                )
            }
            device.toggles[CapabilityID.hiResEnabled]?.value = hiRes
            device.toggles[CapabilityID.hiResInverted]?.value = inverted

            syncServices()

            // If smooth scroll is enabled, activate HID++ target mode.
            if device.toggles[CapabilityID.smoothScrollEnabled]?.value == true {
                await setTarget(true)
            }

            logger.info("[ScrollBehavior] HiRes: enabled=\(hiRes) inverted=\(inverted) multiplier=\(self.device.hiResMultiplier)")
        } catch {
            device.loadErrors.append("HiResScroll: \(error.localizedDescription)")
            debugLog("[ScrollBehavior] Load failed: \(error)")
        }
    }

    // MARK: - Service Sync

    /// Push capability-state values into the shared interceptor.
    func syncServices() {
        let t = device.toggles
        let d = device.doubles
        if let enabled = t[CapabilityID.smoothScrollEnabled]?.value {
            ScrollInterceptor.shared.isEnabled = enabled
        }
        if let speed = d[CapabilityID.smoothScrollSpeed]?.value {
            ScrollInterceptor.shared.speedMultiplier = speed
        }
        if let momentum = d[CapabilityID.smoothScrollMomentum]?.value {
            ScrollInterceptor.shared.momentumDecay = momentum
        }
        if let thumb = d[CapabilityID.smoothScrollThumbSpeed]?.value {
            ScrollInterceptor.shared.thumbSpeedMultiplier = thumb
        }
        if let mode = device.segmented[CapabilityID.smartShiftWheelMode]?.selected {
            ScrollInterceptor.shared.wheelMode = mode == SmartShiftFeature.WheelMode.freeSpin.rawValue ? .freeSpin : .ratchet
        }
    }

    /// Enable or disable HID++ target mode for hi-res scroll data.
    func setTarget(_ enabled: Bool) async {
        guard let idx = device.hiResScrollFeatureIndex else { return }
        let inverted = device.toggles[CapabilityID.hiResInverted]?.value ?? false
        let hiRes = device.toggles[CapabilityID.hiResEnabled]?.value ?? true
        do {
            try await HiResScrollFeature.setWheelMode(
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: idx,
                target: enabled,
                hiRes: hiRes,
                inverted: inverted
            )
            ScrollInterceptor.shared.hiResActive = enabled
            logger.info("[ScrollBehavior] HiRes target set to \(enabled ? "HID++" : "HID")")
        } catch {
            // Force hiResActive off on failure so the CGEventTap does not
            // suppress scroll events while the device state is unknown.
            ScrollInterceptor.shared.hiResActive = false
            logger.warning("[ScrollBehavior] Failed to set HiRes target: \(error.localizedDescription)")
        }
    }

    // MARK: - Notifications

    /// Ratchet-switch events (SmartShift auto-switch). Wheel movement (event 0)
    /// bypasses this via the fast path in DeviceManager.
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        guard let hrIdx = device.hiResScrollFeatureIndex, featureIndex == hrIdx else { return }
        guard functionId == 0x01 else { return }
        if let isRatchet = HiResScrollFeature.parseRatchetSwitch(params: params) {
            let raw = Int(isRatchet ? SmartShiftFeature.WheelMode.ratchet.rawValue : SmartShiftFeature.WheelMode.freeSpin.rawValue)
            device.segmented[CapabilityID.smartShiftWheelMode]?.selected = raw
            ScrollInterceptor.shared.wheelMode = isRatchet ? .ratchet : .freeSpin
            debugLog("[ScrollBehavior] Ratchet switch: \(isRatchet ? "ratchet" : "freeSpin")")
        }
    }

    // MARK: - Rearm

    func rearm() async {
        if device.toggles[CapabilityID.smoothScrollEnabled]?.value == true {
            await setTarget(true)
        }
    }
}
