import AppCore
import AppRuntime
import Testing

@MainActor
struct AppModelTests {
    private struct StubService: DeviceService {
        let snapshot: DeviceSnapshot

        nonisolated func scan() async -> DeviceSnapshot {
            snapshot
        }
    }

    private func makeModel(state: AppState) -> AppModel {
        let snapshot = DeviceSnapshot(devices: DummyData.devices, details: DummyData.details)
        return AppModel(state: state, service: StubService(snapshot: snapshot), scanDelay: .zero)
    }

    @Test func scanRestoresDevicesFromEmptyState() async throws {
        let model = makeModel(state: DummyData.emptyState())
        #expect(model.state.devices.isEmpty)

        model.handle(.refresh)
        #expect(model.state.isScanning)

        try await Task.sleep(for: .milliseconds(50))
        #expect(!model.state.isScanning)
        #expect(model.state.devices.count == 3)
        #expect(model.state.details.count == 2)
    }

    @Test func scanIsIgnoredWhileAlreadyScanning() async throws {
        let model = makeModel(state: DummyData.emptyState())
        model.handle(.refresh)
        model.handle(.refresh)

        try await Task.sleep(for: .milliseconds(50))
        #expect(!model.state.isScanning)
        #expect(model.state.devices.count == 3)
    }

    @Test func resetAllKeepsCurrentRoute() {
        let model = makeModel(state: DummyData.initialState(route: .general))
        model.handle(.resetAll)
        #expect(model.state.route == .general)
        #expect(model.state.devices.count == 3)
    }
}
