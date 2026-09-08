import MXControlHIDPP
import SwiftUI

// MARK: - Capability Sections

/// Per-capability rows rendered from device states. The dispatch in
/// `DeviceDetailView.capabilitySection` is the single device-specific UI
/// spot: a new capability with a known kind needs no code here (it falls
/// through to `simpleToggle`), only capabilities with custom controls
/// (pickers, sliders, action buttons) get a dedicated builder below.
extension DeviceDetailView {

    // MARK: - Generic Toggle

    func simpleToggle(_ state: ToggleState) -> some View {
        ToggleRow(
            label: state.label,
            isOn: toggleBinding(state.id),
            subtitle: state.subtitle
        ) { _ in
            commit(state.id)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Wheel Mode Picker

    var wheelModeSection: some View {
        row {
            Text("Wheel")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            Picker("", selection: wheelModeBinding) {
                if let state = device.segmented[CapabilityID.smartShiftWheelMode] {
                    ForEach(state.options) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
    }

    private var wheelModeBinding: Binding<Int> {
        let fallback = Int(SmartShiftFeature.WheelMode.ratchet.rawValue)
        return Binding(
            get: { device.segmented[CapabilityID.smartShiftWheelMode]?.selected ?? fallback },
            set: {
                device.segmented[CapabilityID.smartShiftWheelMode]?.selected = $0
                commit(CapabilityID.smartShiftWheelMode)
            }
        )
    }

    // MARK: - Smooth Scroll

    var smoothScrollSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Smooth Scroll",
                isOn: toggleBinding(CapabilityID.smoothScrollEnabled),
                subtitle: "Smooths scroll wheel input (best with free-spin)"
            ) { _ in
                commit(CapabilityID.smoothScrollEnabled)
            }

            if (device.toggles[CapabilityID.smoothScrollEnabled]?.value ?? false)
                && !MacActions.hasAccessibilityPermission() {
                WarningBanner(text: "Accessibility permission required. Grant in System Settings > Privacy & Security > Accessibility.")
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Thumb Wheel

    var thumbWheelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Invert Thumb Wheel",
                isOn: toggleBinding(CapabilityID.thumbWheelInverted),
                subtitle: "Reverse horizontal scroll"
            ) { _ in
                commit(CapabilityID.thumbWheelInverted)
            }

            if device.toggles[CapabilityID.smoothScrollEnabled]?.value ?? false,
               let state = device.doubles[CapabilityID.smoothScrollThumbSpeed] {
                SliderRow(
                    label: "Thumb Wheel Speed",
                    value: doubleBinding(state.id),
                    range: state.range,
                    step: state.step,
                    format: state.format,
                    suffix: state.suffix
                ) {
                    commit(state.id)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Mic Mute (F9)

    var micMuteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Mic Mute on F9",
                isOn: toggleBinding(CapabilityID.micMuteEnabled),
                subtitle: (device.micMuteBehavior?.divertActive ?? false)
                    ? "F9 toggles the microphone via the keyboard"
                    : "F9 is intercepted globally (keyboard divert unavailable)"
            ) { _ in
                commit(CapabilityID.micMuteEnabled)
            }

            Button {
                device.fireMicMute()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                    Text("Test Mic Mute")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !(device.micMuteBehavior?.divertActive ?? false) && !MacActions.hasAccessibilityPermission() {
                WarningBanner(text: "Accessibility permission required for F9 intercept. Grant in System Settings > Privacy & Security > Accessibility.")
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Backlight

    var backlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Backlight",
                isOn: toggleBinding(CapabilityID.backlightEnabled),
                subtitle: "Keyboard illumination"
            ) { _ in
                commit(CapabilityID.backlightEnabled)
            }

            if device.toggles[CapabilityID.backlightEnabled]?.value ?? false,
               let state = device.ints[CapabilityID.backlightLevel] {
                SliderRow(
                    label: "Level",
                    intValue: intBinding(state.id),
                    range: state.range,
                    step: state.step
                ) {
                    commit(state.id)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Standard Function Keys

    /// The stored value uses UI sense (standard F-keys primary), so the
    /// binding is direct — no negation (a previous revision negated twice
    /// and displayed/stored the opposite of the device state).
    var fnKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Standard Function Keys",
                isOn: toggleBinding(CapabilityID.fnStandardKeys),
                subtitle: "Use F1-F12 as standard keys, hold Fn for media"
            ) { _ in
                commit(CapabilityID.fnStandardKeys)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Advanced

    var advancedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack {
                    Text("Advanced")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 4) {
                    // DPI
                    if let state = device.ints[CapabilityID.dpi] {
                        SliderRow(
                            label: "DPI",
                            intValue: intBinding(state.id),
                            range: state.range,
                            step: state.step,
                            suffix: " DPI"
                        ) {
                            commit(state.id)
                        }
                    }

                    // SmartShift Force (only while SmartShift is active)
                    if let state = device.ints[CapabilityID.smartShiftTorque],
                       device.toggles[CapabilityID.smartShiftActive]?.value ?? false {
                        SliderRow(
                            label: "SmartShift Force",
                            intValue: intBinding(state.id),
                            range: state.range,
                            step: state.step
                        ) {
                            commit(state.id)
                        }
                    }

                    // Smooth scroll tuning
                    if device.toggles[CapabilityID.smoothScrollEnabled]?.value ?? false {
                        if let state = device.doubles[CapabilityID.smoothScrollSpeed] {
                            SliderRow(
                                label: "Scroll Speed",
                                value: doubleBinding(state.id),
                                range: state.range,
                                step: state.step,
                                format: state.format,
                                suffix: state.suffix
                            ) {
                                commit(state.id)
                            }
                        }

                        if let state = device.doubles[CapabilityID.smoothScrollMomentum] {
                            SliderRow(
                                label: "Scroll Momentum",
                                value: doubleBinding(state.id),
                                range: state.range,
                                step: state.step,
                                format: state.format
                            ) {
                                commit(state.id)
                            }
                        }
                    }

                    // Gesture thresholds
                    if device.thumbGestureBehavior != nil {
                        Text("Gesture Button")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        if !MacActions.hasAccessibilityPermission() {
                            WarningBanner(text: "Accessibility permission required for gestures.")
                        }

                        if device.ints[CapabilityID.gestureClickMs] != nil {
                            SliderRow(
                                label: "Click",
                                intValue: intBinding(CapabilityID.gestureClickMs),
                                range: device.ints[CapabilityID.gestureClickMs]?.range ?? 100...400,
                                step: 10,
                                suffix: "ms"
                            ) {
                                commit(CapabilityID.gestureClickMs)
                            }
                        }

                        if let state = device.ints[CapabilityID.gestureDragThreshold] {
                            SliderRow(
                                label: "Drag",
                                intValue: intBinding(state.id),
                                range: state.range,
                                step: state.step
                            ) {
                                commit(state.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Slider Bindings

    private func intBinding(_ id: CapabilityID) -> Binding<Int> {
        Binding(
            get: { device.ints[id]?.value ?? 0 },
            set: { device.ints[id]?.value = $0 }
        )
    }

    private func doubleBinding(_ id: CapabilityID) -> Binding<Double> {
        Binding(
            get: { device.doubles[id]?.value ?? 0 },
            set: { device.doubles[id]?.value = $0 }
        )
    }
}
