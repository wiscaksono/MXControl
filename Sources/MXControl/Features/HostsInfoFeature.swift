import Foundation

/// HID++ 2.0 Hosts Info (0x1815) — information about paired hosts.
///
/// Functions:
///   0: getHostCount()     -> number of hosts
///   1: getHostInfo(idx)   -> host name, bus type, OS type
///   2: getHostDescriptor() -> host name string (multi-chunk)
enum HostsInfoFeature {

    static let featureId: UInt16 = 0x1815

    // MARK: - Bus Type

    enum BusType: UInt8, Sendable, CustomStringConvertible {
        case unknown = 0
        case bluetooth = 1
        case blePro = 2      // Bolt receiver
        case usb = 3

        var description: String {
            switch self {
            case .unknown: return "Unknown"
            case .bluetooth: return "Bluetooth"
            case .blePro: return "Bolt"
            case .usb: return "USB"
            }
        }
    }

    // MARK: - OS Type

    enum OSType: UInt8, Sendable, CustomStringConvertible {
        case unknown = 0
        case windows = 1
        case winEmb = 2
        case linux = 3
        case chrome = 4
        case android = 5
        case macOS = 6
        case iOS = 7

        var description: String {
            switch self {
            case .unknown: return "Unknown"
            case .windows: return "Windows"
            case .winEmb: return "Windows Embedded"
            case .linux: return "Linux"
            case .chrome: return "Chrome OS"
            case .android: return "Android"
            case .macOS: return "macOS"
            case .iOS: return "iOS"
            }
        }
    }

    // MARK: - Host Entry

    struct HostEntry: Sendable, Identifiable {
        let index: Int
        var name: String
        let busType: BusType
        let osType: OSType
        /// Whether this host slot is paired.
        let isPaired: Bool

        var id: Int { index }
    }

    // MARK: - Function 0: GetHostCount

    /// Get the number of host slots.
    static func getHostCount(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Int {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return Int(response.params[0])
    }

    // MARK: - Function 1: GetHostInfo

    /// Get info about a specific host slot.
    ///
    /// Response:
    ///   param[0]: host index echo
    ///   param[1]: bus type
    ///   param[2]: OS type detected
    ///   param[3]: name length
    ///   param[4]: name max length
    ///   param[5]: flags (bit 0 = paired)
    static func getHostInfo(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        hostIndex: Int
    ) async throws -> (busType: BusType, osType: OSType, nameLength: Int, isPaired: Bool) {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [UInt8(clamping: hostIndex)]
        )

        let params = response.params
        let bus = BusType(rawValue: params[1]) ?? .unknown
        let os = OSType(rawValue: params[2]) ?? .unknown
        let nameLen = Int(params[3])
        let flags = params.count > 5 ? params[5] : 0
        let paired = (flags & 0x01) != 0

        return (busType: bus, osType: os, nameLength: nameLen, isPaired: paired)
    }

    // MARK: - Function 2: GetHostDescriptor (Name)

    /// Get a chunk of the host name.
    ///
    /// Response: param[0] = host index, param[1] = offset, param[2...] = name bytes.
    static func getHostNameChunk(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        hostIndex: Int,
        offset: Int
    ) async throws -> String {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [
                UInt8(clamping: hostIndex),
                UInt8(clamping: offset),
            ]
        )

        // Name bytes start at param[2] (after index echo and offset echo)
        let nameBytes = response.params.dropFirst(2).prefix(while: { $0 != 0 })
        return String(bytes: nameBytes, encoding: .utf8) ?? ""
    }

    // MARK: - Convenience: Get All Hosts

    /// Enumerate all host slots with names.
    static func enumerateHosts(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> [HostEntry] {
        let count = try await getHostCount(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex
        )

        var hosts: [HostEntry] = []

        for i in 0..<count {
            let info = try await getHostInfo(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                hostIndex: i
            )

            // Read host name
            var name = ""
            if info.nameLength > 0 {
                var offset = 0
                while name.count < info.nameLength {
                    let chunk = try await getHostNameChunk(
                        transport: transport,
                        deviceIndex: deviceIndex,
                        featureIndex: featureIndex,
                        hostIndex: i,
                        offset: offset
                    )
                    if chunk.isEmpty { break }
                    name += chunk
                    offset = name.count
                }
            }

            hosts.append(HostEntry(
                index: i,
                name: name.isEmpty ? "Host \(i + 1)" : name,
                busType: info.busType,
                osType: info.osType,
                isPaired: info.isPaired
            ))
        }

        return hosts
    }
}
