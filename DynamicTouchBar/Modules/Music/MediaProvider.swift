import AppKit

/// A media player we can legitimately observe and control.
///
/// Supported: Music.app and Spotify — both publish public distributed notifications and an
/// AppleScript dictionary. Other players (browsers, etc.) only expose their state through the
/// private MediaRemote framework, which this app deliberately does not use.
final class MediaProvider {
    let source: MediaSource

    var onUpdate: ((MediaSource, NowPlaying?) -> Void)?
    var onAutomationError: ((MediaSource, AppleScriptError) -> Void)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var isStarted = false

    init(source: MediaSource) {
        self.source = source
    }

    deinit {
        // Observers are removed in stop(); NotificationCenter tolerates deallocated observers.
    }

    var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playerInfoChanged(_:)),
            name: source.notificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self, app.bundleIdentifier == self.source.bundleID else { return }
                self.onUpdate?(self.source, nil)
            }
        })
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        DistributedNotificationCenter.default().removeObserver(self)
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    @objc private func playerInfoChanged(_ notification: Notification) {
        let info = notification.userInfo ?? [:]
        let now = Date()
        let parsed: NowPlaying? = switch source {
        case .appleMusic: NowPlaying.fromMusicNotification(info, now: now)
        case .spotify: NowPlaying.fromSpotifyNotification(info, now: now)
        }
        onUpdate?(source, parsed)
        // Music doesn't include the playhead in its payload; Spotify's can be stale.
        if parsed != nil { refresh() }
    }

    // MARK: - Status

    private var statusScript: String {
        let name = source.scriptingName
        let idExpression = source == .spotify ? "id of t" : "persistent ID of t"
        return """
        tell application "\(name)"
            set st to player state as text
            if st is "stopped" then return {"stopped"}
            set t to current track
            set tid to ""
            try
                set tid to (\(idExpression)) as text
            end try
            set d to ""
            try
                set d to (duration of t) as text
            end try
            set p to "0"
            try
                set p to (player position) as text
            end try
            return {st, (name of t) as text, (artist of t) as text, (album of t) as text, d, p, tid}
        end tell
        """
    }

    /// Queries the authoritative state (including playhead). Never launches the player.
    func refresh() {
        guard isAppRunning else {
            onUpdate?(source, nil)
            return
        }
        let source = self.source
        AppleScriptRunner.run(statusScript, parse: { descriptor in
            descriptor.listItems.map { $0.stringValue ?? "" }
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                self.onUpdate?(source, NowPlaying.fromScriptResult(items ?? [], source: source, now: Date()))
            case .failure(let error):
                self.report(error)
            }
        }
    }

    // MARK: - Controls

    func playPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }

    func seek(to seconds: TimeInterval) {
        let value = String(format: "%.2f", max(0, seconds)).replacingOccurrences(of: ",", with: ".")
        command("set player position to \(value)")
    }

    private func command(_ verb: String) {
        guard isAppRunning else { return }
        AppleScriptRunner.run("tell application \"\(source.scriptingName)\" to \(verb)") { [weak self] error in
            guard let self else { return }
            if let error { self.report(error) } else { self.refresh() }
        }
    }

    private func report(_ error: AppleScriptError) {
        if error.isAppNotRunning {
            onUpdate?(source, nil)
            return
        }
        Log.music.error("\(self.source.displayName, privacy: .public) script error \(error.code): \(error.message, privacy: .public)")
        onAutomationError?(source, error)
    }

    // MARK: - Artwork

    /// Music: embedded artwork bytes. Spotify: the cover URL, downloaded over HTTPS.
    func fetchArtwork(downloadAllowed: Bool, completion: @escaping @MainActor (NSImage?) -> Void) {
        guard isAppRunning else { completion(nil); return }
        switch source {
        case .appleMusic:
            let script = """
            tell application "Music"
                if (count of artworks of current track) > 0 then
                    return raw data of artwork 1 of current track
                end if
            end tell
            """
            AppleScriptRunner.run(script, parse: { descriptor -> Data? in
                let data = descriptor.data
                return data.isEmpty ? nil : data
            }) { result in
                if case .success(let data?) = result, let image = NSImage(data: data) {
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        case .spotify:
            guard downloadAllowed else { completion(nil); return }
            AppleScriptRunner.run("tell application \"Spotify\" to return artwork url of current track", parse: { $0.stringValue }) { result in
                guard case .success(let string?) = result,
                      let url = URL(string: string), url.scheme == "https" else {
                    completion(nil)
                    return
                }
                ArtworkDownloader.shared.image(at: url, completion: completion)
            }
        }
    }
}

/// Minimal, cookie-less image downloader (only used for Spotify cover art URLs).
final class ArtworkDownloader {
    static let shared = ArtworkDownloader()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpCookieStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()

    func image(at url: URL, completion: @escaping @MainActor (NSImage?) -> Void) {
        let task = session.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let payload = ok ? data : nil
            Task { @MainActor in completion(payload.flatMap { NSImage(data: $0) }) }
        }
        task.resume()
    }
}
