import AppKit
import Combine

/// Base class for everything that can appear inside the capsule or the bubble.
///
/// Subclasses lay out with frames in `layout()` (precise and cheap), report their preferred
/// width, and get `tick()` callbacks only while they're actually on the Touch Bar.
class IslandContentView: NSView {
    unowned let env: AppEnvironment
    let palette: IslandPalette
    /// Call when preferred width or glow color changes so the capsule re-targets.
    var onLayoutChange: (() -> Void)?
    var cancellables = Set<AnyCancellable>()

    private(set) var isOnScreen = false
    private var ticker: Timer?

    init(env: AppEnvironment, palette: IslandPalette) {
        self.env = env
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    /// Compact content sits in a 24 pt pill; expanded content fills the 30 pt bar.
    var prefersCompactHeight: Bool { false }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat { min(maxWidth, 220) }

    /// Tint for the ambient glow around the capsule, or nil for none.
    var glowColor: NSColor? { nil }

    /// Seconds between `tick()` calls while on screen; nil = no ticking.
    var tickInterval: TimeInterval? { nil }

    func tick() {}

    /// Visible on the physical Touch Bar (or preview) right now.
    func setOnScreen(_ onScreen: Bool) {
        guard onScreen != isOnScreen else { return }
        isOnScreen = onScreen
        updateTicker()
        onScreenChanged()
    }

    func onScreenChanged() {}

    func updateTicker() {
        ticker?.invalidate()
        ticker = nil
        guard isOnScreen, let interval = tickInterval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    override func removeFromSuperview() {
        setOnScreen(false)
        super.removeFromSuperview()
    }

    var widthScale: CGFloat { CGFloat(env.settings.settings.capsuleWidthScale) }

    /// Lays out a label vertically centered at a given x/width.
    func center(_ label: NSTextField, x: CGFloat, width: CGFloat, yOffset: CGFloat = 0) {
        let height = IslandLabel.lineHeight(label.font ?? IslandFont.primary())
        label.frame = NSRect(x: x, y: (bounds.height - height) / 2 + yOffset, width: max(0, width), height: height)
    }

    /// Two stacked labels centered as a block.
    func stack(_ top: NSTextField, _ bottom: NSTextField, x: CGFloat, width: CGFloat, spacing: CGFloat = -1) {
        let topHeight = IslandLabel.lineHeight(top.font ?? IslandFont.primary())
        let bottomHeight = IslandLabel.lineHeight(bottom.font ?? IslandFont.primary())
        let total = topHeight + bottomHeight + spacing
        let originY = (bounds.height - total) / 2
        bottom.frame = NSRect(x: x, y: originY, width: max(0, width), height: bottomHeight)
        top.frame = NSRect(x: x, y: originY + bottomHeight + spacing, width: max(0, width), height: topHeight)
    }
}
