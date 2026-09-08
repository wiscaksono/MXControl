import Foundation
import MXControlHIDPP

// MARK: - Capability Model

/// Stable capability identifiers. Each case doubles as the UserDefaults key
/// suffix (`mxcontrol.{device}.{rawValue}`) — never rename a raw value
/// without a migration. Switches over this enum are exhaustive (no default)
/// so adding a capability forces every dispatch site to handle it.
enum CapabilityID: String, Sendable, CaseIterable {
    case battery
    case dpi
    case pointerSpeed = "pointer_speed"
    case smartShiftWheelMode = "smartshift.wheel_mode"
    case smartShiftActive = "smartshift.active"
    case smartShiftTorque = "smartshift.torque"
    case hiResEnabled = "hires.enabled"
    case hiResInverted = "hires.inverted"
    case thumbWheelInverted = "thumbwheel.inverted"
    case smoothScrollEnabled = "smooth_scroll.enabled"
    case smoothScrollSpeed = "smooth_scroll.speed"
    case smoothScrollMomentum = "smooth_scroll.momentum"
    case smoothScrollThumbSpeed = "smooth_scroll.thumb_speed"
    case gestureClickMs = "gesture.click_time_ms"
    case gestureDragThreshold = "gesture.drag_threshold"
    case backlightEnabled = "backlight.enabled"
    case backlightLevel = "backlight.level"
    case fnStandardKeys = "fn.standard_keys"
    case micMuteEnabled = "micmute.enabled"
    case hosts
}

/// One user-facing controllable backed by a HID++ feature (or local service state).
struct DeviceCapability: Sendable {    enum Kind: Sendable {
        case toggle
        case intSlider
        case doubleSlider
        case segmented
        /// Display-only rows (battery, hosts) with dedicated states.
        case info
    }

    let id: CapabilityID
    /// HID++ feature backing this capability.
    /// Nil = resolved dynamically at load (multi-variant features like
    /// backlight v2/v3) or local-only (smooth scroll, gesture thresholds).
    /// Capabilities with a non-nil featureId are skipped when the device
    /// does not report that feature.
    let featureId: UInt16?
    let label: String
    let subtitle: String?
    let kind: Kind
    /// Advanced section placement.
    let advanced: Bool
    /// Hidden from UI entirely (loaded/restored silently, e.g. pointer speed).
    let hidden: Bool

    init(
        id: CapabilityID,
        featureId: UInt16?,
        label: String,
        subtitle: String?,
        kind: Kind,
        advanced: Bool,
        hidden: Bool = false
    ) {
        self.id = id
        self.featureId = featureId
        self.label = label
        self.subtitle = subtitle
        self.kind = kind
        self.advanced = advanced
        self.hidden = hidden
    }
}

// MARK: - Behavior Specs

/// Smooth-scroll service wiring. Present when the device reports
/// HiResScroll and should drive the shared scroll interceptor.
struct ScrollSpec: Sendable {}

/// Thumb-button gesture wiring via SpecialKeys divert.
struct ThumbGestureSpec: Sendable {
    /// CID of the thumb/gesture button (e.g. 0x00C3).
    let thumbCID: UInt16
    /// Also divert Back/Forward for global navigation fallback.
    let sideButtons: Bool
}

/// F9 mic-mute wiring via SpecialKeys divert + event-tap fallback.
struct MicMuteSpec: Sendable {
    /// Candidate CID of the mic-mute key.
    let cid: UInt16
    /// Expected F-row position (firmware-remap guard).
    let position: UInt8
    /// Whether the control must carry the FN flag.
    let requireFnFlag: Bool
}

// MARK: - Device Descriptor

/// Static declaration of everything MXControl knows about one device.
/// Adding a device = adding one `DeviceDescriptor` value + tests.
/// No subclass, no UI code, no behavior code.
struct DeviceDescriptor: Sendable {
    /// Stable id used for settings scoping and logging (e.g. "mx-master-3s").
    let id: String
    let name: String
    let type: DeviceType
    /// IOKit product IDs for direct BLE matches.
    let pids: [Int]
    /// Substrings of the HID++ device name for receiver-path matches.
    let nameMatches: [String]
    /// Ordered capabilities. Only those whose feature is present on the
    /// device (or local-only) are instantiated.
    let capabilities: [DeviceCapability]
    /// Nil = no scroll service wiring.
    let scroll: ScrollSpec?
    /// Nil = no thumb-gesture wiring.
    let thumbGesture: ThumbGestureSpec?
    /// Nil = no mic-mute wiring.
    let micMute: MicMuteSpec?

    /// Match a discovered device to this descriptor.
    /// PID matches are exact; name matches require a full token so
    /// "MX Master 2S" never matches an "MX Master 3S" descriptor.
    func matches(pid: Int?, name: String) -> Bool {
        if let pid, pids.contains(pid) { return true }
        let tokens = name.lowercased().split(separator: " ").map(String.init)
        return nameMatches.contains { match in
            let matchTokens = match.lowercased().split(separator: " ").map(String.init)
            guard matchTokens.count <= tokens.count else { return false }
            return tokens.starts(with: matchTokens)
        }
    }
}
