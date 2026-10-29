import AppCore
import SwiftUI

struct SwitchView: View {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.16))
            .frame(width: 34, height: 20)
            .overlay {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
                    .offset(x: isOn ? 7 : -7)
            }
            .animation(
                Motion.resolved(Motion.control, reduceMotion: reduceMotion),
                value: isOn
            )
    }
}

struct SliderTrack: View {
    let spec: SliderSpec
    let label: String
    let onChange: (Double) -> Void

    @State private var grabOffset: CGFloat?

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
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Keep the thumb where the pointer grabbed it instead of
                        // snapping its center under the cursor.
                        let thumbCenter = 7 + travel * spec.fraction
                        let offset = grabOffset ?? (value.startLocation.x - thumbCenter)
                        if grabOffset == nil {
                            grabOffset = offset
                        }

                        let center = value.location.x - offset
                        let ratio = min(max((center - 7) / travel, 0), 1)
                        let span = spec.range.upperBound - spec.range.lowerBound
                        let raw = spec.range.lowerBound + ratio * span
                        let stepped = (raw / spec.step).rounded() * spec.step
                        onChange(min(max(stepped, spec.range.lowerBound), spec.range.upperBound))
                    }
                    .onEnded { _ in grabOffset = nil }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spec.displayValue))
        .accessibilityAdjustableAction { direction in
            let keyboardStep = max(spec.step, (spec.range.upperBound - spec.range.lowerBound) / 20)
            switch direction {
            case .increment:
                onChange(min(spec.value + keyboardStep, spec.range.upperBound))
            case .decrement:
                onChange(max(spec.value - keyboardStep, spec.range.lowerBound))
            @unknown default:
                break
            }
        }
    }
}

struct SegmentedControl: View {
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .accessibilityLabel(Text(options[index]))
                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .animation(
            Motion.resolved(Motion.control, reduceMotion: reduceMotion),
            value: selectedIndex
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
            Image(systemName: battery.isCharging ? "bolt.fill" : battery.symbolName)
                .font(.system(size: size * 0.26, weight: .semibold))
                .foregroundStyle(battery.band.ringTint)
        }
        .frame(width: size, height: size)
    }
}

struct BatteryPill: View {
    let battery: BatteryState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: battery.isCharging ? "bolt.fill" : battery.symbolName)
                .font(.caption2)
                .fontWeight(.semibold)
            Text("\(battery.level)%")
                .font(.caption2)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(battery.band.pillTint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(battery.band.pillTint.opacity(0.12)))
        .animation(
            Motion.resolved(Motion.control, reduceMotion: reduceMotion),
            value: battery.level
        )
    }
}

struct SpinningIcon: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            SpinnerArc()
                .stroke(
                    Color.secondary,
                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
                )
                .frame(width: 10, height: 10)
                .rotationEffect(
                    .degrees(seconds.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360)
                )
        }
    }
}

private nonisolated struct SpinnerArc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - 0.625
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(270),
            clockwise: false
        )
        return path
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(configuration.isPressed ? Color.primary.opacity(0.55) : Color
                .secondary)
            .frame(width: 28, height: 24)
            .background(
                RoundedRectangle(cornerRadius: Metric.controlCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .contentShape(Rectangle())
    }
}

struct FilledButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Metric.controlCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Metric.controlCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .contentShape(Rectangle())
    }
}

/// List rows: press feedback has to land on mouse-down, before the click
/// commits, otherwise the row feels dead.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
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
