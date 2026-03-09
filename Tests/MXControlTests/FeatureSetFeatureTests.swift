import Testing
@testable import MXControl

@Suite("FeatureSetFeature")
struct FeatureSetFeatureTests {

    @Test func getCount() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x01, functionId: 0x00,
                     params: [20] + [UInt8](repeating: 0, count: 15))

        let count = try await FeatureSetFeature.getCount(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x01
        )

        #expect(count == 20)
    }

    @Test func getFeatureId() async throws {
        let mock = MockHIDTransport()
        // featureId=0x1004, type=0x00
        mock.respond(featureIndex: 0x01, functionId: 0x01,
                     params: [0x10, 0x04, 0x00] + [UInt8](repeating: 0, count: 13))

        let result = try await FeatureSetFeature.getFeatureId(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x01, index: 2
        )

        #expect(result.featureId == 0x1004)
        #expect(result.type == 0x00)

        // Verify the index was sent
        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 2)
    }

    @Test func getFeatureIdHidden() async throws {
        let mock = MockHIDTransport()
        // Hidden feature: type bit 1 set
        mock.respond(featureIndex: 0x01, functionId: 0x01,
                     params: [0x1E, 0x00, 0x02] + [UInt8](repeating: 0, count: 13))

        let result = try await FeatureSetFeature.getFeatureId(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x01, index: 5
        )

        #expect(result.featureId == 0x1E00)
        #expect(result.type == 0x02)
    }

    // MARK: - Short params fallback

    @Test func getFeatureIdShortParams2Bytes() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: featureId — type missing (params.count <= 2)
        mock.respondShort(featureIndex: 0x01, functionId: 0x01,
                          params: [0x10, 0x04])

        let result = try await FeatureSetFeature.getFeatureId(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x01, index: 3
        )

        #expect(result.featureId == 0x1004)
        #expect(result.type == 0) // fallback: no flags
    }
}
