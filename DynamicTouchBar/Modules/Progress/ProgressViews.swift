import AppKit
import Combine

final class ProgressCompactView: IslandContentView {
    private let ring: RingProgressView
    private let label: NSTextField

    override init(env: AppEnvironment, palette: IslandPalette) {
        ring = RingProgressView(lineWidth: 2.4, color: palette.accent, trackColor: palette.track)
        label = IslandLabel.make(font: IslandFont.rounded(11.5), color: palette.primary, alignment: .right)
        super.init(env: env, palette: palette)
        addSubview(ring)
        addSubview(label)
        env.progress.$tasks
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var prefersCompactHeight: Bool { true }
    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { 120 * widthScale }
    override var glowColor: NSColor? { palette.accent }

    private func apply() {
        guard let task = env.progress.primary else { return }
        if let fraction = task.fraction {
            ring.setProgress(fraction, animated: true)
            label.stringValue = "\(Int((fraction * 100).rounded()))%"
        } else {
            ring.setIndeterminate()
            label.stringValue = env.progress.running.count > 1 ? "\(env.progress.running.count) tasks" : "Working"
        }
        setAccessibilityLabel("\(task.title) \(label.stringValue)")
    }

    override func layout() {
        super.layout()
        ring.frame = NSRect(x: 5, y: (bounds.height - 16) / 2, width: 16, height: 16)
        center(label, x: ring.frame.maxX + 4, width: bounds.width - ring.frame.maxX - 16)
    }
}

final class ProgressExpandedView: IslandContentView {
    private let icon = NSImageView()
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let bar: IslandSlider
    private let percentLabel: NSTextField
    private let ring: RingProgressView

    override init(env: AppEnvironment, palette: IslandPalette) {
        titleLabel = IslandLabel.make(font: IslandFont.primary(11), color: palette.primary)
        detailLabel = IslandLabel.make(font: IslandFont.primary(9.5, weight: .regular), color: palette.secondary)
        bar = IslandSlider(palette: palette, fillColor: palette.accent, thickness: 5, activeThickness: 5, accessibilityLabel: "Progress")
        percentLabel = IslandLabel.make(font: IslandFont.digits(11), color: palette.secondary, alignment: .right)
        ring = RingProgressView(lineWidth: 2.4, color: palette.accent, trackColor: palette.track)
        super.init(env: env, palette: palette)
        icon.imageScaling = .scaleNone
        icon.contentTintColor = palette.accent
        [icon, titleLabel, detailLabel, bar, percentLabel, ring].forEach(addSubview)
        env.progress.$tasks
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { min(maxWidth, 430 * widthScale) }
    override var glowColor: NSColor? { palette.accent }

    private func apply() {
        guard let task = env.progress.primary else { return }
        icon.image = Symbol.image(task.symbol, size: 14)
        titleLabel.stringValue = task.title
        let others = env.progress.running.count - 1
        detailLabel.stringValue = [task.detail, others > 0 ? "+\(others) more" : nil].compactMap { $0 }.joined(separator: " · ")
        if let fraction = task.fraction {
            bar.isHidden = false
            ring.isHidden = true
            bar.setValue(fraction, animated: true)
            percentLabel.stringValue = "\(Int((fraction * 100).rounded()))%"
        } else {
            bar.isHidden = true
            ring.isHidden = false
            ring.setIndeterminate()
            percentLabel.stringValue = ""
        }
        setAccessibilityLabel("\(task.title) \(percentLabel.stringValue)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 6, y: (bounds.height - 22) / 2, width: 22, height: 22)
        percentLabel.frame.size.width = 40
        center(percentLabel, x: bounds.width - 12 - 40, width: 40)
        let barWidth: CGFloat = min(150, bounds.width * 0.36)
        let barX = percentLabel.frame.minX - 8 - barWidth
        bar.frame = NSRect(x: barX, y: 0, width: barWidth, height: bounds.height)
        ring.frame = NSRect(x: bounds.width - 12 - 18, y: (bounds.height - 18) / 2, width: 18, height: 18)
        let textX = icon.frame.maxX + 8
        let textTrailing = bar.isHidden ? ring.frame.minX - 8 : barX - 10
        stack(titleLabel, detailLabel, x: textX, width: textTrailing - textX)
    }
}

final class ProgressBubbleView: IslandContentView {
    private let ring: RingProgressView

    override init(env: AppEnvironment, palette: IslandPalette) {
        ring = RingProgressView(lineWidth: 2.2, color: palette.accent, trackColor: palette.track)
        super.init(env: env, palette: palette)
        addSubview(ring)
        env.progress.$tasks
            .sink { [weak self] _ in
                guard let self, let task = self.env.progress.primary else { return }
                if let fraction = task.fraction { self.ring.setProgress(fraction, animated: true) } else { self.ring.setIndeterminate() }
            }
            .store(in: &cancellables)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Progress — tap to show")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        ring.frame = bounds.insetBy(dx: 5, dy: 5)
    }
}
