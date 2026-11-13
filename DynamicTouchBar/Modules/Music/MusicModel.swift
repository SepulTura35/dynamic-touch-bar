import AppKit
import Combine

/// Audio coming from an app without a public Now Playing API (browsers, video apps…).
struct ExternalPlayback: Equatable {
    var app: AppIdentity
    /// Title of the media tab, when the browser exposes it; never guessed.
    var title: String?
    var site: String?
    var isPlaying: Bool
    var lastPlaying: Date
}

/// What the music views render, whichever source it came from.
struct MusicDisplay: Equatable {
    enum Source: Equatable {
        case player(MediaSource)
        case app(String)
    }

    var source: Source
    var title: String
    var subtitle: String
    var isPlaying: Bool

    var isExternal: Bool {
        if case .app = source { return true }
        return false
    }
}

/// Aggregates the supported players into one "now playing" source of truth.
final class MusicModel: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var tint: NSColor?
    /// True while the island should show music as a live activity.
    @Published private(set) var isLive = false
    /// Browser/other-app audio detected through CoreAudio.
    @Published private(set) var external: ExternalPlayback?
    /// Single description of what to show (rich player or external app).
    @Published private(set) var display: MusicDisplay?
    /// Artwork for rich players, the app icon for external playback.
    @Published private(set) var displayImage: NSImage?
    /// Set when a player refused Automation access; surfaced in Settings ▸ Permissions.
    @Published private(set) var automationDenied: Set<MediaSource> = []

    /// Fired when a *different* track starts playing (not on pause/resume).
    var onTrackChange: ((NowPlaying) -> Void)?

    var fetchSpotifyArtwork = true
    var pausedLinger: TimeInterval = 90 { didSet { updateLiveness() } }
    var mediaKeyFallback = false
    var detectAppAudio = true {
        didSet { if isStarted { detectAppAudio ? audioActivity.start() : audioActivity.stop() } }
    }
    var readBrowserTitles = true

    private let audioActivity = AudioActivityMonitor()
    private var isStarted = false

    private let providers: [MediaSource: MediaProvider]
    private var states: [MediaSource: NowPlaying] = [:]
    private var lastPlayingDate: [MediaSource: Date] = [:]
    private var lingerToken: ScheduledToken?
    private var resyncTimer: Timer?
    private var artworkTrackKey: String?
    private let artworkCache = NSCache<NSString, NSImage>()
    private let tintCache = NSCache<NSString, NSColor>()
    private let scheduler: IslandScheduler

    init(scheduler: IslandScheduler = MainScheduler.shared) {
        self.scheduler = scheduler
        artworkCache.countLimit = 40
        var providers: [MediaSource: MediaProvider] = [:]
        for source in MediaSource.allCases { providers[source] = MediaProvider(source: source) }
        self.providers = providers
        for provider in providers.values {
            provider.onUpdate = { [weak self] source, value in self?.ingest(source: source, value: value) }
            provider.onAutomationError = { [weak self] source, error in
                if error.isNotAuthorized { self?.automationDenied.insert(source) }
            }
        }
        audioActivity.onChange = { [weak self] app in self?.ingestAudioActivity(app) }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        providers.values.forEach { $0.start() }
        if detectAppAudio { audioActivity.start() }
    }

    func stop() {
        isStarted = false
        providers.values.forEach { $0.stop() }
        audioActivity.stop()
        setResyncDemand(false)
    }

    /// Re-reads the authoritative playhead (after wake, or when the user summons the island).
    func refresh() { providers.values.forEach { $0.refresh() } }

    /// While the expanded player is on screen, re-sync the playhead every 10 s to absorb seeks
    /// made inside the player itself. Off otherwise — zero polling while collapsed.
    func setResyncDemand(_ active: Bool) {
        if active {
            guard resyncTimer == nil else { return }
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.display?.isExternal == true { self.fetchExternalTitle() } else { self.activeProvider?.refresh() }
                }
            }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            resyncTimer = timer
        } else {
            resyncTimer?.invalidate()
            resyncTimer = nil
        }
    }

    // MARK: - Ingest

    func ingest(source: MediaSource, value: NowPlaying?) {
        let previousActive = nowPlaying
        if let value {
            // "Last playing" is the moment playback was last observed — including the
            // instant it transitions to paused — so the linger window starts at the pause.
            let wasPlaying = states[source]?.isPlaying ?? false
            states[source] = value
            if value.isPlaying || wasPlaying { lastPlayingDate[source] = scheduler.now }
            automationDenied.remove(source)
        } else {
            states[source] = nil
        }
        let active = chooseActive()
        if active != nowPlaying { nowPlaying = active }

        if let active, !active.isSameTrack(as: previousActive) {
            loadArtwork(for: active)
            if active.isPlaying { onTrackChange?(active) }
        } else if active == nil {
            artwork = nil
            tint = nil
            artworkTrackKey = nil
        }
        updateLiveness()
    }

    /// Called (debounced) by the audio monitor with the app producing sound, or nil.
    func ingestAudioActivity(_ app: AppIdentity?) {
        let now = scheduler.now
        if let app {
            let isNewApp = external?.app.bundleID != app.bundleID
            let wasPlaying = external?.isPlaying ?? false
            if isNewApp {
                external = ExternalPlayback(app: app, title: nil, site: nil, isPlaying: true, lastPlaying: now)
            } else {
                external?.isPlaying = true
                external?.lastPlaying = now
            }
            if isNewApp || !wasPlaying { fetchExternalTitle() }
        } else if external != nil {
            external?.isPlaying = false
            external?.lastPlaying = now
        }
        updateLiveness()
    }

    private func fetchExternalTitle() {
        guard readBrowserTitles, let bundleID = external?.app.bundleID else { return }
        BrowserMediaTitle.fetch(bundleID: bundleID) { [weak self] result in
            guard let self, self.external?.app.bundleID == bundleID else { return }
            if self.external?.title != result?.title || self.external?.site != result?.site {
                self.external?.title = result?.title
                self.external?.site = result?.site
                self.recomputeDisplay()
            }
        }
    }

    private func recomputeDisplay() {
        let rich = nowPlaying
        let ext = external
        let next: MusicDisplay?
        var image: NSImage?
        let preferExternal = ext != nil && (rich == nil || (ext!.isPlaying && !(rich?.isPlaying ?? false)))
        if preferExternal, let ext {
            next = MusicDisplay(source: .app(ext.app.bundleID),
                                title: ext.title ?? "Playing audio",
                                subtitle: [ext.site, ext.app.name].compactMap { $0 }.joined(separator: " · "),
                                isPlaying: ext.isPlaying)
            image = ext.app.icon
        } else if let rich {
            next = MusicDisplay(source: .player(rich.source), title: rich.title,
                                subtitle: rich.artist.isEmpty ? rich.album : rich.artist, isPlaying: rich.isPlaying)
            image = artwork
        } else {
            next = nil
        }
        if next != display { display = next }
        if image !== displayImage { displayImage = image }
    }

    private func chooseActive() -> NowPlaying? {
        let all = Array(states.values)
        if let playing = all.filter(\.isPlaying).max(by: { $0.positionDate < $1.positionDate }) { return playing }
        return all.max { (lastPlayingDate[$0.source] ?? .distantPast) < (lastPlayingDate[$1.source] ?? .distantPast) }
    }

    /// Live while anything plays, and for `pausedLinger` seconds after it pauses.
    private func updateLiveness() {
        lingerToken?.cancel()
        lingerToken = nil
        let now = scheduler.now
        var live = false
        var recheck: TimeInterval?

        if let current = nowPlaying {
            if current.isPlaying {
                live = true
            } else {
                let remaining = pausedLinger - now.timeIntervalSince(lastPlayingDate[current.source] ?? .distantPast)
                if remaining > 0 { live = true; recheck = remaining }
            }
        }
        if let ext = external {
            if ext.isPlaying {
                live = true
            } else {
                let remaining = pausedLinger - now.timeIntervalSince(ext.lastPlaying)
                if remaining > 0 {
                    live = true
                    recheck = min(recheck ?? remaining, remaining)
                } else {
                    external = nil
                }
            }
        }
        if let recheck {
            lingerToken = scheduler.schedule(after: recheck + 0.01) { [weak self] in self?.updateLiveness() }
        }
        recomputeDisplay()
        if live != isLive { isLive = live }
    }

    private var activeProvider: MediaProvider? {
        nowPlaying.flatMap { providers[$0.source] }
    }

    // MARK: - Artwork

    private func loadArtwork(for track: NowPlaying) {
        let key = "\(track.source.rawValue)|\(track.trackID)"
        artworkTrackKey = key
        if let cached = artworkCache.object(forKey: key as NSString) {
            artwork = cached
            tint = tintCache.object(forKey: key as NSString)
            recomputeDisplay()
            return
        }
        // Keep the previous cover until the new one arrives (cross-fades in the view).
        providers[track.source]?.fetchArtwork(downloadAllowed: fetchSpotifyArtwork) { [weak self] image in
            guard let self, self.artworkTrackKey == key else { return }
            if let image {
                self.artworkCache.setObject(image, forKey: key as NSString)
                let color = ColorExtraction.tint(from: image)
                if let color { self.tintCache.setObject(color, forKey: key as NSString) }
                self.artwork = image
                self.tint = color
                self.recomputeDisplay()
            } else {
                self.artwork = nil
                self.tint = nil
                self.recomputeDisplay()
            }
        }
    }

    // MARK: - Controls

    /// True when there is something we can control (a supported player, or media keys).
    var canControl: Bool { nowPlaying != nil || external != nil || (mediaKeyFallback && KeyEventPoster.isTrusted) }

    /// External apps (browsers) are controlled with the standard media keys, which macOS
    /// routes to whichever app is playing. Needs Accessibility; asks on first use.
    private func mediaKey(_ key: KeyEventPoster.MediaKey) {
        if !KeyEventPoster.post(key) { KeyEventPoster.requestTrust() }
    }

    func playPause() {
        if display?.isExternal == true {
            mediaKey(.playPause)
        } else if let provider = activeProvider {
            optimisticToggle()
            provider.playPause()
        } else if mediaKeyFallback {
            KeyEventPoster.post(.playPause)
        }
    }

    func nextTrack() {
        if display?.isExternal == true { mediaKey(.next); return }
        if let provider = activeProvider { provider.nextTrack() } else if mediaKeyFallback { KeyEventPoster.post(.next) }
    }

    func previousTrack() {
        if display?.isExternal == true { mediaKey(.previous); return }
        if let provider = activeProvider { provider.previousTrack() } else if mediaKeyFallback { KeyEventPoster.post(.previous) }
    }

    func seek(toFraction fraction: Double) {
        guard let current = nowPlaying, let duration = current.duration, duration > 0 else { return }
        let seconds = min(max(fraction, 0), 1) * duration
        var updated = current
        updated.position = seconds
        updated.positionDate = scheduler.now
        states[current.source] = updated
        nowPlaying = updated
        providers[current.source]?.seek(to: seconds)
    }

    /// Flip the play state immediately so the button responds instantly; the player's own
    /// notification confirms (or corrects) it a moment later.
    private func optimisticToggle() {
        guard var current = nowPlaying else { return }
        let now = scheduler.now
        current.position = current.position(at: now)
        current.positionDate = now
        current.state = current.isPlaying ? .paused : .playing
        lastPlayingDate[current.source] = now
        states[current.source] = current
        nowPlaying = current
        updateLiveness()
    }
}
