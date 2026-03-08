import Foundation

/// HID++ 2.0 DeviceNameAndType (0x0005) — get device model name and type.
enum DeviceNameFeature {

    static let featureId: UInt16 = 0x0005

    /// Device type codes from HID++ 2.0.
    enum DeviceKind: UInt8, Sendable, CustomStringConvertible {
        case keyboard = 0
        case remoteControl = 1
        case numpad = 2
        case mouse = 3
        case touchpad = 4
        case trackball = 5
        case presenter = 6
        case receiver = 7
        case headset = 8
        case webcam = 9
        case steeringWheel = 10
        case joystick = 11
        case gamepad = 12
        case dock = 13
        case speaker = 14
        case microphone = 15
        case unknown = 0xFF

        var description: String {
            switch self {
            case .keyboard: return "Keyboard"
            case .remoteControl: return "Remote Control"
            case .numpad: return "Numpad"
            case .mouse: return "Mouse"
            case .touchpad: return "Touchpad"
            case .trackball: return "Trackball"
            case .presenter: return "Presenter"
            case .receiver: return "Receiver"
            case .headset: return "Headset"
            case .webcam: return "Webcam"
            case .steeringWheel: return "Steering Wheel"
            case .joystick: return "Joystick"
            case .gamepad: return "Gamepad"
            case .dock: return "Dock"
            case .speaker: return "Speaker"
            case .microphone: return "Microphone"
            case .unknown: return "Unknown"
            }
        }
    }

    // MARK: - Function 0: GetNameLength

    /// Get the total length of the device name string.
    static func getNameLength(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Int {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return Int(response.params[0])
    }

    // MARK: - Function 1: GetName

    /// Get a chunk of the device name starting at the given offset.
    /// Each call returns up to 16 bytes of the name (long report payload minus overhead).
    static func getNameChunk(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        offset: UInt8
    ) async throws -> String {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [offset]
        )

        // Response params contain UTF-8 name bytes (null-padded)
        let nameBytes = response.params.prefix(while: { $0 != 0 })
        return String(bytes: nameBytes, encoding: .utf8) ?? ""
    }

    // MARK: - Function 2: GetType

    /// Get the device type code.
    static func getType(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> DeviceKind {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01
        )

        return DeviceKind(rawValue: response.params[0]) ?? .unknown
    }

    // MARK: - Convenience: Full Name

    /// Get the complete device name, handling multi-chunk reads.
    static func getFullName(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> String {
        let totalLength = try await getNameLength(
            transport: transport,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex
        )

        var name = ""
        var offset: UInt8 = 0

        while name.count < totalLength {
            let chunk = try await getNameChunk(
                transport: transport,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                offset: offset
            )

            if chunk.isEmpty { break }
            name += chunk
            offset = UInt8(name.count)
        }

        return name
    }
}
