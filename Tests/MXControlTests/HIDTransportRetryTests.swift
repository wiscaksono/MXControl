import Testing
@testable import MXControl

@Suite("HIDTransport.sendWithRetry")
struct HIDTransportRetryTests {

    @Test func successOnFirstAttempt() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x42] + [UInt8](repeating: 0, count: 15))

        let response = try await mock.sendWithRetry(
            deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
            softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
        )

        #expect(response.params[0] == 0x42)
        #expect(mock.sendCount == 1)
    }

    @Test func retryOnTimeout() async throws {
        let mock = MockHIDTransport()

        // First 2 calls: timeout, third: success
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: HIDPPError.timeout)
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: HIDPPError.timeout)
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x42] + [UInt8](repeating: 0, count: 15))

        let response = try await mock.sendWithRetry(
            deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
            softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
        )

        #expect(response.params[0] == 0x42)
        #expect(mock.sendCount == 3)
    }

    @Test func retryOnBusy() async throws {
        let mock = MockHIDTransport()

        mock.throwError(featureIndex: 0x05, functionId: 0x00,
                       error: HIDPPError.hidppError(code: .busy, featureIndex: 0x05))
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x42] + [UInt8](repeating: 0, count: 15))

        let response = try await mock.sendWithRetry(
            deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
            softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
        )

        #expect(response.params[0] == 0x42)
        #expect(mock.sendCount == 2)
    }

    @Test func retryOnHardwareError() async throws {
        let mock = MockHIDTransport()

        mock.throwError(featureIndex: 0x05, functionId: 0x00,
                       error: HIDPPError.hidppError(code: .hardwareError, featureIndex: 0x05))
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x42] + [UInt8](repeating: 0, count: 15))

        let response = try await mock.sendWithRetry(
            deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
            softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
        )

        #expect(response.params[0] == 0x42)
        #expect(mock.sendCount == 2)
    }

    @Test func noRetryOnNonTransientError() async throws {
        let mock = MockHIDTransport()

        mock.throwError(featureIndex: 0x05, functionId: 0x00,
                       error: HIDPPError.featureNotSupported(0x1004))

        do {
            _ = try await mock.sendWithRetry(
                deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
                softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
            )
            Issue.record("Expected error to be thrown")
        } catch let error as HIDPPError {
            #expect(error == .featureNotSupported(0x1004))
        }

        // Should only have tried once (non-transient = no retry)
        #expect(mock.sendCount == 1)
    }

    @Test func exhaustedRetries() async throws {
        let mock = MockHIDTransport()

        // All 3 attempts timeout
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: HIDPPError.timeout)
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: HIDPPError.timeout)
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: HIDPPError.timeout)

        do {
            _ = try await mock.sendWithRetry(
                deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
                softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
            )
            Issue.record("Expected timeout error")
        } catch let error as HIDPPError {
            #expect(error == .timeout)
        }

        #expect(mock.sendCount == 3)
    }

    @Test func maxAttemptsZeroOrNegative() async throws {
        let mock = MockHIDTransport()
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x42] + [UInt8](repeating: 0, count: 15))

        // maxAttempts=0 should be treated as 1
        let response = try await mock.sendWithRetry(
            deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
            softwareId: 0x01, maxAttempts: 0, retryDelay: .milliseconds(1)
        )

        #expect(response.params[0] == 0x42)
        #expect(mock.sendCount == 1)
    }

    // MARK: - Mixed transient errors then success

    @Test func mixedTransientErrorsThenSuccess() async throws {
        let mock = MockHIDTransport()

        // timeout → busy → success
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: HIDPPError.timeout)
        mock.throwError(featureIndex: 0x05, functionId: 0x00,
                       error: HIDPPError.hidppError(code: .busy, featureIndex: 0x05))
        mock.respond(featureIndex: 0x05, functionId: 0x00,
                     params: [0x42] + [UInt8](repeating: 0, count: 15))

        let response = try await mock.sendWithRetry(
            deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
            softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
        )

        #expect(response.params[0] == 0x42)
        #expect(mock.sendCount == 3) // 2 retries + 1 success
    }

    // MARK: - Non-HIDPPError propagation

    @Test func nonHIDPPErrorNotRetried() async throws {
        let mock = MockHIDTransport()

        // A non-HIDPPError (e.g., generic Swift error) should NOT be retried
        // because the catch clause only matches HIDPPError where isTransient
        struct CustomError: Error {}
        mock.throwError(featureIndex: 0x05, functionId: 0x00, error: CustomError())

        do {
            _ = try await mock.sendWithRetry(
                deviceIndex: 0x01, featureIndex: 0x05, functionId: 0x00,
                softwareId: 0x01, maxAttempts: 3, retryDelay: .milliseconds(1)
            )
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is CustomError)
        }

        // Only 1 attempt — non-HIDPPError is not caught by the retry loop
        #expect(mock.sendCount == 1)
    }
}
