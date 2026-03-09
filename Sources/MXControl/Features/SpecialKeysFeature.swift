import Foundation

/// HID++ 2.0 Special Keys and Mouse Buttons v4 (0x1B04) — button enumeration + remap + divert.
///
/// Functions:
///   0: getCount()              -> number of remappable controls
///   1: getCtrlIdInfo(index)    -> CID, TID, flags, position, group, gmask
///   2: getCtrlIdReporting(cid) -> divert, remap, raw XY, persist flags
///   3: setCtrlIdReporting(cid) -> set divert, remap, raw XY, persist flags
///
/// Events:
///   0: divertedButtonsEvent -> button press/release for diverted CIDs
enum SpecialKeysFeature {

    static let featureId: UInt16 = 0x1B04

    // MARK: - Control Info

    /// Capability flags for a control (from getCtrlIdInfo).
    struct ControlFlags: OptionSet, Sendable {
        let rawValue: UInt16

        static let mouseButton     = ControlFlags(rawValue: 1 << 0)
        static let fnKey           = ControlFlags(rawValue: 1 << 1)
        static let hotKey          = ControlFlags(rawValue: 1 << 2)
        static let fnToggle        = ControlFlags(rawValue: 1 << 3)
        static let reprogrammable  = ControlFlags(rawValue: 1 << 4)
        static let divertable      = ControlFlags(rawValue: 1 << 5)
        static let persistDivert   = ControlFlags(rawValue: 1 << 6)
        static let virtual_        = ControlFlags(rawValue: 1 << 7)
        static let rawXY           = ControlFlags(rawValue: 1 << 8)
        static let rawWheel        = ControlFlags(rawValue: 1 << 9)
        static let analyticsKey    = ControlFlags(rawValue: 1 << 10)
        static let forceRawXY      = ControlFlags(rawValue: 1 << 11)
    }

    /// Information about a single remappable control.
    struct ControlInfo: Sendable, Identifiable {
        let controlId: UInt16   // CID
        let taskId: UInt16      // TID (default action ID)
        let flags: ControlFlags
        let position: UInt8
        let group: UInt8
        let groupMask: UInt8

        var id: UInt16 { controlId }

        /// Whether this control can be remapped to another action.
        var isRemappable: Bool { flags.contains(.reprogrammable) }

        /// Whether this control can be diverted to software.
        var isDivertable: Bool { flags.contains(.divertable) }
    }

    // MARK: - Reporting State

    /// Current reporting configuration for a control.
    struct ReportingState: Sendable {
        let controlId: UInt16
        /// Whether the control is diverted to software.
        let isDiverted: Bool
        /// Whether divert persists across power cycles.
        let persistDivert: Bool
        /// Whether raw XY reporting is enabled.
        let rawXY: Bool
        /// The remap target CID (0 = default action).
        let remapTarget: UInt16
    }

    // MARK: - Known CIDs (MX Master 3S)

    /// Well-known Control IDs for MX Master 3S buttons.
    enum KnownCID: UInt16, Sendable, CaseIterable, CustomStringConvertible {
        case middleButton = 82
        case backButton = 83
        case forwardButton = 86
        case gestureButton = 195    // Thumb button
        case modeShift = 196         // Wheel mode toggle

        var description: String {
            switch self {
            case .middleButton: return "Middle Click"
            case .backButton: return "Back"
            case .forwardButton: return "Forward"
            case .gestureButton: return "Gesture (Thumb)"
            case .modeShift: return "Mode Shift (Wheel)"
            }
        }
    }

    // MARK: - Remap Actions

    /// Predefined remap target actions.
    /// These are CID values or virtual action IDs that the device understands.
    enum RemapAction: UInt16, Sendable, CaseIterable, CustomStringConvertible {
        case defaultAction = 0      // Restore default behavior
        case middleClick = 82
        case back = 83
        case forward = 86
        case gestureButton = 195
        case smartShiftToggle = 196

        var description: String {
            switch self {
            case .defaultAction: return "Default"
            case .middleClick: return "Middle Click"
            case .back: return "Back"
            case .forward: return "Forward"
            case .gestureButton: return "Gesture"
            case .smartShiftToggle: return "SmartShift Toggle"
            }
        }
    }

    // MARK: - Function 0: GetCount

    /// Get the number of remappable controls on the device.
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

    // MARK: - Function 1: GetCtrlIdInfo

    /// Get information about a control at a given index.
    ///
    /// Response format:
    ///   param[0-1]: control ID (CID)
    ///   param[2-3]: task ID (TID)
    ///   param[4-5]: flags
    ///   param[6]: position
    ///   param[7]: group
    ///   param[8]: group mask
    static func getCtrlIdInfo(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        index: UInt8
    ) async throws -> ControlInfo {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [index]
        )

        let params = response.params
        let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
        let tid = (UInt16(params[2]) << 8) | UInt16(params[3])
        // flags1 at byte[4], extended flags2 at byte[8]
        // Merge: flags1 = low byte, flags2 = high byte
        let flags1 = params.count > 4 ? params[4] : 0
        let flags2 = params.count > 8 ? params[8] : 0
        let flagsRaw = UInt16(flags1) | (UInt16(flags2) << 8)
        let flags = ControlFlags(rawValue: flagsRaw)
        let position = params.count > 5 ? params[5] : 0
        let group = params.count > 6 ? params[6] : 0
        let gmask = params.count > 7 ? params[7] : 0

        return ControlInfo(
            controlId: cid,
            taskId: tid,
            flags: flags,
            position: position,
            group: group,
            groupMask: gmask
        )
    }

    // MARK: - Function 2: GetCtrlIdReporting

    /// Get the current reporting/remap state for a control.
    ///
    /// Response format:
    ///   param[0-1]: CID echo
    ///   param[2-3]: flags (divert, persist, rawXY)
    ///   param[4-5]: remap target CID (0 = default)
    static func getCtrlIdReporting(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        controlId: UInt16
    ) async throws -> ReportingState {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [
                UInt8((controlId >> 8) & 0xFF),
                UInt8(controlId & 0xFF),
            ]
        )

        let params = response.params
        let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
        let reportFlags = params.count > 2 ? params[2] : 0
        let remapHi = params.count > 3 ? params[3] : 0
        let remapLo = params.count > 4 ? params[4] : 0
        let remap = (UInt16(remapHi) << 8) | UInt16(remapLo)

        return ReportingState(
            controlId: cid,
            isDiverted: (reportFlags & 0x01) != 0,     // bit 0
            persistDivert: (reportFlags & 0x04) != 0,   // bit 2
            rawXY: (reportFlags & 0x10) != 0,            // bit 4
            remapTarget: remap
        )
    }

    // MARK: - Function 3: SetCtrlIdReporting

    /// Set the reporting/remap state for a control.
    ///
    /// flags1 byte layout (per HID++ 2.0 spec):
    ///   bit 0 (0x01) = divert        (temporary divert active)
    ///   bit 1 (0x02) = dvalid        (update temporary divert flag)
    ///   bit 2 (0x04) = persist       (persistent divert active)
    ///   bit 3 (0x08) = pvalid        (update persistent divert flag)
    ///   bit 4 (0x10) = rawXY         (raw XY while held)
    ///   bit 5 (0x20) = rvalid        (update rawXY flag)
    ///
    /// Both value + valid bits MUST be set for the device to accept changes.
    ///
    /// - Parameters:
    ///   - controlId: CID to configure.
    ///   - divert: Whether to divert events to software.
    ///   - persistDivert: Whether divert persists across power cycles.
    ///   - rawXY: Whether to enable raw XY reporting while button is held.
    ///   - remapTarget: CID to remap to (0 = restore default action).
    static func setCtrlIdReporting(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        controlId: UInt16,
        divert: Bool? = nil,
        persistDivert: Bool? = nil,
        rawXY: Bool? = nil,
        remapTarget: UInt16 = 0
    ) async throws {
        // Build flags1 byte: only set "valid" bits for fields we're explicitly changing.
        // If a field is nil, we leave both the value and valid bits unset so the device
        // preserves the existing state for that field.
        var flags1: UInt8 = 0
        if let divert {
            if divert { flags1 |= 0x01 }   // divert value
            flags1 |= 0x02                  // dvalid
        }
        if let persistDivert {
            if persistDivert { flags1 |= 0x04 } // persist value
            flags1 |= 0x08                  // pvalid
        }
        if let rawXY {
            if rawXY { flags1 |= 0x10 }    // rawXY value
            flags1 |= 0x20                  // rvalid
        }

        // Packet layout per HID++ 2.0 spec (setCidReporting function 0x03):
        //   [cid_hi, cid_lo, flags1, remapHi, remapLo]
        // This uses a short report (report ID 0x10) — 3 param bytes for flags + remap.
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x03,
            softwareId: 0x01,
            params: [
                UInt8((controlId >> 8) & 0xFF),
                UInt8(controlId & 0xFF),
                flags1,
                UInt8((remapTarget >> 8) & 0xFF),
                UInt8(remapTarget & 0xFF),
            ]
        )
    }

    // MARK: - Convenience: Enumerate All Controls

    /// Enumerate all remappable controls on the device.
    static func enumerateControls(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> [ControlInfo] {
        let count = try await getCount(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex
        )

        var controls: [ControlInfo] = []
        controls.reserveCapacity(count)

        for i in 0..<UInt8(count) {
            let info = try await getCtrlIdInfo(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                index: i
            )
            controls.append(info)
        }

        return controls
    }

    // MARK: - Notification Parsing

    /// Parse a `divertedButtonsEvent` (event 0) notification payload.
    ///
    /// The device sends CID pairs for all currently-pressed diverted buttons.
    /// Up to 4 CIDs can be reported simultaneously.
    /// All-zero means all diverted buttons released.
    ///
    /// Payload layout: [cid0_hi, cid0_lo, cid1_hi, cid1_lo, ...]
    static func parseDivertedButtonsEvent(params: [UInt8]) -> [UInt16] {
        var cids: [UInt16] = []
        var i = 0
        while i + 1 < params.count {
            let cid = (UInt16(params[i]) << 8) | UInt16(params[i + 1])
            if cid != 0 { cids.append(cid) }
            i += 2
        }
        return cids
    }

    /// Parse a `rawXY` (event 1) notification payload.
    ///
    /// Sent when a diverted button with rawXY enabled is held and the mouse moves.
    /// Contains delta X/Y as signed 16-bit big-endian values.
    ///
    /// Payload layout: [dx_hi, dx_lo, dy_hi, dy_lo, ...]
    static func parseRawXYEvent(params: [UInt8]) -> (deltaX: Int16, deltaY: Int16) {
        guard params.count >= 4 else { return (0, 0) }
        let dx = Int16(bitPattern: (UInt16(params[0]) << 8) | UInt16(params[1]))
        let dy = Int16(bitPattern: (UInt16(params[2]) << 8) | UInt16(params[3]))
        return (dx, dy)
    }
}
