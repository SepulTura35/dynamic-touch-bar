import SwiftUI

struct GeneralPane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable DynamicTouchBar", isOn: $store.settings.isEnabled)
                Picker("Show on Touch Bar shortcut", selection: $store.settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        launchError = LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchError {
                    Text(launchError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Touch Bar")
            } footer: {
                PaneFooter("macOS only shows a Touch Bar for the app that is in front. Press the shortcut (or use the menu bar icon) to bring the island onto your Touch Bar; press it again or tap Esc to return to the app you were using.")
            }

            AlwaysOnSection(store: store)

            Section("Behaviour") {
                Picker("Resting state", selection: $store.settings.defaultState) {
                    ForEach(DefaultIslandState.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Expand when shown", isOn: $store.settings.expandOnSummon)
                Toggle("Collapse automatically", isOn: $store.settings.autoCollapse)
                if store.settings.autoCollapse {
                    LabeledContent("Collapse after") {
                        HStack {
                            Slider(value: $store.settings.autoCollapseDelay, in: 1...15, step: 0.5)
                            Text("\(store.settings.autoCollapseDelay, specifier: "%.1f") s").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Toggle("Return to previous app after app actions", isOn: $store.settings.returnFocusAfterAction)
                Picker("Hand back focus when idle", selection: $store.settings.autoDismissDelay) {
                    Text("Never").tag(0.0)
                    Text("After 5 seconds").tag(5.0)
                    Text("After 10 seconds").tag(10.0)
                    Text("After 30 seconds").tag(30.0)
                }
            }

            Section {
                Toggle("Show on-screen preview while active", isOn: $store.settings.showMirrorWindow)
            } footer: {
                PaneFooter("An optional mirror of the island near the top of the screen. It is a preview, not a replacement for the Touch Bar.")
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

struct AppearancePane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Style") {
                Picker("Theme", selection: $store.settings.theme) {
                    ForEach(IslandTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases) { choice in
                            AccentSwatch(choice: choice, theme: store.settings.theme, isSelected: store.settings.accent == choice) {
                                store.settings.accent = choice
                            }
                        }
                    }
                }
                Toggle("Tint from album artwork", isOn: $store.settings.tintFromArtwork)
                Toggle("Ambient glow", isOn: $store.settings.ambientGlow)
            }

            Section("Shape") {
                LabeledContent("Compact width") {
                    HStack {
                        Slider(value: $store.settings.capsuleWidthScale, in: 0.8...1.3, step: 0.05)
                        Text("\(Int(store.settings.capsuleWidthScale * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Corner radius") {
                    HStack {
                        Slider(value: $store.settings.cornerRadius, in: 6...15, step: 0.5)
                        Text("\(store.settings.cornerRadius, specifier: "%.1f")").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section {
                Picker("Animation", selection: $store.settings.animationStyle) {
                    ForEach(AnimationStyle.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $store.settings.animationSpeed, in: 0.5...2, step: 0.05)
                        Text("\(store.settings.animationSpeed, specifier: "%.2f")×").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Replay Expansion") { env.coordinator.tapCapsule() }
                }
            } header: {
                Text("Motion")
            } footer: {
                PaneFooter("Fine-tune the custom spring under Advanced ▸ Animation timing.")
            }
        }
    }
}

private struct AccentSwatch: View {
    let choice: AccentChoice
    let theme: IslandTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: IslandPalette.color(for: choice, theme: theme)).gradient)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ModulesPane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore

    private func binding(_ module: IslandModule) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledModules.contains(module) },
            set: { enabled in
                if enabled { store.settings.enabledModules.insert(module) } else { store.settings.enabledModules.remove(module) }
            }
        )
    }

    private func moduleToggle(_ module: IslandModule) -> some View {
        Toggle(isOn: binding(module)) {
            Label(module.title, systemImage: module.symbol)
        }
    }

    var body: some View {
        Form {
            Section {
                moduleToggle(.music)
                if store.settings.enabledModules.contains(.music) {
                    Toggle("Expand briefly when the track changes", isOn: $store.settings.showOnTrackChange)
                    Toggle("Download Spotify cover art", isOn: $store.settings.fetchSpotifyArtwork)
                    Picker("Keep paused music visible", selection: $store.settings.musicPausedLinger) {
                        Text("No").tag(0.0)
                        Text("30 seconds").tag(30.0)
                        Text("90 seconds").tag(90.0)
                        Text("5 minutes").tag(300.0)
                    }
                    Toggle("Show music playing in browsers and other apps", isOn: $store.settings.detectAppAudio)
                    if store.settings.detectAppAudio {
                        Toggle("Read the music tab's title (Safari, Chrome…)", isOn: $store.settings.readBrowserTabTitles)
                    }
                    Toggle("Media keys for other players", isOn: $store.settings.mediaKeyFallback)
                }
            } header: {
                Text("Music")
            } footer: {
                PaneFooter("Full track details, artwork and seeking come from Music and Spotify. For browsers (YouTube, Spotify Web…) and other apps, macOS's public audio API tells the island which app is playing; the title comes from the browser's music tab (macOS asks once for permission). Play/pause and skip use the media keys, which need Accessibility access.")
            }

            Section("System") {
                moduleToggle(.volume)
                if store.settings.enabledModules.contains(.volume) {
                    Toggle("Show when the volume changes", isOn: $store.settings.showVolumeOnChange)
                }
                moduleToggle(.brightness)
                moduleToggle(.battery)
                if store.settings.enabledModules.contains(.battery) {
                    Toggle("Show when the charger is connected", isOn: $store.settings.showOnPowerChange)
                    Stepper("Low battery warning at \(store.settings.lowBatteryThreshold)%", value: $store.settings.lowBatteryThreshold, in: 5...50, step: 5)
                }
            }

            Section {
                moduleToggle(.timer)
                if store.settings.enabledModules.contains(.timer) {
                    Stepper("Focus length: \(store.settings.pomodoroWorkMinutes) min", value: $store.settings.pomodoroWorkMinutes, in: 5...120, step: 5)
                    Stepper("Short break: \(store.settings.pomodoroShortBreakMinutes) min", value: $store.settings.pomodoroShortBreakMinutes, in: 1...30)
                    Stepper("Long break: \(store.settings.pomodoroLongBreakMinutes) min", value: $store.settings.pomodoroLongBreakMinutes, in: 5...60, step: 5)
                    Stepper("Rounds before a long break: \(store.settings.pomodoroRounds)", value: $store.settings.pomodoroRounds, in: 1...8)
                    Toggle("Play a sound when a timer ends", isOn: $store.settings.timerSound)
                    Toggle("Also notify in Notification Center when hidden", isOn: $store.settings.timerSystemNotification)
                }
            } header: {
                Text("Timer & Focus")
            }

            Section {
                moduleToggle(.notifications)
                moduleToggle(.progress)
                if store.settings.enabledModules.contains(.progress) {
                    Toggle("Show browser downloads from the Downloads folder", isOn: $store.settings.watchDownloads)
                }
                moduleToggle(.shortcuts)
            } header: {
                Text("Notifications & Activity")
            } footer: {
                PaneFooter("The island shows its own events (timers, battery, media, copies) and anything sent to dynamictouchbar://notify or dynamictouchbar://progress. Other apps' notifications are private to macOS and are never read. Download percentages aren't exposed by browsers, so downloads show as in progress with the size received so far.")
            }

            Section {
                moduleToggle(.clipboard)
                if store.settings.enabledModules.contains(.clipboard) {
                    Toggle("Hide anything that looks like a password or key", isOn: $store.settings.clipboardHideSecrets)
                    Stepper("Preview length: \(store.settings.clipboardPreviewLength) characters", value: $store.settings.clipboardPreviewLength, in: 16...120, step: 8)
                }
            } header: {
                Text("Clipboard (opt-in)")
            } footer: {
                PaneFooter("Off by default. When on, a preview appears after you copy. Content is kept in memory only, never saved or sent anywhere, and dropped after a minute. Copies from password managers and items marked concealed are ignored. macOS may ask you to allow pasting from other apps.")
            }
        }
    }
}

/// Opt-in always-on mode. Lives in General, clearly marked experimental.
struct AlwaysOnSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            Toggle("Show over other apps when something happens", isOn: $store.settings.alwaysOnMode)
                .disabled(!SystemTouchBarBridge.isAvailable)
            if store.settings.alwaysOnMode {
                Toggle("Rise when music starts or the track changes", isOn: $store.settings.revealOnMusic)
                Toggle("Rise when the volume changes", isOn: $store.settings.revealOnVolume)
                Toggle("Cover the Control Strip while showing", isOn: $store.settings.alwaysOnCoverControlStrip)
            }
        } header: {
            HStack {
                Text("Always-on mode")
                Text("EXPERIMENTAL")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
            }
        } footer: {
            PaneFooter(SystemTouchBarBridge.isAvailable
                ? "While idle your normal Touch Bar stays as it is and a small island button sits in the Control Strip. Notifications, timers, the charger, copies and (optionally) music make the island rise over the current app for a few seconds. This uses an undocumented macOS API (the same one Pock and MTMR use); a future macOS update could break it, in which case the app falls back to shortcut-only mode. Volume is off by default so it never covers the system volume slider while you drag it."
                : "Not available on this version of macOS — the island can only be shown with the shortcut.")
        }
    }
}
