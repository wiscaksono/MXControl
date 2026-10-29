import AppCore
import AppKit
import SwiftUI

public struct PopoverView: View {
    public static let preferredWidth: CGFloat = 320
    public static let chromeHeight: CGFloat =
        Metric.headerHeight + Metric.footerHeight + 2 * Metric.hairlineHeight

    private let state: AppState
    private let scrollable: Bool
    private let maxContentHeight: CGFloat
    private let onAction: (UIAction) -> Void
    private let onHeightChange: ((CGFloat) -> Void)?

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameters:
    ///   - scrollable: `false` renders the content at full height, which is what
    ///     the snapshot target needs. The app uses `true`.
    ///   - maxContentHeight: viewport cap for the current screen, supplied by
    ///     the host so multi-display setups use the right screen.
    ///   - onHeightChange: reports the full popover height so an `NSPopover`
    ///     host can resize itself while staying anchored.
    public init(
        state: AppState,
        scrollable: Bool = true,
        maxContentHeight: CGFloat = 760,
        onAction: @escaping (UIAction) -> Void = { _ in },
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.state = state
        self.scrollable = scrollable
        self.maxContentHeight = maxContentHeight
        self.onAction = onAction
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            contentView
            hairline
            footer
        }
        .frame(width: Self.preferredWidth)
        .background(backgroundColor)
    }

    /// Snapshots need a solid fill because materials are AppKit-backed and do
    /// not render offscreen. In the app the popover draws its own material, so
    /// the view stays transparent.
    private var backgroundColor: Color {
        if !scrollable || reduceTransparency {
            return Color(nsColor: .windowBackgroundColor)
        }
        return .clear
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.12))
            .frame(height: Metric.hairlineHeight)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 2) {
            if state.route != .root {
                Button {
                    onAction(.back)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())
                .help("Back")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ZStack(alignment: .leading) {
                Text(headerTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .id(headerTitle)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 10)),
                            removal: .opacity.combined(with: .offset(x: -6))
                        )
                    )
            }

            Spacer(minLength: 8)

            headerAccessory
        }
        .padding(.leading, state.route == .root ? 10 : 4)
        .padding(.trailing, 4)
        .frame(height: Metric.headerHeight)
        .animation(
            Motion.resolved(Motion.screen, reduceMotion: reduceMotion),
            value: state.route
        )
        .compositingGroup()
        .clipped()
        .focusEffectDisabled()
    }

    private var headerTitle: String {
        switch state.route {
        case .root: "MXControl"
        case .device: state.activeDetail?.device.name ?? "Device"
        case .general: "Settings"
        }
    }

    @ViewBuilder
    private var headerAccessory: some View {
        switch state.route {
        case .root:
            Button {
                onAction(.openGeneral)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help("Settings")
        case .device, .general:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if scrollable {
            ScrollView {
                content
                    .padding(.vertical, 10)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .id(state.route)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.combined(with: .offset(y: -6))
                        )
                    )
            }
            .frame(height: viewportHeight)
            .animation(
                Motion.resolved(Motion.screen, reduceMotion: reduceMotion),
                value: state.route
            )
            .onPreferenceChange(ContentHeightKey.self) { measured in
                contentHeight = measured
                onHeightChange?(Self.chromeHeight + viewportHeight(for: measured))
            }
        } else {
            content
                .padding(.vertical, 10)
        }
    }

    /// Contents are measured because a ScrollView never reports an intrinsic
    /// height; with only a `maxHeight` the viewport collapses to zero.
    private var viewportHeight: CGFloat {
        viewportHeight(for: contentHeight)
    }

    private func viewportHeight(for measured: CGFloat) -> CGFloat {
        PopoverSizing.viewportHeight(measured: measured, maxViewport: maxContentHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch state.route {
        case .root:
            RootScreen(state: state, onAction: onAction)
        case let .device(id):
            if let detail = state.details[id] {
                DeviceScreen(detail: detail, onAction: onAction)
            } else {
                RootScreen(state: state, onAction: onAction)
            }
        case .general:
            GeneralScreen(sections: state.general, onAction: onAction)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                onAction(.refresh)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())
            .help("Rescan")

            Spacer()

            Text(state.version)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                onAction(.quit)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(IconButtonStyle())
            .help("Quit")
        }
        .padding(.horizontal, 4)
        .frame(height: Metric.footerHeight)
        .focusEffectDisabled()
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
