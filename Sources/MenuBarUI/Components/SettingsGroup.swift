import AppCore
import SwiftUI

struct SettingsGroup: View {
    let section: SettingSection
    let onAction: (UIAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title = section.title {
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    SettingRow(item: item, onAction: onAction)
                    if index < section.items.count - 1 {
                        Divider()
                            .opacity(0.6)
                            .padding(.leading, Metric.rowPadding)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.panelFill)
            )
        }
    }
}

struct SettingRow: View {
    let item: SettingItem
    let onAction: (UIAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch item.control {
            case let .toggle(isOn):
                toggleRow(isOn: isOn)
            case let .slider(spec):
                sliderRow(spec)
            case let .picker(options, selectedIndex):
                pickerRow(options: options, selectedIndex: selectedIndex)
            case let .action(detail):
                actionRow(detail: detail)
            case let .info(value):
                infoRow(value: value)
            }
        }
        .opacity(item.isEnabled ? 1 : 0.45)
    }

    private func toggleRow(isOn: Bool) -> some View {
        Button {
            onAction(.toggle(itemID: item.id))
        } label: {
            HStack(spacing: 10) {
                titleBlock
                Spacer(minLength: 8)
                SwitchView(isOn: isOn)
            }
            .padding(.horizontal, Metric.rowPadding)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(!item.isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }

    private func sliderRow(_ spec: SliderSpec) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(item.title)
                    .font(.system(.callout))
                Spacer()
                Text(spec.displayValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(
                        Motion.resolved(Motion.control, reduceMotion: reduceMotion),
                        value: spec.value
                    )
            }
            SliderTrack(spec: spec, label: item.title) { value in
                onAction(.setSlider(itemID: item.id, value: value))
            }
            HStack {
                Text(spec.minimumLabel)
                Spacer()
                Text(spec.maximumLabel)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, 8)
    }

    private func pickerRow(options: [String], selectedIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titleBlock
            SegmentedControl(options: options, selectedIndex: selectedIndex) { index in
                onAction(.selectOption(itemID: item.id, index: index))
            }
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, 8)
    }

    private func actionRow(detail: String?) -> some View {
        Button {
            onAction(.activate(itemID: item.id))
        } label: {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(.callout))
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, Metric.rowPadding)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(Text(item.title))
    }

    private func infoRow(value: String) -> some View {
        HStack(spacing: 8) {
            Text(item.title)
                .font(.system(.callout))
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, 7)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(.system(.callout))
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
