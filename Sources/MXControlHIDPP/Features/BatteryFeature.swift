import Foundation

/// HID++ 2.0 UnifiedBattery (0x1004) — battery level, charging state, SoC.
///
/// Functions:
///   0: getCapabilities() -> flags (rechargeable, state of charge)
///   1: getStatus()       -> level %, flags, charging state
///
/// Events:
///   0: battery status change notification
public enum BatteryFeature {

    public static let featureId: UInt16 = 0x1004

    // MARK: - Charging Status

    /// Battery charging states from HID++ 2.0 UnifiedBattery.
    public enum ChargingStatus: UInt8, Sendable, CustomStringConvertible {
        case discharging = 0
        case charging = 1
        case chargingSlowly = 2  // slow charge (e.g., low-power USB)
        case chargingComplete = 3
        case chargingError = 4

        public var description: String {
            switch self {
            case .discharging: return "Discharging"
            case .charging: return "Charging"
            case .chargingSlowly: return "Charging (slow)"
            case .chargingComplete: return "Fully Charged"
            case .chargingError: return "Charging Error"
            }
        }

        public var isCharging: Bool {
            switch self {
            case .charging, .chargingSlowly, .chargingComplete:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Battery Level

    /// Battery level categories from the status flags.
    public enum BatteryLevel: UInt8, Sendable, CustomStringConvertible {
        case critical = 0   // < 10%
        case low = 1        // 10-30%
        case good = 2       // 30-80%
        case full = 3       // > 80%

        public var description: String {
            switch self {
            case .critical: return "Critical"
            case .low: return "Low"
            case .good: return "Good"
            case .full: return "Full"
            }
        }
    }

    // MARK: - Status Result

    public struct Status: Sendable {
        /// Battery percentage (0-100). May be 0 if SoC not supported.
        public let level: Int
        /// Coarse battery level category.
        public let batteryLevel: BatteryLevel
        /// Current charging status.
        public let chargingStatus: ChargingStatus
        /// Whether the battery supports state of charge (percentage).
        public let hasSoC: Bool
    }

    // MARK: - Capabilities

    public struct Capabilities: Sendable {
        /// Supported battery levels bitmap.
        public let supportedLevels: UInt8
        /// Capability flags.
        public let flags: UInt8

        /// Whether the device reports state of charge (percentage).
        public var hasSoC: Bool { (flags & 0x02) != 0 }
        /// Whether the device is rechargeable.
        public var isRechargeable: Bool { (flags & 0x01) != 0 }
    }

    // MARK: - Function 0: GetCapabilities

    /// Get battery capabilities (rechargeable, SoC support).
    public static func getCapabilities(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Capabilities {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return Capabilities(
            supportedLevels: response.params[0],
            flags: response.params[1]
        )
    }

    // MARK: - Function 1: GetStatus

    /// Get current battery status (level, charging state).
    ///
    /// Response format:
    ///   param[0]: state of charge (0-100%)
    ///   param[1]: battery level (0=critical, 1=low, 2=good, 3=full)
    ///   param[2]: charging status (0=discharging, 1=charging, etc.)
    ///   param[3]: external power status
    public static func getStatus(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Status {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01
        )

        let soc = Int(response.params[0])
        let level = BatteryLevel(rawValue: response.params[1]) ?? .good
        let charging = ChargingStatus(rawValue: response.params[2]) ?? .discharging

        return Status(
            level: soc,
            batteryLevel: level,
            chargingStatus: charging,
            hasSoC: soc > 0  // If device reports 0, SoC may not be supported
        )
    }
}
