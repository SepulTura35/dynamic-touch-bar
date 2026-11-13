import AppKit
import Combine

/// Opt-in "Always-on" mode (uses the private API in `SystemTouchBarBridge`).
///
/// * **Idle:** the island is minimised. Your normal Touch Bar is untouched, and a small island
///   button sits in the Control Strip.
/// * **Something happens** (music starts, track changes, a notification, the charger, a copy…):
///   the island rises over the current app's controls for a few seconds, then minimises again.
///   Any touch keeps it up; tapping the Control Strip button brings it up on demand.
/// * When DynamicTouchBar itself is frontmost, the regular public-API bar is used instead.
final class AlwaysOnController: NSObject, NSTouchBarDelegate {
    static let islandIdentifier = NSTouchBarItem.Identifier("com.dynamictouchbar.system.island")
    static let trayIdentifier = NSTouchBarItem.Identifier("com.dynamictouchbar.system.tray")

    private unowned let env: AppEnvironment
    private var bar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?
    private var isInstalled = false
    private(set) var isRevealed = false
    private var concealToken: ScheduledToken?
    private var cancellables = Set<AnyCancellable>()

    init(env: AppEnvironment) {
        self.env = env
        super.init()
    }

    private var wantsEnabled: Bool {
        env.settings.settings.alwaysOnMode && env.settings.settings.isEnabled && SystemTouchBarBridge.isAvailable
    }

    /// Seconds the island stays up after the last event or touch.
    private var holdDuration: TimeInterval { env.settings.settings.autoCollapseDelay + 1.5 }

    func start() {
        env.revealHandler = { [weak self] reason in self?.reveal(reason) }
        env.interactionHandlers.append { [weak self] in
            guard let self, self.isRevealed else { return }
            self.scheduleConceal()
        }

        env.settings.$settings
            .map { ($0.alwaysOnMode && $0.isEnabled, $0.alwaysOnCoverControlStrip) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _ in self?.reconfigure() }
            .store(in: &cancellables)

        // Keep the island up while transients/notifications are still cycling through.
        env.coordinator.$state
            .sink { [weak self] _ in
                guard let self, self.isRevealed, self.env.coordinator.currentTransientKind != nil else { return }
                self.scheduleConceal()
            }
            .store(in: &cancellables)

        // When our app comes to the front, its regular Touch Bar takes over.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.conceal() }
            .store(in: &cancellables)
    }

    func stop() {
        uninstall()
        cancellables.removeAll()
        env.revealHandler = nil
    }

    /// Re-creates everything (after wake, or if the Touch Bar server restarted).
    func rebuild() {
        guard isInstalled else { return }
        uninstall()
        install()
    }

    private func reconfigure() {
        if wantsEnabled {
            if isInstalled { rebuild() } else { install() }
        } else {
            uninstall()
        }
    }

    // MARK: - Install

    private func install() {
        guard wantsEnabled, !isInstalled else { return }
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.islandIdentifier]
        bar.principalItemIdentifier = Self.islandIdentifier
        self.bar = bar

        let tray = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Show Dynamic Island")
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(trayTapped))
        button.setAccessibilityLabel("Show Dynamic Island")
        tray.view = button
        tray.customizationLabel = "Dynamic Island"
        trayItem = tray
        SystemTouchBarBridge.setTrayItem(tray, installed: true)

        isInstalled = true
        Log.touchBar.info("Always-on mode installed (cover Control Strip: \(self.env.settings.settings.alwaysOnCoverControlStrip))")
    }

    private func uninstall() {
        guard isInstalled else { return }
        concealToken?.cancel()
        if let bar { SystemTouchBarBridge.dismiss(bar) }
        if let trayItem { SystemTouchBarBridge.setTrayItem(trayItem, installed: false) }
        bar = nil
        trayItem = nil
        isInstalled = false
        setRevealed(false)
        Log.touchBar.info("Always-on mode removed")
    }

    // MARK: - Reveal / conceal

    func reveal(_ reason: AppEnvironment.RevealReason) {
        guard isInstalled, let bar, !NSApp.isActive else { return }
        if !isRevealed {
            SystemTouchBarBridge.present(bar, trayIdentifier: Self.trayIdentifier,
                                         coverControlStrip: env.settings.settings.alwaysOnCoverControlStrip)
            setRevealed(true)
            Log.touchBar.info("Always-on: revealed over \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?", privacy: .public) (\(String(describing: reason), privacy: .public))")
        }
        if reason == .userRequest { env.coordinator.expand() }
        scheduleConceal()
    }

    func conceal() {
        concealToken?.cancel()
        concealToken = nil
        guard isRevealed else { return }
        if let bar { SystemTouchBarBridge.minimize(bar) }
        setRevealed(false)
        Log.touchBar.info("Always-on: minimised")
    }

    private func setRevealed(_ revealed: Bool) {
        isRevealed = revealed
        env.setSystemRevealed(revealed)
    }

    private func scheduleConceal() {
        concealToken?.cancel()
        concealToken = MainScheduler.shared.schedule(after: holdDuration) { [weak self] in
            guard let self else { return }
            // Don't drop it mid-notification; check again shortly.
            if self.env.coordinator.currentTransientKind != nil {
                self.scheduleConceal()
            } else {
                self.conceal()
            }
        }
    }

    @objc private func trayTapped() {
        if isRevealed {
            env.coordinator.tapCapsule()
            scheduleConceal()
        } else {
            reveal(.userRequest)
        }
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.islandIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = TouchBarIslandContainer(island: IslandView(env: env, role: .touchBar))
        item.customizationLabel = "Dynamic Island"
        return item
    }
}
