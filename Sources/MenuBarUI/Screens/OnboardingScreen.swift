import AppCore
import SwiftUI

struct OnboardingScreen: View {
    let permissions: PermissionState
    let onAction: (UIAction) -> Void

    @State private var autoContinue: Task<Void, Never>?

    private var requiredKinds: [PermissionKind] {
        PermissionKind.allCases.filter(\.isRequired)
    }

    private var grantedRequiredCount: Int {
        requiredKinds.filter { permissions.status(for: $0) == .granted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            permissionList
            footer
        }
        .padding(.horizontal, Metric.horizontalPadding)
        .onChange(of: permissions.requiredGranted) { _, ready in
            guard ready else { return }
            autoContinue?.cancel()
            autoContinue = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                onAction(.finishOnboarding)
            }
        }
        .onDisappear {
            autoContinue?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("A few permissions first")
                .font(.system(.callout, weight: .semibold))
            Text("They power scroll smoothing, gestures, and Bluetooth discovery.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !permissions.requiredGranted {
                Text("\(grantedRequiredCount) of \(requiredKinds.count) required granted")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var permissionList: some View {
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
    }

    private func row(for kind: PermissionKind) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: kind))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 16)

            VStack(alignment: .leading, spacing: 2) {
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
                rowAction(for: kind)
            }

            Spacer(minLength: 6)

            statusChip(for: kind)
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowAction(for kind: PermissionKind) -> some View {
        if kind == .inputMonitoring, permissions.accessibility != .granted {
            Button("Fix Accessibility") {
                onAction(accessibilityAction)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tint)
            .padding(.top, 1)
        } else {
            switch permissions.status(for: kind) {
            case .granted:
                EmptyView()
            case .denied:
                HStack(spacing: 8) {
                    Button("Open Settings") {
                        onAction(.openPermissionPane(kind))
                    }
                    if kind == .inputMonitoring {
                        Button("Relaunch") {
                            onAction(.relaunchApp)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.top, 1)
            case .unknown:
                Button("Enable") {
                    onAction(.requestPermission(kind))
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func statusChip(for kind: PermissionKind) -> some View {
        if kind == .inputMonitoring, permissions.accessibility != .granted {
            chip(text: "Needs Accessibility", tint: .orange)
        } else {
            let status = permissions.status(for: kind)
            Text(status.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tint(for: status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(tint(for: status).opacity(0.12)))
        }
    }

    private func chip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func tint(for status: PermissionStatus) -> Color {
        switch status {
        case .granted: .green
        case .denied: .orange
        case .unknown: .secondary
        }
    }

    private func icon(for kind: PermissionKind) -> String {
        switch kind {
        case .inputMonitoring: "computermouse"
        case .accessibility: "hand.raised"
        case .bluetooth: "dot.radiowaves.left.and.right"
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button("Check again") {
                    onAction(.refreshPermissions)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button(primaryTitle) {
                    primaryAction()
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(primaryTitle == "Continue" && !permissions.requiredGranted)
            }

            if permissions.accessibility != .granted {
                Text(
                    "Accessibility first: macOS reports Input Monitoring as denied until it is granted."
                )
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            } else if permissions.inputMonitoring != .granted {
                Text(
                    "Still denied after granting? Remove MXControl from the list and add it again — old entries stop matching after a re-sign."
                )
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var primaryTitle: String {
        if permissions.requiredGranted {
            return "Continue"
        }
        if requiredKinds.contains(where: { permissions.status(for: $0) == .denied }) {
            return "Open System Settings"
        }
        return "Grant permissions"
    }

    private func primaryAction() {
        if permissions.requiredGranted {
            onAction(.finishOnboarding)
            return
        }
        if permissions.accessibility != .granted {
            onAction(accessibilityAction)
            return
        }
        if permissions.inputMonitoring != .granted {
            onAction(
                permissions.inputMonitoring == .denied
                    ? .openPermissionPane(.inputMonitoring)
                    : .requestPermission(.inputMonitoring)
            )
        }
    }

    private var accessibilityAction: UIAction {
        permissions.accessibility == .denied
            ? .openPermissionPane(.accessibility)
            : .requestPermission(.accessibility)
    }
}
