import Testing
@testable import MXControl

@Suite("HIDPPError")
struct HIDPPErrorTests {

    // MARK: - isTransient

    @Test func transientErrors() {
        #expect(HIDPPError.timeout.isTransient == true)
        #expect(HIDPPError.hidppError(code: .busy, featureIndex: 0x05).isTransient == true)
        #expect(HIDPPError.hidppError(code: .hardwareError, featureIndex: 0x05).isTransient == true)
    }

    @Test func nonTransientErrors() {
        #expect(HIDPPError.transportNotOpen.isTransient == false)
        #expect(HIDPPError.transportError("test").isTransient == false)
        #expect(HIDPPError.tccDenied.isTransient == false)
        #expect(HIDPPError.exclusiveAccess.isTransient == false)
        #expect(HIDPPError.deviceNotFound.isTransient == false)
        #expect(HIDPPError.invalidResponse.isTransient == false)
        #expect(HIDPPError.featureNotSupported(0x1004).isTransient == false)
        #expect(HIDPPError.unknownReportId(0x13).isTransient == false)
        #expect(HIDPPError.hidppError(code: .invalidArgument, featureIndex: 0).isTransient == false)
        #expect(HIDPPError.hidppError(code: .notAllowed, featureIndex: 0).isTransient == false)
        #expect(HIDPPError.hidppError(code: .unsupported, featureIndex: 0).isTransient == false)
    }

    // MARK: - errorDescription

    @Test func errorDescriptions() {
        #expect(HIDPPError.transportNotOpen.errorDescription != nil)
        #expect(HIDPPError.transportError("test msg").errorDescription!.contains("test msg"))
        #expect(HIDPPError.tccDenied.errorDescription!.contains("Input Monitoring"))
        #expect(HIDPPError.exclusiveAccess.errorDescription!.contains("exclusive"))
        #expect(HIDPPError.timeout.errorDescription!.contains("timed out"))
        #expect(HIDPPError.deviceNotFound.errorDescription!.contains("not found"))
        #expect(HIDPPError.invalidResponse.errorDescription!.contains("Invalid"))
        #expect(HIDPPError.featureNotSupported(0x1004).errorDescription!.contains("1004"))
        #expect(HIDPPError.unknownReportId(0x13).errorDescription!.contains("0x13"))
        #expect(HIDPPError.hidppError(code: .busy, featureIndex: 0x05).errorDescription!.contains("Busy"))
    }

    // MARK: - Equatable

    @Test func equalitySameCases() {
        #expect(HIDPPError.transportNotOpen == HIDPPError.transportNotOpen)
        #expect(HIDPPError.tccDenied == HIDPPError.tccDenied)
        #expect(HIDPPError.exclusiveAccess == HIDPPError.exclusiveAccess)
        #expect(HIDPPError.timeout == HIDPPError.timeout)
        #expect(HIDPPError.deviceNotFound == HIDPPError.deviceNotFound)
        #expect(HIDPPError.invalidResponse == HIDPPError.invalidResponse)
        #expect(HIDPPError.transportError("a") == HIDPPError.transportError("a"))
        #expect(HIDPPError.featureNotSupported(0x1004) == HIDPPError.featureNotSupported(0x1004))
        #expect(HIDPPError.unknownReportId(0x13) == HIDPPError.unknownReportId(0x13))
        #expect(HIDPPError.hidppError(code: .busy, featureIndex: 5) == HIDPPError.hidppError(code: .busy, featureIndex: 5))
    }

    @Test func inequalityDifferentCases() {
        #expect(HIDPPError.timeout != HIDPPError.transportNotOpen)
        #expect(HIDPPError.transportError("a") != HIDPPError.transportError("b"))
        #expect(HIDPPError.featureNotSupported(0x1004) != HIDPPError.featureNotSupported(0x2201))
        #expect(HIDPPError.hidppError(code: .busy, featureIndex: 5) != HIDPPError.hidppError(code: .busy, featureIndex: 6))
        #expect(HIDPPError.hidppError(code: .busy, featureIndex: 5) != HIDPPError.hidppError(code: .notAllowed, featureIndex: 5))
    }
}

// MARK: - HIDPPErrorCode Tests

@Suite("HIDPPErrorCode")
struct HIDPPErrorCodeTests {

    @Test func rawValues() {
        #expect(HIDPPErrorCode.noError.rawValue == 0x00)
        #expect(HIDPPErrorCode.unknown.rawValue == 0x01)
        #expect(HIDPPErrorCode.invalidArgument.rawValue == 0x02)
        #expect(HIDPPErrorCode.outOfRange.rawValue == 0x03)
        #expect(HIDPPErrorCode.hardwareError.rawValue == 0x04)
        #expect(HIDPPErrorCode.notAllowed.rawValue == 0x05)
        #expect(HIDPPErrorCode.invalidFeatureIndex.rawValue == 0x06)
        #expect(HIDPPErrorCode.invalidFunctionId.rawValue == 0x07)
        #expect(HIDPPErrorCode.busy.rawValue == 0x08)
        #expect(HIDPPErrorCode.unsupported.rawValue == 0x09)
    }

    @Test func names() {
        #expect(HIDPPErrorCode.noError.name == "No Error")
        #expect(HIDPPErrorCode.busy.name == "Busy")
        #expect(HIDPPErrorCode.hardwareError.name == "Hardware Error")
        #expect(HIDPPErrorCode.invalidArgument.name == "Invalid Argument")
        #expect(HIDPPErrorCode.unsupported.name == "Unsupported")
    }

    @Test func initFromRawValue() {
        #expect(HIDPPErrorCode(rawValue: 0x00) == .noError)
        #expect(HIDPPErrorCode(rawValue: 0x08) == .busy)
        #expect(HIDPPErrorCode(rawValue: 0x09) == .unsupported)
        #expect(HIDPPErrorCode(rawValue: 0x0A) == nil) // unknown
        #expect(HIDPPErrorCode(rawValue: 0xFF) == nil)
    }
}
