import Testing
@testable import MXControl

@Suite("SpecialKeysFeature Transport")
struct SpecialKeysFeatureTests {

    // MARK: - getCount

    @Test func getCount() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x00,
                     params: [7] + [UInt8](repeating: 0, count: 15))

        let count = try await SpecialKeysFeature.getCount(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09
        )

        #expect(count == 7)
    }

    // MARK: - getCtrlIdInfo

    @Test func getCtrlIdInfo() async throws {
        let mock = MockHIDTransport()
        // CID=82(0x0052), TID=82(0x0052), flags1=0x30(reprog+divert), pos=1, group=2, gmask=3, flags2=0x01
        let params: [UInt8] = [
            0x00, 0x52,   // CID = 82
            0x00, 0x52,   // TID = 82
            0x30,         // flags1 (reprogrammable|divertable)
            0x01,         // position
            0x02,         // group
            0x03,         // gmask
            0x01,         // flags2 (rawXY bit in high byte)
        ] + [UInt8](repeating: 0, count: 7)

        mock.respond(featureIndex: 0x09, functionId: 0x01, params: params)

        let info = try await SpecialKeysFeature.getCtrlIdInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, index: 0
        )

        #expect(info.controlId == 82)
        #expect(info.taskId == 82)
        #expect(info.isRemappable == true)
        #expect(info.isDivertable == true)
        #expect(info.position == 1)
        #expect(info.group == 2)
        #expect(info.groupMask == 3)
        // flags = UInt16(0x30) | (UInt16(0x01) << 8) = 0x0130
        #expect(info.flags.contains(.reprogrammable))
        #expect(info.flags.contains(.divertable))
        #expect(info.flags.contains(.rawXY))
    }

    @Test func getCtrlIdInfoMinimalParams() async throws {
        let mock = MockHIDTransport()
        // Only CID and TID
        let params: [UInt8] = [
            0x00, 0x53,   // CID = 83
            0x00, 0x53,   // TID = 83
        ] + [UInt8](repeating: 0, count: 12)

        mock.respond(featureIndex: 0x09, functionId: 0x01, params: params)

        let info = try await SpecialKeysFeature.getCtrlIdInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, index: 1
        )

        #expect(info.controlId == 83)
        #expect(info.taskId == 83)
        #expect(info.isRemappable == false)
        #expect(info.isDivertable == false)
    }

    // MARK: - getCtrlIdReporting

    @Test func getCtrlIdReporting() async throws {
        let mock = MockHIDTransport()
        // CID echo=82, flags=0x15 (divert=1, persist=1, rawXY=1), remap=86(0x0056)
        let params: [UInt8] = [
            0x00, 0x52,   // CID = 82
            0x15,         // flags: divert(0x01) + persist(0x04) + rawXY(0x10)
            0x00, 0x56,   // remap target = 86
        ] + [UInt8](repeating: 0, count: 11)

        mock.respond(featureIndex: 0x09, functionId: 0x02, params: params)

        let state = try await SpecialKeysFeature.getCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, controlId: 82
        )

        #expect(state.controlId == 82)
        #expect(state.isDiverted == true)
        #expect(state.persistDivert == true)
        #expect(state.rawXY == true)
        #expect(state.remapTarget == 86)
    }

    @Test func getCtrlIdReportingDefault() async throws {
        let mock = MockHIDTransport()
        // No divert, no remap
        let params: [UInt8] = [
            0x00, 0x52,   // CID = 82
            0x00,         // no flags
            0x00, 0x00,   // no remap
        ] + [UInt8](repeating: 0, count: 11)

        mock.respond(featureIndex: 0x09, functionId: 0x02, params: params)

        let state = try await SpecialKeysFeature.getCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, controlId: 82
        )

        #expect(state.isDiverted == false)
        #expect(state.persistDivert == false)
        #expect(state.rawXY == false)
        #expect(state.remapTarget == 0)
    }

    // MARK: - setCtrlIdReporting

    @Test func setCtrlIdReportingAllFlags() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 195, divert: true, persistDivert: true, rawXY: true,
            remapTarget: 82
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0x00) // CID hi (195 = 0x00C3)
        #expect(sent.params[1] == 0xC3) // CID lo
        // flags: divert(0x01) + dvalid(0x02) + persist(0x04) + pvalid(0x08) + rawXY(0x10) + rvalid(0x20) = 0x3F
        #expect(sent.params[2] == 0x3F)
        #expect(sent.params[3] == 0x00) // remap hi (82 = 0x0052)
        #expect(sent.params[4] == 0x52) // remap lo
    }

    @Test func setCtrlIdReportingNoFlags() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        // All nil = no valid bits set, no change
        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 82
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[2] == 0x00) // no flags
        #expect(sent.params[3] == 0x00) // no remap
        #expect(sent.params[4] == 0x00)
    }

    @Test func setCtrlIdReportingDivertOnly() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 82, divert: true
        )

        let sent = mock.sentRequests[0]
        // divert(0x01) + dvalid(0x02) = 0x03
        #expect(sent.params[2] == 0x03)
    }

    @Test func setCtrlIdReportingDisableDivert() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 82, divert: false
        )

        let sent = mock.sentRequests[0]
        // dvalid(0x02) only, divert bit NOT set
        #expect(sent.params[2] == 0x02)
    }

    @Test func setCtrlIdReportingPersistOnly() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 82, persistDivert: true
        )

        let sent = mock.sentRequests[0]
        // persist(0x04) + pvalid(0x08) = 0x0C
        #expect(sent.params[2] == 0x0C)
    }

    @Test func setCtrlIdReportingRawXYOnly() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 82, rawXY: true
        )

        let sent = mock.sentRequests[0]
        // rawXY(0x10) + rvalid(0x20) = 0x30
        #expect(sent.params[2] == 0x30)
    }

    // MARK: - getCtrlIdInfo short params fallback

    @Test func getCtrlIdInfoShortParams5Bytes() async throws {
        let mock = MockHIDTransport()
        // 5 bytes: CID(2) + TID(2) + flags1(1) — position, group, gmask, flags2 all missing
        mock.respondShort(featureIndex: 0x09, functionId: 0x01,
                          params: [0x00, 0x52, 0x00, 0x52, 0x30])

        let info = try await SpecialKeysFeature.getCtrlIdInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, index: 0
        )

        #expect(info.controlId == 82)
        #expect(info.taskId == 82)
        #expect(info.isRemappable == true)   // flags1=0x30 has reprogrammable bit
        #expect(info.isDivertable == true)    // flags1=0x30 has divertable bit
        #expect(info.position == 0)           // fallback
        #expect(info.group == 0)              // fallback
        #expect(info.groupMask == 0)          // fallback
        // flags2 missing → high byte = 0, so rawXY etc. not set
        #expect(info.flags.contains(.rawXY) == false)
    }

    @Test func getCtrlIdInfoShortParams4Bytes() async throws {
        let mock = MockHIDTransport()
        // 4 bytes: CID(2) + TID(2) only — all flags/position/group/gmask missing
        mock.respondShort(featureIndex: 0x09, functionId: 0x01,
                          params: [0x00, 0x56, 0x00, 0x56])

        let info = try await SpecialKeysFeature.getCtrlIdInfo(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, index: 2
        )

        #expect(info.controlId == 86)
        #expect(info.taskId == 86)
        #expect(info.flags.rawValue == 0)  // all flags fallback to 0
        #expect(info.position == 0)
        #expect(info.group == 0)
        #expect(info.groupMask == 0)
    }

    // MARK: - getCtrlIdReporting short params fallback

    @Test func getCtrlIdReportingShortParams2Bytes() async throws {
        let mock = MockHIDTransport()
        // Only 2 bytes: CID echo only — flags, remap all missing
        mock.respondShort(featureIndex: 0x09, functionId: 0x02,
                          params: [0x00, 0x52])

        let state = try await SpecialKeysFeature.getCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, controlId: 82
        )

        #expect(state.controlId == 82)
        #expect(state.isDiverted == false)    // reportFlags fallback = 0
        #expect(state.persistDivert == false)
        #expect(state.rawXY == false)
        #expect(state.remapTarget == 0)       // remap fallback = 0
    }

    @Test func getCtrlIdReportingShortParams3Bytes() async throws {
        let mock = MockHIDTransport()
        // 3 bytes: CID(2) + flags(1) — remap missing
        mock.respondShort(featureIndex: 0x09, functionId: 0x02,
                          params: [0x00, 0x52, 0x05]) // flags: divert + persist

        let state = try await SpecialKeysFeature.getCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09, controlId: 82
        )

        #expect(state.isDiverted == true)
        #expect(state.persistDivert == true)
        #expect(state.rawXY == false)
        #expect(state.remapTarget == 0)  // remap hi/lo both fallback to 0
    }

    // MARK: - CID 0xFFFF edge case

    @Test func parseDivertedButtonsHighCID() {
        // CID 0xFFFF — maximum possible CID value
        let params: [UInt8] = [0xFF, 0xFF, 0x00, 0x00]
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
        #expect(cids == [0xFFFF])
    }

    @Test func setCtrlIdReportingRemapOnly() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        // Set remap target without changing divert flags (all nil)
        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 82, remapTarget: 86
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[2] == 0x00) // no flags changed
        #expect(sent.params[3] == 0x00) // remap hi (86 = 0x0056)
        #expect(sent.params[4] == 0x56) // remap lo
    }

    @Test func setCtrlIdReportingCIDMaxValue() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x09, functionId: 0x03, params: [UInt8](repeating: 0, count: 16))

        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: mock, deviceIndex: 0x01, featureIndex: 0x09,
            controlId: 0xFFFF, divert: true, remapTarget: 0xFFFF
        )

        let sent = mock.sentRequests[0]
        #expect(sent.params[0] == 0xFF) // CID hi
        #expect(sent.params[1] == 0xFF) // CID lo
        #expect(sent.params[3] == 0xFF) // remap hi
        #expect(sent.params[4] == 0xFF) // remap lo
    }
}
