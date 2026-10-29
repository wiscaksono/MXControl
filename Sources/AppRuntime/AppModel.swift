import AppCore
import DeviceCore
import Foundation
import Observation

/// Coordinates app state. It owns the screen state and talks to a
/// `DeviceService`; it never touches HID++ or AppKit.
@Observable
public final class AppModel {
    public private(set) var state: AppState

    private let service: any DeviceService
    private let scanDelay: Duration
    private var scanTask: Task<Void, Never>?

    public init(
        state: AppState = DummyData.initialState(),
        service: any DeviceService = DummyDeviceService(),
        scanDelay: Duration = .milliseconds(600)
    ) {
        self.state = state
        self.service = service
        self.scanDelay = scanDelay
    }

    public func handle(_ action: UIAction) {
        switch action {
        case let .openDevice(id):
            state.route = .device(id)
        case .openGeneral:
            state.route = .general
        case .back:
            state.route = .root
        case let .toggle(itemID):
            state.toggleItem(itemID)
            pushChange(itemID)
        case let .setSlider(itemID, value):
            state.setSlider(itemID, to: value)
            pushChange(itemID)
        case let .selectOption(itemID, index):
            state.selectOption(itemID, index: index)
            pushChange(itemID)
        case .activate:
            break // action rows are confirmed by the controller first
        case .resetAll:
            state = DummyData.initialState(route: state.route)
        case .openPermissionSettings:
            break // handled in the app layer, which owns NSWorkspace
        case .refresh:
            refresh()
        case .quit:
            break // handled in the app layer, which owns NSApp
        }
    }

    private func refresh() {
        guard !state.isScanning else { return }
        state.beginScan()

        scanTask?.cancel()
        scanTask = Task { @MainActor in
            // Keep the scanning state visible even when the service is instant.
            try? await Task.sleep(for: scanDelay)
            guard !Task.isCancelled else { return }

            let snapshot = await service.scan()
            guard !Task.isCancelled else { return }
            state.finishScan(
                devices: snapshot.devices,
                details: snapshot.details,
                warning: snapshot.warning
            )
        }
    }

    /// Push the real system value into the general screen at launch.
    public func syncGeneralToggle(_ itemID: String, to value: Bool) {
        state.setGeneralToggle(itemID, to: value)
    }

    /// Optimistic UI: the local state already changed, so forward the same
    /// value to the device and adopt whatever the service reports back.
    private func pushChange(_ itemID: String) {
        guard case let .device(deviceID) = state.route,
              let value = state.settingValue(itemID) else { return }

        let change = DeviceChange(deviceID: deviceID, itemID: itemID, value: value)
        Task { @MainActor in
            guard let snapshot = await service.apply(change) else { return }
            state.devices = snapshot.devices
            state.details = snapshot.details
        }
    }
}

public extension AppModel {
    static let shared = AppModel(
        state: AppState(general: DummyData.generalSettings, version: DummyData.version),
        service: HIDPPDeviceService()
    )
}
