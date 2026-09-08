import CoreAudio
import Foundation
import os

// MARK: - Mic Mute Notification

extension Notification.Name {
    /// Posted when mic-mute configuration changes (toggle on/off, device divert state).
    /// DeviceManager observes this to refresh F9KeyMonitor routing.
    static let micMuteConfigChanged = Notification.Name("com.mxcontrol.micMuteConfigChanged")
}

// MARK: - Backend Protocol

/// Hardware backend for muting microphone input devices.
///
/// Split out from `MicMuteEngine` so unit tests can inject a mock.
/// All methods are synchronous CoreAudio property access (fast, no I/O streaming).
protocol MicMuteBackend: Sendable {
    /// Audio device IDs with input streams (microphones).
    func inputDeviceIDs() -> [AudioDeviceID]
    /// Whether the device exposes a hardware mute control on the input scope.
    func hasMuteControl(_ device: AudioDeviceID) -> Bool
    /// Current hardware mute state, if readable.
    func getMute(_ device: AudioDeviceID) -> Bool?
    /// Set the hardware mute control. Returns false on failure.
    func setMute(_ device: AudioDeviceID, muted: Bool) -> Bool
    /// Current input volume scalar (0.0-1.0), if the device exposes one.
    func getVolume(_ device: AudioDeviceID) -> Float32?
    /// Set input volume scalar. Returns false on failure.
    func setVolume(_ device: AudioDeviceID, volume: Float32) -> Bool
}

// MARK: - CoreAudio Backend

/// Real backend using CoreAudio HAL property access.
///
/// Mutes via `kAudioDevicePropertyMute` (input scope) when available,
/// otherwise falls back to driving input volume to 0. Devices exposing
/// neither control (e.g. iPhone Continuity Microphone) are skipped.
struct CoreAudioMicMuteBackend: MicMuteBackend {

    /// Audio device IDs that expose input streams. Output-only devices are excluded.
    ///
    /// Note: HAL mute/volume property access does not capture audio and does not
    /// require microphone TCC consent. `NSMicrophoneUsageDescription` alone does
    /// not trigger a prompt; only capture APIs (AVCapture/AVAudio) do.
    func inputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        )
        guard sizeStatus == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        var fetchSize = dataSize
        let fetchStatus: OSStatus = ids.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return OSStatus(paramErr) }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &fetchSize,
                baseAddress
            )
        }
        guard fetchStatus == noErr else { return [] }
        return ids.filter(hasInputStreams)
    }

    /// Whether the device exposes at least one input stream.
    private func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr else {
            return false
        }
        return dataSize > 0
    }

    func hasMuteControl(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(device, &address)
    }

    func getMute(_ device: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            device, &address, 0, nil, &dataSize, &value
        )
        guard status == noErr else { return nil }
        return value != 0
    }

    func setMute(_ device: AudioDeviceID, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = muted ? 1 : 0
        let status = withUnsafePointer(to: &value) { ptr in
            AudioObjectSetPropertyData(
                device, &address, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), ptr
            )
        }
        if status != noErr {
            debugLog("[MicMute] setMute failed device=\(device) status=\(status)")
        }
        return status == noErr
    }

    func getVolume(_ device: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            device, &address, 0, nil, &dataSize, &value
        )
        guard status == noErr else { return nil }
        return value
    }

    func setVolume(_ device: AudioDeviceID, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = volume
        let status = withUnsafePointer(to: &value) { ptr in
            AudioObjectSetPropertyData(
                device, &address, 0, nil,
                UInt32(MemoryLayout<Float32>.size), ptr
            )
        }
        if status != noErr {
            debugLog("[MicMute] setVolume failed device=\(device) status=\(status)")
        }
        return status == noErr
    }
}

// MARK: - Engine

/// System-wide microphone mute engine.
///
/// Mutes ALL input devices (like Logi Options+) so Zoom/Meet/Teams all go
/// silent regardless of which mic the app uses. Best-effort: devices without
/// mute/volume controls are skipped (same limitation as other mute utilities).
///
/// Both trigger paths (HID++ divert via `KeyboardDevice` and the `F9KeyMonitor`
/// event-tap fallback) funnel through `toggleFromKeypress()`, which debounces
/// so a single physical press never double-toggles when both paths fire.
final class MicMuteEngine: @unchecked Sendable {

    static let shared = MicMuteEngine()

    private let backend: MicMuteBackend
    private let lock = NSLock()

    private var _isMuted = false
    private var _lastToggle = Date.distantPast
    /// Pre-mute input volumes for devices without a mute control, for restore on unmute.
    private var savedVolumes: [AudioDeviceID: Float32] = [:]
    /// Devices that were muted via hardware mute (for diagnostics).
    private var mutedViaHardware: Set<AudioDeviceID> = []
    /// Hardware mute states observed before our first mute, so unmute restores
    /// a device that the user had already muted manually instead of unmuting it.
    private var priorHardwareMute: [AudioDeviceID: Bool] = [:]

    /// Minimum interval between toggles. Guards against HID++ + event-tap double-fire.
    var debounceInterval: TimeInterval = 0.3

    private var isMonitoringDevices = false

    init(backend: MicMuteBackend = CoreAudioMicMuteBackend()) {
        self.backend = backend
    }

    var isMuted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isMuted
    }

    /// Toggle mute from an F9 keypress. Debounced: presses within
    /// `debounceInterval` return the current state without re-toggling.
    @discardableResult
    func toggleFromKeypress() -> Bool {
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(_lastToggle) < debounceInterval {
            let current = _isMuted
            lock.unlock()
            debugLog("[MicMute] Debounced rapid toggle")
            return current
        }
        _lastToggle = now
        _isMuted.toggle()
        let muted = _isMuted
        lock.unlock()

        applyMuted(muted)
        logger.info("[MicMute] \(muted ? "MUTED" : "UNMUTED", privacy: .public) via F9")
        return muted
    }

    /// Adopt the actual hardware state so F9 toggles relative to reality even
    /// when the user muted via Control Center, Teams, or another utility.
    /// Called at launch and whenever the device list changes while unmuted.
    func syncFromHardware() {
        var anyMuted = false
        for device in backend.inputDeviceIDs() {
            if let muted = backend.getMute(device) {
                if muted { anyMuted = true }
                continue
            }
            if let volume = backend.getVolume(device), volume == 0.0 {
                anyMuted = true
            }
        }
        lock.lock()
        _isMuted = anyMuted
        lock.unlock()
        debugLog("[MicMute] Synced from hardware: muted=\(anyMuted)")
    }

    /// Set an explicit mute state. No-op if already in that state.
    func setMuted(_ muted: Bool) {
        lock.lock()
        guard muted != _isMuted else {
            lock.unlock()
            return
        }
        _isMuted = muted
        _lastToggle = Date()
        lock.unlock()

        applyMuted(muted)
        logger.info("[MicMute] \(muted ? "MUTED" : "UNMUTED", privacy: .public)")
    }

    // MARK: - Device Monitoring

    /// Watch for audio device list changes so newly-connected mics are muted
    /// while the engine is in muted state. Idempotent, call once at launch.
    func startDeviceMonitoring() {
        lock.lock()
        guard !isMonitoringDevices else {
            lock.unlock()
            return
        }
        isMonitoringDevices = true
        lock.unlock()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            deviceListChanged,
            context
        )
        if status != noErr {
            logger.warning("[MicMute] Device listener install failed: \(status)")
        } else {
            syncFromHardware()
        }
    }

    /// Remove the device-list listener. Call on app termination.
    func stopDeviceMonitoring() {
        lock.lock()
        guard isMonitoringDevices else {
            lock.unlock()
            return
        }
        isMonitoringDevices = false
        lock.unlock()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            deviceListChanged,
            context
        )
        if status != noErr {
            debugLog("[MicMute] Device listener removal failed: \(status)")
        }
    }

    fileprivate func handleDeviceListChanged() {
        if isMuted {
            debugLog("[MicMute] Device list changed while muted — re-applying")
            applyMuted(true)
        } else {
            syncFromHardware()
            pruneStaleState()
        }
    }

    // MARK: - Apply

    private func applyMuted(_ muted: Bool) {
        var hardwareCount = 0
        var volumeCount = 0
        var skippedCount = 0

        let currentDevices = Set(backend.inputDeviceIDs())
        for device in currentDevices {
            if backend.hasMuteControl(device) {
                if muted {
                    // Remember pre-existing state so unmute restores devices the
                    // user had already muted instead of unmuting them.
                    if backend.getMute(device) == true {
                        lock.lock()
                        if priorHardwareMute[device] == nil {
                            priorHardwareMute[device] = true
                        }
                        lock.unlock()
                    }
                    if backend.setMute(device, muted: true) {
                        hardwareCount += 1
                        lock.lock()
                        mutedViaHardware.insert(device)
                        savedVolumes.removeValue(forKey: device)
                        lock.unlock()
                        continue
                    }
                } else {
                    // Restore prior state: leave already-muted devices muted.
                    lock.lock()
                    let wasAlreadyMuted = priorHardwareMute.removeValue(forKey: device) ?? false
                    lock.unlock()
                    if backend.setMute(device, muted: wasAlreadyMuted) {
                        hardwareCount += 1
                        lock.lock()
                        mutedViaHardware.remove(device)
                        savedVolumes.removeValue(forKey: device)
                        lock.unlock()
                        continue
                    }
                }
                // setMute failed — fall through to volume fallback
            }

            if muted {
                if let current = backend.getVolume(device) {
                    lock.lock()
                    if savedVolumes[device] == nil {
                        savedVolumes[device] = current
                    }
                    lock.unlock()
                    if backend.setVolume(device, volume: 0.0) {
                        volumeCount += 1
                    } else {
                        skippedCount += 1
                    }
                } else {
                    skippedCount += 1
                }
            } else {
                lock.lock()
                let saved = savedVolumes.removeValue(forKey: device)
                lock.unlock()
                if let saved {
                    if backend.setVolume(device, volume: saved) {
                        volumeCount += 1
                    } else {
                        skippedCount += 1
                    }
                }
                // No saved volume: leave the device as-is (don't blast to full volume).
            }
        }

        pruneStaleState(keeping: currentDevices)

        debugLog("[MicMute] applyMuted(\(muted)): hardware=\(hardwareCount) volume=\(volumeCount) skipped=\(skippedCount)")
    }

    /// Drop cached state for devices that no longer exist.
    private func pruneStaleState(keeping current: Set<AudioDeviceID>? = nil) {
        let live = current ?? Set(backend.inputDeviceIDs())
        lock.lock()
        savedVolumes = savedVolumes.filter { live.contains($0.key) }
        mutedViaHardware = mutedViaHardware.intersection(live)
        priorHardwareMute = priorHardwareMute.filter { live.contains($0.key) }
        lock.unlock()
    }
}

// MARK: - Device List Listener (C callback)

/// C callback for audio device list changes. Recovers the engine from context.
private func deviceListChanged(
    _ objectID: AudioObjectID,
    _ numAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let engine = Unmanaged<MicMuteEngine>.fromOpaque(clientData).takeUnretainedValue()
    engine.handleDeviceListChanged()
    return noErr
}
