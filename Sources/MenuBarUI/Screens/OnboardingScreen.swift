import AppCore
import SwiftUI

struct OnboardingScreen: View {
    let permissions: PermissionState
    let onAction: (UIAction) -> Void

    @State private var autoContinue: Task<Void, Never>?
    @State private var bluetoothSkipped = false

    /// Order matters: macOS composes Input Monitoring on top of Accessibility,
    /// so Accessibility has to land first.
    private let stepOrder: [PermissionKind] = [.accessibility, .inputMonitoring, .bluetooth]

    private var currentIndex: Int {
        if let index = stepOrder.firstIndex(where: {
            $0 != .bluetooth && permissions.status(for: $0) != .granted
        }) {
            return index
        }
        return stepOrder.count - 1
    }

    private var currentKind: PermissionKind {
        stepOrder[currentIndex]
    }

    private var isLastStep: Bool {
        currentIndex == stepOrder.count - 1
    }

    private var progressLabel: String {
        if currentKind == .bluetooth {
            return "Optional · Step \(currentIndex + 1) of \(stepOrder.count)"
        }
        return "Step \(currentIndex + 1) of \(stepOrder.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stepCard
            footer
        }
        .padding(.horizontal, Metric.horizontalPadding)
        .onChange(of: permissions) { _, state in
            guard state.requiredGranted, state.bluetooth == .granted || bluetoothSkipped else {
                return
            }
            scheduleFinish()
        }
        .onDisappear {
            autoContinue?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Set up permissions")
                .font(.system(.callout, weight: .semibold))
            Text("One at a time — each one unlocks a different part of MXControl.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(progressLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: icon(for: currentKind))
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentKind.title)
                        .font(.system(.callout, weight: .semibold))
                    Text(currentKind.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                chip(for: currentKind)
            }

            if currentKind == .inputMonitoring, permissions.accessibility != .granted {
                Text("macOS reports Input Monitoring as denied until Accessibility is granted.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if currentKind == .inputMonitoring, permissions.accessibility == .granted,
               permissions.inputMonitoring == .denied
            {
                Text(
                    "Still denied? Remove MXControl from the list and add it again — old entries stop matching after a re-sign."
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Metric.cornerRadius, style: .continuous)
                .fill(Color.panelFill)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(FilledButtonStyle())
                .frame(maxWidth: .infinity)

            HStack {
                if currentKind == .bluetooth {
                    Button("Continue without Bluetooth") {
                        bluetoothSkipped = true
                        onAction(.finishOnboarding)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                } else {
                    Button("Check again") {
                        onAction(.refreshPermissions)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentKind == .inputMonitoring,
                   permissions.status(for: .inputMonitoring) == .denied
                {
                    Button("Relaunch") {
                        onAction(.relaunchApp)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var primaryTitle: String {
        switch permissions.status(for: currentKind) {
        case .granted:
            isLastStep ? "Continue" : "Next"
        case .denied:
            "Open System Settings"
        case .unknown:
            "Enable"
        }
    }

    private func primaryAction() {
        switch permissions.status(for: currentKind) {
        case .granted:
            if isLastStep {
                onAction(.finishOnboarding)
            } else {
                onAction(.refreshPermissions)
            }
        case .denied:
            onAction(.openPermissionPane(currentKind))
        case .unknown:
            onAction(.requestPermission(currentKind))
        }
    }

    private func chip(for kind: PermissionKind) -> some View {
        let status = permissions.status(for: kind)
        let tint: Color = switch status {
        case .granted: .green
        case .denied: .orange
        case .unknown: .secondary
        }
        return Text(status.label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func icon(for kind: PermissionKind) -> String {
        switch kind {
        case .inputMonitoring: "computermouse"
        case .accessibility: "hand.raised"
        case .bluetooth: "dot.radiowaves.left.and.right"
        }
    }

    private func scheduleFinish() {
        autoContinue?.cancel()
        autoContinue = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            onAction(.finishOnboarding)
        }
    }
}
