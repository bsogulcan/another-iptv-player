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
        // One walk over the catalog fills both results; mapping the sections first and
        // flattening them afterwards visited every channel twice on each open.
        var queue: [DBLiveStream] = []
        queue.reserveCapacity(store.liveStreams.count)
        var sections: [LiveChannelCategorySection] = []
        sections.reserveCapacity(store.liveCategories.count)
        for cat in store.liveCategories {
            guard let items = store.liveStreamsByCategoryId[cat.id], !items.isEmpty else { continue }
            var streams: [DBLiveStream] = []
            streams.reserveCapacity(items.count)
            for item in items {
                streams.append(item.stream)
                queue.append(item.stream)
            }
            sections.append(LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams))
        }
        return (queue, sections)
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
    /// Last-channel recall (live): the host remembers the channel that was playing
    /// before the current one. The button shows once the action exists.
    var canRecallLastChannel: Bool = false
    var onRecallLastChannel: (() -> Void)? = nil
    var channelPanelSections: [ChannelPanelSection] = []
    var currentChannelPanelItemId: String? = nil
    var onSelectChannelPanelItem: ((String) -> Void)? = nil
    var isLiveChannelSidePanelVisible: Bool = false
    var onToggleLiveChannelSidePanel: (() -> Void)? = nil
    var onVideoSurfaceTap: (() -> Void)? = nil
    var onNavigateToDetail: ((String, String) -> Void)? = nil
    /// A playback failure is on screen (the controller's silent retry has failed as
    /// well). The argument is how long this item had really been playing, in seconds.
    var onPlaybackFailure: ((TimeInterval) -> Void)? = nil

    /// Favori UI — nil ise buton gizli (Xtream şu an kullanmıyor).
    var isFavorite: Bool? = nil
    var onToggleFavorite: (() -> Void)? = nil

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
            canRecallLastChannel: canRecallLastChannel,
            onRecallLastChannel: onRecallLastChannel,
            channelPanelSections: channelPanelSections,
            currentChannelPanelItemId: currentChannelPanelItemId,
            onSelectChannelPanelItem: onSelectChannelPanelItem,
            isLiveChannelSidePanelVisible: isLiveChannelSidePanelVisible,
            onToggleLiveChannelSidePanel: onToggleLiveChannelSidePanel,
            onVideoSurfaceTap: onVideoSurfaceTap,
            onNavigateToDetail: onNavigateToDetail,
            onPlaybackFailure: onPlaybackFailure
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
    var canRecallLastChannel: Bool = false
    var onRecallLastChannel: (() -> Void)? = nil
    var channelPanelSections: [ChannelPanelSection] = []
    var currentChannelPanelItemId: String? = nil
    var onSelectChannelPanelItem: ((String) -> Void)? = nil
    var isLiveChannelSidePanelVisible: Bool = false
    var onToggleLiveChannelSidePanel: (() -> Void)? = nil
    var onVideoSurfaceTap: (() -> Void)? = nil
    var onNavigateToDetail: ((String, String) -> Void)? = nil
    var onPlaybackFailure: ((TimeInterval) -> Void)? = nil

    /// Playing time of the current item, counted from clock ticks, for
    /// `onPlaybackFailure`. Held via `@State` but never observed.
    private final class PlayedTimeTracking {
        private var identity: String?
        private var lastClockMs: Int64 = 0
        private var playedMs: Int64 = 0

        /// Only ordinary forward progress counts: a seek, a reload or a new item moves
        /// the clock by more than a tick does.
        func noteClockTick(_ timeMs: Int64, identity newIdentity: String) {
            defer { lastClockMs = timeMs }
            guard identity == newIdentity else {
                identity = newIdentity
                playedMs = 0
                return
            }
            let step = timeMs - lastClockMs
            if step > 0, step <= 3_000 { playedMs += step }
        }

        func playedSeconds(identity current: String) -> TimeInterval {
            identity == current ? TimeInterval(playedMs) / 1000 : 0
        }
    }

    @State private var playedTimeTracking = PlayedTimeTracking()

    @StateObject private var player = VideoPlayerController()
    /// Route detection for the AirPlay control (dimmed when nothing could receive a cast).
    @StateObject private var airPlayRoutes = AirPlayRouteAvailability()

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

    /// Scrub state the player itself needs: the discrete flag (it gates the gestures and
    /// the auto-hide) and the seek target the thumb stays pinned to. The live scrub value
    /// lives in `PlayerScrubBar`, so a touch-move on the timeline never re-runs this body.
    @State private var isScrubbing = false
    @State private var lockedSliderValue: Double?
    @State private var sliderUnlockGeneration = 0
    @State private var showTrackSettings = false
    @State private var showSubtitleAppearance = false
    @State private var isFastForwarding = false
    /// Picture in Picture bookkeeping. Held via `@State` but never observed.
    private final class PictureInPictureTracking {
        /// Last value seen from the controller: its publisher replays the current value
        /// to every new subscription, and only a change may act.
        var lastActive = false
        /// This player docked itself because a PiP window opened over it, and nothing
        /// has moved it since. Only then does the end of PiP bring it back.
        var minimizedForPictureInPicture = false
    }

    @State private var pipTracking = PictureInPictureTracking()
    @State private var airPlayPickerSignal = 0
    /// The system device list of the visible AirPlay picker is on screen. The picker
    /// lives in the chrome, so the chrome must stay up meanwhile: unmounting the picker
    /// loses its "list closed" callback, the only signal of a cancelled list.
    @State private var isAirPlayPickerListOpen = false
    /// The More menu was opened: the chrome hosts it, so auto-hide waits until a row is
    /// chosen or this moment passes. A deadline, not a flag: SwiftUI does not report a
    /// menu that was closed without a choice, and a flag would then never clear.
    @State private var moreMenuHoldUntil: Date?
    /// A programmatic open of the hidden route picker is waiting for the system to
    /// report the device list. The token keeps an older check from judging a newer open.
    @State private var isAwaitingHiddenAirPlayPicker = false
    @State private var hiddenAirPlayPickerCheckToken: UInt64 = 0
    /// The hidden picker did not bring up the device list (its private button was not
    /// found, or the tap was ignored): the AirPlay slot shows the visible system picker
    /// while a preparation runs, so the list can still be opened by hand.
    @State private var usesVisibleAirPlayPickerFallback = false
    /// "No AirPlay devices found" notice with its explicit "Try anyway" action.
    @State private var showsAirPlayUnavailableNotice = false
    @State private var airPlayUnavailableNoticeToken: UInt64 = 0
    /// The user closed the "Sound is playing on <device>" pill. It covers one occurrence
    /// of that state and is cleared when the occurrence ends (see `audioOnlyAirPlayOverlay`).
    @State private var isAudioOnlyAirPlayPillDismissed = false
    /// VoiceOver or Switch Control is running. The chrome is their only way to the
    /// controls, so it does not auto-hide; mirrored into state so a change re-renders.
    @State private var isAssistiveTechRunning =
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    /// Minutes chosen for the running sleep timer (the controller publishes only its end).
    @State private var sleepTimerChoiceMinutes = 0
    /// Bumped while a sleep timer runs so the menu row's remaining time is re-read.
    @State private var sleepTimerMenuTick: UInt64 = 0
    /// iPhone landscape is compact height; decides where the rotate and recall buttons sit.
    @Environment(\.verticalSizeClass) private var chromeVerticalSizeClass
    /// Transient AirPlay notice (why a cast ended / could not start), shown like the
    /// aspect toast. The token keeps an older notice's timer from hiding a newer one.
    @State private var castNoticeToastText: String?
    @State private var castNoticeToastToken: UInt64 = 0
    /// True once the logical loading flag has been continuously set for the spinner
    /// delay; lets a short post-seek rebuffer pass without flashing a spinner.
    @State private var loadingSpinnerDelayElapsed = false
    @State private var bitrateSamples: [(time: Date, bps: Double)] = []
    @State private var aspectToastText: String?
    @State private var aspectToastToken: UInt64 = 0
    /// HUD pills (aspect toast, 2x badge, countdown) drop their small slide and only
    /// fade when Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var hudReduceMotion
    /// Set while a load has not shown a picture yet; cleared when loading ends. Keeps
    /// the opening artwork up through the first buffering pass after "ready" (so it
    /// hands over to the first frame, not to black) without ever covering a later
    /// rebuffer.
    @State private var openingArtworkLatched = true
    /// Newest AirPlay log lines for the debug overlay, refreshed once a second while
    /// the overlay is mounted (never from the body: formatting the buffer is not free).
    @State private var debugAirPlayLogTail: [String] = []
    @State private var debugLogDidCopy = false
    @State private var debugLogCopyToken: UInt64 = 0

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
    /// Set through `.updating`, so SwiftUI resets it when a dismiss drag is cancelled
    /// (second finger, system interruption, rotation), where `onEnded` never runs.
    @GestureState private var isDismissDragInFlight = false

    /// Bookkeeping for the exits in flight. Held via `@State` but never observed: it is
    /// written on drag events and must not re-evaluate the body.
    private final class DismissTracking {
        /// True from the first event of a dismiss drag until its `onEnded` runs. Still
        /// set once `isDismissDragInFlight` has dropped means the drag was cancelled.
        var dragAwaitsEnd = false
        /// Drag translation when the pull-down axis locked. Progress and the
        /// finger-follow offset are measured from here, so a late lock does not jump.
        var activationTranslation: CGSize = .zero
        /// Finger position (container space) when the pull-down axis locked.
        var activationLocation: CGPoint = .zero
        /// Playback identity the close exit paused, if it paused anything. A presentation
        /// that replaces the one being closed with the same item does not reload it, so
        /// it has to resume.
        var closePausedIdentity: String?
        /// Uptime of the last edge-back release. Its spring back (or slide off) holds
        /// no morph state, so `isTouchPartOfDismissDrag` reads this instead.
        var edgeBackReleaseUptime: TimeInterval = -.infinity
        /// Identifies the morph settle animation in flight: one that finishes late must
        /// not end the settling state of a newer one.
        var settleGeneration: UInt64 = 0
    }

    @State private var dismissTracking = DismissTracking()
    /// The close exit (X) is running: the player shrinks and fades before the
    /// presentation clears.
    @State private var isClosing = false
    @Environment(\.accessibilityReduceMotion) private var exitReduceMotion
    /// Stands in for the spring of an automatic minimize or expand under Reduce Motion:
    /// shorter than a display frame, so the player lands instead of travelling. Still an
    /// animation (not a disabled transaction) so the settle's completion runs as usual.
    private static let reducedMotionMorphAnimation: Animation = .linear(duration: 0.01)

    /// This player holds the app in landscape (see `toggleLandscapeFullscreen`).
    @State private var landscapeForced = false
    /// The window the player is mounted in, for orientation requests to its own scene.
    @State private var windowBox = PlayerWindowBox()

    /// Hardware-keyboard focus for the fullscreen player.
    @FocusState private var isHardwareKeyboardFocused: Bool
    /// System volume to return to when the `m` key unmutes.
    @State private var volumeBeforeKeyboardMute: Float?

    /// Throttle for the pointer-reveal of the chrome. Held via `@State` but never
    /// observed: hover reports every pointer move, and none of them may re-evaluate
    /// the body.
    private final class PointerRevealTracking {
        var lastRevealUptime: TimeInterval = -.infinity
    }

    @State private var pointerRevealTracking = PointerRevealTracking()

    /// Mini player morph state. `morph.progress` drives the whole full↔mini transform
    /// (0 = fullscreen, 1 = docked mini card) and `morph.dismissOffset` is the live offset
    /// of a dismiss drag. Held via `@State` like `cardDrag`, so the body does NOT observe
    /// it: only the morph layers do, and a pull-down no longer re-evaluates this body on
    /// every touch-move. `miniCorner` is the docked corner; the live drag translation of
    /// the docked card lives in `cardDrag`.
    @State private var morph = MiniMorphModel()
    /// A morph settle animation (the release of a pull-down, the expand from the card) is
    /// running. See `isMorphEngaged`.
    @State private var isMorphSettling = false
    @State private var miniCorner: MiniPlayerCorner = .bottomTrailing
    /// Live docked-card drag translation. Held via `@State` so the body does NOT observe it —
    /// only `MiniCardDragLayer` does — keeping the drag from re-rendering the video subtree.
    @State private var cardDrag = MiniCardDragModel()
    /// Live channel banner + "next programme" state. Held via `@State` for the same
    /// reason as `cardDrag`: only the banner and the programme strip observe it, so the
    /// banner coming and going never re-renders this body.
    @State private var channelBanner = PlayerChannelBannerModel()
    /// Invalidates a pending "reveal chrome after expand" if the mode changes again first.
    @State private var expandControlsGeneration = 0
    /// True from the mini → fullscreen switch until the chrome is revealed. The status bar
    /// is visible on the docked card and again once the chrome shows; hiding it for the
    /// 0.44 s in between made the clock blink on every expand.
    @State private var isExpandingFromMini = false

    private var isMiniCommitted: Bool { overlayMode == .mini }

    /// The one discrete morph state the body reads: true from the moment a pull-down
    /// locks until its settle animation is done, and for as long as the card is docked.
    /// It mounts the card's shadow and chrome and takes the fullscreen layers out of hit
    /// testing. Derived, so nothing can leave it behind: an external minimize or expand
    /// moves `isMiniCommitted`, a drag moves the axis, a settle sets and clears its flag.
    ///
    /// The last term holds the state over the one pass in which a card that has just been
    /// told to expand is no longer docked and not settling yet (and keeps the old rule
    /// for any state none of the others names). It is a plain read of the model, not an
    /// observation: this body does not re-run when the progress moves.
    private var isMorphEngaged: Bool {
        isMiniCommitted
            || interactiveDismissAxis == .pullDown
            || isMorphSettling
            || morph.progress > MiniMorphGeometry.cardPiecesProgress
    }

    /// For a button action: the touch that is ending was a dismiss drag, not a tap. A
    /// pull-down or an edge-back swipe keeps the content under the finger, so a button
    /// the drag started on is still under it at release and SwiftUI runs its action;
    /// taking the fullscreen layers out of hit testing when the axis locks does not
    /// cancel a press that is already in flight. True whichever of the two runs first
    /// at release: the axis is still locked before the drag's `onEnded`, and after it
    /// the settle of a pull-down (to the card or back to fullscreen) holds the morph
    /// state, while an edge-back release is remembered for a short settle window.
    private var isTouchPartOfDismissDrag: Bool {
        interactiveDismissAxis != nil || isMorphEngaged
            || ProcessInfo.processInfo.systemUptime - dismissTracking.edgeBackReleaseUptime
                < Self.edgeBackReleaseSettleWindow
    }

    /// How long after an edge-back release a button action still counts as part of it.
    /// The action of the button under the finger runs in the same touch-up as the
    /// release, so this only has to outlast that event.
    private static let edgeBackReleaseSettleWindow: TimeInterval = 0.2

    /// For code that runs outside the body (taps, timers, tasks): the player is
    /// fullscreen, or already on its way back to it. Read from the model at that moment.
    private var isMorphAtFullscreen: Bool {
        morph.progress < MiniMorphGeometry.fullscreenProgress
    }

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
    /// A pinch that snaps between Fit and Fill animates the zoom first and switches the
    /// aspect mode when that animation is done. A newer pinch bumps the token, so the
    /// pending switch of an older one is dropped.
    @State private var pinchSnapToken: UInt64 = 0

    /// Side indicator of the double-tap seek, with the seconds added while it is up.
    private struct DoubleTapSeekIndicator: Equatable {
        let side: PlayerDoubleTapSeekPolicy.Side
        let seconds: Int
    }

    @State private var doubleTapSeekIndicator: DoubleTapSeekIndicator?
    @State private var doubleTapSeekIndicatorToken: UInt64 = 0
    /// The chrome a tap on a seek side has just revealed takes no touches for the
    /// length of a double tap: its second tap has to reach the surface and seek, not
    /// land on the close button, a skip button or a slider that faded in under the
    /// finger. The token keeps an older shield's timer from ending a newer one.
    @State private var isChromeTapShielded = false
    @State private var chromeTapShieldToken: UInt64 = 0

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
        /// 1 except in Fill at rest, where a pinch in may shrink the picture down to Fit.
        var zoomMin: CGFloat = 1
        let zoomMax: CGFloat
        let panCommitted: CGSize
        let aspectFillScale: CGFloat
        let viewportSize: CGSize
        let containerSize: CGSize
        let pinchAnchor: PinchAnchorState?
        @ViewBuilder var content: Content

        private var zoomScale: CGFloat {
            min(max(pinchBase * model.pinchLive, zoomMin), zoomMax)
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

    /// Bookkeeping of the history writes. Held via `@State` but never observed: it is
    /// written on clock ticks and must not re-evaluate the body.
    private final class HistorySaveTracking {
        /// Playback identity whose live row has been written (live writes one row per
        /// identity, not one every few seconds).
        var liveRowIdentity: String?
        /// Clock value of the previous tick, to tell a seek from normal progress.
        var lastClockMs: Int64?
        /// Invalidates a pending after-seek save (a newer jump, or new content).
        var seekSaveToken: UInt64 = 0
    }

    @State private var historyTracking = HistorySaveTracking()
    @State private var appliedPlaybackIdentity: String?
    /// Altyazı `update()` binary search + eşitlik kontrolü yapıyor, ama yine de her 120ms
    /// tetiklemek onChange closure kadar küçük bir yük. 200ms pencere imperceptible.


    private let videoZoomMax: CGFloat = 4

    /// Scale at which the fitted picture covers the screen, whatever the aspect mode
    /// (`videoAspectFillScale` holds the same value, but only while the mode is Fill).
    private var videoCoverScale: CGFloat {
        PlayerPinchAspectSnapPolicy.coverScale(
            fitted: videoViewportSize, container: videoContainerSize
        )
    }

    /// Floor of the pinch zoom: 1, except in Fill at rest, where pinching in may go down
    /// to the fitted picture on its way to Fit.
    private var videoZoomMin: CGFloat {
        PlayerPinchAspectSnapPolicy.minimumZoom(
            mode: selectedAspectMode,
            committedZoom: videoPinchBase,
            coverScale: videoCoverScale
        )
    }

    private var videoZoomScale: CGFloat {
        min(max(videoPinchBase * videoZoomPan.pinchLive, videoZoomMin), videoZoomMax)
    }

    /// Same gate as the skip buttons: seekable, not live, nothing failed.
    private var canDoubleTapSeek: Bool {
        effectiveSeekable && !hasPlaybackFailure
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

    /// Whether the active presentation has produced playback yet. Reads the same source
    /// `isCenterTransportLoading` does: the cast while it presents (the phone engine is
    /// stopped then and would report "not established" forever), the engine otherwise.
    private var isPresentationEstablished: Bool {
        if player.isCastPresenting {
            return player.castController?.isPlaybackEstablished == true
        }
        return player.engine.isReady && player.engine.isPlaybackEstablished
    }

    /// The spinner the user actually sees. `isCenterTransportLoading` stays the logical
    /// flag (it gates seeking); this one only decides the glyph. An opening stream shows
    /// the spinner at once, while a rebuffer on an established stream (every FFmpeg-path
    /// seek passes through one) has to last about 450 ms first, so skips do not flash
    /// it. It clears the moment loading ends.
    private var showsLoadingSpinner: Bool {
        guard isSpinnerCandidate else { return false }
        guard isPresentationEstablished else { return true }
        // A pause taken while buffering keeps reporting `.buffering` until the next
        // play. Show the play glyph there, or the spinner would hide the only control
        // that resumes playback.
        guard player.isPlaying else { return false }
        return loadingSpinnerDelayElapsed
    }

    /// What may put the spinner on screen: loading, or a seek the player has not
    /// confirmed yet. During a seek the layer keeps reporting "playing" (it raises no
    /// buffering state until the seek returns), so the picture used to sit frozen under
    /// the pause glyph for the length of a network seek. The seek is kept out of
    /// `isCenterTransportLoading` on purpose: that flag also disables double-tap
    /// seeking and the centre action, which must keep working while a seek is in flight.
    private var isSpinnerCandidate: Bool {
        if isCenterTransportLoading { return true }
        guard player.isSeekInFlight else { return false }
        // Same exclusions as the loading flag: a failure or the end shows its own
        // glyph, and under native AirPlay the phone-side layer says nothing about the TV.
        return !hasPlaybackFailure && player.state != .ended && !player.isAirPlayPlaybackActive
    }

    private static let loadingSpinnerDelayNanoseconds: UInt64 = 450_000_000

    /// Restarts the spinner delay whenever the spinner's condition flips; run from a
    /// `.task(id:)` so a condition that drops again cancels the pending reveal. A seek
    /// that turns into a rebuffer keeps the condition up, so the delay is not restarted.
    private func trackLoadingSpinnerDelay() async {
        if loadingSpinnerDelayElapsed { loadingSpinnerDelayElapsed = false }
        guard isSpinnerCandidate else { return }
        try? await Task.sleep(nanoseconds: Self.loadingSpinnerDelayNanoseconds)
        guard !Task.isCancelled else { return }
        loadingSpinnerDelayElapsed = true
    }

    /// Failed playback, or a live stream that ran into end-of-stream: there is nothing
    /// to resume, so the transport offers a reload instead of a dead play button.
    private var needsPlaybackRetry: Bool {
        hasPlaybackFailure || (isLiveStream && player.state == .ended)
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

    private static let closeExitDuration: TimeInterval = 0.25

    /// The dismiss action as of now. Exits that finish after an animation capture it
    /// before they start: the overlay host binds its closure to the presentation that is
    /// on screen, so a late call can never close an item presented in the meantime.
    private func capturedDismissAction() -> () -> Void {
        if let overlayDismiss = playerOverlayDismiss { return overlayDismiss }
        let dismiss = self.dismiss
        return { dismiss() }
    }

    /// Close (the X button, the mini card's X, a title tap): pause, shrink and fade the
    /// player inside this view, then clear the presentation. Teardown runs at removal, so
    /// the motion has to happen first; the host's own 0.14 s fade then has nothing left
    /// to show. Exits that already moved the player off screen call the captured action
    /// directly instead.
    private func performPlayerDismiss() {
        guard !isClosing else { return }
        // The next-episode countdown must not overtake an exit that is under way.
        cancelAutoAdvanceCountdown()
        let dismissNow = capturedDismissAction()
        // A cast that holds a route is parked at teardown and keeps playing on the TV
        // until the next stream takes it over; paused here, nothing could resume it.
        // Same test as the parking itself, so a cast without a route (which teardown
        // disposes) is still paused.
        let castOutlivesScreen =
            player.castController.map { $0.isEngaged && $0.hasRouteToPreserve } ?? false
        // Sound must not run on under a player that is fading away.
        let wasPlaying = player.isPlaying && !castOutlivesScreen
        dismissTracking.closePausedIdentity = wasPlaying ? appliedPlaybackIdentity : nil
        // An explicit pause, not a toggle: if playback stopped by itself in between,
        // a toggle would start it again under the closing player.
        if wasPlaying { player.pause() }
        timer?.invalidate()
        // The channel strip is a sibling the live shells draw above this view, so it
        // does not fade with it; the shells close it (animated) on this hook.
        if isLiveChannelSidePanelVisible { onVideoSurfaceTap?() }
        withAnimation(.easeOut(duration: Self.closeExitDuration)) {
            isClosing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeExitDuration) {
            // A newer presentation took over meanwhile and cancelled this exit.
            guard isClosing else { return }
            releaseForcedLandscape()
            dismissNow()
        }
    }

    /// A new item replaced the one being closed: the exit is void and the player has
    /// to be visible again.
    private func cancelCloseExitForNewPresentation() {
        guard isClosing else { return }
        isClosing = false
        // The exit stopped the chrome's hide timer; the player is staying after all.
        resetTimer()
        let pausedIdentity = dismissTracking.closePausedIdentity
        dismissTracking.closePausedIdentity = nil
        // A different item loads and plays by itself; the same item re-presented does
        // not reload, so undo the pause the exit took.
        if let pausedIdentity, pausedIdentity == playbackIdentity, !player.isPlaying {
            player.togglePlayPause()
        }
    }

    /// Sheets hand focus back only once their dismissal has finished.
    private func claimHardwareKeyboardFocusAfterSheet() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            claimHardwareKeyboardFocus()
        }
    }

    /// Scale anchor for the close exit: the docked card shrinks into itself, the
    /// fullscreen player into the centre.
    private func closeExitAnchor(card: CGRect, container: CGSize) -> UnitPoint {
        guard isMiniCommitted, container.width > 0, container.height > 0 else { return .center }
        return UnitPoint(x: card.midX / container.width, y: card.midY / container.height)
    }

    // MARK: - Landscape fullscreen

    /// True while this player holds the app in landscape.
    private var isLandscapeForced: Bool { landscapeForced }

    /// Enters landscape regardless of Portrait Orientation Lock, or leaves it again.
    /// iPhone only: resizable iPad windows ignore geometry requests.
    private func toggleLandscapeFullscreen() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        // Not during the morph: a rotation would resize the container under the running
        // animation, and a docked card has no fullscreen to rotate.
        guard !isMiniCommitted, !isExpandingFromMini, !isClosing,
              isMorphAtFullscreen, interactiveDismissAxis == nil else { return }
        if landscapeForced {
            releaseForcedLandscape()
        } else {
            landscapeForced = true
            PlayerOrientationLock.forceLandscape(in: windowBox.window)
        }
    }

    /// Puts the orientation lock back. Called on every way out of fullscreen (minimize,
    /// dismiss, disappear); a no-op unless this player forced landscape.
    private func releaseForcedLandscape() {
        guard landscapeForced else { return }
        landscapeForced = false
        PlayerOrientationLock.release(in: windowBox.window)
    }

    // MARK: - Hardware keyboard

    /// Keys are handled only while the player is fullscreen and nothing covers it. With
    /// the mini card docked they belong to the catalog (a search field needs its space
    /// and arrow keys).
    private var acceptsHardwareKeys: Bool {
        !isMiniCommitted && !isClosing && isMorphAtFullscreen
            && !showTrackSettings && !showSubtitleAppearance
    }

    /// `onKeyPress` only fires while a view inside the player holds focus. Claimed when
    /// the player appears, expands, or a sheet closes, and whenever the chrome toggles
    /// (a focused control that unmounts leaves focus nowhere).
    private func claimHardwareKeyboardFocus() {
        guard acceptsHardwareKeys, !isHardwareKeyboardFocused else { return }
        isHardwareKeyboardFocused = true
    }

    private func handleHardwareKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard acceptsHardwareKeys else { return .ignored }
        // Command / Control / Option combinations stay with the system.
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .ignored
        }
        switch press.key {
        case .space:
            performCenterTransportAction()
            return .handled
        case .leftArrow, .rightArrow:
            // Same rule as the on-screen skip buttons, which are not mirrored in
            // right-to-left languages either: left is back.
            guard effectiveSeekable, !hasPlaybackFailure else { return .ignored }
            player.jump(seconds: press.key == .leftArrow ? -15 : 15)
            return .handled
        case .upArrow, .downArrow:
            stepVolumeFromKeyboard(up: press.key == .upArrow)
            return .handled
        case .escape:
            minimizeFromKeyboard()
            return .handled
        default:
            break
        }
        switch press.characters.lowercased() {
        case "f":
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .ignored }
            toggleLandscapeFullscreen()
            return .handled
        case "m":
            toggleMuteFromKeyboard()
            return .handled
        default:
            return .ignored
        }
    }

    /// Escape leaves fullscreen the way a pull-down does. Without an overlay host there
    /// is no mini player to shrink into, so it closes instead.
    private func minimizeFromKeyboard() {
        guard let minimize = playerOverlayMinimize else {
            performPlayerDismiss()
            return
        }
        // `onChange(of: overlayMode)` settles the chrome and runs the morph.
        minimize()
    }

    /// Mute through the same system-volume path the volume capsule writes, so the
    /// capsule and the hardware buttons stay in step with it.
    private func toggleMuteFromKeyboard() {
        // Read from the bridge the controller owns; this body does not observe it.
        let volume = player.systemVolume
        let current = volume.outputVolume
        if current > 0 {
            volumeBeforeKeyboardMute = current
            volume.setOutputVolume(0)
        } else {
            volume.setOutputVolume(volumeBeforeKeyboardMute ?? 0.3)
            volumeBeforeKeyboardMute = nil
        }
    }

    /// One step of the up / down arrow keys: a sixteenth, like the hardware buttons,
    /// through the same system-volume path as the capsule.
    private func stepVolumeFromKeyboard(up: Bool) {
        let volume = player.systemVolume
        let step: Float = 1.0 / 16.0
        let next = min(max(volume.outputVolume + (up ? step : -step), 0), 1)
        guard next != volume.outputVolume else { return }
        volume.setOutputVolume(next)
    }

    // MARK: - Pointer

    /// A trackpad or mouse pointer moving over the fullscreen player shows the chrome
    /// and keeps it up while the pointer keeps moving, like the system player. Hover is
    /// reported for an indirect pointer only, so touch behaviour is unchanged. It only
    /// ever reveals the chrome and re-arms the auto-hide timer; it starts nothing else.
    private func revealChromeFromPointer() {
        // Same scope as the hardware keys (fullscreen, nothing covering the player),
        // and not while the chrome is deliberately down: the channel panel is open, a
        // dismiss drag or a morph is in flight, or the expand has not revealed it yet.
        guard acceptsHardwareKeys, !isLiveChannelSidePanelVisible,
              !isExpandingFromMini, !isMorphEngaged, interactiveDismissAxis == nil
        else { return }
        // Hover fires on every pointer move; twice a second is enough for both jobs.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - pointerRevealTracking.lastRevealUptime >= Self.pointerRevealInterval else { return }
        pointerRevealTracking.lastRevealUptime = now
        if !showControls {
            withAnimation(.easeInOut(duration: 0.28)) { showControls = true }
        }
        resetTimer()
    }

    private static let pointerRevealInterval: TimeInterval = 0.5

    /// Invisible focus target and window reader behind the player. The focus target is
    /// what lets `onKeyPress` on the container receive hardware keys; `.edit` keeps it
    /// focusable whether or not system-wide keyboard navigation is enabled.
    private var hardwareKeyboardAndWindowSupport: some View {
        ZStack {
            PlayerWindowReader(box: windowBox)
                .frame(width: 1, height: 1)
            Color.clear
                .frame(width: 1, height: 1)
                .focusable(!isMiniCommitted, interactions: .edit)
                .focused($isHardwareKeyboardFocused)
                .focusEffectDisabled()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let outerSafeAreaInsets = geo.safeAreaInsets
            // The true screen rect in this (safe-area) space. The content below is laid
            // out in it explicitly and transformed about its centre.
            let screen = screenFrame(container: containerSize, safeArea: outerSafeAreaInsets)
            let card = miniCardRect(container: containerSize, safeArea: outerSafeAreaInsets)
            ZStack {
                // The whole mini-card group is repositioned by the live drag inside
                // `MiniCardDragLayer`, which is the ONLY view that re-renders while dragging —
                // the masked/scaled video below is evaluated once and merely re-offset, so the
                // picture is never re-processed (which used to glitch the video mid-drag).
                MiniCardDragLayer(model: cardDrag) {
                    ZStack {
                        // Player content, transformed toward the floating mini card as the
                        // morph progresses. `MiniMorphLayer` observes the morph model and
                        // owns the card shadow and the mask / scale / offset of the
                        // content; this body only hands it the content, built once per
                        // body pass and never per frame of the morph. The content closure
                        // is unconditional, so the player subtree keeps its identity.
                        MiniMorphLayer(
                            model: morph,
                            card: card,
                            screen: screen,
                            containerWidth: containerSize.width,
                            targetScale: miniTargetScale(card: card, screen: screen),
                            showsCardShadow: isMorphEngaged
                        ) {
                            ZStack {
                                Color.black

                                playerChromeAndVideo(outerSafeAreaInsets: outerSafeAreaInsets)
                            }
                            // The player itself keeps the app's layout direction; only
                            // the layers that move it are pinned (see below).
                            .environment(\.layoutDirection, layoutDirection)
                        }
                        .simultaneousGesture(
                            interactiveDismissDragGesture(
                                containerSize: containerSize,
                                safeArea: outerSafeAreaInsets
                            )
                        )
                        // Once docked, stop the (visually card-sized but layout-full-screen)
                        // content from swallowing touches: SwiftUI `.mask` crops rendering only,
                        // not the hit region. `isMiniCommitted` only flips at commit, so the
                        // interactive pull-down morph is unaffected; card taps go to the chrome.
                        .allowsHitTesting(!isMiniCommitted)

                        // Floating mini card chrome (unscaled), tappable only once docked.
                        // Mounted with the morph state, placed and faded by its own layer.
                        if isMorphEngaged {
                            MiniMorphCardChromeLayer(model: morph, card: card) {
                                MiniPlayerChrome(
                                    player: player,
                                    cornerRadius: MiniPlayerMetrics.cornerRadius,
                                    isLoading: showsLoadingSpinner,
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
                                    },
                                    onDragCancelled: { handleMiniCardDragCancelled() }
                                )
                                .environment(\.layoutDirection, layoutDirection)
                            }
                            .allowsHitTesting(isMiniCommitted)
                        }
                    }
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            // Close exit: the whole group shrinks a little and fades before the
            // presentation clears. Reduce Motion keeps the fade and drops the shrink.
            .scaleEffect(
                isClosing && !exitReduceMotion ? 0.9 : 1,
                anchor: closeExitAnchor(card: card, container: containerSize)
            )
            .opacity(isClosing ? 0 : 1)
            .allowsHitTesting(!isClosing)
            // The layers above place and move the player with `.offset` / `.position`,
            // which SwiftUI mirrors in a right-to-left layout, while the drags that feed
            // them report physical translations: in Arabic the mini card and the
            // edge-back slide moved against the finger. Their geometry is physical
            // (`screenFrame`, `MiniPlayerMetrics.cardOrigin`), so they are laid out
            // left-to-right; the content inside gets the ambient direction back.
            .environment(\.layoutDirection, .leftToRight)
            .background(alignment: .topLeading) { hardwareKeyboardAndWindowSupport }
            .onKeyPress(phases: .down) { handleHardwareKeyPress($0) }
            // On the container, not on the video surface below the chrome: a pointer
            // resting on a button counts too.
            .onContinuousHover { phase in
                if case .active = phase { revealChromeFromPointer() }
            }
            .onChange(of: isDismissDragInFlight) { _, active in
                if !active { settleDismissDragIfCancelled() }
            }
            // iPad / geniş yatay düzende durum çubuğunu kontrollerle aç-kapa yapmak üst güvenli alanı
            // değiştirir; GeometryReader yüksekliği sıçrar. Telefonda (compact) eski davranış korunur.
            // Mini kartta durum çubuğu her zaman görünür.
            .statusBarHidden(statusBarHiddenInCurrentMode)
            // Let the home indicator auto-hide over fullscreen video (iPhone only).
            .persistentSystemOverlays(persistentSystemOverlaysInCurrentMode)
            // The timeline lives inside the chrome: once the chrome goes away an in-flight
            // scrub can no longer end, so close it here without seeking.
            .onChange(of: showControls) { _, visible in
                if !visible { cancelScrub() }
                // The picker went away with the chrome (minimize, close); its "list
                // closed" callback can no longer arrive to clear the flag.
                if !visible, isAirPlayPickerListOpen { isAirPlayPickerListOpen = false }
                // The More menu went away with the chrome as well.
                if !visible, moreMenuHoldUntil != nil { moreMenuHoldUntil = nil }
                // A focused chrome control that just unmounted leaves keyboard focus
                // nowhere; a tap that brought the chrome back is a cue to re-arm it too.
                claimHardwareKeyboardFocus()
            }
        .onAppear {
            Log.info("Playback", "Opening player: \(title)")
            resetTimer()
            player.setupAudioHandler()
            // Defer to the next run loop: the KSPlayer surface's view setup and
            // `play` can race within the same tick. First layout also relieves the main queue.
            DispatchQueue.main.async {
                applyPlaybackTransitionIfNeeded()
                applySelectedAspectMode(force: true)
                applySeriesEpisodeRemoteCommands()
                claimHardwareKeyboardFocus()
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
            // The same live channel was chosen again (the shells bump the presentation
            // id for that): nothing reloads by itself, so a channel that has ended or
            // failed is retried. Read before the transition below adopts a new item.
            let reselectedSameItem = appliedPlaybackIdentity == playbackIdentity
            applyPlaybackTransitionIfNeeded()
            if reselectedSameItem, isLiveStream, needsPlaybackRetry {
                player.retryCurrentLoad()
            }
            // A close exit still fading belongs to the item that was replaced.
            cancelCloseExitForNewPresentation()
            // So does a slide-off exit still in flight: its dismiss is void, so bring
            // the player back. A drag still under the finger keeps its offset and is
            // resolved by its own release.
            if interactiveDismissAxis == nil, morph.dismissOffset != .zero {
                morph.dismissOffset = .zero
            }
            // Presenting ends editing app-wide, which also drops the player's key focus.
            DispatchQueue.main.async { claimHardwareKeyboardFocus() }
        }
        .onChange(of: videoAspectModeRaw) { _, _ in
            applySelectedAspectMode()
            showAspectToast()
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
            // Whatever path removed the player, the app must not stay locked to landscape.
            releaseForcedLandscape()
        }
        .sheet(isPresented: $showTrackSettings) {
            // Both panels open at a compact height with the video visible and still
            // interactive behind them (see PlayerSettingsPanelPresentation).
            PlaybackTrackSettingsSheet(player: player, showDebugOverlay: $showDebugOverlay, streamURL: url)
                .playerSettingsPanelPresentation(isPresented: $showTrackSettings, isPlayerMinimized: isMiniCommitted)
        }
        .sheet(isPresented: $showSubtitleAppearance) {
            SubtitleAppearanceSheet(player: player)
                .playerSettingsPanelPresentation(isPresented: $showSubtitleAppearance, isPlayerMinimized: isMiniCommitted)
        }
        .onChange(of: showTrackSettings) { _, isOpen in
            if isOpen, showSubtitleAppearance {
                // The chrome stays reachable behind an open panel, so the other panel
                // can be requested: one sheet at a time.
                PlayerSettingsPanelPresentation.present($showTrackSettings, afterClosing: $showSubtitleAppearance)
            } else if isOpen { resetInteractiveDismissTracking() } else { claimHardwareKeyboardFocusAfterSheet() }
        }
        .onChange(of: showSubtitleAppearance) { _, isOpen in
            if isOpen, showTrackSettings {
                PlayerSettingsPanelPresentation.present($showSubtitleAppearance, afterClosing: $showTrackSettings)
            } else if isOpen { resetInteractiveDismissTracking() } else { claimHardwareKeyboardFocusAfterSheet() }
        }
        .onChange(of: player.isSeekable) { _, _ in checkAndPerformResume() }
        // The duration is published on the playback clock, which this body does not
        // observe. `dropFirst`: the publisher replays its current value to every new
        // subscription, and only a change may run the resume check (a replay right
        // after a content switch would still carry the previous item's duration). The
        // hop leaves the controller's sync pass, which is still publishing when the
        // clock announces the change, as `onChange` used to.
        .onReceive(player.clock.$durationMs.dropFirst()) { _ in
            DispatchQueue.main.async { checkAndPerformResume() }
        }
        .onAppear { startSaveHistoryTimer() }
        .onChange(of: seriesRemoteCommandsKey) { _, _ in
            applySeriesEpisodeRemoteCommands()
        }
        .onChange(of: player.videoBitrate) { _, newValue in
            appendBitrateSample(newValue)
        }
        // Real playing time of the item, for `onPlaybackFailure`. Received, not
        // observed: a tick runs this closure and never the body.
        .onReceive(player.clock.$timeMs) { timeMs in
            guard onPlaybackFailure != nil else { return }
            playedTimeTracking.noteClockTick(timeMs, identity: playbackIdentity)
        }
        // The message is published only after the controller's silent retry failed too.
        .onChange(of: hasPlaybackFailure) { _, failed in
            guard failed else { return }
            // The banner is on screen only; VoiceOver focus may be anywhere (or the
            // chrome hidden), so the failure is spoken as well. Same wording as the
            // banner's label and value.
            if let message = player.playbackFailureMessage, !message.isEmpty {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "\(L("player.playback_error")), \(message)"
                )
            }
            onPlaybackFailure?(playedTimeTracking.playedSeconds(identity: playbackIdentity))
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
                // The gesture path already animated the morph; here only settle chrome.
                // Covers any external minimize too (`isMiniCommitted` keeps the morph
                // state engaged from here on, so this animation needs no settle flag).
                timer?.invalidate()
                if showControls { showControls = false }
                if isExpandingFromMini { isExpandingFromMini = false }
                if morph.progress < 0.999 {
                    // Reduce Motion: an automatic minimize (button, Escape, accessibility
                    // action, PiP) lands on the card at once instead of scaling and
                    // moving the whole screen. A finger release has already animated.
                    withAnimation(
                        exitReduceMotion
                            ? Self.reducedMotionMorphAnimation
                            : .spring(response: 0.42, dampingFraction: 0.86)
                    ) { morph.progress = 1 }
                }
                // The in-player brightness belongs to the fullscreen player: the catalog
                // behind the card gets the level the device had before. Not re-applied
                // on expand.
                player.brightness.restoreBrightnessIfAdjusted()
                // With the card docked the keys belong to the catalog again.
                if isHardwareKeyboardFocused { isHardwareKeyboardFocused = false }
                // Give a forced landscape back once the morph has settled; rotating
                // under the running spring would resize the container mid-animation.
                if landscapeForced {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        guard gen == expandControlsGeneration else { return }
                        releaseForcedLandscape()
                    }
                }
            case .fullscreen:
                // Whoever expanded the card, the end of PiP has nothing left to undo.
                pipTracking.minimizedForPictureInPicture = false
                cardDrag.offset = .zero
                cardDrag.dismissOpacity = 1
                // Keep the (heavy) fullscreen chrome hidden during the grow so its layout doesn't
                // run every animation frame and make the expand judder. Near-critical damping
                // (0.96) also avoids a scale overshoot at the end. Reveal chrome once settled.
                timer?.invalidate()
                showControls = false
                // Status bar stays up through the grow (see `statusBarHiddenInCurrentMode`);
                // released in the same transaction that reveals the chrome, so it never blinks.
                isExpandingFromMini = true
                // Settling: the card is no longer docked, and its shadow and chrome have
                // to stay mounted (and the fullscreen layers untouchable) until the grow
                // is done. Covers an external expand too.
                // Reduce Motion: same settle bookkeeping, without the full-screen grow.
                // The chrome reveal below keeps its delay either way.
                let settle = settleMorph(
                    exitReduceMotion
                        ? Self.reducedMotionMorphAnimation
                        : .spring(response: 0.42, dampingFraction: 0.96)
                ) {
                    morph.progress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) {
                    guard gen == expandControlsGeneration else { return }
                    // The chrome revealed below has to take taps from its first frame,
                    // whether or not the spring has reported its completion yet.
                    finishMorphSettle(settle)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = true
                        isExpandingFromMini = false
                    }
                    resetTimer()
                    claimHardwareKeyboardFocus()
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
            containerExtension: containerExtension,
            isLive: isLiveStream || type == "live"
        )
        // The first tick of the new item is not a seek, and a save still pending for
        // a seek in the previous item must not write that position into this row.
        historyTracking.lastClockMs = nil
        historyTracking.seekSaveToken &+= 1

        // The engine applies a start position on both backends (FFmpeg through
        // KSOptions.startPlayTime, AVPlayer through its own start seek, which also holds
        // the transport at buffering), so the resume position is handed over for every
        // URL. Only the FFmpeg open is certain to start there: for AVPlayer-first
        // containers (mp4/m4v/mov/HLS) the engine drops the start when the item cannot
        // seek in time, so hasInitialSeeked stays false and checkAndPerformResume()
        // remains the fallback. It does nothing once the engine's seek has landed.
        let usesFFmpegStartTime = KSPlayerEngine.prefersFFmpegFirst(for: url)
        let shouldStartFromResume = !isLiveStream && (resumeTimeMs ?? 0) > 5000
        hasInitialSeeked = shouldStartFromResume && usesFFmpegStartTime
        bitrateSamples.removeAll()
        isScrubbing = false
        lockedSliderValue = nil
        sliderUnlockGeneration += 1
        isFastForwarding = false
        player.setRate(1.0)
        videoPinchBase = 1
        videoZoomPan.pinchLive = 1
        videoPanCommitted = .zero

        // The identity embeds the stream URL, which carries the account's credentials.
        Log.info("Playback", "Load playback: \(self.streamId) \(Log.redact(self.url))")
        player.setImportedSubtitleContext(
            contentKey: ImportedSubtitleStore.contentKey(
                playlistId: playlistId, type: type, streamId: streamId
            )
        )
        let initialStartSeconds: TimeInterval? =
            shouldStartFromResume ? Double(resumeTimeMs ?? 0) / 1000.0 : nil
        if let initialStartSeconds {
            Log.info("Playback", "Starting playback at the resume position: \(initialStartSeconds)s")
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
        // An AVPlayer-first URL that fell back to the FFmpeg player was opened at the
        // resume position (KSOptions.startPlayTime), like an FFmpeg-first URL. Its
        // clock can still read 0 while that open-time seek runs, and a seek from here
        // would then freeze playback until the seek timeout or reopen the stream.
        if !player.isCastPresenting, player.engine.isFFmpegBackendActive {
            hasInitialSeeked = true
            return
        }
        // The engine was given the same position at load and publishes its start-seek
        // target as the playhead the moment it seeks, before the duration that lets
        // this check pass is known. A playhead already at the resume point means that
        // seek ran: a second one would only rebuffer again. The slack covers a landing
        // on an earlier keyframe (the start seek is not exact) and the engine's clamp
        // near the end; a start the engine dropped leaves the playhead in the opening
        // seconds instead.
        let resumeTarget = min(Int64(resumeTime), player.durationMs)
        if player.timeMs >= max(resumeTarget - 10_000, 2_000) {
            hasInitialSeeked = true
            return
        }
        let pos = Float(Double(resumeTime) / Double(player.durationMs))
        Log.info("Playback", "Seeking to resumeTimeMs: \(resumeTime) (pos: \(pos))")
        player.seek(to: min(max(pos, 0), 1))
        hasInitialSeeked = true
    }

    private func startSaveHistoryTimer() {
        saveHistoryTimer?.invalidate()
        saveHistoryTimer = Timer.scheduledTimer(
            withTimeInterval: PlayerWatchHistoryPolicy.periodicIntervalSeconds, repeats: true
        ) { _ in
            // The closure captures the view struct from onAppear, freezing plain props
            // (streamId, title, …) at first render. historySaveTags is @State, so it
            // stays live across in-place episode switches — without it, episode 2's
            // position would be written into episode 1's history row.
            guard player.isPlaying else { return }
            // Each of the two is a no-op for the other kind of content. For live this
            // is only the fallback: the row is normally written when the channel
            // starts playing.
            saveLiveHistoryOnce()
            saveProgressHistory()
        }
    }

    // MARK: - Watch history writes
    //
    // Every write re-publishes the history queries of whatever list is mounted under
    // the player, so rows are written when they carry news, not on a short timer:
    // live once per playback identity (its position means nothing) and when it is
    // left; a film or episode every 10 s and on pause, after a seek and when the app
    // goes to the background. Leaving the item and closing the player always save.

    /// A live channel's row: once per playback identity, when it first plays.
    private func saveLiveHistoryOnce() {
        guard let tags = historySaveTags, tags.isLive,
              let identity = appliedPlaybackIdentity,
              historyTracking.liveRowIdentity != identity else { return }
        historyTracking.liveRowIdentity = identity
        saveWatchHistory(tags: tags)
    }

    /// Position of a film or episode. Never for live content.
    private func saveProgressHistory() {
        guard let tags = historySaveTags, !tags.isLive else { return }
        saveWatchHistory(tags: tags)
    }

    /// One clock tick. A jump of the playhead is a seek, whoever asked for it (the
    /// scrubber, the skip buttons, a double tap, the lock screen): the position is
    /// saved once it has stopped jumping, so a burst of skip taps writes one row.
    private func noteClockTickForHistory(_ timeMs: Int64) {
        let previous = historyTracking.lastClockMs
        historyTracking.lastClockMs = timeMs
        guard PlayerWatchHistoryPolicy.isSeekJump(previousMs: previous, currentMs: timeMs)
        else { return }
        historyTracking.seekSaveToken &+= 1
        let token = historyTracking.seekSaveToken
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PlayerWatchHistoryPolicy.seekSettleSeconds
        ) {
            guard token == historyTracking.seekSaveToken else { return }
            saveProgressHistory()
        }
    }

    /// Invisible and always mounted, like `chromeStateDriver`: the triggers of the
    /// history writes that do not come from the timer. The clock is received here, not
    /// observed, so a tick runs a closure and never this view's body.
    private var historySaveDriver: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: player.isPlaying) { _, playing in
                if playing { saveLiveHistoryOnce() }
            }
            .onChange(of: player.state) { _, newState in
                if newState == .paused { saveProgressHistory() }
            }
            .onReceive(player.clock.$timeMs) { timeMs in
                noteClockTickForHistory(timeMs)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            ) { _ in saveProgressHistory() }
    }

    /// Shared by the recognizer arming and by the begin handler, so the two cannot drift.
    private var canBeginSpeedHold: Bool {
        PlayerSpeedHoldGesturePolicy.canBegin(
            settingEnabled: speedUpOnLongPress,
            isPlaying: player.isPlaying,
            isLiveStream: isLiveStream,
            isDismissDragActive: interactiveDismissAxis != nil
        )
    }

    private func applySpeedHoldBegan() {
        guard canBeginSpeedHold, videoZoomScale <= 1.02, !isScrubbing else { return }
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
        // Back to the speed chosen in the menu, not to a hard-coded 1x. A cast does not
        // take the chosen speed (its player resumes at 1x), so it returns to 1x.
        player.setRate(player.isCastPresenting && !player.isLocalCastPlayback ? 1.0 : player.playbackSpeed)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cancelSpeedHoldBecauseDismissDragRecognized() {
        if isFastForwarding {
            applySpeedHoldEnded()
        }
    }

    private func resetInteractiveDismissTracking() {
        interactiveDismissAxis = nil
        if morph.dismissOffset != .zero { morph.dismissOffset = .zero }
    }

    private func resetInteractiveDismissTrackingWithAnimation() {
        interactiveDismissAxis = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            morph.dismissOffset = .zero
        }
    }

    /// Longest a settle may hold the morph state if its completion never arrives.
    private static let morphSettleTimeout: TimeInterval = 1.2

    /// Runs a morph settle animation (back to fullscreen, or on to the docked card).
    /// `isMorphSettling` keeps the morph state engaged until it is done: the card's shadow
    /// and chrome animate out instead of vanishing at the release, and the fullscreen
    /// layers take no taps while they are still moving.
    ///
    /// Returns the settle's generation, for a caller that ends it on its own schedule.
    @discardableResult
    private func settleMorph(_ animation: Animation, _ changes: () -> Void) -> UInt64 {
        dismissTracking.settleGeneration &+= 1
        let generation = dismissTracking.settleGeneration
        if !isMorphSettling { isMorphSettling = true }
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            changes()
        } completion: {
            finishMorphSettle(generation)
        }
        // Safety net: a flag left set would keep every touch of the fullscreen player
        // switched off.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.morphSettleTimeout) {
            finishMorphSettle(generation)
        }
        return generation
    }

    /// A newer settle owns the flag once it has started; an older one ending late is
    /// ignored.
    private func finishMorphSettle(_ generation: UInt64) {
        guard generation == dismissTracking.settleGeneration, isMorphSettling else { return }
        isMorphSettling = false
    }

    /// A cancelled drag (second finger, system interruption, rotation) never reaches
    /// `onEnded`, which used to leave the player half-morphed with its taps gated off
    /// until the next drag. Runs when the in-flight flag drops, one main-queue turn later:
    /// a normal release clears `dragAwaitsEnd` in `onEnded`, so it is never mistaken for
    /// a cancel whichever of the two SwiftUI delivers first.
    private func settleDismissDragIfCancelled() {
        DispatchQueue.main.async {
            guard dismissTracking.dragAwaitsEnd, !isDismissDragInFlight else { return }
            dismissTracking.dragAwaitsEnd = false
            // Same guard as `onEnded`: a committed mini card never springs back.
            guard !isMiniCommitted else { return }
            interactiveDismissAxis = nil
            if morph.progress != 0 {
                settleMorph(.spring(response: 0.4, dampingFraction: 0.85)) {
                    morph.progress = 0
                    morph.dismissOffset = .zero
                }
            } else if morph.dismissOffset != .zero {
                // A cancelled edge-back swipe: only the offset springs back, and the
                // morph state stays out of it (it would mount the card's shadow).
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    morph.dismissOffset = .zero
                }
            }
        }
    }

    /// The edge-back margin is measured from the physical screen edge. `start` is in the
    /// container's safe-area space, so the inset on the starting side is added back.
    private func startsInteractiveEdgeBack(
        start: CGPoint, containerWidth: CGFloat, leadingInset: CGFloat
    ) -> Bool {
        FullscreenPlayerDismissZonePolicy.startsEdgeBack(
            startX: start.x,
            containerWidth: containerWidth,
            leadingInset: leadingInset,
            isRightToLeft: layoutDirection == .rightToLeft
        )
    }

    /// A drag that starts on a brightness or volume capsule belongs to that capsule. In
    /// portrait, on iPad and on phones without a side inset the leading capsule lies
    /// inside the edge-back margin, so a brightness drag that drifted sideways used to
    /// slide the whole player. The capsules only exist while the chrome is showing.
    private func dismissStartIsOnEdgeSlider(
        start: CGPoint, containerSize: CGSize, safeArea: EdgeInsets
    ) -> Bool {
        guard showControls else { return false }
        let isRightToLeft = layoutDirection == .rightToLeft
        return FullscreenPlayerDismissZonePolicy.startsOnEdgeSlider(
            start: start,
            screen: screenFrame(container: containerSize, safeArea: safeArea),
            // The track size the capsules are drawn with and the touch overlay excludes.
            trackSize: CGSize(
                width: isCompactWidth ? 52 : 64,
                height: isCompactWidth ? 160 : 180
            ),
            leftInset: isRightToLeft ? safeArea.trailing : safeArea.leading,
            rightInset: isRightToLeft ? safeArea.leading : safeArea.trailing
        )
    }

    /// Aşağı çekerek kapatmayı yalnızca jestin başladığı nokta “krom” bölgelerindeyse bastır (yan parlaklık/ses,
    /// üst/alt düğme ve zaman çubuğu). Ortadan aşağı kaydırma kontroller açıkken de çalışır.
    private func interactiveDismissShouldSuppressPullDown(
        start: CGPoint,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        safeArea: EdgeInsets
    ) -> Bool {
        // Only the on-screen controls (edge sliders / top & bottom chrome) need protecting
        // from an accidental pull-down. With the chrome hidden — the normal viewing state —
        // pull-down works from anywhere, so it never feels like a restricted zone.
        guard showControls else { return false }
        let container = CGSize(width: containerWidth, height: containerHeight)
        // `start` and the bands share the container's safe-area space; the bottom band
        // used to add the bottom inset on top of that and reached far into the picture.
        // The sides are protected by the capsule frames, not by full-height strips.
        return FullscreenPlayerDismissZonePolicy.startsOnChrome(start: start, container: container)
            || dismissStartIsOnEdgeSlider(start: start, containerSize: container, safeArea: safeArea)
    }

    /// Üst kenar: Kontrol Merkezi / Bildirimler / durum alanı jestleri; oynatıcı kapatmayı tetiklemesin.
    private func interactiveDismissStartedInTopSystemGestureBand(
        start: CGPoint,
        containerHeight: CGFloat,
        safeAreaTop: CGFloat
    ) -> Bool {
        // The band hangs from the physical top edge while `start.y` is measured from the
        // safe-area top; comparing the two directly counted the top inset twice.
        FullscreenPlayerDismissZonePolicy.startsInTopSystemGestureBand(
            startY: start.y,
            safeAreaTop: safeAreaTop,
            containerHeight: containerHeight
        )
    }

    // MARK: - Mini player geometry & morph

    private var statusBarHiddenInCurrentMode: Bool {
        if isMiniCommitted { return false }
        // Compact only: on regular width the bar is hidden for the whole fullscreen session,
        // so there is no blink to avoid and delaying the hide would just move the
        // safe-area jump to the end of the expand.
        if isExpandingFromMini && horizontalSizeClass == .compact { return false }
        return horizontalSizeClass == .compact ? !showControls : true
    }

    /// Home indicator: auto-hidden while fullscreen, system default on the mini card (the
    /// catalog underneath is the foreground UI there). iPhone only — on iPad `.hidden` also
    /// removes Picture in Picture and the multitasking button.
    private var persistentSystemOverlaysInCurrentMode: Visibility {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .automatic }
        return isMiniCommitted ? .automatic : .hidden
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
            corner: mirroredForLayoutDirection(miniCorner), size: size, container: container,
            safeArea: safeArea, bottomInset: bottomInset
        )
        return CGRect(origin: origin, size: size)
    }

    /// `miniCorner` names layout sides, while the card's geometry is physical (it is laid
    /// out left-to-right, see `body`): in a right-to-left layout the trailing corners are
    /// the left ones. Converts between the two; the conversion is its own inverse.
    private func mirroredForLayoutDirection(_ corner: MiniPlayerCorner) -> MiniPlayerCorner {
        guard layoutDirection == .rightToLeft else { return corner }
        switch corner {
        case .topLeading: return .topTrailing
        case .topTrailing: return .topLeading
        case .bottomLeading: return .bottomTrailing
        case .bottomTrailing: return .bottomLeading
        }
    }

    /// The true screen rect in the outer reader's space (origin at the safe-area corner):
    /// the container grown by its own insets. The content is laid out in this frame and
    /// transformed about its centre, so nothing inside the transformed subtree has to
    /// resolve the safe area again.
    private func screenFrame(container: CGSize, safeArea: EdgeInsets) -> CGRect {
        let isRightToLeft = layoutDirection == .rightToLeft
        return MiniPlayerMetrics.screenFrame(
            container: container,
            top: safeArea.top,
            left: isRightToLeft ? safeArea.trailing : safeArea.leading,
            bottom: safeArea.bottom,
            right: isRightToLeft ? safeArea.leading : safeArea.trailing
        )
    }

    /// Scale that lands the *video* (not the letterboxed screen) on the card. The surface
    /// is fitted in the full-screen frame the content is laid out in (see `screenFrame`),
    /// so the scale has to be derived from the same frame. The rest of the transform is
    /// `MiniMorphGeometry.transform`, evaluated by `MiniMorphLayer` as the morph moves.
    private func miniTargetScale(card: CGRect, screen: CGRect) -> CGFloat {
        MiniMorphGeometry.targetScale(
            cardHeight: card.height,
            fittedHeight: fittedVideoSize(in: screen.size).height
        )
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
            // The slide-off below is the exit animation; dismiss without a second one.
            let dismissNow = capturedDismissAction()
            withAnimation(.easeIn(duration: 0.18)) {
                morph.dismissOffset = CGSize(width: 0, height: containerHeight + 60)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                releaseForcedLandscape()
                dismissNow()
            }
            return
        }
        timer?.invalidate()
        showControls = false
        let remaining = max(1, (1 - morph.progress) * distance)
        // Seed the spring with the gesture's normalized velocity (clamped so a release near
        // the end doesn't produce an absurd initial velocity).
        let springV = min(max(Double(velocity) / Double(remaining), -25), 25)
        // Settling until the spring is done; from then on `isMiniCommitted` keeps the
        // morph state engaged.
        settleMorph(.interpolatingSpring(stiffness: 320, damping: 30, initialVelocity: springV)) {
            morph.progress = 1
            // The same spring carries the card from under the finger to its corner.
            morph.dismissOffset = .zero
        }
        minimize()
    }

    /// A cancelled card drag gets no `onEnded`: put the card back in its corner.
    private func handleMiniCardDragCancelled() {
        guard cardDrag.offset != .zero || cardDrag.dismissOpacity != 1 else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            cardDrag.offset = .zero
            cardDrag.dismissOpacity = 1
        }
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
        // `nearestCorner` answers in physical sides; `miniCorner` stores layout sides.
        let target = mirroredForLayoutDirection(
            nearestCorner(toCenter: projected, container: container)
        )
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

        // The slide-off is the exit animation; dismiss without a second one.
        // The next-episode countdown must not overtake it.
        cancelAutoAdvanceCountdown()
        let dismissNow = capturedDismissAction()
        withAnimation(.easeIn(duration: 0.2)) {
            cardDrag.offset = exit
            cardDrag.dismissOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            releaseForcedLandscape()
            dismissNow()
        }
    }

    /// The channel strip is a sibling the live shells draw above this view: it would
    /// stay behind, full size, while the player shrinks or slides away. The shells close
    /// it on this hook.
    private func closeLiveChannelPanelForDismissDrag() {
        if isLiveChannelSidePanelVisible { onVideoSurfaceTap?() }
    }

    private func interactiveDismissDragGesture(
        containerSize: CGSize,
        safeArea: EdgeInsets
    ) -> some Gesture {
        let safeAreaTop = safeArea.top
        return DragGesture(minimumDistance: 22, coordinateSpace: .local)
            // Drops back to false when the drag ends AND when it is cancelled; the body
            // watches it to settle a drag that never got its `onEnded`.
            .updating($isDismissDragInFlight) { _, state, _ in state = true }
            .onChanged { value in
                if isMiniCommitted { return }  // mini card handles its own gestures
                dismissTracking.dragAwaitsEnd = true
                if showTrackSettings || showSubtitleAppearance { return }
                // A pinch in flight owns the touches: its two fingers also move, and the
                // morph must not start under it.
                if videoZoomScale > 1.02 || isScrubbing || pinchAnchorState != nil { return }
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
                    // Not from a brightness or volume capsule: that drag is the
                    // capsule's, however far it drifts sideways.
                    if startsInteractiveEdgeBack(
                        start: start, containerWidth: w, leadingInset: safeArea.leading
                    ), !dismissStartIsOnEdgeSlider(
                        start: start, containerSize: containerSize, safeArea: safeArea
                    ) {
                        if !startedInTopSystemBand {
                            let correctDirection =
                                (layoutDirection == .leftToRight && t.width > 12)
                                || (layoutDirection == .rightToLeft && t.width < -12)
                            if correctDirection, abs(t.width) + 8 >= abs(t.height) {
                                interactiveDismissAxis = .edgeBack
                                morph.dismissOffsetDims = true
                                closeLiveChannelPanelForDismissDrag()
                            }
                        }
                    }
                    if interactiveDismissAxis == nil,
                       FullscreenPlayerPullDownPolicy.shouldActivate(translation: t),
                       !interactiveDismissShouldSuppressPullDown(
                        start: start,
                        containerWidth: w,
                        containerHeight: h,
                        safeArea: safeArea
                       ),
                       !startedInTopSystemBand
                    {
                        interactiveDismissAxis = .pullDown
                        morph.dismissOffsetDims = false
                        closeLiveChannelPanelForDismissDrag()
                        // Everything below is measured from where the axis locked. A drag
                        // that turned downward late locks well past the slop; measuring
                        // from the slop made the morph jump on that frame.
                        dismissTracking.activationTranslation = t
                        dismissTracking.activationLocation = CGPoint(
                            x: start.x + t.width, y: start.y + t.height
                        )
                    }
                }

                switch interactiveDismissAxis {
                case .edgeBack:
                    if layoutDirection == .leftToRight {
                        morph.dismissOffset = CGSize(width: max(0, t.width), height: 0)
                    } else {
                        morph.dismissOffset = CGSize(width: min(0, t.width), height: 0)
                    }
                case .pullDown:
                    // Drive the mini-player morph directly with the finger.
                    let dist = pullDownDragDistance(container: containerSize)
                    let progress = FullscreenPlayerPullDownPolicy.progress(
                        translationHeight: t.height,
                        activationHeight: dismissTracking.activationTranslation.height,
                        fullDistance: dist
                    )
                    // Progress alone slides the content toward the dock corner, which in
                    // landscape is mostly sideways, away from a finger moving down. While
                    // the finger is down the content stays under it instead: the offset
                    // stored here is the finger-follow offset minus the corner lerp the
                    // morph layer adds, so their sum is the follow offset. Release
                    // animates it back to zero together with the progress.
                    let screen = screenFrame(container: containerSize, safeArea: safeArea)
                    let card = miniCardRect(container: containerSize, safeArea: safeArea)
                    let transform = MiniMorphGeometry.transform(
                        progress: progress,
                        card: card,
                        screen: screen,
                        targetScale: miniTargetScale(card: card, screen: screen)
                    )
                    let follow = FullscreenPlayerPullDownPolicy.followOffset(
                        translation: t,
                        activationTranslation: dismissTracking.activationTranslation,
                        grabPoint: dismissTracking.activationLocation,
                        anchor: CGPoint(x: screen.midX, y: screen.midY),
                        scale: transform.scale
                    )
                    // Written to the model, which only the morph layers observe: this
                    // runs on every touch-move.
                    morph.progress = progress
                    morph.dismissOffset = CGSize(
                        width: follow.width - transform.offset.width,
                        height: follow.height - transform.offset.height
                    )
                case .none:
                    break
                }

                if interactiveDismissAxis != nil {
                    cancelSpeedHoldBecauseDismissDragRecognized()
                }
            }
            .onEnded { value in
                // This drag ended normally; the cancel path has nothing to settle.
                dismissTracking.dragAwaitsEnd = false
                if isMiniCommitted { return }
                if showTrackSettings || showSubtitleAppearance {
                    resetInteractiveDismissTracking()
                    if morph.progress > 0 {
                        settleMorph(.spring(response: 0.4, dampingFraction: 0.85)) { morph.progress = 0 }
                    }
                    return
                }

                let axis = interactiveDismissAxis
                if axis == .edgeBack {
                    // The swipe may have started on a chrome button, which is still
                    // under the finger: its action must not run for this release.
                    dismissTracking.edgeBackReleaseUptime = ProcessInfo.processInfo.systemUptime
                }
                guard videoZoomScale <= 1.02, !isScrubbing, pinchAnchorState == nil else {
                    resetInteractiveDismissTrackingWithAnimation()
                    if morph.progress > 0 {
                        settleMorph(.spring(response: 0.4, dampingFraction: 0.85)) { morph.progress = 0 }
                    }
                    return
                }

                guard let axis else {
                    if morph.dismissOffset != .zero {
                        resetInteractiveDismissTrackingWithAnimation()
                    }
                    return
                }

                let t = value.translation
                let cw = max(containerSize.width, 1)
                let ch = max(containerSize.height, 1)

                interactiveDismissAxis = nil
                switch axis {
                case .edgeBack:
                    let progressed = layoutDirection == .leftToRight ? t.width : -t.width
                    // Position only: this swipe ends playback, so a fast flick that has
                    // not carried the player far enough springs back.
                    if FullscreenPlayerDismissZonePolicy.edgeBackShouldCommit(
                        progressed: progressed, containerWidth: cw
                    ) {
                        // The slide-off is the exit animation; dismiss without a second one.
                        // The next-episode countdown must not overtake it.
                        cancelAutoAdvanceCountdown()
                        let dismissNow = capturedDismissAction()
                        let targetX: CGFloat = layoutDirection == .leftToRight ? cw + 60 : -(cw + 60)
                        withAnimation(.easeIn(duration: 0.18)) {
                            morph.dismissOffset = CGSize(width: targetX, height: 0)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            releaseForcedLandscape()
                            dismissNow()
                        }
                    } else {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            morph.dismissOffset = .zero
                        }
                    }
                case .pullDown:
                    // A flick can commit only after meaningful travel; tiny fast touch
                    // drift must never throw the player into the mini card.
                    let dist = pullDownDragDistance(container: containerSize)
                    let vy = value.velocity.height
                    let projected = FullscreenPlayerPullDownPolicy.progress(
                        translationHeight: value.predictedEndTranslation.height,
                        activationHeight: dismissTracking.activationTranslation.height,
                        fullDistance: dist
                    )
                    let commitMini = FullscreenPlayerPullDownPolicy.shouldCommit(
                        progress: morph.progress,
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
                        settleMorph(.spring(response: 0.4, dampingFraction: 0.85)) {
                            morph.progress = 0
                            morph.dismissOffset = .zero
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
                MPVolumeViewHost(bridge: player.systemVolume)
                    .frame(width: 120, height: 48)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(-10)

                HiddenAirPlayRoutePicker(
                    trigger: airPlayPickerSignal,
                    // The programmatic tap is sent from inside a view update, and AVKit
                    // reports the presentation from within it: leave the update before
                    // touching state or the controller (same hop for the close, so the
                    // two stay in order).
                    onWillBegin: { DispatchQueue.main.async { hiddenAirPlayPickerDidOpen() } },
                    onDidEnd: { DispatchQueue.main.async { player.airPlayPickerDidClose() } },
                    // The picker could not even send its tap: no need to wait for the
                    // watchdog below, which stays as the net for a tap that was sent
                    // and ignored.
                    onOpenFailed: { hiddenAirPlayPickerDidFailToOpen() }
                )
                .frame(width: 44, height: 44)
                // The device list is anchored to this view (a popover on iPad), so it
                // sits in the row of the trailing action capsule, at its trailing end,
                // instead of the middle of the picture. The insets repeat the top
                // chrome's own (chrome padding, `topChrome`, the capsule's inner 4 pt).
                // It stays in this stack, not in the chrome: the chrome unmounts when
                // it auto-hides, which would lose the "list closed" callback.
                .padding(.top, outerSafeAreaInsets.top + 16)
                .padding(
                    .trailing,
                    12 + outerSafeAreaInsets.trailing + (isCompactWidth ? 0 : 20) + 4
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(-10)

                chromeStateDriver
                    .zIndex(-10)

                historySaveDriver
                    .zIndex(-10)

                // Not on the mini card: its own chrome is the accessible surface there.
                if !isMiniCommitted {
                    playerSurfaceAccessibilityElement
                        .zIndex(2)
                }

                ZStack {
                    VideoZoomPanLayer(
                        model: videoZoomPan,
                        pinchBase: videoPinchBase,
                        zoomMin: videoZoomMin,
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
                                    // PiP is driven through the controller now; the
                                    // surface's own trigger stays at rest.
                                    manualPiPTrigger: 0,
                                    pipEnabled: pipEnabled,
                                    continuePlayingInBackground: continuePlayingInBackground,
                                    routeName: player.airPlayRouteName
                                )
                                .id("KSPlaybackSurface")
                            }
                        }
                        .frame(width: fittedSize.width, height: fittedSize.height)
                    }

                    // Sibling of the zoom layer: centred on the screen, never scaled or panned.
                    openingArtworkLayer(
                        pictureSize: visiblePictureSize(fitted: fittedSize, container: geo.size)
                    )
                }
                // Clip to the screen so the `.fill` crop never bleeds past the viewport into
                // the chrome. Only Fill overflows, so the clip (an offscreen compositing pass
                // that was adding jank on open / pull-down) is skipped in fit/center.
                .frame(width: geo.size.width, height: geo.size.height)
                .modifier(ConditionalClip(active: selectedAspectMode == .fill))
                .allowsHitTesting(false)  // tüm touch UIKit overlay'de; video katmanı hit-test almaz
                .zIndex(0)

                // The subtitle frame follows the morph (it shrinks to the card's picture),
                // so it is rebuilt by a reader of the morph model, not by this body.
                MiniMorphProgressReader(model: morph) { progress in
                    subtitleTextLayer(
                        progress: progress,
                        fitted: fittedSize,
                        container: geo.size,
                        safeAreaBottom: outerSafeAreaInsets.bottom
                    )
                }
                .zIndex(2)

                // Tap/pinch/pan UIKit overlay'inde. Pinch midpoint callback ile zoom anchor
                // offset hesaplanır; pan yalnızca zoomluyken enabled.
                PlayerMediaKitStyleTouchOverlay(
                    showControls: $showControls,
                    isSeekDisabled: isCenterTransportLoading,
                    videoZoomScale: videoZoomScale,
                    isSpeedHoldActive: isFastForwarding,
                    isSpeedHoldEnabled: canBeginSpeedHold,
                    edgeSliderTrackSize: CGSize(
                        width: isCompactWidth ? 52 : 64,
                        height: isCompactWidth ? 160 : 180
                    ),
                    edgeSliderLeadingInset: 16 + outerSafeAreaInsets.leading,
                    edgeSliderTrailingInset: 16 + outerSafeAreaInsets.trailing,
                    interactionEnabled: !isMorphEngaged,
                    isHideTapEnabled: !isScrubbing,
                    isDoubleTapSeekEnabled: canDoubleTapSeek,
                    // With the channel panel open a tap on the video closes the panel
                    // and does nothing else.
                    isSurfaceTapExclusive: isLiveChannelSidePanelVisible,
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
                    onVideoSurfaceTap: { onVideoSurfaceTap?() },
                    onVideoPinchCancelled: { handleVideoPinchGestureEnded(cancelled: true) },
                    onDoubleTapSeek: { side in handleDoubleTapSeek(side) },
                    onSideTapRevealsChrome: { shieldChromeFromSecondTap() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)

                // Everything that exists only in the fullscreen presentation, in one
                // container above the picture, the subtitles and the touch overlay: faded
                // as a whole along the morph by its wrapper (the elements no longer read
                // the progress themselves).
                MiniMorphFullscreenFade(model: morph) {
                    fullscreenOverlays(container: geo.size, outerSafeAreaInsets: outerSafeAreaInsets)
                }
                // Invisible (opacity ~0) but still-hittable fullscreen layers must not
                // intercept taps during the minimize/expand morph or on the docked card —
                // otherwise a stray tap on the scaled-down invisible close/play button
                // could tear down or pause. Interactive only while the morph is at rest
                // in fullscreen, and not for the length of a double tap after a side
                // tap revealed the chrome (see `isChromeTapShielded`).
                .allowsHitTesting(!isMorphEngaged && !isChromeTapShielded)
                .zIndex(20)

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
        //
        // The edge-to-edge size comes from the explicit full-screen frame the body gives
        // this view, not from `ignoresSafeArea`: SwiftUI resolves that modifier through
        // the mini-morph scale/offset, which resized the surface on the first frame of a
        // pull-down and again when an expand settled. Do not resolve the safe area
        // anywhere inside this subtree (that includes `.background(_:)` with a bare
        // style, which extends into it by default).
    }

    /// Everything that exists only in the fullscreen presentation: chrome, pills, banners
    /// and notices. One container, faded as a whole by `MiniMorphFullscreenFade` and taken
    /// out of hit testing as a whole while the morph is engaged, so no element in here
    /// reads the morph progress. They keep their z-order among themselves; all of them
    /// sit above the picture, the subtitles and the touch overlay.
    private func fullscreenOverlays(
        container: CGSize, outerSafeAreaInsets: EdgeInsets
    ) -> some View {
        ZStack {
            airPlayUnavailableOverlay(outerSafeAreaInsets: outerSafeAreaInsets)

            doubleTapSeekIndicatorLayer(containerWidth: container.width)

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
                // No `ignoresSafeArea` here: the enclosing frame is already the
                // full screen (see the note at the end of `playerChromeAndVideo`).
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
                .zIndex(30)

                // Not under the open channel panel: lifted above the button row, the
                // panel would cut the strip in half.
                if isLiveStream, !isLiveChannelSidePanelVisible, let programme = currentNowNext?.now {
                    // The channel row shares this band from the trailing side: on a
                    // narrow screen the strip ends before the row's first button.
                    let stripMaxWidth = programmeStripMaxWidth(
                        containerWidth: container.width, insets: outerSafeAreaInsets
                    )
                    PlayerLiveProgrammeStrip(
                        model: channelBanner,
                        programme: programme,
                        // The banner is suppressed during a failure; the strip stays then.
                        yieldsToBanner: !hasPlaybackFailure,
                        barWidth: PlayerProgrammeStripLayout.barWidth(stripMaxWidth: stripMaxWidth)
                    )
                        .frame(maxWidth: stripMaxWidth, alignment: .leading)
                        .clipped()
                        .padding(.leading, 20 + outerSafeAreaInsets.leading)
                        .padding(.bottom, 20 + outerSafeAreaInsets.bottom)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                        .allowsHitTesting(false)
                        .transition(hudPillTransition(offsetY: 10))
                        .zIndex(31)
                }

                PlayerControlCenterStyleEdgeSliders(
                    brightness: player.brightness,
                    systemVolume: player.systemVolume,
                    safeAreaInsets: outerSafeAreaInsets,
                    isCompactWidth: isCompactWidth
                ) {
                    resetTimer()
                }
                .zIndex(32)
            }

            // Channel banner: outside `if showControls`, so a zap with the chrome hidden
            // (lock screen, headset, auto-hidden controls) still says which channel is
            // loading. It shows and hides itself from its own model; it sits in this
            // container with the rest of the fullscreen layers, so the mini card never
            // shows it.
            if isLiveStream {
                PlayerChannelBanner(
                    model: channelBanner,
                    channelId: currentChannelPanelItemId ?? streamId,
                    title: title,
                    artworkURL: artworkURL,
                    programme: currentNowNext?.now,
                    playlistId: playlistId,
                    // The failure banner and the channel panel use the same corner.
                    isSuppressed: hasPlaybackFailure || isLiveChannelSidePanelVisible,
                    clearsTransportRow: showControls && (showLiveChannelSkip || showLiveChannelListButton),
                    safeAreaInsets: outerSafeAreaInsets
                )
                .allowsHitTesting(false)
                .zIndex(33)
            }

            // Kontroller gizliyken de yükleme/buffering geri bildirimi: yavaş panel
            // açılışında 5 sn sonra kontroller kaybolunca kullanıcı simsiyah ekranla
            // baş başa kalıyordu. Kontroller açıkken ortadaki buton zaten spinner
            // gösterdiği için burada yalnızca !showControls durumunda çizilir.
            // The wrapper stays mounted so the spinner can fade instead of blinking and
            // so the debounce task below runs whether or not the chrome is visible.
            ZStack {
                if showsLoadingSpinner && !showControls {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                        .padding(18)
                        .background(.black.opacity(0.35), in: Circle())
                        .accessibilityLabel(L("common.loading"))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsLoadingSpinner && !showControls)
            .allowsHitTesting(false)
            .zIndex(25)
            .task(id: isSpinnerCandidate) { await trackLoadingSpinnerDelay() }

            airPlayStatusOverlay(outerSafeAreaInsets: outerSafeAreaInsets)

            audioOnlyAirPlayOverlay(outerSafeAreaInsets: outerSafeAreaInsets)

            debugStatsOverlay(
                outerSafeAreaInsets: outerSafeAreaInsets,
                containerWidth: container.width
            )

            // Aspect toast and 2x badge share one row, so they stack instead of
            // covering each other.
            hudTopPills(outerSafeAreaInsets: outerSafeAreaInsets)

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
                                // Fixed-width digits keep the capsule from changing
                                // width every second; the number rolls instead of
                                // snapping. Animated here because the tick itself is
                                // a plain assignment.
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                                .animation(
                                    hudReduceMotion ? nil : .snappy(duration: 0.25),
                                    value: seconds
                                )
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
                // The frame above is full-screen: a `.move` would travel the whole
                // container height, so the capsules only rise a few points.
                .transition(hudPillTransition(offsetY: 10))
                .zIndex(41)
            }

            // Not: PiP placeholder UI kaldırıldı — sistem `AVPictureInPictureController`
            // kendi "playing in picture in picture" mesajını otomatik gösteriyor.

            // Hata banner'ı krom görünürlüğünden bağımsız: 5 sn auto-hide sonrası
            // patlayan yayında kullanıcı sessiz siyah ekranla kalmasın.
            if hasPlaybackFailure, let msg = player.playbackFailureMessage {
                // The banner is the one failure element that survives the chrome
                // auto-hide, so it doubles as the retry control.
                Button {
                    resetTimer()
                    player.retryCurrentLoad()
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(msg)
                                .font(.caption2.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(L("common.try_again"))
                            }
                            .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: max(0, min(container.width - 24, 280)), alignment: .leading)
                    .background(
                        Color(red: 0.72, green: 0.12, blue: 0.14).opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("player.playback_error"))
                .accessibilityValue(msg)
                .accessibilityHint(L("common.try_again"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, (showControls ? 92 : 12) + outerSafeAreaInsets.bottom)
                .zIndex(25)
            }
        }
        .frame(width: container.width, height: container.height)
        // The chrome is laid out around fixed-size buttons and rows over the picture;
        // text may grow with the user's setting up to the first accessibility size and
        // no further, or titles and pills push the controls off screen. Set here, not
        // on the body: the track and subtitle sheets and the subtitles themselves keep
        // the full range.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func handleVideoPinchBegan(at location: CGPoint, containerSize: CGSize) {
        // A pinch that starts while a Fit/Fill snap is still animating takes the
        // transform over; the pending mode switch of that snap must not fire under it.
        pinchSnapToken &+= 1
        pinchAnchorState = PinchAnchorState(
            screenMidpoint: location,
            containerCenter: CGPoint(x: containerSize.width / 2, y: containerSize.height / 2),
            startScale: effectiveVideoScale,
            startPanCommitted: videoPanCommitted
        )
    }

    /// `cancelled`: the recognizer was cancelled (system gesture, overlay disabled by the
    /// pull-down). The state is reset exactly as on a normal end, but an interrupted
    /// pinch never switches the aspect mode.
    private func handleVideoPinchGestureEnded(cancelled: Bool = false) {
        let cover = videoCoverScale
        let endZoom = min(max(videoPinchBase * videoZoomPan.pinchLive, videoZoomMin), videoZoomMax)
        let outcome = PlayerPinchAspectSnapPolicy.outcome(
            mode: selectedAspectMode,
            committedZoom: videoPinchBase,
            endZoom: endZoom,
            coverScale: cover,
            cancelled: cancelled
        )
        switch outcome {
        case .freeZoom:
            // Pinch end: önce compensating zoom offset'i committed pan'a bake et, sonra state'i temizle.
            let zoomDelta = videoPinchZoomOffset
            pinchAnchorState = nil
            videoPanCommitted = CGSize(
                width: videoPanCommitted.width + zoomDelta.width,
                height: videoPanCommitted.height + zoomDelta.height
            )
            // Scale'i komite et.
            videoPinchBase = endZoom
            videoZoomPan.pinchLive = 1
            if videoPinchBase < 1.02 {
                videoPinchBase = 1
                videoPanCommitted = .zero
            } else {
                commitVideoPanClamp()
            }
        case .snapToFill:
            // In Fit, zoom `cover` is the exact frame of Fill.
            settlePinchZoom(at: cover, thenSwitchTo: .fill)
        case .snapToFit:
            // In Fill, zoom `1 / cover` is the exact frame of Fit.
            settlePinchZoom(at: 1 / cover, thenSwitchTo: .fit)
        case .returnToFill:
            settlePinchZoom(at: 1, thenSwitchTo: nil)
        }
    }

    /// Springs the pinch to `zoom`, centred, and then switches the aspect mode. The mode
    /// switch re-mounts the surface host (`ConditionalClip`), so it happens only once the
    /// picture already sits in the frame of the new mode and nothing moves with it.
    private func settlePinchZoom(at zoom: CGFloat, thenSwitchTo mode: VideoAspectMode?) {
        pinchSnapToken &+= 1
        let token = pinchSnapToken
        if mode != nil {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        withAnimation(
            .spring(response: 0.3, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete
        ) {
            pinchAnchorState = nil
            videoZoomPan.pinchLive = 1
            videoPinchBase = zoom
            videoPanCommitted = .zero
        } completion: {
            guard let mode else { return }
            finishPinchAspectSnap(to: mode, token: token)
        }
    }

    private func finishPinchAspectSnap(to mode: VideoAspectMode, token: UInt64) {
        // A newer pinch owns the transform now.
        guard token == pinchSnapToken, pinchAnchorState == nil else { return }
        // Still where the snap left it? An aspect change from the menu or a new load in
        // the meantime has reset the zoom to 1; there is then nothing to finish.
        switch mode {
        case .fill:
            guard selectedAspectMode == .fit, videoPinchBase > 1 else { return }
        case .fit:
            guard selectedAspectMode == .fill, videoPinchBase < 1 else { return }
        case .center:
            return
        }
        let fillScale = mode == .fill ? videoCoverScale : 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            videoPinchBase = 1
            videoPanCommitted = .zero
            // Set together with the mode, so no frame is drawn at the old scale;
            // `syncVideoLayout` arrives at the same value on the mode change.
            videoAspectFillScale = fillScale
            // The saved mode stays the single source of truth: the rest of the player
            // (engine, toast, layout) follows its change as for the aspect button.
            videoAspectModeRaw = mode.rawValue
        }
    }

    /// A tap on a seek side is revealing the chrome: keep it from taking touches until
    /// a second tap can no longer make this a double tap.
    private func shieldChromeFromSecondTap() {
        chromeTapShieldToken &+= 1
        let token = chromeTapShieldToken
        if !isChromeTapShielded { isChromeTapShielded = true }
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(PlayerDoubleTapSeekPolicy.maximumInterval * 1_000_000_000)
            )
            guard token == chromeTapShieldToken else { return }
            isChromeTapShielded = false
        }
    }

    private func handleDoubleTapSeek(_ side: PlayerDoubleTapSeekPolicy.Side) {
        // The overlay gates on the same flag; this covers a tap that was already on
        // its way when the content stopped being seekable.
        guard canDoubleTapSeek else { return }
        let seconds = PlayerDoubleTapSeekPolicy.jumpSeconds
        // Same path as the skip buttons: taps accumulate into one seek.
        player.jump(seconds: side == .forward ? seconds : -seconds)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let total = PlayerDoubleTapSeekPolicy.indicatorSeconds(
            showing: doubleTapSeekIndicator.map { (side: $0.side, seconds: $0.seconds) },
            tapped: side
        )
        doubleTapSeekIndicatorToken &+= 1
        let token = doubleTapSeekIndicatorToken
        withAnimation(.easeOut(duration: 0.15)) {
            doubleTapSeekIndicator = DoubleTapSeekIndicator(side: side, seconds: total)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard token == doubleTapSeekIndicatorToken else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                doubleTapSeekIndicator = nil
            }
        }
    }

    /// Brief "10" on the tapped side. Shown with or without the chrome, so it has its
    /// own dim backdrop; never takes touches.
    private func doubleTapSeekIndicatorLayer(containerWidth: CGFloat) -> some View {
        let zoneWidth = max(containerWidth * PlayerDoubleTapSeekPolicy.outerZoneFraction, 0)
        return ZStack {
            if let indicator = doubleTapSeekIndicator {
                VStack(spacing: 2) {
                    Image(
                        systemName: indicator.side == .forward ? "goforward.10" : "gobackward.10"
                    )
                    .font(.system(size: 30, weight: .semibold))
                    Text(verbatim: "\(indicator.side == .forward ? "+" : "\u{2212}")\(indicator.seconds)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(.black.opacity(0.35), in: Circle())
                .frame(width: zoneWidth)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: indicator.side == .forward ? .trailing : .leading
                )
                .id(indicator.side)
                .transition(
                    hudReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Physical sides, like the skip buttons: not mirrored in right-to-left languages.
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(33)
    }

    private func handleVideoPanEnded(translation: CGSize) {
        // A pan cancelled because the zoom went back to rest (aspect snap, new load,
        // aspect switch) has nothing to commit: at rest the picture is centred. Same
        // threshold as the one that enables the pan, so a pan that ended normally is
        // always committed.
        guard videoZoomScale > 1.02 else {
            videoPanCommitted = .zero
            videoZoomPan.panLive = .zero
            return
        }
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
            containerExtension: containerExtension,
            isLive: isLiveStream || type == "live"
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
            } catch {
                Log.error("WatchHistory", "Failed to save watch history: \(error)")
            }
        }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                glassIconButton(systemName: "xmark", size: 44) { performPlayerDismiss() }
                    .accessibilityLabel(L("common.close"))
                    .accessibilityIdentifier("player.close")

                // Minimizing used to exist only as the pull-down gesture, which VoiceOver,
                // Switch Control and pointer users cannot perform. Only with an overlay
                // host: without one there is no mini card to go to.
                if playerOverlayMinimize != nil {
                    glassIconButton(systemName: "chevron.down", size: 44) { minimizeFromChrome() }
                        .accessibilityLabel(L("player.a11y.minimize"))
                        .accessibilityIdentifier("player.minimize")
                }
            }

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
                guard !isTouchPartOfDismissDrag else { return }
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
            .playerChromeMaterial(in: Capsule())
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
            .accessibilityLabel(L("player.aspect.title"))
            .accessibilityValue(aspectModeTitle(selectedAspectMode))

            if canShowPiPTopChromeAction {
                groupedCapsuleButton(systemName: "pip") {
                    requestPictureInPicture()
                }
                .accessibilityLabel(L("player.a11y.pip"))
                .disabled(!isPiPActionEnabled)
                .opacity(isPiPActionEnabled ? 1 : 0.4)
            }

            airPlayTopChromeAction

            groupedCapsuleButton(systemName: "textformat.size") {
                showSubtitleAppearance = true
            }
            .accessibilityLabel(L("player.a11y.subtitle_appearance"))

            // Remux selections are forwarded to the writer while AirPlay plays.
            if player.canSelectPlaybackTracks {
                groupedCapsuleButton(systemName: "gearshape") {
                    openTrackSettings()
                }
                .accessibilityLabel(L("player.a11y.track_settings"))
            }

            // Same menu as on compact width: speed, sleep timer and the track pickers
            // have no toolbar button of their own.
            compactTopChromeMoreMenu
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
        // The slot follows the controller's published preparation state. A view-local
        // latch could not: `needsAirPlayPreparation` drops as soon as the cast starts
        // presenting, which used to swap the spinner for an idle-looking picker button
        // one run-loop turn after the tap. With a route already active (a zap during a
        // cast) the system picker stays, since it is the only way back to the phone.
        // It also stays when the hidden picker failed to open the device list: the
        // visible one is then the only way to choose a device for the running preparation.
        if player.isAirPlayPreparing && !player.isAirPlayRouteActive
            && !usesVisibleAirPlayPickerFallback
        {
            ProgressView()
                .tint(.white)
                // Same footprint as the button it replaces, so the capsule keeps its width.
                .frame(width: 44, height: 44)
                .accessibilityLabel(L("player.airplay.preparing"))
        } else if player.isAirPlayVideoCapable {
            if player.needsAirPlayPreparation {
                // FFmpeg-path content: the tap opens the device list and starts the remux
                // preparation side by side (see `prepareAndPresentAirPlay`).
                // Tinted like the system picker's active state while an AirPlay route
                // carries the sound: the button must not look idle then. Display only;
                // the route never starts or ends anything here.
                groupedCapsuleButton(
                    systemName: "airplay.video",
                    tint: player.isAirPlayRouteActive
                        ? Color(uiColor: .systemBlue) : .white.opacity(0.96)
                ) {
                    prepareAndPresentAirPlay()
                }
                .opacity(isAirPlayRouteUnavailable ? 0.4 : 1)
                .accessibilityLabel("AirPlay")
                .accessibilityValue(
                    player.isAirPlayRouteActive
                        ? (player.airPlayRouteName ?? "")
                        : (isAirPlayRouteUnavailable ? L("player.airplay.no_devices") : "")
                )
                // Says "selected" even when the route reports no name.
                .accessibilityAddTraits(player.isAirPlayRouteActive ? .isSelected : [])
            } else {
                AirPlayRoutePickerButton(
                    onWillBegin: {
                        if !isAirPlayPickerListOpen { isAirPlayPickerListOpen = true }
                        player.airPlayPickerWillOpen()
                    },
                    onDidEnd: {
                        if isAirPlayPickerListOpen { isAirPlayPickerListOpen = false }
                        player.airPlayPickerDidClose()
                    }
                )
                .frame(width: 40, height: 34)
                // The glyph keeps its size; the slot is the same 44 pt square as the
                // spinner, the prepare button and the placeholder, so the capsule does
                // not change width when one replaces another.
                .frame(width: 44, height: 44)
                // The picker left its slot (the spinner or the prepare button took
                // it) with the list still up: its "list closed" callback can no
                // longer arrive, and the flag would keep the chrome from hiding.
                // Only the view flag: the system list may still be on screen, and the
                // controller has its own backstop for a close it never hears of.
                .onDisappear {
                    if isAirPlayPickerListOpen { isAirPlayPickerListOpen = false }
                }
                .opacity(isAirPlayRouteUnavailable ? 0.4 : 1)
                .accessibilityLabel("AirPlay")
                .accessibilityValue(isAirPlayRouteUnavailable ? L("player.airplay.no_devices") : "")
            }
        } else if player.isAirPlayCapabilityPending {
            // A load has started and the engine has not reported the codecs yet, so
            // it is not known whether this content can be sent. The slot is kept
            // (dimmed, inert) so the icon does not vanish and the capsule does not
            // change width on every channel change; content that turns out not to
            // be castable drops the slot once, after the probe. Same look as
            // `groupedCapsuleButton`.
            Image(systemName: "airplay.video")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
                .frame(width: 44, height: 44)
                .opacity(0.4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// No second playback route is detected and none is in use: the AirPlay control is
    /// dimmed and reads as unavailable. A negative hint only — detection lags, can miss a
    /// receiver and also counts audio-only routes — so it never starts or ends anything.
    private var isAirPlayRouteUnavailable: Bool {
        !airPlayRoutes.multipleRoutesDetected
            && !player.isAirPlayRouteActive
            && !player.isCastPresenting
    }

    /// The More menu of both size classes: aspect, speed, sleep timer and the track
    /// pickers, then the actions that open a sheet. All SwiftUI (no UIKit-backed menu).
    private var compactTopChromeMoreMenu: some View {
        Menu {
            aspectModeMenuPicker
                // Second report of an opening menu, next to the label's pressed state
                // below. SwiftUI calls it for the first opening after the chrome
                // appeared only, so it cannot be the only one.
                .onAppear { holdChromeForMoreMenu() }

            if showsPlaybackSpeedMenu {
                playbackSpeedMenuPicker
            }

            sleepTimerMenuPicker

            if showsTrackMenuPickers {
                if player.audioTracks.count > 1 {
                    trackMenuPicker(
                        title: L("player.tracks.audio"),
                        systemImage: "waveform",
                        options: player.audioTracks,
                        selection: Binding(
                            get: { player.currentAudioTrackId },
                            set: { id in
                                moreMenuDidAct()
                                player.selectAudioTrack(id: id)
                            }
                        )
                    )
                }
                // The list always starts with "Off"; a picker needs a real track too.
                if player.subtitleTracks.count > 1 {
                    trackMenuPicker(
                        title: L("player.tracks.subtitle"),
                        systemImage: "captions.bubble",
                        options: player.subtitleTracks,
                        selection: Binding(
                            get: { player.currentSubtitleTrackId },
                            set: { id in
                                moreMenuDidAct()
                                player.selectSubtitleTrack(id: id)
                            }
                        )
                    )
                }
            }

            Divider()

            if canShowPiPTopChromeAction {
                Button {
                    moreMenuDidAct()
                    requestPictureInPicture()
                } label: {
                    Label(L("player.a11y.pip"), systemImage: "pip")
                }
                .disabled(!isPiPActionEnabled)
            }

            Button {
                moreMenuDidAct()
                showSubtitleAppearance = true
            } label: {
                Label(L("player.a11y.subtitle_appearance"), systemImage: "textformat.size")
            }

            if player.canSelectPlaybackTracks {
                Button {
                    moreMenuDidAct()
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
        // Declared order top to bottom wherever the menu opens, so rows keep their place.
        .menuOrder(.fixed)
        // Opening the menu holds the chrome (see `moreMenuHoldUntil`). The menu's button
        // stays pressed for as long as its menu is open, and the button style is where
        // SwiftUI reports that. A gesture on the menu does not work: the menu's own
        // button takes the touch, so a tap, a long press or a drag there never fires.
        .buttonStyle(MoreMenuButtonStyle { pressed in
            if pressed { holdChromeForMoreMenu() }
        })
        .accessibilityLabel(L("detail.show_more"))
        .accessibilityIdentifier("player.more")
        // The chrome has to be up for the menu to be opened, so its appearance is the
        // dependable moment to refresh what the track pickers will list.
        .onAppear { refreshTrackMenuLists() }
        // Menu rows are built when this view's body runs. A live stream publishes no
        // clock ticks, so while the chrome stays up (paused, AirPlay, VoiceOver) nothing
        // would re-read the sleep timer's remaining time.
        .task(id: player.sleepTimerEndsAt) {
            guard player.sleepTimerEndsAt != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                sleepTimerMenuTick &+= 1
            }
        }
    }

    /// Longest the open More menu keeps the chrome up when no row is chosen.
    private static let moreMenuHoldSeconds: TimeInterval = 30

    /// The More menu is opening: the chrome that hosts it stays up until a row is
    /// chosen or the hold runs out.
    private func holdChromeForMoreMenu() {
        moreMenuHoldUntil = Date().addingTimeInterval(Self.moreMenuHoldSeconds)
    }

    /// A row of the More menu was chosen: the menu is closed, so its hold on the
    /// chrome ends and a normal auto-hide window starts.
    private func moreMenuDidAct() {
        if moreMenuHoldUntil != nil { moreMenuHoldUntil = nil }
        resetTimer()
    }

    /// Localized name of an aspect mode for the menu and for VoiceOver.
    private func aspectModeTitle(_ mode: VideoAspectMode) -> String {
        switch mode {
        case .fit: return L("player.aspect_fit")
        case .fill: return L("player.aspect_fill")
        case .center: return "1:1"
        }
    }

    private var aspectModeMenuPicker: some View {
        Picker(
            selection: Binding(
                get: { selectedAspectMode },
                set: { mode in
                    moreMenuDidAct()
                    guard mode != selectedAspectMode else { return }
                    // Same zoom / pan reset as the cycling button; a plain binding to the
                    // stored raw value would skip it.
                    resetVideoTransformForAspectSwitch()
                    videoAspectModeRaw = mode.rawValue
                }
            )
        ) {
            ForEach(VideoAspectMode.allCases, id: \.self) { mode in
                Label(aspectModeTitle(mode), systemImage: mode.iconName).tag(mode)
            }
        } label: {
            Label(L("player.aspect.title"), systemImage: selectedAspectMode.iconName)
        }
        .pickerStyle(.menu)
    }

    private static let playbackSpeedOptions: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    /// Speed is for recorded content played on the phone: a live source delivers at 1x,
    /// and the cast player resumes at 1x whatever was chosen.
    private var showsPlaybackSpeedMenu: Bool {
        !isLiveStream && (!player.isCastPresenting || player.isLocalCastPlayback)
    }

    private func playbackSpeedTitle(_ speed: Float) -> String {
        String(format: "%gx", Double(speed))
    }

    private var playbackSpeedMenuPicker: some View {
        Picker(
            selection: Binding(
                get: { player.playbackSpeed },
                set: { speed in
                    moreMenuDidAct()
                    player.setPlaybackSpeed(speed)
                }
            )
        ) {
            ForEach(Self.playbackSpeedOptions, id: \.self) { speed in
                Text(playbackSpeedTitle(speed)).tag(speed)
            }
        } label: {
            Label(L("player.speed.title"), systemImage: "speedometer")
        }
        .pickerStyle(.menu)
    }

    private static let sleepTimerOptionsMinutes = [15, 30, 60]

    /// Row title of the sleep timer: its name, or the time left while one is running.
    private var sleepTimerMenuTitle: String {
        // Read for the dependency only: each tick re-evaluates this title.
        _ = sleepTimerMenuTick
        guard let endsAt = player.sleepTimerEndsAt else { return L("player.sleep.title") }
        let minutesLeft = max(1, Int((endsAt.timeIntervalSinceNow / 60).rounded(.up)))
        return L("player.sleep.remaining", minutesLeft)
    }

    private var sleepTimerMenuPicker: some View {
        Picker(
            selection: Binding(
                // 0 is "Off". Once the timer has fired or was cancelled the controller
                // reports no end date, and the remembered choice no longer applies.
                get: { player.sleepTimerEndsAt == nil ? 0 : sleepTimerChoiceMinutes },
                set: { minutes in
                    moreMenuDidAct()
                    sleepTimerChoiceMinutes = minutes
                    player.setSleepTimer(minutes: minutes > 0 ? minutes : nil)
                }
            )
        ) {
            Text(L("player.sleep.off")).tag(0)
            ForEach(Self.sleepTimerOptionsMinutes, id: \.self) { minutes in
                Text(L("player.sleep.minutes", minutes)).tag(minutes)
            }
        } label: {
            Label(sleepTimerMenuTitle, systemImage: "moon.zzz")
        }
        .pickerStyle(.menu)
    }

    /// Remux casts retain source tracks and forward selections to their writer.
    private var showsTrackMenuPickers: Bool {
        player.canSelectPlaybackTracks
    }

    /// Always a labelled submenu, like the aspect, speed and sleep-timer rows. Listed
    /// inline, the audio and the subtitle tracks were two runs of rows with no heading
    /// (a `Section` title is not drawn for an inline picker inside a menu) and could
    /// not be told apart; a long list also pushed the rest of the menu off screen.
    private func trackMenuPicker(
        title: String,
        systemImage: String,
        options: [TrackMenuOption],
        selection: Binding<Int>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.id)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .pickerStyle(.menu)
    }

    /// Re-reads the engine's tracks into the controller's published lists. Skipped while
    /// a cast presents (the stopped engine would report empty lists and wipe the
    /// selection the cast was started with) and before playback is established (the
    /// controller builds the first list itself then, together with the saved preferences).
    private func refreshTrackMenuLists() {
        guard !player.isCastPresenting, isPresentationEstablished else { return }
        player.updateTracks()
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

    /// The PiP button is usable while a window is up (it closes it), or when the system
    /// reports that one can be opened and `requestPictureInPicture` would accept the
    /// tap. Paused or buffering playback is refused there, so the control is dimmed
    /// instead of taking a tap that does nothing.
    private var isPiPActionEnabled: Bool {
        player.isPiPActive || (player.isPictureInPicturePossible && canEnterPiPNow)
    }

    private func requestPictureInPicture() {
        if player.isPiPActive {
            player.stopPictureInPicture()
            return
        }
        guard canEnterPiPNow else { return }
        player.startPictureInPicture()
    }

    /// PiP opens over the app, which stays in front: while the window is up the
    /// fullscreen surface is empty. The player steps aside into the mini card for that
    /// time and comes back when the window returns to the app.
    private func handlePictureInPictureChange(_ active: Bool) {
        guard active != pipTracking.lastActive else { return }
        pipTracking.lastActive = active
        if active {
            // Only for a window opened over the app in front. Automatic PiP starts while
            // the app is leaving the foreground; docking there would make the window
            // return into the mini card instead of the fullscreen player.
            guard UIApplication.shared.applicationState == .active,
                  let minimize = playerOverlayMinimize,
                  !isMiniCommitted, !isClosing, isMorphAtFullscreen else { return }
            if isFastForwarding { applySpeedHoldEnded() }
            pipTracking.minimizedForPictureInPicture = true
            // `onChange(of: overlayMode)` settles the chrome and runs the morph.
            minimize()
        } else {
            guard pipTracking.minimizedForPictureInPicture else { return }
            pipTracking.minimizedForPictureInPicture = false
            // One main-queue turn later: the controller is in the middle of the pass
            // that announced the change, and `isPlaying` is published further down it.
            DispatchQueue.main.async {
                // The engine does not report whether the window was sent back to the
                // app or closed with its X. Closing pauses playback, returning does
                // not, so the card expands only while playback is still running; a
                // closed window leaves the paused card where it is.
                guard morph.progress > 0.5, !isClosing, player.isPlaying else { return }
                playerOverlayExpand?()
            }
        }
    }

    /// The AirPlay button on FFmpeg-path content. The device list opens on the tap and
    /// the remux preparation runs next to it, so choosing a device overlaps the wait for
    /// the first segments. The cast still starts only from this explicit tap.
    private func prepareAndPresentAirPlay(ignoringRouteDetection: Bool = false) {
        // Nothing detected that could receive a cast: say so instead of stopping
        // playback for a device list that would hold only this phone. Detection lags
        // and can miss a receiver, so the notice offers the full flow as an explicit
        // choice; the dimmed button itself never starts a preparation.
        guard ignoringRouteDetection || !isAirPlayRouteUnavailable else {
            presentAirPlayUnavailableNotice()
            return
        }
        dismissAirPlayUnavailableNotice()
        // Not over the docked mini card (read from the morph model, which is live; the
        // captured environment mode can be stale here), and not when an AirPlay route
        // already carries the cast: there is nothing left to choose then.
        let opensPicker = isMorphAtFullscreen && !player.isAirPlayRouteActive
        // Only a refusal that arrives before `prepareAirPlay` returns matters here (no
        // Wi-Fi, listener down, nothing loaded): the engine was not touched, a notice
        // says why, and a device list opened now would have no cast behind it. Later
        // outcomes are reported through the controller's published state; the
        // completion no longer opens the picker (it used to pop up as much as a minute
        // after the tap, even when a device had been chosen in the meantime).
        var refusedBeforeStarting = false
        player.prepareAirPlay { success in
            if !success { refusedBeforeStarting = true }
        }
        guard opensPicker, !refusedBeforeStarting else { return }
        openHiddenAirPlayPicker()
    }

    /// Opens the system device list through the hidden route picker and checks that it
    /// came up. The open is a tap sent to a private subview of `AVRoutePickerView`; when
    /// that subview is missing nothing happens and nothing reports it, which would leave
    /// a preparation running with no way to choose a device.
    private func openHiddenAirPlayPicker() {
        airPlayPickerSignal += 1
        hiddenAirPlayPickerCheckToken &+= 1
        let token = hiddenAirPlayPickerCheckToken
        isAwaitingHiddenAirPlayPicker = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.hiddenAirPlayPickerCheckNanoseconds)
            guard token == hiddenAirPlayPickerCheckToken else { return }
            hiddenAirPlayPickerDidFailToOpen()
        }
    }

    /// The hidden picker did not bring up the device list: reported by the picker
    /// itself when it could not send its tap, or by the watchdog when a tap that was
    /// sent had no effect. The AirPlay slot switches to the visible system picker.
    private func hiddenAirPlayPickerDidFailToOpen() {
        // Not waiting any more: the list did open, or this was already handled.
        guard isAwaitingHiddenAirPlayPicker else { return }
        isAwaitingHiddenAirPlayPicker = false
        if !usesVisibleAirPlayPickerFallback {
            // Logged once: the flag stays set until a later open is confirmed.
            Log.error(
                "AirPlayCast",
                "hidden route picker did not present the device list; showing the visible picker button"
            )
            usesVisibleAirPlayPickerFallback = true
        }
        // The visible picker lives in the chrome: make sure it is on screen.
        if isMorphAtFullscreen, !showControls {
            withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
            resetTimer()
        }
    }

    /// The presentation callback normally follows the programmatic tap within the same
    /// run-loop turn; the margin covers a main thread still busy stopping the engine.
    private static let hiddenAirPlayPickerCheckNanoseconds: UInt64 = 800_000_000

    /// The system reported the device list for the hidden picker.
    private func hiddenAirPlayPickerDidOpen() {
        if isAwaitingHiddenAirPlayPicker { isAwaitingHiddenAirPlayPicker = false }
        if usesVisibleAirPlayPickerFallback { usesVisibleAirPlayPickerFallback = false }
        player.airPlayPickerWillOpen()
    }

    /// Shows "No AirPlay devices found" for a few seconds (longer for assistive
    /// technologies, which need time to reach its button) and speaks it.
    private func presentAirPlayUnavailableNotice() {
        airPlayUnavailableNoticeToken &+= 1
        let token = airPlayUnavailableNoticeToken
        withAnimation(.easeInOut(duration: 0.18)) {
            showsAirPlayUnavailableNotice = true
        }
        UIAccessibility.post(notification: .announcement, argument: L("player.airplay.no_devices"))
        let seconds: UInt64 = isAssistiveTechRunning ? 20 : 6
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard token == airPlayUnavailableNoticeToken else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showsAirPlayUnavailableNotice = false
            }
        }
    }

    private func dismissAirPlayUnavailableNotice() {
        airPlayUnavailableNoticeToken &+= 1
        if showsAirPlayUnavailableNotice { showsAirPlayUnavailableNotice = false }
    }

    /// The notice sits in the AirPlay status slot. The two never show together: this one
    /// is dismissed when a preparation starts.
    private func airPlayUnavailableOverlay(outerSafeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            if showsAirPlayUnavailableNotice && !player.isAirPlayPreparing {
                airPlayUnavailablePill
                    .transition(hudNoticeTransition)
            }
            Spacer(minLength: 0)
        }
        // Same anchor as the AirPlay status pill: below the toast row and the top chrome.
        .padding(.top, max(64 + 44, outerSafeAreaInsets.top + 16 + 44 + 10))
        .padding(.leading, 16 + outerSafeAreaInsets.leading)
        .padding(.trailing, 16 + outerSafeAreaInsets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: showsAirPlayUnavailableNotice)
        .zIndex(42)
    }

    private var airPlayUnavailablePill: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "airplay.video")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L("player.airplay.no_devices"))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Button {
                resetTimer()
                prepareAndPresentAirPlay(ignoringRouteDetection: true)
            } label: {
                Text(L("player.airplay.try_anyway"))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.white.opacity(0.18), in: Capsule())
                    // The visible chip is small; the hit area is the full pill height.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .frame(minHeight: 44)
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .playerChromeMaterial(in: Capsule())
    }

    // MARK: - AirPlay status

    /// AirPlay preparation status and transient cast notices. They sit in the overlay
    /// stack above the UIKit touch overlay rather than on the video surface (which
    /// ignores hits and scales with pinch) or in the chrome (which auto-hides in the
    /// middle of a preparation). One slot below the aspect-toast / 2x-badge row serves
    /// both: a notice replaces the pill when the preparation ends.
    private func airPlayStatusOverlay(outerSafeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            if player.isAirPlayPreparing {
                airPlayPreparingPill
                    .transition(hudNoticeTransition)
            } else if let castNoticeToastText {
                castNoticeToast(castNoticeToastText)
                    .transition(hudNoticeTransition)
            }
            Spacer(minLength: 0)
        }
        // Below the toast row (64 pt from the top) and, in portrait, below the top chrome.
        .padding(.top, max(64 + 44, outerSafeAreaInsets.top + 16 + 44 + 10))
        .padding(.leading, 16 + outerSafeAreaInsets.leading)
        .padding(.trailing, 16 + outerSafeAreaInsets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: player.isAirPlayPreparing)
        .zIndex(42)
        .onChange(of: player.castNotice) { _, notice in
            presentCastNotice(notice)
        }
    }

    private var airPlayPreparingPill: some View {
        // Read once per render. A preparation the user started from the AirPlay button
        // can always be cancelled: the device is usually picked seconds into the wait,
        // and "Switch to AirPlay" starts with the route already active. A zap or a
        // rebuild of a running cast keeps no Cancel: leaving that cast is the system
        // picker's job.
        let canCancel = !player.isAirPlayRouteActive || player.isAirPlayPreparingFromButton
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "airplay.video")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L("player.airplay.preparing"))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("player.airplay.preparing"))

            if canCancel {
                Button {
                    player.cancelAirPlayPreparation()
                } label: {
                    Text(L("common.cancel"))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.white.opacity(0.18), in: Capsule())
                        // The visible chip is small; the hit area is the full pill height.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .frame(minHeight: 44)
        .padding(.leading, 16)
        .padding(.trailing, canCancel ? 7 : 16)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }

    private func castNoticeToast(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "airplay.video")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.leading)
                // No line cap: a notice can be two sentences, and the second one
                // (where the sound went) must not be cut off.
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Capsule-shaped for one line, a rounded card once the message wraps.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        // Outside the background, so the card hugs short messages and only long ones
        // are capped and wrapped.
        .frame(maxWidth: 360)
        .allowsHitTesting(false)
    }

    /// Shows a cast notice for 4 to 10 s, by its length. Silent ends (the user stopped the cast, a
    /// deliberate route change) have no message and show nothing.
    private func presentCastNotice(_ notice: CastNotice?) {
        guard let notice, let message = player.castNoticeMessage(for: notice),
              !message.isEmpty else { return }
        castNoticeToastToken &+= 1
        let token = castNoticeToastToken
        withAnimation(.easeInOut(duration: 0.18)) {
            castNoticeToastText = message
        }
        // The toast never takes VoiceOver focus and is invisible on the mini card, so
        // it is spoken as well.
        UIAccessibility.post(notification: .announcement, argument: message)
        // Long enough to read: about 20 characters a second, one sentence stays at 4 s.
        let seconds = min(10.0, max(4.0, Double(message.count) / 20.0))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard token == castNoticeToastToken else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                castNoticeToastText = nil
            }
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
        tint: Color = .white.opacity(0.96),
        action: @escaping () -> Void
    ) -> some View {
        Button {
            // See `glassIconButton`: not for the release of a dismiss drag.
            guard !isTouchPartOfDismissDrag else { return }
            resetTimer()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
                .frame(width: 44, height: 44)  // HIG minimum dokunma hedefi
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Pointer only (iPad trackpad or mouse); touch is unchanged. The highlight is
        // a disc inside the slot, so neighbours in the capsule do not touch, and the
        // tap area stays the full square.
        .contentShape(.hoverEffect, Circle().inset(by: 2))
        .hoverEffect(.highlight)
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
            // Skip buttons stay mounted (and enabled) through a rebuffer: every seek
            // passes through one, and with the button gone the next tap used to land
            // on the video surface and hide the chrome. Only the centre glyph changes.
            if effectiveSeekable {
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

            if effectiveSeekable {
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
        // Playback controls are not mirrored in right-to-left languages (UIKit's
        // `.playback` semantic): rewind stays on the left, as its glyph points.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var centerTransportSymbolName: String {
        if needsPlaybackRetry { return "arrow.clockwise" }
        return player.isPlaying ? "pause.fill" : "play.fill"
    }

    private var centerTransportAccessibilityLabel: String {
        if needsPlaybackRetry { return L("common.try_again") }
        if isCenterTransportLoading && !isPresentationEstablished { return L("common.loading") }
        return player.isPlaying ? L("player.a11y.pause") : L("player.a11y.play")
    }

    private func performCenterTransportAction() {
        if needsPlaybackRetry {
            player.retryCurrentLoad()
            return
        }
        // Before the first frame there is nothing to pause or resume. The button still
        // takes the tap, so it cannot fall through to the surface and hide the chrome.
        guard !isCenterTransportLoading || isPresentationEstablished else { return }
        player.togglePlayPause()
    }

    /// Centre slot: one button of a fixed size whose glyph is play / pause, the retry
    /// arrow after a failure, or the (debounced) spinner. Nothing is inserted into or
    /// removed from the row, so it never reflows.
    private var centerPlayPauseOrLoadingButton: some View {
        let showsSpinner = showsLoadingSpinner
        return transparentTransportButton(
            systemName: centerTransportSymbolName,
            symbolSize: transportPlaySymbol,
            hitFrame: transportPlayHit,
            showsSpinner: showsSpinner
        ) {
            performCenterTransportAction()
        }
        .accessibilityLabel(centerTransportAccessibilityLabel)
        .accessibilityIdentifier("player.playPause")
        .animation(.easeInOut(duration: 0.2), value: showsSpinner)
    }

    /// Glass arkaplansız iOS native stili transport butonu: SF Symbol + subtle shadow.
    /// `showsSpinner` swaps the glyph for a progress indicator inside the same frame.
    private func transparentTransportButton(
        systemName: String,
        symbolSize: CGFloat,
        hitFrame: CGFloat = 64,
        showsSpinner: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            // The transport row lies where a pull-down may start: a drag that began on
            // one of its buttons must not also play, pause or skip when it is released.
            guard !isTouchPartOfDismissDrag else { return }
            resetTimer()
            action()
        } label: {
            ZStack {
                Image(systemName: systemName)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
                    .opacity(showsSpinner ? 0 : 1)
                if showsSpinner {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.95))
                        .scaleEffect(1.6)
                        .transition(.opacity)
                }
            }
            .frame(width: hitFrame, height: hitFrame)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Bölüm atlama ayrı; zaman çubuğu yalnızca `scrubTimelineCard` içinde.
    private var bottomTransportChrome: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showsExtrasRow {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if liveExtrasUseOwnRow {
                        recallLastChannelButton
                    }
                    rotateFullscreenButton
                }
                .padding(.horizontal, 12)
            }

            if showsLiveChannelRow {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if !liveExtrasUseOwnRow {
                        recallLastChannelButton
                    }
                    if showLiveChannelSkip {
                        // Previous/next keep their physical order in right-to-left languages
                        // (these symbols do not mirror, so a flipped row made the chevrons
                        // face each other). Only the pair is pinned: the row itself still
                        // follows the trailing edge, clear of the leading programme strip.
                        HStack(spacing: 8) {
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
                        .environment(\.layoutDirection, .leftToRight)
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
                    if !liveExtrasUseOwnRow {
                        rotateFullscreenButton
                    }
                }
                .padding(.horizontal, 12)
            }

            if showSeriesEpisodeSkip {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    // Pair pinned left-to-right (see the live row above).
                    HStack(spacing: 8) {
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
                    .environment(\.layoutDirection, .leftToRight)
                    if !hasLiveActionRow {
                        rotateFullscreenButton
                    }
                }
                .padding(.horizontal, 12)
            }

            if showVODQueueSkip {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    // Pair pinned left-to-right (see the live row above).
                    HStack(spacing: 8) {
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
                    .environment(\.layoutDirection, .leftToRight)
                    if !hasLiveActionRow && !showSeriesEpisodeSkip {
                        rotateFullscreenButton
                    }
                }
                .padding(.horizontal, 12)
            }

            if isLiveStream {
                liveTimelineCard
            } else {
                scrubTimelineCard
            }
        }
    }

    /// Live content has channel controls: skipping, the channel list or the recall button.
    private var hasLiveActionRow: Bool {
        showLiveChannelSkip || showLiveChannelListButton || showLiveRecallButton
    }

    /// Narrow and tall (iPhone portrait, a slim iPad window). The channel row then shares
    /// its band with the programme strip in the opposite corner and must not grow wider
    /// than it is today, so the newer live controls (recall, rotate) take a row of their
    /// own above it. With more width (landscape, iPad) they join the channel row.
    private var liveExtrasUseOwnRow: Bool {
        hasLiveActionRow && isCompactWidth && chromeVerticalSizeClass != .compact
    }

    private var showsLiveChannelRow: Bool {
        showLiveChannelSkip || showLiveChannelListButton
            || (showLiveRecallButton && !liveExtrasUseOwnRow)
    }

    /// Buttons in the live channel row of `bottomTransportChrome`, counted by the same
    /// conditions that mount them there. Keep the two in step.
    private var liveChannelRowButtonCount: Int {
        guard showsLiveChannelRow else { return 0 }
        var count = 0
        if showLiveChannelSkip { count += 2 }
        if showLiveChannelListButton { count += 1 }
        if !liveExtrasUseOwnRow {
            if showLiveRecallButton { count += 1 }
            if showsRotateFullscreenButton { count += 1 }
        }
        return count
    }

    /// Width the programme strip may take: it ends before the channel row begins, which
    /// sits at the same height on the trailing side. A fixed 240 pt ran a long title
    /// over the previous-channel button on a portrait iPhone.
    private func programmeStripMaxWidth(containerWidth: CGFloat, insets: EdgeInsets) -> CGFloat {
        PlayerProgrammeStripLayout.maxWidth(
            containerWidth: containerWidth,
            leadingInset: insets.leading,
            trailingInset: insets.trailing,
            rowButtonCount: liveChannelRowButtonCount
        )
    }

    /// A trailing row above the others for controls that have no row to join: the live
    /// extras in the narrow layout, or the rotate button on content with no skip row.
    private var showsExtrasRow: Bool {
        if liveExtrasUseOwnRow { return showLiveRecallButton || showsRotateFullscreenButton }
        return showsRotateFullscreenButton && !hasLiveActionRow
            && !showSeriesEpisodeSkip && !showVODQueueSkip
    }

    /// The host remembers a previous channel (it supplies the action only then).
    private var showLiveRecallButton: Bool {
        isLiveStream && onRecallLastChannel != nil
    }

    /// Switches back to the channel that was playing before the current one.
    @ViewBuilder
    private var recallLastChannelButton: some View {
        if showLiveRecallButton, let recall = onRecallLastChannel {
            glassIconButton(systemName: "arrow.uturn.backward.circle.fill", size: 44, symbolSize: 17) {
                recall()
            }
            .accessibilityLabel(L("player.a11y.last_channel"))
            .disabled(!canRecallLastChannel)
            .opacity(canRecallLastChannel ? 1 : 0.38)
        }
    }

    /// Forcing landscape goes through the window scene's geometry, which iPad's
    /// resizable windows ignore: the button is iPhone only.
    private var showsRotateFullscreenButton: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Enters landscape under Portrait Orientation Lock, and leaves it again. It rides at
    /// the trailing end of the episode / queue / channel row, or in `showsExtrasRow`.
    @ViewBuilder
    private var rotateFullscreenButton: some View {
        if showsRotateFullscreenButton {
            glassIconButton(
                systemName: isLandscapeForced
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: 44,
                symbolSize: 17
            ) {
                toggleLandscapeFullscreen()
            }
            .accessibilityLabel(
                isLandscapeForced ? L("player.a11y.exit_landscape") : L("player.a11y.enter_landscape")
            )
            // The mini morph and a rotation both resize the container; never start one
            // inside the other.
            .disabled(isMorphEngaged)
        }
    }

    /// The scrubber row. `PlayerScrubBar` observes the playback clock and keeps the live
    /// scrub value itself; this body only hears that a scrub began, ended or was
    /// cancelled.
    private var scrubTimelineCard: some View {
        PlayerScrubBar(
            clock: player.clock,
            isSeekable: effectiveSeekable,
            isScrubbing: isScrubbing,
            lockedValue: lockedSliderValue,
            // During AirPlay the engine is stopped or remote; its buffer end says nothing
            // about what the receiver holds.
            showsBufferedRange: !player.isAirPlayPlaybackActive,
            onScrubBegan: { beginScrub() },
            onScrubEnded: { target in commitScrub(to: target) },
            onScrubCancelled: { cancelScrub() },
            onLockReleased: { if lockedSliderValue != nil { lockedSliderValue = nil } },
            onAccessibilityJump: { seconds in
                resetTimer()
                player.jump(seconds: seconds)
            },
            onInteraction: { resetTimer() }
        )
    }

    private func beginScrub() {
        if isFastForwarding { applySpeedHoldEnded() }
        // A touch on the timeline after the end means the viewer wants this episode:
        // the seek is only issued on release, too late to stop the next-episode
        // countdown.
        cancelAutoAdvanceCountdown()
        // Armed once per scrub: while `isScrubbing` is set the timer re-arms itself
        // instead of hiding the chrome (see `resetTimer`).
        resetTimer()
        isScrubbing = true
    }

    /// The scrub ended on `target` (a fraction of the duration): seek there and keep the
    /// thumb pinned to it until playback reports the new position.
    private func commitScrub(to target: Double) {
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

    /// Closes a scrub that was interrupted (touch cancelled, timeline unmounted) WITHOUT
    /// seeking. A leaked `isScrubbing` froze the thumb and the elapsed label, kept the
    /// chrome from auto-hiding and blocked both the 2x hold and the pull-down.
    private func cancelScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        lockedSliderValue = nil
        // Chrome still up (touch cancelled in place): give it a fresh auto-hide window.
        if showControls { resetTimer() }
    }

    /// Live streams have nothing to scrub: the scrubber row carries the LIVE badge
    /// instead. It sits at the trailing end, where the duration label is for a film, so
    /// it stays clear of the programme strip in the opposite corner.
    private var liveTimelineCard: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            liveBadge
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    /// Red while the stream runs; grey once it is paused, stopped or failed, because the
    /// picture is then no longer the live edge.
    private var liveBadge: some View {
        let isRunning: Bool
        switch player.state {
        case .paused, .stopped, .ended, .error: isRunning = false
        default: isRunning = true
        }
        return HStack(spacing: 5) {
            Circle()
                .fill(Color.white.opacity(isRunning ? 0.95 : 0.6))
                .frame(width: 6, height: 6)
            Text(L("player.live_badge"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(isRunning ? 0.95 : 0.7))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            isRunning ? Color(red: 0.86, green: 0.14, blue: 0.16) : Color.white.opacity(0.24),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
        .animation(.easeInOut(duration: 0.2), value: isRunning)
        .accessibilityElement(children: .combine)
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
                // Same rule as the transport row: a dismiss drag (edge-back or
                // pull-down) that began on this button must not also run its action
                // when it is released.
                guard !isTouchPartOfDismissDrag else { return }
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
            // The other suspension reasons (paused, ended, failed, AirPlay, assistive
            // technology) wait the same way; `chromeStateDriver` re-arms a full window
            // the moment the last of them ends, this re-check is only the safety net.
            guard !isAutoHideSuspended else {
                resetTimer()
                return
            }
            // Cross-fade out like the native player instead of a hard cut.
            withAnimation(.easeInOut(duration: 0.28)) { showControls = false }
        }
    }

    // MARK: - Chrome auto-hide and accessibility

    /// Paused or finished playback. A pause taken during a rebuffer keeps reporting
    /// `.buffering` until the next play, so that case is read from the presentation.
    private var isPlaybackPausedOrEnded: Bool {
        switch player.state {
        case .paused, .ended:
            return true
        case .buffering:
            return isPresentationEstablished && !player.isPlaying
        default:
            return false
        }
    }

    /// Auto-hide waits while the chrome is what the user is working with: playback is
    /// paused, finished or failed, AirPlay is preparing or the picture is on the receiver
    /// (the phone is the remote then), the AirPlay device list of the visible picker is
    /// open, the More menu was opened and no row has been chosen yet (bounded by
    /// `moreMenuHoldUntil`; when that passes, the timer's own re-check hides the chrome),
    /// a scrub is in progress, or an assistive technology is running. Reads only state
    /// objects and @State, so it is also correct inside the timer closure, which runs
    /// against an older copy of this view.
    private var isAutoHideSuspended: Bool {
        isScrubbing
            || isPlaybackPausedOrEnded
            || hasPlaybackFailure
            || player.isAirPlayPreparing
            || player.isAirPlayPlaybackActive
            || isAirPlayPickerListOpen
            || (moreMenuHoldUntil.map { $0 > Date() } ?? false)
            || isAssistiveTechRunning
    }

    /// Invisible and always mounted (the chrome itself is not): keeps the auto-hide
    /// timer, the route detector and the assistive-technology flag in step with state
    /// that changes while the chrome may be hidden.
    private var chromeStateDriver: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Route detection costs power: only while the fullscreen player is on screen.
            .onAppear { airPlayRoutes.setActive(!isMiniCommitted) }
            .onDisappear { airPlayRoutes.setActive(false) }
            .onChange(of: isMiniCommitted) { _, mini in
                airPlayRoutes.setActive(!mini)
                if mini { dismissAirPlayUnavailableNotice() }
            }
            .onChange(of: isAirPlayRouteUnavailable) { _, unavailable in
                if !unavailable { dismissAirPlayUnavailableNotice() }
            }
            .onChange(of: isAutoHideSuspended) { _, suspended in
                // The last suspension reason ended: start a full window. The pending
                // timer could otherwise fire a moment after playback resumes.
                guard !suspended, showControls, !isMiniCommitted, isMorphAtFullscreen else { return }
                resetTimer()
            }
            .onChange(of: isPlaybackPausedOrEnded) { _, held in
                if held { revealChromeForHeldPlayback() }
            }
            // Received, not `onChange`: this runs when the controller publishes, also
            // while the app is in the background, where a deferred view update would
            // see the application state of a later moment.
            .onReceive(player.$isPiPActive) { active in
                handlePictureInPictureChange(active)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            ) { _ in syncAssistiveTechState() }
            .onReceive(
                NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)
            ) { _ in syncAssistiveTechState() }
    }

    /// Paused or finished playback shows its controls: one tap resumes, and the paused
    /// state is visible. Not on the mini card and not during its morph, where the
    /// fullscreen chrome is deliberately unmounted, and not for the pause the close
    /// exit takes while the player fades away.
    private func revealChromeForHeldPlayback() {
        guard !isMiniCommitted, isMorphAtFullscreen, !isExpandingFromMini, !isClosing,
              !showControls else { return }
        withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        resetTimer()
    }

    private func syncAssistiveTechState() {
        let running = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
        guard running != isAssistiveTechRunning else { return }
        isAssistiveTechRunning = running
        // The chrome is the only part of the player these technologies can focus.
        if running { showControlsForAccessibility() }
    }

    private func showControlsForAccessibility() {
        guard !isMiniCommitted, isMorphAtFullscreen else { return }
        if !showControls {
            withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        }
        resetTimer()
    }

    /// Button and accessibility-action counterpart of the pull-down gesture. It asks the
    /// overlay host to minimize; `onChange(of: overlayMode)` then settles the chrome and
    /// runs the morph, as it does for every minimize that does not come from the drag.
    private func minimizeFromChrome() {
        guard let minimize = playerOverlayMinimize, !isMiniCommitted, isMorphAtFullscreen else { return }
        if isFastForwarding { applySpeedHoldEnded() }
        minimize()
    }

    /// The 2x hold as a toggle, for users who cannot hold a finger on the video.
    private func toggleSpeedHoldForAccessibility() {
        if isFastForwarding {
            applySpeedHoldEnded()
        } else {
            applySpeedHoldBegan()
        }
    }

    /// VoiceOver / Switch Control handle for the video itself. Showing the chrome,
    /// minimizing and the 2x hold are otherwise gestures on a UIKit view that assistive
    /// technologies cannot reach. It covers the surface below every chrome layer and
    /// takes no touches.
    private var playerSurfaceAccessibilityElement: some View {
        Color.clear
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityIdentifier("player.surface")
            .accessibilityHint(L("player.a11y.show_controls"))
            .accessibilityAction { showControlsForAccessibility() }
            // Two-finger double tap with focus on the video: play / pause (or retry),
            // the same action as the centre button and the Space key.
            .accessibilityAction(.magicTap) { performCenterTransportAction() }
            .accessibilityActions {
                Button(L("player.a11y.show_controls")) { showControlsForAccessibility() }
                if playerOverlayMinimize != nil {
                    Button(L("player.a11y.minimize")) { minimizeFromChrome() }
                }
                if canBeginSpeedHold || isFastForwarding {
                    Button(L("player.a11y.toggle_2x")) { toggleSpeedHoldForAccessibility() }
                }
            }
            .allowsHitTesting(false)
    }

    /// Reports whether any playback route besides the built-in one exists, so the
    /// AirPlay control can look unavailable when nothing could receive a cast. Detection
    /// raises power use (the SDK asks for it to be off whenever it is not needed), so it
    /// runs only while asked to and while the app is in the foreground.
    private final class AirPlayRouteAvailability: ObservableObject {
        /// Optimistic whenever the answer is unknown (detector off, or still looking):
        /// the control must not look unavailable on a guess.
        @Published private(set) var multipleRoutesDetected = true

        private let detector = AVRouteDetector()
        private var wantsDetection = false
        private var isInBackground = UIApplication.shared.applicationState == .background
        /// Discovery reports "no routes" until it has finished looking; that first
        /// answer is not trusted for this long after detection is switched on.
        private static let settleSeconds: TimeInterval = 4
        private var isSettling = false
        private var settleGeneration: UInt64 = 0
        private var cancellables = Set<AnyCancellable>()

        init() {
            let center = NotificationCenter.default
            center.publisher(for: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: detector)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.publish() }
                .store(in: &cancellables)
            center.publisher(for: UIApplication.didEnterBackgroundNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isInBackground = true
                    self?.apply()
                }
                .store(in: &cancellables)
            center.publisher(for: UIApplication.willEnterForegroundNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isInBackground = false
                    self?.apply()
                }
                .store(in: &cancellables)
        }

        deinit {
            detector.isRouteDetectionEnabled = false
        }

        /// `true` while the fullscreen player is on screen.
        func setActive(_ active: Bool) {
            guard wantsDetection != active else { return }
            wantsDetection = active
            apply()
        }

        private func apply() {
            let enable = wantsDetection && !isInBackground
            if detector.isRouteDetectionEnabled != enable {
                detector.isRouteDetectionEnabled = enable
                settleGeneration &+= 1
                isSettling = enable
                if enable {
                    let generation = settleGeneration
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSeconds) { [weak self] in
                        guard let self, generation == self.settleGeneration else { return }
                        self.isSettling = false
                        self.publish()
                    }
                }
            }
            publish()
        }

        private func publish() {
            let detected = !detector.isRouteDetectionEnabled || isSettling
                || detector.multipleRoutesDetected
            if multipleRoutesDetected != detected { multipleRoutesDetected = detected }
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
            // Same localized names as the aspect picker in the More menu.
            aspectToastText = aspectModeTitle(selectedAspectMode)
        }
        // The toast is visual only and gone in about a second: speak the new mode too.
        UIAccessibility.post(
            notification: .announcement, argument: aspectModeTitle(selectedAspectMode)
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard token == aspectToastToken else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                aspectToastText = nil
            }
        }
    }

    // MARK: - Picture overlays (subtitles, opening artwork)

    /// The part of the picture that is on screen at 1x zoom: the fitted frame times the
    /// `.fill` cover scale, limited to the container. Computed here rather than read
    /// from the synced `videoAspectFillScale` state, so it is right in the same pass
    /// as a rotation or a mode change.
    private func visiblePictureSize(fitted: CGSize, container: CGSize) -> CGSize {
        let scale = aspectFillScale(viewport: container, fitted: fitted)
        return CGSize(
            width: min(fitted.width * scale, container.width),
            height: min(fitted.height * scale, container.height)
        )
    }

    /// Distance from the top of the scrubber row down to the bottom safe-area edge: the
    /// chrome's 12 pt bottom padding, the timeline card's 6 pt and the 44 pt timeline
    /// (see `playerChromeAndVideo`, `scrubTimelineCard` and `PlayerTimeline`).
    private static let scrubberRowTopAboveSafeArea: CGFloat = 12 + 6 + 44

    /// Text subtitles, outside `VideoZoomPanLayer`: framed to the visible picture and
    /// never scaled, panned or cropped with it. Bitmap cues stay on the surface.
    /// `progress` is the morph progress (0...1), handed in by `MiniMorphProgressReader`.
    private func subtitleTextLayer(
        progress: CGFloat, fitted: CGSize, container: CGSize, safeAreaBottom: CGFloat
    ) -> some View {
        let fullscreen = 1 - progress
        let visible = visiblePictureSize(fitted: fitted, container: container)
        // The docked card shows exactly the fitted frame (see `miniTargetScale`), so the
        // layer shrinks to it along the morph. In fit / center both sizes are equal.
        let frame = CGSize(
            width: miniLerp(visible.width, min(visible.width, fitted.width), progress),
            height: miniLerp(visible.height, min(visible.height, fitted.height), progress)
        )
        // Screen space from here on: how far the picture's bottom edge already is from
        // the bottom edge of the screen (the letterbox bar, if there is one).
        let gap = max((container.height - frame.height) / 2, 0)
        // Only the part of the bottom safe area that reaches into the picture.
        let safeAreaInset = max(safeAreaBottom - gap, 0) * fullscreen
        // With the controls up, clear the scrubber row and nothing else: live has no
        // scrubber, and clearing the episode buttons as well would push cues into the
        // centre transport on a short screen. The letterbox bar absorbs what it can, so
        // in portrait nothing moves.
        let scrubberClearance = (showControls && !isLiveStream)
            ? max(safeAreaBottom + Self.scrubberRowTopAboveSafeArea + 4 - gap, 0) * fullscreen
            : 0
        return KSSubtitleTextLayer(
            engine: player.engine,
            bottomInset: safeAreaInset,
            minimumBottomClearance: scrubberClearance
        )
        .frame(width: frame.width, height: frame.height)
        // Same curve as the chrome cross-fade, so the cue and the scrubber move together.
        .animation(.easeInOut(duration: 0.28), value: showControls)
        // Deliberately not in the faded fullscreen container: cues are part of the
        // picture and stay on the docked mini card, as they did while they lived in the
        // surface.
        .allowsHitTesting(false)
    }

    /// Up while a load has not shown a picture yet. The latch carries it through the
    /// first buffering pass after "ready"; a rebuffer on an established stream never
    /// sets it.
    private var showsOpeningArtwork: Bool {
        guard artworkURL != nil, isCenterTransportLoading else { return false }
        // Once the video is on the AirPlay target the surface shows its own placeholder.
        if player.isAirPlayPlaybackActive { return false }
        return !isPresentationEstablished || openingArtworkLatched
    }

    /// Channel logo or poster, dimmed and centred on the black surface on first open and
    /// on every zap, faded out when the picture arrives. The previous frame is not held:
    /// the surface container is shared with cast view swaps and KSPlayer's own fallback
    /// swap, and a held frame would have to be cleared on every failure path.
    private func openingArtworkLayer(pictureSize: CGSize) -> some View {
        let side = min(min(pictureSize.width, pictureSize.height) * 0.42, 180)
        let artwork = ZStack {
            if showsOpeningArtwork, side >= 32 {
                CachedImage(
                    url: artworkURL,
                    width: side,
                    height: side,
                    cornerRadius: 14,
                    contentMode: .fit,
                    iconName: isLiveStream ? "tv" : "film",
                    loadProfile: .standard
                )
                // CachedImage's empty state is a system-gray tile, which is light in the
                // light appearance; over the black surface it has to be the dark one.
                .environment(\.colorScheme, .dark)
                .opacity(0.5)
                .accessibilityHidden(true)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsOpeningArtwork)
        // Faded with the fullscreen layers (it sits with the picture, below them, so it
        // has a fade wrapper of its own): the docked card never shows it.
        return MiniMorphFullscreenFade(model: morph) { artwork }
        .onChange(of: isPresentationEstablished) { _, established in
            // A new load (zap, reload) starts without a picture again.
            if !established, !openingArtworkLatched { openingArtworkLatched = true }
        }
        .onChange(of: isCenterTransportLoading) { _, loading in
            if !loading {
                if openingArtworkLatched { openingArtworkLatched = false }
            } else if !isPresentationEstablished, !openingArtworkLatched {
                // A retry of a stream that never showed a picture: the established
                // flag does not change, so the handler above does not run.
                openingArtworkLatched = true
            }
        }
    }

    // MARK: - HUD pills

    /// Entrance and exit of the HUD pills: a fade with a few points of travel, relative
    /// to the pill. (`.move(edge:)` on their full-screen containers travelled the whole
    /// container height, so a pill was on screen only for the last few frames.) Reduce
    /// Motion drops the travel.
    private func hudPillTransition(offsetY: CGFloat) -> AnyTransition {
        hudReduceMotion ? .opacity : .opacity.combined(with: .offset(y: offsetY))
    }

    /// Entrance and exit of the notices in the AirPlay status slot (preparing pill, cast
    /// notice, "no devices" notice): a fade with a slight grow from the top edge.
    /// Reduce Motion drops the grow.
    private var hudNoticeTransition: AnyTransition {
        hudReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
    }

    /// Top inset of the aspect toast / 2x badge row, from the physical top edge (the
    /// overlay stack ignores the safe area). Chrome hidden: just below the safe area.
    /// Chrome visible: below the top row, which starts 16 pt under the safe area and is
    /// up to about 59 pt tall (two title lines plus the subtitle).
    private func hudTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        // The slot under the top row also holds the AirPlay preparing pill, the cast
        // notice and the "no AirPlay devices" notice. Those cannot step aside, so while
        // one is up this row keeps the compact position.
        let airPlayStatusUp = player.isAirPlayPreparing || castNoticeToastText != nil
            || showsAirPlayUnavailableNotice
        return safeAreaTop + (showControls && !airPlayStatusUp ? 80 : 12)
    }

    /// One persistent row for the 2x badge and the aspect toast: the transitions belong
    /// to the pills themselves, and the two stack instead of covering each other.
    private func hudTopPills(outerSafeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 8) {
            if isFastForwarding {
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
                .transition(hudPillTransition(offsetY: -8))
            }
            if let aspectToastText {
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
                .transition(hudPillTransition(offsetY: -8))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, hudTopPadding(safeAreaTop: outerSafeAreaInsets.top))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The chrome can come or go while a pill is up (a 2x hold outlives the
        // auto-hide): glide to the other slot instead of jumping.
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .allowsHitTesting(false)
        .zIndex(40)
    }

    // MARK: - Audio-only AirPlay

    /// Sound is on an AirPlay route while the picture stays on the phone. Only one
    /// AirPlay element is up at a time (the preparing pill and a cast notice win), and
    /// the pill steps aside for the HUD pills, which use the same part of the screen.
    private var showsAudioOnlyAirPlayPill: Bool {
        player.isAudioOnlyAirPlay && !isAudioOnlyAirPlayPillDismissed
            && !player.isAirPlayPreparing && castNoticeToastText == nil
            && aspectToastText == nil && !isFastForwarding
    }

    /// Shown whether or not the chrome is visible, above the UIKit touch overlay (the
    /// button has to take its own tap). With the chrome up it uses the slot of the
    /// AirPlay preparing pill, which replaces it after a tap on the button; with the
    /// chrome hidden it moves up to the edge of the picture.
    private func audioOnlyAirPlayOverlay(outerSafeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            if showsAudioOnlyAirPlayPill {
                audioOnlyAirPlayPill
                    .transition(hudPillTransition(offsetY: -8))
            }
            Spacer(minLength: 0)
        }
        .padding(
            .top,
            showControls
                ? max(64 + 44, outerSafeAreaInsets.top + 16 + 44 + 10)
                : outerSafeAreaInsets.top + 12
        )
        .padding(.leading, 16 + outerSafeAreaInsets.leading)
        .padding(.trailing, 16 + outerSafeAreaInsets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: showsAudioOnlyAirPlayPill)
        .animation(.easeInOut(duration: 0.2), value: showControls)
        // A dismissal covers one occurrence. These only clear a view flag; nothing
        // starts or ends from them.
        .onChange(of: player.airPlayRouteName) { _, _ in
            if isAudioOnlyAirPlayPillDismissed { isAudioOnlyAirPlayPillDismissed = false }
        }
        .onChange(of: endsAudioOnlyAirPlayOccurrence) { _, ended in
            if ended, isAudioOnlyAirPlayPillDismissed { isAudioOnlyAirPlayPillDismissed = false }
        }
        .zIndex(42)
    }

    /// The "sound there, picture here" state the user dismissed the pill for is over:
    /// the route left AirPlay, a cast was started, or the picture went to the receiver.
    /// Deliberately not `!player.isAudioOnlyAirPlay`: that flag also drops for the length
    /// of a slow channel change (the engine's backend is unknown while a stream opens),
    /// and the pill would come back on every zap of someone listening through a speaker.
    private var endsAudioOnlyAirPlayOccurrence: Bool {
        !player.isAirPlayRouteActive || player.isAirPlayPreparing
            || player.isCastPresenting || player.isAirPlayPlaybackActive
    }

    private var audioOnlyAirPlayPill: some View {
        // The route can be a speaker, which cannot show video: the button is offered
        // only for content the app can prepare for AirPlay, and the cast still starts
        // only from this tap.
        let canSendVideo = player.needsAirPlayPreparation
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "airplay.audio")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L("player.airplay.audio_only", player.airPlayRouteName ?? "AirPlay"))
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)
            // Informational: a tap here belongs to the video underneath.
            .allowsHitTesting(false)

            // One group, so the close button sits right next to the chip instead of
            // taking another full gap from the text on a narrow phone.
            HStack(spacing: 0) {
                if canSendVideo {
                    Button {
                        resetTimer()
                        prepareAndPresentAirPlay()
                    } label: {
                        // Neutral wording: the route can be a speaker, and "play video
                        // there" promised a picture on it.
                        Text(L("player.airplay.switch_to_airplay"))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.white.opacity(0.18), in: Capsule())
                            // The visible chip is small; the hit area is the full pill height.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // The route may be a speaker the user listens through on purpose
                // (the audio route cannot tell it from a TV): the pill must not sit
                // over the picture for the whole session then.
                Button {
                    // A pill that is already on its way out (the occurrence is over,
                    // the debounce has not dropped it yet) must not leave the flag
                    // set: nothing would clear it for the next occurrence.
                    if !endsAudioOnlyAirPlayOccurrence { isAudioOnlyAirPlayPillDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("common.close"))
            }
        }
        .foregroundStyle(.white)
        .frame(minHeight: 44)
        .padding(.leading, 16)
        // The close button brings its own 44 pt slot; 2 pt keeps its glyph inside the
        // capsule's round end.
        .padding(.trailing, 2)
        .background {
            Capsule().fill(.ultraThinMaterial).allowsHitTesting(false)
        }
        .overlay {
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .frame(maxWidth: 460)
    }

    // MARK: - Debug overlay

    private static let debugAirPlayLogTags = ["AirPlayCast", "AirPlayRemux"]
    private static let debugAirPlayLogTailCount = 4

    private var isDebugOverlayVisible: Bool { showControls && showDebugOverlay }

    /// The wrapper stays mounted so the controller hears every change of the panel's
    /// visibility (it only mirrors the statistics while the panel is on screen),
    /// including the last one.
    private func debugStatsOverlay(
        outerSafeAreaInsets: EdgeInsets, containerWidth: CGFloat
    ) -> some View {
        let horizontalInsets = outerSafeAreaInsets.leading + outerSafeAreaInsets.trailing
        let logWidth = max(min(containerWidth - horizontalInsets - 52, 300), 120)
        return ZStack {
            if isDebugOverlayVisible {
                // Debug panel top-trailing, volume slider'ın ÜSTÜNDE render edilir
                // (zIndex slider'dan yüksek). topChrome'un altında, sağda ses slider'ını
                // kaplar.
                VStack {
                    HStack {
                        Spacer()
                        debugStatsPanel(logWidth: logWidth)
                    }
                    .padding(.top, 78 + outerSafeAreaInsets.top)
                    .padding(.trailing, 16 + outerSafeAreaInsets.trailing)
                    Spacer()
                }
            }
        }
        // Only the copy button inside takes touches; see `debugStatsPanel`.
        .zIndex(33)
        .onAppear { player.setDiagnosticsVisible(isDebugOverlayVisible) }
        .onChange(of: isDebugOverlayVisible) { _, visible in
            player.setDiagnosticsVisible(visible)
        }
        .onDisappear { player.setDiagnosticsVisible(false) }
    }

    private func debugStatsPanel(logWidth: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
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
            // The panel covers the volume slider and the video: everything in it
            // except the copy button lets touches through.
            .allowsHitTesting(false)

            if !debugAirPlayLogTail.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(debugAirPlayLogTail.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(width: logWidth, alignment: .leading)
                .allowsHitTesting(false)
            }

            debugCopyAirPlayLogButton
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.5))
                .allowsHitTesting(false)
        }
        // Lives only while the panel is mounted.
        .task { await pollDebugAirPlayLog() }
    }

    private var debugCopyAirPlayLogButton: some View {
        Button {
            resetTimer()
            copyAirPlayLogToPasteboard()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: debugLogDidCopy ? "checkmark" : "doc.on.doc")
                Text(debugLogDidCopy ? L("player.stream_url.copied") : L("player.debug.copy_airplay_log"))
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.2), in: Capsule())
            // Small chip, taller hit area.
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pollDebugAirPlayLog() async {
        while !Task.isCancelled {
            let tail = Array(
                Log.recentLines(tags: Self.debugAirPlayLogTags)
                    .suffix(Self.debugAirPlayLogTailCount)
            )
            if tail != debugAirPlayLogTail { debugAirPlayLogTail = tail }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Copies the whole recent AirPlay log (not only the lines on screen). URLs in it
    /// were already redacted when the lines were written. With no line from this app
    /// session it falls back to the record saved when the last cast ended, the same
    /// text the row in the track settings sheet copies.
    private func copyAirPlayLogToPasteboard() {
        UIPasteboard.general.string = AirPlayLogExport.text()
        debugLogCopyToken &+= 1
        let token = debugLogCopyToken
        debugLogDidCopy = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard token == debugLogCopyToken else { return }
            debugLogDidCopy = false
        }
    }
}

/// The More menu's label style: the look of `.plain`, plus a report of the pressed
/// state. A menu gives no "opened" callback; its button being pressed is the one signal
/// that arrives for every opening.
private struct MoreMenuButtonStyle: ButtonStyle {
    let onPressedChange: (Bool) -> Void

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            // The dim `.plain` gives a pressed label, as measured on the other chrome
            // buttons.
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressedChange(pressed)
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

/// Canlı oynatıcıda oynatmayı kesmeden kanal listesi göstermek için kullanılan alt yatay panel.
/// Üstte yatay kategori çipleri, altta yatay kaydırılan kanal kartları bulunur.
struct LiveChannelSidePanel: View {
    let sections: [ChannelPanelSection]
    let currentItemId: String?
    let onSelectChannel: (String) -> Void

    @State private var selectedCategoryId: String

    /// Room kept free under the panel for the player's live button row, so previous /
    /// next and the panel's own toggle stay reachable while it is open. From the bottom
    /// safe-area edge (see `bottomTransportChrome`): 12 pt inset, the LIVE badge row
    /// (about 30 pt), 10 pt stack spacing, 44 pt buttons, 8 pt gap.
    static let transportRowClearance: CGFloat = 104

    /// Identity of the channel strip for one category. A distinct type on purpose:
    /// category ids and channel ids can be the same string (both are numeric on
    /// Xtream), and `scrollTo(channelId)` must never resolve to the strip itself.
    private struct StripIdentity: Hashable {
        let categoryId: String
    }

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
        .overlay(alignment: .top) { hairline }
        // The panel floats above the button row now, so it has a lower edge as well.
        .overlay(alignment: .bottom) { hairline }
        .contentShape(Rectangle())
        // Outside the content shape: touches in the gap reach the buttons underneath.
        .padding(.bottom, Self.transportRowClearance)
    }

    private var hairline: some View {
        Rectangle()
            .frame(height: 0.5)
            .foregroundStyle(Color.white.opacity(0.18))
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
            .onAppear { placeOnSelectedCategory(proxy: proxy) }
            .onChange(of: selectedCategoryId) { _, _ in
                scrollToSelectedCategory(proxy: proxy)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// First placement of the chip row: the panel opens with the selected category
    /// in view instead of sliding to it.
    private func placeOnSelectedCategory(proxy: ScrollViewProxy) {
        let categoryId = selectedCategoryId
        guard sections.contains(where: { $0.id == categoryId }) else { return }
        placeWithoutAnimation(proxy, on: categoryId)
    }

    private func scrollToSelectedCategory(proxy: ScrollViewProxy) {
        guard sections.contains(where: { $0.id == selectedCategoryId }) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(selectedCategoryId, anchor: .center)
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
            // Inside the `.id` below, so it runs again for every category's fresh strip.
            .onAppear { placeOnCurrent(proxy: proxy) }
            // A new scroll view per category: the offset of the previous category is not
            // carried over, and a category without the current channel starts at its
            // first one.
            .id(StripIdentity(categoryId: selectedCategoryId))
            .onChange(of: currentItemId) { _, _ in
                followCurrentChannel(proxy: proxy)
            }
        }
    }

    /// First placement of a strip, without animation: the panel opens on the current
    /// channel instead of opening at the first one and sliding there.
    private func placeOnCurrent(proxy: ScrollViewProxy) {
        guard let cid = currentItemId,
              activeItems.contains(where: { $0.id == cid }) else { return }
        placeWithoutAnimation(proxy, on: cid)
    }

    private func placeWithoutAnimation(_ proxy: ScrollViewProxy, on id: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(id, anchor: .center)
        }
        // A lazy stack may not be measured yet during its very first pass. Repeat on the
        // next main-queue turn: still unanimated, and a no-op when the first call landed.
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// The playing channel changed while the panel is open (previous / next, recall).
    private func followCurrentChannel(proxy: ScrollViewProxy) {
        guard let cid = currentItemId else { return }
        if activeItems.contains(where: { $0.id == cid }) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(cid, anchor: .center)
            }
            return
        }
        // It left the selected category: switch to its own. That category's strip is a
        // new scroll view and places itself on the channel when it appears.
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

// MARK: - Live channel banner

/// State of the live channel banner and of the "next programme" line. Kept out of
/// `PlayerViewImpl` (held there through `@State`, like `MiniCardDragModel`): showing or
/// hiding the banner re-renders only the banner and the programme strip, never the
/// player body.
final class PlayerChannelBannerModel: ObservableObject {
    /// How long the banner stays up after a channel change.
    static let visibleNanoseconds: UInt64 = 3_000_000_000

    @Published private(set) var isVisible = false
    /// Programme after the one on air. The published EPG snapshot carries only "now",
    /// so this is looked up on demand for the channel being watched.
    @Published private(set) var nextProgramme: EPGProgramme?

    private var hideTask: Task<Void, Never>?

    /// Shows the banner and (re)starts its timer. A burst of zaps keeps one banner up
    /// and hides it once, after the last change.
    func show(announcing channelName: String? = nil) {
        hideTask?.cancel()
        if !isVisible { isVisible = true }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: PlayerChannelBannerModel.visibleNanoseconds)
            guard !Task.isCancelled, let self else { return }
            if self.isVisible { self.isVisible = false }
        }
        // The banner is a picture-only cue; VoiceOver hears the channel name instead.
        if let channelName, !channelName.isEmpty, UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: channelName)
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        if isVisible { isVisible = false }
    }

    func setNextProgramme(_ programme: EPGProgramme?) {
        if nextProgramme != programme { nextProgramme = programme }
    }

    /// `nextProgramme` while it really follows `programme`. After a zap the previous
    /// channel's value is still stored until the new lookup returns; it must not be
    /// shown under the new channel.
    func next(after programme: EPGProgramme?) -> EPGProgramme? {
        guard let programme, let next = nextProgramme,
              next.channelKey == programme.channelKey,
              next.start > programme.start else { return nil }
        return next
    }

    /// Looks up the programme that follows `programme`, off the main thread, and
    /// clears the line when the guide has none.
    func loadNext(after programme: EPGProgramme?, playlistId: UUID,
                  in database: AppDatabase = .shared) async {
        guard let programme else {
            setNextProgramme(nil)
            return
        }
        let channelKey = programme.channelKey
        let start = programme.start
        let found = try? await database.read { db -> EPGProgramme? in
            try PlayerNextProgrammeQuery.fetch(
                db, playlistId: playlistId, channelKey: channelKey, after: start, now: Date()
            )
        }
        guard !Task.isCancelled else { return }
        setNextProgramme(found ?? nil)
    }
}

/// On-demand lookup of the programme after the one on air. `nonisolated`: runs inside
/// the database reader closure.
nonisolated enum PlayerNextProgrammeQuery {
    /// First programme of `channelKey` that starts after `currentStart` and has not
    /// ended at `now`: a range scan on the (playlistId, channelKey, startTs) primary
    /// key that reads one row. The `stopTs` bound skips short entries that overlapping
    /// guide data leaves behind the programme on air.
    static func fetch(_ db: Database, playlistId: UUID, channelKey: String,
                      after currentStart: Date, now: Date) throws -> EPGProgramme? {
        try EPGGuideProgrammeRecord.fetchOne(db, sql: """
            SELECT channelKey, startTs, stopTs, title FROM epgProgramme
            WHERE playlistId = ? AND channelKey = ? AND startTs > ? AND stopTs > ?
            ORDER BY startTs LIMIT 1
            """, arguments: [
                playlistId, channelKey,
                Int64(currentStart.timeIntervalSince1970), Int64(now.timeIntervalSince1970)
            ])?.programme
    }
}

/// Transient banner for a live channel change: logo, channel name and, when the guide
/// has them, the programme on air with its time range and the one after it. It shows
/// itself for a few seconds whenever the channel changes, whether or not the chrome is
/// up, so a zap from the lock screen or a headset says which channel is loading.
struct PlayerChannelBanner: View {
    @ObservedObject var model: PlayerChannelBannerModel
    /// Channel the chrome presents (during a zap burst: the one it has landed on).
    let channelId: String
    let title: String
    let artworkURL: URL?
    let programme: EPGProgramme?
    let playlistId: UUID
    /// Something else owns the corner (failure banner, channel panel): stay hidden.
    var isSuppressed: Bool = false
    /// The chrome's live button row is on screen. On a portrait phone the banner then
    /// sits above it; over it, the card would cover the previous-channel button.
    var clearsTransportRow: Bool = false
    var safeAreaInsets: EdgeInsets = EdgeInsets()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// A change of this value is a zap. Scoped by playlist: two playlists can number
    /// their channels alike.
    private var channelIdentity: String {
        "\(playlistId.uuidString)\u{1e}\(channelId)"
    }

    private var isShown: Bool { model.isVisible && !isSuppressed }

    /// In landscape (compact height) the row is far to the trailing side and the
    /// brightness capsule sits right above this corner, so the banner stays low there.
    private var bottomInset: CGFloat {
        clearsTransportRow && verticalSizeClass != .compact
            ? LiveChannelSidePanel.transportRowClearance
            : 20
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isShown {
                card
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .padding(.leading, 20 + safeAreaInsets.leading)
        .padding(.trailing, 20 + safeAreaInsets.trailing)
        .padding(.bottom, bottomInset + safeAreaInsets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(.easeInOut(duration: 0.22), value: isShown)
        // The chrome can come or go while the banner is up: glide to the other slot.
        .animation(.easeInOut(duration: 0.2), value: bottomInset)
        .accessibilityHidden(true)
        // Not fired for the channel the player opens with: the chrome is up then and
        // already names it.
        .onChange(of: channelIdentity) { _, _ in
            model.show(announcing: title)
        }
        .task(id: programme?.id) {
            await model.loadNext(after: programme, playlistId: playlistId)
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 10) {
            CachedImage(
                url: artworkURL,
                width: 44,
                height: 44,
                cornerRadius: 9,
                iconName: "tv",
                loadProfile: .standard
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let programme {
                    HStack(spacing: 6) {
                        Text(EPGTimeFormat.range(programme.start, programme.stop))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                            .layoutPriority(1)
                        Text(programme.title)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    if let next = model.next(after: programme) {
                        Text(PlayerProgrammeStrip.nextLine(next))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }
}

/// The chrome's programme strip, fed from the banner model: it gets the "next" line
/// from it and steps aside while the banner, which shows the same programme in the
/// same corner, is up.
struct PlayerLiveProgrammeStrip: View {
    @ObservedObject var model: PlayerChannelBannerModel
    let programme: EPGProgramme
    /// False while the banner is suppressed; the strip then stays.
    var yieldsToBanner: Bool = true
    /// Width of the progress capsule; see `PlayerProgrammeStrip.barWidth`.
    var barWidth: CGFloat = PlayerProgrammeStripLayout.defaultBarWidth

    var body: some View {
        let isHidden = yieldsToBanner && model.isVisible
        PlayerProgrammeStrip(
            programme: programme, next: model.next(after: programme), barWidth: barWidth
        )
            .opacity(isHidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.22), value: isHidden)
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
    /// Live content: its row records that the channel was watched, not a position.
    let isLive: Bool
}

/// When the player writes the watch-history row, kept free of view state so it can be
/// unit-tested.
nonisolated enum PlayerWatchHistoryPolicy {
    /// Periodic save while a film or episode plays. A crash or force-quit loses at most
    /// this much of the resume position.
    static let periodicIntervalSeconds: TimeInterval = 10
    /// A playhead move of at least this much between two clock ticks is a seek. Normal
    /// progress is a few hundred milliseconds per tick, also at 2x.
    static let seekJumpThresholdMs: Int64 = 3_000
    /// How long the playhead has to stay put after a jump before the position is saved.
    static let seekSettleSeconds: TimeInterval = 1

    /// False for the first tick of an item (`previousMs == nil`): there is nothing to
    /// compare it with, and a start position is not a seek.
    static func isSeekJump(previousMs: Int64?, currentMs: Int64) -> Bool {
        guard let previousMs else { return false }
        return abs(currentMs - previousMs) >= seekJumpThresholdMs
    }
}
