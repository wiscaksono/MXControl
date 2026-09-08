import Foundation
import MXControlHIDPP
import os

/// Thumb-button gesture wiring via SpecialKeys divert (MX Master 3S).
///
/// Diverts the gesture CID (click → Mission Control, hold+drag → workspace
/// switch via `GestureEngine`) and optionally the side buttons (global
/// Back/Forward fallback). Side-button diverts are volatile; the thumb
/// divert persists only when the device reports PersistDivert support.
@MainActor
final class ThumbGestureBehavior: DeviceBehavior {
    unowned let device: LogiDevice

    /// Last pressed diverted CIDs from SpecialKeys event 0, for press-edge detection.
    private var lastPressedDivertedCIDs: Set<UInt16> = []

    init(device: LogiDevice) {
        self.device = device
    }

    // MARK: - Load

    func load() async {
        guard let spec = device.descriptor.thumbGesture else { return }
        guard device.hasFeature(SpecialKeysFeature.featureId) else { return }

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

            await divertThumb(spec: spec, controls: controls, featureIndex: idx)
            if spec.sideButtons {
                await divertSideButtons(controls: controls, featureIndex: idx)
            }
        } catch {
            device.loadErrors.append("Buttons: \(error.localizedDescription)")
            debugLog("[ThumbGestureBehavior] Load failed: \(error)")
        }
    }

    // MARK: - Divert

    private func divertThumb(spec: ThumbGestureSpec, controls: [SpecialKeysFeature.ControlInfo], featureIndex: UInt8) async {
        guard let thumbButton = controls.first(where: { $0.controlId == spec.thumbCID }) else {
            logger.info("[ThumbGestureBehavior] Thumb button CID 0x\(String(format: "%04X", spec.thumbCID), privacy: .public) not found in controls")
            return
        }
        guard thumbButton.isDivertable else {
            logger.info("[ThumbGestureBehavior] Thumb button is not divertable")
            return
        }

        MacActions.requestAccessibilityPermission()

        do {
            let hasRawXY = thumbButton.flags.contains(.rawXY)
            let canPersist = thumbButton.flags.contains(.persistDivert)
            try await DivertService.divert(
                spec.thumbCID,
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: featureIndex,
                persistDivert: canPersist,
                rawXY: hasRawXY
            )
            syncEngine()
            logger.info("[ThumbGestureBehavior] Thumb button diverted (rawXY=\(hasRawXY) persist=\(canPersist))")
        } catch {
            logger.error("[ThumbGestureBehavior] Failed to divert thumb button: \(error.localizedDescription)")
        }
    }

    private func divertSideButtons(controls: [SpecialKeysFeature.ControlInfo], featureIndex: UInt8) async {
        MacActions.requestAccessibilityPermission()
        await divertSideButton(controlId: SpecialKeysFeature.KnownCID.backButton.rawValue, label: "Back", controls: controls, featureIndex: featureIndex)
        await divertSideButton(controlId: SpecialKeysFeature.KnownCID.forwardButton.rawValue, label: "Forward", controls: controls, featureIndex: featureIndex)
    }

    private func divertSideButton(controlId: UInt16, label: String, controls: [SpecialKeysFeature.ControlInfo], featureIndex: UInt8) async {
        guard let button = controls.first(where: { $0.controlId == controlId }) else {
            debugLog("[ThumbGestureBehavior] \(label) button CID 0x\(String(format: "%04X", controlId)) not in controls")
            return
        }
        guard button.isDivertable else {
            logger.info("[ThumbGestureBehavior] \(label) button is not divertable")
            return
        }

        do {
            let preservedRemap = try await DivertService.remapTarget(
                controlId,
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: featureIndex
            )
            try await DivertService.divert(
                controlId,
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: featureIndex,
                persistDivert: false,
                remapTarget: preservedRemap
            )
            debugLog("[ThumbGestureBehavior] \(label) button diverted")
        } catch {
            logger.warning("[ThumbGestureBehavior] Failed to divert \(label) button: \(error.localizedDescription)")
        }
    }

    // MARK: - Gesture Engine

    /// (Re)create the engine and sync thresholds from capability states.
    func syncEngine() {
        guard let spec = device.descriptor.thumbGesture else { return }
        let clickMs = device.ints[CapabilityID.gestureClickMs]?.value ?? 200
        let drag = device.ints[CapabilityID.gestureDragThreshold]?.value ?? 200
        if device.gestureEngine == nil {
            device.gestureEngine = GestureEngine(thumbCID: spec.thumbCID)
        }
        device.gestureEngine?.updateConfig(clickTimeLimit: Double(clickMs) / 1000.0, dragThreshold: drag)
    }

    // MARK: - Notifications

    /// SpecialKeys notifications: diverted button presses + raw XY movement.
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        guard let skIdx = device.specialKeysFeatureIndex, featureIndex == skIdx else { return }

        switch functionId {
        case 0x00:
            let pressedCIDs = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
            debugLog("[ThumbGestureBehavior] divertedButtonsEvent: \(pressedCIDs.map { String(format: "0x%04X", $0) })")
            let currentPressed = Set(pressedCIDs)
            let newlyPressed = currentPressed.subtracting(lastPressedDivertedCIDs)
            lastPressedDivertedCIDs = currentPressed

            if newlyPressed.contains(SpecialKeysFeature.KnownCID.backButton.rawValue) {
                MacActions.navigateBack()
            }
            if newlyPressed.contains(SpecialKeysFeature.KnownCID.forwardButton.rawValue) {
                MacActions.navigateForward()
            }
            device.gestureEngine?.handleButtonEvent(pressedCIDs: pressedCIDs)

        case 0x01:
            let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
            device.gestureEngine?.handleRawXY(deltaX: dx, deltaY: dy)

        default:
            break
        }
    }

    // MARK: - Rearm

    func rearm() async {
        guard let spec = device.descriptor.thumbGesture else { return }
        guard let idx = device.specialKeysFeatureIndex else {
            // Index lost — full reload recovers everything.
            await load()
            return
        }
        do {
            let controls = try await DivertService.enumerate(
                transport: device.transport,
                deviceIndex: device.deviceIndex,
                featureIndex: idx
            )
            await divertThumb(spec: spec, controls: controls, featureIndex: idx)
            if spec.sideButtons {
                await divertSideButtons(controls: controls, featureIndex: idx)
            }
            if device.gestureEngine == nil {
                syncEngine()
            }
            logger.info("[ThumbGestureBehavior] Divert re-armed after BLE reconnection")
        } catch {
            debugLog("[ThumbGestureBehavior] Rearm failed: \(error)")
            logger.warning("[ThumbGestureBehavior] Failed to re-arm divert: \(error.localizedDescription)")
        }
    }
}
