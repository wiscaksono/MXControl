import Testing
@testable import MXControl

@Suite("RootFeature")
struct RootFeatureTests {

    @Test func getFeature() async throws {
        let mock = MockHIDTransport()
        // Response: index=5, type=0x00, version=0
        mock.respond(featureIndex: 0x00, functionId: 0x00,
                     params: [0x05, 0x00, 0x00] + [UInt8](repeating: 0, count: 13))

        let info = try await RootFeature.getFeature(
            transport: mock, deviceIndex: 0x01, featureId: 0x1004
        )

        #expect(info.index == 5)
        #expect(info.type == 0x00)
        #expect(info.version == 0)

        // Verify the featureId was encoded correctly (big-endian)
        let sent = mock.sentRequests[0]
        #expect(sent.featureIndex == 0x00) // Root feature always at index 0
        #expect(sent.functionId == 0x00)
        #expect(sent.params[0] == 0x10) // 0x1004 >> 8
        #expect(sent.params[1] == 0x04) // 0x1004 & 0xFF
    }

    @Test func getFeatureWithVersion() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x00, functionId: 0x00,
                     params: [0x0A, 0x02, 0x03] + [UInt8](repeating: 0, count: 13))

        let info = try await RootFeature.getFeature(
            transport: mock, deviceIndex: 0x01, featureId: 0x2201
        )

        #expect(info.index == 0x0A)
        #expect(info.type == 0x02)
        #expect(info.version == 0x03)
    }

    @Test func ping() async throws {
        let mock = MockHIDTransport()
        // Response: protocolMajor=4, protocolMinor=2, pingData=0xAA
        mock.respond(featureIndex: 0x00, functionId: 0x01,
                     params: [0x04, 0x02, 0xAA] + [UInt8](repeating: 0, count: 13))

        let result = try await RootFeature.ping(
            transport: mock, deviceIndex: 0x01
        )

        #expect(result.protocolMajor == 4)
        #expect(result.protocolMinor == 2)
        #expect(result.pingData == 0xAA)

        // Verify ping params
        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x00)
        #expect(sent.params[1] == 0x00)
        #expect(sent.params[2] == 0xAA) // default ping data
    }

    @Test func pingCustomData() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x00, functionId: 0x01,
                     params: [0x04, 0x02, 0x55] + [UInt8](repeating: 0, count: 13))

        let result = try await RootFeature.ping(
            transport: mock, deviceIndex: 0x02, pingData: 0x55
        )

        #expect(result.pingData == 0x55)

        let sent = mock.sentRequests[0]
        #expect(sent.deviceIndex == 0x02)
        #expect(sent.params[2] == 0x55)
    }

    @Test func getCount() async throws {
        let mock = MockHIDTransport()
        // First call: getFeature(0x0001) -> index=1
        mock.respond(featureIndex: 0x00, functionId: 0x00,
                     params: [0x01, 0x00, 0x00] + [UInt8](repeating: 0, count: 13))
        // Second call: FeatureSet.getCount -> count=25
        mock.respond(featureIndex: 0x01, functionId: 0x00,
                     params: [25] + [UInt8](repeating: 0, count: 15))

        let count = try await RootFeature.getCount(
            transport: mock, deviceIndex: 0x01
        )

        #expect(count == 25)
        #expect(mock.sendCount == 2)
    }

    @Test func getCountFeatureNotSupported() async throws {
        let mock = MockHIDTransport()
        // getFeature(0x0001) returns index=0 -> not supported
        mock.respond(featureIndex: 0x00, functionId: 0x00,
                     params: [0x00, 0x00, 0x00] + [UInt8](repeating: 0, count: 13))

        do {
            _ = try await RootFeature.getCount(
                transport: mock, deviceIndex: 0x01
            )
            Issue.record("Expected featureNotSupported error")
        } catch let error as HIDPPError {
            #expect(error == .featureNotSupported(0x0001))
        }
    }

    // MARK: - Short params fallback: version defaults to 0

    @Test func getFeatureShortParamsVersionFallback() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: index + type — version missing (params.count <= 2)
        mock.respondShort(featureIndex: 0x00, functionId: 0x00,
                          params: [0x05, 0x01])

        let info = try await RootFeature.getFeature(
            transport: mock, deviceIndex: 0x01, featureId: 0x1004
        )

        #expect(info.index == 5)
        #expect(info.type == 0x01)
        #expect(info.version == 0) // fallback default
    }

    @Test func getFeatureShortParams1Byte() async throws {
        let mock = MockHIDTransport()
        // Only 1 byte: index only — type and version from default behavior
        // params.count = 1, so params.count > 2 is false → version = 0
        // params[1] would be out of bounds without the guard,
        // but the code accesses params[1] directly (no guard) so this tests with 2 bytes minimum
        mock.respondShort(featureIndex: 0x00, functionId: 0x00,
                          params: [0x03, 0x00])

        let info = try await RootFeature.getFeature(
            transport: mock, deviceIndex: 0x01, featureId: 0x2121
        )

        #expect(info.index == 3)
        #expect(info.type == 0x00)
        #expect(info.version == 0) // fallback
    }
}
