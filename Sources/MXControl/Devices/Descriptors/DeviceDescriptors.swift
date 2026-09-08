import Foundation
import MXControlHIDPP

// MARK: - Device Descriptors

/// Static device database (Solaar `descriptors.py` equivalent).
/// To support a new device, add one value here + tests. No subclass needed.
enum DeviceDescriptors {

    static let all: [DeviceDescriptor] = [
        mxMaster3S,
        mxKeysMini,
    ]

    /// Match a discovered device. PID first (precise, BLE direct), then
    /// HID++ name (receiver path where only the receiver PID is visible).
    /// Unknown devices get a generic descriptor exposing battery + hosts.
    static func match(pid: Int?, name: String, kind: DeviceNameFeature.DeviceKind) -> DeviceDescriptor {
        if let found = all.first(where: { $0.matches(pid: pid, name: name) }) {
            return found
        }
        return generic(kind: kind, name: name)
    }

    /// Fallback for unrecognized HID++ 2.0 devices: battery + host info only.
    static func generic(kind: DeviceNameFeature.DeviceKind, name: String) -> DeviceDescriptor {
        let type: DeviceType
        switch kind {
        case .mouse, .trackball, .touchpad:
            type = .mouse
        case .keyboard, .numpad:
            type = .keyboard
        default:
            type = .unknown
        }
        return DeviceDescriptor(
            id: "generic",
            name: name,
            type: type,
            pids: [],
            nameMatches: [],
            capabilities: [
                DeviceCapability(id: CapabilityID.battery, featureId: BatteryFeature.featureId, label: "Battery", subtitle: nil, kind: .info, advanced: false),
                DeviceCapability(id: CapabilityID.hosts, featureId: ChangeHostFeature.featureId, label: "Easy-Switch", subtitle: nil, kind: .info, advanced: false),
            ],
            scroll: nil,
            thumbGesture: nil,
            micMute: nil
        )
    }

    // MARK: - MX Master 3S

    static let mxMaster3S = DeviceDescriptor(
        id: "mx-master-3s",
        name: "MX Master 3S",
        type: .mouse,
        pids: [0xB034],
        nameMatches: ["MX Master 3S"],
        capabilities: [
            DeviceCapability(id: CapabilityID.battery, featureId: BatteryFeature.featureId, label: "Battery", subtitle: nil, kind: .info, advanced: false),
            DeviceCapability(id: CapabilityID.pointerSpeed, featureId: PointerSpeedFeature.featureId, label: "Pointer Speed", subtitle: nil, kind: .intSlider, advanced: false, hidden: true),
            DeviceCapability(id: CapabilityID.smartShiftWheelMode, featureId: SmartShiftFeature.featureId, label: "Wheel", subtitle: nil, kind: .segmented, advanced: false),
            DeviceCapability(id: CapabilityID.smartShiftActive, featureId: SmartShiftFeature.featureId, label: "SmartShift", subtitle: "Auto-switch ratchet / free-spin", kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.smoothScrollEnabled, featureId: nil, label: "Smooth Scroll", subtitle: "Smooths scroll wheel input (best with free-spin)", kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.hiResEnabled, featureId: HiResScrollFeature.featureId, label: "Hi-Res", subtitle: nil, kind: .toggle, advanced: false, hidden: true),
            DeviceCapability(id: CapabilityID.hiResInverted, featureId: HiResScrollFeature.featureId, label: "Natural Scrolling", subtitle: "Content moves in the direction of your finger", kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.thumbWheelInverted, featureId: ThumbWheelFeature.featureId, label: "Invert Thumb Wheel", subtitle: "Reverse horizontal scroll", kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.hosts, featureId: ChangeHostFeature.featureId, label: "Easy-Switch", subtitle: nil, kind: .info, advanced: false),
            // Advanced
            DeviceCapability(id: CapabilityID.dpi, featureId: AdjustableDPIFeature.featureId, label: "DPI", subtitle: nil, kind: .intSlider, advanced: true),
            DeviceCapability(id: CapabilityID.smartShiftTorque, featureId: SmartShiftFeature.featureId, label: "SmartShift Force", subtitle: nil, kind: .intSlider, advanced: true),
            DeviceCapability(id: CapabilityID.smoothScrollSpeed, featureId: nil, label: "Scroll Speed", subtitle: nil, kind: .doubleSlider, advanced: true),
            DeviceCapability(id: CapabilityID.smoothScrollMomentum, featureId: nil, label: "Scroll Momentum", subtitle: nil, kind: .doubleSlider, advanced: true),
            DeviceCapability(id: CapabilityID.smoothScrollThumbSpeed, featureId: nil, label: "Thumb Wheel Speed", subtitle: nil, kind: .doubleSlider, advanced: true),
            DeviceCapability(id: CapabilityID.gestureClickMs, featureId: nil, label: "Gesture Click", subtitle: nil, kind: .intSlider, advanced: true),
            DeviceCapability(id: CapabilityID.gestureDragThreshold, featureId: nil, label: "Gesture Drag", subtitle: nil, kind: .intSlider, advanced: true),
        ],
        scroll: ScrollSpec(),
        thumbGesture: ThumbGestureSpec(thumbCID: SpecialKeysFeature.KnownCID.gestureButton.rawValue, sideButtons: true),
        micMute: nil
    )

    // MARK: - MX Keys Mini

    static let mxKeysMini = DeviceDescriptor(
        id: "mx-keys-mini",
        name: "MX Keys Mini",
        type: .keyboard,
        pids: [0xB369],
        nameMatches: ["MX Keys Mini"],
        capabilities: [
            DeviceCapability(id: CapabilityID.battery, featureId: BatteryFeature.featureId, label: "Battery", subtitle: nil, kind: .info, advanced: false),
            DeviceCapability(id: CapabilityID.backlightEnabled, featureId: nil, label: "Backlight", subtitle: "Keyboard illumination", kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.backlightLevel, featureId: nil, label: "Level", subtitle: nil, kind: .intSlider, advanced: false),
            DeviceCapability(id: CapabilityID.fnStandardKeys, featureId: nil, label: "Standard Function Keys", subtitle: "Use F1-F12 as standard keys, hold Fn for media", kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.micMuteEnabled, featureId: nil, label: "Mic Mute on F9", subtitle: nil, kind: .toggle, advanced: false),
            DeviceCapability(id: CapabilityID.hosts, featureId: ChangeHostFeature.featureId, label: "Easy-Switch", subtitle: nil, kind: .info, advanced: false),
        ],
        scroll: nil,
        thumbGesture: nil,
        micMute: MicMuteSpec(cid: 0x011C, position: 9, requireFnFlag: true)
    )
}
