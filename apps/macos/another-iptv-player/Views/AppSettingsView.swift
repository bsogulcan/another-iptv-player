import SwiftUI

/// macOS native Settings penceresi (Cmd+, ile açılır).
/// Genel uygulama düzeyinde tercihler — playlist-bağımsız.
struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            PlaybackSettingsTab()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @AppStorage("dashboard.selectedSection.v2") private var savedSection: String = "live"

    var body: some View {
        Form {
            Section("Language") {
                Picker("Application language", selection: $localization.selectedLanguage) {
                    Text(L("settings.language.system")).tag("system")
                    ForEach(LocalizationManager.supportedLanguages) { lang in
                        if lang.code != "system" {
                            Text(lang.nativeName).tag(lang.code)
                        }
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Startup") {
                LabeledContent("Default section") {
                    Text(savedSection.capitalized)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PlaybackSettingsTab: View {
    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continueInBackground = true
    @AppStorage("player.videoAspectMode") private var aspectRaw = VideoAspectMode.bestFit.rawValue
    @AppStorage("player.volume") private var savedVolume: Double = 100

    var body: some View {
        Form {
            Section("Player") {
                Toggle("Continue playback when window is hidden", isOn: $continueInBackground)
                Toggle("Picture-in-Picture (coming soon)", isOn: $pipEnabled)
                    .disabled(true)
            }

            Section("Default video aspect") {
                Picker("Aspect", selection: $aspectRaw) {
                    ForEach(VideoAspectMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $savedVolume, in: 0...100)
                    Image(systemName: "speaker.wave.3.fill")
                    Text("\(Int(savedVolume))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("another-iptv-player")
                .font(.title2.weight(.semibold))
            Text("Version \(version) (build \(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Native macOS port of another-iptv-player.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
