import AppKit
import Combine

/// Resting state: a small pill with the time and a battery glyph.
final class MinimalContentView: IslandContentView {
    private let timeLabel: NSTextField
    private let battery: BatteryGlyphView
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    override init(env: AppEnvironment, palette: IslandPalette) {
        timeLabel = IslandLabel.make(font: IslandFont.rounded(12), color: palette.primary)
        battery = BatteryGlyphView(outline: palette.secondary)
        super.init(env: env, palette: palette)
        addSubview(timeLabel)
        addSubview(battery)
        env.battery.$info
            .sink { [weak self] info in self?.apply(info, animated: true) }
            .store(in: &cancellables)
        apply(env.battery.info, animated: false)
        tick()
        setAccessibilityElement(true)
        setAccessibilityLabel("Dynamic Island")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var prefersCompactHeight: Bool { true }
    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { 128 * widthScale }
    override var tickInterval: TimeInterval? { 2 }

    override func tick() {
        let text = formatter.string(from: Date())
        if timeLabel.stringValue != text { timeLabel.stringValue = text }
    }

    private func apply(_ info: BatteryInfo, animated: Bool) {
        battery.isHidden = !info.hasBattery
        battery.update(level: info.fraction, color: BatteryContentView.color(for: info, palette: palette, threshold: env.settings.settings.lowBatteryThreshold),
                       charging: info.isCharging, animated: animated)
        setAccessibilityValue(info.hasBattery ? "Battery \(info.level)%" : nil)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 12
        center(timeLabel, x: inset, width: 60)
        battery.frame = NSRect(x: bounds.width - inset - 24, y: (bounds.height - 12) / 2, width: 24, height: 12)
    }
}

/// Expanded resting state: clock, quick timers, brightness, volume, custom shortcuts, settings.
final class DashboardContentView: IslandContentView {
    private let timeLabel: NSTextField
    private let dateLabel: NSTextField
    private var groups: [[NSView]] = []
    private var dividers: [CALayer] = []
    private var volumeButton: IslandButton?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    override init(env: AppEnvironment, palette: IslandPalette) {
        timeLabel = IslandLabel.make(font: IslandFont.rounded(13), color: palette.primary)
        dateLabel = IslandLabel.make(font: IslandFont.primary(9.5, weight: .medium), color: palette.secondary)
        super.init(env: env, palette: palette)
        addSubview(timeLabel)
        addSubview(dateLabel)
        buildGroups()
        tick()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildGroups() {
        let settings = env.settings.settings
        let env = self.env

        if settings.isModuleEnabled(.timer) {
            groups.append([
                IslandButton(symbol: "timer", title: "5m", accessibilityLabel: "Start 5 minute timer", style: .filled, palette: palette, pointSize: 10) { env.timer.startCountdown(minutes: 5) },
                IslandButton(symbol: "timer", title: "15m", accessibilityLabel: "Start 15 minute timer", style: .filled, palette: palette, pointSize: 10) { env.timer.startCountdown(minutes: 15) },
                IslandButton(symbol: "leaf.fill", title: "Focus", accessibilityLabel: "Start Pomodoro", style: .filled, palette: palette, pointSize: 10, tint: .systemGreen) { env.timer.startPomodoro() },
                IslandButton(symbol: "stopwatch.fill", accessibilityLabel: "Start stopwatch", style: .filled, palette: palette, pointSize: 11) { env.timer.startStopwatch() },
            ])
        }
        var system: [NSView] = []
        if settings.isModuleEnabled(.brightness) {
            system.append(IslandButton(symbol: "sun.min.fill", accessibilityLabel: "Brightness down", palette: palette, pointSize: 12) {
                env.brightness.step(.down)
                env.coordinator.present(.brightness)
            })
            system.append(IslandButton(symbol: "sun.max.fill", accessibilityLabel: "Brightness up", palette: palette, pointSize: 13) {
                env.brightness.step(.up)
                env.coordinator.present(.brightness)
            })
        }
        if settings.isModuleEnabled(.volume) {
            let button = IslandButton(symbol: VolumeModel.symbol(level: env.volume.volume, muted: env.volume.isMuted),
                                      accessibilityLabel: "Volume", palette: palette, pointSize: 12) {
                env.coordinator.present(.volume)
            }
            volumeButton = button
            system.append(button)
            env.volume.$volume.combineLatest(env.volume.$isMuted)
                .sink { [weak button] level, muted in button?.setSymbol(VolumeModel.symbol(level: level, muted: muted), animated: true) }
                .store(in: &cancellables)
        }
        if !system.isEmpty { groups.append(system) }

        if settings.isModuleEnabled(.shortcuts), !settings.dashboardActions.isEmpty {
            let actions = env.actions.resolve(settings.dashboardActions).prefix(5).map { action in
                IslandButton(symbol: action.symbol, accessibilityLabel: action.title, palette: palette, pointSize: 12) {
                    env.perform(action.ref)
                }
            }
            groups.append(Array(actions))
        }
        groups.append([IslandButton(symbol: "gearshape.fill", accessibilityLabel: "DynamicTouchBar Settings", palette: palette, pointSize: 12) {
            env.openSettings?()
        }])

        for group in groups {
            group.forEach(addSubview)
        }
        for _ in 0..<groups.count {
            let divider = CALayer()
            divider.backgroundColor = palette.tertiary.withAlphaComponent(0.35).cgColor
            layer?.addSublayer(divider)
            dividers.append(divider)
        }
    }

    override var tickInterval: TimeInterval? { 2 }

    override func tick() {
        let now = Date()
        let time = timeFormatter.string(from: now)
        if timeLabel.stringValue != time { timeLabel.stringValue = time }
        let date = dateFormatter.string(from: now)
        if dateLabel.stringValue != date { dateLabel.stringValue = date }
    }

    private let clockWidth: CGFloat = 64
    private let groupSpacing: CGFloat = 13
    private let itemSpacing: CGFloat = 4

    private func width(of view: NSView) -> CGFloat {
        (view as? IslandButton)?.preferredWidth(height: 24) ?? 28
    }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        var total: CGFloat = 12 + clockWidth
        for group in groups {
            total += groupSpacing * 2 + 1
            total += group.map(width(of:)).reduce(0, +) + itemSpacing * CGFloat(max(0, group.count - 1))
        }
        return min(maxWidth, total + 6)
    }

    override func layout() {
        super.layout()
        stack(timeLabel, dateLabel, x: 14, width: clockWidth, spacing: 0)
        var x: CGFloat = 12 + clockWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, group) in groups.enumerated() {
            x += groupSpacing
            dividers[index].frame = CGRect(x: x, y: (bounds.height - 14) / 2, width: 1, height: 14)
            x += 1 + groupSpacing
            for view in group {
                let w = width(of: view)
                let h: CGFloat = (view as? IslandButton) != nil ? 24 : bounds.height
                view.frame = NSRect(x: x, y: (bounds.height - h) / 2, width: w, height: h)
                view.isHidden = view.frame.maxX > bounds.width - 2
                x += w + itemSpacing
            }
            x -= itemSpacing
        }
        CATransaction.commit()
    }
}
