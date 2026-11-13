import AppKit
import QuartzCore

/// Anything that animates per frame.
protocol FrameDriven: AnyObject {
    /// Advance by `dt` seconds. Return `false` once settled — the client is then detached.
    func advanceFrame(by dt: Double) -> Bool
}

/// Single shared display-link driver. It runs **only** while at least one client is animating,
/// so an idle island costs zero CPU. Falls back to a timer if no screen is available
/// (e.g. lid closed with no external display).
final class FrameDriver: NSObject {
    static let shared = FrameDriver()

    private final class WeakClient {
        weak var value: FrameDriven?
        init(_ value: FrameDriven) { self.value = value }
    }

    private var clients: [ObjectIdentifier: WeakClient] = [:]
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var lastTimestamp: CFTimeInterval?

    var isRunning: Bool { displayLink != nil || fallbackTimer != nil }

    func start(_ client: FrameDriven) {
        clients[ObjectIdentifier(client)] = WeakClient(client)
        startIfNeeded()
    }

    func stop(_ client: FrameDriven) {
        clients[ObjectIdentifier(client)] = nil
        if clients.isEmpty { stopLink() }
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        lastTimestamp = nil
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let link = screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(timestamp: CACurrentMediaTime()) }
            }
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
        }
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        lastTimestamp = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        tick(timestamp: link.timestamp)
    }

    private func tick(timestamp: CFTimeInterval) {
        // First frame after (re)starting advances by one nominal frame so motion starts immediately.
        let dt = lastTimestamp.map { min(max(timestamp - $0, 0), 0.25) } ?? (1.0 / 60.0)
        lastTimestamp = timestamp

        for (key, weakClient) in clients {
            guard let client = weakClient.value else {
                clients[key] = nil
                continue
            }
            if !client.advanceFrame(by: dt) {
                clients[key] = nil
            }
        }
        if clients.isEmpty { stopLink() }
    }

    /// Call after sleep/wake or display changes: the link is re-created on the current main screen.
    func resetForDisplayChange() {
        let wasRunning = isRunning
        stopLink()
        if wasRunning && !clients.isEmpty { startIfNeeded() }
    }
}
