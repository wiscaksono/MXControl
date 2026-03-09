import Testing
@testable import MXControl

@Suite("DeviceRegistry")
struct DeviceRegistryTests {

    // MARK: - Receiver PIDs

    @Test func isReceiverKnownPIDs() {
        let knownReceiverPIDs = [0xC52B, 0xC52D, 0xC52E, 0xC534, 0xC539, 0xC53A, 0xC547, 0xC548, 0xC549]
        for pid in knownReceiverPIDs {
            #expect(DeviceRegistry.isReceiver(pid: pid), "Expected PID 0x\(String(pid, radix: 16)) to be a receiver")
        }
    }

    @Test func isReceiverUnknownPIDs() {
        #expect(DeviceRegistry.isReceiver(pid: 0x0000) == false)
        #expect(DeviceRegistry.isReceiver(pid: 0xB034) == false) // MX Master 3S BLE
        #expect(DeviceRegistry.isReceiver(pid: 0xFFFF) == false)
    }

    @Test func receiverPIDCount() {
        #expect(DeviceRegistry.receiverPIDs.count == 9)
    }

    // MARK: - BLE Devices

    @Test func bleDeviceMXMaster3S() {
        let device = DeviceRegistry.bleDevice(pid: 0xB034)
        #expect(device != nil)
        #expect(device!.name == "MX Master 3S")
        #expect(device!.type == .mouse)
    }

    @Test func bleDeviceMXKeysMini() {
        let device = DeviceRegistry.bleDevice(pid: 0xB369)
        #expect(device != nil)
        #expect(device!.name == "MX Keys Mini")
        #expect(device!.type == .keyboard)
    }

    @Test func bleDeviceUnknown() {
        #expect(DeviceRegistry.bleDevice(pid: 0x0000) == nil)
        #expect(DeviceRegistry.bleDevice(pid: 0xFFFF) == nil)
    }

    @Test func isBLEDevice() {
        #expect(DeviceRegistry.isBLEDevice(pid: 0xB034) == true)
        #expect(DeviceRegistry.isBLEDevice(pid: 0xB369) == true)
        #expect(DeviceRegistry.isBLEDevice(pid: 0x0000) == false)
    }

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
