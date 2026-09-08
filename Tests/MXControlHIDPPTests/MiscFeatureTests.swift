import Testing
@testable import MXControlHIDPP

// MARK: - HiResScrollFeature Tests

@Suite("HiResScrollFeature")
struct HiResScrollFeatureTests {

    @Test func getWheelCapability() async throws {
        let mock = MockHIDTransport()
        // multiplier=8, flags=0x0C (bit3=invert, bit2=switch), ratchets=24, diameter=32
        mock.respond(featureIndex: 0x0A, functionId: 0x00,
                     params: [0x08, 0x0C, 0x18, 0x20] + [UInt8](repeating: 0, count: 12))

        let cap = try await HiResScrollFeature.getWheelCapability(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(cap.multiplier == 8)
        #expect(cap.hasSwitch == true)
        #expect(cap.hasInvert == true)
        #expect(cap.ratchetsPerRotation == 24)
        #expect(cap.wheelDiameter == 32)
    }

    @Test func getWheelCapabilitySwitchOnly() async throws {
        let mock = MockHIDTransport()
        // flags=0x04: switch bit alone (proves the bits are not swapped)
        mock.respond(featureIndex: 0x0A, functionId: 0x00,
                     params: [0x08, 0x04, 0x00, 0x00] + [UInt8](repeating: 0, count: 12))

        let cap = try await HiResScrollFeature.getWheelCapability(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(cap.hasSwitch == true)
        #expect(cap.hasInvert == false)
    }

    @Test func getWheelCapabilityInvertOnly() async throws {
        let mock = MockHIDTransport()
        // flags=0x08: invert bit alone
        mock.respond(featureIndex: 0x0A, functionId: 0x00,
                     params: [0x08, 0x08, 0x00, 0x00] + [UInt8](repeating: 0, count: 12))

        let cap = try await HiResScrollFeature.getWheelCapability(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0A
        )

        #expect(cap.hasSwitch == false)
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
        #expect(cap.hasSwitch == false)
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
        #expect(cap.hasSwitch == false) // flags fallback = 0
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
//
// Wire format per OpenLogi 0x2150: getInfo returns
// [native BE][diverted BE][direction][caps][time_unit BE]; getConfig returns
// [mode, flags]; setConfig sends [mode, invert, 0x00].

@Suite("ThumbWheelFeature")
struct ThumbWheelFeatureTests {

    @Test func getInfo() async throws {
        let mock = MockHIDTransport()
        // nativeRes=1200(0x04B0), divertedRes=120(0x0078), direction=0,
        // caps=touch|proxy(0x06), time_unit=0
        let params: [UInt8] = [
            0x04, 0xB0,   // native resolution
            0x00, 0x78,   // diverted resolution
            0x00,         // default direction
            0x06,         // touch + proxy
            0x00, 0x00,   // time unit
        ] + [UInt8](repeating: 0, count: 8)

        mock.respond(featureIndex: 0x0C, functionId: 0x00, params: params)

        let info = try await ThumbWheelFeature.getInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(info.nativeResolution == 1200)
        #expect(info.divertedResolution == 120)
        #expect(info.supportsInversion == true) // no cap bit in spec: always settable
        #expect(info.supportsTouch == true)
        #expect(info.supportsTimestamp == false)
        #expect(info.supportsProxy == true)
        #expect(info.supportsSingleTap == false)
        #expect(info.timeUnit == 0)
    }

    @Test func getConfig() async throws {
        let mock = MockHIDTransport()
        // mode=native(0), flags=inverted(0x01)
        mock.respond(featureIndex: 0x0C, functionId: 0x01,
                     params: [0x00, 0x01] + [UInt8](repeating: 0, count: 14))

        let config = try await ThumbWheelFeature.getConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(config.inverted == true)
        #expect(config.diverted == false)
    }

    @Test func getConfigDiverted() async throws {
        let mock = MockHIDTransport()
        // mode=diverted(1), flags=0
        mock.respond(featureIndex: 0x0C, functionId: 0x01,
                     params: [0x01, 0x00] + [UInt8](repeating: 0, count: 14))

        let config = try await ThumbWheelFeature.getConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(config.inverted == false)
        #expect(config.diverted == true)
    }

    @Test func setConfigInverted() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0C, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await ThumbWheelFeature.setConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C,
            inverted: true, diverted: false
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params == [0x00, 0x01, 0x00]) // mode=native, invert, reserved
    }

    @Test func setConfigDefault() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0C, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await ThumbWheelFeature.setConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C,
            inverted: false, diverted: false
        )

        #expect(mock.sentRequests[0].params == [0x00, 0x00, 0x00])
    }

    @Test func setConfigDiverted() async throws {        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0C, functionId: 0x02, params: [UInt8](repeating: 0, count: 16))

        try await ThumbWheelFeature.setConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C,
            inverted: false, diverted: true
        )

        #expect(mock.sentRequests[0].params == [0x01, 0x00, 0x00])
    }

    @Test func getConfigShortParams() async throws {
        let mock = MockHIDTransport()
        mock.respondShort(featureIndex: 0x0C, functionId: 0x01, params: [])

        let config = try await ThumbWheelFeature.getConfig(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(config.inverted == false)
        #expect(config.diverted == false)
    }

    // MARK: - Short params fallback

    @Test func getInfoShortParams() async throws {
        let mock = MockHIDTransport()
        // Only native resolution — everything else missing
        mock.respondShort(featureIndex: 0x0C, functionId: 0x00,
                          params: [0x04, 0xB0]) // nativeRes=1200

        let info = try await ThumbWheelFeature.getInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0C
        )

        #expect(info.nativeResolution == 1200)
        #expect(info.divertedResolution == 1200) // fallback: divertedRes = nativeRes
        #expect(info.supportsInversion == true)
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
//
// Wire format per OpenLogi 0x1815 hostsInfo: fn0 returns
// [caps, desc_caps, count, current]; fn1 takes [host, 0, 0] and returns
// [echo, status, bus, page_count, name_len, name_max_len]. There is no OS
// type field and no name-chunk protocol (names live in descriptor pages
// whose layout is unspecified, so entries fall back to "Slot N").

@Suite("HostsInfoFeature")
struct HostsInfoFeatureTests {

    @Test func getFeatureInfo() async throws {
        let mock = MockHIDTransport()
        // caps=GET_NAME(0x01), descCaps=0, count=3, current=1
        mock.respond(featureIndex: 0x0E, functionId: 0x00,
                     params: [0x01, 0x00, 0x03, 0x01] + [UInt8](repeating: 0, count: 12))

        let info = try await HostsInfoFeature.getFeatureInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
        )

        #expect(info.canGetName == true)
        #expect(info.hostCount == 3)
        #expect(info.currentHost == 1)
    }

    @Test func getFeatureInfoUnknownCurrent() async throws {
        let mock = MockHIDTransport()
        // current=0xFF means unknown -> slot 0
        mock.respond(featureIndex: 0x0E, functionId: 0x00,
                     params: [0x00, 0x00, 0x03, 0xFF] + [UInt8](repeating: 0, count: 12))

        let info = try await HostsInfoFeature.getFeatureInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
        )

        #expect(info.hostCount == 3)
        #expect(info.currentHost == 0)
    }

    @Test func getHostInfo() async throws {
        let mock = MockHIDTransport()
        // echo=0, status=paired(1), bus=blePro(5), pages=2, nameLen=10, maxLen=32
        let params: [UInt8] = [
            0x00,   // slot echo
            0x01,   // paired
            0x05,   // bus = blePro
            0x02,   // page count
            10,     // name length
            32,     // max name length
        ] + [UInt8](repeating: 0, count: 10)

        mock.respond(featureIndex: 0x0E, functionId: 0x01, params: params)

        let slot = try await HostsInfoFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E,
            hostIndex: 0
        )

        #expect(slot.index == 0)
        #expect(slot.busType == .blePro)
        #expect(slot.paired == true)
    }

    @Test func getHostInfoNotPaired() async throws {
        let mock = MockHIDTransport()
        // echo=1, status=empty(0), bus=undefined(0)
        let params: [UInt8] = [0x01, 0x00, 0x00, 0, 0, 0] + [UInt8](repeating: 0, count: 10)
        mock.respond(featureIndex: 0x0E, functionId: 0x01, params: params)

        let slot = try await HostsInfoFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E, hostIndex: 1
        )

        #expect(slot.busType == .undefined)
        #expect(slot.paired == false)
    }

    @Test func getHostInfoSendsSlotIndex() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x0E, functionId: 0x01,
                     params: [0x02, 0x01, 0x02, 0, 0, 0] + [UInt8](repeating: 0, count: 10))

        _ = try await HostsInfoFeature.getHostInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E, hostIndex: 2
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 2) // slot index first, zero-padded
        #expect(sent.params[1] == 0x00)
        #expect(sent.params[2] == 0x00)
    }

    @Test func enumerateHosts() async throws {
        let mock = MockHIDTransport()

        // fn0: 3 slots, current 1
        mock.respond(featureIndex: 0x0E, functionId: 0x00,
                     params: [0x01, 0x00, 0x03, 0x01] + [UInt8](repeating: 0, count: 12))

        // fn1 slot 0: paired via USB
        mock.respond(featureIndex: 0x0E, functionId: 0x01,
                     params: [0x00, 0x01, 0x02, 0, 0, 0] + [UInt8](repeating: 0, count: 10))
        // fn1 slot 1: paired via BLE
        mock.respond(featureIndex: 0x0E, functionId: 0x01,
                     params: [0x01, 0x01, 0x04, 0, 0, 0] + [UInt8](repeating: 0, count: 10))
        // fn1 slot 2: empty
        mock.respond(featureIndex: 0x0E, functionId: 0x01,
                     params: [0x02, 0x00, 0x00, 0, 0, 0] + [UInt8](repeating: 0, count: 10))

        let (hosts, current) = try await HostsInfoFeature.enumerateHosts(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
        )

        #expect(current == 1)
        #expect(hosts.count == 3)
        #expect(hosts[0].name == "Slot 1")
        #expect(hosts[0].busType == .usb)
        #expect(hosts[0].isPaired == true)
        #expect(hosts[1].busType == .ble)
        #expect(hosts[2].isPaired == false)
    }

    @Test func truncatedResponsesThrow() async throws {
        let mock = MockHIDTransport()
        mock.respondShort(featureIndex: 0x0E, functionId: 0x00, params: [0x01, 0x00])

        await #expect(throws: (any Error).self) {
            try await HostsInfoFeature.getFeatureInfo(
                transport: mock, deviceIndex: 0x01, featureIndex: 0x0E
            )
        }

        let mock2 = MockHIDTransport()
        mock2.respondShort(featureIndex: 0x0E, functionId: 0x01, params: [0x00, 0x01])

        await #expect(throws: (any Error).self) {
            try await HostsInfoFeature.getHostInfo(
                transport: mock2, deviceIndex: 0x01, featureIndex: 0x0E, hostIndex: 0
            )
        }
    }
}
