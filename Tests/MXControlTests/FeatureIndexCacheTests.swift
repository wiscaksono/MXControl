import Testing
@testable import MXControl

@Suite("FeatureIndexCache")
struct FeatureIndexCacheTests {

    @Test func getSetBasic() async {
        let cache = FeatureIndexCache()
        let result1 = await cache.get(0x1004)
        #expect(result1 == nil)

        await cache.set(0x1004, index: 5)
        let result2 = await cache.get(0x1004)
        #expect(result2 == 5)
    }

    @Test func setAll() async {
        let cache = FeatureIndexCache()
        await cache.setAll([
            (featureId: 0x1004, index: 5),
            (featureId: 0x2201, index: 10),
            (featureId: 0x2111, index: 7),
        ])

        #expect(await cache.get(0x1004) == 5)
        #expect(await cache.get(0x2201) == 10)
        #expect(await cache.get(0x2111) == 7)
    }

    @Test func clear() async {
        let cache = FeatureIndexCache()
        await cache.set(0x1004, index: 5)
        await cache.set(0x2201, index: 10)

        await cache.clear()

        #expect(await cache.get(0x1004) == nil)
        #expect(await cache.get(0x2201) == nil)
        #expect(await cache.all.isEmpty)
    }

    @Test func allEntries() async {
        let cache = FeatureIndexCache()
        await cache.set(0x1004, index: 5)
        await cache.set(0x2201, index: 10)

        let all = await cache.all
        #expect(all.count == 2)
        #expect(all[0x1004] == 5)
        #expect(all[0x2201] == 10)
    }

    @Test func transferFrom() async {
        let source = FeatureIndexCache()
        await source.set(0x1004, index: 5)
        await source.set(0x2201, index: 10)

        let target = FeatureIndexCache()
        await target.set(0x0001, index: 1) // existing entry

        await target.transferFrom(source)

        #expect(await target.get(0x1004) == 5)
        #expect(await target.get(0x2201) == 10)
        #expect(await target.get(0x0001) == 1) // preserved
    }

    @Test func overwriteExisting() async {
        let cache = FeatureIndexCache()
        await cache.set(0x1004, index: 5)
        await cache.set(0x1004, index: 8)

        #expect(await cache.get(0x1004) == 8)
    }

    // MARK: - resolve with mock transport

    @Test func resolveCacheHit() async throws {
        let cache = FeatureIndexCache()
        await cache.set(0x1004, index: 5)

        let mock = MockHIDTransport()
        // Should NOT hit the transport — cached
        let index = try await cache.resolve(
            featureId: 0x1004, transport: mock, deviceIndex: 0x01
        )

        #expect(index == 5)
        #expect(mock.sendCount == 0) // no transport call
    }

    @Test func resolveCacheMiss() async throws {
        let cache = FeatureIndexCache()
        let mock = MockHIDTransport()

        // RootFeature.getFeature will send to featureIndex=0x00, functionId=0x00
        // Response: index=7, type=0, version=0
        mock.respond(featureIndex: 0x00, functionId: 0x00,
                     params: [0x07, 0x00, 0x00] + [UInt8](repeating: 0, count: 13))

        let index = try await cache.resolve(
            featureId: 0x1004, transport: mock, deviceIndex: 0x01
        )

        #expect(index == 7)
        #expect(mock.sendCount == 1)

        // Should be cached now
        #expect(await cache.get(0x1004) == 7)
    }

    @Test func resolveFeatureNotSupported() async throws {
        let cache = FeatureIndexCache()
        let mock = MockHIDTransport()

        // Device returns index=0 -> feature not supported
        mock.respond(featureIndex: 0x00, functionId: 0x00,
                     params: [0x00, 0x00, 0x00] + [UInt8](repeating: 0, count: 13))

        do {
            _ = try await cache.resolve(
                featureId: 0xABCD, transport: mock, deviceIndex: 0x01
            )
            Issue.record("Expected featureNotSupported error")
        } catch let error as HIDPPError {
            #expect(error == .featureNotSupported(0xABCD))
        }

        // Should NOT be cached
        #expect(await cache.get(0xABCD) == nil)
    }
}
