import AppCore
import Foundation
import Observation

@Observable
final class AppModel {
    private(set) var state: AppState
    private var scanTask: Task<Void, Never>?

    init(state: AppState = DummyData.initialState()) {
        self.state = state
    }

    func handle(_ action: UIAction) {
        switch action {
        case let .openDevice(id):
            state.route = .device(id)
        case .openGeneral:
            state.route = .general
        case .back:
            state.route = .root
        case let .toggle(itemID):
            state.toggleItem(itemID)
        case let .setSlider(itemID, value):
            state.setSlider(itemID, to: value)
        case let .selectOption(itemID, index):
            state.selectOption(itemID, index: index)
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
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            state.finishScan(devices: DummyData.devices, details: DummyData.details)
        }
    }
}

extension AppModel {
    static let shared = AppModel()
}
