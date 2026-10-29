import AppCore
import SwiftUI

struct GeneralScreen: View {
    let sections: [SettingSection]
    let onAction: (UIAction) -> Void

    var body: some View {
        VStack(spacing: Metric.groupSpacing) {
            ForEach(sections) { section in
                SettingsGroup(section: section, onAction: onAction)
            }
        }
        .padding(.horizontal, Metric.horizontalPadding)
    }
}
