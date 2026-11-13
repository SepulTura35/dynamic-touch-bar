import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    private(set) var env: AppEnvironment?
    private var touchBar: TouchBarController?
    private var summon: SummonController?
    private var alwaysOn: AlwaysOnController?
    private var statusItem: StatusItemController?
    private var urlHandler: URLSchemeHandler?
    private var settingsWindow: SettingsWindowController?
    private let hotKeys = HotKeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test host must not register hot keys, touch the Touch Bar or show UI.
        guard !Self.isRunningTests else { return }

        // One island only: a second copy (e.g. a Debug and a Release build both registered for
        // the URL scheme) would fight over the Touch Bar and the hot key.
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != me && !$0.isTerminated }) {
            Log.app.info("Another instance (pid \(other.processIdentifier)) is running — exiting")
            NSApp.terminate(nil)
            return
        }

        let env = AppEnvironment()
        self.env = env
        let summon = SummonController(env: env)
        self.summon = summon
        let touchBar = TouchBarController(env: env)
        self.touchBar = touchBar
        urlHandler = URLSchemeHandler(env: env, summon: summon)

        env.openSettings = { [weak self] in self?.showSettings() }
        env.requestDismiss = { [weak summon] in summon?.dismiss() }

        env.start()
        touchBar.install()
        summon.start()
        let alwaysOn = AlwaysOnController(env: env)
        alwaysOn.start()
        self.alwaysOn = alwaysOn

        let statusItem = StatusItemController(env: env, summon: summon)
        statusItem.install()
        self.statusItem = statusItem

        env.settings.$settings
            .map(\.hotKey)
            .removeDuplicates()
            .sink { [weak self] preset in
                self?.hotKeys.register(preset) { [weak self] in self?.summon?.toggle() }
            }
            .store(in: &cancellables)

        observeSystemEvents()

        if !env.settings.settings.hasCompletedOnboarding {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        alwaysOn?.stop() // remove our Control Strip button so nothing stale is left behind
        summon?.stop()
        env?.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { urlHandler?.handle($0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showSettings() {
        guard let env else { return }
        if settingsWindow == nil { settingsWindow = SettingsWindowController(env: env) }
        settingsWindow?.present()
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.app.info("Did wake — refreshing state and rebuilding Touch Bar")
                self?.env?.handleWake()
                self?.touchBar?.rebuild()
                self?.alwaysOn?.rebuild()
                FrameDriver.shared.resetForDisplayChange()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.env?.music.setResyncDemand(false)
            }
        })
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { _ in FrameDriver.shared.resetForDisplayChange() }
            .store(in: &cancellables)
    }
}
