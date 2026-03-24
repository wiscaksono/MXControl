import Testing
@testable import MXControl

// MARK: - HiResScrollFeature Tests

@Suite("HiResScrollFeature")
struct HiResScrollFeatureTests {

    @Test func getWheelCapability() async throws {
        let mock = MockHIDTransport()
        // multiplier=8, flags=0x0C (hasRatchet=bit3, hasInvert=bit2)
        mock.respond(featureIndex: 0x0A, functionId: 0x00,
                     params: [0x08, 0x0C] + [UInt8](repeating: 0, count: 14))

        let cap = try await HiResScrollFeature.getWheelCapability(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(cap.multiplier == 8)
        #expect(cap.hasRatchet == true)
        #expect(cap.hasInvert == true)
    }

    @Test func getWheelCapabilityNoFlags() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0A, functionId: 0x00,
                     params: [0x04, 0x00] + [UInt8](repeating: 0, count: 14))

        let cap = try await HiResScrollFeature.getWheelCapability(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(cap.multiplier == 4)
        #expect(cap.hasRatchet == false)
        #expect(cap.hasInvert == false)
    }

    @Test func getWheelMode() async throws {
        let mock = MockHIDTransport()
        // flags: target=1, hiRes=1, inverted=1 -> 0x07
        mock.respond(featureIndex: 0x0A, functionId: 0x01,
                     params: [0x07] + [UInt8](repeating: 0, count: 15))

        let mode = try await HiResScrollFeature.getWheelMode(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(mode.target == true)
        #expect(mode.hiRes == true)
        #expect(mode.inverted == true)
    }

    @Test func setWheelMode() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0A, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await HiResScrollFeature.setWheelMode(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A,
            target: true, hiRes: true, inverted: true
        )

        let sent = mock.sentRequests[0]
        // target(0x01) | hiRes(0x02) | inverted(0x04) = 0x07
        #expect(sent.params[0] == 0x07)
    }

    @Test func setWheelModeAllFalse() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0A, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await HiResScrollFeature.setWheelMode(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A,
            hiRes: false, inverted: false
        )


        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x00)
    }

    // MARK: - Short params fallback

    @Test func getWheelCapabilityShortParams1Byte() async throws {
        let mock = MockHIDTransport()
        // Only 1 byte: multiplier — flags missing (params.count <= 1)
        mock.respondShort(featureIndex: 0x0A, functionId: 0x00, params: [0x08])

        let cap = try await HiResScrollFeature.getWheelCapability(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(cap.multiplier == 8)
        #expect(cap.hasRatchet == false) // flags fallback = 0
        #expect(cap.hasInvert == false)  // flags fallback = 0
    }
}

// MARK: - PointerSpeedFeature Tests

@Suite("PointerSpeedFeature")
struct PointerSpeedFeatureTests {

    @Test func getSpeed() async throws {
        let mock = MockHIDTransport()
        // speed = 256 (0x0100)
        mock.respond(featureIndex: 0x0B, functionId: 0x00,
                     params: [0x01, 0x00] + [UInt8](repeating: 0, count: 14))

        let speed = try await PointerSpeedFeature.getSpeed(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0B
        )

        #expect(speed == 256)
    }

    @Test func getSpeedZero() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0B, functionId: 0x00,
                     params: [0x00, 0x00] + [UInt8](repeating: 0, count: 14))

        let speed = try await PointerSpeedFeature.getSpeed(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0B
        )

        #expect(speed == 0)
    }

    @Test func getSpeedMax() async throws {
        let mock = MockHIDTransport()
        // 511 = 0x01FF
        mock.respond(featureIndex: 0x0B, functionId: 0x00,
                     params: [0x01, 0xFF] + [UInt8](repeating: 0, count: 14))

        let speed = try await PointerSpeedFeature.getSpeed(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0B
        )

        #expect(speed == 511)
    }

    @Test func setSpeed() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0B, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await PointerSpeedFeature.setSpeed(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0B, speed: 300
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x01) // 300 >> 8 = 1
        #expect(sent.params[1] == 0x2C) // 300 & 0xFF = 44
    }

    @Test func setSpeedRoundTrip() async throws {
        let mock = MockHIDTransport()

        for testSpeed in [0, 1, 128, 255, 256, 511] {
            mock.reset()
            mock.respond(featureIndex: 0x0B, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

            try await PointerSpeedFeature.setSpeed(
                transport: mock, deviceIndex: 0x01, featureIndex: 0x0B, speed: testSpeed
            )

            let sent = mock.sentRequests[0]
            let encoded = (Int(sent.params[0]) << 8) | Int(sent.params[1])
            #expect(encoded == testSpeed)
        }
    }
}

// MARK: - ThumbWheelFeature Tests

@Suite("ThumbWheelFeature")
struct ThumbWheelFeatureTests {

    @Test func getInfo() async throws {
        let mock = MockHIDTransport()
        // nativeRes=1200(0x04B0), divertedRes=120(0x0078), flags=0x07
        let params: [UInt8] = [
            0x04, 0xB0,   // native resolution
            0x00, 0x78,   // diverted resolution
            0x07,         // all flags set
        ] + [UInt8](repeating: 0, count: 11)

        mock.respond(featureIndex: 0x0C, functionId: 0x00, params: params)

        let info = try await ThumbWheelFeature.getInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(info.nativeResolution == 1200)
        #expect(info.divertedResolution == 120)
        #expect(info.supportsInversion == true)
        #expect(info.supportsTouch == true)
        #expect(info.supportsTimestamp == true)
    }

    @Test func getConfig() async throws {
        let mock = MockHIDTransport()
        // flags: inverted=1, diverted=1 -> 0x03
        mock.respond(featureIndex: 0x0C, functionId: 0x01,
                     params: [0x03] + [UInt8](repeating: 0, count: 15))

        let config = try await ThumbWheelFeature.getConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(config.inverted == true)
        #expect(config.diverted == true)
    }

    @Test func getConfigDefault() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0C, functionId: 0x01,
                     params: [0x00] + [UInt8](repeating: 0, count: 15))

        let config = try await ThumbWheelFeature.getConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(config.inverted == false)
        #expect(config.diverted == false)
    }

    @Test func setConfig() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0C, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await ThumbWheelFeature.setConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C,
            inverted: true, diverted: false
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x01) // inverted only
    }

    @Test func setConfigBothTrue() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0C, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await ThumbWheelFeature.setConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C,
            inverted: true, diverted: true
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x03)
    }

    // MARK: - Short params fallback

    @Test func getInfoShortParams2Bytes() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: nativeResolution — divertedRes and flags missing
        mock.respondShort(featureIndex: 0x0C, functionId: 0x00,
                          params: [0x04, 0xB0]) // nativeRes=1200

        let info = try await ThumbWheelFeature.getInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(info.nativeResolution == 1200)
        #expect(info.divertedResolution == 1200) // fallback: divertedRes = nativeRes
        #expect(info.supportsInversion == false)  // flags fallback = 0
        #expect(info.supportsTouch == false)
        #expect(info.supportsTimestamp == false)
    }

    @Test func getInfoShortParams4Bytes() async throws {
        let mock = MockHIDTransport()
        // 4 bytes: nativeRes(2) + divertedRes(2) — flags missing
        mock.respondShort(featureIndex: 0x0C, functionId: 0x00,
                          params: [0x04, 0xB0, 0x00, 0x78]) // native=1200, diverted=120

        let info = try await ThumbWheelFeature.getInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(info.nativeResolution == 1200)
        #expect(info.divertedResolution == 120)
        #expect(info.supportsInversion == false)  // flags fallback = 0
        #expect(info.supportsTouch == false)
        #expect(info.supportsTimestamp == false)
    }
}

// MARK: - ChangeHostFeature Tests

@Suite("ChangeHostFeature")
struct ChangeHostFeatureTests {

    @Test func getHostInfo() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0D, functionId: 0x00,
                     params: [3, 1] + [UInt8](repeating: 0, count: 14))

        let info = try await ChangeHostFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0D
        )

        #expect(info.hostCount == 3)
        #expect(info.currentHost == 1)
    }

    @Test func setHost() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0D, functionId: 0x01, params: [UInt8](repeating: 0, count: 16))

        try await ChangeHostFeature.setHost(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0D,
            hostIndex: 2
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 2)
    }
}

// MARK: - HostsInfoFeature Tests

@Suite("HostsInfoFeature")
struct HostsInfoFeatureTests {

    @Test func getHostCount() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0E, functionId: 0x00,
                     params: [3] + [UInt8](repeating: 0, count: 15))

        let count = try await HostsInfoFeature.getHostCount(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
        )

        #expect(count == 3)
    }

    @Test func getHostInfo() async throws {
        let mock = MockHIDTransport()
        // hostIndex echo=0, busType=2(bolt), osType=6(macOS), nameLen=10, maxNameLen=32, flags=0x01(paired)
        let params: [UInt8] = [
            0x00,   // host index echo
            0x02,   // bus type = bolt
            0x06,   // OS type = macOS
            10,     // name length
            32,     // max name length
            0x01,   // flags (paired)
        ] + [UInt8](repeating: 0, count: 10)

        mock.respond(featureIndex: 0x0E, functionId: 0x01, params: params)

        let info = try await HostsInfoFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E,
            hostIndex: 0
        )

        #expect(info.busType == .blePro)
        #expect(info.osType == .macOS)
        #expect(info.nameLength == 10)
        #expect(info.isPaired == true)
    }

    @Test func getHostInfoNotPaired() async throws {
        let mock = MockHIDTransport()
        let params: [UInt8] = [0x01, 0x00, 0x00, 0, 32, 0x00] + [UInt8](repeating: 0, count: 10)
        mock.respond(featureIndex: 0x0E, functionId: 0x01, params: params)

        let info = try await HostsInfoFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E, hostIndex: 1
        )

        #expect(info.busType == .unknown)
        #expect(info.osType == .unknown)
        #expect(info.isPaired == false)
    }

    @Test func getHostNameChunk() async throws {
        let mock = MockHIDTransport()
        // Response: hostIndex echo, offset echo, then name bytes
        let nameBytes = Array("MacBook Pro".utf8)
        let params: [UInt8] = [0x00, 0x00] + nameBytes + [UInt8](repeating: 0, count: 14 - nameBytes.count)
        mock.respond(featureIndex: 0x0E, functionId: 0x02, params: params)

        let chunk = try await HostsInfoFeature.getHostNameChunk(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E,
            hostIndex: 0, offset: 0
        )

        #expect(chunk == "MacBook Pro")
    }

    @Test func enumerateHostsSingle() async throws {
        let mock = MockHIDTransport()

        // getHostCount -> 1
        mock.respond(featureIndex: 0x0E, functionId: 0x00,
                     params: [1] + [UInt8](repeating: 0, count: 15))

        // getHostInfo for host 0: bolt, macOS, nameLen=11, paired
        let hostInfoParams: [UInt8] = [0x00, 0x02, 0x06, 11, 32, 0x01] + [UInt8](repeating: 0, count: 10)
        mock.respond(featureIndex: 0x0E, functionId: 0x01, params: hostInfoParams)

        // getHostNameChunk: "MacBook Pro"
        let nameBytes = Array("MacBook Pro".utf8)
        let nameParams: [UInt8] = [0x00, 0x00] + nameBytes + [UInt8](repeating: 0, count: 14 - nameBytes.count)
        mock.respond(featureIndex: 0x0E, functionId: 0x02, params: nameParams)

        let hosts = try await HostsInfoFeature.enumerateHosts(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
        )

        #expect(hosts.count == 1)
        #expect(hosts[0].name == "MacBook Pro")
        #expect(hosts[0].busType == .blePro)
        #expect(hosts[0].osType == .macOS)
        #expect(hosts[0].isPaired == true)
    }

    @Test func enumerateHostsEmptyNameFallback() async throws {
        let mock = MockHIDTransport()

        // getHostCount -> 1
        mock.respond(featureIndex: 0x0E, functionId: 0x00,
                     params: [1] + [UInt8](repeating: 0, count: 15))

        // getHostInfo for host 0: nameLen=0, paired
        let hostInfoParams: [UInt8] = [0x00, 0x01, 0x00, 0, 32, 0x01] + [UInt8](repeating: 0, count: 10)
        mock.respond(featureIndex: 0x0E, functionId: 0x01, params: hostInfoParams)

        let hosts = try await HostsInfoFeature.enumerateHosts(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
        )

        #expect(hosts.count == 1)
        #expect(hosts[0].name == "Host 1") // fallback name
    }

    // MARK: - Short params fallback

    @Test func getHostInfoShortParams5Bytes() async throws {
        let mock = MockHIDTransport()
        // 5 bytes: hostIdx + bus + os + nameLen + maxNameLen — flags missing
        mock.respondShort(featureIndex: 0x0E, functionId: 0x01,
                          params: [0x00, 0x02, 0x06, 10, 32])

        let info = try await HostsInfoFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E, hostIndex: 0
        )

        #expect(info.busType == .blePro)
        #expect(info.osType == .macOS)
        #expect(info.nameLength == 10)
        #expect(info.isPaired == false) // flags fallback = 0, bit 0 = 0
    }
}
