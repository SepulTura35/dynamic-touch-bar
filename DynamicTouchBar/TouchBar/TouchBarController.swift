import AppKit

/// Installs the island on the physical Touch Bar with public `NSTouchBar` APIs.
///
/// The bar is attached to `NSApp` (the end of the responder chain), so it shows whenever
/// DynamicTouchBar is the active app — with or without a window — and also while the Settings
/// window is open. macOS only shows an app's Touch Bar while that app is frontmost; there is
/// no public API to show it on top of other apps.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let islandIdentifier = NSTouchBarItem.Identifier("com.dynamictouchbar.island")

    private unowned let env: AppEnvironment
    private(set) weak var container: TouchBarIslandContainer?

    init(env: AppEnvironment) {
        self.env = env
        super.init()
    }

    func install() {
        NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = false
        NSApp.touchBar = makeTouchBar()
    }

    /// Throws away and recreates the bar (after wake, or if the Touch Bar server restarted).
    func rebuild() {
        NSApp.touchBar = nil
        install()
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.islandIdentifier]
        bar.principalItemIdentifier = Self.islandIdentifier
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.islandIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let island = IslandView(env: env, role: .touchBar)
        let container = TouchBarIslandContainer(island: island)
        item.view = container
        item.customizationLabel = "Dynamic Island"
        item.visibilityPriority = .high
        self.container = container
        Log.touchBar.info("Touch Bar island item created")
        return item
    }
}

/// Hosts the island in the Touch Bar and sizes it to the real app region.
///
/// Measured on a 13-inch M1 MacBook Pro: the Touch Bar does **not** compress an over-wide
/// custom item, but the item's host window reports the true app-region width (685 pt with the
/// collapsed Control Strip). So we track that window's width instead of guessing.
final class TouchBarIslandContainer: NSView {
    let island: IslandView
    private var widthConstraint: NSLayoutConstraint!
    private var resizeObserver: NSObjectProtocol?

    init(island: IslandView) {
        self.island = island
        super.init(frame: NSRect(x: 0, y: 0, width: IslandMetrics.defaultAppRegionWidth, height: IslandMetrics.barHeight))
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: IslandMetrics.defaultAppRegionWidth)
        widthConstraint.isActive = true
        island.frame = bounds
        island.autoresizingMask = [.width, .height]
        addSubview(island)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        guard let window else { return }
        matchWidth(of: window)
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.matchWidth(of: window) }
        }
    }

    private func matchWidth(of window: NSWindow) {
        // The host window briefly reports a placeholder width while it is being set up
        // (seen as 200 pt before 1004 pt on reveal); ignore those so the island doesn't jump.
        guard window.frame.width >= 300 else { return }
        let width = floor(window.frame.width)
        guard abs(widthConstraint.constant - width) > 0.5 else { return }
        widthConstraint.constant = width
        Log.touchBar.info("Touch Bar app region: \(Int(width)) pt")
    }
}
