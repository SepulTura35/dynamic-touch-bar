import Foundation

/// Finds the title of the media tab in a browser that is playing audio, through the browser's
/// own scripting dictionary (Automation permission, asked once). It reads only tab titles and
/// URLs, and only after audio from that browser was detected. Browsers don't say *which* tab
/// is audible, so this picks the first tab on a known media site; if none matches, no title is
/// shown rather than a guess.
nonisolated enum BrowserMediaTitle {
    struct Tab: Equatable, Sendable {
        let title: String
        let url: String
    }

    static let mediaHosts = [
        "music.youtube.com", "youtube.com", "open.spotify.com", "music.apple.com", "soundcloud.com",
        "deezer.com", "tidal.com", "listen.tidal.com", "music.amazon.com", "bandcamp.com", "twitch.tv", "vimeo.com",
    ]

    /// Browsers with a scriptable `tabs` collection exposing title/name and URL.
    static func script(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return """
            tell application id "\(bundleID)"
                set out to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        set end of out to {name of t as text, URL of t as text}
                    end repeat
                end repeat
                return out
            end tell
            """
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera":
            return """
            tell application id "\(bundleID)"
                set out to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        set end of out to {title of t as text, URL of t as text}
                    end repeat
                end repeat
                return out
            end tell
            """
        default:
            return nil
        }
    }

    static func host(of url: String) -> String? {
        URL(string: url)?.host?.lowercased().replacingOccurrences(of: "www.", with: "")
    }

    /// The first tab on a known media site, preferring the most specific host match.
    static func pick(_ tabs: [Tab]) -> Tab? {
        for mediaHost in mediaHosts {
            if let tab = tabs.first(where: { tab in
                guard let host = host(of: tab.url) else { return false }
                return host == mediaHost || host.hasSuffix("." + mediaHost)
            }) {
                return tab
            }
        }
        return nil
    }

    /// "(3) Song Name - YouTube" → "Song Name". Site suffixes and unread badges are removed.
    static func clean(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = result.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        for suffix in [" - YouTube Music", " - YouTube", " | Spotify", " - Spotify", " on Apple Music", " | SoundCloud", " - Twitch", " | Deezer", " on Vimeo"] {
            if result.hasSuffix(suffix) { result = String(result.dropLast(suffix.count)) }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func siteName(of url: String) -> String? {
        guard let host = host(of: url) else { return nil }
        switch true {
        case host.hasSuffix("music.youtube.com"): return "YouTube Music"
        case host.hasSuffix("youtube.com"): return "YouTube"
        case host.hasSuffix("spotify.com"): return "Spotify"
        case host.hasSuffix("music.apple.com"): return "Apple Music"
        case host.hasSuffix("soundcloud.com"): return "SoundCloud"
        case host.hasSuffix("deezer.com"): return "Deezer"
        case host.hasSuffix("tidal.com"): return "TIDAL"
        case host.hasSuffix("twitch.tv"): return "Twitch"
        default: return nil
        }
    }

    /// Fetches (title, site) for the playing browser, or nil.
    static func fetch(bundleID: String, completion: @escaping @MainActor @Sendable ((title: String, site: String?)?) -> Void) {
        guard let source = script(for: bundleID) else {
            Task { @MainActor in completion(nil) }
            return
        }
        AppleScriptRunner.run(source, parse: { descriptor -> [Tab] in
            descriptor.listItems.compactMap { pair in
                let items = pair.listItems
                guard items.count == 2 else { return nil }
                return Tab(title: items[0].stringValue ?? "", url: items[1].stringValue ?? "")
            }
        }) { result in
            guard case .success(let tabs?) = result, let tab = pick(tabs) else {
                completion(nil)
                return
            }
            let title = clean(tab.title)
            completion(title.isEmpty ? nil : (title, siteName(of: tab.url)))
        }
    }
}
