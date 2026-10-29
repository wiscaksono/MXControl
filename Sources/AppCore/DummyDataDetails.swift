import Foundation

/// Device screens kept out of the main fixture enum so the type stays small.
public extension DummyData {
    // MARK: - Mouse

    /// Mirrors `DeviceCoreRuntime.sections(for:)` for MX Master 3S: same
    /// controls, order, and labels as the live screen.
    static var mouseDetail: DeviceDetail {
        DeviceDetail(
            device: mouse,
            connectionDetail: "Bluetooth · Direct",
            sections: [
                SettingSection(id: "pointer", title: "Pointer", items: [
                    SettingItem(
                        id: "dpi",
                        title: "DPI",
                        control: .slider(
                            SliderSpec(value: 1000, range: 200 ... 8000, step: 50, unit: "DPI")
                        )
                    ),
                ]),
                SettingSection(id: "wheel", title: "Wheel", items: [
                    SettingItem(
                        id: "smartshift.wheel_mode",
                        title: "Wheel",
                        control: .picker(options: ["Ratchet", "Free Spin"], selectedIndex: 0)
                    ),
                    SettingItem(
                        id: "smartshift.active",
                        title: "SmartShift",
                        subtitle: "Auto-switch ratchet / free-spin",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "smartshift.torque",
                        title: "SmartShift Force",
                        control: .slider(SliderSpec(value: 50, range: 1 ... 100, step: 1))
                    ),
                ]),
                SettingSection(id: "scrolling", title: "Scrolling", items: [
                    SettingItem(
                        id: "smooth_scroll.enabled",
                        title: "Smooth Scroll",
                        subtitle: "Smooths scroll wheel input (best with free-spin)",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "hires.inverted",
                        title: "Natural Scrolling",
                        subtitle: "Content moves in the direction of your finger",
                        control: .toggle(isOn: false)
                    ),
                    SettingItem(
                        id: "thumbwheel.inverted",
                        title: "Invert Thumb Wheel",
                        subtitle: "Reverse horizontal scroll",
                        control: .toggle(isOn: false)
                    ),
                    SettingItem(
                        id: "smooth_scroll.speed",
                        title: "Scroll Speed",
                        control: .slider(
                            SliderSpec(value: 3, range: 1 ... 10, step: 0.5, unit: "x")
                        )
                    ),
                    SettingItem(
                        id: "smooth_scroll.momentum",
                        title: "Scroll Momentum",
                        control: .slider(
                            SliderSpec(value: 0.92, range: 0.80 ... 0.98, step: 0.01)
                        )
                    ),
                    SettingItem(
                        id: "smooth_scroll.thumb_speed",
                        title: "Thumb Wheel Speed",
                        control: .slider(
                            SliderSpec(value: 1, range: 0.5 ... 5, step: 0.5, unit: "x")
                        )
                    ),
                ]),
                SettingSection(id: "hosts", title: "Hosts", items: [
                    SettingItem(
                        id: "host.0",
                        title: "MacBook Pro",
                        control: .info(value: "USB · Active")
                    ),
                    SettingItem(
                        id: "host.1",
                        title: "Work iMac",
                        control: .info(value: "Bluetooth")
                    ),
                    SettingItem(id: "host.2", title: "Host 3", control: .info(value: "Empty")),
                ]),
            ]
        )
    }

    // MARK: - Keyboard

    /// Mirrors `DeviceCoreRuntime.sections(for:)` for MX Keys Mini.
    static var keyboardDetail: DeviceDetail {
        DeviceDetail(
            device: keyboard,
            connectionDetail: "USB · Bolt receiver",
            sections: [
                SettingSection(id: "backlight", title: "Backlight", items: [
                    SettingItem(
                        id: "backlight.enabled",
                        title: "Backlight",
                        subtitle: "Keyboard illumination",
                        control: .toggle(isOn: true)
                    ),
                    SettingItem(
                        id: "backlight.level",
                        title: "Level",
                        control: .slider(SliderSpec(value: 5, range: 0 ... 8, step: 1))
                    ),
                ]),
                SettingSection(id: "keys", title: "Keys", items: [
                    SettingItem(
                        id: "fn.standard_keys",
                        title: "Standard Function Keys",
                        subtitle: "Use F1-F12 as standard keys, hold Fn for media",
                        control: .toggle(isOn: false)
                    ),
                    SettingItem(
                        id: "micmute.enabled",
                        title: "Mic Mute on F9",
                        control: .toggle(isOn: false)
                    ),
                    SettingItem(
                        id: "fn.restoreDefault",
                        title: "Restore default",
                        control: .action(detail: nil)
                    ),
                ]),
                SettingSection(id: "hosts", title: "Hosts", items: [
                    SettingItem(
                        id: "host.0",
                        title: "MacBook Pro",
                        control: .info(value: "USB · Active")
                    ),
                    SettingItem(
                        id: "host.1",
                        title: "Work iMac",
                        control: .info(value: "Bluetooth")
                    ),
                    SettingItem(id: "host.2", title: "Host 3", control: .info(value: "Empty")),
                ]),
            ]
        )
    }
}
