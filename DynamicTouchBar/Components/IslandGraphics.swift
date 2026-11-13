import AppKit

/// Animated playback indicator: rounded bars that dance while playing and settle into dots
/// when paused. It is a stylised activity indicator, not an audio analyser — reading the
/// actual system audio signal would require Screen Recording permission. Animations run on
/// the render server, so they cost the app no CPU.
final class WaveformView: NSView {
    private var bars: [CALayer] = []
    private var color: NSColor
    private(set) var isActive = false
    private let barCount: Int
    private let durations: [CFTimeInterval] = [0.42, 0.58, 0.36, 0.51, 0.47]
    private let peaks: [CGFloat] = [0.75, 1.0, 0.6, 0.9, 0.7]

    init(color: NSColor, barCount: Int = 4) {
        self.color = color
        self.barCount = barCount
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setColor(_ newColor: NSColor) {
        color = newColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        bars.forEach { $0.backgroundColor = newColor.cgColor }
        CATransaction.commit()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        applyAnimations()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let spacing: CGFloat = 2
        let barWidth = max(2, (bounds.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
        for (index, bar) in bars.enumerated() {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (barWidth + spacing) + barWidth / 2, y: bounds.midY)
            bar.cornerRadius = barWidth / 2
        }
        CATransaction.commit()
        applyAnimations()
    }

    private var restScale: CGFloat {
        guard bounds.height > 0 else { return 0.2 }
        let barWidth = bars.first?.bounds.width ?? 2
        return min(1, barWidth / bounds.height)
    }

    private func applyAnimations() {
        let rest = restScale
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "dance")
            if isActive {
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = rest + 0.1
                animation.toValue = peaks[index % peaks.count]
                animation.duration = durations[index % durations.count]
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.timeOffset = Double(index) * 0.17
                bar.add(animation, forKey: "dance")
                bar.transform = CATransform3DMakeScale(1, rest + 0.1, 1)
            } else {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.35)
                bar.transform = CATransform3DMakeScale(1, rest, 1)
                CATransaction.commit()
            }
        }
    }
}

/// Album artwork with rounded corners, a cross-fade on change, and a tasteful placeholder.
final class ArtworkView: NSView {
    private let imageLayer = CALayer()
    private let placeholder = NSImageView()
    private var cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        layer?.addSublayer(imageLayer)
        placeholder.image = Symbol.image("music.note", size: 10, weight: .bold)
        placeholder.contentTintColor = NSColor(white: 1, alpha: 0.6)
        placeholder.imageScaling = .scaleNone
        addSubview(placeholder)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Album artwork")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Placeholder colours follow the theme so the empty state stays visible on light capsules.
    func applyPalette(_ palette: IslandPalette) {
        imageLayer.backgroundColor = palette.controlFill.cgColor
        placeholder.contentTintColor = palette.secondary
    }

    func setImage(_ image: NSImage?, animated: Bool) {
        let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.35
            imageLayer.add(fade, forKey: "contents")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = cgImage
        CATransaction.commit()
        placeholder.isHidden = cgImage != nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.cornerRadius = min(cornerRadius, bounds.height / 2)
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        placeholder.frame = bounds
    }
}

/// Circular progress ring (timer, progress). `indeterminate` spins a partial arc.
final class RingProgressView: NSView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private var lineWidth: CGFloat
    private(set) var progress: Double = 0
    private var isIndeterminate = false

    init(lineWidth: CGFloat = 2.5, color: NSColor, trackColor: NSColor) {
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        wantsLayer = true
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = nil
            shape.lineWidth = lineWidth
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        trackLayer.strokeColor = trackColor.cgColor
        progressLayer.strokeColor = color.cgColor
        progressLayer.strokeEnd = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setColor(_ color: NSColor) {
        progressLayer.strokeColor = color.cgColor
    }

    func setProgress(_ value: Double, animated: Bool) {
        isIndeterminate = false
        progressLayer.removeAnimation(forKey: "spin")
        progress = min(max(value, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.35 : 0)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = CGFloat(progress)
        CATransaction.commit()
        setAccessibilityValue(NSNumber(value: progress))
    }

    func setIndeterminate() {
        guard !isIndeterminate else { return }
        isIndeterminate = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0.28
        CATransaction.commit()
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 0.9
        spin.repeatCount = .infinity
        progressLayer.add(spin, forKey: "spin")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        for shape in [trackLayer, progressLayer] {
            shape.frame = rect
            let inset = lineWidth / 2
            // Start at 12 o'clock and run clockwise.
            let path = CGMutablePath()
            let center = CGPoint(x: side / 2, y: side / 2)
            path.addArc(center: center, radius: side / 2 - inset, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
            shape.path = path
        }
        CATransaction.commit()
        if isIndeterminate {
            isIndeterminate = false
            setIndeterminate()
        }
    }
}

/// Battery glyph drawn with layers so the fill level, colour and charging shimmer animate.
final class BatteryGlyphView: NSView {
    private let body = CALayer()
    private let cap = CALayer()
    private let fill = CALayer()
    private let shimmer = CAGradientLayer()
    private let bolt = NSImageView()
    private var level: Double = 1
    private var color: NSColor = .white
    private var outline: NSColor
    private(set) var isCharging = false

    init(outline: NSColor) {
        self.outline = outline
        super.init(frame: .zero)
        wantsLayer = true
        body.borderWidth = 1.2
        body.borderColor = outline.cgColor
        cap.backgroundColor = outline.cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.masksToBounds = true
        shimmer.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0.55).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.locations = [-0.6, -0.3, 0]
        shimmer.isHidden = true
        fill.addSublayer(shimmer)
        layer?.addSublayer(body)
        layer?.addSublayer(cap)
        body.addSublayer(fill)
        bolt.image = Symbol.image("bolt.fill", size: 8, weight: .black)
        bolt.contentTintColor = .white
        bolt.imageScaling = .scaleNone
        bolt.isHidden = true
        addSubview(bolt)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(level newLevel: Double, color newColor: NSColor, charging: Bool, animated: Bool) {
        level = min(max(newLevel, 0), 1)
        color = newColor
        let chargingChanged = charging != isCharging
        isCharging = charging
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.6)
        fill.backgroundColor = newColor.cgColor
        layoutFill()
        CATransaction.commit()
        if chargingChanged || animated { updateCharging() }
    }

    private func updateCharging() {
        bolt.isHidden = !isCharging
        shimmer.isHidden = !isCharging
        shimmer.removeAnimation(forKey: "sweep")
        bolt.removeAllSymbolEffects()
        guard isCharging else { return }
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.3, 0]
        sweep.toValue = [1, 1.3, 1.6]
        sweep.duration = 1.6
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmer.add(sweep, forKey: "sweep")
        bolt.addSymbolEffect(.pulse, options: .repeating)
    }

    private func layoutFill() {
        let inner = body.bounds.insetBy(dx: 2, dy: 2)
        fill.bounds = CGRect(x: 0, y: 0, width: max(inner.height * 0.5, inner.width * CGFloat(level)), height: inner.height)
        fill.position = CGPoint(x: inner.minX, y: inner.midY)
        fill.cornerRadius = 1.5
        shimmer.frame = CGRect(x: 0, y: 0, width: inner.width, height: inner.height)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let capWidth: CGFloat = 1.8
        let bodyRect = CGRect(x: 0, y: (bounds.height - 11) / 2, width: bounds.width - capWidth - 1, height: 11)
        body.frame = bodyRect
        body.cornerRadius = 3
        cap.frame = CGRect(x: bodyRect.maxX + 1, y: bodyRect.midY - 2, width: capWidth, height: 4)
        cap.cornerRadius = 0.9
        layoutFill()
        CATransaction.commit()
        bolt.frame = bodyRect
    }
}
