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
    private let refreshInterval: Duration
    private var scanTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pendingChange: Task<Void, Never>?
    private var changeGeneration = 0
    private var lastChangeAt = Date.distantPast
    private var isUIActive = false

    public init(
        state: AppState = DummyData.initialState(),
        service: any DeviceService = DummyDeviceService(),
        scanDelay: Duration = .milliseconds(600),
        refreshInterval: Duration = .milliseconds(500)
    ) {
        self.state = state
        self.service = service
        self.scanDelay = scanDelay
        self.refreshInterval = refreshInterval
        observeDeviceChanges()
        startRefreshLoop()
    }

    /// A physical control (mode-shift button, battery event) can change device
    /// state without our involvement. Adopt it immediately instead of waiting
    /// for the next poll.
    private func observeDeviceChanges() {
        NotificationCenter.default.addObserver(
            forName: .deviceStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let snapshot = await self.service.refresh() else { return }
                self.adoptIfChanged(snapshot)
            }
        }
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
            state.general = DummyData.generalSettings
            state.warning = nil
            Task { @MainActor in
                guard let snapshot = await service.clearSettings() else { return }
                adopt(snapshot)
            }
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
    ///
    /// Slider drags fire dozens of changes; commit the latest one after a short
    /// debounce and ignore snapshots from older requests, otherwise a slow
    /// response overwrites the value the user is still dragging.
    private func pushChange(_ itemID: String) {
        guard case .device = state.route else { return }

        changeGeneration &+= 1
        let generation = changeGeneration
        lastChangeAt = Date()

        pendingChange?.cancel()
        pendingChange = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, generation == changeGeneration,
                  case let .device(deviceID) = state.route,
                  let value = state.settingValue(itemID) else { return }

            let change = DeviceChange(deviceID: deviceID, itemID: itemID, value: value)
            guard let snapshot = await service.apply(change),
                  generation == changeGeneration else { return }
            adopt(snapshot)
        }
    }

    private func adopt(_ snapshot: DeviceSnapshot) {
        state.devices = snapshot.devices
        state.details = snapshot.details
        if let warning = snapshot.warning {
            state.warning = warning
        }
        // The device we were looking at may have disconnected.
        if case let .device(id) = state.route, snapshot.details[id] == nil {
            state.route = .root
        }
    }

    /// Polling only matters while the popover is visible; paused polling keeps
    /// the device quiet when the app sits in the menu bar.
    public func setUIActive(_ active: Bool) {
        isUIActive = active
        guard active else { return }

        Task { @MainActor in
            guard let snapshot = await service.refresh() else { return }
            adoptIfChanged(snapshot)
        }
    }

    /// Battery and connection state drift while the popover is closed, and
    /// devices finish initializing after the first snapshot.
    private func startRefreshLoop() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                guard isUIActive else { continue }
                // A drag is still settling; a poll would fight the local value.
                guard Date().timeIntervalSince(lastChangeAt) > 0.6,
                      let snapshot = await service.refresh() else { continue }
                adoptIfChanged(snapshot)
            }
        }
    }

    private func adoptIfChanged(_ snapshot: DeviceSnapshot) {
        let current = DeviceSnapshot(
            devices: state.devices,
            details: state.details,
            warning: state.warning
        )
        guard snapshot != current else { return }
        adopt(snapshot)
    }
}

public extension AppModel {
    static let shared = AppModel(
        state: AppState(general: DummyData.generalSettings, version: DummyData.version),
        service: HIDPPDeviceService()
    )
}
