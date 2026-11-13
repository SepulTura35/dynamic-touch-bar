import AppKit
import Foundation
import Testing
@testable import DynamicTouchBar

/// Renders every island state through the real `IslandView` at real Touch Bar widths and
/// checks nothing is clipped or overlapping. Set `DTB_SNAPSHOT_DIR` (via
/// `TEST_RUNNER_DTB_SNAPSHOT_DIR=…` on the xcodebuild command line) to also write 2× PNGs.
@MainActor
@Suite("Island rendering", .serialized)
struct RenderingTests {
    /// 685 pt: 13" app region with the collapsed Control Strip (measured on hardware).
    /// 1004 pt: Control Strip hidden. 520 pt: a narrow, defensive case.
    static let widths: [CGFloat] = [685, 1004, 520]

    private static func makeEnvironment(theme: IslandTheme = .dark) -> AppEnvironment {
        let suite = "DynamicTouchBarRenderTests.\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!, key: "s")
        store.update {
            $0.theme = theme
            $0.accent = .blue
            $0.enabledModules = Set(IslandModule.allCases)
            $0.dashboardActions = [.builtIn(.finderDownloads), .builtIn(.openScreenshot)]
            $0.timerSystemNotification = false // never prompt for permissions from tests
        }
        let env = AppEnvironment(settings: store, scheduler: ManualScheduler())
        // Real, read-only system data (no values are changed).
        env.battery.start()
        env.volume.start()
        return env
    }

    private static func seed(_ env: AppEnvironment) -> [String: PresentationContent] {
        // Sample content clearly labelled as test data; it never reaches the real UI.
        env.music.ingest(source: .spotify, value: NowPlaying(
            source: .spotify, trackID: "test", title: "Test Track With A Fairly Long Title", artist: "Test Artist",
            album: "Test Album", duration: 214, position: 71, positionDate: Date(), state: .playing))
        env.timer.startPomodoro()
        env.progress.upsert(id: "test", title: "Building DynamicTouchBar", fraction: 0.62, detail: "Compiling 41 of 66")
        let note = IslandNotification(source: .custom, title: "Deploy finished", subtitle: "All 214 checks passed",
                                      symbol: "checkmark.seal.fill", tint: .systemGreen)
        env.notifications.post(note)
        if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            env.context.contextApp = AppIdentity(bundleID: "com.apple.finder", name: "Finder", processIdentifier: finder.processIdentifier)
        }
        return [
            "01-minimal": .minimal,
            "02-dashboard": .dashboard,
            "03-music-compact": .music(expanded: false),
            "04-music-expanded": .music(expanded: true),
            "05-volume": .volume,
            "06-brightness": .brightness,
            "07-battery": .battery,
            "08-notification": .notification(note.id),
            "09-timer-compact": .timer(expanded: false),
            "10-timer-expanded": .timer(expanded: true),
            "11-progress-compact": .progress(expanded: false),
            "12-progress-expanded": .progress(expanded: true),
            "13-contextual": .contextual,
            "14-clipboard": .clipboard,
        ]
    }

    private static func host(_ island: IslandView, width: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: width, height: 30), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        island.frame = NSRect(x: 0, y: 0, width: width, height: 30)
        window.contentView = island
        island.layoutSubtreeIfNeeded()
        return window
    }

    private static func visibleLeaves(of view: NSView) -> [NSView] {
        view.subviews.filter { !$0.isHidden && $0.alphaValue > 0.01 && !$0.frame.isEmpty }
    }

    private static func checkLayout(_ island: IslandView, name: String, width: CGFloat) {
        let capsule = island.currentCapsuleFrame
        #expect(capsule.minX >= 0 && capsule.maxX <= width, "\(name) @\(width): capsule \(capsule) exceeds bar")
        #expect(capsule.height <= 30.5, "\(name) @\(width): capsule too tall")
        if let bubble = island.currentBubbleFrame {
            #expect(bubble.maxX <= width && bubble.minX >= capsule.maxX, "\(name) @\(width): bubble misplaced")
        }
        guard let content = island.currentContentView else {
            Issue.record("\(name): no content view")
            return
        }
        #expect(abs(content.frame.width - capsule.width) < 1, "\(name) @\(width): content \(content.frame.width) ≠ capsule \(capsule.width)")
        content.layoutSubtreeIfNeeded()
        let leaves = visibleLeaves(of: content)
        for leaf in leaves {
            let frame = leaf.frame
            #expect(frame.minX >= -0.5 && frame.maxX <= content.bounds.width + 0.5 && frame.minY >= -0.5 && frame.maxY <= content.bounds.height + 0.5,
                    "\(name) @\(width): \(type(of: leaf)) \(frame) clipped in \(content.bounds.size)")
        }
        for (i, a) in leaves.enumerated() {
            for b in leaves[(i + 1)...] {
                if let ta = a as? NSTextField, ta.stringValue.isEmpty { continue }
                if let tb = b as? NSTextField, tb.stringValue.isEmpty { continue }
                let overlap = a.frame.intersection(b.frame)
                // Icons may sit on top of their own badge/ring by design (same frame).
                if a.frame == b.frame { continue }
                #expect(overlap.width <= 1 || overlap.height <= 1,
                        "\(name) @\(width): \(type(of: a)) \(a.frame) overlaps \(type(of: b)) \(b.frame)")
            }
        }
    }

    private static func snapshot(_ island: IslandView, to url: URL) {
        let scale: CGFloat = 2
        let size = island.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        island.window?.displayIfNeeded()
        island.layer?.render(in: context)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    @Test(arguments: [IslandTheme.dark, IslandTheme.light])
    func everyStateFitsTheTouchBar(theme: IslandTheme) {
        let env = Self.makeEnvironment(theme: theme)
        let states = Self.seed(env)
        let directory = ProcessInfo.processInfo.environment["DTB_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }

        for width in Self.widths {
            for (name, content) in states.sorted(by: { $0.key < $1.key }) {
                let island = IslandView(env: env, role: .preview)
                let window = Self.host(island, width: width)
                let secondary: LiveActivityKind? = name.hasPrefix("03") ? .timer : nil
                island.render(IslandLayoutState(primary: content, secondary: secondary), animated: false)
                island.layoutSubtreeIfNeeded()
                Self.checkLayout(island, name: name, width: width)
                if let directory, width == 685 {
                    Self.snapshot(island, to: directory.appendingPathComponent("\(theme.rawValue)-\(name).png"))
                }
                window.contentView = nil
                window.close()
            }
        }
        env.stop()
    }

    @Test func animatedTransitionsSettleAndCleanUp() {
        let env = Self.makeEnvironment()
        _ = Self.seed(env)
        let island = IslandView(env: env, role: .preview)
        let window = Self.host(island, width: 685)
        let sequence: [PresentationContent] = [.minimal, .volume, .minimal, .music(expanded: false), .music(expanded: true), .battery, .dashboard]
        for content in sequence {
            island.render(IslandLayoutState(primary: content, secondary: nil), animated: true)
            for _ in 0..<3 { _ = island.advanceFrame(by: 1.0 / 60.0) } // interrupt mid-flight
        }
        var frames = 0
        while island.advanceFrame(by: 1.0 / 60.0) && frames < 600 { frames += 1 }
        #expect(frames < 600, "animation never settled")
        #expect(island.currentContentView is DashboardContentView)
        let remaining = island.subviews.flatMap(\.subviews).filter { $0 is IslandContentView }
        #expect(remaining.count == 1, "departed content views were not removed: \(remaining.map { type(of: $0) })")
        window.close()
        env.stop()
    }
}
