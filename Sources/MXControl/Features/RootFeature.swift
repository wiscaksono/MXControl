import Foundation

/// HID++ 2.0 Root Feature (0x0000) — always at index 0.
///
/// Provides feature discovery, ping, and protocol version detection.
enum RootFeature {

    /// Feature ID is 0x0000, always mapped to index 0.
    static let featureIndex: UInt8 = 0x00

    // MARK: - Function 0: GetFeature

    struct FeatureInfo: Sendable {
        let index: UInt8
        let type: UInt8      // bit flags: software(0), hidden(1), obsolete(2)
        let version: UInt8
    }

    /// Query the device for a feature's runtime index.
    ///
    /// - Parameters:
    ///   - transport: HID++ transport to use.
    ///   - deviceIndex: Device index (1-6 for receiver sub-devices).
    ///   - featureId: The 16-bit feature ID to look up (e.g., 0x1004 for battery).
    /// - Returns: Feature info with runtime index, type flags, and version.
    static func getFeature(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureId: UInt16
    ) async throws -> FeatureInfo {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01,
            params: [
                UInt8((featureId >> 8) & 0xFF),
                UInt8(featureId & 0xFF),
            ]
        )

        return FeatureInfo(
            index: response.params[0],
            type: response.params[1],
            version: response.params.count > 2 ? response.params[2] : 0
        )
    }

    // MARK: - Function 1: Ping

    struct PingResult: Sendable {
        let protocolMajor: UInt8
        let protocolMinor: UInt8
        let pingData: UInt8
    }

    /// Ping the device and get protocol version.
    ///
    /// This verifies the device is alive and speaks HID++ 2.0.
    ///
    /// - Parameters:
    ///   - transport: HID++ transport to use.
    ///   - deviceIndex: Device index to ping.
    ///   - pingData: Arbitrary byte echoed back by device (default 0xAA).
    /// - Returns: Protocol version and echoed ping data.
    static func ping(
        transport: HIDTransport,
        deviceIndex: UInt8,
        pingData: UInt8 = 0xAA
    ) async throws -> PingResult {
        // Ping uses a short report with pingData in the 3rd param byte
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [0x00, 0x00, pingData]
        )

        return PingResult(
            protocolMajor: response.params[0],
            protocolMinor: response.params[1],
            pingData: response.params[2]
        )
    }

    // MARK: - Function 2: GetCount

    /// Get the number of features on the device.
    static func getCount(
        transport: HIDTransport,
        deviceIndex: UInt8
    ) async throws -> Int {
        // GetCount is via FeatureSet (0x0001), but Root's function 2 also works
        // on some devices. We'll use FeatureSet for reliability.
        // This is a convenience that queries root feature index 0, function 2.
        let featureSetInfo = try await getFeature(
            transport: transport,
            deviceIndex: deviceIndex,
            featureId: 0x0001
        )

        guard featureSetInfo.index != 0 else {
            throw HIDPPError.featureNotSupported(0x0001)
        }

        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureSetInfo.index,
            functionId: 0x00,
            softwareId: 0x01
        )

        return Int(response.params[0])
    }
}
