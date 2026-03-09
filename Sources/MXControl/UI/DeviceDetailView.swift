import SwiftUI

/// Per-device detail view displayed when clicking a device in the menu bar.
/// Reads DeviceManager from environment for save operations.
struct DeviceDetailView: View {
    let device: LogiDevice

    var body: some View {
        if let mouse = device as? MouseDevice {
            MouseDetailView(mouse: mouse)
        } else if let keyboard = device as? KeyboardDevice {
            KeyboardDetailView(keyboard: keyboard)
        } else {
            GenericDeviceView(device: device)
        }
    }
}

// MARK: - Compact Row Helper

/// Reusable row: HStack(spacing: 8) with vertical padding.
private func row<C: View>(@ViewBuilder content: () -> C) -> some View {
    HStack(spacing: 8) {
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
}

/// Separator between sections.
private var separator: some View {
    Divider()
}

// MARK: - Mouse Detail View

struct MouseDetailView: View {
    @Bindable var mouse: MouseDevice
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        if !mouse.isFeaturesLoaded {
            loadingView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Battery
                    if mouse.hasFeature(BatteryFeature.featureId) {
                        batteryRow
                        separator
                    }

                    // DPI
                    if mouse.hasFeature(AdjustableDPIFeature.featureId) {
                        dpiSection
                        separator
                    }

                    // Pointer Speed
                    if mouse.hasFeature(PointerSpeedFeature.featureId) {
                        pointerSpeedSection
                        separator
                    }

                    // Scroll Wheel (SmartShift)
                    if mouse.hasFeature(SmartShiftFeature.featureId) {
                        smartShiftSection
                        separator
                    }

                    // Hi-Res Scroll: intentionally not exposed in UI.
                    // Feature 0x2121 setWheelMode(hiRes: true) redirects scroll
                    // events to HID++ channel, causing OS to lose scroll input.
                    // SmartShift (0x2111) handles wheel mode correctly.

                    // Thumb Wheel
                    if mouse.hasFeature(ThumbWheelFeature.featureId) && mouse.thumbWheelSupportsInversion {
                        thumbWheelSection
                        separator
                    }

                    // Gesture Button
                    if mouse.gestureEngine != nil {
                        gestureSection
                        separator
                    }

                    // Button Remapping
                    if !mouse.buttons.isEmpty {
                        buttonsSection
                        separator
                    }

                    // Host Info
                    if !mouse.hosts.isEmpty {
                        hostInfoSection
                        separator
                    }

                    // Connection Info
                    ConnectionInfoRow(device: mouse)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Save

    private func save() {
        deviceManager.saveMouseSettings(mouse)
    }

    // MARK: - Battery

    private var batteryRow: some View {
        row {
            Text("Battery")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            BatteryIndicator(level: mouse.batteryLevel, isCharging: mouse.batteryCharging)

            Text(mouse.batteryStatus.description)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading features...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - DPI

    private var dpiSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SliderRow(
                label: "DPI",
                intValue: $mouse.currentDPI,
                range: mouse.dpiMin...mouse.dpiMax,
                step: mouse.dpiStep,
                suffix: " DPI"
            ) {
                Task {
                    do { try await mouse.setDPI(mouse.currentDPI) }
                    catch { debugLog("[UI] DPI set ERROR: \(error)") }
                }
                save()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Pointer Speed

    private var pointerSpeedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SliderRow(
                label: "Speed",
                intValue: $mouse.pointerSpeed,
                range: 0...512,
                step: 1
            ) {
                Task { try? await mouse.setPointerSpeed(mouse.pointerSpeed) }
                save()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - SmartShift

    private var smartShiftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            row {
                Text("Wheel")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                Spacer()

                Picker("", selection: $mouse.smartShiftWheelMode) {
                    Text("Ratchet").tag(SmartShiftFeature.WheelMode.ratchet)
                    Text("Free Spin").tag(SmartShiftFeature.WheelMode.freeSpin)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .onChange(of: mouse.smartShiftWheelMode) { _, newMode in
                    Task { try? await mouse.setSmartShift(wheelMode: newMode) }
                    save()
                }
            }

            ToggleRow(
                label: "SmartShift",
                isOn: $mouse.smartShiftActive,
                subtitle: "Auto-switch ratchet / free-spin"
            ) { enabled in
                Task { try? await mouse.setSmartShift(autoDisengage: enabled ? 50 : 0) }
                save()
            }

            if mouse.smartShiftActive {
                SliderRow(
                    label: "Force",
                    intValue: $mouse.smartShiftTorque,
                    range: 1...mouse.smartShiftMaxForce,
                    step: 1
                ) {
                    Task { try? await mouse.setSmartShift(torque: mouse.smartShiftTorque) }
                    save()
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Thumb Wheel

    private var thumbWheelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Invert Thumb Wheel",
                isOn: $mouse.thumbWheelInverted,
                subtitle: "Reverse horizontal scroll"
            ) { inverted in
                Task { try? await mouse.setThumbWheelInverted(inverted) }
                save()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Gesture Button

    private var gestureSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Gesture Button")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.top, 10)
                .padding(.bottom, 2)

            SliderRow(
                label: "Click",
                intValue: Binding(
                    get: { Int(mouse.gestureClickTimeLimit * 1000) },
                    set: { mouse.gestureClickTimeLimit = Double($0) / 1000.0 }
                ),
                range: 100...400,
                step: 10,
                suffix: "ms"
            ) {
                save()
            }

            SliderRow(
                label: "Drag",
                intValue: $mouse.gestureDragThreshold,
                range: 50...500,
                step: 10
            ) {
                save()
            }
        }
    }

    // MARK: - Button Remapping

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buttons")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(mouse.buttons.filter { $0.isRemappable }) { button in
                ButtonRemapRow(
                    button: button,
                    mouse: mouse,
                    onRemapped: { save() }
                )
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Host Info

    private var hostInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Easy-Switch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(mouse.hosts) { host in
                row {
                    Image(systemName: host.index == mouse.currentHostIndex
                        ? "checkmark.circle.fill"
                        : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(host.index == mouse.currentHostIndex ? .green : .secondary)

                    Text(host.name)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer()

                    Text("\(host.busType.description) \(host.osType.description)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Button Remap Row

private struct ButtonRemapRow: View {
    let button: SpecialKeysFeature.ControlInfo
    let mouse: MouseDevice
    var onRemapped: (() -> Void)?

    @State private var selectedAction: ButtonAction = .defaultAction

    var body: some View {
        let name = SpecialKeysFeature.KnownCID(rawValue: button.controlId)?.description
            ?? String(format: "CID %d", button.controlId)

        ActionPicker(
            buttonName: name,
            controlId: button.controlId,
            currentAction: $selectedAction
        ) { newAction in
            Task {
                try? await mouse.remapButton(
                    controlId: button.controlId,
                    to: newAction.remapCID
                )
                onRemapped?()
            }
        }
        .onAppear {
            let currentRemap = mouse.buttonRemaps[button.controlId] ?? 0
            selectedAction = ButtonAction.from(cid: currentRemap)
        }
    }
}

// MARK: - Keyboard Detail View

struct KeyboardDetailView: View {
    @Bindable var keyboard: KeyboardDevice
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        if !keyboard.isFeaturesLoaded {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading features...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Battery
                    if keyboard.hasFeature(BatteryFeature.featureId) {
                        batteryRow
                        separator
                    }

                    // Backlight
                    if keyboard.backlightFeatureId != nil {
                        backlightSection
                        separator
                    }

                    // Fn Inversion
                    if keyboard.fnInversionFeatureId != nil {
                        fnInversionSection
                        separator
                    }

                    // Host Info
                    if !keyboard.hosts.isEmpty {
                        hostInfoSection
                        separator
                    }

                    // Connection Info
                    ConnectionInfoRow(device: keyboard)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func save() {
        deviceManager.saveKeyboardSettings(keyboard)
    }

    // MARK: - Battery

    private var batteryRow: some View {
        row {
            Text("Battery")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            BatteryIndicator(level: keyboard.batteryLevel, isCharging: keyboard.batteryCharging)

            Text(keyboard.batteryStatus.description)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Backlight

    private var backlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Backlight",
                isOn: $keyboard.backlightEnabled,
                subtitle: "Keyboard illumination"
            ) { enabled in
                debugLog("[UI] Backlight toggle: enabled=\(enabled)")
                Task {
                    do {
                        try await keyboard.setBacklight(enabled: enabled, level: keyboard.backlightLevel)
                    } catch {
                        debugLog("[UI] Backlight toggle ERROR: \(error)")
                    }
                }
                save()
            }

            if keyboard.backlightEnabled {
                SliderRow(
                    label: "Level",
                    intValue: $keyboard.backlightLevel,
                    range: 0...keyboard.backlightMaxLevel,
                    step: 1
                ) {
                    debugLog("[UI] Backlight level: \(keyboard.backlightLevel)")
                    Task {
                        do {
                            try await keyboard.setBacklight(enabled: keyboard.backlightEnabled, level: keyboard.backlightLevel)
                        } catch {
                            debugLog("[UI] Backlight level ERROR: \(error)")
                        }
                    }
                    save()
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Fn Inversion

    private var fnInversionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Note: The MX Keys Mini 0x40A3 protocol uses inverted semantics from
            // what Solaar docs suggest. fnState=0x00 from device means "F-keys are
            // primary" and fnState=0x01 means "media keys are primary" (the default).
            // We flip the binding so the UI toggle "Standard Function Keys" = ON
            // correctly sends fnState=0x00 (which makes F-keys primary on the device).
            ToggleRow(
                label: "Standard Function Keys",
                isOn: Binding(
                    get: { !keyboard.fnInverted },
                    set: { keyboard.fnInverted = !$0 }
                ),
                subtitle: "Use F1-F12 as standard keys, hold Fn for media"
            ) { wantStandardFKeys in
                let protocolValue = !wantStandardFKeys
                debugLog("[UI] Fn inversion toggle: wantStdFKeys=\(wantStandardFKeys) → protocol fnInverted=\(protocolValue)")
                Task {
                    do {
                        try await keyboard.setFnInversion(protocolValue)
                    } catch {
                        debugLog("[UI] Fn inversion ERROR: \(error)")
                    }
                }
                save()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Host Info

    private var hostInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Easy-Switch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(keyboard.hosts) { host in
                row {
                    Image(systemName: host.index == keyboard.currentHostIndex
                        ? "checkmark.circle.fill"
                        : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(host.index == keyboard.currentHostIndex ? .green : .secondary)

                    Text(host.name)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer()

                    Text("\(host.busType.description) \(host.osType.description)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Connection Info Row

/// Shows transport type and protocol version for a device.
private struct ConnectionInfoRow: View {
    let device: LogiDevice
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        let transport = deviceManager.transportType(for: device)
        row {
            Text("Connection")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            if let transport {
                HStack(spacing: 4) {
                    Image(systemName: transport == .ble ? "bolt.horizontal.fill" : "cable.connector")
                        .font(.system(size: 9))
                    Text(transport == .ble ? "Bluetooth LE" : "USB Receiver")
                        .font(.system(size: 11))
                }
                .foregroundStyle(transport == .ble ? .blue : .secondary)
            }

            if device.protocolMajor > 0 {
                Text("HID++ \(device.protocolMajor).\(device.protocolMinor)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Generic Device View (fallback)

struct GenericDeviceView: View {
    let device: LogiDevice

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)

            Text(device.name)
                .font(.system(size: 13, weight: .medium))

            Text("Unknown device type — no controls available")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
