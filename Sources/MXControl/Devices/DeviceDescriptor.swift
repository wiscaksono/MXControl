import Foundation
import MXControlHIDPP

// MARK: - Capability Model

/// Stable capability identifiers. Each id doubles as the UserDefaults key
/// suffix (`mxcontrol.{device}.{id}`) — never rename an id without a migration.
enum CapabilityID {
    static let battery = "battery"
    static let dpi = "dpi"
    static let pointerSpeed = "pointer_speed"
    static let smartShiftWheelMode = "smartshift.wheel_mode"
    static let smartShiftActive = "smartshift.active"
    static let smartShiftTorque = "smartshift.torque"
    static let hiResEnabled = "hires.enabled"
    static let hiResInverted = "hires.inverted"
    static let thumbWheelInverted = "thumbwheel.inverted"
    static let smoothScrollEnabled = "smooth_scroll.enabled"
    static let smoothScrollSpeed = "smooth_scroll.speed"
    static let smoothScrollMomentum = "smooth_scroll.momentum"
    static let smoothScrollThumbSpeed = "smooth_scroll.thumb_speed"
    static let gestureClickMs = "gesture.click_time_ms"
    static let gestureDragThreshold = "gesture.drag_threshold"
    static let backlightEnabled = "backlight.enabled"
    static let backlightLevel = "backlight.level"
    static let fnStandardKeys = "fn.standard_keys"
    static let micMuteEnabled = "micmute.enabled"
    static let hosts = "hosts"
}

/// One user-facing controllable backed by a HID++ feature (or local service state).
struct DeviceCapability: Sendable {
    enum Kind: Sendable {
        case toggle
        case intSlider
        case doubleSlider
        case segmented
        /// Display-only rows (battery, hosts) with dedicated states.
        case info
    }

    let id: String
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
        id: String,
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
