import SwiftUI

/// Compact app-level settings displayed inside the menu bar popover.
struct GeneralSettingsView: View {
    @Binding var launchAtLogin: Bool
    @Binding var hideAppUntilReopened: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GeneralSettingsSection(title: "Startup") {
                    ToggleRow(
                        label: "Launch at login",
                        isOn: $launchAtLogin,
                        subtitle: "Start MXControl automatically when you sign in."
                    )
                }

                GeneralSettingsSection(title: "Visibility") {
                    ToggleRow(
                        label: "Hide MXControl until reopened",
                        isOn: $hideAppUntilReopened,
                        subtitle: "Removes the menu bar icon. Reopen MXControl from Finder or Spotlight to bring it back."
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GeneralSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}
