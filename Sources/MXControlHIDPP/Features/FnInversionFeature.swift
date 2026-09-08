import Foundation

/// HID++ 2.0 Fn Key Inversion (0x40A0 / 0x40A2 / 0x40A3).
///
/// Controls whether the top row keys act as F1-F12 by default (Fn inverted)
/// or as media/special keys (normal).
///
/// Two protocol variants:
///
/// **Classic (0x40A0 / 0x40A2):**
///   fn 0x00 = getState  → response[0] bit 0 = inverted
///   fn 0x01 = setState  → params[0] = 0x01 (inverted) or 0x00
///
/// **Enhanced (0x40A3) — per Solaar K375sFnSwap:**
///   fn 0x00 = READ  → params=[hostByte], response = [hostByte(skip), fnState, defaultState]
///   fn 0x01 = WRITE → params=[hostByte, fnState, defaultState]
///   hostByte = 0xFF = current host
///   defaultState must be preserved from last read to avoid clobbering it.
public enum FnInversionFeature {

    /// Feature IDs — probe in order: 0x40A3 (v3), 0x40A2 (v2), 0x40A0 (v0).
    public static let featureIdV3: UInt16 = 0x40A3
    public static let featureIdV2: UInt16 = 0x40A2
    public static let featureIdV0: UInt16 = 0x40A0

    /// All feature IDs to probe, in preference order.
    public static let allFeatureIds: [UInt16] = [featureIdV3, featureIdV2, featureIdV0]

    /// Whether a feature ID uses the enhanced (0x40A3) protocol.
    public static func isEnhanced(_ featureId: UInt16) -> Bool {
        featureId == featureIdV3
    }

    // MARK: - State

    public struct FnState: Sendable {
        /// Whether Fn inversion is active (true = F1-F12 default, false = media keys default).
        public let fnInverted: Bool
        /// Factory-default state byte from enhanced protocol. Must be echoed back on writes.
        /// Always 0 for classic protocol.
        public let defaultState: UInt8
    }

    // MARK: - Classic Protocol (0x40A0 / 0x40A2)

    /// Get current Fn inversion state (classic protocol).
    ///
    /// Response: param[0] bit 0 = fn inverted state.
    private static func getStateClassic(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> FnState {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return FnState(
            fnInverted: (response.params[0] & 0x01) != 0,
            defaultState: 0
        )
    }

    /// Set Fn inversion state (classic protocol).
    private static func setStateClassic(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        fnInverted: Bool
    ) async throws {
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [fnInverted ? 0x01 : 0x00]
        )
    }

    // MARK: - Enhanced Protocol (0x40A3)

    /// Get current Fn inversion state (enhanced protocol).
    ///
    /// Sends params=[0xFF] (current host prefix).
    /// Response: [hostByte(skip), fnState, defaultState]
    private static func getStateEnhanced(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> FnState {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01,
            params: [0xFF]  // 0xFF = current host
        )

        let params = response.params
        // params[0] = host prefix byte (skip — read_skip_byte_count=1)
        // params[1] = fnInverted (0x00 = not inverted, 0x01 = inverted)
        // params[2] = defaultState (must be preserved on writes)
        let hex = params.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        debugLog("[FnInversion] getStateEnhanced raw params: [\(hex)]")
        guard params.count >= 3 else {
            return FnState(fnInverted: false, defaultState: 0)
        }

        let inverted = (params[1] & 0x01) != 0
        debugLog("[FnInversion] getStateEnhanced: fnByte=\(String(format: "0x%02X", params[1])) → fnInverted=\(inverted) defaultState=\(params[2])")
        return FnState(
            fnInverted: inverted,
            defaultState: params[2]
        )
    }

    /// Set Fn inversion state (enhanced protocol).
    ///
    /// Params: [0xFF, fnState, defaultState]
    ///   0xFF = current host
    ///   fnState = 0x01 (inverted) or 0x00 (normal)
    ///   defaultState = pass from last known read to avoid clobbering it
    private static func setStateEnhanced(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        fnInverted: Bool,
        defaultState: UInt8
    ) async throws {
        let fnByte: UInt8 = fnInverted ? 0x01 : 0x00
        debugLog("[FnInversion] setStateEnhanced: fnInverted=\(fnInverted) → fnByte=\(String(format: "0x%02X", fnByte)) defaultState=\(defaultState)")
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [0xFF, fnByte, defaultState]
        )
    }

    // MARK: - Public API (auto-dispatches based on feature ID)

    /// Get current Fn inversion state. Auto-dispatches based on feature ID.
    public static func getState(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        featureId: UInt16
    ) async throws -> FnState {
        if isEnhanced(featureId) {
            return try await getStateEnhanced(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex
            )
        } else {
            return try await getStateClassic(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex
            )
        }
    }

    /// Set Fn inversion state. Auto-dispatches based on feature ID.
    public static func setState(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        featureId: UInt16,
        fnInverted: Bool,
        defaultState: UInt8 = 0
    ) async throws {
        if isEnhanced(featureId) {
            try await setStateEnhanced(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                fnInverted: fnInverted,
                defaultState: defaultState
            )
        } else {
            try await setStateClassic(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                fnInverted: fnInverted
            )
        }
    }
}
