import Testing
import Foundation
@testable import MXControl

/// Tests for the production settings path used by capability commit/load
/// (`saveValue`/`savedValue`). The DTO suite covers the legacy structs;
/// this suite covers what the app actually reads and writes.
@Suite("Capability Settings Storage")
struct CapabilitySettingsTests {

    private func uniqueDeviceName(_ base: String = "CapTest") -> String {
        "\(base)_\(UUID().uuidString.prefix(8))"
    }

    @Test func boolRoundTrip() {
        let name = uniqueDeviceName()
        SettingsStore.saveValue(true, CapabilityID.micMuteEnabled, deviceName: name)
        let loaded: Bool? = SettingsStore.savedValue(CapabilityID.micMuteEnabled, deviceName: name)
        #expect(loaded == true)
    }

    @Test func intRoundTrip() {
        let name = uniqueDeviceName()
        SettingsStore.saveValue(200, CapabilityID.gestureClickMs, deviceName: name)
        let loaded: Int? = SettingsStore.savedValue(CapabilityID.gestureClickMs, deviceName: name)
        #expect(loaded == 200)
    }

    @Test func doubleRoundTrip() {
        let name = uniqueDeviceName()
        SettingsStore.saveValue(3.5, CapabilityID.smoothScrollSpeed, deviceName: name)
        let loaded: Double? = SettingsStore.savedValue(CapabilityID.smoothScrollSpeed, deviceName: name)
        #expect(loaded == 3.5)
    }

    @Test func missingKeyReturnsNil() {
        let loaded: Bool? = SettingsStore.savedValue("never.saved", deviceName: uniqueDeviceName())
        #expect(loaded == nil)
    }

    @Test func typeMismatchReturnsNil() {
        let name = uniqueDeviceName()
        SettingsStore.saveValue(200, CapabilityID.gestureClickMs, deviceName: name)
        let loaded: Bool? = SettingsStore.savedValue(CapabilityID.gestureClickMs, deviceName: name)
        #expect(loaded == nil)
    }

    @Test func fnKeysIndependentFromLegacyInverted() {
        // Prod key (UI sense) and legacy key (protocol sense) coexist;
        // the migration in CapabilityHandlers flips legacy exactly once.
        let name = uniqueDeviceName()
        SettingsStore.saveValue(true, "fn.inverted", deviceName: name)
        let legacy: Bool? = SettingsStore.savedValue("fn.inverted", deviceName: name)
        let prod: Bool? = SettingsStore.savedValue(CapabilityID.fnStandardKeys, deviceName: name)
        #expect(legacy == true)
        #expect(prod == nil)
    }

    @Test func clearRemovesCapabilityKeys() {
        let name = uniqueDeviceName()
        SettingsStore.saveValue(true, CapabilityID.micMuteEnabled, deviceName: name)
        SettingsStore.saveValue(200, CapabilityID.gestureClickMs, deviceName: name)
        SettingsStore.clearSettings(for: name)
        let mic: Bool? = SettingsStore.savedValue(CapabilityID.micMuteEnabled, deviceName: name)
        let ms: Int? = SettingsStore.savedValue(CapabilityID.gestureClickMs, deviceName: name)
        #expect(mic == nil)
        #expect(ms == nil)
    }
}
