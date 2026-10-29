import AppCore
import SwiftUI

struct OnboardingScreen: View {
    let permissions: PermissionState
    let onAction: (UIAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("A few permissions first")
                    .font(.system(.callout, weight: .semibold))
                Text("They power scroll smoothing, gestures, and Bluetooth discovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element.rawValue) {
                    index, kind in
                    row(for: kind)
                    if index < PermissionKind.allCases.count - 1 {
                        Divider().opacity(0.6)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.panelFill)
            )

            HStack {
                Button("Skip for now") {
                    onAction(.skipOnboarding)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Continue") {
                    onAction(.finishOnboarding)
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(!permissions.requiredGranted)
                .opacity(permissions.requiredGranted ? 1 : 0.45)
            }
        }
        .padding(.horizontal, Metric.horizontalPadding)
    }

    private func row(for kind: PermissionKind) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(kind.title)
                        .font(.system(.callout))
                    if !kind.isRequired {
                        Text("Optional")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(kind.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            action(for: kind)
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func action(for kind: PermissionKind) -> some View {
        switch permissions.status(for: kind) {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .trailing, spacing: 2) {
                Button("Open Settings") {
                    onAction(.openPermissionPane(kind))
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
                Button("Relaunch") {
                    onAction(.relaunchApp)
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        case .unknown:
            Button("Enable") {
                onAction(.requestPermission(kind))
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
        }
    }
}
