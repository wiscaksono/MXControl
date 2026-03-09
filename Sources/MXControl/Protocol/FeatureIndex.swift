import Foundation

/// Thread-safe per-device cache mapping HID++ feature IDs to their runtime indices.
///
/// Each HID++ 2.0 device assigns features to runtime indices that may differ between
/// devices and firmware versions. This cache stores the mapping after discovery.
actor FeatureIndexCache {
    private var cache: [UInt16: UInt8] = [:]

    /// Get cached index for a feature ID. Returns nil if not cached.
    func get(_ featureId: UInt16) -> UInt8? {
        cache[featureId]
    }

    /// Store a feature ID -> index mapping.
    func set(_ featureId: UInt16, index: UInt8) {
        cache[featureId] = index
    }

    /// Store multiple mappings at once.
    func setAll(_ mappings: [(featureId: UInt16, index: UInt8)]) {
        for mapping in mappings {
            cache[mapping.featureId] = mapping.index
        }
    }

    /// Get index for a feature, resolving via RootFeature if not cached.
    /// This requires a transport and device index to query the device.
    func resolve(
        featureId: UInt16,
        transport: HIDTransport,
        deviceIndex: UInt8
    ) async throws -> UInt8 {
        if let cached = cache[featureId] {
            return cached
        }

        let result = try await RootFeature.getFeature(
            transport: transport,
            deviceIndex: deviceIndex,
            featureId: featureId
        )

        guard result.index != 0 else {
            throw HIDPPError.featureNotSupported(featureId)
        }

        cache[featureId] = result.index
        return result.index
    }

    /// Clear all cached mappings.
    func clear() {
        cache.removeAll()
    }

    /// All cached entries.
    var all: [UInt16: UInt8] {
        cache
    }

    /// Copy all entries from another cache (used when promoting a probe to a typed device).
    func transferFrom(_ other: FeatureIndexCache) async {
        let entries = await other.all
        for (featureId, index) in entries {
            cache[featureId] = index
        }
    }
}
