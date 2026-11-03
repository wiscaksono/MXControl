import HIDPP
import CoreAudio
import Foundation
import os

// MARK: - Mic Mute Notification

extension Notification.Name {
    /// Posted when mic-mute configuration changes (toggle on/off, device divert state).
    /// DeviceManager observes this to refresh F9KeyMonitor routing.
    static let micMuteConfigChanged = Notification.Name("com.mxcontrol.micMuteConfigChanged")

    /// Posted when the effective mute state changes, including changes made
    /// outside the app (Control Center, the system volume slider, or another
    /// audio app). The overlay listens so it never lies about the mic state.
    static let micMuteStateChanged = Notification.Name("com.mxcontrol.micMuteStateChanged")
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

    /// Main-thread state for the default input device listeners. CoreAudio
    /// callbacks hop to main before touching these.
    private var listenedInputDevice: AudioDeviceID?
    private var hasInputMuteListener = false
    private var hasInputVolumeListener = false
    private var hasDefaultInputListener = false

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
        let changed = _isMuted != anyMuted
        _isMuted = anyMuted
        lock.unlock()
        if changed {
            NotificationCenter.default.post(name: .micMuteStateChanged, object: nil)
        }
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

    /// Best-effort cleanup on quit: never leave the system muted behind.
    /// Restores pre-mute hardware state, then stops watching devices.
    func restoreForTermination() {
        stopDeviceMonitoring()
        if isMuted {
            setMuted(false)
        }
        pruneStaleState()
    }

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
        }
        installDefaultInputListener()
        installInputDeviceListeners()
        syncFromHardware()
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
        removeInputDeviceListeners()
        removeDefaultInputListener()
    }

    fileprivate func handleDeviceListChanged() {
        // The default input device may have changed; listener state is main.
        DispatchQueue.main.async { [weak self] in
            self?.installInputDeviceListeners()
        }
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
                    if backend.setMute(device, muted: true) {
                        hardwareCount += 1
                        lock.lock()
                        mutedViaHardware.insert(device)
                        savedVolumes.removeValue(forKey: device)
                        lock.unlock()
                        continue
                    }
                } else {
                    // The built-in mic only really releases its mute after the
                    // input volume is touched. Writing it here is the same
                    // nudge a user would do by hand in System Settings.
                    if let current = backend.getVolume(device) {
                        let nudge = current > 0 ? current : 1.0
                        if backend.setVolume(device, volume: nudge) {
                            volumeCount += 1
                        }
                    }
                    // An explicit unmute wins over any state observed earlier.
                    if backend.setMute(device, muted: false) {
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
                if let saved, saved > 0 {
                    if backend.setVolume(device, volume: saved) {
                        volumeCount += 1
                    } else {
                        skippedCount += 1
                    }
                } else if let current = backend.getVolume(device), current == 0 {
                    // The app was killed while muted, or the device list
                    // changed and the saved level was pruned. Leaving this at
                    // zero makes the UI lie about being unmuted.
                    if backend.setVolume(device, volume: 1.0) {
                        volumeCount += 1
                    } else {
                        skippedCount += 1
                    }
                }
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
        lock.unlock()
    }

    // MARK: - External Input State

    /// Main-thread only. Watches the default input device so the app notices
    /// mute/volume changes made outside the app (Control Center, System
    /// Settings, Teams muting the device).
    private func installDefaultInputListener() {
        guard !hasDefaultInputListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultInputDeviceChanged,
            context
        )
        hasDefaultInputListener = status == noErr
        if status != noErr {
            debugLog("[MicMute] Default input listener install failed: \(status)")
        }
    }

    /// Main-thread only.
    private func removeDefaultInputListener() {
        guard hasDefaultInputListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultInputDeviceChanged,
            context
        )
        if status != noErr {
            debugLog("[MicMute] Default input listener removal failed: \(status)")
        }
        hasDefaultInputListener = false
    }

    /// Main-thread only. Re-point the mute/volume listeners at the current
    /// default input device.
    private func installInputDeviceListeners() {
        lock.lock()
        let monitoring = isMonitoringDevices
        lock.unlock()
        guard monitoring else { return }

        removeInputDeviceListeners()
        guard let device = defaultInputDevice() else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &muteAddress) {
            let status = AudioObjectAddPropertyListener(
                device,
                &muteAddress,
                inputDevicePropertyChanged,
                context
            )
            hasInputMuteListener = status == noErr
            if status != noErr {
                debugLog("[MicMute] Input mute listener install failed: \(status)")
            }
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &volumeAddress) {
            let status = AudioObjectAddPropertyListener(
                device,
                &volumeAddress,
                inputDevicePropertyChanged,
                context
            )
            hasInputVolumeListener = status == noErr
            if status != noErr {
                debugLog("[MicMute] Input volume listener install failed: \(status)")
            }
        }

        listenedInputDevice = device
    }

    /// Main-thread only.
    private func removeInputDeviceListeners() {
        guard let device = listenedInputDevice else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()

        if hasInputMuteListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectRemovePropertyListener(
                device,
                &address,
                inputDevicePropertyChanged,
                context
            )
            if status != noErr {
                debugLog("[MicMute] Input mute listener removal failed: \(status)")
            }
        }

        if hasInputVolumeListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectRemovePropertyListener(
                device,
                &address,
                inputDevicePropertyChanged,
                context
            )
            if status != noErr {
                debugLog("[MicMute] Input volume listener removal failed: \(status)")
            }
        }

        listenedInputDevice = nil
        hasInputMuteListener = false
        hasInputVolumeListener = false
    }

    private func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    /// Main-thread only.
    fileprivate func handleDefaultInputDeviceChanged() {
        installInputDeviceListeners()
        syncFromHardware()
        pruneStaleState()
    }

    /// Runs on main; reading CoreAudio properties is safe there.
    fileprivate func handleExternalInputChange() {
        syncFromHardware()
        pruneStaleState()
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

/// C callback for default input device changes.
private func defaultInputDeviceChanged(
    _ objectID: AudioObjectID,
    _ numAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let engine = Unmanaged<MicMuteEngine>.fromOpaque(clientData).takeUnretainedValue()
    DispatchQueue.main.async {
        engine.handleDefaultInputDeviceChanged()
    }
    return noErr
}

/// C callback for input mute/volume property changes on the default device.
private func inputDevicePropertyChanged(
    _ objectID: AudioObjectID,
    _ numAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let engine = Unmanaged<MicMuteEngine>.fromOpaque(clientData).takeUnretainedValue()
    DispatchQueue.main.async {
        engine.handleExternalInputChange()
    }
    return noErr
}
