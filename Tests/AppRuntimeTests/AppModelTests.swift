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

    private actor RecordingService: DeviceService { nonisolated let snapshot: DeviceSnapshot
        private var changes: [DeviceChange] = []

        init(snapshot: DeviceSnapshot) {
            self.snapshot = snapshot
        }

        nonisolated func scan() async -> DeviceSnapshot {
            snapshot
        }

        func apply(_ change: DeviceChange) async -> DeviceSnapshot? {
            changes.append(change)
            return nil
        }

        func recorded() -> [DeviceChange] {
            changes
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

    @Test func toggleForwardsChangeToService() async throws {
        let snapshot = DeviceSnapshot(devices: DummyData.devices, details: DummyData.details)
        let service = RecordingService(snapshot: snapshot)
        let model = AppModel(
            state: DummyData.initialState(route: .device(DummyData.mouseID)),
            service: service,
            scanDelay: .zero
        )

        model.handle(.toggle(itemID: "wheel.smartshift"))
        #expect(model.state.settingValue("wheel.smartshift") == .bool(false))

        try await Task.sleep(for: .milliseconds(50))
        let changes = await service.recorded()
        #expect(changes.count == 1)
        #expect(changes.first?.deviceID == DummyData.mouseID)
        #expect(changes.first?.itemID == "wheel.smartshift")
        #expect(changes.first?.value == .bool(false))
    }
}

struct AppModelDisconnectionTests {
    private struct EmptyingService: DeviceService {
        nonisolated func scan() async -> DeviceSnapshot {
            DeviceSnapshot()
        }

        func apply(_ change: DeviceChange) async -> DeviceSnapshot? {
            DeviceSnapshot()
        }
    }

    @Test func disconnectFallsBackToRoot() async throws {
        let model = await AppModel(
            state: DummyData.initialState(route: .device(DummyData.mouseID)),
            service: EmptyingService(),
            scanDelay: .zero
        )

        await MainActor.run {
            model.handle(.toggle(itemID: "wheel.smartshift"))
        }
        try await Task.sleep(for: .milliseconds(50))
        let route = await model.state.route
        #expect(route == .root)
    }

    @Test func resetKeepsLiveDevices() async {
        let model = await AppModel(
            state: DummyData.initialState(route: .general),
            service: EmptyingService(),
            scanDelay: .zero
        )
        let ids = await model.state.devices.map(\.id)

        await MainActor.run {
            model.handle(.resetAll)
        }
        let after = await model.state.devices.map(\.id)
        #expect(after == ids)
    }
}
