import AppKit

/// Maps a presentation to its view.
enum ContentFactory {
    static func makeView(for content: PresentationContent, env: AppEnvironment, palette: IslandPalette) -> IslandContentView {
        switch content {
        case .minimal: MinimalContentView(env: env, palette: palette)
        case .dashboard: DashboardContentView(env: env, palette: palette)
        case .music(let expanded):
            expanded ? MusicExpandedView(env: env, palette: palette) : MusicCompactView(env: env, palette: palette)
        case .timer(let expanded):
            expanded ? TimerExpandedView(env: env, palette: palette) : TimerCompactView(env: env, palette: palette)
        case .progress(let expanded):
            expanded ? ProgressExpandedView(env: env, palette: palette) : ProgressCompactView(env: env, palette: palette)
        case .contextual: ContextualContentView(env: env, palette: palette)
        case .volume: VolumeContentView(env: env, palette: palette)
        case .brightness: BrightnessContentView(env: env, palette: palette)
        case .battery: BatteryContentView(env: env, palette: palette)
        case .clipboard: ClipboardContentView(env: env, palette: palette)
        case .notification(let id): NotificationContentView(env: env, palette: palette, id: id)
        }
    }

    static func makeBubbleView(for kind: LiveActivityKind, env: AppEnvironment, palette: IslandPalette) -> IslandContentView {
        switch kind {
        case .music: MusicBubbleView(env: env, palette: palette)
        case .timer: TimerBubbleView(env: env, palette: palette)
        case .progress: ProgressBubbleView(env: env, palette: palette)
        }
    }
}
