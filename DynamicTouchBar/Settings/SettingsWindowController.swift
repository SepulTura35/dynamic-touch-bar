import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let env: AppEnvironment
    private var window: NSWindow?

    init(env: AppEnvironment) {
        self.env = env
        super.init()
    }

    func present() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(env: env, store: env.settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "DynamicTouchBar"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 940, height: 660))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("DynamicTouchBarSettings")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !env.settings.settings.hasCompletedOnboarding {
            env.settings.update { $0.hasCompletedOnboarding = true }
        }
    }
}
