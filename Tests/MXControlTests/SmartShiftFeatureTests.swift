import Testing
@testable import MXControl

@Suite("SmartShiftFeature")
struct SmartShiftFeatureTests {

    @Test func getCapabilities() async throws {
        let mock = MockHIDTransport()
        // flags=0x01 (tunable torque), autoDisDefault=30, defaultTorque=50, maxForce=100
        mock.respond(featureIndex: 0x06, functionId: 0x00,
                     params: [0x01, 30, 50, 100] + [UInt8](repeating: 0, count: 12))

        let caps = try await SmartShiftFeature.getCapabilities(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(caps.hasTunableTorque == true)
        #expect(caps.autoDisengageDefault == 30)
        #expect(caps.defaultTunableTorque == 50)
        #expect(caps.maxForce == 100)
    }

    @Test func getCapabilitiesNoTorque() async throws {
        let mock = MockHIDTransport()
        // Mock pads to 16 bytes, so params[2] and params[3] are 0.
        // The code reads them as Int(params[2]) = 0 and Int(params[3]) = 0.
        // Defaults only apply if params.count <= 2 / <= 3.
        mock.respond(featureIndex: 0x06, functionId: 0x00,
                     params: [0x00, 20] + [UInt8](repeating: 0, count: 14))

        let caps = try await SmartShiftFeature.getCapabilities(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(caps.hasTunableTorque == false)
        #expect(caps.autoDisengageDefault == 20)
        #expect(caps.defaultTunableTorque == 0) // params[2] = 0 (mock pads zeros)
        #expect(caps.maxForce == 0) // params[3] = 0 (mock pads zeros)
    }

    @Test func getStatusRatchet() async throws {
        let mock = MockHIDTransport()
        // mode=2(ratchet), autoDisengage=30, autoDisDefault=25, torque=60
        mock.respond(featureIndex: 0x06, functionId: 0x01,
                     params: [0x02, 30, 25, 60] + [UInt8](repeating: 0, count: 12))

        let status = try await SmartShiftFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(status.wheelMode == .ratchet)
        #expect(status.autoDisengage == 30)
        #expect(status.autoDisengageDefault == 25)
        #expect(status.torque == 60)
    }

    @Test func getStatusFreeSpin() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x06, functionId: 0x01,
                     params: [0x01, 0, 0, 40] + [UInt8](repeating: 0, count: 12))

        let status = try await SmartShiftFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(status.wheelMode == .freeSpin)
        #expect(status.autoDisengage == 0)
    }

    @Test func getStatusUnknownModeFallback() async throws {
        let mock = MockHIDTransport()
        // Unknown mode value 0x05 -> fallback to .ratchet
        mock.respond(featureIndex: 0x06, functionId: 0x01,
                     params: [0x05, 30, 25, 60] + [UInt8](repeating: 0, count: 12))

        let status = try await SmartShiftFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(status.wheelMode == .ratchet)
    }

    // MARK: - setStatus

    @Test func setStatusAll() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x06, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await SmartShiftFeature.setStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06,
            wheelMode: .freeSpin, autoDisengage: 30, torque: 50
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x01) // freeSpin
        #expect(sent.params[1] == 30)   // autoDisengage
        #expect(sent.params[2] == 0xFF) // autoDisDefault = no change
        #expect(sent.params[3] == 50)   // torque
    }

    @Test func setStatusNoChange() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x06, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        // All nil = no change
        try await SmartShiftFeature.setStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06,
            wheelMode: nil, autoDisengage: nil, torque: nil
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x00) // wheelMode nil -> 0 (no change)
        #expect(sent.params[1] == 0xFF) // autoDisengage nil -> 0xFF (no change)
        #expect(sent.params[3] == 0x00) // torque nil -> 0 (no change)
    }

    // MARK: - Short params fallback branches

    @Test func getCapabilitiesShortParams2Bytes() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: flags + autoDisengage — params[2] and params[3] missing
        mock.respondShort(featureIndex: 0x06, functionId: 0x00, params: [0x01, 30])

        let caps = try await SmartShiftFeature.getCapabilities(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(caps.hasTunableTorque == true)
        #expect(caps.autoDisengageDefault == 30)
        #expect(caps.defaultTunableTorque == 50) // fallback default
        #expect(caps.maxForce == 100) // fallback default
    }

    @Test func getCapabilitiesShortParams3Bytes() async throws {
        let mock = MockHIDTransport()
        // 3 bytes: flags + autoDisengage + torque — params[3] missing
        mock.respondShort(featureIndex: 0x06, functionId: 0x00, params: [0x01, 30, 60])

        let caps = try await SmartShiftFeature.getCapabilities(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(caps.defaultTunableTorque == 60)
        #expect(caps.maxForce == 100) // fallback default
    }

    @Test func getStatusShortParams2Bytes() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: mode + autoDisengage — autoDisDefault and torque missing
        mock.respondShort(featureIndex: 0x06, functionId: 0x01, params: [0x02, 30])

        let status = try await SmartShiftFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(status.wheelMode == .ratchet)
        #expect(status.autoDisengage == 30)
        #expect(status.autoDisengageDefault == 0) // fallback
        #expect(status.torque == 50) // fallback default
    }

    @Test func getStatusShortParams3Bytes() async throws {
        let mock = MockHIDTransport()
        // 3 bytes: mode + autoDisengage + autoDisDefault — torque missing
        mock.respondShort(featureIndex: 0x06, functionId: 0x01, params: [0x01, 0, 25])

        let status = try await SmartShiftFeature.getStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06
        )

        #expect(status.autoDisengageDefault == 25)
        #expect(status.torque == 50) // fallback default
    }

    @Test func setStatusOnlyWheelMode() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x06, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await SmartShiftFeature.setStatus(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x06,
            wheelMode: .ratchet
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x02) // ratchet
        #expect(sent.params[1] == 0xFF) // no change
        #expect(sent.params[3] == 0x00) // no change
    }
}
