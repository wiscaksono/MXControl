import Foundation
import Testing
@testable import DeviceCore
@testable import HIDPP

/// Wire-format regressions that the UI layer cannot catch on its own.
@Suite("Capability Handlers")
@MainActor
struct CapabilityHandlersTests {

    @Test func smartShiftToggleKeepsAutoDisengage() async throws {
        let fixture = DeviceFixture.make(descriptor: DeviceDescriptors.mxMaster3S)
        let device = fixture.device
        let transport = fixture.transport

        device.features = [
            FeatureSetFeature.FeatureEntry(
                featureId: SmartShiftFeature.featureId,
                index: 0x07,
                type: 0
            ),
        ]

        let padding = [UInt8](repeating: 0, count: 13)
        // Root.getFeature → SmartShift lives at index 0x07.
        transport.respond(featureIndex: 0x00, functionId: 0x00, params: [0x07] + padding)
        // Capabilities: tunable torque, default auto-disengage 25, max force 100.
        transport.respond(featureIndex: 0x07, functionId: 0x00, params: [0x01, 25, 50, 100] + padding)
        // Status: ratchet, auto-disengage 25, torque 50.
        transport.respond(featureIndex: 0x07, functionId: 0x01, params: [0x02, 25, 50] + padding)
        // Set echo carries the resulting state.
        transport.respond(featureIndex: 0x07, functionId: 0x02, params: [0x02, 25, 50] + padding)

        CapabilityHandlers.createStates(for: device.descriptor.capabilities, on: device)

        // A saved force of 90 used to be written into auto-disengage too.
        SettingsStore.saveValue(90, CapabilityID.smartShiftTorque, scope: device.settingScope)
        SettingsStore.saveValue(true, CapabilityID.smartShiftActive, scope: device.settingScope)
        defer { SettingsStore.clearSettings(for: device.settingScope) }

        await CapabilityHandlers.load(.smartShiftActive, on: device)

        let write = try #require(
            transport.sent.first { $0.featureIndex == 0x07 && $0.functionId == 0x02 }
        )
        #expect(write.params[1] == 25)
        #expect(write.params[2] == 90)
    }

    @Test func hiResLoadPreservesFirmwareBytesOnReconnect() async throws {
        let fixture = DeviceFixture.make(descriptor: DeviceDescriptors.mxMaster3S)
        let device = fixture.device
        let transport = fixture.transport

        device.features = [
            FeatureSetFeature.FeatureEntry(
                featureId: HiResScrollFeature.featureId,
                index: 0x0A,
                type: 0
            ),
        ]

        let padding = [UInt8](repeating: 0, count: 13)
        transport.respond(featureIndex: 0x00, functionId: 0x00, params: [0x0A] + padding)
        transport.respond(featureIndex: 0x0A, functionId: 0x00, params: [15, 0x0C, 0, 0] + padding)
        transport.respond(featureIndex: 0x0A, functionId: 0x01, params: [0x02, 0xAB, 0xCD] + padding)
        transport.respond(featureIndex: 0x0A, functionId: 0x02, params: [0x02, 0xAB, 0xCD] + padding)

        // A saved direction preference triggers the write on reconnect.
        SettingsStore.saveValue(true, CapabilityID.hiResInverted, scope: device.settingScope)
        defer { SettingsStore.clearSettings(for: device.settingScope) }

        await device.scrollBehavior?.load()

        let write = try #require(
            transport.sent.first { $0.featureIndex == 0x0A && $0.functionId == 0x02 }
        )
        // HID path stays neutral (hiRes only); direction is applied when the
        // wheel is diverted in smooth mode.
        #expect(write.params == [0x02, 0xAB, 0xCD])
    }

    @Test func smartShiftWriteUsesCachedThresholdWhenDisabling() async throws {
        let fixture = DeviceFixture.make(descriptor: DeviceDescriptors.mxMaster3S)
        let device = fixture.device
        let transport = fixture.transport

        device.features = [
            FeatureSetFeature.FeatureEntry(
                featureId: SmartShiftFeature.featureId,
                index: 0x07,
                type: 0
            ),
        ]
        let padding = [UInt8](repeating: 0, count: 13)
        transport.respond(featureIndex: 0x00, functionId: 0x00, params: [0x07] + padding)
        transport.respond(featureIndex: 0x07, functionId: 0x02, params: [0x02, 25, 50] + padding)

        CapabilityHandlers.createStates(for: device.descriptor.capabilities, on: device)
        device.smartShiftFid = SmartShiftFeature.featureId
        device.smartShiftFeatureIndex = 0x07
        await device.featureIndexCache.set(0x2111, index: 0x07)
        device.toggles[CapabilityID.smartShiftActive]?.value = false
        device.smartShiftAutoDisengage = 42

        await CapabilityHandlers.commit(.smartShiftActive, on: device)

        let write = try #require(
            transport.sent.first { $0.featureIndex == 0x07 && $0.functionId == 0x02 }
        )
        #expect(write.params[1] == 0xFF)
    }
}
