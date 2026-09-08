import Foundation
import MXControlHIDPP
import os

/// Shared SpecialKeys divert operations.
///
/// Thumb-gesture, side-button, and mic-mute wiring all divert controls
/// through `0x1B04` with slightly different flags. Centralizing here keeps
/// the volatile/persist/remap contract in one place: diverts are volatile
/// unless explicitly requested, so keys recover when MXControl is not
/// running.
@MainActor
enum DivertService {

    /// Enumerate all remappable controls on the device.
    static func enumerate(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> [SpecialKeysFeature.ControlInfo] {
        try await SpecialKeysFeature.enumerateControls(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex
        )
    }

    /// Divert one control to software.
    static func divert(
        _ controlId: UInt16,
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        persistDivert: Bool = false,
        rawXY: Bool? = nil,
        remapTarget: UInt16 = 0
    ) async throws {
        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            controlId: controlId,
            divert: true,
            persistDivert: persistDivert,
            rawXY: rawXY,
            remapTarget: remapTarget
        )
        debugLog("[DivertService] Diverted CID 0x\(String(format: "%04X", controlId)) (persist=\(persistDivert))")
    }

    /// Release a diverted control back to hardware behavior.
    static func undivert(
        _ controlId: UInt16,
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws {
        try await SpecialKeysFeature.setCtrlIdReporting(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            controlId: controlId,
            divert: false,
            persistDivert: false
        )
        debugLog("[DivertService] Undiverted CID 0x\(String(format: "%04X", controlId))")
    }

    /// Read the current remap target so divert can preserve it.
    static func remapTarget(
        _ controlId: UInt16,
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> UInt16 {
        try await SpecialKeysFeature.getCtrlIdReporting(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            controlId: controlId
        ).remapTarget
    }
}
