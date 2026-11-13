import AppKit

/// Controls inside the island receive touches through the island's single gesture
/// recognizer (see `IslandView`), which works identically for Touch Bar touches and mouse
/// clicks in the on-screen preview. Points are in the control's own coordinate space.
protocol IslandInteractive: NSView {
    func trackingBegan(at point: NSPoint)
    func trackingMoved(to point: NSPoint)
    func trackingEnded(at point: NSPoint, cancelled: Bool)
}

/// Shared helpers for building labels.
enum IslandLabel {
    static func make(_ text: String = "", font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.setAccessibilityElement(false)
        return label
    }

    /// Single-line height for a font, so manual layout centers glyphs precisely.
    static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static func width(of text: String, font: NSFont) -> CGFloat {
        // + NSTextField's internal cell padding (2 pt each side) and a little slack.
        ceil((text as NSString).size(withAttributes: [.font: font]).width) + 6
    }
}

/// Icon (+ optional title) button with a soft press highlight and a symbol bounce.
final class IslandButton: NSView, IslandInteractive {
    enum Style { case plain, filled, prominent }

    var action: () -> Void
    private let style: Style
    private var palette: IslandPalette
    private let imageView = NSImageView()
    private let titleLabel: NSTextField?
    private let highlight = CALayer()
    private let pointSize: CGFloat
    private var symbolName: String
    private var tint: NSColor?
    private var isPressed = false { didSet { updateHighlight() } }

    init(symbol: String, title: String? = nil, accessibilityLabel: String? = nil, style: Style = .plain,
         palette: IslandPalette, pointSize: CGFloat = 13, tint: NSColor? = nil, action: @escaping () -> Void) {
        self.action = action
        self.style = style
        self.palette = palette
        self.pointSize = pointSize
        self.symbolName = symbol
        self.tint = tint
        self.titleLabel = title.map { IslandLabel.make($0, font: IslandFont.primary(11, weight: .medium), color: palette.primary) }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(highlight)
        highlight.backgroundColor = backgroundColor.cgColor
        imageView.image = Symbol.image(symbol, size: pointSize)
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = foregroundColor
        addSubview(imageView)
        if let titleLabel {
            titleLabel.textColor = foregroundColor
            addSubview(titleLabel)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel ?? title ?? symbol)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    private var foregroundColor: NSColor {
        switch style {
        case .prominent: palette.onAccent(tint ?? palette.accent)
        default: tint ?? palette.primary
        }
    }

    private var backgroundColor: NSColor {
        switch style {
        case .plain: .clear
        case .filled: palette.controlFill
        case .prominent: tint ?? palette.accent
        }
    }

    /// Preferred width for a given height.
    func preferredWidth(height: CGFloat) -> CGFloat {
        guard let titleLabel else { return max(height, 28) }
        let textWidth = IslandLabel.width(of: titleLabel.stringValue, font: titleLabel.font ?? IslandFont.primary(11))
        // Matches layout(): 8 leading + icon (pointSize + 8) + 1 gap + text + 8 trailing.
        return 8 + (pointSize + 8) + 1 + textWidth + 8
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let inset: CGFloat = style == .plain ? 1 : 0
        highlight.frame = bounds.insetBy(dx: inset, dy: inset)
        highlight.cornerRadius = highlight.frame.height / 2
        CATransaction.commit()

        let iconSide = pointSize + 8
        if let titleLabel {
            let iconX: CGFloat = 8
            imageView.frame = NSRect(x: iconX, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
            let font = titleLabel.font ?? IslandFont.primary(11)
            let lineHeight = IslandLabel.lineHeight(font)
            let textX = imageView.frame.maxX + 1
            titleLabel.frame = NSRect(x: textX, y: (bounds.height - lineHeight) / 2, width: max(0, bounds.width - textX - 8), height: lineHeight)
        } else {
            imageView.frame = NSRect(x: (bounds.width - iconSide) / 2, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        }
    }

    func setSymbol(_ name: String, animated: Bool) {
        guard name != symbolName else { return }
        symbolName = name
        guard let image = Symbol.image(name, size: pointSize) else { return }
        if animated {
            imageView.setSymbolImage(image, contentTransition: .replace.downUp)
        } else {
            imageView.image = image
        }
    }

    func setTint(_ color: NSColor?) {
        tint = color
        imageView.contentTintColor = foregroundColor
        titleLabel?.textColor = foregroundColor
        updateHighlight()
    }

    func setTitle(_ title: String) {
        titleLabel?.stringValue = title
        setAccessibilityLabel(title)
        needsLayout = true
    }

    var isEnabled = true {
        didSet { alphaValue = isEnabled ? 1 : 0.35 }
    }

    private func updateHighlight() {
        let color = isPressed ? (style == .prominent ? backgroundColor.blended(withFraction: 0.25, of: .white) ?? backgroundColor : palette.controlPressed) : backgroundColor
        highlight.backgroundColor = color.cgColor
        let scale: CGFloat = isPressed ? 0.92 : 1
        highlight.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: IslandInteractive

    func trackingBegan(at point: NSPoint) {
        guard isEnabled else { return }
        isPressed = true
    }

    func trackingMoved(to point: NSPoint) {
        guard isEnabled else { return }
        isPressed = bounds.insetBy(dx: -12, dy: -12).contains(point)
    }

    func trackingEnded(at point: NSPoint, cancelled: Bool) {
        let inside = bounds.insetBy(dx: -12, dy: -12).contains(point)
        isPressed = false
        guard isEnabled, !cancelled, inside else { return }
        imageView.addSymbolEffect(.bounce.down, options: .nonRepeating)
        action()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        action()
        return true
    }
}

/// Horizontal level/scrub control. Drag anywhere on it to set the value (absolute mapping,
/// like the iOS volume island). The bar thickens while touched.
final class IslandSlider: NSView, IslandInteractive {
    var onChange: ((Double, _ isFinal: Bool) -> Void)?
    private(set) var value: Double = 0
    private(set) var isTracking = false

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var palette: IslandPalette
    private var fillColor: NSColor
    private let thickness: CGFloat
    private let activeThickness: CGFloat
    private var linearEnd: (value: Double, duration: TimeInterval)?

    init(palette: IslandPalette, fillColor: NSColor? = nil, thickness: CGFloat = 5, activeThickness: CGFloat = 8, accessibilityLabel: String) {
        self.palette = palette
        self.fillColor = fillColor ?? palette.primary
        self.thickness = thickness
        self.activeThickness = activeThickness
        super.init(frame: .zero)
        wantsLayer = true
        trackLayer.backgroundColor = palette.track.cgColor
        fillLayer.backgroundColor = self.fillColor.cgColor
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(trackLayer)
        trackLayer.addSublayer(fillLayer)
        trackLayer.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setFillColor(_ color: NSColor) {
        fillColor = color
        fillLayer.backgroundColor = color.cgColor
    }

    /// Sets the value. While the user is dragging, external updates are ignored.
    func setValue(_ newValue: Double, animated: Bool) {
        guard !isTracking else { return }
        linearEnd = nil
        value = min(max(newValue, 0), 1)
        fillLayer.removeAnimation(forKey: "linear")
        applyFill(animated: animated)
        setAccessibilityValue(NSNumber(value: value))
    }

    /// Advances the fill linearly to `endValue` over `duration` entirely on the render server
    /// (used for playback progress: zero CPU between label refreshes).
    func setValue(_ newValue: Double, advancingTo endValue: Double, over duration: TimeInterval) {
        guard !isTracking else { return }
        value = min(max(newValue, 0), 1)
        guard duration > 0.05, endValue > value else {
            setValue(newValue, animated: false)
            return
        }
        linearEnd = (endValue, duration)
        startLinearAnimation()
    }

    private func startLinearAnimation() {
        guard let linearEnd else { return }
        let fromWidth = width(for: value)
        let toWidth = width(for: linearEnd.value)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.bounds.size.width = toWidth
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = fromWidth
        animation.toValue = toWidth
        animation.duration = linearEnd.duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        fillLayer.add(animation, forKey: "linear")
    }

    private func width(for fraction: Double) -> CGFloat {
        trackLayer.bounds.width * CGFloat(min(max(fraction, 0), 1))
    }

    private func applyFill(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.22 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let height = trackLayer.bounds.height
        fillLayer.bounds = CGRect(x: 0, y: 0, width: width(for: value), height: height)
        fillLayer.position = CGPoint(x: 0, y: height / 2)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        layoutTrack(animated: false)
    }

    private func layoutTrack(animated: Bool) {
        let barHeight = isTracking ? activeThickness : thickness
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.18)
        trackLayer.frame = CGRect(x: 0, y: (bounds.height - barHeight) / 2, width: bounds.width, height: barHeight)
        trackLayer.cornerRadius = barHeight / 2
        CATransaction.commit()
        fillLayer.removeAnimation(forKey: "linear")
        applyFill(animated: false)
        if linearEnd != nil && !isTracking { startLinearAnimation() }
    }

    private func valueAt(_ point: NSPoint) -> Double {
        guard bounds.width > 0 else { return 0 }
        return Double(min(max(point.x / bounds.width, 0), 1))
    }

    // MARK: IslandInteractive

    func trackingBegan(at point: NSPoint) {
        isTracking = true
        linearEnd = nil
        fillLayer.removeAnimation(forKey: "linear")
        layoutTrack(animated: true)
        value = valueAt(point)
        applyFill(animated: false)
        onChange?(value, false)
    }

    func trackingMoved(to point: NSPoint) {
        guard isTracking else { return }
        value = valueAt(point)
        applyFill(animated: false)
        onChange?(value, false)
    }

    func trackingEnded(at point: NSPoint, cancelled: Bool) {
        guard isTracking else { return }
        if !cancelled { value = valueAt(point) }
        isTracking = false
        layoutTrack(animated: true)
        setAccessibilityValue(NSNumber(value: value))
        onChange?(value, true)
    }

    override func accessibilityPerformIncrement() -> Bool {
        value = min(1, value + 0.0625)
        applyFill(animated: true)
        onChange?(value, true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        value = max(0, value - 0.0625)
        applyFill(animated: true)
        onChange?(value, true)
        return true
    }
}
