import AVKit
import Combine
import SwiftUI
import GRDB
import UIKit
import os

struct LiveChannelCategorySection: Identifiable, Equatable {
    let id: String
    let title: String
    let streams: [DBLiveStream]
}

/// Kanal panelinin Xtream `DBLiveStream` veya M3U `DBM3UChannel` gibi farklı kaynaklarla çalışabilmesi için
/// hafif bir görüntüleme modelidir. Tıklamalar item `id`'sini callback'e verir; aranması/akışın seçilmesi
/// çağıranın sorumluluğundadır.
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

/// Kanal tarayıcısı kapandıktan sonra ana mpv/UIKit köprüsünü tazelemek için iç gövdeyi `.id` ile yeniden oluşturur.
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

    /// Favori UI — nil ise buton gizli (Xtream şu an kullanmıyor).
    var isFavorite: Bool? = nil
    var onToggleFavorite: (() -> Void)? = nil

    @State private var channelBrowserVolumeBackup: Double?

    var body: some View {
        PlayerViewImpl(
            url: url,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            isLiveStream: isLiveStream,
            playlistId: playlistId,
            streamId: streamId,
            type: type,
            seriesId: seriesId,
            resumeTimeMs: resumeTimeMs,
            containerExtension: containerExtension,
            isFavorite: isFavorite,
            onToggleFavorite: onToggleFavorite,
            canGoToPreviousEpisode: canGoToPreviousEpisode,
            canGoToNextEpisode: canGoToNextEpisode,
            onPreviousEpisode: onPreviousEpisode,
            onNextEpisode: onNextEpisode,
            canGoToPreviousChannel: canGoToPreviousChannel,
            canGoToNextChannel: canGoToNextChannel,
            onPreviousChannel: onPreviousChannel,
            onNextChannel: onNextChannel,
            channelPanelSections: channelPanelSections,
            currentChannelPanelItemId: currentChannelPanelItemId,
            onSelectChannelPanelItem: onSelectChannelPanelItem,
            isLiveChannelSidePanelVisible: isLiveChannelSidePanelVisible,
            onToggleLiveChannelSidePanel: onToggleLiveChannelSidePanel,
            onVideoSurfaceTap: onVideoSurfaceTap,
            onNavigateToDetail: onNavigateToDetail,
            volumeBackupDuringChannelBrowser: $channelBrowserVolumeBackup,
            onLiveChannelBrowserClosed: {}
        )
    }
}

private struct PlayerViewImpl: View {
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

    /// Opsiyonel favori butonu — yalnız ikisi de set ise topChrome'da gösterilir.
    var isFavorite: Bool? = nil
    var onToggleFavorite: (() -> Void)? = nil

    /// Dizi oynatırken playlist sırasına göre önceki / sonraki bölüm (UI + Kontrol Merkezi).
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

    @Binding var volumeBackupDuringChannelBrowser: Double?
    var onLiveChannelBrowserClosed: () -> Void

    @StateObject private var player = VideoPlayerController()
    @StateObject private var subtitleManager = SubtitleManager()
    @StateObject private var systemVolumeBridge = SystemVolumeBridge()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerOverlayDismiss) private var playerOverlayDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var showControls = true
    @State private var timer: Timer?
    @State private var saveHistoryTimer: Timer?
    @State private var hasInitialSeeked = false
    @AppStorage("player.debugOverlayEnabled") private var showDebugOverlay = false
    @AppStorage("player.videoAspectMode") private var videoAspectModeRaw = VideoAspectMode.bestFit.rawValue
    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continuePlayingInBackground = true
    @AppStorage("player.speedUpOnLongPress") private var speedUpOnLongPress = true

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var lockedSliderValue: Double?
    @State private var sliderUnlockGeneration = 0
    @State private var showTrackSettings = false
    @State private var showSubtitleAppearance = false
    @State private var isFastForwarding = false
    @State private var pipManualSignal = 0
    @State private var bitrateSamples: [(time: Date, bps: Double)] = []
    @State private var aspectToastText: String?
    @State private var aspectToastToken: UInt64 = 0

    /// Tam ekran kapak: kenardan geri (pop) ve aşağı çekerek kapatma.
    private enum InteractiveDismissAxis {
        case edgeBack
        case pullDown
    }

    @State private var interactiveDismissAxis: InteractiveDismissAxis?
    @State private var interactiveDismissOffset: CGSize = .zero

    /// İki parmak pinch: 1x–4x; yakınlaştırınca tek parmakla sürükleyerek kadraj kaydırılabilir.
    /// Pinch & pan UIKit tarafında (`PlayerMediaKitTouchContainerView`); koordinat sistemi
    /// scaled view'a bağlı olmadığı için drag güvenilir. Pinch midpoint anchor için aşağıdaki
    /// `pinchAnchorState` kullanılır.
    @State private var videoPinchBase: CGFloat = 1
    @State private var videoPinchLive: CGFloat = 1
    @State private var videoPanCommitted: CGSize = .zero
    @State private var videoPanLive: CGSize = .zero
    @State private var videoViewportSize: CGSize = .zero
    @State private var pinchAnchorState: PinchAnchorState?

    /// Pinch başlarken çekilen snapshot: zoomu pinch midpoint'ten yapmak için offset
    /// hesaplamasına ihtiyaç duyulan tüm sabit değerler.
    private struct PinchAnchorState: Equatable {
        let screenMidpoint: CGPoint  // UIKit container (= playerChrome) koordinatları
        let containerCenter: CGPoint
        let startScale: CGFloat
        let startPanCommitted: CGSize
    }

    /// Son yüklenen içerik; `streamId`/URL değişince önce bununla geçmiş kaydedilir (yeni struct alanları henüz güncellenmiş olabilir).
    @State private var historySaveTags: WatchHistoryTags?
    @State private var appliedPlaybackIdentity: String?
    /// Altyazı `update()` binary search + eşitlik kontrolü yapıyor, ama yine de her 120ms
    /// tetiklemek onChange closure kadar küçük bir yük. 200ms pencere imperceptible.
    @State private var lastSubtitleUpdateMs: Int64 = 0

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "another-iptv-player", category: "Playback")

    private let videoZoomMax: CGFloat = 4

    private var videoZoomScale: CGFloat {
        min(max(videoPinchBase * videoPinchLive, 1), videoZoomMax)
    }

    /// Yalnızca committed + live pan'ı valid range'e clamp eder. `videoEffectiveOffset` tüm
    /// bileşenleri birleşik şekilde clamp ettiği için gesture sırasında kullanılmaz; pinch end'de
    /// committed pan'ı tekrar clamp etmek için `commitVideoPanClamp` kullanır.
    private var videoPanClamped: CGSize {
        let maxX = max(0, (videoViewportSize.width * (videoZoomScale - 1)) / 2)
        let maxY = max(0, (videoViewportSize.height * (videoZoomScale - 1)) / 2)
        let raw = CGSize(
            width: videoPanCommitted.width + videoPanLive.width,
            height: videoPanCommitted.height + videoPanLive.height
        )
        return CGSize(
            width: min(max(raw.width, -maxX), maxX),
            height: min(max(raw.height, -maxY), maxY)
        )
    }

    /// Pinch anchor (pinch midpoint'ten zoomlamak için) compensating offset.
    /// Scale center'dan olduğu için, parmak altında kalması istenen noktayı sabitlemek üzere
    /// delta döner. Pinch end'de değer `videoPanCommitted`'a bake edilir ve bu fonksiyon sıfır döner.
    private var videoPinchZoomOffset: CGSize {
        guard let s = pinchAnchorState else { return .zero }
        let M = s.screenMidpoint
        let C = s.containerCenter
        let S0 = s.startScale
        let O0 = s.startPanCommitted
        // Pinch başındaki content noktası (center'a göreli, unscaled):
        let Px = (M.x - C.x - O0.width) / S0
        let Py = (M.y - C.y - O0.height) / S0
        // Yeni ölçekte noktayı aynı ekran konumunda tutmak için gereken mutlak offset:
        let S = videoZoomScale
        let Ox = M.x - C.x - S * Px
        let Oy = M.y - C.y - S * Py
        // `videoPanCommitted` start değerine göre delta:
        return CGSize(width: Ox - O0.width, height: Oy - O0.height)
    }

    /// Gerçek offset: committed pan + live pan + pinch zoom offset hepsi birlikte **current
    /// scale'e göre clamp** edilir. Zoom out sırasında max offset küçülür ve içerik viewport
    /// sınırında kalır — eskiden zoom offset ayrı eklendiği için dışarı taşabiliyordu.
    private var videoEffectiveOffset: CGSize {
        let rawX = videoPanCommitted.width + videoPanLive.width + videoPinchZoomOffset.width
        let rawY = videoPanCommitted.height + videoPanLive.height + videoPinchZoomOffset.height
        let maxX = max(0, (videoViewportSize.width * (videoZoomScale - 1)) / 2)
        let maxY = max(0, (videoViewportSize.height * (videoZoomScale - 1)) / 2)
        return CGSize(
            width: min(max(rawX, -maxX), maxX),
            height: min(max(rawY, -maxY), maxY)
        )
    }

    private var playbackPresentationKey: String {
        [title, subtitle ?? "", artworkURL?.absoluteString ?? "", isLiveStream ? "1" : "0"]
            .joined(separator: "\u{1e}")
    }

    private var showSeriesEpisodeSkip: Bool {
        type == "series" && (onPreviousEpisode != nil || onNextEpisode != nil)
    }

    private var showLiveChannelSkip: Bool {
        isLiveStream && (onPreviousChannel != nil || onNextChannel != nil)
    }

    private var showLiveChannelListButton: Bool {
        isLiveStream && !channelPanelSections.isEmpty && onToggleLiveChannelSidePanel != nil
    }

    private var showVODQueueSkip: Bool {
        !isLiveStream && type == "vod" && (onPreviousChannel != nil || onNextChannel != nil)
    }

    private var hasPlaybackFailure: Bool {
        !(player.playbackFailureMessage ?? "").isEmpty
    }

    /// Orta tuşta bekleme göstergesi: mpv `pause=no` olsa bile gerçek pipeline (`FILE_LOADED` / `PLAYBACK_RESTART`) gelene kadar.
    /// Bitişte `END_FILE` kurulum bayrağını sıfırlar; bu durumda yükleniyor değil yeniden oynat gösterilir.
    private var isCenterTransportLoading: Bool {
        if hasPlaybackFailure { return false }
        if player.state == .ended { return false }
        if !player.mpvEngine.isReady { return true }
        if player.state == .buffering { return true }
        if !player.mpvEngine.isPlaybackEstablished { return true }
        return false
    }

    private var seriesRemoteCommandsKey: String {
        "\(streamId)|\(type)|\(canGoToPreviousEpisode ? "1" : "0")|\(canGoToNextEpisode ? "1" : "0")|\(onPreviousEpisode != nil)|\(onNextEpisode != nil)|\(canGoToPreviousChannel ? "1" : "0")|\(canGoToNextChannel ? "1" : "0")"
    }

    private var selectedAspectMode: VideoAspectMode {
        VideoAspectMode(rawValue: videoAspectModeRaw) ?? .bestFit
    }

    private var nextAspectMode: VideoAspectMode {
        let all = VideoAspectMode.allCases
        guard let idx = all.firstIndex(of: selectedAspectMode) else { return .bestFit }
        return all[(idx + 1) % all.count]
    }

    private var sourceVideoAspectRatio: CGFloat {
        let w = CGFloat(player.videoWidth)
        let h = CGFloat(player.videoHeight)
        guard w > 0, h > 0 else { return 16.0 / 9.0 }
        return w / h
    }

    private func fittedVideoSize(in viewport: CGSize) -> CGSize {
        let vw = max(viewport.width, 0)
        let vh = max(viewport.height, 0)
        guard vw > 0, vh > 0 else { return .zero }
        switch selectedAspectMode {
        case .center:
            // Kaynak boyutu center: mümkünse 1:1, sığmıyorsa küçült.
            let displayScale = max(UIScreen.main.scale, 1)
            let sourceWPoints = max(CGFloat(player.videoWidth) / displayScale, 1)
            let sourceHPoints = max(CGFloat(player.videoHeight) / displayScale, 1)
            let scale = min(vw / sourceWPoints, vh / sourceHPoints, 1)
            return CGSize(width: sourceWPoints * scale, height: sourceHPoints * scale)
        default:
            let ratio = max(selectedAspectMode.preferredAspectRatio ?? sourceVideoAspectRatio, 0.01)
            let viewportRatio = vw / vh
            if viewportRatio > ratio {
                return CGSize(width: vh * ratio, height: vh)
            }
            return CGSize(width: vw, height: vw / ratio)
        }
    }

    /// Aynı `PlayerView` örneğinde başka videoya geçişi tanır (`onAppear` yalnızca ilk açılışta çalışır).
    private var playbackIdentity: String {
        "\(streamId)\u{1e}\(url.absoluteString)"
    }

    private var displayedSliderPosition: Double {
        if isScrubbing { return scrubValue }
        if let locked = lockedSliderValue { return locked }
        let p = player.position
        guard p.isFinite else { return 0 }
        return Double(min(max(p, 0), 1))
    }

    private var effectiveSeekable: Bool {
        !isLiveStream && player.isSeekable
    }

    private var playbackDebugResolutionText: String {
        guard player.videoWidth > 0, player.videoHeight > 0 else { return "--" }
        return "\(player.videoWidth)x\(player.videoHeight)"
    }

    private var playbackDebugFpsText: String {
        let render = player.renderFPS
        let stream = player.streamFPS
        if render > 0, stream > 0 {
            return String(format: "%.2f/%.2f", render, stream)
        }
        if render > 0 { return String(format: "%.2f", render) }
        if stream > 0 { return String(format: "%.2f", stream) }
        return "--"
    }

    private var playbackDebugBitrateText: String {
        let values = bitrateSamples.map(\.bps).filter { $0 > 0 }
        guard !values.isEmpty else { return "--" }
        let avg = values.reduce(0, +) / Double(values.count)
        let minV = values.min() ?? avg
        let maxV = values.max() ?? avg
        return "\(formatBitrate(avg)) (\(formatBitrate(minV))-\(formatBitrate(maxV)))"
    }

    private var playbackDebugFramesText: String {
        "D:\(player.droppedFrameCount) R:\(player.delayedFrameCount)"
    }

    private var playbackDebugCacheText: String {
        let pct = max(0, min(100, player.cacheBufferingState))
        let sec = max(player.cacheDurationSeconds, 0)
        let ahead = max(player.cacheAheadSeconds, 0)
        let state: String
        switch player.state {
        case .buffering: state = "REFILL"
        case .playing: state = "OK"
        default: state = "IDLE"
        }
        return String(format: "BUF %@ A:%.1fs C:%.1fs %.0f%%", state, ahead, sec, pct)
    }

    private var playbackDebugAvSyncText: String {
        String(format: "AV %+0.3fs", player.avSyncSeconds)
    }

    private var playbackDebugNetText: String {
        let bps = max(player.networkSpeedBps, 0)
        return "NET \(formatBitrate(bps))/s"
    }

    private var playbackDebugCodecText: String {
        let hw = player.hwdecCurrent.isEmpty ? "sw" : player.hwdecCurrent
        let codec = player.videoCodecName.isEmpty ? "--" : player.videoCodecName
        return "DEC \(hw) \(codec)"
    }

    private var playbackDebugSeekText: String {
        let ms = player.seekLatencyMs
        return ms >= 0 ? "SEEK \(ms)ms" : "SEEK --"
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { displayedSliderPosition },
            set: { newVal in if isScrubbing { scrubValue = newVal } }
        )
    }

    private func performPlayerDismiss() {
        if let overlayDismiss = playerOverlayDismiss {
            overlayDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let outerSafeAreaInsets = geo.safeAreaInsets
            ZStack {
                Color.black
                    .ignoresSafeArea()

                playerChromeAndVideo(outerSafeAreaInsets: outerSafeAreaInsets)
            }
            .background(Color.black)
            .frame(width: containerSize.width, height: containerSize.height)
            .offset(interactiveDismissOffset)
            .opacity(interactiveDismissOpacity(containerSize: containerSize))
            .simultaneousGesture(
                interactiveDismissDragGesture(
                    containerSize: containerSize,
                    safeAreaTop: geo.safeAreaInsets.top,
                    safeAreaBottom: geo.safeAreaInsets.bottom
                )
            )
            // iPad / geniş yatay düzende durum çubuğunu kontrollerle aç-kapa yapmak üst güvenli alanı
            // değiştirir; GeometryReader yüksekliği sıçrar. Telefonda (compact) eski davranış korunur.
            .statusBarHidden(horizontalSizeClass == .compact ? !showControls : true)
        .onAppear {
            log.info("Opening player: \(title, privacy: .public)")
            resetTimer()
            player.setupAudioHandler()
            // Bir sonraki run loop: `MPVPlayerPlaybackContainerView` `viewDidLoad` → `configure` sırası SwiftUI sürümüne göre değişebilir;
            // aynı tick’te `play` önce gelirse `mpv` henüz yokken yükleme atlanabilir. Ayrıca ilk layout ana kuyruğu rahatlatır.
            DispatchQueue.main.async {
                applyPlaybackTransitionIfNeeded()
                applySelectedAspectMode(force: true)
                applySeriesEpisodeRemoteCommands()
                if let v = volumeBackupDuringChannelBrowser {
                    player.setVolume(v)
                    volumeBackupDuringChannelBrowser = nil
                }
            }
        }
        .onChange(of: playbackIdentity) { _, _ in
            applyPlaybackTransitionIfNeeded()
        }
        .onChange(of: videoAspectModeRaw) { _, _ in
            applySelectedAspectMode()
            showAspectToast()
        }
        .onReceive(player.$position.removeDuplicates()) { newPos in
            guard newPos.isFinite else { return }
            if isScrubbing { return }
            if let locked = lockedSliderValue {
                if abs(Double(newPos) - locked) < 0.035 {
                    DispatchQueue.main.async {
                        lockedSliderValue = nil
                    }
                }
                return
            }
        }
        .onChange(of: player.timeMs) { _, newTime in
            // 200ms throttle: altyazı cue'ları tipik olarak saniyeler sürer, 120ms → 200ms fark edilmez.
            // Geriye doğru seek (scrub) durumunda anında güncelle.
            let delta = newTime - lastSubtitleUpdateMs
            if delta >= 200 || delta < 0 {
                lastSubtitleUpdateMs = newTime
                subtitleManager.update(currentTime: Double(newTime) / 1000.0)
            }
        }
        .onChange(of: playbackPresentationKey) { _, _ in
            player.setPlaybackPresentation(
                PlaybackPresentation(title: title, subtitle: subtitle,
                                     artworkURL: artworkURL, isLive: isLiveStream)
            )
        }
        .onDisappear {
            timer?.invalidate()
            saveHistoryTimer?.invalidate()
            saveWatchHistory()
            player.teardown()
        }
        .sheet(isPresented: $showTrackSettings) {
            PlaybackTrackSettingsSheet(player: player, showDebugOverlay: $showDebugOverlay, streamURL: url)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSubtitleAppearance) {
            SubtitleAppearanceSheet(player: player)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: showTrackSettings) { _, isOpen in
            if isOpen { resetInteractiveDismissTracking() }
        }
        .onChange(of: showSubtitleAppearance) { _, isOpen in
            if isOpen { resetInteractiveDismissTracking() }
        }
        .onChange(of: player.isSeekable) { _, _ in checkAndPerformResume() }
        .onChange(of: player.durationMs) { _, _ in checkAndPerformResume() }
        .onAppear { startSaveHistoryTimer() }
        .onChange(of: seriesRemoteCommandsKey) { _, _ in
            applySeriesEpisodeRemoteCommands()
        }
        .onChange(of: player.videoBitrate) { _, newValue in
            appendBitrateSample(newValue)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applySeriesEpisodeRemoteCommands() {
        switch type {
        case "series":
            player.configureSeriesEpisodeSkipping(
                canPrevious: canGoToPreviousEpisode,
                canNext: canGoToNextEpisode,
                onPrevious: onPreviousEpisode,
                onNext: onNextEpisode
            )
        default:
            // Canlı TV: kanal atlama için skip'i kapat, prev/next göster.
            // Filmler (vod): skip her zaman açık; prev/next film kuyruğu Control Center'a yansımaz.
            player.configureSeriesEpisodeSkipping(
                canPrevious: canGoToPreviousChannel,
                canNext: canGoToNextChannel,
                onPrevious: onPreviousChannel,
                onNext: onNextChannel,
                swapSkipForNav: isLiveStream
            )
        }
    }

    private func applyPlaybackTransitionIfNeeded() {
        guard appliedPlaybackIdentity != playbackIdentity else { return }
        if let tags = historySaveTags {
            saveWatchHistory(tags: tags)
        }
        appliedPlaybackIdentity = playbackIdentity
        historySaveTags = WatchHistoryTags(
            playlistId: playlistId,
            streamId: streamId,
            type: type,
            seriesId: seriesId,
            title: title,
            secondaryTitle: subtitle,
            imageURL: artworkURL?.absoluteString,
            containerExtension: containerExtension
        )

        let shouldStartFromResume = !isLiveStream && (resumeTimeMs ?? 0) > 5000
        hasInitialSeeked = shouldStartFromResume
        bitrateSamples.removeAll()
        isScrubbing = false
        scrubValue = 0
        lockedSliderValue = nil
        sliderUnlockGeneration += 1
        isFastForwarding = false
        player.setRate(1.0)
        videoPinchBase = 1
        videoPinchLive = 1
        videoPanCommitted = .zero
        subtitleManager.reset()

        log.info("Load playback: \(self.playbackIdentity, privacy: .public)")
        player.setImportedSubtitleContext(
            contentKey: ImportedSubtitleStore.contentKey(
                playlistId: playlistId, type: type, streamId: streamId
            )
        )
        let initialStartSeconds: TimeInterval? = shouldStartFromResume ? Double(resumeTimeMs ?? 0) / 1000.0 : nil
        if let initialStartSeconds {
            log.info("Starting playback with mpv start option: \(initialStartSeconds, privacy: .public)s")
        }
        player.play(url: url, startSeconds: initialStartSeconds, isLiveStream: isLiveStream)
        applySelectedAspectMode(force: true)
        player.setPlaybackPresentation(
            PlaybackPresentation(title: title, subtitle: subtitle,
                                 artworkURL: artworkURL, isLive: isLiveStream)
        )
        applySeriesEpisodeRemoteCommands()
    }

    private func checkAndPerformResume() {
        guard !isLiveStream else { return }
        guard !hasInitialSeeked, player.isSeekable, player.durationMs > 0,
              let resumeTime = resumeTimeMs, resumeTime > 5000 else { return }
        let pos = Float(Double(resumeTime) / Double(player.durationMs))
        log.info("Seeking to resumeTimeMs: \(resumeTime) (pos: \(pos))")
        player.seek(to: min(max(pos, 0), 1))
        hasInitialSeeked = true
    }

    private func startSaveHistoryTimer() {
        saveHistoryTimer?.invalidate()
        saveHistoryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            if player.isPlaying { saveWatchHistory() }
        }
    }

    private func applySpeedHoldBegan() {
        guard speedUpOnLongPress else { return }
        guard videoZoomScale <= 1.02, !isScrubbing else { return }
        resetTimer()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isFastForwarding = true
        }
        player.setRate(2.0)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func applySpeedHoldEnded() {
        guard isFastForwarding else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isFastForwarding = false
        }
        player.setRate(1.0)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cancelSpeedHoldBecauseDismissDragRecognized() {
        if isFastForwarding {
            applySpeedHoldEnded()
        }
    }

    private func resetInteractiveDismissTracking() {
        interactiveDismissAxis = nil
        interactiveDismissOffset = .zero
    }

    private func resetInteractiveDismissTrackingWithAnimation() {
        interactiveDismissAxis = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            interactiveDismissOffset = .zero
        }
    }

    private func startsInteractiveEdgeBack(start: CGPoint, containerWidth: CGFloat) -> Bool {
        let margin: CGFloat = 36
        switch layoutDirection {
        case .rightToLeft:
            return start.x > containerWidth - margin
        default:
            return start.x < margin
        }
    }

    /// Aşağı çekerek kapatmayı yalnızca jestin başladığı nokta “krom” bölgelerindeyse bastır (yan parlaklık/ses,
    /// üst/alt düğme ve zaman çubuğu). Ortadan aşağı kaydırma kontroller açıkken de çalışır.
    private func interactiveDismissShouldSuppressPullDown(
        start: CGPoint,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> Bool {
        let w = max(containerWidth, 1)
        let h = max(containerHeight, 1)
        let sideMargin: CGFloat = 110
        if start.x <= sideMargin || start.x >= w - sideMargin {
            return true
        }
        guard showControls else { return false }

        let topChrome: CGFloat = 96
        if start.y <= topChrome {
            return true
        }

        let bottomChrome = safeAreaBottom + 168
        if start.y >= h - bottomChrome {
            return true
        }

        return false
    }

    /// Üst kenar: Kontrol Merkezi / Bildirimler / durum alanı jestleri; oynatıcı kapatmayı tetiklemesin.
    private func interactiveDismissTopSystemGestureBandHeight(
        safeAreaTop: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let h = max(containerHeight, 1)
        let minBand: CGFloat = 72
        let fromSafe = safeAreaTop + 40
        return min(max(fromSafe, minBand), h * 0.28)
    }

    private func interactiveDismissStartedInTopSystemGestureBand(
        start: CGPoint,
        containerHeight: CGFloat,
        safeAreaTop: CGFloat
    ) -> Bool {
        start.y <= interactiveDismissTopSystemGestureBandHeight(
            safeAreaTop: safeAreaTop,
            containerHeight: containerHeight
        )
    }

    private func interactiveDismissOpacity(containerSize: CGSize) -> Double {
        let w = max(containerSize.width, 1)
        let h = max(containerSize.height, 1)
        let vx = Double(abs(interactiveDismissOffset.width)) / Double(w)
        let vy = Double(max(0, interactiveDismissOffset.height)) / Double(h)
        let combined = min(0.55, vx * 0.32 + vy * 0.5)
        return max(0.38, 1.0 - combined)
    }

    private func interactiveDismissDragGesture(
        containerSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onChanged { value in
                if showTrackSettings || showSubtitleAppearance { return }
                if videoZoomScale > 1.02 || isScrubbing { return }

                let start = value.startLocation
                let t = value.translation
                let w = max(containerSize.width, 1)
                let h = max(containerSize.height, 1)
                let startedInTopSystemBand = interactiveDismissStartedInTopSystemGestureBand(
                    start: start,
                    containerHeight: h,
                    safeAreaTop: safeAreaTop
                )

                if interactiveDismissAxis == nil {
                    if startsInteractiveEdgeBack(start: start, containerWidth: w) {
                        if !startedInTopSystemBand {
                            let correctDirection =
                                (layoutDirection == .leftToRight && t.width > 12)
                                || (layoutDirection == .rightToLeft && t.width < -12)
                            if correctDirection, abs(t.width) + 8 >= abs(t.height) {
                                interactiveDismissAxis = .edgeBack
                            }
                        }
                    }
                    if interactiveDismissAxis == nil, t.height > 18, t.height > abs(t.width) * 0.9,
                       !interactiveDismissShouldSuppressPullDown(
                        start: start,
                        containerWidth: w,
                        containerHeight: h,
                        safeAreaBottom: safeAreaBottom
                       ),
                       !startedInTopSystemBand
                    {
                        interactiveDismissAxis = .pullDown
                    }
                }

                switch interactiveDismissAxis {
                case .edgeBack:
                    if layoutDirection == .leftToRight {
                        interactiveDismissOffset = CGSize(width: max(0, t.width), height: 0)
                    } else {
                        interactiveDismissOffset = CGSize(width: min(0, t.width), height: 0)
                    }
                case .pullDown:
                    interactiveDismissOffset = CGSize(width: 0, height: max(0, t.height))
                case .none:
                    break
                }

                if interactiveDismissAxis != nil {
                    cancelSpeedHoldBecauseDismissDragRecognized()
                }
            }
            .onEnded { value in
                if showTrackSettings || showSubtitleAppearance {
                    resetInteractiveDismissTracking()
                    return
                }

                let axis = interactiveDismissAxis
                guard videoZoomScale <= 1.02, !isScrubbing else {
                    resetInteractiveDismissTrackingWithAnimation()
                    return
                }

                guard let axis else {
                    if interactiveDismissOffset != .zero {
                        resetInteractiveDismissTrackingWithAnimation()
                    }
                    return
                }

                let t = value.translation
                let pred = value.predictedEndTranslation
                let cw = max(containerSize.width, 1)
                let ch = max(containerSize.height, 1)

                var shouldDismiss = false
                switch axis {
                case .edgeBack:
                    let progressed = layoutDirection == .leftToRight ? t.width : -t.width
                    let predProg = layoutDirection == .leftToRight ? pred.width : -pred.width
                    if progressed > min(cw * 0.28, 130) || predProg > 200 {
                        shouldDismiss = true
                    }
                case .pullDown:
                    if t.height > min(ch * 0.22, 150) || pred.height > 220 {
                        shouldDismiss = true
                    }
                }

                interactiveDismissAxis = nil
                if shouldDismiss {
                    switch axis {
                    case .pullDown:
                        withAnimation(.easeIn(duration: 0.18)) {
                            interactiveDismissOffset = CGSize(width: 0, height: ch + 60)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            performPlayerDismiss()
                        }
                    case .edgeBack:
                        let targetX: CGFloat = layoutDirection == .leftToRight ? cw + 60 : -(cw + 60)
                        withAnimation(.easeIn(duration: 0.18)) {
                            interactiveDismissOffset = CGSize(width: targetX, height: 0)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            performPlayerDismiss()
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        interactiveDismissOffset = .zero
                    }
                }
            }
    }

    // MARK: - Player surface

    private func playerChromeAndVideo(outerSafeAreaInsets: EdgeInsets) -> some View {
        GeometryReader { geo in
            let fittedSize = fittedVideoSize(in: geo.size)
            ZStack {
                MPVolumeViewHost(bridge: systemVolumeBridge)
                    .frame(width: 120, height: 48)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(-10)

                ZStack {
                    MPVPlayerPlaybackContainerView(
                        mpvPlayer: player.mpvEngine,
                        playbackBridge: player,
                        manualPiPTrigger: pipManualSignal,
                        pipEnabled: pipEnabled,
                        continuePlayingInBackground: continuePlayingInBackground
                    )
                    .id("MPVPlaybackPiP")

                    SubtitleOverlayView(text: subtitleManager.currentSubtitle)
                        .allowsHitTesting(false)
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(videoZoomScale, anchor: .center)
                .offset(videoEffectiveOffset)
                .allowsHitTesting(false)  // tüm touch UIKit overlay'de; video katmanı hit-test almaz
                .zIndex(0)

                // Tap/pinch/pan UIKit overlay'inde. Pinch midpoint callback ile zoom anchor
                // offset hesaplanır; pan yalnızca zoomluyken enabled.
                PlayerMediaKitStyleTouchOverlay(
                    showControls: $showControls,
                    isSeekDisabled: isCenterTransportLoading,
                    videoZoomScale: videoZoomScale,
                    isSpeedHoldActive: isFastForwarding,
                    onResetTimer: { resetTimer() },
                    onInvalidateTimer: { timer?.invalidate() },
                    onSpeedHoldBegan: { applySpeedHoldBegan() },
                    onSpeedHoldEnded: { applySpeedHoldEnded() },
                    onVideoPinchBegan: { location, containerBounds in
                        handleVideoPinchBegan(at: location, containerSize: containerBounds)
                    },
                    onVideoPinchChanged: { videoPinchLive = $0 },
                    onVideoPinchEnded: { handleVideoPinchGestureEnded() },
                    onVideoPanChanged: { translation in
                        videoPanLive = translation
                    },
                    onVideoPanEnded: { translation in
                        handleVideoPanEnded(translation: translation)
                    },
                    onVideoSurfaceTap: { onVideoSurfaceTap?() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)

                if showControls {
                    // iOS native player gibi okunabilirlik için üst/alt koyu gradient.
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.55),
                                Color.black.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 160)
                        Spacer(minLength: 0)
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.0),
                                Color.black.opacity(0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 220)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(29)

                    VStack(spacing: 0) {
                        topChrome
                        Spacer()
                        centerTransport
                        Spacer()
                        bottomTransportChrome
                    }
                    .padding(.leading, 12 + outerSafeAreaInsets.leading)
                    .padding(.trailing, 12 + outerSafeAreaInsets.trailing)
                    .padding(.top, outerSafeAreaInsets.top)
                    .padding(.bottom, 12 + outerSafeAreaInsets.bottom)
                    // Kontroller güvenli alanın dışına çıkmasın — home indicator / app switcher
                    // jest bölgesinde scrub bar yanlışlıkla seek tetiklemesin diye alt safe area korunur.
                    .simultaneousGesture(
                        TapGesture().onEnded { resetTimer() }
                    )
                    .zIndex(30)

                    PlayerControlCenterStyleEdgeSliders(
                        player: player,
                        systemVolume: systemVolumeBridge,
                        safeAreaInsets: outerSafeAreaInsets,
                        isCompactWidth: isCompactWidth
                    ) {
                        resetTimer()
                    }
                    .zIndex(32)
                }

                if showControls && showDebugOverlay {
                    // Debug panel top-trailing, volume slider'ın ÜSTÜNDE render edilir
                    // (zIndex slider'dan yüksek). topChrome'un altında, sağda ses slider'ını
                    // kaplar.
                    VStack {
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("RES \(playbackDebugResolutionText)")
                                Text("FPS \(playbackDebugFpsText)")
                                Text("BR \(playbackDebugBitrateText)")
                                Text(playbackDebugFramesText)
                                Text(playbackDebugCacheText)
                                Text(playbackDebugAvSyncText)
                                Text(playbackDebugNetText)
                                Text(playbackDebugCodecText)
                                Text(playbackDebugSeekText)
                            }
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(.top, 78 + outerSafeAreaInsets.top)
                        .padding(.trailing, 16 + outerSafeAreaInsets.trailing)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .zIndex(33)
                }

                if let aspectToastText {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: selectedAspectMode.iconName)
                                .font(.footnote.weight(.semibold))
                            Text(aspectToastText)
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
                        .padding(.top, 64)
                        Spacer()
                    }
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.92, anchor: .top))
                            .combined(with: .move(edge: .top))
                    )
                    .zIndex(40)
                    .allowsHitTesting(false)
                }

                // Not: PiP placeholder UI kaldırıldı — sistem `AVPictureInPictureController`
                // kendi "playing in picture in picture" mesajını otomatik gösteriyor.

                if isFastForwarding {
                    VStack {
                        HStack(spacing: 6) {
                            Text("2x")
                            Image(systemName: "forward.fill")
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                        .padding(.top, 64)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }

                if showControls && hasPlaybackFailure, let msg = player.playbackFailureMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                        Text(msg)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: max(0, min(geo.size.width - 24, 280)), alignment: .leading)
                    .background(
                        Color(red: 0.72, green: 0.12, blue: 0.14).opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 12)
                    .padding(.bottom, (showControls ? 92 : 12) + outerSafeAreaInsets.bottom)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("player.playback_error"))
                    .accessibilityValue(msg)
                    .zIndex(25)
                }

            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { videoViewportSize = fittedSize }
            .onChange(of: geo.size) { _, new in
                videoViewportSize = fittedVideoSize(in: new)
                commitVideoPanClamp()
            }
            .onChange(of: sourceVideoAspectRatio) { _, _ in
                videoViewportSize = fittedVideoSize(in: geo.size)
                commitVideoPanClamp()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Video yüzeyi ekranın kenarlarına kadar uzansın. Kontroller ayrıca `outerSafeAreaInsets`
        // kullanarak güvenli alana saygı gösterir (aşağıda controls VStack padding'i).
        .ignoresSafeArea()
    }

    private func handleVideoPinchBegan(at location: CGPoint, containerSize: CGSize) {
        pinchAnchorState = PinchAnchorState(
            screenMidpoint: location,
            containerCenter: CGPoint(x: containerSize.width / 2, y: containerSize.height / 2),
            startScale: videoZoomScale,
            startPanCommitted: videoPanCommitted
        )
    }

    private func handleVideoPinchGestureEnded() {
        // Pinch end: önce compensating zoom offset'i committed pan'a bake et, sonra state'i temizle.
        let zoomDelta = videoPinchZoomOffset
        pinchAnchorState = nil
        videoPanCommitted = CGSize(
            width: videoPanCommitted.width + zoomDelta.width,
            height: videoPanCommitted.height + zoomDelta.height
        )
        // Scale'i komite et.
        videoPinchBase = min(max(videoPinchBase * videoPinchLive, 1), videoZoomMax)
        videoPinchLive = 1
        if videoPinchBase < 1.02 {
            videoPinchBase = 1
            videoPanCommitted = .zero
        } else {
            commitVideoPanClamp()
        }
    }

    private func handleVideoPanEnded(translation: CGSize) {
        let maxX = max(0, (videoViewportSize.width * (videoZoomScale - 1)) / 2)
        let maxY = max(0, (videoViewportSize.height * (videoZoomScale - 1)) / 2)
        let combined = CGSize(
            width: videoPanCommitted.width + translation.width,
            height: videoPanCommitted.height + translation.height
        )
        videoPanCommitted = CGSize(
            width: min(max(combined.width, -maxX), maxX),
            height: min(max(combined.height, -maxY), maxY)
        )
        videoPanLive = .zero
    }

    private func commitVideoPanClamp() {
        let maxX = max(0, (videoViewportSize.width * (videoZoomScale - 1)) / 2)
        let maxY = max(0, (videoViewportSize.height * (videoZoomScale - 1)) / 2)
        videoPanCommitted = CGSize(
            width: min(max(videoPanCommitted.width, -maxX), maxX),
            height: min(max(videoPanCommitted.height, -maxY), maxY)
        )
    }

    private func saveWatchHistory(tags: WatchHistoryTags? = nil) {
        let resolvedTags = tags ?? WatchHistoryTags(
            playlistId: playlistId,
            streamId: streamId,
            type: type,
            seriesId: seriesId,
            title: title,
            secondaryTitle: subtitle,
            imageURL: artworkURL?.absoluteString,
            containerExtension: containerExtension
        )
        let currentTime = Int(player.timeMs)
        let duration = Int(player.durationMs)
        guard duration > 0 else { return }

        let history = DBWatchHistory(
            id: "\(resolvedTags.playlistId)_\(resolvedTags.type)_\(resolvedTags.streamId)",
            playlistId: resolvedTags.playlistId,
            streamId: resolvedTags.streamId,
            type: resolvedTags.type,
            lastTimeMs: currentTime,
            durationMs: duration,
            lastWatchedAt: Date(),
            seriesId: resolvedTags.seriesId,
            title: resolvedTags.title,
            secondaryTitle: resolvedTags.secondaryTitle,
            imageURL: resolvedTags.imageURL,
            containerExtension: resolvedTags.containerExtension
        )

        Task {
            do {
                try await AppDatabase.shared.write { db in
                    try history.save(db)
                }
            } catch {
                log.error("Failed to save watch history: \(error)")
            }
        }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            glassIconButton(systemName: "xmark", size: 44) { performPlayerDismiss() }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if let onNavigate = onNavigateToDetail {
                    let targetId = (type == "series" ? seriesId : streamId) ?? streamId
                    onNavigate(type, targetId)
                    performPlayerDismiss()
                }
            }

            HStack(spacing: 2) {
                if let isFav = isFavorite, let toggle = onToggleFavorite {
                    groupedCapsuleButton(systemName: isFav ? "star.fill" : "star") {
                        toggle()
                    }
                    .accessibilityLabel(isFav ? L("favorites.remove") : L("favorites.add"))
                }

                groupedCapsuleButton(systemName: selectedAspectMode.iconName) {
                    resetVideoTransformForAspectSwitch()
                    videoAspectModeRaw = nextAspectMode.rawValue
                }
                .accessibilityLabel(selectedAspectMode.accessibilityLabel)

                if AVPictureInPictureController.isPictureInPictureSupported() && pipEnabled {
                    groupedCapsuleButton(systemName: "pip") {
                        guard canEnterPiPNow else { return }
                        pipManualSignal += 1
                    }
                }
                groupedCapsuleButton(systemName: "textformat.size") {
                    showSubtitleAppearance = true
                }
                groupedCapsuleButton(systemName: "gearshape") {
                    player.updateTracks()
                    showTrackSettings = true
                }
            }
            .padding(.horizontal, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// Top chrome sağ tarafında gruplu material capsule içinde kullanılan inline buton.
    /// Kendi arka planı yoktur; parent capsule blur'u tüm grubun altındadır.
    private func groupedCapsuleButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            resetTimer()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Compact horizontal size class'ta (iPhone) daha sıkı yerleşim — edge slider'lar için
    /// yatayda boşluk bırakır. Regular'da (iPad) geniş orijinal düzen.
    private var isCompactWidth: Bool { horizontalSizeClass == .compact }
    private var transportSpacing: CGFloat { isCompactWidth ? 22 : 56 }
    private var transportSkipHit: CGFloat { isCompactWidth ? 52 : 64 }
    private var transportSkipSymbol: CGFloat { isCompactWidth ? 30 : 36 }
    private var transportPlayHit: CGFloat { isCompactWidth ? 84 : 96 }
    private var transportPlaySymbol: CGFloat { isCompactWidth ? 46 : 52 }

    /// iOS native player stili: pill arka plan yok, sadece SF Symbols + shadow.
    /// Alt gradient arkaplanı karartıyor, butonlar direkt üstünde durur.
    private var centerTransport: some View {
        HStack(spacing: transportSpacing) {
            if !isLiveStream && !isCenterTransportLoading {
                transparentTransportButton(
                    systemName: "gobackward.15",
                    symbolSize: transportSkipSymbol,
                    hitFrame: transportSkipHit
                ) {
                    player.jump(seconds: -15)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                .disabled(hasPlaybackFailure)
                .opacity(hasPlaybackFailure ? 0.4 : 1)
            }

            centerPlayPauseOrLoadingButton

            if !isLiveStream && !isCenterTransportLoading {
                transparentTransportButton(
                    systemName: "goforward.15",
                    symbolSize: transportSkipSymbol,
                    hitFrame: transportSkipHit
                ) {
                    player.jump(seconds: 15)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                .disabled(hasPlaybackFailure)
                .opacity(hasPlaybackFailure ? 0.4 : 1)
            }
        }
        .padding(.vertical, 8)
    }

    /// Orta: yüklenirken `ProgressView`, hazır olunca oynat / duraklat.
    private var centerPlayPauseOrLoadingButton: some View {
        Group {
            if isCenterTransportLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.95))
                    .scaleEffect(1.6)
                    .frame(width: transportPlayHit, height: transportPlayHit)
                    .allowsHitTesting(false)
            } else {
                transparentTransportButton(
                    systemName: player.isPlaying ? "pause.fill" : "play.fill",
                    symbolSize: transportPlaySymbol,
                    hitFrame: transportPlayHit
                ) {
                    player.togglePlayPause()
                }
                .disabled(hasPlaybackFailure)
                .opacity(hasPlaybackFailure ? 0.4 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isCenterTransportLoading)
    }

    /// Glass arkaplansız iOS native stili transport butonu: SF Symbol + subtle shadow.
    private func transparentTransportButton(
        systemName: String,
        symbolSize: CGFloat,
        hitFrame: CGFloat = 64,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            resetTimer()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
                .frame(width: hitFrame, height: hitFrame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Bölüm atlama ayrı; zaman çubuğu yalnızca `scrubTimelineCard` içinde.
    private var bottomTransportChrome: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showLiveChannelSkip || showLiveChannelListButton {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if showLiveChannelSkip {
                        glassIconButton(systemName: "chevron.left.circle.fill", size: 44, symbolSize: 17) {
                            onPreviousChannel?()
                        }
                        .disabled(!canGoToPreviousChannel)
                        .opacity(canGoToPreviousChannel ? 1 : 0.38)

                        glassIconButton(systemName: "chevron.right.circle.fill", size: 44, symbolSize: 17) {
                            onNextChannel?()
                        }
                        .disabled(!canGoToNextChannel)
                        .opacity(canGoToNextChannel ? 1 : 0.38)
                    }
                    if showLiveChannelListButton, let toggle = onToggleLiveChannelSidePanel {
                        glassIconButton(
                            systemName: isLiveChannelSidePanelVisible ? "rectangle.bottomthird.inset.filled" : "rectangle.grid.1x2",
                            size: 44,
                            symbolSize: 17
                        ) {
                            toggle()
                        }
                        .accessibilityLabel(L("list.channel_list"))
                    }
                }
                .padding(.horizontal, 12)
            }

            if showSeriesEpisodeSkip {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    glassIconButton(systemName: "backward.end.fill", size: 44, symbolSize: 17) {
                        onPreviousEpisode?()
                    }
                    .disabled(!canGoToPreviousEpisode)
                    .opacity(canGoToPreviousEpisode ? 1 : 0.38)

                    glassIconButton(systemName: "forward.end.fill", size: 44, symbolSize: 17) {
                        onNextEpisode?()
                    }
                    .disabled(!canGoToNextEpisode)
                    .opacity(canGoToNextEpisode ? 1 : 0.38)
                }
                .padding(.horizontal, 12)
            }

            if showVODQueueSkip {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    glassIconButton(systemName: "backward.end.fill", size: 44, symbolSize: 17) {
                        onPreviousChannel?()
                    }
                    .disabled(!canGoToPreviousChannel)
                    .opacity(canGoToPreviousChannel ? 1 : 0.38)

                    glassIconButton(systemName: "forward.end.fill", size: 44, symbolSize: 17) {
                        onNextChannel?()
                    }
                    .disabled(!canGoToNextChannel)
                    .opacity(canGoToNextChannel ? 1 : 0.38)
                }
                .padding(.horizontal, 12)
            }

            if !isLiveStream {
                scrubTimelineCard
            }
        }
    }

    /// iOS native player stili: kartsız, düz düzen; okunabilirlik alt gradient'ten gelir.
    private var scrubTimelineCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(isScrubbing ? formatMs(Int(scrubValue * Double(player.durationMs))) : formatMs(Int(player.timeMs)))
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
                .frame(minWidth: 52, alignment: .leading)

            PlayerTimeline(
                value: sliderBinding,
                isSeekable: effectiveSeekable,
                onEditingChanged: { editing in
                    if editing {
                        if isFastForwarding { applySpeedHoldEnded() }
                        resetTimer()
                        isScrubbing = true
                        scrubValue = displayedSliderPosition
                    } else {
                        let target = scrubValue
                        lockedSliderValue = target
                        player.seek(to: Float(target))
                        isScrubbing = false
                        resetTimer()
                        sliderUnlockGeneration += 1
                        let gen = sliderUnlockGeneration
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_800_000_000)
                            guard gen == sliderUnlockGeneration else { return }
                            lockedSliderValue = nil
                        }
                    }
                },
                onDragValue: { dragVal in
                    scrubValue = dragVal
                }
            )
            .layoutPriority(1)

            Text(totalDurationLabel)
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    private var totalDurationLabel: String {
        if isLiveStream { return L("player.live_badge") }
        if player.durationMs > 500 { return formatMs(Int(player.durationMs)) }
        return "--:--"
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func appendBitrateSample(_ bps: Double) {
        let now = Date()
        if bps > 0 {
            bitrateSamples.append((time: now, bps: bps))
        }
        let cutoff = now.addingTimeInterval(-5)
        bitrateSamples.removeAll { $0.time < cutoff }
    }

    private func formatBitrate(_ bps: Double) -> String {
        let mbps = bps / 1_000_000
        if mbps >= 1 { return String(format: "%.2fM", mbps) }
        let kbps = bps / 1_000
        return String(format: "%.0fK", kbps)
    }

    private var canEnterPiPNow: Bool {
        player.state == .playing
            && player.isPlaying
            && player.mpvEngine.isPlaybackEstablished
            && !player.mpvEngine.isPaused
            && !player.mpvEngine.isBuffering
    }

    private func glassIconButton(
        systemName: String, size: CGFloat,
        symbolSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        GlassSystemIconButton(
            systemName: systemName,
            pointSize: symbolSize ?? size * 0.34,
            buttonSize: size,
            action: {
                resetTimer()
                action()
            }
        )
    }

    private func resetTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            showControls = false
        }
    }

    private func resetVideoTransformForAspectSwitch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            videoPinchBase = 1
            videoPinchLive = 1
            videoPanCommitted = .zero
        }
    }

    private func applySelectedAspectMode(force: Bool = false) {
        player.setAspectMode(selectedAspectMode, force: force)
    }

    private func showAspectToast() {
        aspectToastToken &+= 1
        let token = aspectToastToken
        withAnimation(.easeInOut(duration: 0.18)) {
            aspectToastText = selectedAspectMode.title
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard token == aspectToastToken else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                aspectToastText = nil
            }
        }
    }
}

struct LiveChannelBrowserScreen: View {
    let sections: [LiveChannelCategorySection]
    let currentStreamId: Int?
    let onSelectChannel: (DBLiveStream) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryId: String
    @State private var highlightedStreamId: Int

    init(
        sections: [LiveChannelCategorySection],
        currentStreamId: Int?,
        onSelectChannel: @escaping (DBLiveStream) -> Void
    ) {
        self.sections = sections
        self.currentStreamId = currentStreamId
        self.onSelectChannel = onSelectChannel
        let firstSectionId = sections.first?.id ?? "all"
        let categoryIdForCurrentStream: String? = {
            guard let sid = currentStreamId else { return nil }
            return sections.first(where: { $0.streams.contains(where: { $0.streamId == sid }) })?.id
        }()
        let initialCategoryId = categoryIdForCurrentStream ?? firstSectionId
        let initialStreamId = currentStreamId
            ?? sections.first(where: { $0.id == initialCategoryId })?.streams.first?.streamId
            ?? sections.first?.streams.first?.streamId
            ?? 0
        _selectedCategoryId = State(initialValue: initialCategoryId)
        _highlightedStreamId = State(initialValue: initialStreamId)
    }

    private var activeSection: LiveChannelCategorySection? {
        sections.first(where: { $0.id == selectedCategoryId }) ?? sections.first
    }

    private var currentStreams: [DBLiveStream] {
        activeSection?.streams ?? []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                categoryHorizontalBar
                channelListColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Kanallar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                }
                .tint(.white)
                .buttonStyle(.plain)
                .accessibilityLabel("Geri")
            }
        }
        .onAppear {
            AppDelegate.orientationLock = .landscape
            requestLandscapeGeometryUpdateIfPossible()
            syncSelectionToCurrentStreamIfPossible()
        }
        .onDisappear {
            AppDelegate.orientationLock = .allButUpsideDown
        }
    }

    /// Seçili kanal `currentStreams` içindeyse listeyle hizala (ilk açılış ve kategori değişimi).
    private func scrollChannelListToHighlightedItem(proxy: ScrollViewProxy) {
        guard let stream = currentStreams.first(where: { $0.streamId == highlightedStreamId }) else { return }
        Task { @MainActor in
            // LazyVStack ölçümü için kısa gecikme; aksi halde scrollTo bazen etkisiz kalıyor.
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(stream.id, anchor: .center)
            }
        }
    }

    private func requestLandscapeGeometryUpdateIfPossible() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: UIInterfaceOrientationMask.landscape
        )
        scene.requestGeometryUpdate(prefs) { _ in }
    }

    private func syncSelectionToCurrentStreamIfPossible() {
        guard let sid = currentStreamId else { return }
        guard let section = sections.first(where: { $0.streams.contains(where: { $0.streamId == sid }) }) else { return }
        if selectedCategoryId != section.id {
            selectedCategoryId = section.id
        }
        if highlightedStreamId != sid {
            highlightedStreamId = sid
        }
    }

    /// Başlığın altında yatay kaydırmalı kategoriler. Yatay ScrollView dikeyde şişmemesi için `fixedSize` kullanılır.
    private var categoryHorizontalBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 9) {
                ForEach(sections) { section in
                    Button {
                        selectedCategoryId = section.id
                    } label: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedCategoryId == section.id ? Color.accentColor : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white.opacity(0.06))
    }

    private var channelListColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(currentStreams) { stream in
                        channelListRow(stream: stream)
                            .id(stream.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.06))
            .onAppear {
                scrollChannelListToHighlightedItem(proxy: proxy)
            }
            .onChange(of: selectedCategoryId) { _, _ in
                scrollChannelListToHighlightedItem(proxy: proxy)
            }
            .onChange(of: highlightedStreamId) { _, _ in
                scrollChannelListToHighlightedItem(proxy: proxy)
            }
        }
    }

    private func channelListRow(stream: DBLiveStream) -> some View {
        let isSelected = stream.streamId == highlightedStreamId
        let isCurrent = stream.streamId == currentStreamId
        return Button {
            highlightedStreamId = stream.streamId
            onSelectChannel(stream)
        } label: {
            HStack(spacing: 8) {
                CachedImage(
                    url: stream.streamIcon.flatMap { URL(string: $0) },
                    width: 30,
                    height: 30,
                    cornerRadius: 7,
                    iconName: "tv",
                    loadProfile: .standard
                )
                Text(stream.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isCurrent {
                    Text(L("player.live_on_air"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(channelRowBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private func channelRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
    }
}

/// Canlı oynatıcıda oynatmayı kesmeden kanal listesi göstermek için kullanılan alt yatay panel.
/// Üstte yatay kategori çipleri, altta yatay kaydırılan kanal kartları bulunur.
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

private struct WatchHistoryTags: Equatable {
    let playlistId: UUID
    let streamId: String
    let type: String
    let seriesId: String?
    let title: String
    let secondaryTitle: String?
    let imageURL: String?
    let containerExtension: String?
}

