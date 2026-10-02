import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PlaybackTrackSettingsSheet: View {
    @ObservedObject var player: VideoPlayerController
    @Binding var showDebugOverlay: Bool
    let streamURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var didCopyURL = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var didCopyAirPlayLog = false
    @State private var airPlayLogCopyResetTask: Task<Void, Never>?
    @State private var showSubtitleImporter = false
    @State private var showSubtitleImportError = false
    /// What went wrong with the last import, shown under the alert's generic title.
    @State private var subtitleImportErrorMessage: String?
    @State private var audioDelaySeconds = AudioDelayPersistence.load()
    /// Experimental and off by default: AirPlay on a live channel first tries the
    /// provider's own HLS stream (see `CastNativeURL`).
    @AppStorage(CastNativeURL.enabledDefaultsKey) private var nativeLiveCastEnabled = false

    /// Only the formats the import pipeline can parse; anything else would be picked
    /// and then rejected.
    private static let subtitleContentTypes: [UTType] =
        ["srt", "ass", "ssa", "vtt"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        NavigationStack {
            List {
                trackSection(
                    title: L("player.tracks.video"),
                    items: player.videoTracks,
                    currentId: player.currentVideoTrackId,
                    emptyLabel: L("player.tracks.empty.video"),
                    select: { player.selectVideoTrack(id: $0) }
                )
                trackSection(
                    title: L("player.tracks.audio"),
                    items: player.audioTracks,
                    currentId: player.currentAudioTrackId,
                    emptyLabel: L("player.tracks.empty.audio"),
                    select: { player.selectAudioTrack(id: $0) }
                )
                // The delay only acts on the FFmpeg player; on the AVPlayer path (and
                // while casting) the slider would be inert, so the row is not offered.
                if player.supportsAudioDelay {
                    audioDelaySection
                }
                trackSection(
                    title: L("player.tracks.subtitle"),
                    items: player.subtitleTracks,
                    currentId: player.currentSubtitleTrackId,
                    emptyLabel: L("player.tracks.empty.subtitle"),
                    select: { player.selectSubtitleTrack(id: $0) }
                )
                if !player.isLiveStream {
                    importedSubtitlesSection
                }
                Section(L("player.dev_section")) {
                    Toggle(L("player.show_debug_overlay"), isOn: $showDebugOverlay)
                    Toggle(L("player.airplay.native_live_cast"), isOn: $nativeLiveCastEnabled)
                        .onChange(of: nativeLiveCastEnabled) { _, enabled in
                            // Switching it on is the way to try a host again that a
                            // failed attempt put on the one-week skip list.
                            if enabled { CastNativeURL.forgetFailures() }
                        }
                    // Reachable without the debug overlay, and after a relaunch: this
                    // sheet is hidden while a cast plays, so the row is mostly used once
                    // the cast is over (see `AirPlayLogExport`).
                    Button(action: copyAirPlayLog) {
                        HStack(spacing: 10) {
                            Text(
                                didCopyAirPlayLog
                                    ? L("player.stream_url.copied")
                                    : L("player.debug.copy_airplay_log")
                            )
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: didCopyAirPlayLog ? "checkmark" : "doc.on.doc")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(didCopyAirPlayLog ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Section(L("player.stream_url.title")) {
                    Button(action: copyStreamURL) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(streamURL.absoluteString)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Image(systemName: didCopyURL ? "checkmark" : "doc.on.doc")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(didCopyURL ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(
                        didCopyURL ? L("player.stream_url.copied") : L("player.stream_url.copy")
                    )
                }
            }
            .navigationTitle(L("player.tracks.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
        .onAppear { player.updateTracks() }
        .onDisappear {
            copyResetTask?.cancel()
            airPlayLogCopyResetTask?.cancel()
        }
        .onChange(of: audioDelaySeconds) { _, new in
            player.applyAudioDelaySeconds(new)
        }
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: Self.subtitleContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let picked = urls.first else { return }
            do {
                try player.importSubtitleFile(at: picked)
            } catch {
                // The import names its own reasons (encoding, format, no cues); anything
                // else is a file error the system describes.
                subtitleImportErrorMessage =
                    (error as? SubtitleImportError)?.errorDescription ?? error.localizedDescription
                showSubtitleImportError = true
            }
        }
        .alert(L("player.subtitle_import.failed"), isPresented: $showSubtitleImportError) {
            Button(L("common.close"), role: .cancel) {}
        } message: {
            if let subtitleImportErrorMessage, !subtitleImportErrorMessage.isEmpty {
                Text(subtitleImportErrorMessage)
            }
        }
    }

    /// Imported files are stored for this content and loaded automatically on future playbacks.
    private var importedSubtitlesSection: some View {
        Section {
            ForEach(player.importedSubtitleFiles, id: \.self) { file in
                Label(file.lastPathComponent, systemImage: "doc.text")
                    .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    player.deleteImportedSubtitle(player.importedSubtitleFiles[index])
                }
            }
            Button {
                showSubtitleImporter = true
            } label: {
                Label(L("player.subtitle_import.button"), systemImage: "plus")
            }
        } header: {
            Text(L("player.subtitle_import.section"))
        } footer: {
            Text(L("player.subtitle_import.footer"))
        }
    }

    private var audioDelaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("player.audio_delay.label"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(audioDelayDisplay)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // The slider carries the same label and value for VoiceOver.
                .accessibilityHidden(true)
                Slider(
                    value: $audioDelaySeconds,
                    in: AudioDelayPersistence.range,
                    step: AudioDelayPersistence.step
                ) {
                    Text(L("player.audio_delay.label"))
                }
                .accessibilityValue(audioDelayDisplay)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L("player.audio_delay.section"))
        } footer: {
            Text(L("player.audio_delay.footer"))
        }
    }

    private var audioDelayDisplay: String {
        let ms = Int((audioDelaySeconds * 1000).rounded())
        if ms == 0 { return L("subtitle.no_delay") }
        return ms > 0 ? "+\(ms) ms" : "\(ms) ms"
    }

    private func copyStreamURL() {
        UIPasteboard.general.string = streamURL.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        didCopyURL = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { didCopyURL = false }
        }
    }

    private func copyAirPlayLog() {
        UIPasteboard.general.string = AirPlayLogExport.text()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        didCopyAirPlayLog = true
        airPlayLogCopyResetTask?.cancel()
        airPlayLogCopyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { didCopyAirPlayLog = false }
        }
    }

    @ViewBuilder
    private func trackSection(
        title: String,
        items: [TrackMenuOption],
        currentId: Int,
        emptyLabel: String,
        select: @escaping (Int) -> Void
    ) -> some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyLabel)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        select(item.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            // The engine hands over the row texts ready-made: `title` is the
                            // stream's own track title or, without one, the language name in
                            // the app language; `detail` is codec, channels and bitrate.
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 8)
                            if item.id == currentId {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    // Spoken as the row's selected state instead.
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(item.id == currentId ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - AirPlay log export

/// The text behind every "Copy AirPlay log" control: the lines of this app session
/// or, when there are none (the app was relaunched since the cast, or the shared log
/// buffer has moved on), the record saved when the last cast ended. Every line was
/// redacted when it was written, so the text holds no stream URL or credentials.
nonisolated enum AirPlayLogExport {
    static let tags = ["AirPlayCast", "AirPlayRemux"]
    /// Where the cast controller saves the record of the last cast.
    static let persistedKey = "airplay.lastSessionLog"

    static func text() -> String {
        text(live: Log.recentLines(tags: tags), persisted: Log.persistedLines(key: persistedKey))
    }

    /// The choice itself, free of the log store. The saved record is labelled, so a
    /// reader does not take it for what just happened.
    static func text(live: [String], persisted: @autoclosure () -> [String]) -> String {
        if !live.isEmpty { return live.joined(separator: "\n") }
        let saved = persisted()
        guard !saved.isEmpty else { return "No AirPlay log lines recorded." }
        return (["Last saved AirPlay session:"] + saved).joined(separator: "\n")
    }
}

// MARK: - Panel presentation

/// Height of the in-player settings panels below full size. In regular height this is
/// a fixed 320 pt, which leaves the picture visible above the panel. In compact height
/// (iPhone landscape) 320 pt would be nearly the whole screen, so the panel takes 60 %
/// of the available height there.
/// `nonisolated`: SwiftUI's `CustomPresentationDetent` requirement is not main-actor
/// isolated.
nonisolated private struct PlayerSettingsPanelDetent: CustomPresentationDetent {
    static let regularHeight: CGFloat = 320
    static let compactHeightFraction: CGFloat = 0.6

    static func height(in context: Context) -> CGFloat? {
        guard context.verticalSizeClass == .compact else { return regularHeight }
        return min(regularHeight, (context.maxDetentValue * compactHeightFraction).rounded())
    }
}

/// How the track settings and subtitle appearance sheets are presented over the
/// player: a panel that starts at a compact height with the video visible, playing
/// and still interactive behind it, and that can be pulled up to full size.
struct PlayerSettingsPanelPresentation: ViewModifier {
    @Binding var isPresented: Bool
    /// The player went to the docked mini card.
    let isPlayerMinimized: Bool

    private static let compactDetent = PresentationDetent.custom(PlayerSettingsPanelDetent.self)

    /// A sheet presented straight after another one is dismissed ignores its detents
    /// and its compact adaptation and comes up full screen (seen on iOS 18.1 and 26.0).
    /// It has to wait for the dismissal to finish.
    private static let reopenDelay: TimeInterval = 0.7

    func body(content: Content) -> some View {
        content
            .presentationDetents([Self.compactDetent, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: Self.compactDetent))
            // A drag on the content scrolls it; the panel is resized by its grabber
            // and its navigation bar.
            .presentationContentInteraction(.scrolls)
            // Without this a sheet is full screen in compact height whatever its
            // detents are. With it the sheet stays attached to the bottom edge at
            // form width, so the picture also stays visible on both sides.
            .presentationCompactAdaptation(horizontal: .sheet, vertical: .sheet)
            .presentationDragIndicator(.visible)
            // With the chrome reachable behind the panel the player can now be
            // minimized while the panel is open; it must not stay over the catalog.
            .onChange(of: isPlayerMinimized) { _, minimized in
                if minimized, isPresented { isPresented = false }
            }
    }

    /// One panel was requested while the other is open, which the reachable chrome
    /// now allows: closes the open one and presents the requested one afterwards.
    static func present(_ requested: Binding<Bool>, afterClosing open: Binding<Bool>) {
        requested.wrappedValue = false
        open.wrappedValue = false
        DispatchQueue.main.asyncAfter(deadline: .now() + reopenDelay) {
            guard !open.wrappedValue else { return }
            requested.wrappedValue = true
        }
    }
}

extension View {
    func playerSettingsPanelPresentation(
        isPresented: Binding<Bool>,
        isPlayerMinimized: Bool
    ) -> some View {
        modifier(
            PlayerSettingsPanelPresentation(
                isPresented: isPresented,
                isPlayerMinimized: isPlayerMinimized
            )
        )
    }
}
