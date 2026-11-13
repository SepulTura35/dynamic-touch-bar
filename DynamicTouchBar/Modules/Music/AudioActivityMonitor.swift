import AppKit
import CoreAudio

/// Detects which *app* is producing sound, using public CoreAudio process objects
/// (`kAudioHardwarePropertyProcessObjectList`, macOS 14.2+). Event-driven property
/// listeners, no polling, and no permission is needed — it only reveals *that* an app is
/// playing audio, never the audio itself.
///
/// This is how browser playback (YouTube, Spotify Web, …) is detected: Apple restricted the
/// MediaRemote "Now Playing" framework to its own apps in macOS 15.4, and the known
/// workarounds bypass that restriction, which this app does not do.
final class AudioActivityMonitor {
    /// Called with the app now playing audio (debounced), or nil when audio stops.
    var onChange: ((AppIdentity?) -> Void)?
    private(set) var current: AppIdentity?

    private var listListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pendingToken: ScheduledToken?
    private var pendingCandidate: AppIdentity?
    private var isStarted = false

    /// Sound shorter than this (notification pings, UI sounds) is ignored.
    static let startDebounce: TimeInterval = 1.5
    /// Gaps shorter than this (between tracks, buffering) don't count as stopping.
    static let stopDebounce: TimeInterval = 1.2

    /// Rich players handled by `MediaProvider` with full track info.
    static let richPlayers: Set<String> = Set(MediaSource.allCases.map(\.bundleID))

    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var runningOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningOutput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    func start() {
        guard Self.isSupported, !isStarted else { return }
        isStarted = true
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebuildProcessListeners() }
        }
        listListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.processListAddress, .main, block)
        rebuildProcessListeners()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        if let listListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.processListAddress, .main, listListener)
        }
        listListener = nil
        for (id, block) in processListeners {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningOutputAddress, .main, block)
        }
        processListeners.removeAll()
        pendingToken?.cancel()
        current = nil
    }

    private func processObjects() -> [AudioObjectID] {
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &Self.processListAddress, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &Self.processListAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func rebuildProcessListeners() {
        let ids = Set(processObjects())
        for (id, block) in processListeners where !ids.contains(id) {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningOutputAddress, .main, block)
            processListeners[id] = nil
        }
        for id in ids where processListeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &Self.runningOutputAddress, .main, block) == noErr {
                processListeners[id] = block
            }
        }
        evaluate()
    }

    private struct AudioProcess {
        let bundleID: String
        let pid: pid_t
    }

    private func playingProcesses() -> [AudioProcess] {
        processListeners.keys.compactMap { id in
            var running = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &Self.runningOutputAddress, 0, nil, &size, &running) == noErr, running != 0 else { return nil }
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid = pid_t(0)
            size = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &size, &pid)
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bundle: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &bundle) { AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &size, $0) }
            let bundleID = status == noErr ? (bundle?.takeRetainedValue() as String?) ?? "" : ""
            return AudioProcess(bundleID: bundleID, pid: pid)
        }
    }

    private func evaluate() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { RunningApp(bundleID: $0, name: app.localizedName ?? $0, pid: app.processIdentifier) } }
        let candidate = playingProcesses().lazy
            .compactMap { Self.resolve(processBundleID: $0.bundleID, pid: $0.pid, runningApps: running) }
            .first
        schedule(candidate)
    }

    private func schedule(_ candidate: AppIdentity?) {
        guard candidate?.bundleID != current?.bundleID else {
            pendingToken?.cancel()
            pendingCandidate = nil
            return
        }
        if pendingCandidate?.bundleID == candidate?.bundleID, pendingToken != nil { return }
        pendingToken?.cancel()
        pendingCandidate = candidate
        let delay = candidate == nil ? Self.stopDebounce : Self.startDebounce
        pendingToken = MainScheduler.shared.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.pendingToken = nil
            self.pendingCandidate = nil
            self.current = candidate
            Log.music.info("Audio activity: \(candidate?.bundleID ?? "none", privacy: .public)")
            self.onChange?(candidate)
        }
    }

    // MARK: - Resolution (pure, unit-tested)

    struct RunningApp: Equatable {
        let bundleID: String
        let name: String
        let pid: pid_t
    }

    /// Maps an audio-producing process to the user-facing app that owns it:
    /// the app itself, its helper (`com.google.Chrome.helper` → Chrome), or for WebKit's
    /// shared audio process, Safari. System daemons, DynamicTouchBar itself and the rich
    /// players (Music, Spotify — they report full track info elsewhere) are ignored.
    static func resolve(processBundleID: String, pid: pid_t, runningApps: [RunningApp], ownBundleID: String? = Bundle.main.bundleIdentifier) -> AppIdentity? {
        func identity(_ app: RunningApp) -> AppIdentity? {
            guard app.bundleID != ownBundleID, !richPlayers.contains(app.bundleID) else { return nil }
            return AppIdentity(bundleID: app.bundleID, name: app.name, processIdentifier: app.pid)
        }
        if let direct = runningApps.first(where: { $0.pid == pid }) { return identity(direct) }
        guard !processBundleID.isEmpty else { return nil }
        if processBundleID.hasPrefix("com.apple.WebKit") {
            let safari = runningApps.first { $0.bundleID == "com.apple.Safari" } ?? runningApps.first { $0.bundleID == "com.apple.SafariTechnologyPreview" }
            return safari.flatMap(identity)
        }
        let owner = runningApps
            .filter { processBundleID.hasPrefix($0.bundleID + ".") || processBundleID == $0.bundleID }
            .max { $0.bundleID.count < $1.bundleID.count }
        return owner.flatMap(identity)
    }
}
