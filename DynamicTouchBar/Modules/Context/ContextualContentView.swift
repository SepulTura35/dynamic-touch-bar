import AppKit
import Combine

/// App-specific quick actions for the app the island was summoned from.
final class ContextualContentView: IslandContentView {
    private let appIcon = NSImageView()
    private let nameLabel: NSTextField
    private let divider = CALayer()
    private var buttons: [IslandButton] = []

    override init(env: AppEnvironment, palette: IslandPalette) {
        nameLabel = IslandLabel.make(font: IslandFont.primary(11), color: palette.primary)
        super.init(env: env, palette: palette)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(appIcon)
        addSubview(nameLabel)
        divider.backgroundColor = palette.tertiary.withAlphaComponent(0.35).cgColor
        layer?.addSublayer(divider)
        env.context.$contextApp
            .sink { [weak self] app in self?.rebuild(for: app) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func rebuild(for app: AppIdentity?) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        appIcon.image = app?.icon
        nameLabel.stringValue = app?.name ?? ""
        let profile = env.settings.settings.profile(for: app?.bundleID)
        let env = self.env
        for action in env.actions.resolve(profile?.actions ?? []) {
            let button = IslandButton(symbol: action.symbol, title: action.title, style: .filled, palette: palette, pointSize: 10) {
                env.perform(action.ref)
            }
            buttons.append(button)
            addSubview(button)
        }
        setAccessibilityElement(false)
        onLayoutChange?()
        needsLayout = true
    }

    private var headerWidth: CGFloat {
        min(110, IslandLabel.width(of: nameLabel.stringValue, font: nameLabel.font!)) + 4 + 20 + 7
    }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let buttonsWidth = buttons.map { $0.preferredWidth(height: 22) }.reduce(0, +) + CGFloat(max(0, buttons.count - 1)) * 5
        return min(maxWidth, headerWidth + 12 + 1 + 12 + buttonsWidth + 5)
    }

    override func layout() {
        super.layout()
        appIcon.frame = NSRect(x: 6, y: (bounds.height - 20) / 2, width: 20, height: 20)
        let nameWidth = min(110, IslandLabel.width(of: nameLabel.stringValue, font: nameLabel.font!))
        center(nameLabel, x: appIcon.frame.maxX + 7, width: nameWidth)
        var x = nameLabel.frame.maxX + 12
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        divider.frame = CGRect(x: x, y: (bounds.height - 14) / 2, width: 1, height: 14)
        CATransaction.commit()
        x += 13
        for button in buttons {
            let width = button.preferredWidth(height: 22)
            button.frame = NSRect(x: x, y: (bounds.height - 22) / 2, width: width, height: 22)
            button.isHidden = button.frame.maxX > bounds.width - 3
            x += width + 5
        }
    }
}
