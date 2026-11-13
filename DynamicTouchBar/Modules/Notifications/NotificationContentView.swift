import AppKit

final class NotificationContentView: IslandContentView {
    private let notification: IslandNotification?
    private let badge = CALayer()
    private let icon = NSImageView()
    private let artwork = ArtworkView(cornerRadius: 6)
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private var actionButton: IslandButton?

    init(env: AppEnvironment, palette: IslandPalette, id: UUID) {
        notification = env.notifications.notification(id)
        titleLabel = IslandLabel.make(notification?.title ?? "", font: IslandFont.primary(11.5), color: palette.primary)
        subtitleLabel = IslandLabel.make(notification?.subtitle ?? "", font: IslandFont.primary(10, weight: .regular), color: palette.secondary)
        super.init(env: env, palette: palette)
        let tint = notification?.tint ?? palette.accent
        badge.backgroundColor = tint.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(badge)
        icon.image = Symbol.image(notification?.symbol ?? "bell.fill", size: 12, weight: .bold)
        icon.contentTintColor = ColorExtraction.legible(tint)
        icon.imageScaling = .scaleNone
        addSubview(icon)
        if let image = notification?.image {
            artwork.setImage(image, animated: false)
            addSubview(artwork)
            badge.isHidden = true
            icon.isHidden = true
        }
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        subtitleLabel.isHidden = (notification?.subtitle ?? "").isEmpty
        if let action = notification?.action {
            let button = IslandButton(symbol: action.symbol, title: action.title, style: .prominent, palette: palette,
                                      pointSize: 10, tint: tint) { [weak env] in
                action.handler()
                env?.coordinator.dismissTransient()
            }
            actionButton = button
            addSubview(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([notification?.title, notification?.subtitle].compactMap { $0 }.joined(separator: ". "))
    }

    override init(env: AppEnvironment, palette: IslandPalette) { fatalError("Use init(env:palette:id:)") }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var glowColor: NSColor? { notification?.tint }

    override func onScreenChanged() {
        if isOnScreen { icon.addSymbolEffect(.bounce, options: .nonRepeating) }
    }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let titleWidth = IslandLabel.width(of: titleLabel.stringValue, font: titleLabel.font!)
        let subtitleWidth = subtitleLabel.isHidden ? 0 : IslandLabel.width(of: subtitleLabel.stringValue, font: subtitleLabel.font!)
        let actionWidth = actionButton.map { $0.preferredWidth(height: 22) + 8 } ?? 0
        let width = 3 + 24 + 9 + max(titleWidth, subtitleWidth) + 14 + actionWidth
        return min(maxWidth, max(220 * widthScale, width))
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 24
        let iconFrame = NSRect(x: 3, y: (bounds.height - side) / 2, width: side, height: side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badge.frame = iconFrame
        badge.cornerRadius = side / 2
        CATransaction.commit()
        icon.frame = iconFrame
        artwork.frame = iconFrame
        var trailing = bounds.width - 12
        if let actionButton {
            let width = actionButton.preferredWidth(height: 22)
            actionButton.frame = NSRect(x: bounds.width - 4 - width, y: (bounds.height - 22) / 2, width: width, height: 22)
            trailing = actionButton.frame.minX - 8
        }
        let textX = iconFrame.maxX + 9
        if subtitleLabel.isHidden {
            center(titleLabel, x: textX, width: trailing - textX)
        } else {
            stack(titleLabel, subtitleLabel, x: textX, width: trailing - textX)
        }
    }
}
