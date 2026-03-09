import Testing
@testable import MXControl

@Suite("AdjustableDPIFeature")
struct AdjustableDPIFeatureTests {

    // MARK: - getSensorCount

    @Test func getSensorCount() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x00, params: [0x01] + [UInt8](repeating: 0, count: 15))

        let count = try await AdjustableDPIFeature.getSensorCount(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )
        #expect(count == 1)
    }

    // MARK: - getSensorDPIList: Range

    @Test func getDPIListRange() async throws {
        let mock = MockHIDTransport()
        // Range: min=200, step=50 (with 0x2000 indicator), max=8000
        // min: 0x00C8, step: 0x2032 (50 | 0x2000), max: 0x1F40
        let params: [UInt8] = [
            0x00, 0xC8,   // min = 200
            0x20, 0x32,   // step = 50 | 0x2000
            0x1F, 0x40,   // max = 8000
            0x00, 0x00,   // terminator
        ] + [UInt8](repeating: 0, count: 8)

        mock.respond(featureIndex: 0x05, functionId: 0x01, params: params)

        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        if case .range(let min, let max, let step) = dpiList {
            #expect(min == 200)
            #expect(max == 8000)
            #expect(step == 50)
        } else {
            Issue.record("Expected .range but got .list")
        }
    }

    // MARK: - getSensorDPIList: List

    @Test func getDPIListDiscrete() async throws {
        let mock = MockHIDTransport()
        // Discrete list: 400, 800, 1600, 3200
        let params: [UInt8] = [
            0x01, 0x90,   // 400
            0x03, 0x20,   // 800
            0x06, 0x40,   // 1600
            0x0C, 0x80,   // 3200
            0x00, 0x00,   // terminator
        ] + [UInt8](repeating: 0, count: 6)

        mock.respond(featureIndex: 0x05, functionId: 0x01, params: params)

        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        if case .list(let values) = dpiList {
            #expect(values == [400, 800, 1600, 3200])
        } else {
            Issue.record("Expected .list but got .range")
        }
    }

    @Test func getDPIListEmpty() async throws {
        let mock = MockHIDTransport()
        // All zeros = empty
        let params = [UInt8](repeating: 0, count: 16)
        mock.respond(featureIndex: 0x05, functionId: 0x01, params: params)

        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        if case .list(let values) = dpiList {
            #expect(values.isEmpty)
        } else {
            Issue.record("Expected empty .list")
        }
    }

    @Test func getDPIListSingleValue() async throws {
        let mock = MockHIDTransport()
        // Single value, no step indicator
        let params: [UInt8] = [
            0x03, 0x20,   // 800
            0x00, 0x00,   // terminator
        ] + [UInt8](repeating: 0, count: 12)

        mock.respond(featureIndex: 0x05, functionId: 0x01, params: params)

        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        if case .list(let values) = dpiList {
            #expect(values == [800])
        } else {
            Issue.record("Expected .list with single value")
        }
    }

    @Test func getDPIListRangeWithStepIndicatorE000() async throws {
        let mock = MockHIDTransport()
        // Test with 0xE000 mask (higher bits set)
        let params: [UInt8] = [
            0x00, 0xC8,   // min = 200
            0xE0, 0x32,   // step = 50 | 0xE000
            0x1F, 0x40,   // max = 8000
            0x00, 0x00,
        ] + [UInt8](repeating: 0, count: 8)

        mock.respond(featureIndex: 0x05, functionId: 0x01, params: params)

        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        if case .range(let min, let max, let step) = dpiList {
            #expect(min == 200)
            #expect(max == 8000)
            #expect(step == 50)
        } else {
            Issue.record("Expected .range")
        }
    }

    // MARK: - getSensorDPI

    @Test func getSensorDPI() async throws {
        let mock = MockHIDTransport()
        // param[0]=sensorIndex, param[1-2]=currentDPI BE, param[3-4]=defaultDPI BE
        let params: [UInt8] = [
            0x00,         // sensor index echo
            0x03, 0x20,   // current DPI = 800
            0x04, 0xB0,   // default DPI = 1200
        ] + [UInt8](repeating: 0, count: 11)

        mock.respond(featureIndex: 0x05, functionId: 0x02, params: params)

        let info = try await AdjustableDPIFeature.getSensorDPI(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        #expect(info.currentDPI == 800)
        #expect(info.defaultDPI == 1200)
    }

    @Test func getSensorDPIShortResponse() async throws {
        let mock = MockHIDTransport()
        // Only 3 params (no default DPI) — should fallback to currentDPI
        let params: [UInt8] = [
            0x00,         // sensor index
            0x06, 0x40,   // current DPI = 1600
        ] + [UInt8](repeating: 0, count: 13)

        mock.respond(featureIndex: 0x05, functionId: 0x02, params: params)

        let info = try await AdjustableDPIFeature.getSensorDPI(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        #expect(info.currentDPI == 1600)
        // With zeros in params[3-4], defaultDPI = 0, not fallback
        // Actually looking at the code: params.count >= 5 is true (16 params from mock)
        // so it will parse params[3-4] = 0x00,0x00 = 0
        #expect(info.defaultDPI == 0)
    }

    // MARK: - setSensorDPI

    @Test func setSensorDPI() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await AdjustableDPIFeature.setSensorDPI(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05, dpi: 1600
        )

        #expect(mock.sendCount == 1)
        let sent = mock.sentRequests[0]
        #expect(sent.featureIndex == 0x05)
        #expect(sent.functionId == 0x03)
        #expect(sent.params[0] == 0x00) // sensor index
        #expect(sent.params[1] == 0x06) // 1600 >> 8
        #expect(sent.params[2] == 0x40) // 1600 & 0xFF
    }

    @Test func setSensorDPIHighValue() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await AdjustableDPIFeature.setSensorDPI(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05, dpi: 8000
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[1] == 0x1F) // 8000 >> 8 = 0x1F
        #expect(sent.params[2] == 0x40) // 8000 & 0xFF = 0x40
    }

    // MARK: - Short params fallback: defaultDPI = currentDPI

    @Test func getSensorDPIShortParamsFallbackToCurrentDPI() async throws {
        let mock = MockHIDTransport()
        // Only 3 bytes (sensorIndex + 2 bytes currentDPI) — params.count < 5
        // so defaultDPI should fallback to currentDPI
        mock.respondShort(featureIndex: 0x05, functionId: 0x02,
                          params: [0x00, 0x06, 0x40]) // sensor=0, currentDPI=1600

        let info = try await AdjustableDPIFeature.getSensorDPI(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        #expect(info.currentDPI == 1600)
        #expect(info.defaultDPI == 1600) // fallback: defaultDPI = currentDPI
    }

    @Test func getSensorDPIShortParams4BytesFallback() async throws {
        let mock = MockHIDTransport()
        // 4 bytes: sensorIndex + currentDPI(2) + partial defaultDPI(1) — still < 5
        mock.respondShort(featureIndex: 0x05, functionId: 0x02,
                          params: [0x00, 0x03, 0x20, 0x04]) // currentDPI=800

        let info = try await AdjustableDPIFeature.getSensorDPI(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        #expect(info.currentDPI == 800)
        #expect(info.defaultDPI == 800) // fallback: defaultDPI = currentDPI
    }

    // MARK: - DPI range step=0 edge case

    @Test func getDPIListRangeStepZeroClampedTo1() async throws {
        let mock = MockHIDTransport()
        // Range: min=400, step=0 (with 0x2000 indicator), max=3200
        // step=0 | 0x2000 = 0x2000. Code clamps step=0 to 1 to avoid div-by-zero.
        let params: [UInt8] = [
            0x01, 0x90,   // min = 400
            0x20, 0x00,   // step = 0 | 0x2000
            0x0C, 0x80,   // max = 3200
            0x00, 0x00,   // terminator
        ] + [UInt8](repeating: 0, count: 8)

        mock.respond(featureIndex: 0x05, functionId: 0x01, params: params)

        let dpiList = try await AdjustableDPIFeature.getSensorDPIList(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x05
        )

        if case .range(let min, let max, let step) = dpiList {
            #expect(min == 400)
            #expect(max == 3200)
            #expect(step == 1) // step=0 clamped to 1 by source code
        } else {
            Issue.record("Expected .range but got .list")
        }
    }
}
