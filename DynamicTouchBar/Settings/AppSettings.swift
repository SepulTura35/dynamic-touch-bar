import Foundation

nonisolated enum IslandTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark, light
    var id: String { rawValue }
    var title: String { self == .dark ? "Dark" : "Light" }
}

nonisolated enum AccentChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var title: String { rawValue == "system" ? "System" : rawValue.capitalized }
}

/// Global shortcut that brings the island onto the Touch Bar. Registered with the public
/// Carbon `RegisterEventHotKey` API — no Accessibility permission needed.
nonisolated enum HotKeyPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlOptionSpace, controlOptionCommandSpace, controlOptionI, optionShiftSpace, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionCommandSpace: "⌃⌥⌘Space"
        case .controlOptionI: "⌃⌥I"
        case .optionShiftSpace: "⌥⇧Space"
        case .off: "Off"
        }
    }

    /// (virtual key code, Carbon modifier mask)
    var carbonDefinition: (keyCode: UInt32, modifiers: UInt32)? {
        let cmd: UInt32 = 0x0100, shift: UInt32 = 0x0200, option: UInt32 = 0x0800, control: UInt32 = 0x1000
        let space: UInt32 = 49, keyI: UInt32 = 34
        switch self {
        case .controlOptionSpace: return (space, control | option)
        case .controlOptionCommandSpace: return (space, control | option | cmd)
        case .controlOptionI: return (keyI, control | option)
        case .optionShiftSpace: return (space, option | shift)
        case .off: return nil
        }
    }
}

/// Every user preference. Stored as one JSON blob in `UserDefaults`; decoding is tolerant —
/// missing or malformed keys fall back to defaults, so new versions never lose old settings.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = AppSettings.currentSchemaVersion

    // MARK: General
    var isEnabled = true
    var hotKey: HotKeyPreset = .controlOptionSpace
    var expandOnSummon = true
    var autoCollapse = true
    var autoCollapseDelay: Double = 4
    var defaultState: DefaultIslandState = .minimal
    var showMirrorWindow = !HardwareInfo.current.hasTouchBar
    var returnFocusAfterAction = true
    /// Seconds of no interaction before handing focus back to the previous app. 0 = never.
    var autoDismissDelay: Double = 0
    var hasCompletedOnboarding = false
    /// Opt-in: uses the private system-modal Touch Bar API (see SystemTouchBarBridge) so the
    /// island can appear over other apps when something happens.
    var alwaysOnMode = false
    var alwaysOnCoverControlStrip = false
    var revealOnMusic = true
    var revealOnVolume = false

    // MARK: Appearance
    var theme: IslandTheme = .dark
    var accent: AccentChoice = .system
    var tintFromArtwork = true
    var ambientGlow = true
    var capsuleWidthScale: Double = 1.0
    var cornerRadius: Double = 15
    var animationStyle: AnimationStyle = .smooth
    var animationSpeed: Double = 1.0
    var customSpring: SpringParameters = .smooth

    // MARK: Modules
    var enabledModules: Set<IslandModule> = Set(IslandModule.allCases).subtracting([.clipboard])
    var showOnTrackChange = true
    var fetchSpotifyArtwork = true
    var musicPausedLinger: Double = 90
    var mediaKeyFallback = false
    var detectAppAudio = true
    var readBrowserTabTitles = true
    var lowBatteryThreshold = 20
    var showOnPowerChange = true
    var showVolumeOnChange = true
    var clipboardHideSecrets = true
    var clipboardPreviewLength = 48
    var pomodoroWorkMinutes = 25
    var pomodoroShortBreakMinutes = 5
    var pomodoroLongBreakMinutes = 15
    var pomodoroRounds = 4
    var timerSystemNotification = true
    var timerSound = true
    var watchDownloads = false

    // MARK: Advanced
    var livePriority: [LiveActivityKind] = [.music, .timer, .progress]
    var profiles: [AppProfile] = AppProfile.defaults
    var customActions: [CustomAction] = []
    var dashboardActions: [ActionRef] = []
    var debugMode = false

    init() {}

    // MARK: Derived

    var springParameters: SpringParameters {
        animationStyle.parameters(custom: customSpring).scaled(speed: animationSpeed)
    }

    var behavior: IslandBehavior {
        var behavior = IslandBehavior()
        behavior.defaultState = defaultState
        behavior.expandOnSummon = expandOnSummon
        behavior.autoCollapse = autoCollapse
        behavior.autoCollapseDelay = autoCollapseDelay
        behavior.transientDuration = max(1.2, autoCollapseDelay * 0.6)
        behavior.notificationDuration = max(2.5, autoCollapseDelay)
        behavior.livePriority = livePriority
        behavior.enabledModules = isEnabled ? enabledModules : []
        return behavior
    }

    func isModuleEnabled(_ module: IslandModule) -> Bool { isEnabled && enabledModules.contains(module) }

    func profile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID && $0.isEnabled && !$0.actions.isEmpty }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, isEnabled, hotKey, expandOnSummon, autoCollapse, autoCollapseDelay, defaultState
        case showMirrorWindow, returnFocusAfterAction, autoDismissDelay, hasCompletedOnboarding
        case alwaysOnMode, alwaysOnCoverControlStrip, revealOnMusic, revealOnVolume
        case theme, accent, tintFromArtwork, ambientGlow, capsuleWidthScale, cornerRadius
        case animationStyle, animationSpeed, customSpring
        case enabledModules, showOnTrackChange, fetchSpotifyArtwork, musicPausedLinger, mediaKeyFallback, detectAppAudio, readBrowserTabTitles
        case lowBatteryThreshold, showOnPowerChange, showVolumeOnChange, clipboardHideSecrets, clipboardPreviewLength
        case pomodoroWorkMinutes, pomodoroShortBreakMinutes, pomodoroLongBreakMinutes, pomodoroRounds
        case timerSystemNotification, timerSound, watchDownloads
        case livePriority, profiles, customActions, dashboardActions, debugMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        schemaVersion = c.value(.schemaVersion, d.schemaVersion)
        isEnabled = c.value(.isEnabled, d.isEnabled)
        hotKey = c.value(.hotKey, d.hotKey)
        expandOnSummon = c.value(.expandOnSummon, d.expandOnSummon)
        autoCollapse = c.value(.autoCollapse, d.autoCollapse)
        autoCollapseDelay = c.value(.autoCollapseDelay, d.autoCollapseDelay).clamped(1, 15)
        defaultState = c.value(.defaultState, d.defaultState)
        showMirrorWindow = c.value(.showMirrorWindow, d.showMirrorWindow)
        returnFocusAfterAction = c.value(.returnFocusAfterAction, d.returnFocusAfterAction)
        autoDismissDelay = c.value(.autoDismissDelay, d.autoDismissDelay).clamped(0, 300)
        hasCompletedOnboarding = c.value(.hasCompletedOnboarding, d.hasCompletedOnboarding)
        alwaysOnMode = c.value(.alwaysOnMode, d.alwaysOnMode)
        alwaysOnCoverControlStrip = c.value(.alwaysOnCoverControlStrip, d.alwaysOnCoverControlStrip)
        revealOnMusic = c.value(.revealOnMusic, d.revealOnMusic)
        revealOnVolume = c.value(.revealOnVolume, d.revealOnVolume)
        theme = c.value(.theme, d.theme)
        accent = c.value(.accent, d.accent)
        tintFromArtwork = c.value(.tintFromArtwork, d.tintFromArtwork)
        ambientGlow = c.value(.ambientGlow, d.ambientGlow)
        capsuleWidthScale = c.value(.capsuleWidthScale, d.capsuleWidthScale).clamped(0.8, 1.3)
        cornerRadius = c.value(.cornerRadius, d.cornerRadius).clamped(6, 15)
        animationStyle = c.value(.animationStyle, d.animationStyle)
        animationSpeed = c.value(.animationSpeed, d.animationSpeed).clamped(0.5, 2)
        customSpring = c.value(.customSpring, d.customSpring)
        enabledModules = c.value(.enabledModules, d.enabledModules)
        showOnTrackChange = c.value(.showOnTrackChange, d.showOnTrackChange)
        fetchSpotifyArtwork = c.value(.fetchSpotifyArtwork, d.fetchSpotifyArtwork)
        musicPausedLinger = c.value(.musicPausedLinger, d.musicPausedLinger).clamped(0, 3600)
        mediaKeyFallback = c.value(.mediaKeyFallback, d.mediaKeyFallback)
        detectAppAudio = c.value(.detectAppAudio, d.detectAppAudio)
        readBrowserTabTitles = c.value(.readBrowserTabTitles, d.readBrowserTabTitles)
        lowBatteryThreshold = c.value(.lowBatteryThreshold, d.lowBatteryThreshold).clamped(5, 50)
        showOnPowerChange = c.value(.showOnPowerChange, d.showOnPowerChange)
        showVolumeOnChange = c.value(.showVolumeOnChange, d.showVolumeOnChange)
        clipboardHideSecrets = c.value(.clipboardHideSecrets, d.clipboardHideSecrets)
        clipboardPreviewLength = c.value(.clipboardPreviewLength, d.clipboardPreviewLength).clamped(16, 120)
        pomodoroWorkMinutes = c.value(.pomodoroWorkMinutes, d.pomodoroWorkMinutes).clamped(1, 180)
        pomodoroShortBreakMinutes = c.value(.pomodoroShortBreakMinutes, d.pomodoroShortBreakMinutes).clamped(1, 60)
        pomodoroLongBreakMinutes = c.value(.pomodoroLongBreakMinutes, d.pomodoroLongBreakMinutes).clamped(1, 90)
        pomodoroRounds = c.value(.pomodoroRounds, d.pomodoroRounds).clamped(1, 12)
        timerSystemNotification = c.value(.timerSystemNotification, d.timerSystemNotification)
        timerSound = c.value(.timerSound, d.timerSound)
        watchDownloads = c.value(.watchDownloads, d.watchDownloads)
        livePriority = c.value(.livePriority, d.livePriority)
        profiles = c.value(.profiles, d.profiles)
        customActions = c.value(.customActions, d.customActions)
        dashboardActions = c.value(.dashboardActions, d.dashboardActions)
        debugMode = c.value(.debugMode, d.debugMode)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(hotKey, forKey: .hotKey)
        try c.encode(expandOnSummon, forKey: .expandOnSummon)
        try c.encode(autoCollapse, forKey: .autoCollapse)
        try c.encode(autoCollapseDelay, forKey: .autoCollapseDelay)
        try c.encode(defaultState, forKey: .defaultState)
        try c.encode(showMirrorWindow, forKey: .showMirrorWindow)
        try c.encode(returnFocusAfterAction, forKey: .returnFocusAfterAction)
        try c.encode(autoDismissDelay, forKey: .autoDismissDelay)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try c.encode(alwaysOnMode, forKey: .alwaysOnMode)
        try c.encode(alwaysOnCoverControlStrip, forKey: .alwaysOnCoverControlStrip)
        try c.encode(revealOnMusic, forKey: .revealOnMusic)
        try c.encode(revealOnVolume, forKey: .revealOnVolume)
        try c.encode(theme, forKey: .theme)
        try c.encode(accent, forKey: .accent)
        try c.encode(tintFromArtwork, forKey: .tintFromArtwork)
        try c.encode(ambientGlow, forKey: .ambientGlow)
        try c.encode(capsuleWidthScale, forKey: .capsuleWidthScale)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(animationStyle, forKey: .animationStyle)
        try c.encode(animationSpeed, forKey: .animationSpeed)
        try c.encode(customSpring, forKey: .customSpring)
        try c.encode(enabledModules.map(\.rawValue).sorted(), forKey: .enabledModules)
        try c.encode(showOnTrackChange, forKey: .showOnTrackChange)
        try c.encode(fetchSpotifyArtwork, forKey: .fetchSpotifyArtwork)
        try c.encode(musicPausedLinger, forKey: .musicPausedLinger)
        try c.encode(mediaKeyFallback, forKey: .mediaKeyFallback)
        try c.encode(detectAppAudio, forKey: .detectAppAudio)
        try c.encode(readBrowserTabTitles, forKey: .readBrowserTabTitles)
        try c.encode(lowBatteryThreshold, forKey: .lowBatteryThreshold)
        try c.encode(showOnPowerChange, forKey: .showOnPowerChange)
        try c.encode(showVolumeOnChange, forKey: .showVolumeOnChange)
        try c.encode(clipboardHideSecrets, forKey: .clipboardHideSecrets)
        try c.encode(clipboardPreviewLength, forKey: .clipboardPreviewLength)
        try c.encode(pomodoroWorkMinutes, forKey: .pomodoroWorkMinutes)
        try c.encode(pomodoroShortBreakMinutes, forKey: .pomodoroShortBreakMinutes)
        try c.encode(pomodoroLongBreakMinutes, forKey: .pomodoroLongBreakMinutes)
        try c.encode(pomodoroRounds, forKey: .pomodoroRounds)
        try c.encode(timerSystemNotification, forKey: .timerSystemNotification)
        try c.encode(timerSound, forKey: .timerSound)
        try c.encode(watchDownloads, forKey: .watchDownloads)
        try c.encode(livePriority, forKey: .livePriority)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(customActions, forKey: .customActions)
        try c.encode(dashboardActions, forKey: .dashboardActions)
        try c.encode(debugMode, forKey: .debugMode)
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `defaultValue` when missing *or* malformed.
    func value<T: Decodable>(_ key: Key, _ defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}

nonisolated extension Comparable {
    func clamped(_ lower: Self, _ upper: Self) -> Self { min(max(self, lower), upper) }
}
