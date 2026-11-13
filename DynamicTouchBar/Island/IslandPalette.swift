import AppKit

/// Physical layout constants for the Touch Bar (30 pt tall; app region measured at 685 pt on a
/// 13-inch MacBook Pro with the collapsed Control Strip, ~1004 pt with it hidden). The island
/// always lays out against the *actual* bounds it is given, so nothing is hard-coded to a width.
enum IslandMetrics {
    static let barHeight: CGFloat = 30
    static let compactHeight: CGFloat = 24
    static let expandedHeight: CGFloat = 30
    static let edgeMargin: CGFloat = 4
    static let bubbleGap: CGFloat = 6
    static let bubbleDiameter: CGFloat = 24
    static let minimumCapsuleWidth: CGFloat = 64
    /// Fallback for the app region before the Touch Bar reports its real width.
    static let defaultAppRegionWidth: CGFloat = 685
    static let contentInset: CGFloat = 10
}

/// All colors the island draws with. Tuned for an OLED strip: the capsule is a *very* dark
/// graphite rather than pure black so it reads as an object against the black bar, with a
/// faint top highlight instead of a border.
struct IslandPalette {
    let theme: IslandTheme
    let accent: NSColor
    let capsuleTop: NSColor
    let capsuleBottom: NSColor
    let rim: NSColor
    let primary: NSColor
    let secondary: NSColor
    let tertiary: NSColor
    let controlFill: NSColor
    let controlPressed: NSColor
    let track: NSColor

    static func make(theme: IslandTheme, accent choice: AccentChoice) -> IslandPalette {
        let accent = color(for: choice, theme: theme)
        switch theme {
        case .dark:
            return IslandPalette(
                theme: theme,
                accent: accent,
                capsuleTop: NSColor(srgbRed: 0.125, green: 0.125, blue: 0.135, alpha: 1),
                capsuleBottom: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.06, alpha: 1),
                rim: NSColor(white: 1, alpha: 0.16),
                primary: NSColor(white: 0.97, alpha: 1),
                secondary: NSColor(white: 1, alpha: 0.58),
                tertiary: NSColor(white: 1, alpha: 0.32),
                controlFill: NSColor(white: 1, alpha: 0.10),
                controlPressed: NSColor(white: 1, alpha: 0.24),
                track: NSColor(white: 1, alpha: 0.16)
            )
        case .light:
            return IslandPalette(
                theme: theme,
                accent: accent,
                capsuleTop: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1),
                capsuleBottom: NSColor(srgbRed: 0.80, green: 0.80, blue: 0.83, alpha: 1),
                rim: NSColor(white: 1, alpha: 0.7),
                primary: NSColor(white: 0.06, alpha: 1),
                secondary: NSColor(white: 0, alpha: 0.58),
                tertiary: NSColor(white: 0, alpha: 0.32),
                controlFill: NSColor(white: 0, alpha: 0.08),
                controlPressed: NSColor(white: 0, alpha: 0.2),
                track: NSColor(white: 0, alpha: 0.14)
            )
        }
    }

    static func color(for choice: AccentChoice, theme: IslandTheme) -> NSColor {
        switch choice {
        case .system: .controlAccentColor
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .graphite: theme == .dark ? NSColor(white: 0.78, alpha: 1) : NSColor(white: 0.35, alpha: 1)
        }
    }

    /// Text/icon color to put on top of an accent-filled control.
    func onAccent(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.7 ? NSColor(white: 0.05, alpha: 1) : .white
    }
}

enum IslandFont {
    static func primary(_ size: CGFloat = 12, weight: NSFont.Weight = .semibold) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func digits(_ size: CGFloat = 12, weight: NSFont.Weight = .semibold) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func rounded(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }
}

enum Symbol {
    static func image(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold, scale: NSImage.SymbolScale = .medium) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight, scale: scale)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
}
