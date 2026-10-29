import Testing
import Foundation
@testable import DeviceCore

/// Tests for SettingsStore persistence. Production reads/writes through the
/// single-value `saveValue`/`savedValue` API keyed by capability id
/// (`mxcontrol.{device}.{suffix}`); these tests cover exactly that path.
@Suite("SettingsStore")
struct SettingsStoreTests {

    /// Use a unique device name per test to avoid cross-contamination.
    private func uniqueDeviceName(_ base: String = "TestDevice") -> String {
        "\(base)_\(UUID().uuidString.prefix(8))"
    }

    /// Clean up UserDefaults keys for a device name.
    private func cleanup(scope: String) {
        SettingsStore.clearSettings(for: scope)
    }

    // MARK: - Single-Value Round-Trip

    @Test func intRoundTrip() {
        let name = uniqueDeviceName()
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(1600, CapabilityID.dpi, scope: name)
        let loaded: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name)

        #expect(loaded == 1600)
    }

    @Test func boolRoundTrip() {
        let name = uniqueDeviceName()
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(true, CapabilityID.smartShiftActive, scope: name)
        SettingsStore.saveValue(false, CapabilityID.hiResInverted, scope: name)

        let active: Bool? = SettingsStore.savedValue(CapabilityID.smartShiftActive, scope: name)
        let inverted: Bool? = SettingsStore.savedValue(CapabilityID.hiResInverted, scope: name)

        #expect(active == true)
        #expect(inverted == false)
    }

    @Test func doubleRoundTrip() {
        let name = uniqueDeviceName()
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(3.5, CapabilityID.smoothScrollSpeed, scope: name)
        let loaded: Double? = SettingsStore.savedValue(CapabilityID.smoothScrollSpeed, scope: name)

        #expect(loaded == 3.5)
    }

    @Test func missingKeyReturnsNil() {
        let intLoaded: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: uniqueDeviceName())
        let boolLoaded: Bool? = SettingsStore.savedValue(CapabilityID.smartShiftActive, scope: uniqueDeviceName())

        #expect(intLoaded == nil)
        #expect(boolLoaded == nil)
    }

    @Test func typeMismatchReturnsNil() {
        let name = uniqueDeviceName()
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(1600, CapabilityID.dpi, scope: name)
        let loaded: Bool? = SettingsStore.savedValue(CapabilityID.dpi, scope: name)

        #expect(loaded == nil)
    }

    @Test func overwriteReplacesValue() {
        let name = uniqueDeviceName()
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(800, CapabilityID.dpi, scope: name)
        SettingsStore.saveValue(1600, CapabilityID.dpi, scope: name)
        let loaded: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name)

        #expect(loaded == 1600)
    }

    // MARK: - Key Format

    @Test func keyFormatSpacesAndCase() {
        let name1 = uniqueDeviceName("MX Master 3S")
        let name2 = uniqueDeviceName("mx keys mini")
        defer {
            cleanup(scope: name1)
            cleanup(scope: name2)
        }

        SettingsStore.saveValue(1600, CapabilityID.dpi, scope: name1)
        SettingsStore.saveValue(false, CapabilityID.fnStandardKeys, scope: name2)

        let dpi: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name1)
        #expect(dpi == 1600)

        let fnStandard: Bool? = SettingsStore.savedValue(CapabilityID.fnStandardKeys, scope: name2)
        #expect(fnStandard == false)
    }

    @Test func specialCharsInDeviceName() {
        let name = uniqueDeviceName("MX-Keys_Mini (BLE)")
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(2400, CapabilityID.dpi, scope: name)
        let loaded: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name)

        #expect(loaded == 2400)
    }

    // MARK: - Clear Settings

    @Test func clearSettingsRemovesAllKeys() {
        let name = uniqueDeviceName()
        defer { cleanup(scope: name) }

        SettingsStore.saveValue(1600, CapabilityID.dpi, scope: name)
        SettingsStore.saveValue(256, CapabilityID.pointerSpeed, scope: name)
        SettingsStore.saveValue(true, CapabilityID.backlightEnabled, scope: name)

        let beforeDPI: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name)
        #expect(beforeDPI == 1600)

        SettingsStore.clearSettings(for: name)

        let afterDPI: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name)
        let afterSpeed: Int? = SettingsStore.savedValue(CapabilityID.pointerSpeed, scope: name)
        let afterBacklight: Bool? = SettingsStore.savedValue(CapabilityID.backlightEnabled, scope: name)
        #expect(afterDPI == nil)
        #expect(afterSpeed == nil)
        #expect(afterBacklight == nil)
    }

    @Test func clearSettingsDoesNotAffectOtherDevices() {
        let name1 = uniqueDeviceName("Device A")
        let name2 = uniqueDeviceName("Device B")
        defer {
            cleanup(scope: name1)
            cleanup(scope: name2)
        }

        SettingsStore.saveValue(1600, CapabilityID.dpi, scope: name1)
        SettingsStore.saveValue(3200, CapabilityID.dpi, scope: name2)

        SettingsStore.clearSettings(for: name1)

        let afterA: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name1)
        #expect(afterA == nil)

        let afterB: Int? = SettingsStore.savedValue(CapabilityID.dpi, scope: name2)
        #expect(afterB == 3200)
    }
}
