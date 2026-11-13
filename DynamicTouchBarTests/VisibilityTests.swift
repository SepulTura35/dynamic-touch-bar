import Foundation
import Testing
@testable import DynamicTouchBar

@MainActor
@Suite("Island visibility & always-on reveal")
struct VisibilityTests {
    private func makeEnvironment(_ configure: (inout AppSettings) -> Void = { _ in }) -> AppEnvironment {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "DTBVisibility.\(UUID().uuidString)")!, key: "s")
        store.update {
            $0.expandOnSummon = false
            $0.timerSystemNotification = false
            configure(&$0)
        }
        return AppEnvironment(settings: store, scheduler: ManualScheduler())
    }

    @Test func visibleWhenActiveOrRevealed() {
        let env = makeEnvironment()
        #expect(!env.isIslandVisible && !env.coordinator.isVisible)
        env.setAppActive(true)
        #expect(env.coordinator.isVisible)
        env.setAppActive(false)
        env.setSystemRevealed(true)
        #expect(env.isIslandVisible && env.coordinator.isVisible)
        env.setSystemRevealed(false)
        #expect(!env.coordinator.isVisible)
    }

    @Test func transientIsDroppedWhenHiddenWithoutAlwaysOn() {
        let env = makeEnvironment()
        env.present(.battery)
        #expect(env.coordinator.state.primary == .minimal)
    }

    @Test func presentAsksForRevealFirst() {
        let env = makeEnvironment()
        var reasons: [AppEnvironment.RevealReason] = []
        env.revealHandler = { reason in
            reasons.append(reason)
            env.setSystemRevealed(true) // what AlwaysOnController does
        }
        env.present(.battery)
        #expect(reasons == [.transient])
        #expect(env.coordinator.state.primary == .battery)
    }

    @Test func volumeRevealIsOptIn() {
        let env = makeEnvironment { $0.revealOnVolume = false }
        var revealed = false
        env.revealHandler = { _ in revealed = true; env.setSystemRevealed(true) }
        env.present(.volume, reveal: env.settings.settings.revealOnVolume)
        #expect(!revealed)
        #expect(env.coordinator.state.primary == .minimal)
    }

    @Test func disabledModuleNeverReveals() {
        let env = makeEnvironment { $0.enabledModules.remove(.battery) }
        var revealed = false
        env.revealHandler = { _ in revealed = true }
        env.present(.battery)
        #expect(!revealed)
    }

    @Test func musicStartingAsksForReveal() {
        let env = makeEnvironment { $0.revealOnMusic = true }
        var reasons: [AppEnvironment.RevealReason] = []
        env.revealHandler = { reason in reasons.append(reason); env.setSystemRevealed(true) }
        env.music.ingest(source: .spotify, value: NowPlaying(source: .spotify, trackID: "t", title: "Test", artist: "A", album: "B",
                                                            duration: 100, position: 0, positionDate: Date(), state: .playing))
        #expect(reasons.contains(.music))
        #expect(env.coordinator.state.primary == .music(expanded: false))
    }

    @Test func alwaysOnSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.alwaysOnMode = true
        settings.alwaysOnCoverControlStrip = true
        settings.revealOnVolume = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(!AppSettings().alwaysOnMode) // opt-in
    }
}
