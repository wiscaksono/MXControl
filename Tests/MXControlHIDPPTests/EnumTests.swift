import Testing
@testable import MXControlHIDPP

// MARK: - Battery Enum Tests

@Suite("BatteryFeature Enums")
struct BatteryEnumTests {

    @Test func chargingStatusDescriptions() {
        #expect(BatteryFeature.ChargingStatus.discharging.description == "Discharging")
        #expect(BatteryFeature.ChargingStatus.charging.description == "Charging")
        #expect(BatteryFeature.ChargingStatus.chargingSlowly.description == "Charging (slow)")
        #expect(BatteryFeature.ChargingStatus.chargingComplete.description == "Fully Charged")
        #expect(BatteryFeature.ChargingStatus.chargingError.description == "Charging Error")
    }

    @Test func chargingStatusIsCharging() {
        #expect(BatteryFeature.ChargingStatus.charging.isCharging == true)
        #expect(BatteryFeature.ChargingStatus.chargingSlowly.isCharging == true)
        #expect(BatteryFeature.ChargingStatus.chargingComplete.isCharging == true)
        #expect(BatteryFeature.ChargingStatus.discharging.isCharging == false)
        #expect(BatteryFeature.ChargingStatus.chargingError.isCharging == false)
    }

    @Test func batteryLevelDescriptions() {
        #expect(BatteryFeature.BatteryLevel.critical.description == "Critical")
        #expect(BatteryFeature.BatteryLevel.low.description == "Low")
        #expect(BatteryFeature.BatteryLevel.good.description == "Good")
        #expect(BatteryFeature.BatteryLevel.full.description == "Full")
    }

    @Test func batteryLevelRawValues() {
        #expect(BatteryFeature.BatteryLevel.critical.rawValue == 1)
        #expect(BatteryFeature.BatteryLevel.low.rawValue == 2)
        #expect(BatteryFeature.BatteryLevel.good.rawValue == 4)
        #expect(BatteryFeature.BatteryLevel.full.rawValue == 8)
    }

    @Test func capabilitiesFlags() {
        let caps1 = BatteryFeature.Capabilities(supportedLevels: 0xFF, flags: 0x03)
        #expect(caps1.hasSoC == true)
        #expect(caps1.isRechargeable == true)

        let caps2 = BatteryFeature.Capabilities(supportedLevels: 0xFF, flags: 0x01)
        #expect(caps2.hasSoC == false)
        #expect(caps2.isRechargeable == true)

        let caps3 = BatteryFeature.Capabilities(supportedLevels: 0xFF, flags: 0x00)
        #expect(caps3.hasSoC == false)
        #expect(caps3.isRechargeable == false)
    }
}

// MARK: - FeatureSet Entry Tests

@Suite("FeatureSetFeature.FeatureEntry")
struct FeatureSetEntryTests {

    @Test func isHidden() {
        let hidden = FeatureSetFeature.FeatureEntry(featureId: 0x1E00, index: 5, type: 0x02)
        #expect(hidden.isHidden == true)
        #expect(hidden.isObsolete == false)
    }

    @Test func isObsolete() {
        let obsolete = FeatureSetFeature.FeatureEntry(featureId: 0x1000, index: 3, type: 0x04)
        #expect(obsolete.isHidden == false)
        #expect(obsolete.isObsolete == true)
    }

    @Test func normalEntry() {
        let normal = FeatureSetFeature.FeatureEntry(featureId: 0x1004, index: 2, type: 0x00)
        #expect(normal.isHidden == false)
        #expect(normal.isObsolete == false)
    }

    @Test func hiddenAndObsolete() {
        let both = FeatureSetFeature.FeatureEntry(featureId: 0x0000, index: 0, type: 0x06)
        #expect(both.isHidden == true)
        #expect(both.isObsolete == true)
    }

    @Test func description() {
        let entry = FeatureSetFeature.FeatureEntry(featureId: 0x1004, index: 2, type: 0x00)
        #expect(entry.description.contains("1004"))
        #expect(entry.description.contains("2"))
    }

    @Test func descriptionWithFlags() {
        let entry = FeatureSetFeature.FeatureEntry(featureId: 0x1E00, index: 5, type: 0x06)
        #expect(entry.description.contains("[hidden]"))
        #expect(entry.description.contains("[obsolete]"))
    }
}

// MARK: - SmartShift Enum Tests

@Suite("SmartShiftFeature Enums")
struct SmartShiftEnumTests {

    @Test func wheelModeDescriptions() {
        #expect(SmartShiftFeature.WheelMode.freeSpin.description == "Free Spin")
        #expect(SmartShiftFeature.WheelMode.ratchet.description == "Ratchet")
    }

    @Test func wheelModeRawValues() {
        #expect(SmartShiftFeature.WheelMode.freeSpin.rawValue == 1)
        #expect(SmartShiftFeature.WheelMode.ratchet.rawValue == 2)
    }
}

// MARK: - HostsInfo Enum Tests

@Suite("HostsInfoFeature Enums")
struct HostsInfoEnumTests {

    @Test func busTypeDescriptions() {
        #expect(HostsInfoFeature.BusType.undefined.description == "Unknown")
        #expect(HostsInfoFeature.BusType.equad.description == "Receiver")
        #expect(HostsInfoFeature.BusType.usb.description == "USB")
        #expect(HostsInfoFeature.BusType.bluetoothClassic.description == "Bluetooth")
        #expect(HostsInfoFeature.BusType.ble.description == "Bluetooth LE")
        #expect(HostsInfoFeature.BusType.blePro.description == "Bolt")
    }

    @Test func busTypeRawValues() {
        #expect(HostsInfoFeature.BusType(rawValue: 0) == .undefined)
        #expect(HostsInfoFeature.BusType(rawValue: 1) == .equad)
        #expect(HostsInfoFeature.BusType(rawValue: 2) == .usb)
        #expect(HostsInfoFeature.BusType(rawValue: 3) == .bluetoothClassic)
        #expect(HostsInfoFeature.BusType(rawValue: 4) == .ble)
        #expect(HostsInfoFeature.BusType(rawValue: 5) == .blePro)
        #expect(HostsInfoFeature.BusType(rawValue: 6) == nil)
    }

    @Test func slotStatusRawValues() {
        #expect(HostsInfoFeature.SlotStatus(rawValue: 0) == .empty)
        #expect(HostsInfoFeature.SlotStatus(rawValue: 1) == .paired)
        #expect(HostsInfoFeature.SlotStatus(rawValue: 2) == nil)
    }
}

// MARK: - DeviceName Enum Tests

@Suite("DeviceNameFeature.DeviceKind")
struct DeviceKindTests {

    @Test func allDescriptions() {
        #expect(DeviceNameFeature.DeviceKind.keyboard.description == "Keyboard")
        #expect(DeviceNameFeature.DeviceKind.remoteControl.description == "Remote Control")
        #expect(DeviceNameFeature.DeviceKind.numpad.description == "Numpad")
        #expect(DeviceNameFeature.DeviceKind.mouse.description == "Mouse")
        #expect(DeviceNameFeature.DeviceKind.touchpad.description == "Touchpad")
        #expect(DeviceNameFeature.DeviceKind.trackball.description == "Trackball")
        #expect(DeviceNameFeature.DeviceKind.presenter.description == "Presenter")
        #expect(DeviceNameFeature.DeviceKind.receiver.description == "Receiver")
        #expect(DeviceNameFeature.DeviceKind.headset.description == "Headset")
        #expect(DeviceNameFeature.DeviceKind.webcam.description == "Webcam")
        #expect(DeviceNameFeature.DeviceKind.steeringWheel.description == "Steering Wheel")
        #expect(DeviceNameFeature.DeviceKind.joystick.description == "Joystick")
        #expect(DeviceNameFeature.DeviceKind.gamepad.description == "Gamepad")
        #expect(DeviceNameFeature.DeviceKind.dock.description == "Dock")
        #expect(DeviceNameFeature.DeviceKind.speaker.description == "Speaker")
        #expect(DeviceNameFeature.DeviceKind.microphone.description == "Microphone")
        #expect(DeviceNameFeature.DeviceKind.unknown.description == "Unknown")
    }

    @Test func rawValues() {
        #expect(DeviceNameFeature.DeviceKind.keyboard.rawValue == 0)
        #expect(DeviceNameFeature.DeviceKind.mouse.rawValue == 3)
        #expect(DeviceNameFeature.DeviceKind.unknown.rawValue == 0xFF)
    }

    @Test func initFromRawValue() {
        #expect(DeviceNameFeature.DeviceKind(rawValue: 0) == .keyboard)
        #expect(DeviceNameFeature.DeviceKind(rawValue: 3) == .mouse)
        #expect(DeviceNameFeature.DeviceKind(rawValue: 15) == .microphone)
        #expect(DeviceNameFeature.DeviceKind(rawValue: 16) == nil) // gap before 0xFF
    }
}

// MARK: - FnInversion Tests

@Suite("FnInversionFeature")
struct FnInversionEnumTests {

    @Test func isEnhanced() {
        #expect(FnInversionFeature.isEnhanced(0x40A3) == true)
        #expect(FnInversionFeature.isEnhanced(0x40A2) == false)
        #expect(FnInversionFeature.isEnhanced(0x40A0) == false)
    }

    @Test func allFeatureIdsOrder() {
        let ids = FnInversionFeature.allFeatureIds
        #expect(ids.count == 3)
        #expect(ids[0] == 0x40A3) // v3 first (preferred)
        #expect(ids[1] == 0x40A2) // v2
        #expect(ids[2] == 0x40A0) // v0
    }
}

// MARK: - Backlight Config Tests

@Suite("BacklightFeature.BacklightConfig")
struct BacklightConfigTests {

    @Test func autoSupported() {
        let config1 = BacklightFeature.BacklightConfig(
            enabled: true, options: 0, supported: 0x08,
            mode: .automatic, level: 0, dho: 0, dhi: 0, dpow: 0
        )
        #expect(config1.autoSupported == true)
        #expect(config1.tempSupported == false)
        #expect(config1.permSupported == false)
    }

    @Test func tempSupported() {
        let config = BacklightFeature.BacklightConfig(
            enabled: true, options: 0, supported: 0x10,
            mode: .temporary, level: 0, dho: 0, dhi: 0, dpow: 0
        )
        #expect(config.autoSupported == false)
        #expect(config.tempSupported == true)
        #expect(config.permSupported == false)
    }

    @Test func permSupported() {
        let config = BacklightFeature.BacklightConfig(
            enabled: true, options: 0, supported: 0x20,
            mode: .manual, level: 5, dho: 0, dhi: 0, dpow: 0
        )
        #expect(config.autoSupported == false)
        #expect(config.tempSupported == false)
        #expect(config.permSupported == true)
    }

    @Test func allSupported() {
        let config = BacklightFeature.BacklightConfig(
            enabled: true, options: 0, supported: 0x38,
            mode: .manual, level: 5, dho: 0, dhi: 0, dpow: 0
        )
        #expect(config.autoSupported == true)
        #expect(config.tempSupported == true)
        #expect(config.permSupported == true)
    }
}
