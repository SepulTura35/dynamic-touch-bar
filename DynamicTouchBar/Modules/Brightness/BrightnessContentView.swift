import AppKit
import Combine

/// Brightness steps. The current level is deliberately *not* drawn: macOS exposes no public
/// way to read it on Apple Silicon, and the system's own brightness HUD shows the real value.
final class BrightnessContentView: IslandContentView {
    private let downButton: IslandButton
    private let upButton: IslandButton
    private let icon = NSImageView()
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let allowButton: IslandButton

    override init(env: AppEnvironment, palette: IslandPalette) {
        let brightness = env.brightness
        downButton = IslandButton(symbol: "minus", accessibilityLabel: "Brightness down", style: .filled, palette: palette, pointSize: 11) {
            brightness.step(.down)
        }
        upButton = IslandButton(symbol: "plus", accessibilityLabel: "Brightness up", style: .filled, palette: palette, pointSize: 11) {
            brightness.step(.up)
        }
        allowButton = IslandButton(symbol: "lock.open.fill", title: "Allow", accessibilityLabel: "Allow Accessibility access",
                                   style: .prominent, palette: palette, pointSize: 10) {
            KeyEventPoster.requestTrust()
        }
        titleLabel = IslandLabel.make("Brightness", font: IslandFont.primary(11.5), color: palette.primary)
        detailLabel = IslandLabel.make(font: IslandFont.primary(9.5, weight: .regular), color: palette.secondary)
        super.init(env: env, palette: palette)
        icon.image = Symbol.image("sun.max.fill", size: 14)
        icon.contentTintColor = .systemYellow
        icon.imageScaling = .scaleNone
        [icon, titleLabel, detailLabel, downButton, upButton, allowButton].forEach(addSubview)

        brightness.$canAdjust
            .sink { [weak self] canAdjust in self?.apply(canAdjust: canAdjust) }
            .store(in: &cancellables)
        brightness.$lastDirection
            .compactMap { $0 }
            .sink { [weak self] direction in
                guard let self else { return }
                self.icon.setSymbolImage(Symbol.image(direction == .up ? "sun.max.fill" : "sun.min.fill", size: 14)!, contentTransition: .replace)
                self.icon.addSymbolEffect(.bounce, options: .nonRepeating)
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func onScreenChanged() {
        if isOnScreen { env.brightness.refreshPermission() }
    }

    private func apply(canAdjust: Bool) {
        downButton.isHidden = !canAdjust
        upButton.isHidden = !canAdjust
        allowButton.isHidden = canAdjust
        detailLabel.stringValue = canAdjust ? "Steps like the brightness keys" : "Needs Accessibility access"
        onLayoutChange?()
    }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { min(maxWidth, 290 * widthScale) }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 8, y: (bounds.height - 22) / 2, width: 22, height: 22)
        let trailing: CGFloat
        if allowButton.isHidden {
            upButton.frame = NSRect(x: bounds.width - 6 - 34, y: (bounds.height - 24) / 2, width: 34, height: 24)
            downButton.frame = NSRect(x: upButton.frame.minX - 6 - 34, y: (bounds.height - 24) / 2, width: 34, height: 24)
            trailing = downButton.frame.minX
        } else {
            let width = allowButton.preferredWidth(height: 22)
            allowButton.frame = NSRect(x: bounds.width - 5 - width, y: (bounds.height - 22) / 2, width: width, height: 22)
            trailing = allowButton.frame.minX
        }
        stack(titleLabel, detailLabel, x: icon.frame.maxX + 6, width: trailing - icon.frame.maxX - 12)
    }
}
