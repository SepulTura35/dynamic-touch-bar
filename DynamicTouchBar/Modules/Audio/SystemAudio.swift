import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Output volume via public CoreAudio HAL properties. Fully event-driven: property listeners
/// fire on volume, mute and default-device changes — no polling, no permissions.
final class VolumeModel: ObservableObject {
    @Published private(set) var volume: Double = 0
    @Published private(set) var isMuted = false
    @Published private(set) var isAvailable = false
    @Published private(set) var deviceName = ""

    /// Called for changes that didn't originate from our own slider (hardware keys, Control
    /// Strip, other apps) so the island can pop up.
    var onExternalChange: (() -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var suppressExternalUntil = Date.distantPast
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var isStarted = false

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, listener)
        attachToDefaultDevice()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        detachFromDevice()
        if let deviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, deviceListener)
        }
        deviceListener = nil
    }

    /// Re-reads everything (after wake).
    func refresh() {
        guard isStarted else { return }
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        detachFromDevice()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else {
            isAvailable = false
            deviceName = ""
            return
        }
        deviceID = id
        deviceName = Self.name(of: id) ?? "Output"

        let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readState(notify: true) }
        }
        volumeListener = volumeBlock
        if AudioObjectHasProperty(id, &Self.volumeAddress) {
            AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, volumeBlock)
        }
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readState(notify: true) }
        }
        muteListener = muteBlock
        if AudioObjectHasProperty(id, &Self.muteAddress) {
            AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, muteBlock)
        }
        readState(notify: false)
    }

    private func detachFromDevice() {
        guard deviceID != kAudioObjectUnknown else { return }
        if let volumeListener {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.volumeAddress, .main, volumeListener)
        }
        if let muteListener {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddress, .main, muteListener)
        }
        volumeListener = nil
        muteListener = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func readState(notify: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var available = false
        if AudioObjectHasProperty(deviceID, &Self.volumeAddress) {
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &value) == noErr {
                let newVolume = Double(min(max(value, 0), 1))
                if abs(newVolume - volume) > 0.0005 { volume = newVolume }
                available = true
            }
        }
        if AudioObjectHasProperty(deviceID, &Self.muteAddress) {
            var muted = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &muted) == noErr {
                if (muted != 0) != isMuted { isMuted = muted != 0 }
            }
        }
        var settable = DarwinBoolean(false)
        if available, AudioObjectIsPropertySettable(deviceID, &Self.volumeAddress, &settable) == noErr {
            available = settable.boolValue
        }
        if available != isAvailable { isAvailable = available }
        if notify && Date() > suppressExternalUntil { onExternalChange?() }
    }

    // MARK: - Control

    func setVolume(_ newValue: Double) {
        guard isAvailable, deviceID != kAudioObjectUnknown else { return }
        suppressExternalUntil = Date().addingTimeInterval(0.4)
        var value = Float32(min(max(newValue, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &Self.volumeAddress, 0, nil, size, &value)
        volume = Double(value)
        if isMuted && value > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown, AudioObjectHasProperty(deviceID, &Self.muteAddress) else { return }
        suppressExternalUntil = Date().addingTimeInterval(0.4)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        isMuted = muted
    }

    func toggleMute() { setMuted(!isMuted) }

    /// Effective level for display (0 when muted).
    var displayLevel: Double { isMuted ? 0 : volume }

    static func symbol(level: Double, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }
}
