import Testing
@testable import MXControl
@testable import MXControlHIDPP

@Suite("DeviceRegistry")
struct DeviceRegistryTests {

    // MARK: - Feature Names

    @Test func knownFeatureNames() {
        #expect(DeviceRegistry.featureName(for: 0x0000) == "Root")
        #expect(DeviceRegistry.featureName(for: 0x0001) == "FeatureSet")
        #expect(DeviceRegistry.featureName(for: 0x1004) == "UnifiedBattery")
        #expect(DeviceRegistry.featureName(for: 0x2201) == "AdjustableDPI")
        #expect(DeviceRegistry.featureName(for: 0x2111) == "SmartShiftV2")
        #expect(DeviceRegistry.featureName(for: 0x1B04) == "SpecialKeysV4")
        #expect(DeviceRegistry.featureName(for: 0x1982) == "BacklightV2")
        #expect(DeviceRegistry.featureName(for: 0x1983) == "KeyboardBacklightV3")
        #expect(DeviceRegistry.featureName(for: 0x40A3) == "FnInversionV3")
    }

    @Test func unknownFeatureNameReturnsHex() {
        #expect(DeviceRegistry.featureName(for: 0xABCD) == "0xABCD")
        #expect(DeviceRegistry.featureName(for: 0x0002) == "0x0002")
    }

    // MARK: - DeviceType

    @Test func deviceTypeRawValues() {
        #expect(DeviceType.mouse.rawValue == "mouse")
        #expect(DeviceType.keyboard.rawValue == "keyboard")
        #expect(DeviceType.receiver.rawValue == "receiver")
        #expect(DeviceType.unknown.rawValue == "unknown")
    }
}
