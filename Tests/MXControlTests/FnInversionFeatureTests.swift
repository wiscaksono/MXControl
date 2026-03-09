import Testing
@testable import MXControl

@Suite("FnInversionFeature")
struct FnInversionFeatureTests {

    // MARK: - getState Classic

    @Test func getStateClassicInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x00,
                     params: [0x01] + [UInt8](repeating: 0, count: 15))

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV2
        )

        #expect(state.fnInverted == true)
        #expect(state.gKeyState == 0) // always 0 for classic
    }

    @Test func getStateClassicNotInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x00,
                     params: [0x00] + [UInt8](repeating: 0, count: 15))

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV0
        )

        #expect(state.fnInverted == false)
    }

    // MARK: - getState Enhanced (0x40A3)

    @Test func getStateEnhancedInverted() async throws {
        let mock = MockHIDTransport()
        // Response: [hostByte(skip), fnState=0x01, gKeyState=0x42]
        mock.respond(featureIndex: 0x08, functionId: 0x00,
                     params: [0xFF, 0x01, 0x42] + [UInt8](repeating: 0, count: 13))

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3
        )

        #expect(state.fnInverted == true)
        #expect(state.gKeyState == 0x42)

        // Verify the request sent 0xFF for current host
        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0xFF)
    }

    @Test func getStateEnhancedNotInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x00,
                     params: [0xFF, 0x00, 0x00] + [UInt8](repeating: 0, count: 13))

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3
        )

        #expect(state.fnInverted == false)
        #expect(state.gKeyState == 0x00)
    }

    // MARK: - setState Classic

    @Test func setStateClassicInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await FnInversionFeature.setState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV2,
            fnInverted: true
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x01)
    }

    @Test func setStateClassicNotInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await FnInversionFeature.setState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV0,
            fnInverted: false
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x00)
    }

    // MARK: - setState Enhanced

    @Test func setStateEnhancedInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await FnInversionFeature.setState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3,
            fnInverted: true, gKeyState: 0x42
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0xFF) // current host
        #expect(sent.params[1] == 0x01) // fnInverted = true
        #expect(sent.params[2] == 0x42) // gKeyState preserved
    }

    @Test func setStateEnhancedNotInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x08, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await FnInversionFeature.setState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3,
            fnInverted: false, gKeyState: 0x00
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0xFF)
        #expect(sent.params[1] == 0x00)
        #expect(sent.params[2] == 0x00)
    }

    // MARK: - Enhanced short params fallback (< 3 bytes)

    @Test func getStateEnhancedShortParams2Bytes() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: hostByte + fnState — gKeyState missing
        // params.count < 3 → guard triggers, returns FnState(false, 0)
        mock.respondShort(featureIndex: 0x08, functionId: 0x00,
                          params: [0xFF, 0x01])

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3
        )

        #expect(state.fnInverted == false)  // guard fallback
        #expect(state.gKeyState == 0)       // guard fallback
    }

    @Test func getStateEnhancedShortParams1Byte() async throws {
        let mock = MockHIDTransport()
        // Only 1 byte: hostByte only
        mock.respondShort(featureIndex: 0x08, functionId: 0x00,
                          params: [0xFF])

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3
        )

        #expect(state.fnInverted == false)  // guard fallback
        #expect(state.gKeyState == 0)       // guard fallback
    }

    @Test func getStateEnhancedEmptyParams() async throws {
        let mock = MockHIDTransport()
        mock.respondShort(featureIndex: 0x08, functionId: 0x00, params: [])

        let state = try await FnInversionFeature.getState(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x08,
            featureId: FnInversionFeature.featureIdV3
        )

        #expect(state.fnInverted == false)
        #expect(state.gKeyState == 0)
    }
}
