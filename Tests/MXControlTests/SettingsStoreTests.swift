import Testing
import Foundation
@testable import MXControl

@Suite("SettingsStore")
struct SettingsStoreTests {

    /// Use a unique device name per test to avoid cross-contamination.
    private func uniqueDeviceName(_ base: String = "TestDevice") -> String {
        "\(base)_\(UUID().uuidString.prefix(8))"
    }

    /// Clean up UserDefaults keys for a device name.
    private func cleanup(deviceName: String) {
        let prefix = "mxcontrol.\(deviceName.lowercased().replacingOccurrences(of: " ", with: "_"))"
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Mouse Settings Round-Trip

    @Test func mouseSettingsRoundTrip() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        let settings = SettingsStore.MouseSettings(
            dpi: 1600,
            pointerSpeed: 256,
            smartShiftActive: true,
            smartShiftTorque: 50,
            smartShiftWheelMode: 2,
            hiResEnabled: true,
            hiResInverted: false,
            thumbWheelInverted: true,
            buttonRemaps: [82: 86, 83: 82],
            gestureClickTimeLimit: 0.25,
            gestureDragThreshold: 200
        )

        SettingsStore.saveMouseSettings(settings, deviceName: name)
        let loaded = SettingsStore.loadMouseSettings(deviceName: name)

        #expect(loaded.dpi == 1600)
        #expect(loaded.pointerSpeed == 256)
        #expect(loaded.smartShiftActive == true)
        #expect(loaded.smartShiftTorque == 50)
        #expect(loaded.smartShiftWheelMode == 2)
        #expect(loaded.hiResEnabled == true)
        #expect(loaded.hiResInverted == false)
        #expect(loaded.thumbWheelInverted == true)
        #expect(loaded.buttonRemaps?[82] == 86)
        #expect(loaded.buttonRemaps?[83] == 82)
        #expect(loaded.gestureClickTimeLimit == 0.25)
        #expect(loaded.gestureDragThreshold == 200)
    }

    @Test func mouseSettingsPartialSave() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        // Save only DPI
        let settings = SettingsStore.MouseSettings(dpi: 800)
        SettingsStore.saveMouseSettings(settings, deviceName: name)

        let loaded = SettingsStore.loadMouseSettings(deviceName: name)
        #expect(loaded.dpi == 800)
        #expect(loaded.pointerSpeed == nil)
        #expect(loaded.smartShiftActive == nil)
        #expect(loaded.buttonRemaps == nil)
    }

    @Test func mouseSettingsEmptyLoad() {
        let name = uniqueDeviceName()
        let loaded = SettingsStore.loadMouseSettings(deviceName: name)

        #expect(loaded.dpi == nil)
        #expect(loaded.pointerSpeed == nil)
        #expect(loaded.smartShiftActive == nil)
        #expect(loaded.buttonRemaps == nil)
    }

    // MARK: - Button Remap Filtering

    @Test func mouseSettingsFilterThumbButton() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        // CID 195 (0x00C3) = gesture button -> should be filtered out
        let settings = SettingsStore.MouseSettings(
            buttonRemaps: [82: 86, 195: 82, 83: 82]
        )
        SettingsStore.saveMouseSettings(settings, deviceName: name)

        let loaded = SettingsStore.loadMouseSettings(deviceName: name)
        #expect(loaded.buttonRemaps?[82] == 86)
        #expect(loaded.buttonRemaps?[83] == 82)
        #expect(loaded.buttonRemaps?[195] == nil) // filtered
    }

    @Test func mouseSettingsFilterSelfRemaps() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        // Self-remap (CID == target) should be filtered
        let settings = SettingsStore.MouseSettings(
            buttonRemaps: [82: 82, 83: 86]
        )
        SettingsStore.saveMouseSettings(settings, deviceName: name)

        let loaded = SettingsStore.loadMouseSettings(deviceName: name)
        #expect(loaded.buttonRemaps?[82] == nil) // self-remap filtered
        #expect(loaded.buttonRemaps?[83] == 86)
    }

    // MARK: - Keyboard Settings Round-Trip

    @Test func keyboardSettingsRoundTrip() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        let settings = SettingsStore.KeyboardSettings(
            backlightEnabled: true,
            backlightLevel: 5,
            fnInverted: true
        )

        SettingsStore.saveKeyboardSettings(settings, deviceName: name)
        let loaded = SettingsStore.loadKeyboardSettings(deviceName: name)

        #expect(loaded.backlightEnabled == true)
        #expect(loaded.backlightLevel == 5)
        #expect(loaded.fnInverted == true)
    }

    @Test func keyboardSettingsEmptyLoad() {
        let name = uniqueDeviceName()
        let loaded = SettingsStore.loadKeyboardSettings(deviceName: name)

        #expect(loaded.backlightEnabled == nil)
        #expect(loaded.backlightLevel == nil)
        #expect(loaded.fnInverted == nil)
    }

    // MARK: - Key Format

    @Test func keyFormatSpacesAndCase() {
        let name1 = uniqueDeviceName("MX Master 3S")
        let name2 = uniqueDeviceName("mx keys mini")
        defer {
            cleanup(deviceName: name1)
            cleanup(deviceName: name2)
        }

        // Save with different case/spaces
        SettingsStore.saveMouseSettings(
            SettingsStore.MouseSettings(dpi: 1600), deviceName: name1
        )
        SettingsStore.saveKeyboardSettings(
            SettingsStore.KeyboardSettings(fnInverted: true), deviceName: name2
        )

        // Verify they can be loaded back
        let mouse = SettingsStore.loadMouseSettings(deviceName: name1)
        #expect(mouse.dpi == 1600)

        let keyboard = SettingsStore.loadKeyboardSettings(deviceName: name2)
        #expect(keyboard.fnInverted == true)
    }

    // MARK: - Special characters in device name

    @Test func specialCharsInDeviceName() {
        let name = uniqueDeviceName("MX-Keys_Mini (BLE)")
        defer { cleanup(deviceName: name) }

        let settings = SettingsStore.MouseSettings(dpi: 2400)
        SettingsStore.saveMouseSettings(settings, deviceName: name)

        let loaded = SettingsStore.loadMouseSettings(deviceName: name)
        #expect(loaded.dpi == 2400)
    }

    // MARK: - Empty remap dict after filtering

    @Test func mouseSettingsEmptyRemapAfterFiltering() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        // All remaps are self-remaps → all filtered out → empty dict saved
        let settings = SettingsStore.MouseSettings(
            buttonRemaps: [82: 82, 83: 83, 86: 86]
        )
        SettingsStore.saveMouseSettings(settings, deviceName: name)

        let loaded = SettingsStore.loadMouseSettings(deviceName: name)
        // The filtered dict is empty, but it's still saved as an empty dict
        #expect(loaded.buttonRemaps != nil)
        #expect(loaded.buttonRemaps!.isEmpty)
    }

    @Test func mouseSettingsAllGestureButtonsFiltered() {
        let name = uniqueDeviceName()
        defer { cleanup(deviceName: name) }

        // Only gesture button remap → filtered out → empty dict
        let settings = SettingsStore.MouseSettings(
            buttonRemaps: [195: 82]
        )
        SettingsStore.saveMouseSettings(settings, deviceName: name)

        let loaded = SettingsStore.loadMouseSettings(deviceName: name)
        #expect(loaded.buttonRemaps != nil)
        #expect(loaded.buttonRemaps!.isEmpty)
    }
}
