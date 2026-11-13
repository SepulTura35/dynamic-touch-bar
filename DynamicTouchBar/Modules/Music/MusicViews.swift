import AppKit
import Combine

private func musicTint(_ env: AppEnvironment, palette: IslandPalette) -> NSColor {
    if env.settings.settings.tintFromArtwork, let tint = env.music.tint { return tint }
    return palette.accent
}

/// Compact live activity: tiny artwork on the leading edge, waveform on the trailing edge.
final class MusicCompactView: IslandContentView {
    private let artwork = ArtworkView(cornerRadius: 5)
    private let waveform: WaveformView

    override init(env: AppEnvironment, palette: IslandPalette) {
        waveform = WaveformView(color: musicTint(env, palette: palette))
        super.init(env: env, palette: palette)
        artwork.applyPalette(palette)
        addSubview(artwork)
        addSubview(waveform)
        env.music.$displayImage
            .sink { [weak self] image in self?.artwork.setImage(image, animated: true) }
            .store(in: &cancellables)
        env.music.$tint
            .sink { [weak self] _ in
                guard let self else { return }
                self.waveform.setColor(musicTint(self.env, palette: self.palette))
                self.onLayoutChange?()
            }
            .store(in: &cancellables)
        env.music.$display
            .sink { [weak self] value in
                self?.waveform.setActive(value?.isPlaying ?? false)
                self?.setAccessibilityLabel(value.map { "Now playing: \($0.title), \($0.subtitle)" } ?? "Music")
            }
            .store(in: &cancellables)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var prefersCompactHeight: Bool { true }
    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { 168 * widthScale }
    override var glowColor: NSColor? { musicTint(env, palette: palette) }

    override func layout() {
        super.layout()
        let side = bounds.height - 6
        artwork.frame = NSRect(x: 4, y: 3, width: side, height: side)
        waveform.frame = NSRect(x: bounds.width - 10 - 15, y: (bounds.height - 11) / 2, width: 15, height: 11)
    }
}

/// Full player: artwork, title/artist, scrubbable progress with times, transport, waveform.
final class MusicExpandedView: IslandContentView {
    private let artwork = ArtworkView(cornerRadius: 6)
    private let titleLabel: NSTextField
    private let artistLabel: NSTextField
    private let elapsedLabel: NSTextField
    private let remainingLabel: NSTextField
    private let progress: IslandSlider
    private let previousButton: IslandButton
    private let playButton: IslandButton
    private let nextButton: IslandButton
    private let waveform: WaveformView
    private var showsProgress = true
    private var scrubFraction: Double?

    override init(env: AppEnvironment, palette: IslandPalette) {
        titleLabel = IslandLabel.make(font: IslandFont.primary(11.5, weight: .semibold), color: palette.primary)
        artistLabel = IslandLabel.make(font: IslandFont.primary(10, weight: .regular), color: palette.secondary)
        elapsedLabel = IslandLabel.make(font: IslandFont.digits(9.5, weight: .medium), color: palette.secondary, alignment: .right)
        remainingLabel = IslandLabel.make(font: IslandFont.digits(9.5, weight: .medium), color: palette.secondary)
        progress = IslandSlider(palette: palette, thickness: 4, activeThickness: 7, accessibilityLabel: "Playback position")
        let music = env.music
        previousButton = IslandButton(symbol: "backward.fill", accessibilityLabel: "Previous track", palette: palette, pointSize: 12) { music.previousTrack() }
        playButton = IslandButton(symbol: "play.fill", accessibilityLabel: "Play or pause", palette: palette, pointSize: 15) { music.playPause() }
        nextButton = IslandButton(symbol: "forward.fill", accessibilityLabel: "Next track", palette: palette, pointSize: 12) { music.nextTrack() }
        waveform = WaveformView(color: musicTint(env, palette: palette))
        super.init(env: env, palette: palette)
        artwork.applyPalette(palette)

        [artwork, titleLabel, artistLabel, elapsedLabel, progress, remainingLabel, previousButton, playButton, nextButton, waveform].forEach(addSubview)

        progress.onChange = { [weak self] fraction, isFinal in
            guard let self else { return }
            self.scrubFraction = isFinal ? nil : fraction
            if isFinal { self.env.music.seek(toFraction: fraction) }
            self.updateTimes()
        }

        env.music.$displayImage
            .sink { [weak self] image in self?.artwork.setImage(image, animated: true) }
            .store(in: &cancellables)
        env.music.$tint
            .sink { [weak self] _ in self?.applyTint() }
            .store(in: &cancellables)
        env.music.$nowPlaying.combineLatest(env.music.$display)
            .sink { [weak self] value, display in self?.apply(value, display: display) }
            .store(in: &cancellables)
        applyTint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var glowColor: NSColor? { musicTint(env, palette: palette) }
    override var tickInterval: TimeInterval? { 1 }

    override func onScreenChanged() {
        env.music.setResyncDemand(isOnScreen)
        if isOnScreen { apply(env.music.nowPlaying, display: env.music.display) }
    }

    override func removeFromSuperview() {
        env.music.setResyncDemand(false)
        super.removeFromSuperview()
    }

    private func applyTint() {
        let tint = musicTint(env, palette: palette)
        waveform.setColor(tint)
        progress.setFillColor(palette.theme == .dark ? NSColor(white: 1, alpha: 0.92).blended(withFraction: 0.25, of: tint) ?? tint : tint)
        onLayoutChange?()
    }

    /// Browser/app playback has no timeline we can read, so the progress row is hidden then.
    private var hasTimeline = true

    private func apply(_ value: NowPlaying?, display: MusicDisplay?) {
        guard let display else {
            waveform.setActive(false)
            playButton.setSymbol("play.fill", animated: true)
            return
        }
        if titleLabel.stringValue != display.title { titleLabel.stringValue = display.title }
        if artistLabel.stringValue != display.subtitle { artistLabel.stringValue = display.subtitle }
        playButton.setSymbol(display.isPlaying ? "pause.fill" : "play.fill", animated: true)
        waveform.setActive(display.isPlaying)
        setAccessibilityLabel("\(display.title), \(display.subtitle)")
        let timeline = !display.isExternal && value?.duration != nil
        if timeline != hasTimeline {
            hasTimeline = timeline
            needsLayout = true
            onLayoutChange?()
        }
        guard timeline, let value else { return }
        let now = Date()
        if let fraction = value.fraction(at: now), let duration = value.duration {
            progress.isHidden = !showsProgress
            if value.isPlaying {
                progress.setValue(fraction, advancingTo: 1, over: max(0, duration - value.position(at: now)))
            } else {
                progress.setValue(fraction, animated: true)
            }
        } else {
            progress.setValue(0, animated: false)
        }
        updateTimes()
    }

    override func tick() { updateTimes() }

    private func updateTimes() {
        guard hasTimeline, let value = env.music.nowPlaying else { return }
        let duration = value.duration ?? 0
        let position = scrubFraction.map { $0 * duration } ?? value.position(at: Date())
        let elapsed = TimeFormat.clock(position)
        let remaining = duration > 0 ? "-" + TimeFormat.clock(duration - position) : ""
        if elapsedLabel.stringValue != elapsed { elapsedLabel.stringValue = elapsed }
        if remainingLabel.stringValue != remaining { remainingLabel.stringValue = remaining }
    }

    // Layout widths
    private let fixedWidth: CGFloat = 3 + 24 + 8 + 12 + 34 + 6 + 6 + 38 + 8 + 3 * 30 + 6 + 16 + 12
    /// Art, 300 pt of text and transport — used when there's no timeline to show.
    private let compactPlayerWidth: CGFloat = 487

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        // Without a timeline (browser audio) the player is narrower: art, text, transport.
        hasTimeline ? min(maxWidth, fixedWidth + 380) : min(maxWidth, compactPlayerWidth)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let artSide = h - 6
        artwork.frame = NSRect(x: 3, y: 3, width: artSide, height: artSide)

        let waveformWidth: CGFloat = 16
        waveform.frame = NSRect(x: bounds.width - 12 - waveformWidth, y: (h - 12) / 2, width: waveformWidth, height: 12)
        let buttonWidth: CGFloat = 30
        let buttonsX = waveform.frame.minX - 6 - 3 * buttonWidth
        previousButton.frame = NSRect(x: buttonsX, y: (h - 26) / 2, width: buttonWidth, height: 26)
        playButton.frame = NSRect(x: buttonsX + buttonWidth, y: (h - 26) / 2, width: buttonWidth, height: 26)
        nextButton.frame = NSRect(x: buttonsX + 2 * buttonWidth, y: (h - 26) / 2, width: buttonWidth, height: 26)

        let textX = artwork.frame.maxX + 8
        let flexible = buttonsX - 8 - textX - 12 - (34 + 6 + 6 + 38)
        // Prefer text, then the bar; drop the progress group entirely if it can't be legible.
        showsProgress = hasTimeline && flexible >= 110 + 70
        let textWidth = showsProgress ? min(190, max(110, flexible - 70)) : max(40, min(320, buttonsX - 8 - textX))
        stack(titleLabel, artistLabel, x: textX, width: textWidth, spacing: -1)

        [elapsedLabel, progress, remainingLabel].forEach { $0.isHidden = !showsProgress }
        guard showsProgress else { return }
        let groupX = textX + textWidth + 12
        center(elapsedLabel, x: groupX, width: 34)
        let barX = elapsedLabel.frame.maxX + 6
        let barWidth = max(40, buttonsX - 8 - 38 - 6 - barX)
        progress.frame = NSRect(x: barX, y: (h - 14) / 2, width: barWidth, height: 14)
        center(remainingLabel, x: progress.frame.maxX + 6, width: 38)
    }
}

/// Bubble for music when it's the secondary live activity.
final class MusicBubbleView: IslandContentView {
    private let waveform: WaveformView

    override init(env: AppEnvironment, palette: IslandPalette) {
        waveform = WaveformView(color: musicTint(env, palette: palette), barCount: 3)
        super.init(env: env, palette: palette)
        addSubview(waveform)
        env.music.$display
            .sink { [weak self] value in self?.waveform.setActive(value?.isPlaying ?? false) }
            .store(in: &cancellables)
        env.music.$tint
            .sink { [weak self] _ in
                guard let self else { return }
                self.waveform.setColor(musicTint(self.env, palette: self.palette))
            }
            .store(in: &cancellables)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Music — tap to show")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        waveform.frame = NSRect(x: (bounds.width - 10) / 2, y: (bounds.height - 9) / 2, width: 10, height: 9)
    }
}
