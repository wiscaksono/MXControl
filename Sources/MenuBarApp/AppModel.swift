import AppCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState

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
        case let .activate(itemID):
            activate(itemID)
        case .refresh:
            refresh()
        case .quit:
            break // handled in the app layer, which owns NSApp
        }
    }

    private func activate(_ itemID: String) {
        // Dummy: the only action row throws away all edits.
        if itemID == "general.reset" {
            state = DummyData.initialState(route: .general)
        }
    }

    private func refresh() {
        // Dummy data: pretend a rescan succeeded.
        state.warning = nil
    }
}

@MainActor
extension AppModel {
    static let shared = AppModel()
}
