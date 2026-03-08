import Foundation

/// HID++ 2.0 FeatureSet (0x0001) — enumerate all features on a device.
enum FeatureSetFeature {

    static let featureId: UInt16 = 0x0001

    // MARK: - Function 0: GetCount

    /// Get the total number of features on the device.
    static func getCount(
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

    // MARK: - Function 1: GetFeatureId

    /// Get the feature ID at a given index.
    static func getFeatureId(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        index: UInt8
    ) async throws -> (featureId: UInt16, type: UInt8) {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [index]
        )

        let featureId = (UInt16(response.params[0]) << 8) | UInt16(response.params[1])
        let type = response.params.count > 2 ? response.params[2] : 0

        return (featureId: featureId, type: type)
    }

    // MARK: - Enumerate All

    struct FeatureEntry: Sendable, CustomStringConvertible {
        let featureId: UInt16
        let index: UInt8
        let type: UInt8    // 0=normal, bit0=software, bit1=hidden, bit2=obsolete

        var isHidden: Bool { (type & 0x02) != 0 }
        var isObsolete: Bool { (type & 0x04) != 0 }

        var description: String {
            var flags = ""
            if isHidden { flags += " [hidden]" }
            if isObsolete { flags += " [obsolete]" }
            return String(format: "  [%2d] 0x%04X%@", index, featureId, flags)
        }
    }

    /// Enumerate all features on the device.
    ///
    /// 1. Resolves FeatureSet (0x0001) index via Root feature.
    /// 2. Calls GetCount to know how many features.
    /// 3. Iterates GetFeatureId for each index.
    ///
    /// - Returns: Array of (featureId, runtime index, type flags).
    static func enumerateAll(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndexCache: FeatureIndexCache
    ) async throws -> [FeatureEntry] {
        // Resolve FeatureSet index
        let fsIndex = try await featureIndexCache.resolve(
            featureId: featureId,
            transport: transport,
            deviceIndex: deviceIndex
        )

        // Get count
        let count = try await getCount(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: fsIndex
        )

        // Enumerate each
        var entries: [FeatureEntry] = []
        entries.reserveCapacity(count)

        for i in 0..<UInt8(count) {
            let result = try await getFeatureId(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: fsIndex,
                index: i
            )

            let entry = FeatureEntry(
                featureId: result.featureId,
                index: i,
                type: result.type
            )
            entries.append(entry)

            // Cache the mapping
            await featureIndexCache.set(result.featureId, index: i)
        }

        return entries
    }
}
