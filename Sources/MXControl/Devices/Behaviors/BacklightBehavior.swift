import Foundation
import MXControlHIDPP
import os

/// Backlight live-sync wiring (MX Keys Mini).
///
/// The device pushes `backlightInfoEvent` whenever the user adjusts the
/// backlight via hardware keys. Without this behavior the UI shows stale
/// load-time values. No divert or volatile state is involved — this only
/// routes notifications into capability states.
@MainActor
final class BacklightBehavior: DeviceBehavior {
    unowned let device: LogiDevice

    /// Resolved backlight feature index for notification routing.
    /// Set during capability load (v3 or v2, whichever the device reports).
    var featureIndex: UInt8?

    init(device: LogiDevice) {
        self.device = device
    }

    func load() async {
        // Index resolution + state creation happen in CapabilityHandlers;
        // mirror the resolved index here for routing.
        featureIndex = device.backlightFeatureIndex
    }

    /// Handle a `backlightInfoEvent` (event fn 0) notification.
    func handleNotification(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        guard let idx = self.featureIndex, featureIndex == idx else { return }
        guard functionId == 0x00 else { return }
        guard let update = BacklightFeature.parseInfoEvent(params: params) else { return }

        debugLog("[BacklightBehavior] InfoChanged: level=\(update.level)/\(update.levelCount) status=\(update.status)")
        device.ints[CapabilityID.backlightLevel]?.value = update.level
        if update.isManual {
            device.toggles[CapabilityID.backlightEnabled]?.value = true
        } else if update.isDisabled {
            device.toggles[CapabilityID.backlightEnabled]?.value = false
        }
        // ALS statuses leave the toggle alone; the level still tracks.
    }
}
