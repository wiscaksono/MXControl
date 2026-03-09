import Foundation

/// HID++ 2.0 Keyboard Backlight (0x1982 Backlight v2 / 0x1983 Backlight v3).
///
/// The MX Keys Mini uses 0x1982 (BACKLIGHT2).
///
/// **0x1982 (BACKLIGHT2) response format** (per Solaar, little-endian struct):
///   fn 0x00 getBacklightConfig():
///     Byte 0:    enabled (0/1)
///     Byte 1:    options (bits [4:3] = mode: 0=off, 1=auto, 2=temp, 3=manual)
///     Byte 2:    supported capabilities flags
///     Byte 3-4:  effects (LE uint16)
///     Byte 5:    level (0-N, only meaningful in manual mode)
///     Byte 6-7:  dho - duration hands out (LE uint16, units of 5 seconds)
///     Byte 8-9:  dhi - duration hands in (LE uint16, units of 5 seconds)
///     Byte 10-11: dpow - duration powered (LE uint16, units of 5 seconds)
///
///   fn 0x10 setBacklightConfig():
///     Byte 0:    enabled (0/1)
///     Byte 1:    options
///     Byte 2:    0xFF (effect = no change)
///     Byte 3:    level
///     Byte 4-5:  dho (LE uint16)
///     Byte 6-7:  dhi (LE uint16)
///     Byte 8-9:  dpow (LE uint16)
///
/// **0x1983 (BACKLIGHT3) — simpler:**
///   fn 0x00: param[0] = mode, param[1] = level
///   fn 0x01: param[0] = mode, param[1] = level
enum BacklightFeature {

    /// Feature IDs — probe 0x1983 first (v3), fall back to 0x1982 (v2).
    static let featureIdV3: UInt16 = 0x1983
    static let featureIdV2: UInt16 = 0x1982

    // MARK: - Backlight Mode (0x1982)

    /// Backlight operating mode from the options byte.
    enum BacklightMode: Int, Sendable {
        case off = 0
        case automatic = 1
        case temporary = 2   // turns on temporarily on keypress
        case manual = 3      // fixed level, controlled by user
    }

    // MARK: - Backlight Configuration

    struct BacklightConfig: Sendable {
        /// Master enabled flag.
        let enabled: Bool
        /// Raw options byte (preserve for write-back).
        let options: UInt8
        /// Supported capability flags.
        let supported: UInt8
        /// Operating mode extracted from options bits [4:3].
        let mode: BacklightMode
        /// Current brightness level (0-N).
        let level: Int
        /// Duration hands out (in 5-second units, LE).
        let dho: UInt16
        /// Duration hands in (in 5-second units, LE).
        let dhi: UInt16
        /// Duration powered (in 5-second units, LE).
        let dpow: UInt16

        /// Whether auto-brightness is supported.
        var autoSupported: Bool { (supported & 0x08) != 0 }
        /// Whether temporary mode is supported.
        var tempSupported: Bool { (supported & 0x10) != 0 }
        /// Whether permanent/manual mode is supported.
        var permSupported: Bool { (supported & 0x20) != 0 }
    }

    // MARK: - Function 0: GetBacklightConfig

    /// Get current backlight configuration.
    static func getBacklightConfig(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        featureId: UInt16
    ) async throws -> BacklightConfig {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        let params = response.params

        if featureId == featureIdV2 {
            // 0x1982 — complex 12-byte little-endian struct
            return parseV2Config(params)
        } else {
            // 0x1983 — simpler format
            return parseV3Config(params)
        }
    }

    /// Parse 0x1982 (BACKLIGHT2) response.
    private static func parseV2Config(_ params: [UInt8]) -> BacklightConfig {
        let enabled = params.count > 0 ? params[0] : 0
        let options = params.count > 1 ? params[1] : 0
        let supported = params.count > 2 ? params[2] : 0
        // effects at [3-4] — skip (LE uint16)
        let level = params.count > 5 ? Int(params[5]) : 0
        // dho at [6-7] LE
        let dho: UInt16 = params.count > 7
            ? (UInt16(params[7]) << 8) | UInt16(params[6])
            : 0
        // dhi at [8-9] LE
        let dhi: UInt16 = params.count > 9
            ? (UInt16(params[9]) << 8) | UInt16(params[8])
            : 0
        // dpow at [10-11] LE
        let dpow: UInt16 = params.count > 11
            ? (UInt16(params[11]) << 8) | UInt16(params[10])
            : 0

        let modeRaw = Int((options >> 3) & 0x03)
        let mode = BacklightMode(rawValue: modeRaw) ?? .off

        return BacklightConfig(
            enabled: enabled != 0,
            options: options,
            supported: supported,
            mode: mode,
            level: level,
            dho: dho,
            dhi: dhi,
            dpow: dpow
        )
    }

    /// Parse 0x1983 (BACKLIGHT3) response.
    private static func parseV3Config(_ params: [UInt8]) -> BacklightConfig {
        let enabled = params.count > 0 ? params[0] != 0 : false
        let level = params.count > 1 ? Int(params[1]) : 0

        return BacklightConfig(
            enabled: enabled,
            options: 0,
            supported: 0x38,  // assume all supported
            mode: enabled ? .manual : .off,
            level: level,
            dho: 0,
            dhi: 0,
            dpow: 0
        )
    }

    // MARK: - Function 1 (0x10): SetBacklightConfig

    /// Set backlight configuration.
    ///
    /// For 0x1982: writes the full struct back to the device.
    /// For 0x1983: simple [mode, level] write.
    static func setBacklightConfig(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        featureId: UInt16,
        enabled: Bool,
        mode: BacklightMode,
        level: Int,
        currentOptions: UInt8,
        dho: UInt16,
        dhi: UInt16,
        dpow: UInt16
    ) async throws {
        if featureId == featureIdV2 {
            try await setBacklightV2(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                enabled: enabled,
                mode: mode,
                level: level,
                currentOptions: currentOptions,
                dho: dho,
                dhi: dhi,
                dpow: dpow
            )
        } else {
            try await setBacklightV3(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                enabled: enabled,
                level: level
            )
        }
    }

    /// Write 0x1982 backlight config.
    ///
    /// Params: [enabled, options, 0xFF(effect no-change), level, dho_lo, dho_hi, dhi_lo, dhi_hi, dpow_lo, dpow_hi]
    private static func setBacklightV2(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        enabled: Bool,
        mode: BacklightMode,
        level: Int,
        currentOptions: UInt8,
        dho: UInt16,
        dhi: UInt16,
        dpow: UInt16
    ) async throws {
        // Rebuild options byte: preserve low 3 bits, set mode in bits [4:3]
        let options = (currentOptions & 0x07) | (UInt8(mode.rawValue) << 3)
        // Level is only meaningful in manual mode (3)
        let effectiveLevel = mode == .manual ? UInt8(clamping: level) : 0

        let params: [UInt8] = [
            enabled ? 0x01 : 0x00,
            options,
            0xFF,                           // effect = no change
            effectiveLevel,
            UInt8(dho & 0xFF),              // dho low byte (LE)
            UInt8((dho >> 8) & 0xFF),       // dho high byte
            UInt8(dhi & 0xFF),              // dhi low byte (LE)
            UInt8((dhi >> 8) & 0xFF),       // dhi high byte
            UInt8(dpow & 0xFF),             // dpow low byte (LE)
            UInt8((dpow >> 8) & 0xFF),      // dpow high byte
        ]

        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: params
        )
    }

    /// Write 0x1983 backlight config (simple).
    private static func setBacklightV3(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        enabled: Bool,
        level: Int
    ) async throws {
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [
                enabled ? 0x01 : 0x00,
                UInt8(clamping: level),
            ]
        )
    }

    // MARK: - Function 2 (0x20): GetBacklightLevelRange (v2 only)

    /// Get the maximum backlight level (v2/v3 with min_version 3).
    /// Response[0] = number of levels (max_level = response[0] - 1).
    static func getBacklightLevelCount(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Int {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01
        )

        return Int(response.params[0])
    }
}
