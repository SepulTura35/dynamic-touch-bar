import Foundation

nonisolated enum MediaSource: String, CaseIterable, Sendable {
    case appleMusic, spotify

    var bundleID: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Name used in AppleScript `tell application` blocks.
    var scriptingName: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }

    var displayName: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Distributed notification each player posts on play/pause/track change.
    var notificationName: Notification.Name {
        switch self {
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

nonisolated enum PlaybackState: String, Equatable, Sendable {
    case playing, paused, stopped

    init(playerStateString: String?) {
        switch playerStateString?.lowercased() {
        case "playing": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

/// Real playback information reported by a supported player. Position is stored with the
/// time it was sampled and extrapolated locally, so progress stays accurate with no polling.
nonisolated struct NowPlaying: Equatable, Sendable {
    var source: MediaSource
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    var position: TimeInterval
    var positionDate: Date
    var state: PlaybackState

    var isPlaying: Bool { state == .playing }

    func position(at date: Date) -> TimeInterval {
        var value = position
        if isPlaying { value += max(0, date.timeIntervalSince(positionDate)) }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    func fraction(at date: Date) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(position(at: date) / duration, 0), 1)
    }

    /// Same track, same state — only the sampled position differs.
    func isSameTrack(as other: NowPlaying?) -> Bool {
        guard let other else { return false }
        return source == other.source && trackID == other.trackID
    }

    // MARK: Parsing

    /// Parses Music.app's `com.apple.Music.playerInfo` userInfo. Position isn't included in
    /// that payload, so the caller follows up with one AppleScript query.
    static func fromMusicNotification(_ info: [AnyHashable: Any], now: Date) -> NowPlaying? {
        let state = PlaybackState(playerStateString: info["Player State"] as? String)
        guard state != .stopped else { return nil }
        let title = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
        let totalMilliseconds = (info["Total Time"] as? NSNumber)?.doubleValue
        let persistentID = (info["PersistentID"] as? NSNumber)?.int64Value
            ?? (info["Persistent ID"] as? NSNumber)?.int64Value
        let trackID = persistentID.map { String($0) } ?? "\(title)|\(artist)|\(album)"
        return NowPlaying(
            source: .appleMusic,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: totalMilliseconds.map { $0 / 1000 },
            position: 0,
            positionDate: now,
            state: state
        )
    }

    /// Parses Spotify's `com.spotify.client.PlaybackStateChanged` userInfo.
    static func fromSpotifyNotification(_ info: [AnyHashable: Any], now: Date) -> NowPlaying? {
        let state = PlaybackState(playerStateString: info["Player State"] as? String)
        guard state != .stopped else { return nil }
        let title = (info["Name"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        let durationMilliseconds = (info["Duration"] as? NSNumber)?.doubleValue
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        let trackID = (info["Track ID"] as? String) ?? "\(title)|\(artist)|\(album)"
        return NowPlaying(
            source: .spotify,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: durationMilliseconds.map { $0 / 1000 },
            position: position,
            positionDate: now,
            state: state
        )
    }

    /// Parses the list returned by the providers' status AppleScript:
    /// {state, name, artist, album, duration, position, id}. Spotify reports duration in ms.
    static func fromScriptResult(_ items: [String], source: MediaSource, now: Date) -> NowPlaying? {
        guard let first = items.first else { return nil }
        let state = PlaybackState(playerStateString: first)
        guard state != .stopped, items.count >= 7 else { return nil }
        let title = items[1]
        guard !title.isEmpty else { return nil }
        var duration = Double(items[4].replacingOccurrences(of: ",", with: "."))
        if source == .spotify, let ms = duration { duration = ms / 1000 }
        let position = Double(items[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        let id = items[6].isEmpty ? "\(title)|\(items[2])|\(items[3])" : items[6]
        return NowPlaying(
            source: source,
            trackID: id,
            title: title,
            artist: items[2],
            album: items[3],
            duration: duration,
            position: position,
            positionDate: now,
            state: state
        )
    }
}
