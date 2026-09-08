import Testing
@testable import MXControlHIDPP

@Suite("BatteryFeature")
struct BatteryFeatureTests {

    @Test func getCapabilities() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x04, functionId: 0x00,
                     params: [0x0F, 0x03] + [UInt8](repeating: 0, count: 14))

        let caps = try await BatteryFeature.getCapabilities(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(caps.supportedLevels == 0x0F)
        #expect(caps.flags == 0x03)
        #expect(caps.hasSoC == true)
        #expect(caps.isRechargeable == true)
    }

    @Test func getCapabilitiesNotRechargeable() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x04, functionId: 0x00,
                     params: [0x0F, 0x00] + [UInt8](repeating: 0, count: 14))

        let caps = try await BatteryFeature.getCapabilities(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(caps.hasSoC == false)
        #expect(caps.isRechargeable == false)
    }

    @Test func getStatusCharging() async throws {
        let mock = MockHIDTransport()
        // SoC=75, level=good(4), charging(1)
        mock.respond(featureIndex: 0x04, functionId: 0x01,
                     params: [75, 0x04, 0x01] + [UInt8](repeating: 0, count: 13))

        let status = try await BatteryFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(status.level == 75)
        #expect(status.batteryLevel == .good)
        #expect(status.chargingStatus == .charging)
    }

    @Test func getStatusDischarging() async throws {
        let mock = MockHIDTransport()
        // SoC=100, level=full(8), discharging(0)
        mock.respond(featureIndex: 0x04, functionId: 0x01,
                     params: [100, 0x08, 0x00] + [UInt8](repeating: 0, count: 13))

        let status = try await BatteryFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(status.level == 100)
        #expect(status.batteryLevel == .full)
        #expect(status.chargingStatus == .discharging)
    }

    @Test func getStatusZeroSoC() async throws {
        let mock = MockHIDTransport()
        // SoC=0, level=critical(1), discharging(0)
        mock.respond(featureIndex: 0x04, functionId: 0x01,
                     params: [0, 0x01, 0x00] + [UInt8](repeating: 0, count: 13))

        let status = try await BatteryFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(status.level == 0)
        #expect(status.batteryLevel == .critical)
    }

    @Test func getStatusUnknownEnumFallback() async throws {
        let mock = MockHIDTransport()
        // Unknown battery level (0x0A) and charging status (0x0A) -> fallbacks
        mock.respond(featureIndex: 0x04, functionId: 0x01,
                     params: [50, 0x0A, 0x0A] + [UInt8](repeating: 0, count: 13))

        let status = try await BatteryFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(status.batteryLevel == .good) // fallback
        #expect(status.chargingStatus == .discharging) // fallback
    }

    // MARK: - SoC boundary

    @Test func getStatusLow() async throws {
        let mock = MockHIDTransport()
        // SoC=15, level=low(2), discharging(0)
        mock.respond(featureIndex: 0x04, functionId: 0x01,
                     params: [15, 0x02, 0x00] + [UInt8](repeating: 0, count: 13))

        let status = try await BatteryFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x04
        )

        #expect(status.level == 15)
        #expect(status.batteryLevel == .low)
        #expect(status.chargingStatus == .discharging)
    }

    @Test func parseInfoTruncatedThrows() async throws {
        await #expect(throws: (any Error).self) {
            try BatteryFeature.parseInfo(params: [50, 0x04])
        }
    }
}
