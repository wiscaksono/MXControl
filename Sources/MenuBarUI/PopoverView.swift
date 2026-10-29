import AppCore
import AppKit
import SwiftUI

public struct PopoverView: View {
    public static let preferredWidth: CGFloat = 320

    private let state: AppState
    private let scrollable: Bool
    private let onAction: (UIAction) -> Void
    private let onHeightChange: ((CGFloat) -> Void)?

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// - Parameter scrollable: `false` renders the content at full height, which
    ///   is what the snapshot target needs. The app uses `true`.
    /// - Parameter onHeightChange: reports the full popover height so an
    ///   `NSPopover` host can resize itself while staying anchored.
    public init(
        state: AppState,
        scrollable: Bool = true,
        onAction: @escaping (UIAction) -> Void = { _ in },
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.state = state
        self.scrollable = scrollable
        self.onAction = onAction
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            contentView
            Divider().opacity(0.6)
            footer
        }
        .frame(width: Self.preferredWidth)
        .background(backgroundColor)
    }

    /// Header, footer and two hairlines. The scroll viewport is added on top.
    public static let chromeHeight: CGFloat = 40 + 30 + 2

    /// Snapshots need a solid fill because materials are AppKit-backed and do
    /// not render offscreen. In the app the window draws its own material, so
    /// the view stays transparent and the native corners and shadow survive.
    private var backgroundColor: Color {
        if !scrollable || reduceTransparency {
            return Color(nsColor: .windowBackgroundColor)
        }
        return .clear
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if state.route == .root {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            } else {
                Button {
                    onAction(.back)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())
                .help("Back")
            }

            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            headerAccessory
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
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
        case .device:
            if let detail = state.activeDetail {
                BatteryPill(battery: detail.device.battery)
            }
        case .general:
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
            }
            .frame(height: viewportHeight)
            .onPreferenceChange(ContentHeightKey.self) { measured in
                contentHeight = measured
                onHeightChange?(Self.chromeHeight + min(measured, maxContentHeight))
            }
        } else {
            content
                .padding(.vertical, 10)
        }
    }

    /// Contents are measured because a ScrollView never reports an intrinsic
    /// height; with only a `maxHeight` the window collapses to header + footer.
    private var viewportHeight: CGFloat {
        guard contentHeight > 1 else { return 240 }
        return min(contentHeight, maxContentHeight)
    }

    private var maxContentHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(280, screenHeight - 140)
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
                .font(.system(size: 9))
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
        .padding(.horizontal, 10)
        .frame(height: 30)
        .focusEffectDisabled()
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
