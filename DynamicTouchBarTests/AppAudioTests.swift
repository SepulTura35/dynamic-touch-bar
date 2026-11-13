import Foundation
import Testing
@testable import DynamicTouchBar

@MainActor
@Suite("Browser & app audio")
struct AppAudioTests {
    typealias App = AudioActivityMonitor.RunningApp

    let running = [
        App(bundleID: "com.apple.Safari", name: "Safari", pid: 100),
        App(bundleID: "com.google.Chrome", name: "Google Chrome", pid: 200),
        App(bundleID: "com.spotify.client", name: "Spotify", pid: 300),
        App(bundleID: "com.dynamictouchbar.app", name: "DynamicTouchBar", pid: 400),
        App(bundleID: "us.zoom.xos", name: "zoom.us", pid: 500),
    ]

    private func resolve(_ bundle: String, pid: pid_t = 9999) -> String? {
        AudioActivityMonitor.resolve(processBundleID: bundle, pid: pid, runningApps: running, ownBundleID: "com.dynamictouchbar.app")?.bundleID
    }

    @Test func mapsWebKitAudioToSafari() {
        #expect(resolve("com.apple.WebKit.GPU") == "com.apple.Safari")
    }

    @Test func mapsHelpersToTheirApp() {
        #expect(resolve("com.google.Chrome.helper") == "com.google.Chrome")
        #expect(resolve("com.google.Chrome.helper.Renderer") == "com.google.Chrome")
    }

    @Test func directPIDMatchWins() {
        #expect(resolve("anything", pid: 500) == "us.zoom.xos")
    }

    @Test func ignoresSystemDaemonsSelfAndRichPlayers() {
        #expect(resolve("com.apple.CoreSpeech") == nil)
        #expect(resolve("") == nil)
        #expect(resolve("x", pid: 400) == nil)       // ourselves
        #expect(resolve("x", pid: 300) == nil)       // Spotify reports full info elsewhere
        #expect(resolve("com.spotify.client.helper") == nil)
    }

    @Test func webKitWithoutSafariIsUnattributed() {
        let none = AudioActivityMonitor.resolve(processBundleID: "com.apple.WebKit.GPU", pid: 1, runningApps: [], ownBundleID: nil)
        #expect(none == nil)
    }

    @Test func picksMediaTabAndCleansTitle() {
        let tabs = [
            BrowserMediaTitle.Tab(title: "Inbox (3)", url: "https://mail.example.com"),
            BrowserMediaTitle.Tab(title: "(2) Lofi beats to study to - YouTube", url: "https://www.youtube.com/watch?v=1"),
        ]
        let tab = BrowserMediaTitle.pick(tabs)
        #expect(tab?.url == "https://www.youtube.com/watch?v=1")
        #expect(BrowserMediaTitle.clean(tab!.title) == "Lofi beats to study to")
        #expect(BrowserMediaTitle.siteName(of: tab!.url) == "YouTube")
    }

    @Test func prefersYouTubeMusicOverYouTube() {
        let tabs = [
            BrowserMediaTitle.Tab(title: "Video - YouTube", url: "https://youtube.com/watch?v=2"),
            BrowserMediaTitle.Tab(title: "Song - YouTube Music", url: "https://music.youtube.com/watch?v=3"),
        ]
        let tab = BrowserMediaTitle.pick(tabs)
        #expect(BrowserMediaTitle.siteName(of: tab!.url) == "YouTube Music")
        #expect(BrowserMediaTitle.clean(tab!.title) == "Song")
    }

    @Test func noMediaTabMeansNoTitle() {
        #expect(BrowserMediaTitle.pick([BrowserMediaTitle.Tab(title: "Docs", url: "https://developer.apple.com")]) == nil)
        #expect(BrowserMediaTitle.script(for: "com.example.unknown") == nil)
        #expect(BrowserMediaTitle.script(for: "com.apple.Safari") != nil)
    }

    private let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari", processIdentifier: 100)

    @Test func browserAudioMakesMusicLiveAndLingers() {
        let scheduler = ManualScheduler()
        let model = MusicModel(scheduler: scheduler)
        model.readBrowserTitles = false
        model.pausedLinger = 30
        model.ingestAudioActivity(safari)
        #expect(model.isLive)
        #expect(model.display?.isExternal == true)
        #expect(model.display?.title == "Playing audio")
        #expect(model.display?.subtitle == "Safari")
        #expect(model.display?.isPlaying == true)

        model.ingestAudioActivity(nil)
        #expect(model.isLive)
        #expect(model.display?.isPlaying == false)
        scheduler.advance(by: 31)
        #expect(!model.isLive)
        #expect(model.display == nil)
        #expect(model.external == nil)
    }

    @Test func richPlayerWinsWhileItPlays() {
        let scheduler = ManualScheduler()
        let model = MusicModel(scheduler: scheduler)
        model.readBrowserTitles = false
        model.ingest(source: .spotify, value: NowPlaying(source: .spotify, trackID: "1", title: "Rich", artist: "A", album: "B",
                                                         duration: 100, position: 0, positionDate: scheduler.now, state: .playing))
        model.ingestAudioActivity(safari)
        #expect(model.display?.title == "Rich")
        model.ingest(source: .spotify, value: NowPlaying(source: .spotify, trackID: "1", title: "Rich", artist: "A", album: "B",
                                                         duration: 100, position: 5, positionDate: scheduler.now, state: .paused))
        #expect(model.display?.isExternal == true)
    }
}
