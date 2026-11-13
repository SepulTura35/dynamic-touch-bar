import AppKit
import Combine

final class VolumeContentView: IslandContentView {
    private let muteButton: IslandButton
    private let slider: IslandSlider
    private let valueLabel: NSTextField
    private let unavailableLabel: NSTextField

    override init(env: AppEnvironment, palette: IslandPalette) {
        let volume = env.volume
        muteButton = IslandButton(symbol: VolumeModel.symbol(level: volume.volume, muted: volume.isMuted),
                                  accessibilityLabel: "Mute", palette: palette, pointSize: 13) { volume.toggleMute() }
        slider = IslandSlider(palette: palette, thickness: 6, activeThickness: 10, accessibilityLabel: "Volume")
        valueLabel = IslandLabel.make(font: IslandFont.digits(11), color: palette.secondary, alignment: .right)
        unavailableLabel = IslandLabel.make(font: IslandFont.primary(11, weight: .medium), color: palette.secondary)
        super.init(env: env, palette: palette)
        [muteButton, slider, valueLabel, unavailableLabel].forEach(addSubview)

        slider.onChange = { [weak self] value, _ in
            self?.env.volume.setVolume(value)
            self?.env.noteInteraction()
        }
        volume.$volume.combineLatest(volume.$isMuted, volume.$isAvailable, volume.$deviceName)
            .sink { [weak self] level, muted, available, name in self?.apply(level: level, muted: muted, available: available, device: name) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func preferredWidth(maxWidth: CGFloat) -> CGFloat { min(maxWidth, 330 * widthScale) }

    private func apply(level: Double, muted: Bool, available: Bool, device: String) {
        let display = muted ? 0 : level
        muteButton.setSymbol(VolumeModel.symbol(level: level, muted: muted), animated: true)
        slider.setValue(display, animated: true)
        slider.setFillColor(muted ? palette.tertiary : palette.primary)
        valueLabel.stringValue = muted ? "Muted" : "\(Int((level * 100).rounded()))%"
        slider.isHidden = !available
        valueLabel.isHidden = !available
        unavailableLabel.isHidden = available
        unavailableLabel.stringValue = "\(device.isEmpty ? "This output" : device) has no software volume"
        setAccessibilityLabel("Volume \(valueLabel.stringValue)")
    }

    override func layout() {
        super.layout()
        muteButton.frame = NSRect(x: 5, y: (bounds.height - 26) / 2, width: 30, height: 26)
        let labelWidth: CGFloat = 44
        center(valueLabel, x: bounds.width - 12 - labelWidth, width: labelWidth)
        let sliderX = muteButton.frame.maxX + 8
        slider.frame = NSRect(x: sliderX, y: 0, width: valueLabel.frame.minX - 10 - sliderX, height: bounds.height)
        center(unavailableLabel, x: sliderX, width: bounds.width - sliderX - 12)
    }
}
