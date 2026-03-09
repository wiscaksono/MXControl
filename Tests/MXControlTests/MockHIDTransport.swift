import Foundation
@testable import MXControl

/// Mock HID++ transport for unit testing.
///
/// Allows pre-programming responses keyed by (featureIndex, functionId).
/// Records all sent requests for verification.
final class MockHIDTransport: HIDTransport, @unchecked Sendable {

    struct SentRequest: Sendable {
        let deviceIndex: UInt8
        let featureIndex: UInt8
        let functionId: UInt8
        let softwareId: UInt8
        let params: [UInt8]
    }

    /// Key for response lookup.
    struct RequestKey: Hashable {
        let featureIndex: UInt8
        let functionId: UInt8
    }

    /// Pre-programmed responses. Multiple responses per key are returned in FIFO order.
    private var responses: [RequestKey: [HIDPPResponse]] = [:]

    /// Pre-programmed errors. Takes priority over responses if set.
    private var errors: [RequestKey: [any Error]] = [:]

    /// All requests sent through this transport.
    private(set) var sentRequests: [SentRequest] = []

    /// Number of send calls made.
    var sendCount: Int { sentRequests.count }

    // MARK: - Programming

    /// Program a response for a given (featureIndex, functionId) pair.
    /// Params are passed as-is (typically callers pad to 16 bytes for normal responses).
    func respond(
        featureIndex: UInt8,
        functionId: UInt8,
        params: [UInt8],
        reportId: ReportID = .long
    ) {
        let key = RequestKey(featureIndex: featureIndex, functionId: functionId)
        let response = HIDPPResponse(
            reportId: reportId,
            deviceIndex: 0x01,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: 0x01,
            params: params
        )
        responses[key, default: []].append(response)
    }

    /// Program a response with exact (unpadded) params to test short/truncated responses.
    /// Use this to exercise `params.count > N ? ... : fallback` guards in source code.
    func respondShort(
        featureIndex: UInt8,
        functionId: UInt8,
        params: [UInt8],
        reportId: ReportID = .short
    ) {
        respond(featureIndex: featureIndex, functionId: functionId,
                params: params, reportId: reportId)
    }

    /// Program an error for a given (featureIndex, functionId) pair.
    func throwError(
        featureIndex: UInt8,
        functionId: UInt8,
        error: any Error
    ) {
        let key = RequestKey(featureIndex: featureIndex, functionId: functionId)
        errors[key, default: []].append(error)
    }

    // MARK: - HIDTransport

    func send(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionId: UInt8,
        softwareId: UInt8,
        params: [UInt8]
    ) async throws -> HIDPPResponse {
        sentRequests.append(SentRequest(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: params
        ))

        let key = RequestKey(featureIndex: featureIndex, functionId: functionId)

        // Check for programmed errors first
        if var errorQueue = errors[key], !errorQueue.isEmpty {
            let error = errorQueue.removeFirst()
            errors[key] = errorQueue.isEmpty ? nil : errorQueue
            throw error
        }

        // Then check for programmed responses
        if var responseQueue = responses[key], !responseQueue.isEmpty {
            let response = responseQueue.removeFirst()
            responses[key] = responseQueue.isEmpty ? nil : responseQueue
            return response
        }

        // No programmed response — return a default empty response
        return HIDPPResponse(
            reportId: .long,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: functionId,
            softwareId: softwareId,
            params: [UInt8](repeating: 0, count: 16)
        )
    }

    func open() async throws {}
    func close() {}

    /// Reset all programmed responses, errors, and recorded requests.
    func reset() {
        responses.removeAll()
        errors.removeAll()
        sentRequests.removeAll()
    }
}
