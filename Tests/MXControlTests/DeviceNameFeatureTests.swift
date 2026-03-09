import Testing
@testable import MXControl

@Suite("DeviceNameFeature")
struct DeviceNameFeatureTests {

    @Test func getNameLength() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x03, functionId: 0x00,
                     params: [14] + [UInt8](repeating: 0, count: 15))

        let length = try await DeviceNameFeature.getNameLength(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03
        )

        #expect(length == 14)
    }

    @Test func getNameChunk() async throws {
        let mock = MockHIDTransport()
        let nameBytes: [UInt8] = Array("MX Master 3S".utf8)
        let params = nameBytes + [UInt8](repeating: 0, count: 16 - nameBytes.count)
        mock.respond(featureIndex: 0x03, functionId: 0x01, params: params)

        let chunk = try await DeviceNameFeature.getNameChunk(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03, offset: 0
        )

        #expect(chunk == "MX Master 3S")
    }

    @Test func getNameChunkNullTerminated() async throws {
        let mock = MockHIDTransport()
        // "MX" followed by null bytes
        let params: [UInt8] = [0x4D, 0x58, 0x00] + [UInt8](repeating: 0, count: 13)
        mock.respond(featureIndex: 0x03, functionId: 0x01, params: params)

        let chunk = try await DeviceNameFeature.getNameChunk(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03, offset: 0
        )

        #expect(chunk == "MX")
    }

    @Test func getType() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x03, functionId: 0x02,
                     params: [0x03] + [UInt8](repeating: 0, count: 15)) // mouse = 3

        let kind = try await DeviceNameFeature.getType(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03
        )

        #expect(kind == .mouse)
    }

    @Test func getTypeUnknown() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x03, functionId: 0x02,
                     params: [0x20] + [UInt8](repeating: 0, count: 15)) // unknown raw value

        let kind = try await DeviceNameFeature.getType(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03
        )

        #expect(kind == .unknown)
    }

    @Test func getFullNameSingleChunk() async throws {
        let mock = MockHIDTransport()
        let name = "MX Master 3S"

        // getNameLength -> 12
        mock.respond(featureIndex: 0x03, functionId: 0x00,
                     params: [UInt8(name.count)] + [UInt8](repeating: 0, count: 15))
        // getNameChunk(offset=0) -> full name
        let nameBytes = Array(name.utf8)
        mock.respond(featureIndex: 0x03, functionId: 0x01,
                     params: nameBytes + [UInt8](repeating: 0, count: 16 - nameBytes.count))

        let result = try await DeviceNameFeature.getFullName(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03
        )

        #expect(result == "MX Master 3S")
    }

    @Test func getFullNameMultiChunk() async throws {
        let mock = MockHIDTransport()
        let name = "Logitech MX Keys Mini Wireless"

        // getNameLength -> 30
        mock.respond(featureIndex: 0x03, functionId: 0x00,
                     params: [UInt8(name.count)] + [UInt8](repeating: 0, count: 15))

        // First chunk: first 16 chars
        let chunk1 = Array("Logitech MX Keys".utf8)
        mock.respond(featureIndex: 0x03, functionId: 0x01,
                     params: chunk1 + [UInt8](repeating: 0, count: 16 - chunk1.count))

        // Second chunk: remaining " Mini Wireless" (14 chars)
        let chunk2 = Array(" Mini Wireless".utf8)
        mock.respond(featureIndex: 0x03, functionId: 0x01,
                     params: chunk2 + [UInt8](repeating: 0, count: 16 - chunk2.count))

        let result = try await DeviceNameFeature.getFullName(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03
        )

        #expect(result == name)
    }

    @Test func getFullNameEmptyChunkStops() async throws {
        let mock = MockHIDTransport()

        // getNameLength -> 20
        mock.respond(featureIndex: 0x03, functionId: 0x00,
                     params: [20] + [UInt8](repeating: 0, count: 15))

        // First chunk: some name
        let chunk1 = Array("Test".utf8)
        mock.respond(featureIndex: 0x03, functionId: 0x01,
                     params: chunk1 + [UInt8](repeating: 0, count: 16 - chunk1.count))

        // Second chunk: empty (all nulls)
        mock.respond(featureIndex: 0x03, functionId: 0x01,
                     params: [UInt8](repeating: 0, count: 16))

        let result = try await DeviceNameFeature.getFullName(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x03
        )

        // Should stop at "Test" because second chunk is empty
        #expect(result == "Test")
    }
}
