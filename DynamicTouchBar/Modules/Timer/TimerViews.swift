import AppKit
import Combine

private func timerTint(_ session: TimerSession?, palette: IslandPalette) -> NSColor {
    switch session?.kind {
    case .pomodoro(let phase, _): phase == .work ? .systemGreen : .systemTeal
    case .focus: .systemIndigo
    case .stopwatch: .systemOrange
    default: .systemOrange
    }
}

final class TimerCompactView: IslandContentView {
    private let ring: RingProgressView
    private let timeLabel: NSTextField

    override init(env: AppEnvironment, palette: IslandPalette) {
        ring = RingProgressView(lineWidth: 2.4, color: timerTint(env.timer.session, palette: palette), trackColor: palette.track)
        timeLabel = IslandLabel.make(font: IslandFont.rounded(12), color: palette.primary, alignment: .right)
        super.init(env: env, palette: palette)
        addSubview(ring)
        addSubview(timeLabel)
        env.timer.$session
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var prefersCompactHeight: Bool { true }
    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { 120 * widthScale }
    override var glowColor: NSColor? { timerTint(env.timer.session, palette: palette) }
    override var tickInterval: TimeInterval? { 1 }

    override func tick() {
        guard let session = env.timer.session else { return }
        let now = env.timer.now
        ring.setColor(timerTint(session, palette: palette))
        ring.setProgress(session.fraction(at: now), animated: true)
        let text = session.displayTime(at: now)
        if timeLabel.stringValue != text { timeLabel.stringValue = text }
        timeLabel.textColor = session.isRunning ? palette.primary : palette.secondary
        setAccessibilityLabel("\(session.label) \(text)")
    }

    override func layout() {
        super.layout()
        ring.frame = NSRect(x: 5, y: (bounds.height - 16) / 2, width: 16, height: 16)
        center(timeLabel, x: ring.frame.maxX + 4, width: bounds.width - ring.frame.maxX - 16)
    }
}

final class TimerExpandedView: IslandContentView {
    private let ring: RingProgressView
    private let kindIcon = NSImageView()
    private let titleLabel: NSTextField
    private let timeLabel: NSTextField
    private let pauseButton: IslandButton
    private let addButton: IslandButton
    private let stopButton: IslandButton

    override init(env: AppEnvironment, palette: IslandPalette) {
        let timer = env.timer
        ring = RingProgressView(lineWidth: 2.6, color: timerTint(timer.session, palette: palette), trackColor: palette.track)
        titleLabel = IslandLabel.make(font: IslandFont.primary(9.5, weight: .medium), color: palette.secondary)
        timeLabel = IslandLabel.make(font: IslandFont.rounded(15), color: palette.primary)
        pauseButton = IslandButton(symbol: "pause.fill", accessibilityLabel: "Pause or resume", style: .prominent, palette: palette,
                                   pointSize: 11, tint: timerTint(timer.session, palette: palette)) { timer.togglePause() }
        addButton = IslandButton(symbol: "plus", title: "1 min", accessibilityLabel: "Add one minute", style: .filled, palette: palette, pointSize: 9) {
            timer.addMinute()
        }
        stopButton = IslandButton(symbol: "xmark", accessibilityLabel: "Stop timer", style: .filled, palette: palette, pointSize: 10) { timer.stop() }
        super.init(env: env, palette: palette)
        kindIcon.imageScaling = .scaleNone
        [ring, kindIcon, titleLabel, timeLabel, pauseButton, addButton, stopButton].forEach(addSubview)
        timer.$session
            .sink { [weak self] session in self?.apply(session) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { min(maxWidth, 330 * widthScale) }
    override var glowColor: NSColor? { timerTint(env.timer.session, palette: palette) }
    override var tickInterval: TimeInterval? { env.timer.session?.isStopwatch == true ? 0.1 : 1 }

    private func apply(_ session: TimerSession?) {
        guard let session else { return }
        let tint = timerTint(session, palette: palette)
        ring.setColor(tint)
        pauseButton.setTint(tint)
        pauseButton.setSymbol(session.isRunning ? "pause.fill" : "play.fill", animated: true)
        kindIcon.image = Symbol.image(session.kind.symbol, size: 9, weight: .bold)
        kindIcon.contentTintColor = tint
        titleLabel.stringValue = session.isRunning ? session.label : "\(session.label) · Paused"
        addButton.isHidden = session.isStopwatch
        updateTicker()
        tick()
        onLayoutChange?()
    }

    override func tick() {
        guard let session = env.timer.session else { return }
        let now = env.timer.now
        ring.setProgress(session.fraction(at: now), animated: !session.isStopwatch)
        let text = session.isStopwatch ? TimeFormat.stopwatch(session.elapsed(at: now)) : session.displayTime(at: now)
        if timeLabel.stringValue != text { timeLabel.stringValue = text }
        setAccessibilityLabel("\(session.label), \(text)")
    }

    override func layout() {
        super.layout()
        let ringSide: CGFloat = 22
        ring.frame = NSRect(x: 4, y: (bounds.height - ringSide) / 2, width: ringSide, height: ringSide)
        kindIcon.frame = ring.frame
        stopButton.frame = NSRect(x: bounds.width - 4 - 26, y: (bounds.height - 22) / 2, width: 26, height: 22)
        var trailing = stopButton.frame.minX - 5
        if !addButton.isHidden {
            let width = addButton.preferredWidth(height: 22)
            addButton.frame = NSRect(x: trailing - width, y: (bounds.height - 22) / 2, width: width, height: 22)
            trailing = addButton.frame.minX - 5
        }
        pauseButton.frame = NSRect(x: trailing - 30, y: (bounds.height - 22) / 2, width: 30, height: 22)
        let textX = ring.frame.maxX + 9
        stack(titleLabel, timeLabel, x: textX, width: pauseButton.frame.minX - 8 - textX, spacing: -1)
    }
}

final class TimerBubbleView: IslandContentView {
    private let ring: RingProgressView

    override init(env: AppEnvironment, palette: IslandPalette) {
        ring = RingProgressView(lineWidth: 2.2, color: timerTint(env.timer.session, palette: palette), trackColor: palette.track)
        super.init(env: env, palette: palette)
        addSubview(ring)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Timer — tap to show")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var tickInterval: TimeInterval? { 1 }

    override func tick() {
        guard let session = env.timer.session else { return }
        ring.setColor(timerTint(session, palette: palette))
        ring.setProgress(session.fraction(at: env.timer.now), animated: true)
    }

    override func layout() {
        super.layout()
        ring.frame = bounds.insetBy(dx: 5, dy: 5)
    }
}
