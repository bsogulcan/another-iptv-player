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

extension LiveChannelCategorySection {
    /// Full live queue + per-category sections for the current Xtream playlist.
    /// Players opened outside the main channel list (EPG guide, programme sheet)
    /// use this so prev/next channel and the channel side panel keep working instead
    /// of being disabled by a single-item queue.
    @MainActor
    static func xtreamLiveQueue() -> (queue: [DBLiveStream], sections: [LiveChannelCategorySection]) {
        let store = PlaylistContentStore.shared
        let sections = store.liveCategories.compactMap { cat -> LiveChannelCategorySection? in
            let streams = store.liveStreamsByCategoryId[cat.id]?.map(\.stream) ?? []
            guard !streams.isEmpty else { return nil }
            return LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams)
        }
        return (sections.flatMap(\.streams), sections)
    }
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
    /// M3U kanal bazlı User-Agent (#EXTVLCOPT / #KODIPROP); motora load'da geçirilir.
    var userAgent: String? = nil
    /// EPG lookup key for the live channel; drives the in-player now-playing strip.
    var epgChannelKey: String? = nil
    /// Catch-up playback must not write watch history (would overwrite the live row).
    var suppressWatchHistory: Bool = false

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
            userAgent: userAgent,
            epgChannelKey: epgChannelKey,
            suppressWatchHistory: suppressWatchHistory,
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
    var userAgent: String? = nil
    var epgChannelKey: String? = nil
    var suppressWatchHistory: Bool = false

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
    @StateObject private var systemVolumeBridge = SystemVolumeBridge()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerOverlayDismiss) private var playerOverlayDismiss
    @Environment(\.playerOverlayMode) private var overlayMode
    @Environment(\.playerOverlayPresentationID) private var overlayPresentationID
    @Environment(\.playerOverlayMinimize) private var playerOverlayMinimize
    @Environment(\.playerOverlayExpand) private var playerOverlayExpand
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.epgSnapshot) private var epgSnapshot

    /// Current programme for the live channel, if EPG data is available.
    private var currentNowNext: EPGNowNext? {
        guard isLiveStream, let key = epgChannelKey else { return nil }
        return epgSnapshot?[key]
    }

    @State private var showControls = true
    @State private var timer: Timer?
    @State private var saveHistoryTimer: Timer?
    @State private var hasInitialSeeked = false
    @AppStorage("player.debugOverlayEnabled") private var showDebugOverlay = false
    @AppStorage("player.videoAspectMode") private var videoAspectModeRaw = VideoAspectMode.fit.rawValue
    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continuePlayingInBackground = true
    @AppStorage("player.speedUpOnLongPress") private var speedUpOnLongPress = true
    @AppStorage("player.autoPlayNextEpisode") private var autoPlayNextEpisode = true

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var lockedSliderValue: Double?
    @State private var sliderUnlockGeneration = 0
    @State private var showTrackSettings = false
    @State private var showSubtitleAppearance = false
    @State private var isFastForwarding = false
    @State private var pipManualSignal = 0
    @State private var isPreparingAirPlay = false
    @State private var airPlayPickerSignal = 0
    @State private var bitrateSamples: [(time: Date, bps: Double)] = []
    @State private var aspectToastText: String?
    @State private var aspectToastToken: UInt64 = 0

    /// Dizi bölümü bitince sonraki bölüme otomatik geçiş geri sayımı. Token, iptal sonrası
    /// gecikmiş tick'lerin sayacı yeniden canlandırmasını engeller; `handled` bayrağı kullanıcı
    /// iptal ettiğinde aynı `.ended` durumu için sayacın tekrar başlamasını önler.
    @State private var autoAdvanceSecondsRemaining: Int?
    @State private var autoAdvanceToken: UInt64 = 0
    @State private var autoAdvanceHandledForCurrentEnd = false

    /// Tam ekran kapak: kenardan geri (pop) ve aşağı çekerek kapatma.
    private enum InteractiveDismissAxis {
        case edgeBack
        case pullDown
    }

    @State private var interactiveDismissAxis: InteractiveDismissAxis?
    @State private var interactiveDismissOffset: CGSize = .zero

    /// Mini player morph state. `miniProgress` drives the whole full↔mini transform
    /// (0 = fullscreen, 1 = docked mini card). `miniCorner` is the docked corner; the live
    /// drag translation lives in `cardDrag` (isolated so it doesn't re-render the body).
    @State private var miniProgress: CGFloat = 0
    @State private var miniCorner: MiniPlayerCorner = .bottomTrailing
    /// Live docked-card drag translation. Held via `@State` so the body does NOT observe it —
    /// only `MiniCardDragLayer` does — keeping the drag from re-rendering the video subtree.
    @State private var cardDrag = MiniCardDragModel()
    /// Invalidates a pending "reveal chrome after expand" if the mode changes again first.
    @State private var expandControlsGeneration = 0

    private var isMiniCommitted: Bool { overlayMode == .mini }

    /// İki parmak pinch: 1x–4x; yakınlaştırınca tek parmakla sürükleyerek kadraj kaydırılabilir.
    /// Pinch & pan UIKit tarafında (`PlayerMediaKitTouchContainerView`); koordinat sistemi
    /// scaled view'a bağlı olmadığı için drag güvenilir. Pinch midpoint anchor için aşağıdaki
    /// `pinchAnchorState` kullanılır.
    @State private var videoPinchBase: CGFloat = 1
    /// Live-only pinch/pan values, isolated in an ObservableObject like `cardDrag` so
    /// per-frame gesture updates re-render only `VideoZoomPanLayer`, not this whole body.
    @State private var videoZoomPan = VideoZoomPanModel()
    @State private var videoPanCommitted: CGSize = .zero
    /// The fitted (aspect-ratio) layout size of the surface — its rendered size is this
    /// times `effectiveVideoScale`.
    @State private var videoViewportSize: CGSize = .zero
    /// The full container (screen) size the surface is centered in. Pan bounds are the
    /// overflow of the rendered surface past this, so panning never exposes the background.
    @State private var videoContainerSize: CGSize = .zero
    /// Extra scale applied in `.fill` mode to cover the screen (crop). 1 in fit/center.
    /// Kept in sync with the container size so the pan-clamp math uses the true render scale.
    @State private var videoAspectFillScale: CGFloat = 1
    @State private var pinchAnchorState: PinchAnchorState?

    /// Per-window pixel density; used for the 1:1 (`.center`) mapping. `UIScreen.main.scale`
    /// is wrong on external displays / multi-window and can collapse the surface to 1×1.
    @Environment(\.displayScale) private var displayScale

    /// Pinch başlarken çekilen snapshot: zoomu pinch midpoint'ten yapmak için offset
    /// hesaplamasına ihtiyaç duyulan tüm sabit değerler.
    private struct PinchAnchorState: Equatable {
        let screenMidpoint: CGPoint  // UIKit container (= playerChrome) koordinatları
        let containerCenter: CGPoint
        let startScale: CGFloat
        let startPanCommitted: CGSize
    }

    /// Live pinch/pan values only; mutating `@Published` here does not re-render
    /// `PlayerViewImpl.body` (held via plain `@State`, not `@StateObject`) — only
    /// `VideoZoomPanLayer` below, which observes it via `@ObservedObject`, does. Mirrors
    /// `MiniCardDragModel` in MiniPlayerSupport.swift for the same reason.
    private final class VideoZoomPanModel: ObservableObject {
        @Published var pinchLive: CGFloat = 1
        @Published var panLive: CGSize = .zero
    }

    /// Applies the live pinch/pan transform to the video surface. Observing `model`
    /// directly keeps per-frame gesture updates from re-rendering the whole chrome —
    /// only this layer re-evaluates while zooming/panning.
    private struct VideoZoomPanLayer<Content: View>: View {
        @ObservedObject var model: VideoZoomPanModel
        let pinchBase: CGFloat
        let zoomMax: CGFloat
        let panCommitted: CGSize
        let aspectFillScale: CGFloat
        let viewportSize: CGSize
        let containerSize: CGSize
        let pinchAnchor: PinchAnchorState?
        @ViewBuilder var content: Content

        private var zoomScale: CGFloat {
            min(max(pinchBase * model.pinchLive, 1), zoomMax)
        }

        private var effectiveScale: CGFloat {
            aspectFillScale * zoomScale
        }

        private var panBounds: CGSize {
            CGSize(
                width: max(0, (viewportSize.width * effectiveScale - containerSize.width) / 2),
                height: max(0, (viewportSize.height * effectiveScale - containerSize.height) / 2)
            )
        }

        private var pinchZoomOffset: CGSize {
            guard let s = pinchAnchor else { return .zero }
            let M = s.screenMidpoint
            let C = s.containerCenter
            let S0 = s.startScale
            let O0 = s.startPanCommitted
            let Px = (M.x - C.x - O0.width) / S0
            let Py = (M.y - C.y - O0.height) / S0
            let S = effectiveScale
            let Ox = M.x - C.x - S * Px
            let Oy = M.y - C.y - S * Py
            return CGSize(width: Ox - O0.width, height: Oy - O0.height)
        }

        private var effectiveOffset: CGSize {
            let rawX = panCommitted.width + model.panLive.width + pinchZoomOffset.width
            let rawY = panCommitted.height + model.panLive.height + pinchZoomOffset.height
            let maxX = panBounds.width
            let maxY = panBounds.height
            return CGSize(
                width: min(max(rawX, -maxX), maxX),
                height: min(max(rawY, -maxY), maxY)
            )
        }

        var body: some View {
            content
                .scaleEffect(effectiveScale, anchor: .center)
                .offset(effectiveOffset)
        }
    }

    /// Son yüklenen içerik; `streamId`/URL değişince önce bununla geçmiş kaydedilir (yeni struct alanları henüz güncellenmiş olabilir).
    @State private var historySaveTags: WatchHistoryTags?
    @State private var appliedPlaybackIdentity: String?
    /// Altyazı `update()` binary search + eşitlik kontrolü yapıyor, ama yine de her 120ms
    /// tetiklemek onChange closure kadar küçük bir yük. 200ms pencere imperceptible.

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "another-iptv-player", category: "Playback")

    private let videoZoomMax: CGFloat = 4

    private var videoZoomScale: CGFloat {
        min(max(videoPinchBase * videoZoomPan.pinchLive, 1), videoZoomMax)
    }

    /// The true on-screen render scale of the video: the user pinch-zoom multiplied by the
    /// `.fill` cover scale. All pan-clamp / pinch-anchor math uses this so bounds are correct
    /// whether the extra scale came from a pinch or from fill-mode cropping.
    private var effectiveVideoScale: CGFloat {
        videoAspectFillScale * videoZoomScale
    }

    /// Max pan offset on each axis: half the amount the rendered surface (fitted × effective
    /// scale) overflows the container. Zero when the content fits, so panning never reveals
    /// the black background — correct for both pinch-zoom and `.fill` cropping. Using the
    /// container (not the fitted size) as the reference is what keeps Fill from over-panning.
    private var videoPanBounds: CGSize {
        CGSize(
            width: max(0, (videoViewportSize.width * effectiveVideoScale - videoContainerSize.width) / 2),
            height: max(0, (videoViewportSize.height * effectiveVideoScale - videoContainerSize.height) / 2)
        )
    }

    /// Yalnızca committed + live pan'ı valid range'e clamp eder. `VideoZoomPanLayer.effectiveOffset` tüm
    /// bileşenleri birleşik şekilde clamp ettiği için gesture sırasında kullanılmaz; pinch end'de
    /// committed pan'ı tekrar clamp etmek için `commitVideoPanClamp` kullanır.
    private var videoPanClamped: CGSize {
        let maxX = videoPanBounds.width
        let maxY = videoPanBounds.height
        let raw = CGSize(
            width: videoPanCommitted.width + videoZoomPan.panLive.width,
            height: videoPanCommitted.height + videoZoomPan.panLive.height
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
        let S = effectiveVideoScale
        let Ox = M.x - C.x - S * Px
        let Oy = M.y - C.y - S * Py
        // `videoPanCommitted` start değerine göre delta:
        return CGSize(width: Ox - O0.width, height: Oy - O0.height)
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
        if player.isCastPresenting {
            // The phone engine is intentionally stopped throughout a remux cast;
            // consulting it would leave the spinner visible forever even while
            // the TV is playing. CastController is the active presentation source.
            if player.state == .buffering { return true }
            return player.castController?.isPlaybackEstablished != true
        }
        // Native AVPlayer external playback can report its phone-side layer as
        // buffering/not-established even though the Apple TV is already playing.
        // Once video external playback is active, that local layer must not drive
        // an endless spinner on the handset.
        if player.isAirPlayPlaybackActive { return false }
        if !player.engine.isReady { return true }
        if player.state == .buffering { return true }
        if !player.engine.isPlaybackEstablished { return true }
        return false
    }

    private var seriesRemoteCommandsKey: String {
        "\(streamId)|\(type)|\(canGoToPreviousEpisode ? "1" : "0")|\(canGoToNextEpisode ? "1" : "0")|\(onPreviousEpisode != nil)|\(onNextEpisode != nil)|\(canGoToPreviousChannel ? "1" : "0")|\(canGoToNextChannel ? "1" : "0")"
    }

    private var selectedAspectMode: VideoAspectMode {
        VideoAspectMode(rawValue: videoAspectModeRaw) ?? .fit
    }

    private var nextAspectMode: VideoAspectMode {
        let all = VideoAspectMode.allCases
        guard let idx = all.firstIndex(of: selectedAspectMode) else { return .fit }
        return all[(idx + 1) % all.count]
    }

    private var sourceVideoAspectRatio: CGFloat {
        let w = CGFloat(player.videoWidth)
        let h = CGFloat(player.videoHeight)
        guard w > 0, h > 0 else { return 16.0 / 9.0 }
        return w / h
    }

    /// The layout frame the video surface is given, at the source's natural aspect ratio.
    /// `.fit` and `.fill` both use this; `.fill` additionally applies `aspectFillScale` to
    /// the surface transform to cover the screen and crops the overflow.
    private func fittedVideoSize(in viewport: CGSize) -> CGSize {
        let vw = max(viewport.width, 0)
        let vh = max(viewport.height, 0)
        guard vw > 0, vh > 0 else { return .zero }
        if selectedAspectMode == .center, player.videoWidth > 0, player.videoHeight > 0 {
            // 1:1 pixel mapping; downscale only if the native size doesn't fit.
            let scale = max(displayScale, 1)
            let sourceWPoints = max(CGFloat(player.videoWidth) / scale, 1)
            let sourceHPoints = max(CGFloat(player.videoHeight) / scale, 1)
            let fit = min(vw / sourceWPoints, vh / sourceHPoints, 1)
            return CGSize(width: sourceWPoints * fit, height: sourceHPoints * fit)
        }
        // fit / fill (and center before real dimensions arrive): aspect-fit the source ratio.
        return aspectFittedSize(ratio: sourceVideoAspectRatio, in: CGSize(width: vw, height: vh))
    }

    /// Largest box of `ratio` that fits inside `viewport` (letterbox/pillarbox).
    private func aspectFittedSize(ratio: CGFloat, in viewport: CGSize) -> CGSize {
        let r = max(ratio, 0.01)
        if viewport.width / viewport.height > r {
            return CGSize(width: viewport.height * r, height: viewport.height)
        }
        return CGSize(width: viewport.width, height: viewport.width / r)
    }

    /// Cover scale for `.fill`: multiplies the fitted frame up until it covers the whole
    /// viewport (one axis matches, the other overflows and is clipped). 1 in fit/center.
    private func aspectFillScale(viewport: CGSize, fitted: CGSize) -> CGFloat {
        guard selectedAspectMode == .fill, fitted.width > 0, fitted.height > 0 else { return 1 }
        return max(viewport.width / fitted.width, viewport.height / fitted.height)
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
        let audio = player.audioCodecName.isEmpty ? "--" : player.audioCodecName
        let airPlay = player.isAirPlayVideoCapable ? "AP✓" : "AP✗"
        return "DEC \(hw) \(codec)/\(audio) \(airPlay)"
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
            let clampedProgress = min(max(miniProgress, 0), 1)
            let card = miniCardRect(container: containerSize, safeArea: outerSafeAreaInsets)
            let t = miniTransform(progress: clampedProgress, card: card, container: containerSize)
            ZStack {
                // The whole mini-card group is repositioned by the live drag inside
                // `MiniCardDragLayer`, which is the ONLY view that re-renders while dragging —
                // the masked/scaled video below is evaluated once and merely re-offset, so the
                // picture is never re-processed (which used to glitch the video mid-drag).
                MiniCardDragLayer(model: cardDrag) {
                    ZStack {
                        // Card shadow, a cheap standalone rounded rect tracking the visible video
                        // card through the whole morph. The masked video layer never carries a
                        // shadow itself — re-shadowing that full-screen layer each frame as the
                        // mask animates caused judder/tremble. The opaque video lands on top of
                        // this fill; only the shadow spills out.
                        if clampedProgress > 0.01 {
                            let visibleCard = CGSize(width: t.maskSize.width * t.scale, height: t.maskSize.height * t.scale)
                            RoundedRectangle(
                                cornerRadius: MiniPlayerMetrics.cornerRadius * min(clampedProgress * 2.5, 1),
                                style: .continuous
                            )
                            .fill(Color.black)
                            .frame(width: visibleCard.width, height: visibleCard.height)
                            .shadow(color: .black.opacity(0.38 * Double(clampedProgress)),
                                    radius: 22 * clampedProgress, x: 0, y: 8 * clampedProgress)
                            .position(
                                x: containerSize.width / 2 + t.offset.width + interactiveDismissOffset.width,
                                y: containerSize.height / 2 + t.offset.height + interactiveDismissOffset.height
                            )
                            .allowsHitTesting(false)
                        }

                        // Player content, transformed toward the floating mini card as
                        // `miniProgress` grows. The mask crops the letterbox down to the card;
                        // scale/offset land the video on the card center. View identity is stable
                        // so playback never restarts.
                        ZStack {
                            Color.black
                                .ignoresSafeArea()

                            playerChromeAndVideo(outerSafeAreaInsets: outerSafeAreaInsets)
                        }
                        .background(Color.black)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .mask(
                            RoundedRectangle(cornerRadius: t.cornerRadius, style: .continuous)
                                .frame(width: t.maskSize.width, height: t.maskSize.height)
                        )
                        .scaleEffect(t.scale)
                        .offset(
                            x: t.offset.width + interactiveDismissOffset.width,
                            y: t.offset.height + interactiveDismissOffset.height
                        )
                        .opacity(edgeBackOpacity(containerSize: containerSize))
                        .simultaneousGesture(
                            interactiveDismissDragGesture(
                                containerSize: containerSize,
                                safeAreaTop: geo.safeAreaInsets.top,
                                safeAreaBottom: geo.safeAreaInsets.bottom
                            )
                        )
                        // Once docked, stop the (visually card-sized but layout-full-screen)
                        // content from swallowing touches: SwiftUI `.mask` crops rendering only,
                        // not the hit region. `isMiniCommitted` only flips at commit, so the
                        // interactive pull-down morph is unaffected; card taps go to the chrome.
                        .allowsHitTesting(!isMiniCommitted)

                        // Floating mini card chrome (unscaled), tappable only once docked.
                        if clampedProgress > 0.01 {
                            MiniPlayerChrome(
                                player: player,
                                cornerRadius: MiniPlayerMetrics.cornerRadius,
                                isLoading: isCenterTransportLoading,
                                onExpand: { playerOverlayExpand?() },
                                onClose: { performPlayerDismiss() },
                                onDragChanged: { translation in
                                    handleMiniCardDragChanged(
                                        translation: translation,
                                        card: card, container: containerSize
                                    )
                                },
                                onDragEnded: { translation, velocity in
                                    handleMiniCardDragEnded(
                                        translation: translation, velocity: velocity,
                                        container: containerSize, safeArea: outerSafeAreaInsets
                                    )
                                }
                            )
                            .frame(width: card.width, height: card.height)
                            .position(x: card.midX, y: card.midY)
                            .opacity(miniChromeOpacity)
                            .allowsHitTesting(isMiniCommitted)
                        }
                    }
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            // iPad / geniş yatay düzende durum çubuğunu kontrollerle aç-kapa yapmak üst güvenli alanı
            // değiştirir; GeometryReader yüksekliği sıçrar. Telefonda (compact) eski davranış korunur.
            // Mini kartta durum çubuğu her zaman görünür.
            .statusBarHidden(statusBarHiddenInCurrentMode)
        .onAppear {
            log.info("Opening player: \(title, privacy: .public)")
            resetTimer()
            player.setupAudioHandler()
            // Defer to the next run loop: the KSPlayer surface's view setup and
            // `play` can race within the same tick. First layout also relieves the main queue.
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
            cancelAutoAdvanceCountdown(resetEndHandling: true)
            applyPlaybackTransitionIfNeeded()
        }
        .onChange(of: overlayPresentationID) { _, _ in
            // The overlay deliberately preserves PlayerView identity so an active
            // AirPlay AVPlayer survives a source switch. Observe the host's explicit
            // presentation revision as a reliable handoff trigger; the identity guard
            // inside applyPlaybackTransitionIfNeeded prevents duplicate loads.
            cancelAutoAdvanceCountdown(resetEndHandling: true)
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
        .onChange(of: playbackPresentationKey) { _, _ in
            player.setPlaybackPresentation(makePresentation())
        }
        .onChange(of: currentNowNext?.now?.id) { _, _ in
            player.setPlaybackPresentation(makePresentation())
        }
        .onDisappear {
            timer?.invalidate()
            saveHistoryTimer?.invalidate()
            // Save under the applied playback identity, not the (possibly newer)
            // incoming props — mirrors the timer path above.
            saveWatchHistory(tags: historySaveTags)
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
        .onChange(of: player.state) { _, newState in
            if newState == .ended {
                startAutoAdvanceCountdownIfEligible()
            } else {
                cancelAutoAdvanceCountdown(resetEndHandling: true)
            }
        }
        .onChange(of: overlayMode) { _, newMode in
            expandControlsGeneration &+= 1
            let gen = expandControlsGeneration
            switch newMode {
            case .mini:
                // The gesture path already animated `miniProgress`; here only settle chrome.
                // Covers any external minimize too.
                timer?.invalidate()
                if showControls { showControls = false }
                if miniProgress < 0.999 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { miniProgress = 1 }
                }
            case .fullscreen:
                cardDrag.offset = .zero
                cardDrag.dismissOpacity = 1
                // Keep the (heavy) fullscreen chrome hidden during the grow so its layout doesn't
                // run every animation frame and make the expand judder. Near-critical damping
                // (0.96) also avoids a scale overshoot at the end. Reveal chrome once settled.
                timer?.invalidate()
                showControls = false
                withAnimation(.spring(response: 0.42, dampingFraction: 0.96)) { miniProgress = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) {
                    guard gen == expandControlsGeneration else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
                    resetTimer()
                }
            }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Otomatik geçiş yalnız dizilerde ve gerçekten gidilecek bir sonraki bölüm varken.
    private var isAutoAdvanceEligible: Bool {
        autoPlayNextEpisode && type == "series" && !isLiveStream
            && canGoToNextEpisode && onNextEpisode != nil
    }

    private func startAutoAdvanceCountdownIfEligible() {
        guard isAutoAdvanceEligible, !autoAdvanceHandledForCurrentEnd,
              autoAdvanceSecondsRemaining == nil else { return }
        autoAdvanceHandledForCurrentEnd = true
        autoAdvanceToken &+= 1
        let token = autoAdvanceToken
        withAnimation(.easeOut(duration: 0.25)) {
            autoAdvanceSecondsRemaining = 5
        }
        scheduleAutoAdvanceTick(token: token)
    }

    private func scheduleAutoAdvanceTick(token: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard token == autoAdvanceToken,
                  let remaining = autoAdvanceSecondsRemaining else { return }
            if remaining <= 1 {
                triggerAutoAdvance()
            } else {
                autoAdvanceSecondsRemaining = remaining - 1
                scheduleAutoAdvanceTick(token: token)
            }
        }
    }

    private func triggerAutoAdvance() {
        autoAdvanceToken &+= 1
        withAnimation(.easeOut(duration: 0.2)) {
            autoAdvanceSecondsRemaining = nil
        }
        onNextEpisode?()
    }

    private func cancelAutoAdvanceCountdown(resetEndHandling: Bool = false) {
        autoAdvanceToken &+= 1
        if autoAdvanceSecondsRemaining != nil {
            withAnimation(.easeOut(duration: 0.2)) {
                autoAdvanceSecondsRemaining = nil
            }
        }
        if resetEndHandling { autoAdvanceHandledForCurrentEnd = false }
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

        // KSOptions.startPlayTime (the `startSeconds` we pass) is honored ONLY by the
        // FFmpeg engine — the AVPlayer path (mp4/m4v/mov/HLS) ignores it, which used to
        // restart VOD resume at 0:00. For AVPlayer-native containers, leave
        // hasInitialSeeked false so checkAndPerformResume() seeks once the item is seekable.
        let usesFFmpegStartTime = KSPlayerEngine.prefersFFmpegFirst(for: url)
        let shouldStartFromResume = !isLiveStream && (resumeTimeMs ?? 0) > 5000
        hasInitialSeeked = shouldStartFromResume && usesFFmpegStartTime
        bitrateSamples.removeAll()
        isScrubbing = false
        scrubValue = 0
        lockedSliderValue = nil
        sliderUnlockGeneration += 1
        isFastForwarding = false
        player.setRate(1.0)
        videoPinchBase = 1
        videoZoomPan.pinchLive = 1
        videoPanCommitted = .zero

        log.info("Load playback: \(self.playbackIdentity, privacy: .public)")
        player.setImportedSubtitleContext(
            contentKey: ImportedSubtitleStore.contentKey(
                playlistId: playlistId, type: type, streamId: streamId
            )
        )
        let initialStartSeconds: TimeInterval? =
            (shouldStartFromResume && usesFFmpegStartTime) ? Double(resumeTimeMs ?? 0) / 1000.0 : nil
        if let initialStartSeconds {
            log.info("Starting playback with mpv start option: \(initialStartSeconds, privacy: .public)s")
        }
        player.play(
            url: url, startSeconds: initialStartSeconds, isLiveStream: isLiveStream,
            userAgent: userAgent
        )
        applySelectedAspectMode(force: true)
        player.setPlaybackPresentation(makePresentation())
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
            // The closure captures the view struct from onAppear, freezing plain props
            // (streamId, title, …) at first render. historySaveTags is @State, so it
            // stays live across in-place episode switches — without it, episode 2's
            // position would be written into episode 1's history row.
            if player.isPlaying, let tags = historySaveTags {
                saveWatchHistory(tags: tags)
            }
        }
    }

    private func applySpeedHoldBegan() {
        guard speedUpOnLongPress else { return }
        guard player.isPlaying, videoZoomScale <= 1.02, !isScrubbing,
              interactiveDismissAxis == nil else { return }
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
        // Only the on-screen controls (edge sliders / top & bottom chrome) need protecting
        // from an accidental pull-down. With the chrome hidden — the normal viewing state —
        // pull-down works from anywhere, so it never feels like a restricted zone.
        guard showControls else { return false }
        let w = max(containerWidth, 1)
        let h = max(containerHeight, 1)

        let sideMargin: CGFloat = 110
        if start.x <= sideMargin || start.x >= w - sideMargin {
            return true
        }

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

    /// Fade only for the horizontal edge-back swipe. The pull-down axis no longer fades;
    /// it morphs into the mini card instead.
    private func edgeBackOpacity(containerSize: CGSize) -> Double {
        let w = max(containerSize.width, 1)
        let vx = Double(abs(interactiveDismissOffset.width)) / Double(w)
        let combined = min(0.55, vx * 0.32)
        return max(0.38, 1.0 - combined)
    }

    // MARK: - Mini player geometry & morph

    /// Fullscreen chrome fades out over the first quarter of the minimize morph so the
    /// controls don't ride the shrinking card.
    private var fullChromeOpacity: Double {
        Double(1 - min(max(miniProgress, 0) / 0.25, 1))
    }

    /// Mini card chrome fades in over the last third of the morph.
    private var miniChromeOpacity: Double {
        Double(max(0, min(1, (miniProgress - 0.65) / 0.35)))
    }

    private var statusBarHiddenInCurrentMode: Bool {
        if isMiniCommitted { return false }
        return horizontalSizeClass == .compact ? !showControls : true
    }

    /// Vertical finger travel that maps to a full minimize (before velocity projection).
    private func pullDownDragDistance(container: CGSize) -> CGFloat {
        max(container.height * 0.32, 180)
    }

    /// Rest frame of the mini card in the GeometryReader's coordinate space, for the
    /// currently docked corner.
    private func miniCardRect(container: CGSize, safeArea: EdgeInsets) -> CGRect {
        let fitted = fittedVideoSize(in: container)
        let aspect = fitted.height > 0 ? fitted.width / fitted.height : 16.0 / 9.0
        // Reserve only the tab-bar height on compact widths. The home-indicator safe area is
        // already contained within the tab bar's region here, so adding `safeArea.bottom` on top
        // lifted the card well above the bar instead of resting it directly on top.
        let bottomInset = isCompactWidth ? MiniPlayerMetrics.tabBarAllowance : 0
        // Bound the card height to the free vertical space so it always floats fully on-screen
        // above the tab bar (matters for portrait video in a short/landscape container).
        let maxHeight = max(
            80,
            min(container.height * 0.42,
                container.height - safeArea.top - bottomInset - MiniPlayerMetrics.margin * 2)
        )
        let size = MiniPlayerMetrics.cardSize(container: container, videoAspect: aspect, maxHeight: maxHeight)
        let origin = MiniPlayerMetrics.cardOrigin(
            corner: miniCorner, size: size, container: container,
            safeArea: safeArea, bottomInset: bottomInset
        )
        return CGRect(origin: origin, size: size)
    }

    /// Scale / offset / mask / corner radius for the player content at morph progress `p`.
    /// The transform lands the *video* (not the letterboxed screen) onto the card. The mask
    /// starts generously oversized so the fullscreen state never clips the safe-area bleed.
    private func miniTransform(
        progress p: CGFloat, card: CGRect, container: CGSize
    ) -> (scale: CGFloat, offset: CGSize, maskSize: CGSize, cornerRadius: CGFloat) {
        let fitted = fittedVideoSize(in: container)
        let fh = max(fitted.height, 1)
        // Minimize must never scale content UP. Clamping guards the degenerate window where
        // .center aspect mode reports a 1×1 fitted size before the stream dimensions arrive.
        let targetScale = min(card.height / fh, 1)
        let scale = miniLerp(1, targetScale, p)

        // Oversized at p=0 (no clip); shrinks to the card slot (in pre-scale points) at p=1.
        let bleed: CGFloat = 160
        let maskSize = CGSize(
            width: miniLerp(container.width + bleed * 2, card.width / max(targetScale, 0.01), p),
            height: miniLerp(container.height + bleed * 2, card.height / max(targetScale, 0.01), p)
        )

        let containerCenter = CGPoint(x: container.width / 2, y: container.height / 2)
        let offset = CGSize(
            width: miniLerp(0, card.midX - containerCenter.x, p),
            height: miniLerp(0, card.midY - containerCenter.y, p)
        )
        // Corner radius is applied pre-scale, so divide by scale to keep it visually constant.
        let cornerRadius = MiniPlayerMetrics.cornerRadius * min(p * 2.5, 1) / max(scale, 0.01)
        return (scale, offset, maskSize, cornerRadius)
    }

    private func nearestCorner(toCenter c: CGPoint, container: CGSize) -> MiniPlayerCorner {
        let left = c.x < container.width / 2
        let top = c.y < container.height / 2
        switch (top, left) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    /// Commit the pull-down gesture into the mini card, seeding the spring with the
    /// gesture's exit velocity so a flick feels continuous. Falls back to the old
    /// slide-off dismiss when there is no overlay host to minimize into.
    private func commitMinimize(velocity: CGFloat, distance: CGFloat, containerHeight: CGFloat) {
        guard let minimize = playerOverlayMinimize else {
            withAnimation(.easeIn(duration: 0.18)) {
                interactiveDismissOffset = CGSize(width: 0, height: containerHeight + 60)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                performPlayerDismiss()
            }
            return
        }
        timer?.invalidate()
        showControls = false
        let remaining = max(1, (1 - miniProgress) * distance)
        // Seed the spring with the gesture's normalized velocity (clamped so a release near
        // the end doesn't produce an absurd initial velocity).
        let springV = min(max(Double(velocity) / Double(remaining), -25), 25)
        withAnimation(.interpolatingSpring(stiffness: 320, damping: 30, initialVelocity: springV)) {
            miniProgress = 1
        }
        minimize()
    }

    private func handleMiniCardDragChanged(
        translation: CGSize, card: CGRect, container: CGSize
    ) {
        // Mutate the isolated model directly — the body does not observe it, so only
        // `MiniCardDragLayer` re-renders and the video is left untouched. Offset and fade are set
        // together so the whole card group moves and dims in the same tick (no lockstep drift).
        cardDrag.offset = translation
        let center = CGPoint(x: card.midX + translation.width, y: card.midY + translation.height)
        let frac = MiniPlayerDismissPolicy.offscreenFraction(
            center: center, card: card.size, container: container
        )
        cardDrag.dismissOpacity = MiniPlayerDismissPolicy.liveOpacity(offscreenFraction: frac)
    }

    private func handleMiniCardDragEnded(
        translation: CGSize, velocity: CGSize, container: CGSize, safeArea: EdgeInsets
    ) {
        let card = miniCardRect(container: container, safeArea: safeArea)
        let draggedCenter = CGPoint(
            x: card.midX + translation.width,
            y: card.midY + translation.height
        )

        // Dismiss ONLY when the card has actually been dragged out of the app — half of it past a
        // left, right, or bottom edge at the moment of release. This is position-only on purpose:
        // a quick flick that doesn't physically leave the screen must re-dock, not close (a fast
        // horizontal swipe from a top corner used to close via velocity projection). The top edge
        // is excluded by `offscreenFraction`, so an upward drag always re-docks.
        let liveFrac = MiniPlayerDismissPolicy.offscreenFraction(
            center: draggedCenter, card: card.size, container: container
        )
        if liveFrac >= MiniPlayerDismissPolicy.releaseFraction {
            dismissMiniCardOffscreen(
                draggedCenter: draggedCenter, card: card, container: container
            )
            return
        }

        // Not dismissed → settle to the nearest corner. Velocity still projects the *corner*
        // choice so a flick toward a corner snaps there, but it can no longer trigger a close.
        let projected = CGPoint(
            x: draggedCenter.x + velocity.width * 0.12,
            y: draggedCenter.y + velocity.height * 0.12
        )
        let target = nearestCorner(toCenter: projected, container: container)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            miniCorner = target
            cardDrag.offset = .zero
            cardDrag.dismissOpacity = 1
        }
    }

    /// Slide the card the rest of the way off whichever edge it has cleared most, fade it out,
    /// then tear the player down. The exit direction continues the user's own drag rather than
    /// snapping to a fixed side.
    private func dismissMiniCardOffscreen(
        draggedCenter: CGPoint, card: CGRect, container: CGSize
    ) {
        let halfW = card.width / 2
        let offLeft = halfW - draggedCenter.x
        let offRight = draggedCenter.x + halfW - container.width
        let offBottom = draggedCenter.y + card.height / 2 - container.height

        var exit = cardDrag.offset
        // Continue off whichever edge the card has already left the most.
        if offBottom >= max(offLeft, offRight) {
            exit.height += container.height - draggedCenter.y + card.height
        } else if offLeft >= offRight {
            exit.width -= draggedCenter.x + card.width
        } else {
            exit.width += container.width - draggedCenter.x + card.width
        }

        withAnimation(.easeIn(duration: 0.2)) {
            cardDrag.offset = exit
            cardDrag.dismissOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            performPlayerDismiss()
        }
    }

    private func interactiveDismissDragGesture(
        containerSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onChanged { value in
                if isMiniCommitted { return }  // mini card handles its own gestures
                if showTrackSettings || showSubtitleAppearance { return }
                if videoZoomScale > 1.02 || isScrubbing { return }
                // While a 2x speed-hold is active it owns the touch until finger-up; the
                // dismiss drag must not fight it (was the "drag-down vs long-press" conflict).
                if isFastForwarding { return }

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
                    if interactiveDismissAxis == nil,
                       FullscreenPlayerPullDownPolicy.shouldActivate(translation: t),
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
                    // Drive the mini-player morph directly with the finger.
                    let dist = pullDownDragDistance(container: containerSize)
                    miniProgress = FullscreenPlayerPullDownPolicy.progress(
                        translationHeight: t.height,
                        fullDistance: dist
                    )
                case .none:
                    break
                }

                if interactiveDismissAxis != nil {
                    cancelSpeedHoldBecauseDismissDragRecognized()
                }
            }
            .onEnded { value in
                if isMiniCommitted { return }
                if showTrackSettings || showSubtitleAppearance {
                    resetInteractiveDismissTracking()
                    return
                }

                let axis = interactiveDismissAxis
                guard videoZoomScale <= 1.02, !isScrubbing else {
                    resetInteractiveDismissTrackingWithAnimation()
                    if miniProgress > 0 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { miniProgress = 0 }
                    }
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

                interactiveDismissAxis = nil
                switch axis {
                case .edgeBack:
                    let progressed = layoutDirection == .leftToRight ? t.width : -t.width
                    let predProg = layoutDirection == .leftToRight ? pred.width : -pred.width
                    if progressed > min(cw * 0.28, 130) || predProg > 200 {
                        let targetX: CGFloat = layoutDirection == .leftToRight ? cw + 60 : -(cw + 60)
                        withAnimation(.easeIn(duration: 0.18)) {
                            interactiveDismissOffset = CGSize(width: targetX, height: 0)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            performPlayerDismiss()
                        }
                    } else {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            interactiveDismissOffset = .zero
                        }
                    }
                case .pullDown:
                    // A flick can commit only after meaningful travel; tiny fast touch
                    // drift must never throw the player into the mini card.
                    let dist = pullDownDragDistance(container: containerSize)
                    let vy = value.velocity.height
                    let projected = FullscreenPlayerPullDownPolicy.progress(
                        translationHeight: value.predictedEndTranslation.height,
                        fullDistance: dist
                    )
                    let commitMini = FullscreenPlayerPullDownPolicy.shouldCommit(
                        progress: miniProgress,
                        projectedProgress: projected,
                        velocityY: vy
                    )
                    if commitMini {
                        commitMinimize(
                            velocity: vy,
                            distance: FullscreenPlayerPullDownPolicy.activeDistance(
                                fullDistance: dist
                            ),
                            containerHeight: ch
                        )
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            miniProgress = 0
                        }
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

                HiddenAirPlayRoutePicker(trigger: airPlayPickerSignal)
                    .frame(width: 44, height: 44)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(-10)

                ZStack {
                    VideoZoomPanLayer(
                        model: videoZoomPan,
                        pinchBase: videoPinchBase,
                        zoomMax: videoZoomMax,
                        panCommitted: videoPanCommitted,
                        aspectFillScale: videoAspectFillScale,
                        viewportSize: videoViewportSize,
                        containerSize: videoContainerSize,
                        pinchAnchor: pinchAnchorState
                    ) {
                        ZStack {
                            if let cast = player.castController {
                                KSPlayerVideoSurface(
                                    engine: player.engine,
                                    cast: cast,
                                    manualPiPTrigger: pipManualSignal,
                                    pipEnabled: pipEnabled,
                                    continuePlayingInBackground: continuePlayingInBackground
                                )
                                .id("KSPlaybackSurface")
                            }
                        }
                        .frame(width: fittedSize.width, height: fittedSize.height)
                    }
                }
                // Clip to the screen so the `.fill` crop never bleeds past the viewport into
                // the chrome. Only Fill overflows, so the clip (an offscreen compositing pass
                // that was adding jank on open / pull-down) is skipped in fit/center.
                .frame(width: geo.size.width, height: geo.size.height)
                .modifier(ConditionalClip(active: selectedAspectMode == .fill))
                .allowsHitTesting(false)  // tüm touch UIKit overlay'de; video katmanı hit-test almaz
                .zIndex(0)

                // Tap/pinch/pan UIKit overlay'inde. Pinch midpoint callback ile zoom anchor
                // offset hesaplanır; pan yalnızca zoomluyken enabled.
                PlayerMediaKitStyleTouchOverlay(
                    showControls: $showControls,
                    isSeekDisabled: isCenterTransportLoading,
                    videoZoomScale: videoZoomScale,
                    isSpeedHoldActive: isFastForwarding,
                    isSpeedHoldEnabled: speedUpOnLongPress
                        && player.isPlaying
                        && interactiveDismissAxis == nil,
                    edgeSliderTrackSize: CGSize(
                        width: isCompactWidth ? 52 : 64,
                        height: isCompactWidth ? 160 : 180
                    ),
                    edgeSliderLeadingInset: 16 + outerSafeAreaInsets.leading,
                    edgeSliderTrailingInset: 16 + outerSafeAreaInsets.trailing,
                    interactionEnabled: miniProgress < 0.02,
                    onResetTimer: { resetTimer() },
                    onInvalidateTimer: { timer?.invalidate() },
                    onSpeedHoldBegan: { applySpeedHoldBegan() },
                    onSpeedHoldEnded: { applySpeedHoldEnded() },
                    onVideoPinchBegan: { location, containerBounds in
                        handleVideoPinchBegan(at: location, containerSize: containerBounds)
                    },
                    onVideoPinchChanged: { videoZoomPan.pinchLive = $0 },
                    onVideoPinchEnded: { handleVideoPinchGestureEnded() },
                    onVideoPanChanged: { translation in
                        videoZoomPan.panLive = translation
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
                    .opacity(fullChromeOpacity)
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
                    .opacity(fullChromeOpacity)
                    // Invisible (opacity ~0) but still-hittable fullscreen chrome must not
                    // intercept taps during the minimize/expand morph — otherwise a stray tap
                    // on the scaled-down invisible close/play button could tear down or pause.
                    // Only interactive when essentially fullscreen.
                    .allowsHitTesting(miniProgress < 0.02)
                    .zIndex(30)

                    if isLiveStream, let programme = currentNowNext?.now {
                        PlayerProgrammeStrip(programme: programme)
                            .frame(maxWidth: 240, alignment: .leading)
                            .clipped()
                            .padding(.leading, 20 + outerSafeAreaInsets.leading)
                            .padding(.bottom, 20 + outerSafeAreaInsets.bottom)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .bottomLeading
                            )
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .opacity(fullChromeOpacity)
                            .zIndex(31)
                    }

                    PlayerControlCenterStyleEdgeSliders(
                        player: player,
                        systemVolume: systemVolumeBridge,
                        safeAreaInsets: outerSafeAreaInsets,
                        isCompactWidth: isCompactWidth
                    ) {
                        resetTimer()
                    }
                    .opacity(fullChromeOpacity)
                    .allowsHitTesting(miniProgress < 0.02)
                    .zIndex(32)
                }

                // Kontroller gizliyken de yükleme/buffering geri bildirimi: yavaş panel
                // açılışında 5 sn sonra kontroller kaybolunca kullanıcı simsiyah ekranla
                // baş başa kalıyordu. Kontroller açıkken ortadaki buton zaten spinner
                // gösterdiği için burada yalnızca !showControls durumunda çizilir.
                if isCenterTransportLoading && !showControls {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                        .padding(18)
                        .background(.black.opacity(0.35), in: Circle())
                        .allowsHitTesting(false)
                        .opacity(fullChromeOpacity)
                        .zIndex(25)
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
                    .opacity(fullChromeOpacity)
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
                    .opacity(fullChromeOpacity)
                    .zIndex(40)
                    .allowsHitTesting(false)
                }

                if let seconds = autoAdvanceSecondsRemaining {
                    HStack(spacing: 10) {
                        Button {
                            cancelAutoAdvanceCountdown()
                        } label: {
                            Text(L("common.cancel"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        }

                        Button {
                            triggerAutoAdvance()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.footnote.weight(.bold))
                                Text(L("player.autonext.countdown", seconds))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.white, in: Capsule())
                        }
                    }
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16 + outerSafeAreaInsets.trailing)
                    .padding(.bottom, (showControls ? 92 : 16) + outerSafeAreaInsets.bottom)
                    // Krom görünürlüğü animasyonsuz (Transaction.disablesAnimations)
                    // değişebildiği için padding'i kendi animasyonuyla sür — kullanıcı
                    // "İptal"e uzanırken butonlar 76pt ışınlanıyordu.
                    .animation(.easeInOut(duration: 0.2), value: showControls)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .opacity(fullChromeOpacity)
                    .zIndex(41)
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
                    .opacity(fullChromeOpacity)
                    .zIndex(10)
                }

                // Hata banner'ı krom görünürlüğünden bağımsız: 5 sn auto-hide sonrası
                // patlayan yayında kullanıcı sessiz siyah ekranla kalmasın.
                if hasPlaybackFailure, let msg = player.playbackFailureMessage {
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
                    .opacity(fullChromeOpacity)
                    .zIndex(25)
                }

            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { syncVideoLayout(container: geo.size) }
            .onChange(of: geo.size) { _, new in syncVideoLayout(container: new) }
            .onChange(of: sourceVideoAspectRatio) { _, _ in syncVideoLayout(container: geo.size) }
            .onChange(of: videoAspectModeRaw) { _, _ in syncVideoLayout(container: geo.size) }
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
            startScale: effectiveVideoScale,
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
        videoPinchBase = min(max(videoPinchBase * videoZoomPan.pinchLive, 1), videoZoomMax)
        videoZoomPan.pinchLive = 1
        if videoPinchBase < 1.02 {
            videoPinchBase = 1
            videoPanCommitted = .zero
        } else {
            commitVideoPanClamp()
        }
    }

    private func handleVideoPanEnded(translation: CGSize) {
        let maxX = videoPanBounds.width
        let maxY = videoPanBounds.height
        let combined = CGSize(
            width: videoPanCommitted.width + translation.width,
            height: videoPanCommitted.height + translation.height
        )
        videoPanCommitted = CGSize(
            width: min(max(combined.width, -maxX), maxX),
            height: min(max(combined.height, -maxY), maxY)
        )
        videoZoomPan.panLive = .zero
    }

    private func commitVideoPanClamp() {
        let maxX = videoPanBounds.width
        let maxY = videoPanBounds.height
        videoPanCommitted = CGSize(
            width: min(max(videoPanCommitted.width, -maxX), maxX),
            height: min(max(videoPanCommitted.height, -maxY), maxY)
        )
    }

    /// Recomputes the fitted frame + `.fill` cover scale for a container size and re-clamps
    /// the pan. Called on appear, container resize, source-ratio change, and mode change.
    private func syncVideoLayout(container: CGSize) {
        let fitted = fittedVideoSize(in: container)
        videoViewportSize = fitted
        videoContainerSize = container
        videoAspectFillScale = aspectFillScale(viewport: container, fitted: fitted)
        commitVideoPanClamp()
    }

    /// Builds the Now Playing presentation, folding in the current EPG programme
    /// (used as the Now Playing title on live channels).
    private func makePresentation() -> PlaybackPresentation {
        let programme = currentNowNext?.now
        return PlaybackPresentation(
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            isLive: isLiveStream,
            programmeTitle: programme?.title,
            programmeInterval: programme.map { DateInterval(start: $0.start, end: max($0.start, $0.stop)) }
        )
    }

    private func saveWatchHistory(tags: WatchHistoryTags? = nil) {
        // Catch-up (timeshift) sessions must not persist history: the key would
        // collide with the channel's live row and its resume time is meaningless
        // once the archive window rolls past.
        if suppressWatchHistory { return }
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
        // Canlı yayında mpv duration çoğunlukla 0 kalır; guard'ı canlıda atlamazsak
        // "son izlenen kanallar" hiç dolmaz. VOD/dizide geçerli süre şartı sürer.
        guard duration > 0 || resolvedTags.type == "live" else { return }

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
                SyncEngine.shared.enqueueProgressChange(history)
            } catch {
                log.error("Failed to save watch history: \(error)")
            }
        }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            glassIconButton(systemName: "xmark", size: 44) { performPlayerDismiss() }
                .accessibilityLabel(L("common.close"))

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
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            // Long channel metadata must never push trailing controls off-screen.
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if let onNavigate = onNavigateToDetail {
                    let targetId = (type == "series" ? seriesId : streamId) ?? streamId
                    onNavigate(type, targetId)
                    performPlayerDismiss()
                }
            }

            HStack(spacing: 2) {
                topChromeActions
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        // The containing chrome already has 12pt + safe-area padding. A second
        // 20pt inset made the live-TV toolbar overflow on compact phones.
        .padding(.horizontal, isCompactWidth ? 0 : 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var topChromeActions: some View {
        if isCompactWidth {
            favoriteTopChromeAction
            airPlayTopChromeAction
            compactTopChromeMoreMenu
        } else {
            favoriteTopChromeAction

            groupedCapsuleButton(systemName: selectedAspectMode.iconName) {
                cycleVideoAspectMode()
            }
            .accessibilityLabel(selectedAspectMode.accessibilityLabel)

            if canShowPiPTopChromeAction {
                groupedCapsuleButton(systemName: "pip") {
                    requestPictureInPicture()
                }
                .accessibilityLabel(L("player.a11y.pip"))
            }

            airPlayTopChromeAction

            groupedCapsuleButton(systemName: "textformat.size") {
                showSubtitleAppearance = true
            }
            .accessibilityLabel(L("player.a11y.subtitle_appearance"))

            // Hide track settings only once playback is actually on the AirPlay
            // target (local engine stopped -> empty track list). Stays visible
            // through the remux prepare/picker window so the toolbar does not
            // collapse the instant the AirPlay button is tapped.
            if !player.isAirPlayPlaybackActive {
                groupedCapsuleButton(systemName: "gearshape") {
                    openTrackSettings()
                }
                .accessibilityLabel(L("player.a11y.track_settings"))
            }
        }
    }

    @ViewBuilder
    private var favoriteTopChromeAction: some View {
        if let isFav = isFavorite, let toggle = onToggleFavorite {
            groupedCapsuleButton(systemName: isFav ? "star.fill" : "star") {
                toggle()
            }
            .accessibilityLabel(isFav ? L("favorites.remove") : L("favorites.add"))
        }
    }

    @ViewBuilder
    private var airPlayTopChromeAction: some View {
        if player.isAirPlayVideoCapable {
            if player.needsAirPlayPreparation {
                // UHF akışı: önce remux hazırlanır (loading), sonra seçici açılır.
                if isPreparingAirPlay {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 40, height: 34)
                } else {
                    groupedCapsuleButton(systemName: "airplay.video") {
                        prepareAndPresentAirPlay()
                    }
                    .accessibilityLabel("AirPlay")
                }
            } else {
                AirPlayRoutePickerButton()
                    .frame(width: 40, height: 34)
                    .accessibilityLabel("AirPlay")
            }
        }
    }

    private var compactTopChromeMoreMenu: some View {
        Menu {
            Button {
                resetTimer()
                cycleVideoAspectMode()
            } label: {
                Label(selectedAspectMode.accessibilityLabel, systemImage: selectedAspectMode.iconName)
            }

            if canShowPiPTopChromeAction {
                Button {
                    resetTimer()
                    requestPictureInPicture()
                } label: {
                    Label(L("player.a11y.pip"), systemImage: "pip")
                }
            }

            Button {
                resetTimer()
                showSubtitleAppearance = true
            } label: {
                Label(L("player.a11y.subtitle_appearance"), systemImage: "textformat.size")
            }

            if !player.isAirPlayPlaybackActive {
                Button {
                    resetTimer()
                    openTrackSettings()
                } label: {
                    Label(L("player.a11y.track_settings"), systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("detail.show_more"))
    }

    private var canShowPiPTopChromeAction: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
            && pipEnabled
            // Hide PiP only once the video is actually on the AirPlay target
            // (local surface shows the placeholder). Keep it available while the
            // remux cast is still preparing / awaiting device selection.
            && !player.isAirPlayPlaybackActive
    }

    private func cycleVideoAspectMode() {
        resetVideoTransformForAspectSwitch()
        videoAspectModeRaw = nextAspectMode.rawValue
    }

    private func requestPictureInPicture() {
        guard canEnterPiPNow else { return }
        pipManualSignal += 1
    }

    private func prepareAndPresentAirPlay() {
        isPreparingAirPlay = true
        player.prepareAirPlay { success in
            isPreparingAirPlay = false
            if success { airPlayPickerSignal += 1 }
        }
    }

    private func openTrackSettings() {
        player.updateTracks()
        showTrackSettings = true
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
                .frame(width: 44, height: 44)  // HIG minimum dokunma hedefi
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
            if effectiveSeekable && !isCenterTransportLoading {
                transparentTransportButton(
                    systemName: "gobackward.15",
                    symbolSize: transportSkipSymbol,
                    hitFrame: transportSkipHit
                ) {
                    player.jump(seconds: -15)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                .accessibilityLabel(L("player.a11y.skip_back_15"))
                .disabled(hasPlaybackFailure)
                .opacity(hasPlaybackFailure ? 0.4 : 1)
            }

            centerPlayPauseOrLoadingButton

            if effectiveSeekable && !isCenterTransportLoading {
                transparentTransportButton(
                    systemName: "goforward.15",
                    symbolSize: transportSkipSymbol,
                    hitFrame: transportSkipHit
                ) {
                    player.jump(seconds: 15)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                .accessibilityLabel(L("player.a11y.skip_forward_15"))
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
                .accessibilityLabel(player.isPlaying ? L("player.a11y.pause") : L("player.a11y.play"))
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
                        .accessibilityLabel(L("player.a11y.previous_channel"))
                        .disabled(!canGoToPreviousChannel)
                        .opacity(canGoToPreviousChannel ? 1 : 0.38)

                        glassIconButton(systemName: "chevron.right.circle.fill", size: 44, symbolSize: 17) {
                            onNextChannel?()
                        }
                        .accessibilityLabel(L("player.a11y.next_channel"))
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
                    .accessibilityLabel(L("player.a11y.previous_episode"))
                    .disabled(!canGoToPreviousEpisode)
                    .opacity(canGoToPreviousEpisode ? 1 : 0.38)

                    glassIconButton(systemName: "forward.end.fill", size: 44, symbolSize: 17) {
                        onNextEpisode?()
                    }
                    .accessibilityLabel(L("player.a11y.next_episode"))
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
                    .accessibilityLabel(L("player.a11y.previous_item"))
                    .disabled(!canGoToPreviousChannel)
                    .opacity(canGoToPreviousChannel ? 1 : 0.38)

                    glassIconButton(systemName: "forward.end.fill", size: 44, symbolSize: 17) {
                        onNextChannel?()
                    }
                    .accessibilityLabel(L("player.a11y.next_item"))
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
                    // Each drag tick postpones auto-hide; otherwise a >5 s scrub would
                    // remove the timeline mid-gesture (drag cancelled, seek lost).
                    resetTimer()
                }
            )
            .layoutPriority(1)
            // DragGesture VoiceOver altında erişilemez; kaydırıcıyı ayarlanabilir öğe
            // olarak sun (yan parlaklık/ses slider'larıyla aynı desen). ±15 sn adım,
            // mevcut goforward/gobackward.15 butonlarıyla tutarlı.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("player.a11y.playback_position"))
            .accessibilityValue("\(formatMs(Int(player.timeMs))) / \(totalDurationLabel)")
            .accessibilityAdjustableAction { direction in
                guard effectiveSeekable else { return }
                resetTimer()
                switch direction {
                case .increment: player.jump(seconds: 15)
                case .decrement: player.jump(seconds: -15)
                @unknown default: break
                }
            }

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
            && player.engine.isPlaybackEstablished
            && !player.engine.isPaused
            && !player.engine.isBuffering
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
            // Never hide the chrome mid-scrub: removing the timeline cancels the drag
            // without onEditingChanged(false), leaking isScrubbing=true and dropping
            // the seek. A held-still thumb schedules no drag ticks, so guard here too.
            guard !isScrubbing else {
                resetTimer()
                return
            }
            // Cross-fade out like the native player instead of a hard cut.
            withAnimation(.easeInOut(duration: 0.28)) { showControls = false }
        }
    }

    private func resetVideoTransformForAspectSwitch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            videoPinchBase = 1
            videoZoomPan.pinchLive = 1
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

/// Applies `.clipped()` only when needed, so fit/center playback avoids the extra
/// offscreen compositing pass (cheaper on open and during the pull-down morph).
private struct ConditionalClip: ViewModifier {
    let active: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.clipped() } else { content }
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
        .navigationTitle(L("dashboard.channels"))
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
                .accessibilityLabel(L("common.back"))
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
