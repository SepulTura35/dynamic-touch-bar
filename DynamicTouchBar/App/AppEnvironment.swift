import AppKit
import Combine

/// Composition root: owns every service/model, wires their events into the island
/// coordinator, and applies settings. Views receive this object instead of singletons.
final class AppEnvironment {
    let hardware = HardwareInfo.current
    let settings: SettingsStore
    let coordinator: IslandCoordinator
    let music: MusicModel
    let volume = VolumeModel()
    let battery = BatteryMonitor()
    let brightness = BrightnessController()
    let timer: TimerEngine
    let progress: ProgressCenter
    let clipboard = ClipboardMonitor()
    let notifications = NotificationsModel()
    let context = ContextMonitor()
    let systemNotifier = SystemNotifier()
    let downloads: DownloadsWatcher
    let actions: ActionPerformer

    /// Hooks installed by the app delegate.
    var requestDismiss: (() -> Void)?
    var openSettings: (() -> Void)?
    /// Every interested party (summon auto-dismiss, always-on reveal) gets touch events.
    var interactionHandlers: [() -> Void] = []
    /// Installed by `AlwaysOnController`: bring the island over other apps for an event.
    var revealHandler: ((RevealReason) -> Void)?

    enum RevealReason { case music, transient, userRequest }

    /// The island is visible when DynamicTouchBar is the active app (public API) or when the
    /// opt-in always-on mode has revealed it over another app.
    private(set) var isAppActive = false
    private(set) var isSystemRevealed = false
    var isIslandVisible: Bool { isAppActive || isSystemRevealed }
    static let visibilityChanged = Notification.Name("DynamicTouchBar.islandVisibilityChanged")

    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var lastSettings: AppSettings

    init(settings: SettingsStore = SettingsStore(), scheduler: IslandScheduler = MainScheduler.shared) {
        self.settings = settings
        self.coordinator = IslandCoordinator(behavior: settings.settings.behavior, scheduler: scheduler)
        self.music = MusicModel(scheduler: scheduler)
        self.timer = TimerEngine(scheduler: scheduler)
        self.progress = ProgressCenter(scheduler: scheduler)
        self.downloads = DownloadsWatcher(progress: progress)
        self.actions = ActionPerformer(settings: settings, music: music, timer: timer, volume: volume, notifications: notifications)
        self.lastSettings = settings.settings
        wire()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        volume.start()
        battery.start()
        context.start()
        apply(settings.settings, initial: true)
        Log.app.info("\(self.hardware.summary, privacy: .public)")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        music.stop()
        volume.stop()
        battery.stop()
        context.stop()
        clipboard.setEnabled(false)
        downloads.setEnabled(false)
    }

    /// After wake: everything event-driven may have missed events while asleep.
    func handleWake() {
        battery.refresh()
        volume.refresh()
        music.refresh()
        timer.refresh()
        brightness.refreshPermission()
    }

    func noteInteraction() {
        coordinator.noteInteraction()
        interactionHandlers.forEach { $0() }
    }

    func setAppActive(_ active: Bool) {
        guard active != isAppActive else { return }
        isAppActive = active
        visibilityDidChange()
    }

    func setSystemRevealed(_ revealed: Bool) {
        guard revealed != isSystemRevealed else { return }
        isSystemRevealed = revealed
        visibilityDidChange()
    }

    private func visibilityDidChange() {
        coordinator.setVisible(isIslandVisible)
        NotificationCenter.default.post(name: Self.visibilityChanged, object: self)
    }

    /// Presents a transient, first asking always-on mode (if enabled) to reveal the island.
    func present(_ kind: TransientKind, duration: TimeInterval? = nil, holdWhenHidden: Bool = false, reveal: Bool = true) {
        guard settings.settings.isModuleEnabled(kind.module) else { return }
        if reveal { revealHandler?(.transient) }
        coordinator.present(kind, duration: duration, holdWhenHidden: holdWhenHidden)
    }

    func perform(_ ref: ActionRef) {
        noteInteraction()
        let outcome = actions.perform(ref)
        if case .returnFocus = outcome, settings.settings.returnFocusAfterAction {
            requestDismiss?()
        }
    }

    // MARK: - Wiring

    private func wire() {
        settings.$settings
            .dropFirst()
            .sink { [weak self] value in self?.apply(value, initial: false) }
            .store(in: &cancellables)

        music.$isLive
            .removeDuplicates()
            .sink { [weak self] live in
                guard let self else { return }
                if live && self.settings.settings.revealOnMusic { self.revealHandler?(.music) }
                self.coordinator.setLiveActivity(.music, active: live)
            }
            .store(in: &cancellables)
        music.onTrackChange = { [weak self] _ in
            guard let self, self.settings.settings.showOnTrackChange else { return }
            if self.settings.settings.revealOnMusic { self.revealHandler?(.music) }
            guard self.coordinator.isVisible else { return }
            if case .music(expanded: false) = self.coordinator.state.primary { self.coordinator.expand() }
        }

        timer.$session
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] active in
                guard let self else { return }
                self.coordinator.setLiveActivity(.timer, active: active)
                // Starting a timer is the natural moment to ask for notification permission.
                if active && self.settings.settings.timerSystemNotification { self.systemNotifier.requestAuthorizationIfNeeded() }
            }
            .store(in: &cancellables)
        timer.onComplete = { [weak self] finished, next in self?.timerCompleted(finished, next: next) }

        progress.$tasks
            .map { tasks in tasks.contains { $0.state == .running } }
            .removeDuplicates()
            .sink { [weak self] active in self?.coordinator.setLiveActivity(.progress, active: active) }
            .store(in: &cancellables)
        progress.onFinish = { [weak self] task in
            self?.notifications.post(IslandNotification(
                source: .progress,
                title: task.title,
                subtitle: task.detail ?? (task.state == .succeeded ? "Completed" : "Failed"),
                symbol: task.state == .succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill",
                tint: task.state == .succeeded ? .systemGreen : .systemRed
            ))
        }

        volume.onExternalChange = { [weak self] in
            guard let self, self.settings.settings.showVolumeOnChange else { return }
            self.present(.volume, reveal: self.settings.settings.revealOnVolume)
        }

        battery.onEvent = { [weak self] event in self?.batteryEvent(event) }

        clipboard.onCopy = { [weak self] _ in self?.present(.clipboard) }

        notifications.present = { [weak self] notification, hold in
            self?.present(.notification(notification.id), duration: notification.duration, holdWhenHidden: hold)
        }

        context.$contextApp
            .sink { [weak self] _ in self?.updateContextAvailability() }
            .store(in: &cancellables)
    }

    private func updateContextAvailability() {
        let available = settings.settings.profile(for: context.contextApp?.bundleID) != nil
        coordinator.setContextAvailable(available)
    }

    private func apply(_ value: AppSettings, initial: Bool) {
        coordinator.update(behavior: value.behavior)

        music.fetchSpotifyArtwork = value.fetchSpotifyArtwork
        music.pausedLinger = value.musicPausedLinger
        music.mediaKeyFallback = value.mediaKeyFallback
        music.detectAppAudio = value.detectAppAudio
        music.readBrowserTitles = value.readBrowserTabTitles
        if value.isModuleEnabled(.music) { music.start() } else { music.stop() }

        battery.lowThreshold = value.lowBatteryThreshold
        clipboard.hideSecrets = value.clipboardHideSecrets
        clipboard.previewLength = value.clipboardPreviewLength
        clipboard.setEnabled(value.isModuleEnabled(.clipboard))
        downloads.setEnabled(value.isModuleEnabled(.progress) && value.watchDownloads)

        timer.pomodoro = PomodoroConfig(
            work: TimeInterval(value.pomodoroWorkMinutes * 60),
            shortBreak: TimeInterval(value.pomodoroShortBreakMinutes * 60),
            longBreak: TimeInterval(value.pomodoroLongBreakMinutes * 60),
            rounds: value.pomodoroRounds
        )
        lastSettings = value
        updateContextAvailability()
    }

    // MARK: - Events

    private func timerCompleted(_ finished: TimerSession, next: TimerSession?) {
        let title: String
        var subtitle: String?
        switch finished.kind {
        case .pomodoro(let phase, _):
            title = phase == .work ? "Focus session complete" : "Break's over"
            subtitle = next.map { "\($0.label) started" } ?? "Pomodoro cycle complete"
        case .focus:
            title = "Focus session complete"
        case .countdown:
            title = "\(finished.label) finished"
            subtitle = finished.duration.map { TimeFormat.duration(minutes: Int($0 / 60)) }
        case .stopwatch:
            return
        }
        notifications.post(IslandNotification(source: .timer, title: title, subtitle: subtitle, symbol: "bell.and.waves.left.and.right.fill",
                                              tint: .systemOrange, duration: 6))
        if settings.settings.timerSound { NSSound(named: "Glass")?.play() }
        if settings.settings.timerSystemNotification && !coordinator.isVisible {
            systemNotifier.deliver(title: title, body: subtitle)
        }
    }

    private func batteryEvent(_ event: BatteryEvent) {
        let current = settings.settings
        switch event {
        case .pluggedIn, .unplugged:
            if current.showOnPowerChange { present(.battery) }
        case .low(let level):
            notifications.post(IslandNotification(source: .battery, title: "Low Battery", subtitle: "\(level)% remaining",
                                                  symbol: "battery.25percent", tint: .systemRed, duration: 5))
        case .fullyCharged:
            notifications.post(IslandNotification(source: .battery, title: "Fully Charged", subtitle: "You can unplug your Mac",
                                                  symbol: "battery.100percent.bolt", tint: .systemGreen), holdWhenHidden: false)
        }
    }
}
