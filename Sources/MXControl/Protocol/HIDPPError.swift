import Foundation

/// Errors from HID++ communication.
enum HIDPPError: Error, LocalizedError, Sendable {
    // Transport errors
    case transportNotOpen
    case transportError(String)
    case tccDenied
    case exclusiveAccess
    case timeout
    case deviceNotFound

    // Protocol errors
    case invalidResponse
    case featureNotSupported(UInt16)
    case unknownReportId(UInt8)

    // HID++ 2.0 error codes (from device)
    case hidppError(code: HIDPPErrorCode, featureIndex: UInt8)

    var errorDescription: String? {
        switch self {
        case .transportNotOpen:
            return "Transport is not open"
        case .transportError(let msg):
            return "Transport error: \(msg)"
        case .tccDenied:
            return "Input Monitoring permission required — grant access in System Settings > Privacy & Security > Input Monitoring"
        case .exclusiveAccess:
            return "Another process has exclusive access to HID devices — quit Logi Options+ or similar apps and retry"
        case .timeout:
            return "Request timed out"
        case .deviceNotFound:
            return "Device not found"
        case .invalidResponse:
            return "Invalid HID++ response"
        case .featureNotSupported(let id):
            return String(format: "Feature 0x%04X not supported", id)
        case .unknownReportId(let id):
            return String(format: "Unknown report ID: 0x%02X", id)
        case .hidppError(let code, let idx):
            return String(format: "HID++ error %d (%@) on feature index 0x%02X", code.rawValue, code.name, idx)
        }
    }
}

/// HID++ 2.0 device error codes.
enum HIDPPErrorCode: UInt8, Sendable {
    case noError = 0x00
    case unknown = 0x01
    case invalidArgument = 0x02
    case outOfRange = 0x03
    case hardwareError = 0x04
    case notAllowed = 0x05
    case invalidFeatureIndex = 0x06
    case invalidFunctionId = 0x07
    case busy = 0x08
    case unsupported = 0x09

    var name: String {
        switch self {
        case .noError: return "No Error"
        case .unknown: return "Unknown"
        case .invalidArgument: return "Invalid Argument"
        case .outOfRange: return "Out of Range"
        case .hardwareError: return "Hardware Error"
        case .notAllowed: return "Not Allowed"
        case .invalidFeatureIndex: return "Invalid Feature Index"
        case .invalidFunctionId: return "Invalid Function ID"
        case .busy: return "Busy"
        case .unsupported: return "Unsupported"
        }
    }
}
