import AppKit

/// Menu bar entry point: summon, quick timers, settings, quit.
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let env: AppEnvironment
    private let summon: SummonController
    private var statusItem: NSStatusItem?

    init(env: AppEnvironment, summon: SummonController) {
        self.env = env
        self.summon = summon
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "DynamicTouchBar")
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
            button.toolTip = "DynamicTouchBar"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = env.settings.settings
        let shortcut = settings.hotKey == .off ? "" : "  (\(settings.hotKey.title))"
        menu.addItem(item("Show on Touch Bar\(shortcut)", symbol: "rectangle.and.hand.point.up.left.filled") { [weak self] in self?.summon.summon() })
        if !env.hardware.hasTouchBar {
            let note = NSMenuItem(title: "No physical Touch Bar — showing on-screen preview", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        menu.addItem(.separator())

        if settings.isModuleEnabled(.timer) {
            if env.timer.isActive {
                menu.addItem(item("Stop Timer", symbol: "stop.circle") { [weak self] in self?.env.timer.stop() })
            } else {
                menu.addItem(item("Start Pomodoro", symbol: "leaf") { [weak self] in self?.env.timer.startPomodoro(); self?.summon.summon() })
                menu.addItem(item("Start 5-Minute Timer", symbol: "timer") { [weak self] in self?.env.timer.startCountdown(minutes: 5); self?.summon.summon() })
                menu.addItem(item("Start Stopwatch", symbol: "stopwatch") { [weak self] in self?.env.timer.startStopwatch(); self?.summon.summon() })
            }
            menu.addItem(.separator())
        }

        let enabled = item(settings.isEnabled ? "Pause DynamicTouchBar" : "Resume DynamicTouchBar", symbol: settings.isEnabled ? "pause.circle" : "play.circle") { [weak self] in
            self?.env.settings.update { $0.isEnabled.toggle() }
        }
        menu.addItem(enabled)
        let settingsItem = item("Settings…", symbol: "gearshape") { [weak self] in self?.env.openSettings?() }
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DynamicTouchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, symbol: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
