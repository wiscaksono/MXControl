import Foundation

// MARK: - Report IDs

/// HID++ report types with their total sizes (including report ID byte).
enum ReportID: UInt8, Sendable {
    case short = 0x10     // 7 bytes total, 4 bytes payload
    case long = 0x11      // 20 bytes total, 17 bytes payload
    case veryLong = 0x12  // 64 bytes total, 61 bytes payload

    /// Total report size including report ID byte.
    var reportLength: Int {
        switch self {
        case .short: return 7
        case .long: return 20
        case .veryLong: return 64
        }
    }

    /// Maximum parameter bytes that fit in this report type.
    var maxParams: Int {
        // Total - reportID(1) - deviceIndex(1) - featureIndex(1) - funcId+swId(1)
        return reportLength - 4
    }

    /// Select the smallest report type that fits the given parameter count.
    static func select(forParamCount count: Int) -> ReportID {
        if count <= ReportID.short.maxParams {
            return .short
        } else if count <= ReportID.long.maxParams {
            return .long
        } else {
            return .veryLong
        }
    }
}

// MARK: - HID++ Request

/// Builds a raw HID++ 2.0 request packet.
struct HIDPPRequest: Sendable {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionId: UInt8
    let softwareId: UInt8
    let params: [UInt8]

    /// The report ID chosen based on parameter length.
    var reportId: ReportID {
        ReportID.select(forParamCount: params.count)
    }

    /// Serialize to raw bytes for IOKit HIDDeviceSetReport.
    /// Returns the full report including report ID as first byte.
    func serialize() -> [UInt8] {
        let rid = reportId
        var data = [UInt8](repeating: 0, count: rid.reportLength)

        data[0] = rid.rawValue
        data[1] = deviceIndex
        data[2] = featureIndex
        data[3] = (functionId << 4) | (softwareId & 0x0F)

        for (i, byte) in params.prefix(rid.maxParams).enumerated() {
            data[4 + i] = byte
        }

        return data
    }
}

// MARK: - HID++ Response

/// Parsed HID++ 2.0 response packet.
struct HIDPPResponse: Sendable {
    let reportId: ReportID
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionId: UInt8
    let softwareId: UInt8
    let params: [UInt8]

    /// Whether this is an HID++ 2.0 error response (feature index 0xFF).
    var isError: Bool {
        featureIndex == 0xFF
    }

    /// Whether this is an HID++ 1.0 error response (feature index 0x8F).
    /// HID++ 1.0 errors use sub-ID 0x8F with error code in params[1].
    var isHidpp10Error: Bool {
        featureIndex == 0x8F
    }

    /// Whether this is any kind of error response.
    var isAnyError: Bool {
        isError || isHidpp10Error
    }

    /// If this is an error response, the error code.
    /// HID++ 2.0: featureIndex=0xFF, errorCode in params[1]
    /// HID++ 1.0: featureIndex=0x8F, errorCode in params[1]
    var errorCode: UInt8? {
        guard isAnyError, params.count >= 2 else { return nil }
        return params[1]
    }

    /// The feature index that caused the error (params[0] in error responses).
    var errorFeatureIndex: UInt8? {
        guard isAnyError, params.count >= 1 else { return nil }
        return params[0]
    }

    /// Parse raw report bytes into a response.
    /// - Parameter data: Raw bytes from HID input report callback.
    /// - Returns: Parsed response, or nil if data is too short or has unknown report ID.
    static func parse(_ data: [UInt8]) -> HIDPPResponse? {
        guard data.count >= 4 else { return nil }
        guard let rid = ReportID(rawValue: data[0]) else { return nil }
        guard data.count >= rid.reportLength else { return nil }

        let params = Array(data[4..<rid.reportLength])

        return HIDPPResponse(
            reportId: rid,
            deviceIndex: data[1],
            featureIndex: data[2],
            functionId: (data[3] >> 4) & 0x0F,
            softwareId: data[3] & 0x0F,
            params: params
        )
    }

    /// Parse from Data (convenience for IOKit callbacks).
    static func parse(_ data: Data) -> HIDPPResponse? {
        parse([UInt8](data))
    }
}
