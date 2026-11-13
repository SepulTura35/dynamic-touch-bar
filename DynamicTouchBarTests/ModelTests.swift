import AppKit
import Foundation
import IOKit.ps
import Testing
@testable import DynamicTouchBar

@MainActor
@Suite("Settings persistence")
struct SettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "DynamicTouchBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func roundTripsEveryChange() throws {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults, key: "s")
        store.update {
            $0.theme = .light
            $0.accent = .pink
            $0.autoCollapseDelay = 7.5
            $0.enabledModules = [.music, .timer]
            $0.livePriority = [.timer, .progress, .music]
            $0.customSpring = SpringParameters(response: 0.61, dampingFraction: 0.7)
            $0.customActions = [CustomAction(title: "Notes", symbol: "note.text", kind: .runShortcut("Daily Note"))]
            $0.profiles[0].actions = [.builtIn(.xcodeTest)]
            $0.timerSound = false
        }
        let reloaded = SettingsStore(defaults: defaults, key: "s")
        #expect(reloaded.settings == store.settings)
        #expect(reloaded.settings.timerSound == false)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let data = #"{"theme":"light","autoCollapseDelay":9}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.theme == .light)
        #expect(settings.autoCollapseDelay == 9)
        #expect(settings.accent == AppSettings().accent)
        #expect(settings.profiles == AppProfile.defaults)
    }

    @Test func malformedValuesAreClampedOrReplaced() throws {
        let data = #"{"autoCollapseDelay":500,"animationSpeed":-3,"theme":"neon","cornerRadius":"round"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.autoCollapseDelay == 15)
        #expect(settings.animationSpeed == 0.5)
        #expect(settings.theme == .dark)
        #expect(settings.cornerRadius == 15)
    }

    @Test func corruptDataUsesDefaults() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "s")
        let store = SettingsStore(defaults: defaults, key: "s")
        #expect(store.settings == AppSettings())
    }

    @Test func resetKeepsOnboardingFlag() {
        let store = SettingsStore(defaults: freshDefaults(), key: "s")
        store.update { $0.hasCompletedOnboarding = true; $0.theme = .light }
        store.reset()
        #expect(store.settings.theme == .dark)
        #expect(store.settings.hasCompletedOnboarding)
    }

    @Test func clipboardIsOptIn() {
        #expect(!AppSettings().enabledModules.contains(.clipboard))
    }

    @Test func behaviorReflectsMasterSwitch() {
        var settings = AppSettings()
        settings.isEnabled = false
        #expect(settings.behavior.enabledModules.isEmpty)
    }

    @Test func profileLookupRequiresEnabledProfileWithActions() {
        var settings = AppSettings()
        #expect(settings.profile(for: "com.apple.dt.Xcode") != nil)
        settings.profiles[0].isEnabled = false
        #expect(settings.profile(for: "com.apple.dt.Xcode") == nil)
        #expect(settings.profile(for: nil) == nil)
    }
}

@MainActor
@Suite("Timer engine")
struct TimerEngineTests {
    let scheduler = ManualScheduler()

    @Test func countdownCompletesOnTimeEvenWhenNobodyIsWatching() {
        let engine = TimerEngine(scheduler: scheduler)
        var completed: TimerSession?
        engine.onComplete = { finished, _ in completed = finished }
        engine.startCountdown(minutes: 5)
        scheduler.advance(by: 120)
        #expect(engine.session?.remaining(at: scheduler.now) == 180)
        scheduler.advance(by: 180)
        #expect(completed?.kind == .countdown)
        #expect(engine.session == nil)
    }

    @Test func pauseStopsTheClock() {
        let engine = TimerEngine(scheduler: scheduler)
        engine.startCountdown(minutes: 1)
        scheduler.advance(by: 20)
        engine.pause()
        scheduler.advance(by: 600)
        #expect(engine.session?.remaining(at: scheduler.now) == 40)
        engine.resume()
        scheduler.advance(by: 39)
        #expect(engine.session != nil)
        scheduler.advance(by: 1)
        #expect(engine.session == nil)
    }

    @Test func addMinuteExtendsCompletion() {
        let engine = TimerEngine(scheduler: scheduler)
        engine.startCountdown(minutes: 1)
        scheduler.advance(by: 50)
        engine.addMinute()
        scheduler.advance(by: 60)
        #expect(engine.session != nil)
        scheduler.advance(by: 10)
        #expect(engine.session == nil)
    }

    @Test func pomodoroCyclesThroughPhases() {
        let engine = TimerEngine(scheduler: scheduler)
        engine.pomodoro = PomodoroConfig(work: 100, shortBreak: 10, longBreak: 30, rounds: 2)
        var finished: [TimerKind] = []
        engine.onComplete = { session, _ in finished.append(session.kind) }
        engine.startPomodoro()
        scheduler.advance(by: 100)
        #expect(engine.session?.kind == .pomodoro(.shortBreak, round: 1))
        scheduler.advance(by: 10)
        #expect(engine.session?.kind == .pomodoro(.work, round: 2))
        scheduler.advance(by: 100)
        #expect(engine.session?.kind == .pomodoro(.longBreak, round: 2))
        scheduler.advance(by: 30)
        #expect(engine.session == nil)
        #expect(finished == [.pomodoro(.work, round: 1), .pomodoro(.shortBreak, round: 1), .pomodoro(.work, round: 2), .pomodoro(.longBreak, round: 2)])
    }

    @Test func stopwatchCountsUpAndNeverCompletes() {
        let engine = TimerEngine(scheduler: scheduler)
        engine.startStopwatch()
        scheduler.advance(by: 3725)
        #expect(engine.session?.elapsed(at: scheduler.now) == 3725)
        #expect(engine.session?.displayTime(at: scheduler.now) == "1:02:05")
        #expect(scheduler.pendingCount == 0)
    }

    @Test func refreshAfterSleepCompletesExpiredTimer() {
        let engine = TimerEngine(scheduler: scheduler)
        var done = false
        engine.onComplete = { _, _ in done = true }
        engine.startCountdown(minutes: 1)
        engine.refresh()
        #expect(!done)
        scheduler.advance(by: 61)
        #expect(done)
    }
}

@MainActor
@Suite("Parsing and formatting")
struct ParsingTests {
    let now = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func parsesMusicNotification() {
        let info: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Song", "Artist": "Artist", "Album": "Album",
                                        "Total Time": NSNumber(value: 201_000), "PersistentID": NSNumber(value: Int64(42))]
        let track = NowPlaying.fromMusicNotification(info, now: now)
        #expect(track?.title == "Song")
        #expect(track?.duration == 201)
        #expect(track?.trackID == "42")
        #expect(track?.isPlaying == true)
    }

    @Test func stoppedMusicIsNil() {
        #expect(NowPlaying.fromMusicNotification(["Player State": "Stopped"], now: now) == nil)
    }

    @Test func parsesSpotifyNotification() {
        let info: [AnyHashable: Any] = ["Player State": "Paused", "Name": "Track", "Artist": "A", "Album": "B",
                                        "Duration": NSNumber(value: 180_000), "Playback Position": NSNumber(value: 42.5), "Track ID": "spotify:track:1"]
        let track = NowPlaying.fromSpotifyNotification(info, now: now)
        #expect(track?.state == .paused)
        #expect(track?.position == 42.5)
        #expect(track?.duration == 180)
    }

    @Test func parsesScriptResultsWithLocaleDecimals() {
        let music = NowPlaying.fromScriptResult(["playing", "S", "A", "B", "200,5", "12,25", "ABC"], source: .appleMusic, now: now)
        #expect(music?.duration == 200.5)
        #expect(music?.position == 12.25)
        let spotify = NowPlaying.fromScriptResult(["paused", "S", "A", "B", "180000", "3", "id"], source: .spotify, now: now)
        #expect(spotify?.duration == 180)
        #expect(NowPlaying.fromScriptResult(["stopped"], source: .spotify, now: now) == nil)
    }

    @Test func positionExtrapolatesOnlyWhilePlaying() {
        var track = NowPlaying(source: .spotify, trackID: "1", title: "T", artist: "A", album: "B", duration: 100,
                               position: 10, positionDate: now, state: .playing)
        #expect(track.position(at: now.addingTimeInterval(5)) == 15)
        #expect(track.position(at: now.addingTimeInterval(500)) == 100)
        track.state = .paused
        #expect(track.position(at: now.addingTimeInterval(5)) == 10)
    }

    @Test func parsesBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 83, kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true, kIOPSTimeToFullChargeKey: 47,
        ]
        let info = BatteryInfo.parse(descriptions: [description], adapter: [kIOPSPowerAdapterWattsKey: 61], lowPowerMode: false)
        #expect(info.hasBattery && info.level == 83 && info.isCharging && info.isPluggedIn)
        #expect(info.adapterWatts == 61)
        #expect(info.statusText == "47 min to full")
        #expect(!BatteryInfo.parse(descriptions: [], adapter: nil, lowPowerMode: false).hasBattery)
    }

    @Test func batteryTransitionsEmitEventsOnce() {
        var warned = false
        let base = BatteryInfo(hasBattery: true, level: 50, isCharging: false, isPluggedIn: false, isCharged: false,
                               minutesToEmpty: nil, minutesToFull: nil, adapterWatts: nil, isLowPowerMode: false)
        var plugged = base; plugged.isPluggedIn = true; plugged.isCharging = true
        #expect(BatteryMonitor.events(from: base, to: plugged, lowThreshold: 20, alreadyWarned: &warned) == [.pluggedIn])
        #expect(BatteryMonitor.events(from: plugged, to: base, lowThreshold: 20, alreadyWarned: &warned) == [.unplugged])
        var low = base; low.level = 19
        #expect(BatteryMonitor.events(from: base, to: low, lowThreshold: 20, alreadyWarned: &warned) == [.low(19)])
        var lower = low; lower.level = 18
        #expect(BatteryMonitor.events(from: low, to: lower, lowThreshold: 20, alreadyWarned: &warned).isEmpty)
        var full = plugged; full.level = 100; full.isCharging = false; full.isCharged = true
        var nearlyFull = plugged; nearlyFull.level = 99
        #expect(BatteryMonitor.events(from: nearlyFull, to: full, lowThreshold: 20, alreadyWarned: &warned) == [.fullyCharged])
    }

    @Test func detectsTouchBarModels() {
        #expect(HardwareInfo(modelIdentifier: "MacBookPro17,1").hasTouchBar)
        #expect(HardwareInfo(modelIdentifier: "Mac14,7").hasTouchBar)
        #expect(!HardwareInfo(modelIdentifier: "MacBookPro18,3").hasTouchBar) // 14" M1 Pro: no Touch Bar
        #expect(!HardwareInfo(modelIdentifier: "Mac14,9").hasTouchBar)        // 14" M2 Pro: no Touch Bar
        #expect(!HardwareInfo.readModelIdentifier().isEmpty)
    }

    @Test func formatsTimes() {
        #expect(TimeFormat.clock(0) == "0:00")
        #expect(TimeFormat.clock(201.9) == "3:21")
        #expect(TimeFormat.clock(3725) == "1:02:05")
        #expect(TimeFormat.clock(-5) == "0:00")
        #expect(TimeFormat.clock(.nan) == "0:00")
        #expect(TimeFormat.countdown(59.1) == "1:00")
        #expect(TimeFormat.stopwatch(62.37) == "1:02.3")
        #expect(TimeFormat.duration(minutes: 80) == "1 h 20 min")
    }

    @Test func truncatesPreviews() {
        #expect("hello   world\n\nagain".truncatedForPreview(50) == "hello world again")
        #expect("abcdefghij".truncatedForPreview(5) == "abcd…")
    }
}

@MainActor
@Suite("Clipboard privacy")
struct ClipboardPrivacyTests {
    @Test func detectsSecrets() {
        #expect(ClipboardPrivacy.looksLikeSecret("sk-proj-abcdEFGH1234ijklMNOP"))
        #expect(ClipboardPrivacy.looksLikeSecret("ghp_16C7e42F292c6912E7710c838347Ae178B4a"))
        #expect(ClipboardPrivacy.looksLikeSecret("Tr0ub4dor&3xyz"))
        #expect(ClipboardPrivacy.looksLikeSecret("-----BEGIN OPENSSH PRIVATE KEY-----\nabc"))
    }

    @Test func leavesOrdinaryTextAlone() {
        #expect(!ClipboardPrivacy.looksLikeSecret("Meeting notes for Thursday"))
        #expect(!ClipboardPrivacy.looksLikeSecret("https://www.apple.com/macbook-pro/?ref=Touch_Bar_2024"))
        #expect(!ClipboardPrivacy.looksLikeSecret("someone@example.com"))
        #expect(!ClipboardPrivacy.looksLikeSecret("hello"))
        #expect(!ClipboardPrivacy.looksLikeSecret("1234567890"))
    }

    @Test func concealedPasteboardTypesAreSkipped() {
        #expect(ClipboardPrivacy.isConcealed(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardPrivacy.isConcealed(types: ["public.utf8-plain-text"]))
    }

    @Test func classifiesAndHidesSecrets() {
        let now = Date()
        let secret = ClipboardPrivacy.classify("AKIAIOSFODNN7EXAMPLE1234", hideSecrets: true, previewLength: 40, now: now)
        #expect(secret.kind == .secret(24))
        #expect(!secret.preview.contains("AKIA"))
        let shown = ClipboardPrivacy.classify("AKIAIOSFODNN7EXAMPLE1234", hideSecrets: false, previewLength: 40, now: now)
        #expect(shown.kind == .text)
        #expect(ClipboardPrivacy.classify("https://apple.com", hideSecrets: true, previewLength: 40, now: now).kind == .url)
        #expect(ClipboardPrivacy.classify("a@b.co", hideSecrets: true, previewLength: 40, now: now).kind == .email)
        #expect(ClipboardPrivacy.classify("1,234.5", hideSecrets: true, previewLength: 40, now: now).kind == .number)
        #expect(ClipboardPrivacy.classify(String(repeating: "word ", count: 40), hideSecrets: true, previewLength: 20, now: now).preview.count == 20)
    }
}

@MainActor
@Suite("URL commands")
struct URLCommandTests {
    private func parse(_ string: String) -> URLCommand? { URLCommand.parse(URL(string: string)!) }

    @Test func parsesBasics() {
        #expect(parse("dynamictouchbar://show") == .show)
        #expect(parse("DynamicTouchBar://TOGGLE") == .toggle)
        #expect(parse("dynamictouchbar://timer/stop") == .stopTimer)
        #expect(parse("dynamictouchbar://pomodoro") == .pomodoro)
        #expect(parse("https://show") == nil)
        #expect(parse("dynamictouchbar://rm-rf") == nil)
    }

    @Test func parsesNotify() {
        #expect(parse("dynamictouchbar://notify?title=Deploy%20done&body=Green&symbol=checkmark.seal.fill&duration=99")
                == .notify(title: "Deploy done", body: "Green", symbol: "checkmark.seal.fill", duration: 30))
        #expect(parse("dynamictouchbar://notify?body=missing-title") == nil)
        if case .notify(_, _, let symbol, _) = parse("dynamictouchbar://notify?title=x&symbol=../../etc") {
            #expect(symbol == nil)
        } else {
            Issue.record("expected notify")
        }
    }

    @Test func limitsTextLength() {
        let long = String(repeating: "a", count: 500)
        guard case .notify(let title, _, _, _) = parse("dynamictouchbar://notify?title=\(long)") else {
            Issue.record("expected notify")
            return
        }
        #expect(title.count == URLCommand.maxTextLength)
    }

    @Test func parsesProgress() {
        #expect(parse("dynamictouchbar://progress?id=build&title=Building&value=0.42")
                == .progress(id: "build", title: "Building", value: 0.42, state: .running))
        #expect(parse("dynamictouchbar://progress?id=build&value=42")
                == .progress(id: "build", title: nil, value: 0.42, state: .running))
        #expect(parse("dynamictouchbar://progress?id=build&state=done")
                == .progress(id: "build", title: nil, value: nil, state: .done))
        #expect(parse("dynamictouchbar://progress?id=x&value=-4") == .progress(id: "x", title: nil, value: 0, state: .running))
        #expect(parse("dynamictouchbar://progress?title=no-id") == nil)
    }

    @Test func parsesTimer() {
        #expect(parse("dynamictouchbar://timer?minutes=25&label=Tea") == .timer(minutes: 25, label: "Tea"))
        #expect(parse("dynamictouchbar://timer?minutes=0") == nil)
        #expect(parse("dynamictouchbar://timer?minutes=nan") == nil)
        #expect(parse("dynamictouchbar://timer?minutes=99999") == .timer(minutes: 1440, label: nil))
    }
}

@MainActor
@Suite("Progress and music models")
struct LiveModelTests {
    let scheduler = ManualScheduler()

    @Test func progressLifecycle() {
        let center = ProgressCenter(scheduler: scheduler)
        var finished: [ProgressTask] = []
        center.onFinish = { finished.append($0) }
        center.upsert(id: "a", title: "Build", fraction: 0.2)
        center.upsert(id: "a", title: nil, fraction: 1.7)
        #expect(center.primary?.fraction == 1)
        #expect(center.primary?.title == "Build")
        center.finish(id: "a", success: true)
        #expect(!center.isActive)
        #expect(finished.map(\.state) == [.succeeded])
    }

    @Test func staleProgressExpires() {
        let center = ProgressCenter(scheduler: scheduler)
        center.upsert(id: "a", title: "Stuck", fraction: nil)
        scheduler.advance(by: ProgressCenter.staleTimeout + 1)
        #expect(center.tasks.isEmpty)
    }

    @Test func downloadWatcherRecognisesPartialFiles() {
        #expect(DownloadsWatcher.isPartial("movie.mov.download"))
        #expect(DownloadsWatcher.isPartial("x.zip.crdownload"))
        #expect(!DownloadsWatcher.isPartial("x.zip"))
        #expect(DownloadsWatcher.displayName("movie.mov.download") == "movie.mov")
    }

    private func track(_ id: String, _ state: PlaybackState) -> NowPlaying {
        NowPlaying(source: .spotify, trackID: id, title: "T\(id)", artist: "A", album: "B", duration: 200,
                   position: 0, positionDate: scheduler.now, state: state)
    }

    @Test func musicLingersAfterPauseThenLeaves() {
        let model = MusicModel(scheduler: scheduler)
        model.pausedLinger = 60
        model.ingest(source: .spotify, value: track("1", .playing))
        #expect(model.isLive)
        scheduler.advance(by: 600) // played for 10 minutes without notifications
        model.ingest(source: .spotify, value: track("1", .paused))
        #expect(model.isLive)
        scheduler.advance(by: 59)
        #expect(model.isLive)
        scheduler.advance(by: 2)
        #expect(!model.isLive)
    }

    @Test func pausedAtLaunchIsNotLive() {
        let model = MusicModel(scheduler: scheduler)
        model.ingest(source: .spotify, value: track("1", .paused))
        #expect(!model.isLive)
        #expect(model.nowPlaying?.trackID == "1")
    }

    @Test func trackChangeFiresOnlyForNewTracks() {
        let model = MusicModel(scheduler: scheduler)
        var changes: [String] = []
        model.onTrackChange = { changes.append($0.trackID) }
        model.ingest(source: .spotify, value: track("1", .playing))
        model.ingest(source: .spotify, value: track("1", .paused))
        model.ingest(source: .spotify, value: track("1", .playing))
        model.ingest(source: .spotify, value: track("2", .playing))
        #expect(changes == ["1", "2"])
        model.ingest(source: .spotify, value: nil)
        #expect(model.nowPlaying == nil && !model.isLive)
    }
}
