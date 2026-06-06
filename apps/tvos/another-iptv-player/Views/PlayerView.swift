import SwiftUI
import UIKit
import GRDB

private enum PlayerControl: Hashable {
    case previous
    case next
    case settings
    case scrubber
}

/// Metadata needed to upsert a `DBWatchHistory` row for the currently playing
/// item. Attach to each `PlayableItem` so queue items (e.g. series episodes)
/// carry their own history identity across prev/next navigation.
struct WatchHistoryTags: Equatable, Hashable {
    let playlistId: UUID
    let streamId: String
    let type: String // "live" | "vod" | "series"
    let seriesId: String?
    let title: String
    let secondaryTitle: String?
    let imageURL: String?
    let containerExtension: String?
}

struct PlayableItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    var historyTags: WatchHistoryTags? = nil
    /// Last saved position in milliseconds. Applied once per item when the
    /// player reports a non-zero duration (so the seek lands on a real timeline).
    var resumeTimeMs: Int? = nil
}

struct PlayerView: View {
    let items: [PlayableItem]

    @StateObject private var player = MPVPlayer()
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showDebug = false
    @State private var showSettings = false
    @State private var hasAppliedTrackPreferences = false

    @State private var saveHistoryTimer: Timer?

    @FocusState private var focusedControl: PlayerControl?

    init(items: [PlayableItem], startIndex: Int = 0) {
        precondition(!items.isEmpty, "PlayerView requires at least one item")
        self.items = items
        self._currentIndex = State(initialValue: max(0, min(startIndex, items.count - 1)))
    }

    init(url: URL, title: String?) {
        self.items = [PlayableItem(url: url, title: title ?? "")]
        self._currentIndex = State(initialValue: 0)
    }

    init(url: URL, title: String?, historyTags: WatchHistoryTags?, resumeTimeMs: Int? = nil) {
        self.items = [PlayableItem(url: url, title: title ?? "",
                                   historyTags: historyTags, resumeTimeMs: resumeTimeMs)]
        self._currentIndex = State(initialValue: 0)
    }

    private var currentItem: PlayableItem { items[currentIndex] }
    private var canGoPrevious: Bool { currentIndex > 0 }
    private var canGoNext: Bool { currentIndex < items.count - 1 }
    private var hasMultipleItems: Bool { items.count > 1 }

    private let autoHideSeconds: UInt64 = 5

    /// Seconds to seek per directional button press / swipe on the scrubber.
    /// Previously the touchpad pan mapped to full duration (1600pt span),
    /// which felt far too fast. Discrete 10s steps feel controllable.
    private let seekStepSeconds: TimeInterval = 10

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MPVVideoSurfaceView(player: player)
                .ignoresSafeArea()

            if let error = player.errorMessage {
                errorOverlay(error)
            }

            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        }
        .fullScreenCover(isPresented: $showSettings, onDismiss: {
            focusedControl = .settings
            presentControls()
        }) {
            SettingsPanel(
                player: player,
                onClose: { showSettings = false }
            )
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            player.load(currentItem.url, startAt: resumeStartSeconds(for: currentItem))
            presentControls()
            startSaveHistoryTimer()
            DispatchQueue.main.async { focusedControl = .scrubber }
        }
        .onDisappear {
            hideTask?.cancel()
            saveHistoryTimer?.invalidate()
            saveHistoryTimer = nil
            // Final flush so the last few seconds aren't lost when the user dismisses.
            saveWatchHistory()
            UIApplication.shared.isIdleTimerDisabled = false
            // MPVPlayer is disposed via its deinit after the StateObject releases;
            // MPVVideoSurfaceView.dismantleUIView stops the display link first so
            // no render tick can race with the teardown.
        }
        .onPlayPauseCommand {
            player.togglePause()
            presentControls()
        }
        .onExitCommand {
            if controlsVisible {
                // First Menu press hides controls; second dismisses the player.
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
                hideTask?.cancel()
            } else {
                dismiss()
            }
        }
        .onChange(of: player.isPaused) { _, paused in
            if paused {
                hideTask?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
            } else {
                presentControls()
            }
        }
        .onChange(of: focusedControl) { _, _ in
            presentControls()
        }
        .onChange(of: player.audioTracks) { _, _ in
            applyTrackPreferencesIfNeeded()
        }
        .onChange(of: player.subtitleTracks) { _, _ in
            applyTrackPreferencesIfNeeded()
        }
    }

    // MARK: - Track preferences

    private func applyTrackPreferencesIfNeeded() {
        guard !hasAppliedTrackPreferences else { return }
        // Wait until mpv has published at least one track list. Files with no
        // subtitles still publish `audioTracks` once the demuxer opens.
        guard !player.audioTracks.isEmpty || !player.subtitleTracks.isEmpty else { return }
        hasAppliedTrackPreferences = true

        let prefs = TrackPreferenceStore.load()
        if let audio = TrackPreferenceStore.pickAudio(from: player.audioTracks, prefs: prefs) {
            player.selectTrack(kind: .audio, id: audio.id)
        }
        if let video = TrackPreferenceStore.pickVideo(from: player.videoTracks, prefs: prefs) {
            player.selectTrack(kind: .video, id: video.id)
        }
        switch TrackPreferenceStore.pickSubtitle(from: player.subtitleTracks, prefs: prefs) {
        case .disabled:
            player.selectTrack(kind: .sub, id: 0)
        case .track(let sub):
            player.selectTrack(kind: .sub, id: sub.id)
        case .noPreference:
            break
        }
    }

    // MARK: - Queue navigation

    private func playPrevious() {
        guard canGoPrevious else { return }
        load(index: currentIndex - 1)
    }

    private func playNext() {
        guard canGoNext else { return }
        load(index: currentIndex + 1)
    }

    private func load(index: Int) {
        // Flush the outgoing item's history before we lose access to its
        // position. `currentIndex` still points to the old item here.
        saveWatchHistory()

        currentIndex = index
        // New file → fresh track list arrives from mpv. Let the preference
        // auto-apply run again for this episode.
        hasAppliedTrackPreferences = false
        player.load(currentItem.url, startAt: resumeStartSeconds(for: currentItem))
        presentControls()
    }

    /// Converts the item's saved `resumeTimeMs` into the seconds value mpv
    /// wants for `loadfile start=<sec>`. Live streams and short-progress items
    /// start from zero.
    private func resumeStartSeconds(for item: PlayableItem) -> TimeInterval {
        guard let resumeMs = item.resumeTimeMs, resumeMs > 5000 else { return 0 }
        guard item.historyTags?.type != "live" else { return 0 }
        return Double(resumeMs) / 1000.0
    }

    // MARK: - Watch history

    /// Starts/restarts the periodic save so we capture resume positions even
    /// when the user never actively dismisses (e.g. crash, force-quit).
    private func startSaveHistoryTimer() {
        saveHistoryTimer?.invalidate()
        saveHistoryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in saveWatchHistoryIfPlaying() }
        }
    }

    @MainActor
    private func saveWatchHistoryIfPlaying() {
        guard !player.isPaused else { return }
        saveWatchHistory()
    }

    /// Upsert the row for the currently-playing item. No-op if the item has
    /// no `historyTags` (e.g. the url-only initializer) or if duration isn't
    /// known yet for non-live types (avoids storing bogus progress).
    private func saveWatchHistory() {
        guard let tags = currentItem.historyTags else { return }
        let currentMs = Int(player.position * 1000)
        let durationMs = Int(player.duration * 1000)
        let isLive = tags.type == "live"
        // VOD/series need a real duration to express progress. Live has no
        // duration but we still want it in the list — record with durationMs=0.
        if !isLive && durationMs <= 0 { return }

        let history = DBWatchHistory(
            id: "\(tags.playlistId)_\(tags.type)_\(tags.streamId)",
            playlistId: tags.playlistId,
            streamId: tags.streamId,
            type: tags.type,
            lastTimeMs: isLive ? 0 : currentMs,
            durationMs: isLive ? 0 : durationMs,
            lastWatchedAt: Date(),
            seriesId: tags.seriesId,
            title: tags.title,
            secondaryTitle: tags.secondaryTitle,
            imageURL: tags.imageURL,
            containerExtension: tags.containerExtension
        )

        Task {
            do {
                try await AppDatabase.shared.write { db in try history.save(db) }
            } catch {
                print("[WatchHistory] save failed: \(error)")
            }
        }
    }

    // MARK: - Seek

    private func stepSeek(_ direction: TimeInterval) {
        let duration = max(player.duration, 0)
        let target: TimeInterval
        if duration > 0 {
            target = min(max(player.position + direction, 0), duration)
        } else {
            target = max(player.position + direction, 0)
        }
        player.seek(to: target)
        presentControls()
    }

    // MARK: - Overlays

    private func errorOverlay(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text(error)
                .font(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80)
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(player.mediaTitle.isEmpty ? currentItem.title : player.mediaTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    if hasMultipleItems {
                        Text("\(currentIndex + 1) / \(items.count)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if player.isPaused {
                        Label("Duraklatıldı", systemImage: "pause.fill")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                if showDebug {
                    debugPanel
                }
                if hasMultipleItems {
                    circleIconButton(
                        systemName: "backward.end.fill",
                        isEnabled: canGoPrevious,
                        focusTag: .previous,
                        action: playPrevious
                    )
                    circleIconButton(
                        systemName: "forward.end.fill",
                        isEnabled: canGoNext,
                        focusTag: .next,
                        action: playNext
                    )
                }
                circleIconButton(
                    systemName: "gearshape.fill",
                    isEnabled: true,
                    focusTag: .settings,
                    action: {
                        showSettings = true
                        hideTask?.cancel()
                    }
                )
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)

            Spacer()

            scrubberControl
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private func circleIconButton(
        systemName: String,
        isEnabled: Bool,
        focusTag: PlayerControl,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 34, weight: .semibold))
                .padding(22)
        }
        .buttonStyle(.plain)
        .background(.black.opacity(0.35), in: Circle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.35)
        .focused($focusedControl, equals: focusTag)
    }

    // MARK: - Scrubber control

    private var scrubberControl: some View {
        let duration = max(player.duration, 0.1)
        let displayPosition = min(max(player.position, 0), duration)
        let progress = displayPosition / duration
        let isFocused = focusedControl == .scrubber

        return VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: isFocused ? 10 : 6)
                    Capsule()
                        .fill(isFocused ? Color.yellow : .white)
                        .frame(width: max(0, geo.size.width * progress),
                               height: isFocused ? 10 : 6)
                    Circle()
                        .fill(isFocused ? Color.yellow : .white)
                        .frame(width: isFocused ? 24 : 14, height: isFocused ? 24 : 14)
                        .offset(x: max(0, min(geo.size.width, geo.size.width * progress)) - (isFocused ? 12 : 7))
                        .shadow(color: .black.opacity(0.4), radius: 6)
                }
                .frame(height: 24)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .frame(height: 24)

            HStack {
                Text(format(displayPosition))
                    .monospacedDigit()
                Spacer()
                Text(format(duration))
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.9))
        }
        .contentShape(Rectangle())
        .focusable(true)
        .focused($focusedControl, equals: .scrubber)
        .onMoveCommand { direction in
            switch direction {
            case .left:  stepSeek(-seekStepSeconds)
            case .right: stepSeek(+seekStepSeconds)
            default: break
            }
        }
        .onTapGesture {
            player.togglePause()
            presentControls()
        }
    }

    // MARK: - Controls visibility

    private func presentControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        let delay = autoHideSeconds
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard !player.isPaused, !showSettings else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
    }

    // MARK: - Debug

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            debugRow("Delivered", String(format: "%.1f fps", player.deliveredFPS))
            debugRow("Stream",    String(format: "%.2f fps", player.streamFPS))
            debugRow("Dropped",   "\(player.droppedFrameCount)")
            debugRow("Delayed",   "\(player.delayedFrameCount)")
            debugRow("Codec",     player.videoCodec.isEmpty ? "—" : player.videoCodec)
            debugRow("HW decode", player.hwdecCurrent.isEmpty ? "sw" : player.hwdecCurrent)
            debugRow("Resolution", player.videoWidth > 0 ? "\(player.videoWidth)×\(player.videoHeight)" : "—")
        }
        .font(.system(size: 22, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.white.opacity(0.7)).frame(width: 140, alignment: .leading)
            Text(value).foregroundStyle(.white)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Settings panel

private struct SettingsPanel: View {
    @ObservedObject var player: MPVPlayer
    var onClose: () -> Void

    private enum FocusTarget: Hashable { case close, video, audio, subtitle }
    @FocusState private var focused: FocusTarget?

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .center) {
                    Text("Ayarlar")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Label("Kapat", systemImage: "xmark")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .focused($focused, equals: .close)
                }

                trackSection(
                    title: "Video",
                    tracks: player.videoTracks,
                    selectedID: player.selectedVideoTrackID,
                    kind: .video,
                    allowDisable: false,
                    focusTag: .video
                )

                trackSection(
                    title: "Ses",
                    tracks: player.audioTracks,
                    selectedID: player.selectedAudioTrackID,
                    kind: .audio,
                    allowDisable: true,
                    focusTag: .audio
                )

                trackSection(
                    title: "Altyazı",
                    tracks: player.subtitleTracks,
                    selectedID: player.selectedSubtitleTrackID,
                    kind: .sub,
                    allowDisable: true,
                    focusTag: .subtitle
                )

                Spacer()
            }
            .padding(.horizontal, 120)
            .padding(.vertical, 80)
        }
        .onAppear {
            DispatchQueue.main.async {
                focused = !player.audioTracks.isEmpty ? .audio : .close
            }
        }
        .onExitCommand { onClose() }
    }

    @ViewBuilder
    private func trackSection(
        title: String,
        tracks: [MPVTrack],
        selectedID: Int64,
        kind: MPVTrack.Kind,
        allowDisable: Bool,
        focusTag: FocusTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))

            if tracks.isEmpty && !allowDisable {
                Text("Kullanılabilir parça yok")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        if allowDisable {
                            trackButton(
                                label: "Kapalı",
                                isSelected: selectedID <= 0,
                                action: { selectTrack(kind: kind, track: nil) }
                            )
                        }
                        ForEach(tracks) { track in
                            trackButton(
                                label: track.displayName,
                                isSelected: selectedID == track.id,
                                action: { selectTrack(kind: kind, track: track) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .focused($focused, equals: focusTag)
            }
        }
    }

    /// Applies the selection and persists it so future episodes default to the
    /// same language.
    private func selectTrack(kind: MPVTrack.Kind, track: MPVTrack?) {
        player.selectTrack(kind: kind, id: track?.id ?? 0)
        switch kind {
        case .audio:
            if let track { TrackPreferenceStore.saveAudio(from: track) }
        case .sub:
            if let track { TrackPreferenceStore.saveSubtitle(from: track) }
            else { TrackPreferenceStore.saveSubtitleDisabled() }
        case .video:
            if let track { TrackPreferenceStore.saveVideo(from: track) }
        }
    }

    private func trackButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                }
                Text(label)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .buttonStyle(.card)
    }
}

// MARK: - Video surface

struct MPVVideoSurfaceView: UIViewRepresentable {
    let player: MPVPlayer

    func makeUIView(context: Context) -> MPVVideoView {
        MPVVideoView(player: player)
    }

    func updateUIView(_ uiView: MPVVideoView, context: Context) {}

    /// Runs synchronously when SwiftUI removes the view from the hierarchy.
    /// Must invalidate the display link *before* the MPVPlayer disposes its
    /// render context, otherwise a pending tick reads a freed pointer and crashes.
    static func dismantleUIView(_ uiView: MPVVideoView, coordinator: ()) {
        uiView.teardown()
    }
}
