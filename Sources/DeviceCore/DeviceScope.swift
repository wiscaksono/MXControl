import Foundation

extension LogiDevice {
    /// Stable settings identity: descriptor id plus HID++ unit id. The device
    /// name is not unique and the random UUID changes every launch, so neither
    /// can be used as a key.
    var settingScope: String {
        "\(descriptor.id).\(deviceIndex)"
    }
}
