import SwiftUI

/// A labeled row with a slider and current value display.
/// Uses a pending-value pattern: local @State tracks drag, commits only on release.
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    var suffix: String = ""

    /// Action called when slider drag ends (commit the value to device).
    var onCommit: (() -> Void)?

    @State private var pendingValue: Double?

    /// The displayed value: pending during drag, otherwise the bound value.
    private var displayValue: Double {
        pendingValue ?? value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                Spacer()

                Text(String(format: format, displayValue) + suffix)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Slider(value: Binding(
                get: { displayValue },
                set: { pendingValue = $0 }
            ), in: range, step: step) {
                EmptyView()
            } onEditingChanged: { editing in
                if !editing {
                    // Commit pending value to binding and device
                    if let pending = pendingValue {
                        value = pending
                        pendingValue = nil
                        onCommit?()
                    }
                }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Convenience Int Binding

extension SliderRow {
    /// Create a SliderRow with Int binding (converts to/from Double internally).
    init(
        label: String,
        intValue: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = "",
        onCommit: (() -> Void)? = nil
    ) {
        self.label = label
        self._value = Binding(
            get: { Double(intValue.wrappedValue) },
            set: { intValue.wrappedValue = Int($0) }
        )
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        self.step = Double(step)
        self.format = "%.0f"
        self.suffix = suffix
        self.onCommit = onCommit
    }
}
