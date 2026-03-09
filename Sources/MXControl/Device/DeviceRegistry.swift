import Foundation

/// Known device types.
enum DeviceType: String, Sendable {
    case mouse
    case keyboard
    case receiver
    case unknown
}

/// Static lookup for known Logitech device PIDs and model IDs.
enum DeviceRegistry {

    // MARK: - Known Bolt/Unifying Receiver PIDs

    static let receiverPIDs: Set<Int> = [
        0xC52B,  // Unifying
        0xC52D,  // Unifying (alt)
        0xC52E,  // Unifying (alt)
        0xC534,  // Nano
        0xC539,  // Lightspeed
        0xC53A,  // Lightspeed (alt)
        0xC547,  // Bolt (alt)
        0xC548,  // Bolt
        0xC549,  // Bolt (alt)
    ]

    /// Check if a USB PID is a known receiver.
    static func isReceiver(pid: Int) -> Bool {
        receiverPIDs.contains(pid)
    }

    // MARK: - Known BLE Device PIDs

    /// BLE product IDs for known Logitech devices (direct BLE connection, no receiver).
    /// These PIDs appear in the GATT Device Information service (PnP ID characteristic)
    /// or can be queried via HID++ DeviceNameType feature.
    struct BLEDeviceInfo {
        let pid: Int
        let name: String
        let type: DeviceType
    }

    static let bleDevices: [BLEDeviceInfo] = [
        BLEDeviceInfo(pid: 0xB034, name: "MX Master 3S", type: .mouse),
        BLEDeviceInfo(pid: 0xB369, name: "MX Keys Mini", type: .keyboard),
        // Add more BLE PIDs here as devices are tested
    ]

    /// Look up a BLE device by PID.
    static func bleDevice(pid: Int) -> BLEDeviceInfo? {
        bleDevices.first { $0.pid == pid }
    }

    /// Check if a PID is a known BLE direct-connect device.
    static func isBLEDevice(pid: Int) -> Bool {
        bleDevices.contains { $0.pid == pid }
    }

    // MARK: - Known Feature Names

    /// Human-readable names for common HID++ 2.0 feature IDs.
    static let featureNames: [UInt16: String] = [
        0x0000: "Root",
        0x0001: "FeatureSet",
        0x0003: "FirmwareInfo",
        0x0005: "DeviceNameType",
        0x0007: "DeviceFriendlyName",
        0x0008: "SwitchAndKeepAlive",
        0x0020: "ConfigChange",
        0x1000: "BatteryLevelStatus",
        0x1001: "BatteryVoltage",
        0x1004: "UnifiedBattery",
        0x1300: "LEDControl",
        0x1814: "ChangeHost",
        0x1815: "HostsInfos",
        0x1B04: "SpecialKeysV4",
        0x1B10: "ControlList",
        0x1D4B: "WirelessStatus",
        0x1E00: "EnableHiddenFeatures",
        0x1F20: "ADCMeasurement",
        0x1981: "KeyboardBacklightV1",
        0x1982: "BacklightV2",
        0x1983: "KeyboardBacklightV3",
        0x19B0: "HapticFeedback",
        0x2110: "SmartShift",
        0x2111: "SmartShiftV2",
        0x2121: "HiResWheel",
        0x2130: "RatchetWheel",
        0x2150: "Thumbwheel",
        0x2201: "AdjustableDPI",
        0x2202: "ExtendedAdjustableDPI",
        0x2205: "PointerMotionScaling",
        0x2230: "AngleSnapping",
        0x2240: "SurfaceTuning",
        0x40A0: "FnInversionV0",
        0x40A2: "FnInversionV2",
        0x40A3: "FnInversionV3",
        0x4220: "LockKeyState",
        0x4521: "DisableKeys",
        0x4522: "DisableKeysByUsage",
        0x4531: "MultiPlatform",
        0x4540: "KBLayout",
        0x8060: "ReportRate",
        0x8061: "ExtendedReportRate",
        0x8070: "ColorLEDEffects",
        0x8071: "RGBEffects",
        0x8100: "OnboardProfiles",
        0x00C0: "DFUControlV0",
        0x00C3: "DFUControlV3",
        0x00D0: "DFU",
    ]

    /// Get human-readable name for a feature ID, or hex string if unknown.
    static func featureName(for id: UInt16) -> String {
        featureNames[id] ?? String(format: "0x%04X", id)
    }
}
