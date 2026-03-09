import SwiftUI

/// A labeled row with a toggle switch, sized for compact menu bar UI.
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var subtitle: String?
    var onChange: ((Bool) -> Void)?

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onChange(of: isOn) { _, newValue in
            onChange?(newValue)
        }
    }
}
