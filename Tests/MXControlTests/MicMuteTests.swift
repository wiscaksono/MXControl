import Testing
import CoreAudio
import Foundation
@testable import MXControl

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
        return mutedState[device]
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

@Suite("KeyboardDevice Mic Mute")
struct KeyboardMicMuteTests {

    @MainActor
    private func makeKeyboard() -> KeyboardDevice {
        KeyboardDevice(deviceIndex: 0x01, transport: MockHIDTransport())
    }

    @Test @MainActor func micMuteCIDUnknownByDefault() {
        // Empty table → no match.
        #expect(KeyboardDevice.micMuteCID(in: []) == nil)
    }

    @Test @MainActor func micMuteCIDMatchesF9DivertableControl() {
        let controls = [
            SpecialKeysFeature.ControlInfo(
                controlId: 0x00D1, taskId: 0x00AE,
                flags: [.fnKey, .fnToggle, .analyticsKey],
                position: 1, group: 0, groupMask: 0
            ),
            SpecialKeysFeature.ControlInfo(
                controlId: 0x011C, taskId: 0x00F1,
                flags: [.fnKey, .hotKey, .fnToggle, .reprogrammable, .divertable, .analyticsKey],
                position: 9, group: 0, groupMask: 0
            ),
        ]
        #expect(KeyboardDevice.micMuteCID(in: controls) == 0x011C)
    }

    @Test @MainActor func micMuteCIDRejectsNonDivertable() {
        let controls = [
            SpecialKeysFeature.ControlInfo(
                controlId: 0x011C, taskId: 0x00F1,
                flags: [.fnKey, .analyticsKey],  // not divertable
                position: 9, group: 0, groupMask: 0
            ),
        ]
        #expect(KeyboardDevice.micMuteCID(in: controls) == nil)
    }

    @Test @MainActor func micMuteCIDRejectsWrongPosition() {
        // Same CID but unexpected position (firmware remap) → reject.
        let controls = [
            SpecialKeysFeature.ControlInfo(
                controlId: 0x011C, taskId: 0x00F1,
                flags: [.fnKey, .hotKey, .fnToggle, .reprogrammable, .divertable, .analyticsKey],
                position: 5, group: 0, groupMask: 0
            ),
        ]
        #expect(KeyboardDevice.micMuteCID(in: controls) == nil)
    }

    @Test @MainActor func micMuteCIDRejectsMissingFnFlag() {
        // Divertable CID at the right position but without the FN flag → reject.
        let controls = [
            SpecialKeysFeature.ControlInfo(
                controlId: 0x011C, taskId: 0x00F1,
                flags: [.hotKey, .reprogrammable, .divertable, .analyticsKey],
                position: 9, group: 0, groupMask: 0
            ),
        ]
        #expect(KeyboardDevice.micMuteCID(in: controls) == nil)
    }

    @Test @MainActor func divertedMicPressFiresOncePerPress() {
        let keyboard = makeKeyboard()
        keyboard.micMuteCID = 0x00C9
        keyboard.specialKeysFeatureIndex = 0x05

        var fires = 0
        keyboard.onMicMuteKeypress = { fires += 1 }

        // Press (edge) → fires
        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])
        // Held (repeat, same state) → no additional fire
        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])
        // Release
        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0, 0, 0, 0])
        // Press again → fires
        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])

        #expect(fires == 2)
    }

    @Test @MainActor func otherCIDsAndFeaturesIgnored() {
        let keyboard = makeKeyboard()
        keyboard.micMuteCID = 0x00C9
        keyboard.specialKeysFeatureIndex = 0x05

        var fires = 0
        keyboard.onMicMuteKeypress = { fires += 1 }

        // Different CID pressed
        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0x50, 0, 0])
        // Different feature index
        keyboard.handleNotification(featureIndex: 0x06, functionId: 0x00, params: [0x00, 0xC9, 0, 0])
        // Different event (rawXY, not button event)
        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x01, params: [0x00, 0xC9, 0, 0])

        #expect(fires == 0)
    }

    @Test @MainActor func noCIDConfiguredIgnoresEverything() {
        let keyboard = makeKeyboard()
        keyboard.micMuteCID = nil
        keyboard.specialKeysFeatureIndex = 0x05

        var fires = 0
        keyboard.onMicMuteKeypress = { fires += 1 }

        keyboard.handleNotification(featureIndex: 0x05, functionId: 0x00, params: [0x00, 0xC9, 0, 0])

        #expect(fires == 0)
    }
}
