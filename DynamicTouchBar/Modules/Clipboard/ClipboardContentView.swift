import AppKit

final class ClipboardContentView: IslandContentView {
    private let badge = CALayer()
    private let icon = NSImageView()
    private let titleLabel: NSTextField
    private let previewLabel: NSTextField
    private var buttons: [IslandButton] = []

    override init(env: AppEnvironment, palette: IslandPalette) {
        let item = env.clipboard.latest
        titleLabel = IslandLabel.make(item?.title ?? "Copied", font: IslandFont.primary(11), color: palette.primary)
        previewLabel = IslandLabel.make(item?.preview ?? "", font: IslandFont.primary(10, weight: .regular), color: palette.secondary)
        super.init(env: env, palette: palette)
        badge.backgroundColor = palette.controlFill.cgColor
        layer?.addSublayer(badge)
        icon.image = Symbol.image(item?.symbol ?? "doc.on.clipboard", size: 11, weight: .bold)
        icon.contentTintColor = palette.primary
        icon.imageScaling = .scaleNone
        [icon, titleLabel, previewLabel].forEach(addSubview)

        let clipboard = env.clipboard
        if clipboard.canOpen {
            buttons.append(IslandButton(symbol: "safari", title: "Open", style: .filled, palette: palette, pointSize: 10) { clipboard.openLink() })
        }
        if clipboard.canMakePlain {
            buttons.append(IslandButton(symbol: "textformat", title: "Plain", accessibilityLabel: "Convert to plain text", style: .filled, palette: palette, pointSize: 10) {
                clipboard.makePlainText()
            })
        }
        buttons.append(IslandButton(symbol: "xmark", accessibilityLabel: "Clear clipboard", style: .filled, palette: palette, pointSize: 10) {
            clipboard.clearPasteboard()
            env.coordinator.dismissTransient()
        })
        buttons.forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityLabel("\(titleLabel.stringValue): \(previewLabel.stringValue)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let text = max(IslandLabel.width(of: titleLabel.stringValue, font: titleLabel.font!),
                       IslandLabel.width(of: previewLabel.stringValue, font: previewLabel.font!))
        let actions = buttons.map { $0.preferredWidth(height: 22) + 5 }.reduce(0, +)
        return min(maxWidth, max(260, 3 + 24 + 9 + min(text, 260) + 12 + actions + 4))
    }

    override func onScreenChanged() {
        if isOnScreen { icon.addSymbolEffect(.bounce, options: .nonRepeating) }
    }

    override func layout() {
        super.layout()
        let iconFrame = NSRect(x: 3, y: (bounds.height - 24) / 2, width: 24, height: 24)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badge.frame = iconFrame
        badge.cornerRadius = 12
        CATransaction.commit()
        icon.frame = iconFrame
        var x = bounds.width - 4
        for button in buttons.reversed() {
            let width = button.preferredWidth(height: 22)
            x -= width
            button.frame = NSRect(x: x, y: (bounds.height - 22) / 2, width: width, height: 22)
            x -= 5
        }
        let textX = iconFrame.maxX + 9
        if previewLabel.stringValue.isEmpty {
            previewLabel.isHidden = true
            center(titleLabel, x: textX, width: x - 7 - textX)
        } else {
            stack(titleLabel, previewLabel, x: textX, width: x - 7 - textX)
        }
    }
}
