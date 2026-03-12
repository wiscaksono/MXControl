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

                    // Feature load error / connection warning
                    if let error = mouse.featureLoadError {
                        featureWarningBanner(error)
                        separator
                    }

                    // Wheel Mode picker (Ratchet / Free Spin)
                    if mouse.hasFeature(SmartShiftFeature.featureId) {
                        wheelModeSection
                        separator
                    }

                    // SmartShift toggle
                    if mouse.hasFeature(SmartShiftFeature.featureId) {
                        smartShiftToggleSection
                        separator
                    }

                    // Smooth Scroll toggle (+ accessibility warning)
                    smoothScrollSection
                    separator

                    // Natural Scrolling
                    if mouse.hasFeature(HiResScrollFeature.featureId) {
                        scrollDirectionSection
                        separator
                    }

                    // Invert Thumb Wheel
                    if mouse.hasFeature(ThumbWheelFeature.featureId) && mouse.thumbWheelSupportsInversion {
                        thumbWheelSection
                        separator
                    }

                    // Host Info
                    if !mouse.hosts.isEmpty {
                        hostInfoSection
                        separator
                    }

                    // Advanced (DPI, SmartShift Force, Scroll Speed/Momentum, Gesture thresholds)
                    advancedSection
                    separator

                    // Reset
                    resetSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Save

    private func save() {
        SettingsStore.save(mouse: mouse)
    }

    // MARK: - Reset (inline confirmation — .alert() dismisses MenuBarExtra)

    @State private var showResetConfirm = false
    @State private var resetHovered = false

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showResetConfirm {
                VStack(spacing: 10) {
                    Text("Remove all saved settings and reload from device?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        ResetActionButton(label: "Cancel", isDestructive: false) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showResetConfirm = false
                            }
                        }

                        ResetActionButton(label: "Clear", isDestructive: true) {
                            SettingsStore.clearMouseSettings(deviceName: mouse.name)
                            Task {
                                mouse.isFeaturesLoaded = false
                                await mouse.loadMouseFeatures()
                            }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showResetConfirm = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showResetConfirm = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Clear Saved Settings")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(resetHovered
                                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                                : Color(nsColor: .controlBackgroundColor))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { resetHovered = $0 }
            }
        }
        .padding(.vertical, 4)
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

    // MARK: - Wheel Mode (picker only)

    private var wheelModeSection: some View {
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
                Task {
                    do { try await mouse.setSmartShift(wheelMode: newMode) }
                    catch { debugLog("[UI] setSmartShift wheelMode failed: \(error)") }
                }
                save()
            }
        }
    }

    // MARK: - SmartShift Toggle (no Force slider — that's in Advanced)

    private var smartShiftToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "SmartShift",
                isOn: $mouse.smartShiftActive,
                subtitle: "Auto-switch ratchet / free-spin"
            ) { enabled in
                Task {
                    do { try await mouse.setSmartShift(autoDisengage: enabled ? 50 : 0) }
                    catch { debugLog("[UI] setSmartShift autoDisengage failed: \(error)") }
                }
                save()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Feature Warning Banner

    private func featureWarningBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Some features failed to load: \(error)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Smooth Scroll (toggle + accessibility warning only)

    private var smoothScrollSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Smooth Scroll",
                isOn: $mouse.smoothScrollEnabled,
                subtitle: "Smooths scroll wheel input (best with free-spin)"
            ) { enabled in
                if enabled {
                    MacActions.requestAccessibilityPermission()
                }
                save()
            }

            if mouse.smoothScrollEnabled && !MacActions.hasAccessibilityPermission() {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Accessibility permission required. Grant in System Settings > Privacy & Security > Accessibility.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Advanced (custom disclosure — full row is clickable)

    @State private var showAdvanced = false

    private var advancedSection: some View {
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
                    if mouse.hasFeature(AdjustableDPIFeature.featureId) {
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

                    // SmartShift Force
                    if mouse.hasFeature(SmartShiftFeature.featureId) && mouse.smartShiftActive {
                        SliderRow(
                            label: "SmartShift Force",
                            intValue: $mouse.smartShiftTorque,
                            range: 1...mouse.smartShiftMaxForce,
                            step: 1
                        ) {
                            Task {
                                do { try await mouse.setSmartShift(torque: mouse.smartShiftTorque) }
                                catch { debugLog("[UI] setSmartShift torque failed: \(error)") }
                            }
                            save()
                        }
                    }

                    // Smooth Scroll Speed
                    if mouse.smoothScrollEnabled {
                        SliderRow(
                            label: "Scroll Speed",
                            value: $mouse.smoothScrollSpeed,
                            range: 1.0...10.0,
                            step: 0.5,
                            format: "%.1f",
                            suffix: "x"
                        ) {
                            save()
                        }

                        SliderRow(
                            label: "Scroll Momentum",
                            value: $mouse.smoothScrollMomentum,
                            range: 0.80...0.98,
                            step: 0.01,
                            format: "%.2f"
                        ) {
                            save()
                        }
                    }

                    // Gesture thresholds
                    if mouse.gestureEngine != nil {
                        Text("Gesture Button")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        if !MacActions.hasAccessibilityPermission() {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                Text("Accessibility permission required for gestures.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

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
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Scroll Direction

    private var scrollDirectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(
                label: "Natural Scrolling",
                isOn: $mouse.hiResInverted,
                subtitle: "Content moves in the direction of your finger"
            ) { inverted in
                Task {
                    do { try await mouse.setHiResScroll(hiRes: mouse.hiResEnabled, inverted: inverted) }
                    catch { debugLog("[UI] setHiResScroll inversion failed: \(error)") }
                }
                save()
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
                Task {
                    do { try await mouse.setThumbWheelInverted(inverted) }
                    catch { debugLog("[UI] setThumbWheelInverted failed: \(error)") }
                }
                save()
            }
        }
        .padding(.vertical, 6)
    }

    // (Gesture thresholds moved into Advanced section)

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

                    // Reset
                    resetSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func save() {
        SettingsStore.save(keyboard: keyboard)
    }

    // MARK: - Reset (inline confirmation — .alert() dismisses MenuBarExtra)

    @State private var showResetConfirm = false
    @State private var resetHovered = false

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showResetConfirm {
                VStack(spacing: 10) {
                    Text("Remove all saved settings and reload from device?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        ResetActionButton(label: "Cancel", isDestructive: false) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showResetConfirm = false
                            }
                        }

                        ResetActionButton(label: "Clear", isDestructive: true) {
                            SettingsStore.clearKeyboardSettings(deviceName: keyboard.name)
                            Task {
                                keyboard.isFeaturesLoaded = false
                                await keyboard.loadKeyboardFeatures()
                            }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showResetConfirm = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showResetConfirm = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Clear Saved Settings")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(resetHovered
                                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                                : Color(nsColor: .controlBackgroundColor))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { resetHovered = $0 }
            }
        }
        .padding(.vertical, 4)
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

// MARK: - Reset Action Button

/// Styled button for inline reset confirmation (Cancel / Clear).
private struct ResetActionButton: View {
    let label: String
    let isDestructive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isDestructive ? .medium : .regular))
                .foregroundStyle(isDestructive ? .red : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered
                            ? (isDestructive
                                ? Color.red.opacity(0.12)
                                : Color(nsColor: .selectedContentBackgroundColor).opacity(0.12))
                            : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
