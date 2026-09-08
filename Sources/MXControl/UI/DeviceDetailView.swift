import MXControlHIDPP
import SwiftUI

/// Per-device detail view. Renders entirely from the device descriptor:
/// capability states drive rows, behaviors drive actions. No per-device
/// branches — supporting a new device needs no UI code when its
/// capabilities are known (see `UI/Sections/DeviceSections.swift`).
struct DeviceDetailView: View {
    @Bindable var device: LogiDevice

    @State var showAdvanced = false

    var body: some View {
        if !device.isFeaturesLoaded {
            loadingView
        } else if device.toggles.isEmpty && device.ints.isEmpty
            && device.doubles.isEmpty && device.segmented.isEmpty
            && device.hosts.hosts.isEmpty {
            GenericDeviceView(device: device)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Battery
                if device.hasFeature(BatteryFeature.featureId) {
                    batteryRow
                    separator
                }

                // Feature load error / connection warning
                if let error = device.featureLoadError {
                    featureWarningBanner(error)
                    separator
                }

                // Main capabilities in descriptor order
                ForEach(mainCapabilities, id: \.id) { capability in
                    capabilitySection(capability)
                    separator
                }

                // Host Info
                if !device.hosts.hosts.isEmpty {
                    hostInfoSection
                    separator
                }

                // Advanced (DPI, force, scroll tuning, gesture thresholds)
                if hasAdvanced {
                    advancedSection
                    separator
                }

                // Reset
                resetSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Capability Filtering

    /// Top-level rows: non-advanced toggles/segmented in descriptor order.
    /// Battery, hosts, and slider-only rows render in dedicated sections.
    private var mainCapabilities: [DeviceCapability] {
        device.descriptor.capabilities.filter { capability in
            guard !capability.hidden, !capability.advanced else { return false }
            switch capability.id {
            case CapabilityID.battery, CapabilityID.hosts,
                 CapabilityID.backlightLevel, CapabilityID.pointerSpeed,
                 CapabilityID.hiResEnabled, CapabilityID.smartShiftTorque,
                 CapabilityID.dpi, CapabilityID.smoothScrollSpeed,
                 CapabilityID.smoothScrollMomentum, CapabilityID.smoothScrollThumbSpeed,
                 CapabilityID.gestureClickMs, CapabilityID.gestureDragThreshold:
                return false
            default:
                break
            }
            switch capability.kind {
            case .toggle:
                return device.toggles[capability.id] != nil
            case .segmented:
                return device.segmented[capability.id] != nil
            case .intSlider, .doubleSlider:
                return false
            case .info:
                return false
            }
        }
    }

    private var hasAdvanced: Bool {
        device.descriptor.capabilities.contains { capability in
            guard !capability.hidden, capability.advanced else { return false }
            switch capability.kind {
            case .toggle:
                return device.toggles[capability.id] != nil
            case .intSlider:
                // Thumb speed renders inside the thumb-wheel section, not here.
                if capability.id == CapabilityID.smoothScrollThumbSpeed { return false }
                return device.ints[capability.id] != nil
            case .doubleSlider:
                return device.doubles[capability.id] != nil
            case .segmented:
                return device.segmented[capability.id] != nil
            case .info:
                return false
            }
        }
    }

    @ViewBuilder
    private func capabilitySection(_ capability: DeviceCapability) -> some View {
        switch capability.id {
        case CapabilityID.smartShiftWheelMode:
            wheelModeSection
        case CapabilityID.smoothScrollEnabled:
            smoothScrollSection
        case CapabilityID.micMuteEnabled:
            micMuteSection
        case CapabilityID.backlightEnabled:
            backlightSection
        case CapabilityID.fnStandardKeys:
            fnKeysSection
        case CapabilityID.thumbWheelInverted:
            thumbWheelSection
        default:
            if let state = device.toggles[capability.id] {
                simpleToggle(state)
            }
        }
    }

    // MARK: - Bindings (internal for section builders)

    func toggleBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { device.toggles[id]?.value ?? false },
            set: { device.toggles[id]?.value = $0 }
        )
    }

    func commit(_ id: String) {
        Task { [device] in
            await device.commit(id)
        }
    }

    // MARK: - Shared Rows

    private var batteryRow: some View {
        row {
            Text("Battery")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            BatteryIndicator(level: device.battery.level, isCharging: device.battery.charging)

            Text(device.battery.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

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

    // MARK: - Host Info

    private var hostInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Easy-Switch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(device.hosts.hosts) { host in
                row {
                    Image(systemName: host.index == device.hosts.currentHostIndex
                        ? "checkmark.circle.fill"
                        : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(host.index == device.hosts.currentHostIndex ? .green : .secondary)

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
                            SettingsStore.clearSettings(for: device.name)
                            Task { [device] in
                                device.isFeaturesLoaded = false
                                await device.loadCapabilities()
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
}

// MARK: - Row Helpers

/// Reusable row: HStack(spacing: 8) with vertical padding.
func row<C: View>(@ViewBuilder content: () -> C) -> some View {
    HStack(spacing: 8) {
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
}

/// Separator between sections.
var separator: some View {
    Divider()
}

// MARK: - Reset Action Button

/// Styled button for inline reset confirmation (Cancel / Clear).
struct ResetActionButton: View {
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
