import Foundation

/// HID++ 2.0 Change Host (0x1814) — Easy-Switch host selection.
///
/// Functions:
///   0: getHostCount()   -> number of hosts + current host index
///   1: setHost(index)   -> switch to host (WARNING: changes active connection)
enum ChangeHostFeature {

    static let featureId: UInt16 = 0x1814

    // MARK: - Host Info

    struct HostInfo: Sendable {
        /// Total number of available hosts (typically 3 for Easy-Switch).
        let hostCount: Int
        /// Currently connected host index (0-based).
        let currentHost: Int
    }

    // MARK: - Function 0: GetHostInfo

    /// Get host count and current host index.
    ///
    /// Response:
    ///   param[0]: number of hosts
    ///   param[1]: current host index (0-based)
    static func getHostInfo(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> HostInfo {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return HostInfo(
            hostCount: Int(response.params[0]),
            currentHost: Int(response.params[1])
        )
    }

    // MARK: - Function 1: SetHost

    /// Switch to a different host.
    ///
    /// WARNING: This changes the active Bluetooth/receiver connection.
    /// The device will disconnect from the current host.
    ///
    /// - Parameter hostIndex: 0-based host index to switch to.
    static func setHost(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        hostIndex: Int
    ) async throws {
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [UInt8(clamping: hostIndex)]
        )
    }
}
