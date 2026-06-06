import SwiftUI
import GRDB
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Public types (call sites bağımlı)

struct LiveChannelCategorySection: Identifiable, Equatable {
    let id: String
    let title: String
    let streams: [DBLiveStream]
}

struct ChannelPanelItem: Identifiable, Equatable {
    let id: String
    let name: String
    let iconURL: URL?
}

struct ChannelPanelSection: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [ChannelPanelItem]
}

enum VideoAspectMode: String, CaseIterable, Identifiable {
    case bestFit, fill, stretch
    /// Fixed aspect ratio modları — video frame'i container'a sığar (`.resizeAspect`),
    /// container ise dış aspectRatio modifier'ı ile sabit orana clamp edilir.
    case ratio16x9, ratio4x3, ratio16x10
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bestFit:    return "Best Fit"
        case .fill:       return "Fill (crop)"
        case .stretch:    return "Stretch"
        case .ratio16x9:  return "16:9"
        case .ratio4x3:   return "4:3"
        case .ratio16x10: return "16:10"
        }
    }
    var gravity: AVLayerVideoGravity {
        switch self {
        case .bestFit, .ratio16x9, .ratio4x3, .ratio16x10:
            return .resizeAspect
        case .fill:    return .resizeAspectFill
        case .stretch: return .resize
        }
    }
    /// Container'ı sabit orana clamp eder; free-form modlarda `nil`.
    var fixedAspect: CGFloat? {
        switch self {
        case .ratio16x9:  return 16.0 / 9.0
        case .ratio4x3:   return 4.0 / 3.0
        case .ratio16x10: return 16.0 / 10.0
        case .bestFit, .fill, .stretch: return nil
        }
    }
}

// MARK: - PlayerView

struct PlayerView: View {
    let url: URL
    let title: String
    var subtitle: String? = nil
    var artworkURL: URL? = nil
    var isLiveStream: Bool = false

    let playlistId: UUID
    let streamId: String
    let type: String
    var seriesId: String? = nil
    var resumeTimeMs: Int? = nil
    var containerExtension: String? = nil

    var canGoToPreviousEpisode: Bool = false
    var canGoToNextEpisode: Bool = false
    var onPreviousEpisode: (() -> Void)? = nil
    var onNextEpisode: (() -> Void)? = nil
    var canGoToPreviousChannel: Bool = false
    var canGoToNextChannel: Bool = false
    var onPreviousChannel: (() -> Void)? = nil
    var onNextChannel: (() -> Void)? = nil
    var channelPanelSections: [ChannelPanelSection] = []
    var currentChannelPanelItemId: String? = nil
    var onSelectChannelPanelItem: ((String) -> Void)? = nil
    var isLiveChannelSidePanelVisible: Bool = false
    var onToggleLiveChannelSidePanel: (() -> Void)? = nil
    var onVideoSurfaceTap: (() -> Void)? = nil
    var onNavigateToDetail: ((String, String) -> Void)? = nil

    var isFavorite: Bool? = nil
    var onToggleFavorite: (() -> Void)? = nil

    @Environment(\.playerOverlayDismiss) fileprivate var overlayDismiss
    @Environment(\.dismiss) private var dismiss

    @StateObject private var player = MPVPlayer()
    @State private var nowPlaying: NowPlayingCenter?
    @State private var controlsVisible = true
    /// Reference type — Task'ı @State'e koyarsak her armHideTimer çağrısı view
    /// re-render tetikleyip menü açıkken NSMenu highlight'ını sıfırlıyordu (flicker bug).
    @State private var hideTimer = HideTimerHolder()
    /// Watch history persistence: 5s cadansla `saveWatchHistory()` çağıran loop.
    /// iOS PlayerView ile birebir behavior — `.onDisappear`'da bir kez daha sync çağrılır.
    @State private var saveHistoryTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showSidePanel = false
    @State private var isHovered = false

    @AppStorage("player.videoAspectMode") private var aspectRaw = VideoAspectMode.bestFit.rawValue
    @AppStorage("player.volume") private var savedVolume: Double = 100
    @AppStorage("player.debugOverlayEnabled") private var showDebugOverlay = false
    @State private var lastVolumeBeforeMute: Double = 100

    @State private var videoTracks: [TrackMenuOption] = []
    @State private var audioTracks: [TrackMenuOption] = []
    @State private var subtitleTracks: [TrackMenuOption] = [TrackMenuOption(id: -1, title: "Kapalı")]
    @State private var currentVideoId: Int = -1
    @State private var currentAudioId: Int = -1
    @State private var currentSubtitleId: Int = -1
    /// player.$playbackRate mirror — menü Binding'i bu @State'i göstersin ki player
    /// position update'lerinde menü Picker'ı re-evaluate olmasın (NSMenu flicker fix).
    @State private var playbackRateMirror: Double = 1.0
    /// Aynı motivasyonla volume/isPaused/isBuffering mirror'ları — transport bar
    /// Equatable diff'inde sadece bunlar değişince re-render olur.
    @State private var volumeMirror: Double = 100
    @State private var isPausedMirror: Bool = true
    @State private var isBufferingMirror: Bool = false
    /// Subtitle appearance modal flag — track menüsünden tetiklenir.
    @State private var showSubtitleAppearance = false

    private var aspect: VideoAspectMode { VideoAspectMode(rawValue: aspectRaw) ?? .bestFit }

    var body: some View {
        ZStack {
            // .ignoresSafeArea kaldırıldı — PlayerView artık NavigationSplitView detail panel
            // içinde embed render ediliyor; bu modifier SwiftUI sınırlarını window seviyesine
            // kadar gevşetip video'nun sidebar arkasına geçmesine yol açıyordu. Native macOS
            // fullscreen (Cmd+Ctrl+F) modunda sidebar zaten gizleniyor → tüm window dolar.
            Color.black

            // Tap gesture'ları SADECE video surface'te — controls overlay'deki butonlar
            // disambiguation gecikmesinden etkilenmesin. (Eskiden parent ZStack üstündeydi,
            // her button click ~300ms gecikmeli çalışıyordu.)
            Group {
                if let ratio = aspect.fixedAspect {
                    // Fixed-ratio modlarda video container'ı orana clamp et; etrafı siyahta
                    // kalır (letterbox/pillarbox). bestFit ile sonuç görsel olarak bestFit'e
                    // yakın olabilir ama burada container'ın kendisi sabittir.
                    VideoSurfaceContainer(player: player, gravity: aspect.gravity)
                        .aspectRatio(ratio, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VideoSurfaceContainer(player: player, gravity: aspect.gravity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .onTapGesture(count: 1) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    controlsVisible.toggle()
                }
                if controlsVisible { armHideTimer() }
            }

            // Controls always in hierarchy; opacity-based fade. Bu sayede menu açıkken
            // overlay kaybolup menu kapanmıyor — sadece görünmez oluyor, etkileşim hala canlı.
            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .animation(.easeInOut(duration: 0.18), value: controlsVisible)

            // Playback failure mesajı — mpv stream açamayınca kırmızı alert gibi.
            if let msg = player.playbackFailureMessage, !msg.isEmpty {
                VStack {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stream could not be played")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(msg)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(NSColor.systemRed).opacity(0.92))
                    )
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
                    .padding(.top, 78)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(50)
            }

            // Debug overlay — controls görünürken sağ-üstte (player menüsünden açılır).
            if controlsVisible, showDebugOverlay {
                VStack {
                    HStack {
                        Spacer()
                        PlayerDebugOverlay(player: player)
                            .padding(.top, 78)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if isLiveStream, showSidePanel, !channelPanelSections.isEmpty {
                VStack {
                    Spacer()
                    LiveChannelSidePanel(
                        sections: channelPanelSections,
                        currentItemId: currentChannelPanelItemId,
                        onSelectChannel: { id in onSelectChannelPanelItem?(id) }
                    )
                    .padding(.bottom, controlsVisible ? 120 : 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeOut(duration: 0.22), value: controlsVisible)
            }

            keyboardBridge
        }
        // PlayerWindowChrome (titleVisibility=.hidden + titlebarAppearsTransparent +
        // fullSizeContentView) embed mode'da NavigationSplitView'in titlebar/toolbar bölgesini
        // bozuyor — sidebar üstündeki traffic light butonları (close/min/max) görünmez oluyor.
        // Player detail panel içinde render edildiği için window chrome modifikasyonuna gerek yok.
        // Toolbar gizleme de aynı sebeple kaldırıldı; ContentView'in toolbar item'ları korunur.
        // Sürekli hover takibi: mouse hareket ettiği her an kontrol görünür kalsın
        // ve hide timer sıfırlansın. Menu açıkken mouse menu içindeyse hover ended
        // gelir ama overlay opacity'li olduğu için menu kapanmaz.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !controlsVisible {
                    withAnimation(.easeInOut(duration: 0.18)) { controlsVisible = true }
                }
                armHideTimer()
            case .ended:
                armHideTimer()
            }
        }
        .task {
            let startSeconds: TimeInterval? = {
                guard let resumeTimeMs, resumeTimeMs > 0 else { return nil }
                return Double(resumeTimeMs) / 1000.0
            }()
            player.load(url, play: true, startSeconds: startSeconds, liveLowLatency: isLiveStream)
            player.setVolume(savedVolume)
            armHideTimer()
            let np = NowPlayingCenter(player: player)
            np.setMetadata(title: title, subtitle: subtitle, isLive: isLiveStream)
            np.nextHandler = { onNextEpisode?(); onNextChannel?() }
            np.prevHandler = { onPreviousEpisode?(); onPreviousChannel?() }
            nowPlaying = np
            startSaveHistoryLoop()
            // Persisted subtitle appearance + delay — kullanıcı önceki oturumdan ayarladığını
            // beklediği şekilde uygula. mpv property setter'ları idempotent, no-op'ta zarar yok.
            let appearance = SubtitleAppearancePersistence.load()
            player.applySubtitleAppearanceFromSettings(appearance)
            player.setSubDelay(seconds: appearance.delaySeconds)
        }
        // Track'leri birden çok event'te tetikle: file ready, ilk pozisyon, süre değişimi.
        .onChange(of: player.isReady) { _, ready in
            if ready { reloadTracks() }
        }
        .onChange(of: player.duration) { _, dur in
            if dur > 0 { reloadTracks() }
        }
        .onChange(of: player.videoDisplayWidth) { _, w in
            if w > 0 { reloadTracks() }
        }
        .onReceive(player.$playbackRate) { playbackRateMirror = $0 }
        .onReceive(player.$volume) { volumeMirror = $0 }
        .onReceive(player.$isPaused) { isPausedMirror = $0 }
        .onReceive(player.$isBuffering) { isBufferingMirror = $0 }
        .onDisappear {
            hideTimer.task?.cancel()
            saveHistoryTask?.cancel()
            // Final flush — kullanıcı player'ı kapatırken son pozisyon kaybolmasın.
            saveWatchHistory()
            player.dispose()
        }
        .sheet(isPresented: $showSubtitleAppearance) {
            SubtitleAppearanceSheet(player: player)
        }
    }

    /// External subtitle dosyası için NSOpenPanel açar; .srt/.ass/.ssa/.sub/.vtt seçilebilir.
    /// Seçilen dosyayı mpv `sub-add ... select` ile yükler — track menüsünde yeni sub track
    /// otomatik görünür hale gelir.
    private func presentSubtitleOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.plainText, .data]
        for ext in ["srt", "ass", "ssa", "sub", "vtt"] {
            if let t = UTType(filenameExtension: ext) { types.insert(t, at: 0) }
        }
        panel.allowedContentTypes = types
        panel.prompt = L("subtitle.open_panel_prompt")
        panel.title = L("subtitle.open_panel_title")
        if panel.runModal() == .OK, let url = panel.url {
            let lang = url.deletingPathExtension().pathExtension // foo.en.srt → "en"
            player.loadExternalSubtitle(url: url,
                                        title: url.deletingPathExtension().lastPathComponent,
                                        lang: lang.isEmpty ? nil : lang)
        }
    }

    // MARK: - Watch history

    /// 5 saniye cadansla DB'ye snapshot yazar. Player paused/buffering iken yazma atlanır
    /// (iOS davranışı: `if player.isPlaying`). Cancel `.onDisappear`'da yapılır.
    private func startSaveHistoryLoop() {
        saveHistoryTask?.cancel()
        saveHistoryTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                if !player.isPaused {
                    saveWatchHistory()
                }
            }
        }
    }

    /// `DBWatchHistory` upsert. Live stream'leri (duration <= 0) iOS gibi atlar.
    /// ID formatı `"{playlistId}_{type}_{streamId}"` iOS ile aynı.
    private func saveWatchHistory() {
        let positionMs = Int((player.position * 1000).rounded())
        let durationMs = Int((player.duration * 1000).rounded())
        guard durationMs > 0 else { return }

        let history = DBWatchHistory(
            id: "\(playlistId)_\(type)_\(streamId)",
            playlistId: playlistId,
            streamId: streamId,
            type: type,
            lastTimeMs: positionMs,
            durationMs: durationMs,
            lastWatchedAt: Date(),
            seriesId: seriesId,
            title: title,
            secondaryTitle: subtitle,
            imageURL: artworkURL?.absoluteString,
            containerExtension: containerExtension
        )

        Task {
            do {
                try await AppDatabase.shared.write { db in
                    try history.save(db)
                }
            } catch {
                NSLog("Failed to save watch history: %@", String(describing: error))
            }
        }
    }

    private final class HideTimerHolder {
        var task: Task<Void, Never>?
    }

    // MARK: - Overlay layout

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topChrome
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.7), .black.opacity(0.3), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 140)
                    .allowsHitTesting(false),
                    alignment: .top
                )

            Spacer(minLength: 0)

            bottomChrome
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4), .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 200)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
        }
    }

    private var topChrome: some View {
        HStack(spacing: 8) {
            PlayerIconButton(systemName: "xmark") {
                if let overlayDismiss { overlayDismiss() } else { dismiss() }
            }
            .help("Close player (Esc)")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)

            Spacer()

            HStack(spacing: 4) {
                if let isFavorite, let onToggleFavorite {
                    PlayerIconButton(systemName: isFavorite ? "heart.fill" : "heart") {
                        onToggleFavorite()
                    }
                    .help("Toggle favorite")
                }

                if isLiveStream, !channelPanelSections.isEmpty {
                    PlayerIconButton(systemName: showSidePanel ? "rectangle.bottomthird.inset.filled" : "rectangle.split.3x1") {
                        withAnimation(.easeOut(duration: 0.22)) { showSidePanel.toggle() }
                    }
                    .help("Channel browser")
                }

                // Menüler ayrı, Equatable View'a çıkarıldı — player.position update'lerinde
                // re-evaluate olmasın diye. Aksi halde NSMenu highlight sıfırlanıyor.
                PlayerMenusBar(
                    audioTracks: audioTracks,
                    subtitleTracks: subtitleTracks,
                    videoTracks: videoTracks,
                    currentAudioId: $currentAudioId,
                    currentSubtitleId: $currentSubtitleId,
                    currentVideoId: $currentVideoId,
                    aspectRaw: $aspectRaw,
                    playbackRate: $playbackRateMirror,
                    showDebugOverlay: $showDebugOverlay,
                    onSelectAudio: { player.selectAudioTrack(id: $0) },
                    onSelectSubtitle: { player.selectSubtitleTrack(id: $0) },
                    onSelectVideo: { player.selectVideoTrack(id: $0) },
                    onSetPlaybackRate: { player.setPlaybackRate($0) },
                    onOpenSubtitleFile: { presentSubtitleOpenPanel() },
                    onOpenSubtitleSettings: { showSubtitleAppearance = true }
                )
                .equatable()

                PlayerIconButton(systemName: "arrow.up.left.and.arrow.down.right") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .help("Toggle full screen (⌃⌘F)")
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            if !isLiveStream, player.duration > 0 {
                PlayerTimeline(
                    value: Binding(
                        get: {
                            let total = max(player.duration, 1)
                            return isScrubbing ? scrubValue : min(player.position / total, 1)
                        },
                        set: { newRatio in
                            let total = max(player.duration, 1)
                            player.seek(to: newRatio * total)
                        }
                    ),
                    isSeekable: player.isSeekable,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing { hideTimer.task?.cancel() } else { armHideTimer() }
                    },
                    onDragValue: { ratio in scrubValue = ratio }
                )

                HStack {
                    Text(formatTime(isScrubbing ? scrubValue * player.duration : player.position))
                    Spacer()
                    Text("-\(formatTime(player.duration - (isScrubbing ? scrubValue * player.duration : player.position)))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            }

            // Transport butonları + volume — izole Equatable view, position update'lerinde
            // re-render olmaz; butonlar anlık tepki verir.
            PlayerTransportBar(
                isPaused: isPausedMirror,
                isBuffering: isBufferingMirror,
                isLiveStream: isLiveStream,
                canGoToPrevious: canGoToPreviousEpisode || canGoToPreviousChannel,
                canGoToNext: canGoToNextEpisode || canGoToNextChannel,
                volume: $volumeMirror,
                onPrevious: { onPreviousEpisode?(); onPreviousChannel?() },
                onNext: { onNextEpisode?(); onNextChannel?() },
                onSeekBack: { player.seek(to: max(player.position - 10, 0)) },
                onSeekForward: { player.seek(to: min(player.position + 10, max(player.duration, 0))) },
                onPlayPause: {
                    if isPausedMirror { player.play() } else { player.pause() }
                    armHideTimer()
                },
                onMute: { toggleMute() },
                onVolumeChange: { v in
                    player.setVolume(v)
                    savedVolume = v
                }
            )
            .equatable()
        }
    }

    private func toggleMute() {
        if volumeMirror > 0 {
            lastVolumeBeforeMute = volumeMirror
            player.setVolume(0); savedVolume = 0
        } else {
            let restore = lastVolumeBeforeMute > 0 ? lastVolumeBeforeMute : 50
            player.setVolume(restore); savedVolume = restore
        }
    }

    // MARK: - Menus + transport bar (PlayerMenusBar / PlayerTransportBar dosyanın sonunda)

    // MARK: - Helpers

    private func reloadTracks() {
        player.reloadTrackList { v, a, s, vid, aid, sid in
            videoTracks = v
            audioTracks = a
            subtitleTracks = s
            currentVideoId = vid
            currentAudioId = aid
            currentSubtitleId = sid
        }
    }

    private func armHideTimer() {
        hideTimer.task?.cancel()
        hideTimer.task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            if !isScrubbing {
                withAnimation(.easeInOut(duration: 0.25)) {
                    controlsVisible = false
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    // MARK: - Keyboard

    @ViewBuilder
    private var keyboardBridge: some View {
        VStack {
            Button("") {
                if player.isPaused { player.play() } else { player.pause() }
                showControlsBriefly()
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)

            Button("") {
                player.seek(to: max(player.position - 5, 0))
                showControlsBriefly()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(0)

            Button("") {
                player.seek(to: min(player.position + 5, max(player.duration, 0)))
                showControlsBriefly()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .opacity(0)

            Button("") {
                let v = min(player.volume + 5, 100)
                player.setVolume(v); savedVolume = v
                showControlsBriefly()
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .opacity(0)

            Button("") {
                let v = max(player.volume - 5, 0)
                player.setVolume(v); savedVolume = v
                showControlsBriefly()
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .opacity(0)

            Button("") {
                if let overlayDismiss { overlayDismiss() } else { dismiss() }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)

            Button("") {
                toggleMute()
                showControlsBriefly()
            }
            .keyboardShortcut("m", modifiers: [])
            .opacity(0)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    private func showControlsBriefly() {
        if !controlsVisible {
            withAnimation(.easeInOut(duration: 0.18)) { controlsVisible = true }
        }
        armHideTimer()
    }
}

// MARK: - Reusable button components

private struct PlayerIconButton: View {
    enum Size { case small, medium, large
        var box: CGFloat { switch self { case .small: 32; case .medium: 38; case .large: 44 } }
        var icon: CGFloat { switch self { case .small: 13; case .medium: 15; case .large: 18 } }
    }
    let systemName: String
    var size: Size = .small
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size.icon, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size.box, height: size.box)
                .background(
                    Circle()
                        .fill(hovering ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PlayPauseButton: View {
    let isPaused: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(hovering ? Color.white.opacity(0.22) : Color.white.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .onHover { hovering = $0 }
        .help(isPaused ? "Play (Space)" : "Pause (Space)")
    }
}

private struct PlayerMenu<MenuContent: View>: View {
    let systemName: String
    let help: String
    @ViewBuilder let content: () -> MenuContent
    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(hovering ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                )
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Video surface (native Metal display)

private struct VideoSurfaceContainer: NSViewRepresentable {
    @ObservedObject var player: MPVPlayer
    let gravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MetalVideoView {
        let view = MetalVideoView()
        view.videoGravity = gravity
        context.coordinator.attach(player: player, to: view)
        return view
    }

    func updateNSView(_ nsView: MetalVideoView, context: Context) {
        context.coordinator.attach(player: player, to: nsView)
        nsView.videoGravity = gravity
    }

    final class Coordinator {
        private weak var boundPlayer: MPVPlayer?
        private var didConfigure = false

        func attach(player: MPVPlayer, to view: MetalVideoView) {
            if didConfigure, boundPlayer === player { return }
            boundPlayer = player
            didConfigure = true
            player.configure(
                enableHardwareAcceleration: true,
                onVideoSizeChange: { _ in },
                onFrame: { [weak view] buffer, _, flip in
                    view?.enqueuePixelBuffer(buffer, flipVerticalForOpenGL: flip)
                }
            )
        }
    }
}

// MARK: - Window chrome control

/// Player açıkken NSWindow'un titlebar'ını şeffaflaştırıp içeriği altına yayar.
/// Trafik ışıkları görünür kalır; başlık metni gizlenir. View kaybolunca eski hali geri yüklenir.
struct PlayerWindowChrome: NSViewRepresentable {
    let immersive: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            context.coordinator.apply(immersive: immersive, on: v.window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.apply(immersive: immersive, on: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // View ortadan kalkarken eski state'i geri al.
        DispatchQueue.main.async {
            coordinator.restore(on: nsView.window)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var saved: SavedState?
        private struct SavedState {
            let titleVisibility: NSWindow.TitleVisibility
            let titlebarAppearsTransparent: Bool
            let styleMaskHadFullSize: Bool
        }

        func apply(immersive: Bool, on window: NSWindow?) {
            guard let window else { return }
            if immersive, saved == nil {
                saved = SavedState(
                    titleVisibility: window.titleVisibility,
                    titlebarAppearsTransparent: window.titlebarAppearsTransparent,
                    styleMaskHadFullSize: window.styleMask.contains(.fullSizeContentView)
                )
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                // Toolbar'a manuel dokunmuyoruz — SwiftUI'nin .toolbar(.hidden, for:
                // .windowToolbar) modifier'ı PlayerView body'sinde bu işi yapıyor.
                // Manuel müdahale dashboard'ın back button/title gibi item'larını
                // bozuyordu (player kapanınca kaybolma sebebi).
            } else if !immersive {
                restore(on: window)
            }
        }

        func restore(on window: NSWindow?) {
            guard let window, let s = saved else { return }
            window.titleVisibility = s.titleVisibility
            window.titlebarAppearsTransparent = s.titlebarAppearsTransparent
            if !s.styleMaskHadFullSize {
                window.styleMask.remove(.fullSizeContentView)
            }
            window.isMovableByWindowBackground = false
            saved = nil
        }
    }
}

// MARK: - PlayerTransportBar — izole transport butonları + volume

/// player.position 30+ Hz yayınladığı için parent View body sürekli re-evaluate olur.
/// Transport butonlarını burada Equatable diff ile koruruz; volume/isPaused/isBuffering
/// dışında değişen prop yoksa body atlanır, butonlar anlık tepki verir.
private struct PlayerTransportBar: View, Equatable {
    let isPaused: Bool
    let isBuffering: Bool
    let isLiveStream: Bool
    let canGoToPrevious: Bool
    let canGoToNext: Bool
    @Binding var volume: Double
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeekBack: () -> Void
    let onSeekForward: () -> Void
    let onPlayPause: () -> Void
    let onMute: () -> Void
    let onVolumeChange: (Double) -> Void

    static func == (lhs: PlayerTransportBar, rhs: PlayerTransportBar) -> Bool {
        lhs.isPaused == rhs.isPaused
            && lhs.isBuffering == rhs.isBuffering
            && lhs.isLiveStream == rhs.isLiveStream
            && lhs.canGoToPrevious == rhs.canGoToPrevious
            && lhs.canGoToNext == rhs.canGoToNext
            && lhs.volume == rhs.volume
    }

    private var volumeIcon: String {
        switch volume {
        case 0:       return "speaker.slash.fill"
        case 1...33:  return "speaker.wave.1.fill"
        case 34...66: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if canGoToPrevious {
                PlayerIconButton(systemName: "backward.end.fill", size: .medium, action: onPrevious)
                    .help(isLiveStream ? "Previous channel" : "Previous episode")
            }
            if !isLiveStream {
                PlayerIconButton(systemName: "gobackward.10", size: .medium, action: onSeekBack)
                    .help("Back 10 seconds")
            }
            PlayPauseButton(isPaused: isPaused, action: onPlayPause)
            if !isLiveStream {
                PlayerIconButton(systemName: "goforward.10", size: .medium, action: onSeekForward)
                    .help("Forward 10 seconds")
            }
            if canGoToNext {
                PlayerIconButton(systemName: "forward.end.fill", size: .medium, action: onNext)
                    .help(isLiveStream ? "Next channel" : "Next episode")
            }

            Spacer()

            if isBuffering {
                ProgressView().controlSize(.small).tint(.white)
            }

            HStack(spacing: 8) {
                Button(action: onMute) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Mute / unmute (M)")

                Slider(value: Binding(
                    get: { volume },
                    set: { v in
                        volume = v
                        onVolumeChange(v)
                    }
                ), in: 0...100)
                .tint(.white)
                .frame(width: 110)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - PlayerMenusBar — izole Menu grubu

/// Player'ın @ObservedObject güncelleme döngüsünden bağımsız menu bar.
/// `Equatable` ile, parent body re-evaluate olduğunda gerçekten değişen prop olmadıkça
/// re-render edilmez; bu sayede `player.position` her yayında NSMenu highlight'ı sıfırlanmaz.
private struct PlayerMenusBar: View, Equatable {
    let audioTracks: [TrackMenuOption]
    let subtitleTracks: [TrackMenuOption]
    let videoTracks: [TrackMenuOption]
    @Binding var currentAudioId: Int
    @Binding var currentSubtitleId: Int
    @Binding var currentVideoId: Int
    @Binding var aspectRaw: String
    @Binding var playbackRate: Double
    @Binding var showDebugOverlay: Bool
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int) -> Void
    let onSelectVideo: (Int) -> Void
    let onSetPlaybackRate: (Double) -> Void
    /// External SRT/SUB dosyası seçim diyalogu açar. Yüklenen dosya mpv'ye `sub-add ... select`
    /// ile eklenir; dosya açılınca menüdeki Subtitle picker otomatik yeni ID'yi reflect eder.
    let onOpenSubtitleFile: () -> Void
    /// Subtitle appearance sheet'i (font/size/color/outline/delay) açar.
    let onOpenSubtitleSettings: () -> Void

    static func == (lhs: PlayerMenusBar, rhs: PlayerMenusBar) -> Bool {
        lhs.audioTracks == rhs.audioTracks
            && lhs.subtitleTracks == rhs.subtitleTracks
            && lhs.videoTracks == rhs.videoTracks
            && lhs.currentAudioId == rhs.currentAudioId
            && lhs.currentSubtitleId == rhs.currentSubtitleId
            && lhs.currentVideoId == rhs.currentVideoId
            && lhs.aspectRaw == rhs.aspectRaw
            && lhs.playbackRate == rhs.playbackRate
            && lhs.showDebugOverlay == rhs.showDebugOverlay
    }

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        HStack(spacing: 4) {
            tracksMenu
            aspectMenu
            speedMenu
        }
    }

    private var tracksMenu: some View {
        PlayerMenu(systemName: "captions.bubble", help: "Audio, subtitles, video tracks") {
            if !audioTracks.isEmpty {
                Picker("Audio", selection: Binding(
                    get: { currentAudioId },
                    set: { id in currentAudioId = id; onSelectAudio(id) }
                )) {
                    ForEach(audioTracks) { Text($0.title).tag($0.id) }
                }
            }
            if subtitleTracks.count > 1 {
                Picker("Subtitle", selection: Binding(
                    get: { currentSubtitleId },
                    set: { id in currentSubtitleId = id; onSelectSubtitle(id) }
                )) {
                    ForEach(subtitleTracks) { Text($0.title).tag($0.id) }
                }
            }
            if videoTracks.count > 1 {
                Picker("Video", selection: Binding(
                    get: { currentVideoId },
                    set: { id in currentVideoId = id; onSelectVideo(id) }
                )) {
                    ForEach(videoTracks) { Text($0.title).tag($0.id) }
                }
            }
            Divider()
            Button(L("subtitle.open_external_file")) { onOpenSubtitleFile() }
            Button(L("subtitle.open_appearance")) { onOpenSubtitleSettings() }
        }
    }

    private var aspectMenu: some View {
        PlayerMenu(systemName: "rectangle.expand.vertical", help: "Video aspect") {
            Picker("Aspect", selection: $aspectRaw) {
                ForEach(VideoAspectMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
        }
    }

    private var speedMenu: some View {
        PlayerMenu(systemName: "gauge.with.dots.needle.bottom.50percent", help: "Playback speed & debug") {
            Picker("Speed", selection: Binding(
                get: { playbackRate },
                set: { v in playbackRate = v; onSetPlaybackRate(v) }
            )) {
                ForEach(speeds, id: \.self) { s in
                    Text(String(format: "%.2fx", s)).tag(s)
                }
            }
            Divider()
            Toggle("Debug overlay", isOn: $showDebugOverlay)
        }
    }
}

// MARK: - PlayerDebugOverlay

/// iOS PlayerView'deki debug paneli karşılığı. mpv'nin yayınladığı oynatma metriklerini
/// gerçek zamanlı gösterir; sağ-üstte yarı şeffaf panel.
private struct PlayerDebugOverlay: View {
    @ObservedObject var player: MPVPlayer

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            line("RES",  resolution)
            line("FPS",  fps)
            line("BR",   bitrate)
            line("DROP", "D:\(player.droppedFrameCount) R:\(player.delayedFrameCount)")
            line("BUF",  buffer)
            line("AV",   String(format: "%+0.3fs", player.avSyncSeconds))
            line("NET",  formatBitrate(player.networkSpeedBps) + "/s")
            line("DEC",  "\(decoder) \(codec)")
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func line(_ tag: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(tag)
                .foregroundStyle(.white.opacity(0.5))
                .frame(minWidth: 32, alignment: .trailing)
            Text(value)
        }
    }

    private var resolution: String {
        guard player.videoDisplayWidth > 0, player.videoDisplayHeight > 0 else { return "--" }
        return "\(player.videoDisplayWidth)x\(player.videoDisplayHeight)"
    }

    private var fps: String {
        let r = player.renderFPS, s = player.streamFPS
        if r > 0, s > 0 { return String(format: "%.2f/%.2f", r, s) }
        if r > 0 { return String(format: "%.2f", r) }
        if s > 0 { return String(format: "%.2f", s) }
        return "--"
    }

    private var bitrate: String {
        formatBitrate(player.videoBitrate)
    }

    private var buffer: String {
        let pct = max(0, min(100, player.cacheBufferingState))
        let sec = max(player.cacheDurationSeconds, 0)
        let state: String
        if player.isBuffering      { state = "REFILL" }
        else if player.isPaused    { state = "PAUSE" }
        else if player.isReady     { state = "OK" }
        else                       { state = "IDLE" }
        return String(format: "%@ %.1fs %.0f%%", state, sec, pct)
    }

    private var decoder: String {
        player.hwdecCurrent.isEmpty ? "sw" : player.hwdecCurrent
    }

    private var codec: String {
        player.videoCodecName.isEmpty ? "--" : player.videoCodecName
    }

    private func formatBitrate(_ bps: Double) -> String {
        guard bps > 0 else { return "--" }
        if bps >= 1_000_000 { return String(format: "%.1fM", bps / 1_000_000) }
        if bps >= 1_000     { return String(format: "%.0fK", bps / 1_000) }
        return String(format: "%.0f", bps)
    }
}

// MARK: - LiveChannelSidePanel (iOS portu — pure SwiftUI)

struct LiveChannelSidePanel: View {
    let sections: [ChannelPanelSection]
    let currentItemId: String?
    let onSelectChannel: (String) -> Void

    @State private var selectedCategoryId: String

    init(
        sections: [ChannelPanelSection],
        currentItemId: String?,
        onSelectChannel: @escaping (String) -> Void
    ) {
        self.sections = sections
        self.currentItemId = currentItemId
        self.onSelectChannel = onSelectChannel
        let initialId: String = {
            if let cid = currentItemId,
               let match = sections.first(where: { section in
                   section.items.contains(where: { $0.id == cid })
               }) {
                return match.id
            }
            return sections.first?.id ?? ""
        }()
        _selectedCategoryId = State(initialValue: initialId)
    }

    private var activeItems: [ChannelPanelItem] {
        sections.first(where: { $0.id == selectedCategoryId })?.items ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            categoryPicker
            channelStrip
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.55))
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.white.opacity(0.18))
        }
        .contentShape(Rectangle())
    }

    private var categoryPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(sections) { section in
                        Button {
                            selectedCategoryId = section.id
                        } label: {
                            Text(section.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selectedCategoryId == section.id ? Color.accentColor : Color.white.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .id(section.id)
                    }
                }
                .padding(.horizontal, 14)
            }
            .onAppear { scrollToSelectedCategory(proxy: proxy) }
            .onChange(of: selectedCategoryId) { _, _ in
                scrollToSelectedCategory(proxy: proxy)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func scrollToSelectedCategory(proxy: ScrollViewProxy) {
        guard sections.contains(where: { $0.id == selectedCategoryId }) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(selectedCategoryId, anchor: .center)
            }
        }
    }

    private var channelStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(activeItems) { item in
                        channelCard(item: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(height: 104)
            .onAppear { scrollToCurrent(proxy: proxy) }
            .onChange(of: selectedCategoryId) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: currentItemId) { _, _ in
                syncCategoryToCurrentIfNeeded()
                scrollToCurrent(proxy: proxy)
            }
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        guard let cid = currentItemId,
              activeItems.contains(where: { $0.id == cid }) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(cid, anchor: .center)
            }
        }
    }

    private func syncCategoryToCurrentIfNeeded() {
        guard let cid = currentItemId else { return }
        guard let section = sections.first(where: { $0.items.contains(where: { $0.id == cid }) }) else { return }
        if selectedCategoryId != section.id {
            selectedCategoryId = section.id
        }
    }

    private func channelCard(item: ChannelPanelItem) -> some View {
        let isCurrent = item.id == currentItemId
        return Button {
            onSelectChannel(item.id)
        } label: {
            VStack(alignment: .center, spacing: 6) {
                CachedImage(
                    url: item.iconURL,
                    width: 56,
                    height: 56,
                    cornerRadius: 10,
                    iconName: "tv",
                    loadProfile: .standard
                )
                Text(item.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subtitle appearance sheet
//
// macOS native subtitle appearance editor. Ayarlar `playback.subtitleAppearance.v2`
// UserDefaults key'inde JSON olarak persist edilir ve aktif MPVPlayer'a
// `applySubtitleAppearanceFromSettings(_:)` üzerinden uygulanır. Delay slider'ı drag
// esnasında live apply edilir (kullanıcı altyazıyı playback'e göre sync'lerken anlık
// geri besleme alır); diğer ayarlar Apply'a kadar bekler ki tweaking sırasında
// `sub-ass-override` rewrite maliyeti her frame'de ödenmesin.
struct SubtitleAppearanceSheet: View {
    @ObservedObject var player: MPVPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SubtitleAppearanceSettings
    @State private var initial: SubtitleAppearanceSettings

    init(player: MPVPlayer) {
        self.player = player
        let loaded = SubtitleAppearancePersistence.load()
        _draft = State(initialValue: loaded)
        _initial = State(initialValue: loaded)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("subtitle.settings_title"))
                    .font(.headline)
                Spacer()
                Button(L("subtitle.reset")) { draft = .default }
                    .disabled(draft == .default)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SubtitlePreviewCard(settings: draft)
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    sectionBox(title: L("subtitle.font_settings")) {
                        sliderRow(label: L("subtitle.font_size"),
                                  value: Binding(get: { Double(draft.fontSize) },
                                                 set: { draft.fontSize = Int($0.rounded()) }),
                                  range: Double(SubtitleAppearanceSettings.fontSizeRange.lowerBound)...Double(SubtitleAppearanceSettings.fontSizeRange.upperBound),
                                  step: 1,
                                  display: { "\(Int($0)) px" })
                        sliderRow(label: L("subtitle.font_height"),
                                  value: $draft.lineHeight,
                                  range: SubtitleAppearanceSettings.lineHeightRange,
                                  step: 0.05,
                                  display: { String(format: "%.2fx", $0) })
                        sliderRow(label: L("subtitle.letter_spacing"),
                                  value: $draft.letterSpacing,
                                  range: SubtitleAppearanceSettings.letterSpacingRange,
                                  step: 0.1,
                                  display: { String(format: "%.1f", $0) })
                        sliderRow(label: L("subtitle.padding"),
                                  value: Binding(get: { Double(draft.padding) },
                                                 set: { draft.padding = Int($0.rounded()) }),
                                  range: Double(SubtitleAppearanceSettings.paddingRange.lowerBound)...Double(SubtitleAppearanceSettings.paddingRange.upperBound),
                                  step: 1,
                                  display: { "\(Int($0)) px" })
                        HStack {
                            Text(L("subtitle.font_weight")).frame(width: 110, alignment: .leading)
                            Picker(L("subtitle.font_weight"), selection: $draft.fontWeight) {
                                ForEach(SubtitleFontWeight.allCases) { w in Text(w.shortLabel).tag(w) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        Toggle(L("subtitle.italic"), isOn: $draft.italic)
                    }

                    sectionBox(title: L("subtitle.colors")) {
                        ColorPicker(L("subtitle.text_color"),
                                    selection: Binding(get: { Color(subHex6: draft.textColorHex6) },
                                                       set: { draft.textColorHex6 = $0.toSubHex6() }),
                                    supportsOpacity: false)
                        Toggle(L("subtitle.background_box"), isOn: $draft.backgroundEnabled)
                        if draft.backgroundEnabled {
                            ColorPicker(L("subtitle.background_color"),
                                        selection: Binding(get: { Color(subHex6: draft.backgroundColorHex6) },
                                                           set: { draft.backgroundColorHex6 = $0.toSubHex6() }),
                                        supportsOpacity: false)
                            sliderRow(label: L("subtitle.background_opacity"),
                                      value: $draft.backgroundOpacity,
                                      range: SubtitleAppearanceSettings.backgroundOpacityRange,
                                      step: 0.05,
                                      display: { "\(Int(($0 * 100).rounded()))%" })
                        }
                    }

                    sectionBox(title: L("subtitle.text_align")) {
                        HStack {
                            Text(L("subtitle.text_align")).frame(width: 110, alignment: .leading)
                            Picker(L("subtitle.text_align"), selection: $draft.textAlignment) {
                                ForEach(SubtitleTextAlignment.allCases) { a in
                                    Image(systemName: a.iconName).tag(a)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        sliderRow(label: L("subtitle.vertical_offset"),
                                  value: Binding(get: { Double(draft.verticalOffset) },
                                                 set: { draft.verticalOffset = Int($0.rounded()) }),
                                  range: Double(SubtitleAppearanceSettings.verticalOffsetRange.lowerBound)...Double(SubtitleAppearanceSettings.verticalOffsetRange.upperBound),
                                  step: 4,
                                  display: { v in
                                      let i = Int(v)
                                      if i == 0 { return "0 px" }
                                      return i > 0 ? "+\(i) px" : "\(i) px"
                                  })
                    }

                    sectionBox(title: L("subtitle.outline_position")) {
                        sliderRow(label: L("subtitle.outline_size"),
                                  value: $draft.outlineSize,
                                  range: SubtitleAppearanceSettings.outlineSizeRange,
                                  step: 0.5,
                                  display: { String(format: "%.1f", $0) })
                        ColorPicker(L("subtitle.outline_color"),
                                    selection: Binding(get: { Color(subHex6: draft.outlineColorHex6) },
                                                       set: { draft.outlineColorHex6 = $0.toSubHex6() }),
                                    supportsOpacity: false)
                    }

                    sectionBox(title: L("subtitle.timing")) {
                        sliderRow(label: L("subtitle.delay"),
                                  value: $draft.delaySeconds,
                                  range: SubtitleAppearanceSettings.delaySecondsRange,
                                  step: 0.1,
                                  display: { s in
                                      if abs(s) < 0.05 { return "0.0 s" }
                                      let sign = s > 0 ? "+" : ""
                                      return "\(sign)\(String(format: "%.1f", s)) s"
                                  })
                        Text(L("subtitle.delay.footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Divider()

            HStack {
                Spacer()
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("subtitle.apply")) {
                    var clamped = draft
                    clamped.clamp()
                    SubtitleAppearancePersistence.save(clamped)
                    player.applySubtitleAppearanceFromSettings(clamped)
                    player.setSubDelay(seconds: clamped.delaySeconds)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == initial)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 600)
        .onChange(of: draft.delaySeconds) { _, new in
            player.setSubDelay(seconds: new)
        }
    }

    @ViewBuilder
    private func sectionBox<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private func sliderRow(label: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           display: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct SubtitlePreviewCard: View {
    let settings: SubtitleAppearanceSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.19, blue: 0.28),
                         Color(red: 0.05, green: 0.06, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            Text("Lorem ipsum dolor sit amet")
                .font(.system(size: previewSize, weight: previewWeight, design: .default))
                .italic(settings.italic)
                .kerning(CGFloat(settings.letterSpacing))
                .multilineTextAlignment(previewTextAlignment)
                .foregroundStyle(Color(subHex6: settings.textColorHex6))
                .shadow(color: Color(subHex6: settings.outlineColorHex6).opacity(settings.outlineSize > 0 ? 0.95 : 0),
                        radius: CGFloat(settings.outlineSize), x: 0, y: 0)
                .padding(.horizontal, CGFloat(settings.padding))
                .padding(.vertical, 4)
                .background(
                    Group {
                        if settings.backgroundEnabled {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(subHex6: settings.backgroundColorHex6).opacity(settings.backgroundOpacity))
                        }
                    }
                )
                .offset(y: CGFloat(-settings.verticalOffset))
                .padding(.bottom, 12)
        }
    }

    private var previewSize: CGFloat { CGFloat(min(settings.fontSize, 32)) * 0.85 }

    private var previewWeight: Font.Weight {
        switch settings.fontWeight {
        case .thin: return .thin
        case .normal: return .regular
        case .medium: return .medium
        case .bold: return .bold
        case .extraBold: return .heavy
        }
    }

    private var previewTextAlignment: TextAlignment {
        switch settings.textAlignment {
        case .left: return .leading
        case .right: return .trailing
        case .center, .justify: return .center
        }
    }
}

private extension Color {
    /// Initializer'a ad çakışmasını önlemek için `subHex6:` etiketi: sıradan UInt32
    /// init overload'ları ile karışmaz.
    init(subHex6: UInt32) {
        let r = Double((subHex6 >> 16) & 0xFF) / 255.0
        let g = Double((subHex6 >> 8) & 0xFF) / 255.0
        let b = Double(subHex6 & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// `Color` → 24-bit RGB hex. Alpha kanalı dahil değil; NSColor sRGB üzerinden çevirir.
    func toSubHex6() -> UInt32 {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = UInt32(max(0, min(1, ns.redComponent)) * 255)
        let g = UInt32(max(0, min(1, ns.greenComponent)) * 255)
        let b = UInt32(max(0, min(1, ns.blueComponent)) * 255)
        return (r << 16) | (g << 8) | b
    }
}
