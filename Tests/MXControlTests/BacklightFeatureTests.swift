import Testing
@testable import MXControl

@Suite("BacklightFeature")
struct BacklightFeatureTests {

    // MARK: - getBacklightConfig V2

    @Test func getBacklightConfigV2() async throws {
        let mock = MockHIDTransport()
        // V2 response: enabled=1, options=0x18 (mode=3=manual, low bits=0),
        // supported=0x38, effects=0x0000, level=5,
        // dho=0x003C(LE=60), dhi=0x0078(LE=120), dpow=0x00B4(LE=180)
        let params: [UInt8] = [
            0x01,       // enabled
            0x18,       // options: mode=3(manual) << 3 = 0x18
            0x38,       // supported
            0x00, 0x00, // effects (LE)
            0x05,       // level = 5
            0x3C, 0x00, // dho = 60 (LE)
            0x78, 0x00, // dhi = 120 (LE)
            0xB4, 0x00, // dpow = 180 (LE)
        ] + [UInt8](repeating: 0, count: 4)

        mock.respond(featureIndex: 0x07, functionId: 0x00, params: params)

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.enabled == true)
        #expect(config.mode == .manual)
        #expect(config.level == 5)
        #expect(config.supported == 0x38)
        #expect(config.dho == 60)
        #expect(config.dhi == 120)
        #expect(config.dpow == 180)
    }

    @Test func getBacklightConfigV2AutoMode() async throws {
        let mock = MockHIDTransport()
        // mode=1(auto) << 3 = 0x08
        let params: [UInt8] = [
            0x01, 0x08, 0x38, 0x00, 0x00, 0x03,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ] + [UInt8](repeating: 0, count: 4)

        mock.respond(featureIndex: 0x07, functionId: 0x00, params: params)

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.mode == .automatic)
        #expect(config.level == 3)
    }

    @Test func getBacklightConfigV2Disabled() async throws {
        let mock = MockHIDTransport()
        // enabled=0, mode=0(off)
        let params: [UInt8] = [
            0x00, 0x00, 0x38, 0x00, 0x00, 0x00,
        ] + [UInt8](repeating: 0, count: 10)

        mock.respond(featureIndex: 0x07, functionId: 0x00, params: params)

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.enabled == false)
        #expect(config.mode == .off)
    }

    // MARK: - getBacklightConfig V3

    @Test func getBacklightConfigV3() async throws {
        let mock = MockHIDTransport()
        // V3: param[0]=mode(non-zero=enabled), param[1]=level
        mock.respond(featureIndex: 0x07, functionId: 0x00,
                     params: [0x01, 0x06] + [UInt8](repeating: 0, count: 14))

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV3
        )

        #expect(config.enabled == true)
        #expect(config.level == 6)
        #expect(config.mode == .manual)
    }

    @Test func getBacklightConfigV3Disabled() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x07, functionId: 0x00,
                     params: [0x00, 0x00] + [UInt8](repeating: 0, count: 14))

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV3
        )

        #expect(config.enabled == false)
        #expect(config.mode == .off)
    }

    // MARK: - setBacklightConfig V2

    @Test func setBacklightV2Manual() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x07, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await BacklightFeature.setBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2,
            enabled: true, mode: .manual, level: 5,
            currentOptions: 0x05, // preserve low 3 bits = 0x05
            dho: 60, dhi: 120, dpow: 180
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x01) // enabled
        // options = (0x05 & 0x07) | (3 << 3) = 0x05 | 0x18 = 0x1D
        #expect(sent.params[1] == 0x1D)
        #expect(sent.params[2] == 0xFF) // effect = no change
        #expect(sent.params[3] == 5)    // level
        #expect(sent.params[4] == 60)   // dho low byte
        #expect(sent.params[5] == 0)    // dho high byte
        #expect(sent.params[6] == 120)  // dhi low byte
        #expect(sent.params[7] == 0)    // dhi high byte
        #expect(sent.params[8] == 180)  // dpow low byte
        #expect(sent.params[9] == 0)    // dpow high byte
    }

    @Test func setBacklightV2AutoMode() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x07, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await BacklightFeature.setBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2,
            enabled: true, mode: .automatic, level: 5,
            currentOptions: 0x00, dho: 0, dhi: 0, dpow: 0
        )

        let sent = mock.sentRequests[0]
        // options = (0x00 & 0x07) | (1 << 3) = 0x08
        #expect(sent.params[1] == 0x08)
        // In auto mode, level should be 0 (not manual level)
        #expect(sent.params[3] == 0)
    }

    // MARK: - setBacklightConfig V3

    @Test func setBacklightV3() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x07, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await BacklightFeature.setBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV3,
            enabled: true, mode: .manual, level: 7,
            currentOptions: 0, dho: 0, dhi: 0, dpow: 0
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x01) // enabled
        #expect(sent.params[1] == 7)    // level
    }

    @Test func setBacklightV3Disabled() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x07, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await BacklightFeature.setBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV3,
            enabled: false, mode: .off, level: 0,
            currentOptions: 0, dho: 0, dhi: 0, dpow: 0
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x00) // disabled
        #expect(sent.params[1] == 0)
    }

    // MARK: - getBacklightLevelCount

    @Test func getBacklightLevelCount() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x07, functionId: 0x02,
                     params: [0x09] + [UInt8](repeating: 0, count: 15))

        let count = try await BacklightFeature.getBacklightLevelCount(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07
        )

        #expect(count == 9) // 9 levels (0-8)
    }

    // MARK: - V2 Short params fallback

    @Test func getBacklightConfigV2EmptyParams() async throws {
        let mock = MockHIDTransport()
        // Empty params — all fields fallback to 0
        mock.respondShort(featureIndex: 0x07, functionId: 0x00, params: [])

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.enabled == false)  // 0 != 0 is false
        #expect(config.options == 0)
        #expect(config.supported == 0)
        #expect(config.mode == .off)
        #expect(config.level == 0)
        #expect(config.dho == 0)
        #expect(config.dhi == 0)
        #expect(config.dpow == 0)
    }

    @Test func getBacklightConfigV2ShortParams6Bytes() async throws {
        let mock = MockHIDTransport()
        // 6 bytes: enabled + options + supported + effects(2) + level
        // Missing: dho, dhi, dpow → all fallback to 0
        mock.respondShort(featureIndex: 0x07, functionId: 0x00,
                          params: [0x01, 0x18, 0x38, 0x00, 0x00, 0x07])

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.enabled == true)
        #expect(config.mode == .manual)  // (0x18 >> 3) & 0x03 = 3
        #expect(config.level == 7)
        #expect(config.dho == 0)   // fallback
        #expect(config.dhi == 0)   // fallback
        #expect(config.dpow == 0)  // fallback
    }

    @Test func getBacklightConfigV2TemporaryMode() async throws {
        let mock = MockHIDTransport()
        // mode=2(temporary) << 3 = 0x10
        let params: [UInt8] = [
            0x01, 0x10, 0x38, 0x00, 0x00, 0x03,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ] + [UInt8](repeating: 0, count: 4)

        mock.respond(featureIndex: 0x07, functionId: 0x00, params: params)

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.mode == .temporary)
    }

    @Test func getBacklightConfigV2LEValuesAbove255() async throws {
        let mock = MockHIDTransport()
        // Test LE uint16 values > 255
        // dho=300 (LE: 0x2C, 0x01), dhi=500 (LE: 0xF4, 0x01), dpow=1000 (LE: 0xE8, 0x03)
        let params: [UInt8] = [
            0x01, 0x18, 0x38, 0x00, 0x00, 0x05,
            0x2C, 0x01,  // dho = 300 LE
            0xF4, 0x01,  // dhi = 500 LE
            0xE8, 0x03,  // dpow = 1000 LE
        ] + [UInt8](repeating: 0, count: 4)

        mock.respond(featureIndex: 0x07, functionId: 0x00, params: params)

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV2
        )

        #expect(config.dho == 300)
        #expect(config.dhi == 500)
        #expect(config.dpow == 1000)
    }

    // MARK: - V3 Short params fallback

    @Test func getBacklightConfigV3EmptyParams() async throws {
        let mock = MockHIDTransport()
        mock.respondShort(featureIndex: 0x07, functionId: 0x00, params: [])

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV3
        )

        #expect(config.enabled == false) // fallback
        #expect(config.level == 0)       // fallback
        #expect(config.mode == .off)
    }

    @Test func getBacklightConfigV3ShortParams1Byte() async throws {
        let mock = MockHIDTransport()
        // Only enabled byte, no level
        mock.respondShort(featureIndex: 0x07, functionId: 0x00, params: [0x01])

        let config = try await BacklightFeature.getBacklightConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x07,
            featureId: BacklightFeature.featureIdV3
        )

        #expect(config.enabled == true)
        #expect(config.level == 0)  // fallback
        #expect(config.mode == .manual)
    }
}
