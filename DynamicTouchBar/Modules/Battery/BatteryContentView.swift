import AppKit
import Combine

final class BatteryContentView: IslandContentView {
    private let glyph: BatteryGlyphView
    private let percentLabel: NSTextField
    private let statusLabel: NSTextField
    private let detailLabel: NSTextField
    private var currentGlow: NSColor?

    static func color(for info: BatteryInfo, palette: IslandPalette, threshold: Int) -> NSColor {
        if info.isCharging || (info.isPluggedIn && info.level >= 100) { return .systemGreen }
        if info.isLowPowerMode { return .systemYellow }
        if !info.isPluggedIn && info.level <= threshold { return .systemRed }
        return palette.primary
    }

    override init(env: AppEnvironment, palette: IslandPalette) {
        glyph = BatteryGlyphView(outline: palette.secondary)
        percentLabel = IslandLabel.make(font: IslandFont.rounded(14), color: palette.primary)
        statusLabel = IslandLabel.make(font: IslandFont.primary(11, weight: .semibold), color: palette.primary, alignment: .right)
        detailLabel = IslandLabel.make(font: IslandFont.primary(9.5, weight: .regular), color: palette.secondary, alignment: .right)
        super.init(env: env, palette: palette)
        [glyph, percentLabel, statusLabel, detailLabel].forEach(addSubview)
        env.battery.$info
            .sink { [weak self] info in self?.apply(info) }
            .store(in: &cancellables)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { min(maxWidth, 270 * widthScale) }
    override var glowColor: NSColor? { currentGlow }

    private func apply(_ info: BatteryInfo) {
        let color = Self.color(for: info, palette: palette, threshold: env.settings.settings.lowBatteryThreshold)
        glyph.update(level: info.fraction, color: color, charging: info.isCharging, animated: true)
        percentLabel.stringValue = info.hasBattery ? "\(info.level)%" : "AC"
        percentLabel.textColor = color == palette.primary ? palette.primary : color
        if info.isCharging || info.isPluggedIn {
            statusLabel.stringValue = info.isCharging ? "Charging" : (info.level >= 100 || info.isCharged ? "Fully Charged" : "Connected")
            var parts: [String] = []
            if info.isCharging, info.minutesToFull != nil { parts.append(info.statusText) }
            if let watts = info.adapterWatts { parts.append("\(watts) W adapter") }
            detailLabel.stringValue = parts.isEmpty ? "Power adapter" : parts.joined(separator: " · ")
        } else {
            statusLabel.stringValue = info.isLowPowerMode ? "Low Power Mode" : (info.level <= env.settings.settings.lowBatteryThreshold ? "Low Battery" : "On Battery")
            detailLabel.stringValue = info.statusText
        }
        let newGlow: NSColor? = (color == palette.primary) ? nil : color
        if newGlow != currentGlow {
            currentGlow = newGlow
            onLayoutChange?()
        }
        setAccessibilityLabel("Battery \(percentLabel.stringValue), \(statusLabel.stringValue)")
    }

    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: 12, y: (bounds.height - 13) / 2, width: 27, height: 13)
        center(percentLabel, x: glyph.frame.maxX + 7, width: 52)
        let textX = percentLabel.frame.maxX + 4
        stack(statusLabel, detailLabel, x: textX, width: bounds.width - 12 - textX)
    }
}
