import AppKit
import Combine

/// Brings the island onto the Touch Bar and hands focus back afterwards.
///
/// Public AppKit only shows the Touch Bar of the *active* app. "Summoning" therefore activates
/// DynamicTouchBar (from the global shortcut or the menu bar), remembers which app the user
/// came from, and "dismissing" re-activates that app — so the island feels like an overlay
/// without injecting anything into other apps.
final class SummonController {
    private unowned let env: AppEnvironment
    private var previousApp: NSRunningApplication?
    private var mirror: IslandMirrorWindow?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var autoDismissToken: ScheduledToken?

    init(env: AppEnvironment) {
        self.env = env
    }

    var isSummoned: Bool { NSApp.isActive }

    func start() {
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.activeChanged() }
            .store(in: &cancellables)
        center.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.activeChanged() }
            .store(in: &cancellables)
        env.settings.$settings
            .map(\.showMirrorWindow)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.updateMirror() }
            .store(in: &cancellables)
        env.interactionHandlers.append { [weak self] in self?.scheduleAutoDismiss() }

        // Esc on the Touch Bar (or keyboard) returns to the previous app while the island
        // has focus and no other window of ours (e.g. Settings) is key.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.isSummoned else { return event }
            let key = NSApp.keyWindow
            if key == nil || key === self.mirror {
                self.dismiss()
                return nil
            }
            return event
        }
        activeChanged()
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        cancellables.removeAll()
    }

    func toggle() {
        if isSummoned && (NSApp.keyWindow == nil || NSApp.keyWindow === mirror) {
            dismiss()
        } else {
            summon()
        }
    }

    func summon() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        if env.settings.settings.showMirrorWindow { showMirror() }
        NSApp.activate()
        Log.app.info("Summon requested (previous app: \(self.previousApp?.bundleIdentifier ?? "none", privacy: .public))")
    }

    func dismiss() {
        autoDismissToken?.cancel()
        hideMirror()
        if let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        } else {
            NSApp.hide(nil)
        }
    }

    private func activeChanged() {
        let active = NSApp.isActive
        env.setAppActive(active)
        if active {
            env.music.refresh()
            env.brightness.refreshPermission()
            updateMirror()
            scheduleAutoDismiss()
        } else {
            autoDismissToken?.cancel()
            hideMirror()
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissToken?.cancel()
        let delay = env.settings.settings.autoDismissDelay
        guard delay > 0, isSummoned else { return }
        autoDismissToken = MainScheduler.shared.schedule(after: delay) { [weak self] in
            guard let self, self.isSummoned, NSApp.keyWindow == nil || NSApp.keyWindow === self.mirror else { return }
            self.dismiss()
        }
    }

    // MARK: - Mirror

    private func updateMirror() {
        if env.settings.settings.showMirrorWindow && isSummoned { showMirror() } else { hideMirror() }
    }

    private func showMirror() {
        if mirror == nil { mirror = IslandMirrorWindow(env: env) }
        mirror?.present()
    }

    private func hideMirror() {
        mirror?.orderOut(nil)
    }
}

/// Optional on-screen mirror of the island. It's a *preview* (useful on Macs without a Touch
/// Bar, for screenshots, or to see the island while looking at the screen) — never presented
/// as the Touch Bar itself. Off by default on Touch Bar Macs.
final class IslandMirrorWindow: NSWindow {
    private let island: IslandView

    init(env: AppEnvironment) {
        island = IslandView(env: env, role: .mirror)
        let size = NSSize(width: IslandMetrics.defaultAppRegionWidth + 24, height: IslandMetrics.barHeight + 16)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        island.frame = NSRect(x: 12, y: 8, width: IslandMetrics.defaultAppRegionWidth, height: IslandMetrics.barHeight)
        island.autoresizingMask = [.width]
        content.addSubview(island)
        contentView = content
        setAccessibilityLabel("DynamicTouchBar preview")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 6)
        setFrameOrigin(origin)
        orderFrontRegardless()
        makeKey()
    }
}
