import Foundation
import Testing
@testable import MXControl

// MARK: - ReportID Tests

@Suite("ReportID")
struct ReportIDTests {

    @Test func reportLengths() {
        #expect(ReportID.short.reportLength == 7)
        #expect(ReportID.long.reportLength == 20)
        #expect(ReportID.veryLong.reportLength == 64)
    }

    @Test func maxParams() {
        #expect(ReportID.short.maxParams == 3)
        #expect(ReportID.long.maxParams == 16)
        #expect(ReportID.veryLong.maxParams == 60)
    }

    @Test func selectForParamCount() {
        // 0-3 params -> short
        #expect(ReportID.select(forParamCount: 0) == .short)
        #expect(ReportID.select(forParamCount: 1) == .short)
        #expect(ReportID.select(forParamCount: 3) == .short)

        // 4-16 params -> long
        #expect(ReportID.select(forParamCount: 4) == .long)
        #expect(ReportID.select(forParamCount: 16) == .long)

        // 17-60 params -> veryLong
        #expect(ReportID.select(forParamCount: 17) == .veryLong)
        #expect(ReportID.select(forParamCount: 60) == .veryLong)
    }

    @Test func rawValues() {
        #expect(ReportID.short.rawValue == 0x10)
        #expect(ReportID.long.rawValue == 0x11)
        #expect(ReportID.veryLong.rawValue == 0x12)
    }
}

// MARK: - HIDPPRequest Tests

@Suite("HIDPPRequest")
struct HIDPPRequestTests {

    @Test func serializeShortReport() {
        let request = HIDPPRequest(
            deviceIndex: 0x01,
            featureIndex: 0x05,
            functionId: 0x02,
            softwareId: 0x0A,
            params: [0x10, 0x20]
        )

        let data = request.serialize()

        #expect(data.count == 7) // short report
        #expect(data[0] == 0x10) // report ID
        #expect(data[1] == 0x01) // device index
        #expect(data[2] == 0x05) // feature index
        #expect(data[3] == 0x2A) // (functionId << 4) | softwareId = (2 << 4) | 0xA
        #expect(data[4] == 0x10) // param 0
        #expect(data[5] == 0x20) // param 1
        #expect(data[6] == 0x00) // zero-padded
    }

    @Test func serializeLongReport() {
        let params = [UInt8](repeating: 0xBB, count: 10)
        let request = HIDPPRequest(
            deviceIndex: 0x02,
            featureIndex: 0x0A,
            functionId: 0x03,
            softwareId: 0x01,
            params: params
        )

        let data = request.serialize()

        #expect(data.count == 20) // long report
        #expect(data[0] == 0x11) // report ID
        #expect(data[1] == 0x02) // device index
        #expect(data[2] == 0x0A) // feature index
        #expect(data[3] == 0x31) // (3 << 4) | 1
        // Params 0-9 should be 0xBB
        for i in 4..<14 {
            #expect(data[i] == 0xBB)
        }
        // Remaining should be zero-padded
        for i in 14..<20 {
            #expect(data[i] == 0x00)
        }
    }

    @Test func serializeVeryLongReport() {
        let params = [UInt8](repeating: 0xCC, count: 30)
        let request = HIDPPRequest(
            deviceIndex: 0x03,
            featureIndex: 0x0B,
            functionId: 0x0F,
            softwareId: 0x0F,
            params: params
        )

        let data = request.serialize()

        #expect(data.count == 64) // very long report
        #expect(data[0] == 0x12) // report ID
        #expect(data[3] == 0xFF) // (0xF << 4) | 0xF
    }

    @Test func serializeEmptyParams() {
        let request = HIDPPRequest(
            deviceIndex: 0x01,
            featureIndex: 0x00,
            functionId: 0x01,
            softwareId: 0x01,
            params: []
        )

        let data = request.serialize()

        #expect(data.count == 7) // short report
        #expect(data[4] == 0x00)
        #expect(data[5] == 0x00)
        #expect(data[6] == 0x00)
    }

    @Test func reportIdAutoSelection() {
        let short = HIDPPRequest(deviceIndex: 0, featureIndex: 0, functionId: 0, softwareId: 0, params: [1, 2, 3])
        #expect(short.reportId == .short)

        let long = HIDPPRequest(deviceIndex: 0, featureIndex: 0, functionId: 0, softwareId: 0, params: [UInt8](repeating: 0, count: 4))
        #expect(long.reportId == .long)

        let veryLong = HIDPPRequest(deviceIndex: 0, featureIndex: 0, functionId: 0, softwareId: 0, params: [UInt8](repeating: 0, count: 17))
        #expect(veryLong.reportId == .veryLong)
    }

    // MARK: - Params truncation

    @Test func serializeTruncatesExcessParams() {
        // 5 params → long report (maxParams=16), but let's test short truncation
        // Short report has maxParams=3. If we force 5 params into a short report via
        // the auto-select: 5 params → long report. Instead, verify truncation by
        // providing more than 16 params (which selects veryLong with maxParams=60).
        // Actually, the simpler test: provide exactly 4 params → long report (maxParams=16).
        // All fit. Let's test the real truncation path:
        // 65 params → veryLong (maxParams=60). Params beyond 60 should be silently dropped.
        let params = [UInt8](repeating: 0xAA, count: 65)
        let request = HIDPPRequest(
            deviceIndex: 0x01, featureIndex: 0x02,
            functionId: 0x03, softwareId: 0x04,
            params: params
        )

        let data = request.serialize()

        #expect(data.count == 64) // veryLong report
        #expect(data[0] == 0x12) // report ID
        // First 60 params should be 0xAA
        for i in 4..<64 {
            #expect(data[i] == 0xAA)
        }
        // The 5 excess params (indices 60-64) are silently dropped — verified by
        // the fact that data.count == 64 and all 60 param slots contain 0xAA
    }

    @Test func serializeShortReportTruncatesTo3Params() {
        // Exactly 3 params = short report. Verify no truncation needed.
        let request = HIDPPRequest(
            deviceIndex: 0x01, featureIndex: 0x02,
            functionId: 0x03, softwareId: 0x04,
            params: [0x10, 0x20, 0x30]
        )

        let data = request.serialize()
        #expect(data.count == 7)
        #expect(data[4] == 0x10)
        #expect(data[5] == 0x20)
        #expect(data[6] == 0x30)
    }
}

// MARK: - HIDPPResponse Tests

@Suite("HIDPPResponse")
struct HIDPPResponseTests {

    @Test func parseShortReport() {
        var data = [UInt8](repeating: 0, count: 7)
        data[0] = 0x10 // short report
        data[1] = 0x01 // device index
        data[2] = 0x05 // feature index
        data[3] = 0x3A // functionId=3, softwareId=0xA
        data[4] = 0xAA // param 0
        data[5] = 0xBB // param 1
        data[6] = 0xCC // param 2

        let response = HIDPPResponse.parse(data)

        #expect(response != nil)
        #expect(response!.reportId == .short)
        #expect(response!.deviceIndex == 0x01)
        #expect(response!.featureIndex == 0x05)
        #expect(response!.functionId == 0x03)
        #expect(response!.softwareId == 0x0A)
        #expect(response!.params == [0xAA, 0xBB, 0xCC])
    }

    @Test func parseLongReport() {
        var data = [UInt8](repeating: 0, count: 20)
        data[0] = 0x11 // long report
        data[1] = 0x02
        data[2] = 0x0A
        data[3] = 0x41 // functionId=4, softwareId=1
        data[4] = 0xFF

        let response = HIDPPResponse.parse(data)

        #expect(response != nil)
        #expect(response!.reportId == .long)
        #expect(response!.functionId == 0x04)
        #expect(response!.softwareId == 0x01)
        #expect(response!.params.count == 16)
        #expect(response!.params[0] == 0xFF)
    }

    @Test func parseVeryLongReport() {
        var data = [UInt8](repeating: 0, count: 64)
        data[0] = 0x12 // very long
        data[1] = 0x03
        data[2] = 0x0B
        data[3] = 0x52

        let response = HIDPPResponse.parse(data)

        #expect(response != nil)
        #expect(response!.reportId == .veryLong)
        #expect(response!.params.count == 60)
    }

    @Test func parseReturnsNilForShortData() {
        #expect(HIDPPResponse.parse([]) == nil)
        #expect(HIDPPResponse.parse([0x10]) == nil)
        #expect(HIDPPResponse.parse([0x10, 0x01, 0x02]) == nil) // 3 bytes, need 4 min
    }

    @Test func parseReturnsNilForUnknownReportId() {
        let data: [UInt8] = [0x13, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]
        #expect(HIDPPResponse.parse(data) == nil)
    }

    @Test func parseReturnsNilForTruncatedReport() {
        // Report ID says short (7 bytes) but only 5 bytes provided
        let data: [UInt8] = [0x10, 0x01, 0x02, 0x03, 0x04]
        #expect(HIDPPResponse.parse(data) == nil)
    }

    @Test func parseFromData() {
        var bytes = [UInt8](repeating: 0, count: 7)
        bytes[0] = 0x10
        bytes[1] = 0x01
        bytes[2] = 0x00
        bytes[3] = 0x10 // functionId=1, softwareId=0
        let data = Data(bytes)

        let response = HIDPPResponse.parse(data)
        #expect(response != nil)
        #expect(response!.reportId == .short)
    }

    @Test func isError() {
        let errorResponse = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0xFF, functionId: 0, softwareId: 0,
            params: [0x05, 0x02, 0x00]
        )
        #expect(errorResponse.isError == true)
        #expect(errorResponse.isHidpp10Error == false)
        #expect(errorResponse.isAnyError == true)

        let normalResponse = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0x05, functionId: 0, softwareId: 0,
            params: [0x00, 0x00, 0x00]
        )
        #expect(normalResponse.isError == false)
        #expect(normalResponse.isAnyError == false)
    }

    @Test func isHidpp10Error() {
        let error10 = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0x8F, functionId: 0, softwareId: 0,
            params: [0x05, 0x03, 0x00]
        )
        #expect(error10.isHidpp10Error == true)
        #expect(error10.isError == false)
        #expect(error10.isAnyError == true)
    }

    @Test func errorCode() {
        let errorResponse = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0xFF, functionId: 0, softwareId: 0,
            params: [0x05, 0x08, 0x00] // errorCode = 0x08 (busy)
        )
        #expect(errorResponse.errorCode == 0x08)
        #expect(errorResponse.errorFeatureIndex == 0x05)

        let normalResponse = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0x05, functionId: 0, softwareId: 0,
            params: [0x00, 0x08, 0x00]
        )
        #expect(normalResponse.errorCode == nil)
        #expect(normalResponse.errorFeatureIndex == nil)
    }

    @Test func errorCodeWithShortParams() {
        let errorShort = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0xFF, functionId: 0, softwareId: 0,
            params: [] // too short for errorCode
        )
        #expect(errorShort.errorCode == nil)
        #expect(errorShort.errorFeatureIndex == nil)

        let errorOneParam = HIDPPResponse(
            reportId: .short, deviceIndex: 0x01,
            featureIndex: 0xFF, functionId: 0, softwareId: 0,
            params: [0x05] // has errorFeatureIndex but not errorCode
        )
        #expect(errorOneParam.errorCode == nil)
        #expect(errorOneParam.errorFeatureIndex == 0x05)
    }

    // MARK: - Excess data parse

    @Test func parseDiscardsExcessData() {
        // Short report = 7 bytes. Provide 10 bytes — excess 3 should be ignored.
        var data = [UInt8](repeating: 0, count: 10)
        data[0] = 0x10 // short report
        data[1] = 0x01
        data[2] = 0x05
        data[3] = 0x21 // functionId=2, softwareId=1
        data[4] = 0xAA
        data[5] = 0xBB
        data[6] = 0xCC
        data[7] = 0xDD // excess — should be discarded
        data[8] = 0xEE // excess
        data[9] = 0xFF // excess

        let response = HIDPPResponse.parse(data)

        #expect(response != nil)
        #expect(response!.params.count == 3) // only 3 params for short report
        #expect(response!.params == [0xAA, 0xBB, 0xCC])
    }

    @Test func parseLongReportDiscardsExcess() {
        // Long report = 20 bytes. Provide 25 bytes.
        var data = [UInt8](repeating: 0xBB, count: 25)
        data[0] = 0x11 // long report
        data[1] = 0x01
        data[2] = 0x05
        data[3] = 0x10

        let response = HIDPPResponse.parse(data)

        #expect(response != nil)
        #expect(response!.params.count == 16) // only 16 params for long report
    }
}
