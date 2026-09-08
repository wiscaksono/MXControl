import Testing
import Foundation
@testable import MXControl
@testable import MXControlHIDPP

/// Tests for live battery InfoUpdate routing (event fn 0, same payload as
/// getStatus). The device pushes these when charge state changes; the row
/// must update without a reconnect or manual refresh.
@Suite("Battery Live Updates")
struct BatteryEventTests {

    @Test @MainActor func infoEventUpdatesBatteryState() {
        let fixture = DeviceFixture.make()
        defer { _ = fixture }
        let device = fixture.device
        device.batteryFeatureIndex = 0x04
        device.battery.level = 50

        // SoC=90, level=full(8), charging(1)
        device.handleNotification(featureIndex: 0x04, functionId: 0x00, params: [90, 0x08, 0x01])

        #expect(device.battery.level == 90)
        #expect(device.battery.charging == true)
    }

    @Test @MainActor func wrongIndexIgnored() {
        let fixture = DeviceFixture.make()
        defer { _ = fixture }
        let device = fixture.device
        device.batteryFeatureIndex = 0x04
        device.battery.level = 50

        device.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [90, 0x08, 0x01])

        #expect(device.battery.level == 50)
    }

    @Test @MainActor func truncatedEventIgnoredSilently() {
        let fixture = DeviceFixture.make()
        defer { _ = fixture }
        let device = fixture.device
        device.batteryFeatureIndex = 0x04
        device.battery.level = 50

        // Too short to parse: must not crash, must not change state.
        device.handleNotification(featureIndex: 0x04, functionId: 0x00, params: [90])

        #expect(device.battery.level == 50)
    }

    @Test @MainActor func noIndexConfiguredIgnoresEverything() {
        let fixture = DeviceFixture.make()
        defer { _ = fixture }
        let device = fixture.device
        device.battery.level = 50

        device.handleNotification(featureIndex: 0x04, functionId: 0x00, params: [90, 0x08, 0x01])

        #expect(device.battery.level == 50)
    }
}
