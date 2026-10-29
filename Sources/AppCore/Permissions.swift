import Foundation

public enum PermissionKind: String, Sendable, Equatable, CaseIterable {
    case inputMonitoring
    case accessibility
    case bluetooth

    public var title: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        case .bluetooth: "Bluetooth"
        }
    }

    public var detail: String {
        switch self {
        case .inputMonitoring: "Reads the mouse wheel so scrolling can be smoothed."
        case .accessibility: "Installs the scroll interceptor and button gestures."
        case .bluetooth: "Finds devices connected directly over Bluetooth."
        }
    }
}

public enum PermissionStatus: Sendable, Equatable {
    case granted
    /// Granted in System Settings, but this process started before the grant
    /// and has to restart before the kernel will honor it.
    case needsRelaunch
    case denied
    case unknown

    public var label: String {
        switch self {
        case .granted: "Allowed"
        case .needsRelaunch: "Restart needed"
        case .denied: "Denied"
        case .unknown: "Not requested"
        }
    }
}

public struct PermissionState: Sendable, Equatable {
    public var inputMonitoring: PermissionStatus
    public var accessibility: PermissionStatus
    public var bluetooth: PermissionStatus

    public init(
        inputMonitoring: PermissionStatus = .unknown,
        accessibility: PermissionStatus = .unknown,
        bluetooth: PermissionStatus = .unknown
    ) {
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.bluetooth = bluetooth
    }

    public static let allGranted = PermissionState(
        inputMonitoring: .granted,
        accessibility: .granted,
        bluetooth: .granted
    )

    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .inputMonitoring: inputMonitoring
        case .accessibility: accessibility
        case .bluetooth: bluetooth
        }
    }

    public var requiredGranted: Bool {
        PermissionKind.allCases.allSatisfy { status(for: $0) == .granted }
    }
}

public protocol PermissionsService: Sendable {
    func status() async -> PermissionState
    /// Triggers the system prompt when the OS allows one; no-op otherwise.
    func request(_ kind: PermissionKind) async
}

public struct DummyPermissionsService: PermissionsService {
    public init() {}

    public func status() async -> PermissionState {
        .allGranted
    }

    public func request(_ kind: PermissionKind) async {}
}
