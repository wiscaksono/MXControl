import Foundation

public enum DeviceKind: String, Equatable, Sendable, CaseIterable {
    case mouse
    case keyboard
    case other

    public var label: String {
        switch self {
        case .mouse: "Mouse"
        case .keyboard: "Keyboard"
        case .other: "Device"
        }
    }

    public var symbolName: String {
        switch self {
        case .mouse: "computermouse.fill"
        case .keyboard: "keyboard.fill"
        case .other: "questionmark.circle"
        }
    }
}

public enum TransportKind: String, Equatable, Sendable, Codable, CaseIterable {
    case usb
    case ble

    public var label: String {
        rawValue.uppercased()
    }
}

public struct BatteryState: Equatable, Sendable {
    public var level: Int
    public var isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }

    public var isLow: Bool {
        level <= 20
    }

    public var isCritical: Bool {
        level <= 10
    }
}

public struct DeviceSummary: Identifiable, Equatable, Sendable {
    public let id: DeviceID
    public var name: String
    public var kind: DeviceKind
    public var transport: TransportKind
    public var battery: BatteryState
    public var isConnected: Bool

    public init(
        id: DeviceID,
        name: String,
        kind: DeviceKind,
        transport: TransportKind,
        battery: BatteryState,
        isConnected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.transport = transport
        self.battery = battery
        self.isConnected = isConnected
    }
}
