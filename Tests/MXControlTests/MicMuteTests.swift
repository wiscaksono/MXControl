import Testing
import CoreAudio
import Foundation
@testable import MXControl
@testable import MXControlHIDPP

/// In-memory MicMuteBackend for testing engine logic without touching hardware.
final class MockMicMuteBackend: MicMuteBackend, @unchecked Sendable {
    struct DeviceCaps {
        var hasMute: Bool
        var volume: Float32?  // nil = no volume control
    }

    var devices: [AudioDeviceID: DeviceCaps] = [:]
    var mutedState: [AudioDeviceID: Bool] = [:]
    var setMuteCalls: [(device: AudioDeviceID, muted: Bool)] = []
    var setVolumeCalls: [(device: AudioDeviceID, volume: Float32)] = []

    func inputDeviceIDs() -> [AudioDeviceID] { Array(devices.keys) }

    func hasMuteControl(_ device: AudioDeviceID) -> Bool {
        devices[device]?.hasMute ?? false
    }

    func getMute(_ device: AudioDeviceID) -> Bool? {
        guard devices[device]?.hasMute == true else { return nil }
        // Match hardware: an unmuted device reads false, never nil.
        return mutedState[device] ?? false
    }

    func setMute(_ device: AudioDeviceID, muted: Bool) -> Bool {
        setMuteCalls.append((device, muted))
        guard devices[device]?.hasMute == true else { return false }
        mutedState[device] = muted
        return true
    }

    func getVolume(_ device: AudioDeviceID) -> Float32? {
        devices[device]?.volume
    }

    func setVolume(_ device: AudioDeviceID, volume: Float32) -> Bool {
        setVolumeCalls.append((device, volume))
        guard devices[device]?.volume != nil else { return false }
        devices[device]?.volume = volume
        return true
    }
}

@Suite("MicMuteEngine")
struct MicMuteEngineTests {

    private func makeEngine(
        devices: [AudioDeviceID: MockMicMuteBackend.DeviceCaps],
        debounce: TimeInterval = 0
    ) -> (MicMuteEngine, MockMicMuteBackend) {
        let backend = MockMicMuteBackend()
        backend.devices = devices
        let engine = MicMuteEngine(backend: backend)
        engine.debounceInterval = debounce
        return (engine, backend)
    }

    @Test func toggleMutesHardwareMuteDevice() {
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: 0.8)])

        let muted = engine.toggleFromKeypress()

        #expect(muted == true)
        #expect(engine.isMuted == true)
        #expect(backend.setMuteCalls.count == 1)
        #expect(backend.setMuteCalls[0] == (7, true))
        #expect(backend.mutedState[7] == true)
    }

    @Test func toggleTwiceUnmutes() {
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: 0.8)])

        engine.toggleFromKeypress()
        let muted = engine.toggleFromKeypress()

        #expect(muted == false)
        #expect(backend.setMuteCalls.count == 2)
        #expect(backend.setMuteCalls[1] == (7, false))
    }

    @Test func debounceSwallowsRapidSecondToggle() {
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: nil)], debounce: 60)

        let first = engine.toggleFromKeypress()
        let second = engine.toggleFromKeypress()

        #expect(first == true)
        #expect(second == true)  // still muted, second press swallowed
        #expect(backend.setMuteCalls.count == 1)
    }

    @Test func setMutedIsIdempotent() {
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: nil)])

        engine.setMuted(true)
        engine.setMuted(true)

        #expect(backend.setMuteCalls.count == 1)
    }

    @Test func volumeFallbackSavesAndRestores() {
        let (engine, backend) = makeEngine(devices: [9: .init(hasMute: false, volume: 0.7)])

        engine.toggleFromKeypress()  // mute
        #expect(backend.setVolumeCalls.last?.volume == 0.0)

        engine.toggleFromKeypress()  // unmute
        #expect(backend.setVolumeCalls.last?.volume == 0.7)
    }

    @Test func deviceWithoutControlsIsSkipped() {
        let (engine, backend) = makeEngine(devices: [11: .init(hasMute: false, volume: nil)])

        engine.toggleFromKeypress()

        #expect(engine.isMuted == true)
        #expect(backend.setMuteCalls.isEmpty)
        #expect(backend.setVolumeCalls.isEmpty)
    }

    @Test func mutesAllInputDevices() {
        typealias Caps = MockMicMuteBackend.DeviceCaps
        let (engine, backend) = makeEngine(devices: [
            AudioDeviceID(1): Caps(hasMute: true, volume: 0.5),
            AudioDeviceID(2): Caps(hasMute: true, volume: 0.5),
            AudioDeviceID(3): Caps(hasMute: false, volume: 0.6),
        ])

        engine.setMuted(true)

        #expect(backend.mutedState[1] == true)
        #expect(backend.mutedState[2] == true)
        #expect(backend.setVolumeCalls.contains { $0.device == 3 && $0.volume == 0.0 })
    }

    @Test func unmuteRestoresManuallyMutedDevice() {
        // User muted device 7 via Control Center before F9. Our mute→unmute
        // cycle must leave it muted instead of unmuting it.
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: 0.8)])
        backend.mutedState[7] = true

        engine.toggleFromKeypress()  // mute (already muted, stays muted)
        engine.toggleFromKeypress()  // unmute → restores prior muted=true

        #expect(backend.mutedState[7] == true)
    }

    @Test func syncFromHardwareAdoptsExternalMute() {
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: 0.8)])
        backend.mutedState[7] = true

        engine.syncFromHardware()

        #expect(engine.isMuted == true)
    }

    @Test func syncFromHardwareClearsWhenAllUnmuted() {
        let (engine, backend) = makeEngine(devices: [7: .init(hasMute: true, volume: 0.8)])
        backend.mutedState[7] = false

        engine.syncFromHardware()

        #expect(engine.isMuted == false)
    }
}

@Suite("Descriptor Mic Mute")
struct DescriptorMicMuteTests {

    private var spec: MicMuteSpec {
        DeviceDescriptors.mxKeysMini.micMute!
    }

    private func f9Control(
        controlId: UInt16 = 0x011C,
        position: UInt8 = 9,
        flags: SpecialKeysFeature.ControlFlags = [.fnKey, .hotKey, .fnToggle, .reprogrammable, .divertable, .analyticsKey]
    ) -> SpecialKeysFeature.ControlInfo {
        SpecialKeysFeature.ControlInfo(
            controlId: controlId, taskId: 0x00F1,
            flags: flags, position: position, group: 0, groupMask: 0
        )
    }

    /// Minimal HIDTransport stub. The tests below never perform I/O —
    /// they only drive `handleNotification` and CID matching.
    final class StubHIDTransport: HIDTransport, @unchecked Sendable {
        func send(
            deviceIndex: UInt8,
            featureIndex: UInt8,
            functionId: UInt8,
            softwareId: UInt8,
            params: [UInt8]
        ) async throws -> HIDPPResponse {
            HIDPPResponse(
                reportId: .long,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionId: functionId,
                softwareId: softwareId,
                params: [UInt8](repeating: 0, count: 16)
            )
        }

        func open() async throws {}
        func close() {}
    }

    @MainActor
    private func makeBehavior() -> (LogiDevice, MicMuteBehavior) {
        let device = LogiDevice(
            deviceIndex: 0x01,
            transport: StubHIDTransport(),
            descriptor: DeviceDescriptors.mxKeysMini
        )
        let behavior = MicMuteBehavior(device: device)
        behavior.micCID = 0x00C9
        device.specialKeysFeatureIndex = 0x05
        return (device, behavior)
    }

    @Test @MainActor func micMuteCIDUnknownByDefault() {
        // Empty table → no match.
        #expect(MicMuteBehavior.matchCID(in: [], spec: spec) == nil)
    }

    @Test @MainActor func micMuteCIDMatchesF9DivertableControl() {
        let controls = [
            SpecialKeysFeature.ControlInfo(
                controlId: 0x00D1, taskId: 0x00AE,
                flags: [.fnKey, .fnToggle, .analyticsKey],
                position: 1, group: 0, groupMask: 0
            ),
            f9Control(),
        ]
        #expect(MicMuteBehavior.matchCID(in: controls, spec: spec) == 0x011C)
    }

    @Test @MainActor func micMuteCIDRejectsNonDivertable() {
        let controls = [f9Control(flags: [.fnKey, .analyticsKey])]
        #expect(MicMuteBehavior.matchCID(in: controls, spec: spec) == nil)
    }

    @Test @MainActor func micMuteCIDRejectsWrongPosition() {
        // Same CID but unexpected position (firmware remap) → reject.
        let controls = [f9Control(position: 5)]
        #expect(MicMuteBehavior.matchCID(in: controls, spec: spec) == nil)
    }

    @Test @MainActor func micMuteCIDRejectsMissingFnFlag() {
        // Divertable CID at the right position but without the FN flag → reject.
        let controls = [f9Control(flags: [.hotKey, .reprogrammable, .divertable, .analyticsKey])]
        #expect(MicMuteBehavior.matchCID(in: controls, spec: spec) == nil)
    }

    @Test @MainActor func divertedMicPressFiresOncePerPress() {
        let (device, behavior) = makeBehavior()
        defer { _ = device } // keep device alive: behavior holds it unowned


        var fires = 0
        behavior.onMicMuteKeypress = { fires += 1 }

        // Press (edge) → fires
        behavior.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])
        // Held (repeat, same state) → no additional fire
        behavior.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])
        // Release
        behavior.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0, 0, 0, 0])
        // Press again → fires
        behavior.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])

        #expect(fires == 2)
    }

    @Test @MainActor func otherCIDsAndFeaturesIgnored() {
        let (device, behavior) = makeBehavior()
        defer { _ = device } // keep device alive: behavior holds it unowned


        var fires = 0
        behavior.onMicMuteKeypress = { fires += 1 }

        // Different CID pressed
        behavior.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0x50, 0, 0])
        // Different feature index
        behavior.handleNotification(featureIndex: 0x06, functionId: 0x00, params: [0x00, 0xC9, 0, 0])
        // Different event (rawXY, not button event)
        behavior.handleNotification(featureIndex: 0x05, functionId: 0x01, params: [0x00, 0xC9, 0, 0])

        #expect(fires == 0)
    }

    @Test @MainActor func noCIDConfiguredIgnoresEverything() {
        let (device, behavior) = makeBehavior()
        defer { _ = device } // keep device alive: behavior holds it unowned

        behavior.micCID = nil

        var fires = 0
        behavior.onMicMuteKeypress = { fires += 1 }

        behavior.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])

        #expect(fires == 0)
    }
}

@Suite("DeviceDescriptors")
struct DeviceDescriptorTests {

    @Test func matchByPID() {
        let found = DeviceDescriptors.match(pid: 0xB034, name: "MX Master 3S", kind: .mouse)
        #expect(found.id == "mx-master-3s")
    }

    @Test func matchByName() {
        // Receiver path: no device PID visible, match on HID++ name.
        let found = DeviceDescriptors.match(pid: nil, name: "MX Keys Mini", kind: .keyboard)
        #expect(found.id == "mx-keys-mini")
    }

    @Test func unknownFallsBackToGeneric() {
        let found = DeviceDescriptors.match(pid: 0x1234, name: "Mystery Mouse", kind: .mouse)
        #expect(found.id == "generic")
        #expect(found.type == .mouse)
        #expect(found.capabilities.map(\.id).contains(CapabilityID.battery))
    }

    @Test func master3SDeclaresBehaviors() {
        let descriptor = DeviceDescriptors.mxMaster3S
        #expect(descriptor.scroll != nil)
        #expect(descriptor.thumbGesture?.thumbCID == 0x00C3)
        #expect(descriptor.micMute == nil)
    }

    @Test func keysMiniDeclaresMicMute() {
        let descriptor = DeviceDescriptors.mxKeysMini
        #expect(descriptor.micMute?.cid == 0x011C)
        #expect(descriptor.scroll == nil)
        #expect(descriptor.thumbGesture == nil)
    }
}
