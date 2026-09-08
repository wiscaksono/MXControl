import Testing
@testable import MXControlHIDPP

/// Tests for the original SmartShift variant (0x2110), per OpenLogi
/// `0x2110 smartShift`: fn 0 reads `[mode, ad, adDefault]`, fn 1 writes
/// `[mode, ad, adDefault]` with absent fields as 0 (no change).
@Suite("SmartShiftV1Feature")
struct SmartShiftV1FeatureTests {

    @Test func getStatus() async throws {
        let mock = MockHIDTransport()
        // mode=2(ratchet), autoDisengage=30, default=25
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x02, 30, 25] + [UInt8](repeating: 0, count: 13))

        let status = try await SmartShiftV1Feature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        #expect(status.wheelMode == .ratchet)
        #expect(status.autoDisengage == 30)
        #expect(status.autoDisengageDefault == 25)
    }

    @Test func getStatusFreeSpin() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x01, 0xFF, 0xFF] + [UInt8](repeating: 0, count: 13))

        let status = try await SmartShiftV1Feature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        #expect(status.wheelMode == .freeSpin)
        #expect(status.autoDisengage == 0xFF)
    }

    @Test func setStatusAll() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await SmartShiftV1Feature.setStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05,
            wheelMode: .freeSpin, autoDisengage: 30, autoDisengageDefault: 25
        )

        let sent = mock.sentRequests[0]
        #expect(sent.functionId == 0x01)
        #expect(sent.params[0] == 0x01) // freeSpin
        #expect(sent.params[1] == 30)
        #expect(sent.params[2] == 25)
        #expect(sent.params.count == 3)
    }

    @Test func setStatusNoChange() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await SmartShiftV1Feature.setStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05,
            wheelMode: nil, autoDisengage: nil, autoDisengageDefault: nil
        )

        #expect(mock.sentRequests[0].params == [0x00, 0x00, 0x00])
    }
}
