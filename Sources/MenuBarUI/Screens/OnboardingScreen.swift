import AppCore
import os
import SwiftUI

private let logger = Logger(subsystem: "com.wiscaksono.mxcontrol", category: "onboarding")

struct OnboardingScreen: View {
    let permissions: PermissionState
    let onAction: (UIAction) -> Void

    @State private var furthestStep = 0

    /// Order matters: macOS composes Input Monitoring on top of Accessibility,
    /// so Accessibility has to land first.
    private let stepOrder: [PermissionKind] = [.accessibility, .inputMonitoring, .bluetooth]

    /// First step whose required permission is still missing.
    private var requiredStep: Int {
        if let index = stepOrder.firstIndex(where: { permissions.status(for: $0) != .granted }) {
            return index
        }
        return stepOrder.count - 1
    }

    /// Steps only move forward. A transient "denied" (TCC being edited in
    /// System Settings) must not throw the user back while a prompt is open.
    private var currentIndex: Int {
        max(requiredStep, furthestStep)
    }

    private var currentKind: PermissionKind {
        stepOrder[currentIndex]
    }

    private var isLastStep: Bool {
        currentIndex == stepOrder.count - 1
    }

    private var progressLabel: String {
        "Step \(currentIndex + 1) of \(stepOrder.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stepCard
            footer
        }
        .padding(.horizontal, Metric.horizontalPadding)
        .onChange(of: requiredStep) { _, step in
            guard step > furthestStep else { return }
            furthestStep = step
        }
        .onChange(of: currentIndex) { _, index in
            let kind = stepOrder[index]
            logger.notice(
                "[Onboarding] step \(index + 1)/\(stepOrder.count) kind=\(kind.rawValue, privacy: .public) \(statusSummary, privacy: .public)"
            )
        }
        .onAppear {
            // Start from the first missing grant, and never move backwards.
            furthestStep = max(furthestStep, requiredStep)
            logger.notice("[Onboarding] shown \(statusSummary, privacy: .public)")
        }
    }

    private var statusSummary: String {
        PermissionKind.allCases
            .map { "\($0.rawValue)=\(permissions.status(for: $0).label)" }
            .joined(separator: " ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Set up permissions")
                .font(.system(.callout, weight: .semibold))
            Text("One at a time. Each step unlocks a different part of MXControl.")
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

            if currentKind == .inputMonitoring,
               permissions.inputMonitoring == .needsRelaunch
            {
                Text(
                    "Granted. Restart MXControl so macOS hands the listener access to the new process."
                )
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if currentKind == .inputMonitoring, permissions.accessibility == .granted,
               permissions.inputMonitoring == .denied
            {
                Text(
                    "Still denied? Remove MXControl from the list and add it again. Old entries stop matching after a re-sign."
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
        Button(primaryTitle, action: primaryAction)
            .buttonStyle(FilledButtonStyle(fullWidth: true))
    }

    private var primaryTitle: String {
        switch permissions.status(for: currentKind) {
        case .granted:
            isLastStep ? "Continue" : "Next"
        case .needsRelaunch:
            "Relaunch MXControl"
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
        case .needsRelaunch:
            onAction(.relaunchApp)
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
        case .needsRelaunch, .denied: .orange
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
}
