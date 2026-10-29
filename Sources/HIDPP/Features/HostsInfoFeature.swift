import Foundation

/// HID++ 2.0 Hosts Info (0x1815) — multi-host slots and pairing status.
///
/// Wire format per OpenLogi `0x1815 hostsInfo` (Logitech HID++ 2.0):
///
/// Functions:
///   0: getFeatureInfo()          -> caps, descriptor caps, slot count, current slot
///   1: getHostInfo(host)         -> status, bus type, page/name lengths
///   2: getHostDescriptor(h,p)    -> raw descriptor page (names live here;
///                                   byte layout unspecified, so names fall
///                                   back to "Slot N")
///
/// There is deliberately no OS-type field: the spec has none (an earlier
/// revision of this file invented ones from the wrong bytes).
public enum HostsInfoFeature {

    public static let featureId: UInt16 = 0x1815

    // MARK: - Bus Type

    public enum BusType: UInt8, Sendable, CustomStringConvertible {
        case undefined = 0
        case equad = 1
        case usb = 2
        case bluetoothClassic = 3
        case ble = 4
        case blePro = 5      // Logi Bolt

        public var description: String {
            switch self {
            case .undefined: return "Unknown"
            case .equad: return "Receiver"
            case .usb: return "USB"
            case .bluetoothClassic: return "Bluetooth"
            case .ble: return "Bluetooth LE"
            case .blePro: return "Bolt"
            }
        }
    }

    // MARK: - Slot Status

    public enum SlotStatus: UInt8, Sendable {
        case empty = 0
        case paired = 1
    }

    // MARK: - Feature Info

    public struct FeatureInfo: Sendable {
        /// GET_NAME bit allows reading friendly names (unused: layout unspecified).
        public let canGetName: Bool
        /// Total number of host slots.
        public let hostCount: Int
        /// Currently active slot.
        public let currentHost: Int
    }

    // MARK: - Host Slot

    public struct HostSlot: Sendable {
        public let index: Int
        public let paired: Bool
        public let busType: BusType
    }

    // MARK: - Host Entry (UI model)

    public struct HostEntry: Sendable, Identifiable {
        public let index: Int
        /// Display name. "Slot N" — descriptor-page name decoding is
        /// unspecified, so friendly names are not read.
        public var name: String
        public let busType: BusType
        /// Whether this host slot is paired.
        public let isPaired: Bool

        public var id: Int { index }

        public init(index: Int, name: String, busType: BusType, isPaired: Bool) {
            self.index = index
            self.name = name
            self.busType = busType
            self.isPaired = isPaired
        }
    }

    // MARK: - Function 0: GetFeatureInfo

    /// Get slot count, current slot, and capabilities.
    ///
    /// Response:
    ///   param[0]: capabilities (bit 0 = GET_NAME)
    ///   param[1]: descriptor capabilities
    ///   param[2]: host slot count
    ///   param[3]: current slot (0xFF = unknown, treated as slot 0)
    public static func getFeatureInfo(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> FeatureInfo {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        let params = response.params
        guard params.count >= 4 else {
            throw HIDPPError.transportError("Truncated hosts-info (\(params.count) bytes)")
        }
        let current = Int(params[3])
        return FeatureInfo(
            canGetName: (params[0] & 0x01) != 0,
            hostCount: Int(params[2]),
            currentHost: current == 0xFF ? 0 : current
        )
    }

    // MARK: - Function 1: GetHostInfo

    /// Get pairing status and bus type for one slot.
    ///
    /// Request: `[host, 0x00, 0x00]`.
    /// Response:
    ///   param[0]: slot echo
    ///   param[1]: status (0 = empty, 1 = paired)
    ///   param[2]: bus type
    ///   param[3]: descriptor page count
    ///   param[4]: friendly-name length
    ///   param[5]: friendly-name max length
    public static func getHostInfo(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        hostIndex: Int
    ) async throws -> HostSlot {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [UInt8(clamping: hostIndex), 0x00, 0x00]
        )

        let params = response.params
        guard params.count >= 6 else {
            throw HIDPPError.transportError("Truncated host info (\(params.count) bytes)")
        }
        guard Int(params[0]) == hostIndex else {
            throw HIDPPError.transportError("Host slot echo mismatch (want \(hostIndex), got \(params[0]))")
        }
        return HostSlot(
            index: hostIndex,
            paired: params[1] == SlotStatus.paired.rawValue,
            busType: BusType(rawValue: params[2]) ?? .undefined
        )
    }

    // MARK: - Convenience: Get All Hosts

    /// Maximum sane slot count. A corrupt count byte must not fan out into
    /// hundreds of sequential requests and UI rows.
    private static let maxSlots = 16

    /// Enumerate all host slots. Names are "Slot N" — friendly-name decoding
    /// from descriptor pages is unspecified, so it is not attempted.
    public static func enumerateHosts(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> (hosts: [HostEntry], currentHost: Int) {
        let info = try await getFeatureInfo(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex
        )

        let count = min(info.hostCount, maxSlots)
        if count != info.hostCount {
            debugLog("[HostsInfo] Clamping implausible slot count \(info.hostCount) to \(maxSlots)")
        }

        var hosts: [HostEntry] = []
        for i in 0..<count {
            let slot = try await getHostInfo(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                hostIndex: i
            )
            hosts.append(HostEntry(
                index: i,
                name: "Slot \(i + 1)",
                busType: slot.busType,
                isPaired: slot.paired
            ))
        }

        // Clamp: a corrupt current value must not index out of range.
        let current = hosts.isEmpty ? 0 : min(info.currentHost, hosts.count - 1)
        return (hosts, current)
    }
}
