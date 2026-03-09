import Testing
@testable import MXControl

@Suite("SpecialKeysFeature Parsing")
struct SpecialKeysParsingTests {

    // MARK: - parseDivertedButtonsEvent

    @Test func parseSingleButton() {
        let params: [UInt8] = [0x00, 0x52, 0x00, 0x00] // CID 0x0052 = 82 (middle button)
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
        #expect(cids == [82])
    }

    @Test func parseMultipleButtons() {
        let params: [UInt8] = [0x00, 0x52, 0x00, 0x53, 0x00, 0x56] // CIDs 82, 83, 86
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
        #expect(cids == [82, 83, 86])
    }

    @Test func parseAllReleased() {
        let params: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
        #expect(cids.isEmpty)
    }

    @Test func parseEmptyParams() {
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: [])
        #expect(cids.isEmpty)
    }

    @Test func parseSingleByte() {
        // Odd-length array: single byte can't form a pair
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: [0x01])
        #expect(cids.isEmpty)
    }

    @Test func parseSkipsZeroCIDs() {
        // Mix of real CIDs and zero CIDs
        let params: [UInt8] = [0x00, 0x52, 0x00, 0x00, 0x00, 0x53]
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
        #expect(cids == [82, 83])
    }

    @Test func parseHighCIDValues() {
        let params: [UInt8] = [0x00, 0xC3, 0x00, 0xC4] // CIDs 195, 196
        let cids = SpecialKeysFeature.parseDivertedButtonsEvent(params: params)
        #expect(cids == [195, 196])
    }

    // MARK: - parseRawXYEvent

    @Test func parsePositiveDeltas() {
        let params: [UInt8] = [0x00, 0x64, 0x00, 0x32] // dx=100, dy=50
        let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
        #expect(dx == 100)
        #expect(dy == 50)
    }

    @Test func parseNegativeDeltas() {
        // dx = -100 = 0xFF9C, dy = -50 = 0xFFCE
        let params: [UInt8] = [0xFF, 0x9C, 0xFF, 0xCE]
        let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
        #expect(dx == -100)
        #expect(dy == -50)
    }

    @Test func parseZeroDeltas() {
        let params: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
        #expect(dx == 0)
        #expect(dy == 0)
    }

    @Test func parseMaxPositive() {
        let params: [UInt8] = [0x7F, 0xFF, 0x7F, 0xFF] // Int16.max = 32767
        let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
        #expect(dx == 32767)
        #expect(dy == 32767)
    }

    @Test func parseMaxNegative() {
        let params: [UInt8] = [0x80, 0x00, 0x80, 0x00] // Int16.min = -32768
        let (dx, dy) = SpecialKeysFeature.parseRawXYEvent(params: params)
        #expect(dx == -32768)
        #expect(dy == -32768)
    }

    @Test func parseTooShortReturnsZero() {
        let (dx1, dy1) = SpecialKeysFeature.parseRawXYEvent(params: [])
        #expect(dx1 == 0 && dy1 == 0)

        let (dx2, dy2) = SpecialKeysFeature.parseRawXYEvent(params: [0x01, 0x02])
        #expect(dx2 == 0 && dy2 == 0)

        let (dx3, dy3) = SpecialKeysFeature.parseRawXYEvent(params: [0x01, 0x02, 0x03])
        #expect(dx3 == 0 && dy3 == 0)
    }

    // MARK: - KnownCID / RemapAction

    @Test func knownCIDDescriptions() {
        #expect(SpecialKeysFeature.KnownCID.middleButton.description == "Middle Click")
        #expect(SpecialKeysFeature.KnownCID.backButton.description == "Back")
        #expect(SpecialKeysFeature.KnownCID.forwardButton.description == "Forward")
        #expect(SpecialKeysFeature.KnownCID.gestureButton.description == "Gesture (Thumb)")
        #expect(SpecialKeysFeature.KnownCID.modeShift.description == "Mode Shift (Wheel)")
    }

    @Test func knownCIDRawValues() {
        #expect(SpecialKeysFeature.KnownCID.middleButton.rawValue == 82)
        #expect(SpecialKeysFeature.KnownCID.backButton.rawValue == 83)
        #expect(SpecialKeysFeature.KnownCID.forwardButton.rawValue == 86)
        #expect(SpecialKeysFeature.KnownCID.gestureButton.rawValue == 195)
        #expect(SpecialKeysFeature.KnownCID.modeShift.rawValue == 196)
    }

    @Test func remapActionDescriptions() {
        #expect(SpecialKeysFeature.RemapAction.defaultAction.description == "Default")
        #expect(SpecialKeysFeature.RemapAction.middleClick.description == "Middle Click")
        #expect(SpecialKeysFeature.RemapAction.smartShiftToggle.description == "SmartShift Toggle")
    }

    // MARK: - ControlFlags

    @Test func controlFlagsIsRemappable() {
        let flags = SpecialKeysFeature.ControlFlags([.reprogrammable, .divertable])
        let info = SpecialKeysFeature.ControlInfo(
            controlId: 82, taskId: 82, flags: flags,
            position: 0, group: 0, groupMask: 0
        )
        #expect(info.isRemappable == true)
        #expect(info.isDivertable == true)
    }

    @Test func controlFlagsNotRemappable() {
        let flags = SpecialKeysFeature.ControlFlags([.mouseButton])
        let info = SpecialKeysFeature.ControlInfo(
            controlId: 82, taskId: 82, flags: flags,
            position: 0, group: 0, groupMask: 0
        )
        #expect(info.isRemappable == false)
        #expect(info.isDivertable == false)
    }
}
