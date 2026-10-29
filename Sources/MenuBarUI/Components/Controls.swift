import AppCore
import SwiftUI

struct SwitchView: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.16))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
            }
    }
}

struct SliderTrack: View {
    let spec: SliderSpec
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - 14, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: travel * spec.fraction, height: 4)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .frame(width: 14, height: 14)
                    .offset(x: travel * spec.fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let ratio = min(max((value.location.x - 7) / travel, 0), 1)
                    let span = spec.range.upperBound - spec.range.lowerBound
                    let raw = spec.range.lowerBound + ratio * span
                    let stepped = (raw / spec.step).rounded() * spec.step
                    onChange(min(max(stepped, spec.range.lowerBound), spec.range.upperBound))
                }
            )
        }
        .frame(height: 16)
    }
}

struct SegmentedControl: View {
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var selectedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Text(options[index])
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .foregroundStyle(index == selectedIndex ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(index == selectedIndex ? selectedFill : Color.clear)
                                .shadow(
                                    color: index == selectedIndex ? .black.opacity(0.12) : .clear,
                                    radius: 1,
                                    y: 0.5
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }
}

struct BatteryRing: View {
    let battery: BatteryState
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.03, Double(battery.level) / 100))
                .stroke(battery.band.ringTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(battery.band.ringTint)
            }
        }
        .frame(width: size, height: size)
    }
}

struct BatteryPill: View {
    let battery: BatteryState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: battery.isCharging ? "bolt.fill" : battery.symbolName)
                .font(.caption2)
                .fontWeight(.semibold)
            Text("\(battery.level)%")
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundStyle(battery.band.pillTint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(battery.band.pillTint.opacity(0.12)))
    }
}

struct TransportBadge: View {
    let transport: TransportKind

    private var tint: Color {
        transport == .ble ? .blue : .secondary
    }

    var body: some View {
        Text(transport.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .tracking(0.3)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(configuration.isPressed ? Color.primary.opacity(0.55) : Color
                .secondary)
            .frame(width: 24, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .contentShape(Rectangle())
    }
}

struct FilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Battery presentation

extension BatteryState {
    enum Band {
        case charging
        case critical
        case low
        case normal
    }

    var band: Band {
        if isCharging {
            return .charging
        }
        if isCritical {
            return .critical
        }
        if isLow {
            return .low
        }
        return .normal
    }

    var symbolName: String {
        switch level {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }
}

private extension BatteryState.Band {
    var ringTint: Color {
        switch self {
        case .charging: .accentColor
        case .critical: .red
        case .low: .orange
        case .normal: .green
        }
    }

    var pillTint: Color {
        switch self {
        case .charging: .accentColor
        case .critical: .red
        case .low: .orange
        case .normal: .secondary
        }
    }
}
