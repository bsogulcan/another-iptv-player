import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import os

struct TrackMenuOption: Identifiable, Hashable {
  let id: Int
  let title: String
  let detail: String?
  let langCode: String?
  /// mpv `track-list/N/external`: external file track added via `sub-add`.
  let isExternal: Bool
  /// Başlık gerçek metadata değil, index'ten türetilmiş ("Parça 2" gibi). Tercih olarak
  /// SAKLANMAMALI — bir sonraki videoda pozisyonu aynı olan alakasız parçayı seçtirir.
  let isSyntheticTitle: Bool

  init(id: Int, title: String, detail: String? = nil, langCode: String? = nil, isExternal: Bool = false, isSyntheticTitle: Bool = false) {
    self.id = id
    self.title = title
    self.detail = detail
    self.langCode = langCode
    self.isExternal = isExternal
    self.isSyntheticTitle = isSyntheticTitle
  }
}

enum VideoPlayerState: Int {
  case idle = 0
  case loading = 1
  case buffering = 2
  case playing = 3
  case paused = 4
  case stopped = 5
  case ended = 6
  case error = 7
}

/// The three aspect presentations the player cycles through. Named fixed ratios
/// (16:9/4:3/16:10) were removed: they only ever pillar/letter-boxed the source at
/// its natural ratio inside a forced frame — indistinguishable from Fit for most
/// content and misleading. Fit / Fill / Center covers the real intents (respect the
/// source, crop-to-fill the screen, or map 1:1) — same set AVPlayer/Infuse expose.
enum VideoAspectMode: String, CaseIterable {
  /// Aspect-fit: source shown at its natural ratio, letter/pillar-boxed to fit the screen.
  case fit
  /// Zoom-to-fill: source scaled to cover the whole screen at its natural ratio; overflow cropped.
  case fill
  /// 1:1 pixel mapping (downscaled only if it doesn't fit).
  case center

  var iconName: String {
    switch self {
    case .fit: return "rectangle.arrowtriangle.2.inward"
    case .fill: return "rectangle.arrowtriangle.2.outward"
    case .center: return "square.dashed"
    }
  }

  /// Localized name of the mode ("1:1" reads the same in every language).
  var title: String {
    switch self {
    case .fit: return L("player.aspect_fit")
    case .fill: return L("player.aspect_fill")
    case .center: return "1:1"
    }
  }

  var accessibilityLabel: String {
    "\(L("player.aspect.title")): \(title)"
  }
}

/// Budget for reloading a live stream that reached end-of-stream. A panel reset
/// or an "offline" clip ends the response cleanly, which FFmpeg's reconnect does
/// not cover; a few spaced reloads bring the channel back. The budget is bounded
/// so two devices sharing a one-connection account cannot kick each other
/// forever, and it is restored once a reload has given real playback.
struct LiveReloadBudget: Equatable {
  /// Wait before the first, second and third reload.
  static let delays: [TimeInterval] = [0.5, 2, 5]
  /// Established playback of at least this long counts as recovered.
  static let restoreAfterStableSeconds: TimeInterval = 60

  private(set) var attemptsUsed = 0

  /// Delay before the next reload, or nil when the budget is spent.
  /// `stablePlaybackSeconds`: how long playback had been established when the
  /// stream ended (0 when it never was).
  mutating func nextDelay(stablePlaybackSeconds: TimeInterval) -> TimeInterval? {
    if stablePlaybackSeconds >= Self.restoreAfterStableSeconds { attemptsUsed = 0 }
    guard attemptsUsed < Self.delays.count else { return nil }
    defer { attemptsUsed += 1 }
    return Self.delays[attemptsUsed]
  }

  mutating func reset() {
    attemptsUsed = 0
  }
}

/// Pure decisions of `VideoPlayerController`, kept free of player, session and
/// system state so they can be unit-tested (the controller has no seam for a fake
/// engine or a fake audio session).
nonisolated enum VideoPlayerControllerLogic {
  // MARK: Audio-only AirPlay ("sound on the TV, picture on the phone")

  /// How long the raw condition must hold before the published flag follows it.
  /// A zap clears the engine's backend flag for a moment and stopping a player
  /// flaps the route; neither may blink the hint.
  static let audioOnlyAirPlayDebounceSeconds: TimeInterval = 1.5

  /// An AirPlay output carries the sound of the FFmpeg engine, which cannot send
  /// video, and no cast engagement exists that would.
  static func isAudioOnlyAirPlay(
    routeIsAirPlay: Bool,
    castEngaged: Bool,
    ffmpegBackendActive: Bool
  ) -> Bool {
    routeIsAirPlay && !castEngaged && ffmpegBackendActive
  }

  nonisolated enum DebounceStep: Equatable {
    /// Nothing to do.
    case keep
    /// The raw value went back to the published one: drop the pending change.
    case cancelPending
    /// Publish at once, dropping any pending change.
    case commit(Bool)
    /// Publish after the debounce interval, if the raw value still holds then.
    case schedule(Bool)
  }

  /// Next step of the debounced flag. `pending` is the value a running debounce
  /// timer is waiting to publish (nil when none runs).
  static func audioOnlyAirPlayStep(
    published: Bool,
    pending: Bool?,
    raw: Bool,
    castEngaged: Bool
  ) -> DebounceStep {
    // A cast engagement replaces the state at once: its own "preparing" and
    // "playing via AirPlay" presentation takes over, with no overlap.
    if castEngaged {
      return published || pending != nil ? .commit(false) : .keep
    }
    if raw == published { return pending == nil ? .keep : .cancelPending }
    return pending == raw ? .keep : .schedule(raw)
  }

  // MARK: Native AirPlay continuation

  /// An in-place content change continues native AirPlay through the cast
  /// controller instead of rebuilding the engine's AVPlayer (which drops the TV
  /// out of playback between items). Only an explicit content change qualifies,
  /// and only while the video is on the receiver — or was, for this load, with
  /// the AirPlay route still selected (at a natural end the TV may have left
  /// external playback already).
  static func continuesNativeExternalPlayback(
    isNewContent: Bool,
    castEngaged: Bool,
    engineExternalPlaybackActive: Bool,
    loadWasExternal: Bool,
    airPlayRouteActive: Bool
  ) -> Bool {
    guard isNewContent, !castEngaged else { return false }
    return engineExternalPlaybackActive || (loadWasExternal && airPlayRouteActive)
  }

  // MARK: Idle timer

  /// The screen stays awake while something plays on it. Once the engine's own
  /// AVPlayer shows the video on the receiver the phone may auto-lock like in
  /// Apple's players. A remux cast is NOT native external playback: there the
  /// phone is the HTTP origin of the stream and stays awake.
  static func shouldDisableIdleTimer(isPlaying: Bool, isNativeExternalPlayback: Bool) -> Bool {
    isPlaying && !isNativeExternalPlayback
  }

  /// Is the video on the receiver, fetched by the receiver itself? Either the
  /// engine's own AVPlayer is in external playback, or a cast engagement shows an
  /// item it does not remux (a natively playable URL, the provider's HLS stream).
  /// A remux cast never counts: the receiver fetches its segments from this phone.
  static func isNativeExternalPlayback(
    castPresenting: Bool,
    castExternalPlaybackActive: Bool,
    castIsRemuxing: Bool,
    engineExternalPlaybackActive: Bool
  ) -> Bool {
    castPresenting
      ? castExternalPlaybackActive && !castIsRemuxing
      : engineExternalPlaybackActive
  }

  // MARK: Play on a failed engine

  /// A play request while the engine holds no player and reports a failure (the
  /// playback watchdog or an "unsupported" verdict retired the layer): the
  /// engine's own `play()` does nothing in that state, only a fresh load plays
  /// again. This is what makes the lock-screen play button work after such a
  /// failure, also while the failure message is not (or no longer) published.
  static func playShouldReload(engineHasLayer: Bool, engineHasFailure: Bool) -> Bool {
    !engineHasLayer && engineHasFailure
  }

  // MARK: Playback clock

  /// Whether `timeMs` / `position` are republished on this pass. A live stream
  /// without a duration shows no clock and no scrubber, so its ticks would only
  /// re-run every observing view for nothing; it is published when the state or
  /// the duration changes instead.
  static func publishesClock(
    isLive: Bool,
    durationMs: Int64,
    stateChanged: Bool,
    durationChanged: Bool
  ) -> Bool {
    !(isLive && durationMs <= 0) || stateChanged || durationChanged
  }

  // MARK: Playback speed

  static let supportedPlaybackSpeeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

  /// The speed a request becomes: live always plays at 1x (the source delivers
  /// at 1x, anything faster only drains the buffer), garbage becomes 1x, the
  /// rest is clamped to the supported range.
  static func sanitizedPlaybackSpeed(_ speed: Float, isLive: Bool) -> Float {
    guard !isLive, speed.isFinite, speed > 0 else { return 1 }
    let lowest = supportedPlaybackSpeeds.min() ?? 1
    let highest = supportedPlaybackSpeeds.max() ?? 1
    return min(max(speed, lowest), highest)
  }

  /// Rate for a momentary override (`setRate`, the hold-for-2x gesture) on the
  /// engine. The neutral rate 1 means "override over": playback returns to the
  /// chosen speed, never implicitly to 1x.
  static func engineRate(requested: Float, chosenSpeed: Float) -> Float {
    guard requested.isFinite, requested > 0 else { return chosenSpeed }
    return requested == 1 ? chosenSpeed : requested
  }

  // MARK: Sleep timer

  static let maximumSleepTimerMinutes = 24 * 60

  /// Seconds until the sleep timer fires; nil cancels (nil or a non-positive
  /// request).
  static func sleepTimerInterval(minutes: Int?) -> TimeInterval? {
    guard let minutes, minutes > 0 else { return nil }
    return TimeInterval(min(minutes, maximumSleepTimerMinutes)) * 60
  }

  // MARK: Paused resume after a cast

  /// How long after establishment a load that must come back paused is kept
  /// paused. `KSPlayerLayer` plays by itself once more when a start seek lands,
  /// which can be several seconds after the item became ready.
  static let pausedResumeEnforceSeconds: TimeInterval = 10

  nonisolated enum PausedResumeStep: Equatable {
    /// Not established yet: the load must autoplay or it never prepares.
    case wait
    /// Pause now.
    case pause
    /// Paused, still inside the window: keep watching.
    case hold
    /// Window over: the paused state is the player's own from here on.
    case finish
  }

  static func pausedResumeStep(
    isEstablished: Bool,
    pauseIssued: Bool,
    isPaused: Bool,
    secondsSinceEstablished: TimeInterval
  ) -> PausedResumeStep {
    guard isEstablished else { return .wait }
    // The first pause is unconditional: the layer was created with autoplay,
    // whatever the engine's paused flag says at this instant.
    guard pauseIssued else { return .pause }
    if secondsSinceEstablished >= pausedResumeEnforceSeconds { return .finish }
    return isPaused ? .hold : .pause
  }

  // MARK: Delayed retry after a rejected zap

  /// Wait before the one reload of a new-content load that was answered with
  /// HTTP 403 before anything played. A connection-limited panel answers so
  /// while it still counts the socket of the previous channel, which closes
  /// asynchronously; a second later that connection is gone.
  static let forbiddenRetryDelaySeconds: TimeInterval = 1

  nonisolated enum ZapRetryDecision: Equatable {
    /// Show the failure; nothing is scheduled.
    case none
    /// HTTP 403 before playback was established, whatever the content.
    case afterForbidden
    /// A live open that took the place of a running layer was rejected with an
    /// error the immediate silent retry does not handle.
    case afterReplacedLiveLayer
  }

  /// Decided once, when the failure of a new-content engine load appears. At
  /// most one delayed reload per zap: the caller disarms before it acts, and the
  /// reload itself is not a new-content load.
  /// - `retryAlreadyScheduled`: the post-cast retry already claimed this failure.
  /// - `castOwnsContent`: a cast engagement exists; the engine must stay closed.
  /// - `failureIsRecoverable`: timeout / host unreachable, which the immediate
  ///   silent retry handles; a dead channel must not get a third attempt.
  /// - `failureWantsDelayedRetry`: the engine's HTTP 403 before playback.
  /// - `replacedActiveLayer`: the load replaced a layer that was open and not
  ///   failed, so the previous socket was still closing when this one opened.
  static func zapRetryDecision(
    retryAlreadyScheduled: Bool,
    castOwnsContent: Bool,
    hadHealthyStretch: Bool,
    failureIsRecoverable: Bool,
    hasLoadRequest: Bool,
    failureWantsDelayedRetry: Bool,
    isLiveStream: Bool,
    replacedActiveLayer: Bool
  ) -> ZapRetryDecision {
    guard !retryAlreadyScheduled, !castOwnsContent, !hadHealthyStretch,
          !failureIsRecoverable, hasLoadRequest
    else { return .none }
    if failureWantsDelayedRetry { return .afterForbidden }
    return isLiveStream && replacedActiveLayer ? .afterReplacedLiveLayer : .none
  }

  // MARK: Skips while a cast presents

  /// A seek sent to the receiver is trusted as "still on its way" for this long;
  /// after that the reported time is the base again, whatever it says (a seek
  /// that never landed must not pin every later skip to its target).
  static let castSeekTargetMaxAgeSeconds: TimeInterval = 5
  /// The reported time counts as "the seek has landed" within this distance of
  /// the target. Must stay above the 1 s tolerance of `AirPlayCastPlayer.seek`.
  static let castSeekLandedToleranceSeconds: TimeInterval = 2
  /// Fastest rate a cast plays at (the hold-for-2x gesture): how far past the
  /// target the receiver can have played since the seek.
  static let castSeekMaximumRate: Double = 2

  /// Position a skip is added to while a cast presents. The cast publishes a
  /// seek target at once, but the receiver keeps reporting its pre-seek time
  /// until the seek lands, and that tick overwrites the target. A skip tapped in
  /// between must add to the target, or two quick +15 taps land on +15.
  ///
  /// The reported time wins as soon as it is where the seek would have put it:
  /// between the target and as far as playback can have run since. Anything else
  /// is the receiver still on its way, and the target is the base.
  static func castSkipBase(
    reportedSeconds: TimeInterval,
    pendingTargetSeconds: TimeInterval?,
    secondsSinceTarget: TimeInterval
  ) -> TimeInterval {
    guard let target = pendingTargetSeconds, target.isFinite,
          secondsSinceTarget >= 0, secondsSinceTarget < castSeekTargetMaxAgeSeconds
    else { return reportedSeconds }
    guard reportedSeconds.isFinite else { return target }
    let landedFrom = target - castSeekLandedToleranceSeconds
    let landedTo = target + castSeekMaximumRate * secondsSinceTarget
      + castSeekLandedToleranceSeconds
    return (landedFrom...landedTo).contains(reportedSeconds) ? reportedSeconds : target
  }

  /// Absolute target of a relative skip while a cast presents, kept inside the
  /// content (an unknown duration only bounds it at 0).
  static func castSkipTarget(
    reportedSeconds: TimeInterval,
    pendingTargetSeconds: TimeInterval?,
    secondsSinceTarget: TimeInterval,
    delta: TimeInterval,
    durationSeconds: TimeInterval
  ) -> TimeInterval {
    let base = castSkipBase(
      reportedSeconds: reportedSeconds,
      pendingTargetSeconds: pendingTargetSeconds,
      secondsSinceTarget: secondsSinceTarget
    )
    let target = max((base.isFinite ? base : 0) + delta, 0)
    guard durationSeconds.isFinite, durationSeconds > 0 else { return target }
    return min(target, durationSeconds)
  }

  // MARK: AirPlay capability while a load opens

  /// The AirPlay button depends on codec facts the engine only has once the
  /// stream is open, and every load clears them. Between the load start and
  /// those facts the answer is "not known yet", not "no": the view keeps the
  /// button's slot instead of dropping it on every channel change. It ends with
  /// the first verdict (capable, or established without being capable) and with
  /// a failure that is shown; a failure hidden behind a delayed retry keeps it,
  /// the reload being on its way.
  static func isAirPlayCapabilityPending(
    capable: Bool,
    hasLoadRequest: Bool,
    isPlaybackEstablished: Bool,
    hasFailure: Bool,
    delayedRetryScheduled: Bool
  ) -> Bool {
    guard !capable, hasLoadRequest, !isPlaybackEstablished else { return false }
    return !hasFailure || delayedRetryScheduled
  }

  // MARK: Now Playing

  /// Everything in the Now Playing dictionary except elapsed time.
  nonisolated struct NowPlayingFields: Equatable {
    var title: String
    var artist: String
    var durationSeconds: Double
    /// 0 while not playing.
    var rate: Double
    var isLive: Bool
    /// Identity of the cached artwork object (nil = no artwork).
    var artworkID: ObjectIdentifier?
  }

  /// A push that is neither forced nor a play/pause change waits this long after
  /// the previous one, so a field that changes continuously (the growing
  /// duration of an event playlist) cannot push on every tick.
  static let nowPlayingMinimumInterval: TimeInterval = 0.8
  /// Elapsed time may differ this much from what the system extrapolates before
  /// it is pushed again (a stall, a seek that came from the player itself).
  static let nowPlayingDriftToleranceSeconds: TimeInterval = 2

  /// Elapsed time the system shows `secondsSincePush` after a push: it
  /// extrapolates from the pushed elapsed time and rate.
  static func extrapolatedElapsed(
    pushedElapsed: Double,
    pushedRate: Double,
    secondsSincePush: TimeInterval
  ) -> Double {
    pushedElapsed + pushedRate * max(secondsSincePush, 0)
  }

  /// Whether the dictionary is written on this pass. Elapsed time alone never
  /// causes a write while it follows the extrapolation.
  static func shouldPushNowPlaying(
    force: Bool,
    fields: NowPlayingFields,
    pushed: NowPlayingFields?,
    elapsed: Double,
    pushedElapsed: Double,
    secondsSincePush: TimeInterval
  ) -> Bool {
    guard let pushed else { return true }
    // Explicit pushes (seek, presentation, reinstall) and play/pause/speed
    // changes go out at once, with a fresh elapsed time.
    if force || fields.rate != pushed.rate { return true }
    guard secondsSincePush >= nowPlayingMinimumInterval else { return false }
    if fields != pushed { return true }
    let expected = extrapolatedElapsed(
      pushedElapsed: pushedElapsed, pushedRate: pushed.rate, secondsSincePush: secondsSincePush
    )
    return abs(elapsed - expected) > nowPlayingDriftToleranceSeconds
  }

  /// `KSPlayerLayer` wipes the shared dictionary (stop, deinit), fills a new one
  /// with the stream's metadata title, and overwrites the duration with its
  /// player's (not finite for a live item). Such a dictionary is no longer ours
  /// and must be written again. The duration may differ by rounding only.
  static func nowPlayingIsIntact(
    title: String?,
    artist: String?,
    durationSeconds: Double?,
    hasArtwork: Bool,
    expected: NowPlayingFields
  ) -> Bool {
    guard title == expected.title, artist == expected.artist,
          let durationSeconds, durationSeconds.isFinite,
          abs(durationSeconds - expected.durationSeconds) <= 0.5
    else { return false }
    return expected.artworkID == nil || hasArtwork
  }

  static let nowPlayingArtworkMaxDimension: CGFloat = 600

  /// Size the artwork is scaled down to (never up): MediaPlayer JPEG-encodes
  /// whatever the artwork handler returns, at its full size.
  static func nowPlayingArtworkSize(for size: CGSize) -> CGSize {
    let longest = max(size.width, size.height)
    guard longest.isFinite, longest > nowPlayingArtworkMaxDimension else { return size }
    let scale = nowPlayingArtworkMaxDimension / longest
    return CGSize(
      width: max((size.width * scale).rounded(), 1),
      height: max((size.height * scale).rounded(), 1)
    )
  }
}

/// `PlayerView` köprüsü: `KSPlayerEngine` + Now Playing / uzaktan kumanda.
final class VideoPlayerController: ObservableObject {
  /// SwiftUI may construct the incoming player before the outgoing player's
  /// `onDisappear` runs. Weak process-level registration lets the new controller
  /// see and claim an active AirPlay owner during that overlap window.
  private final class WeakControllerReference {
    weak var value: VideoPlayerController?
    init(_ value: VideoPlayerController) { self.value = value }
  }

  private static var activeControllerReferences: [WeakControllerReference] = []

  private static func register(_ controller: VideoPlayerController) {
    activeControllerReferences.removeAll { $0.value == nil }
    activeControllerReferences.append(WeakControllerReference(controller))
  }

  private static func unregister(_ controller: VideoPlayerController) {
    activeControllerReferences.removeAll { $0.value == nil || $0.value === controller }
  }

  private static func engagedCastController() -> CastController? {
    activeControllerReferences.removeAll { $0.value == nil }
    return activeControllerReferences.lazy
      .compactMap(\.value)
      .filter { !$0.isTornDown }
      .compactMap(\.castController)
      // Same rule as parking: only an engagement that holds (or held) a route is
      // worth sharing with the new screen. A route-less one would be inherited
      // as a ghost cast; its own screen disposes it on teardown.
      .first { $0.isEngaged && $0.hasRouteToPreserve }
  }

  private static func hasNativeExternalPlayback(excluding controller: VideoPlayerController) -> Bool {
    activeControllerReferences.removeAll { $0.value == nil }
    return activeControllerReferences.lazy
      .compactMap(\.value)
      .contains { other in
        other !== controller && !other.isTornDown
          && (other.engine.isExternalPlaybackActive
              || other.isAirPlayPlaybackActive)
      }
  }

  /// AVAudioSession is process-wide while VideoPlayerController is screen-scoped.
  /// A newly opened player claims a newer lease so an older controller's delayed
  /// teardown cannot deactivate the session underneath current playback.
  nonisolated private static let audioSessionLeaseLock = NSLock()
  nonisolated(unsafe) private static var audioSessionLeaseSerial: UInt64 = 0
  nonisolated(unsafe) private static var currentAudioSessionLease: UInt64?

  nonisolated private static func claimAudioSessionLease() -> (token: UInt64, previous: UInt64?) {
    audioSessionLeaseLock.lock()
    defer { audioSessionLeaseLock.unlock() }
    let previous = currentAudioSessionLease
    audioSessionLeaseSerial &+= 1
    currentAudioSessionLease = audioSessionLeaseSerial
    return (audioSessionLeaseSerial, previous)
  }

  nonisolated private static func rollBackAudioSessionLease(
    _ token: UInt64, previous: UInt64?
  ) {
    audioSessionLeaseLock.lock()
    defer { audioSessionLeaseLock.unlock() }
    if currentAudioSessionLease == token {
      currentAudioSessionLease = previous
    }
  }

  nonisolated private static func deactivateAudioSessionIfCurrent(_ token: UInt64) {
    audioSessionLeaseLock.lock()
    defer { audioSessionLeaseLock.unlock() }
    guard currentAudioSessionLease == token else { return }
    currentAudioSessionLease = nil
    try? AVAudioSession.sharedInstance().setActive(
      false, options: .notifyOthersOnDeactivation
    )
  }

  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "another-iptv-player",
    category: "VideoPlayer"
  )

  /// Intervals around the synchronous main-thread work of a load, a stop and the
  /// audio session activation, for Instruments (Points of Interest). Measurement
  /// only: whether a zap stalls the main thread was never measured on a device.
  nonisolated private static let signposter = OSSignposter(
    subsystem: Bundle.main.bundleIdentifier ?? "another-iptv-player",
    category: .pointsOfInterest
  )

  let engine: KSPlayerEngine
  /// AirPlay cast orkestratörü. Cast oturumu aktifken motor tamamen durdurulur;
  /// sunum ve transport bu nesne üzerinden akar.
  let castController: CastController?
  private let castOwnerToken = UUID()

  @Published var state: VideoPlayerState = .idle
  @Published var isPlaying: Bool = false
  @Published var isSeekable: Bool = false
  /// The engine has a seek the player has not confirmed yet (mirror of
  /// `KSPlayerEngine.isSeekInFlight`). False while a cast presents: the engine is
  /// stopped then and the cast reports its own buffering.
  @Published private(set) var isSeekInFlight: Bool = false
  /// Playback time for views that have to follow it (the scrubber). A plain `let`:
  /// a tick publishes on the clock, not on this object, so it no longer re-runs
  /// every view that observes the controller.
  let clock = PlaybackClock()
  /// Same values as the clock's, for readers that only need the current figure
  /// (history saves, resume checks, Now Playing). Not published on purpose.
  private(set) var position: Float = 0
  private(set) var durationMs: Int64 = 0
  private(set) var timeMs: Int64 = 0
  @Published var bufferingProgress: Float = 0
  @Published var rate: Float = 1.0
  @Published var videoWidth: Int = 0
  @Published var videoHeight: Int = 0
  @Published var streamFPS: Double = 0
  @Published var renderFPS: Double = 0
  @Published var videoBitrate: Double = 0
  @Published var droppedFrameCount: Int64 = 0
  @Published var delayedFrameCount: Int64 = 0
  @Published var cacheBufferingState: Double = 0
  @Published var cacheDurationSeconds: Double = 0
  @Published var cacheAheadSeconds: Double = 0
  @Published var avSyncSeconds: Double = 0
  @Published var networkSpeedBps: Double = 0
  @Published var hwdecCurrent: String = ""
  @Published var videoCodecName: String = ""
  @Published var seekLatencyMs: Int = -1
  /// Ağ / yükleme hatası (`KSPlayerEngine.playbackFailureMessage` yansıması).
  @Published var playbackFailureMessage: String?

  @Published var videoTracks: [TrackMenuOption] = []
  @Published var audioTracks: [TrackMenuOption] = []
  @Published var subtitleTracks: [TrackMenuOption] = [TrackMenuOption(id: -1, title: L("player.subtitle_off"))]
  @Published var currentVideoTrackId: Int = -1
  @Published var currentAudioTrackId: Int = -1
  @Published var currentSubtitleTrackId: Int = -1

  @Published var isPiPActive: Bool = false
  /// Yalnız KSPlayer/AVPlayer yolunda true: gerçek AirPlay external playback mümkün.
  @Published private(set) var isAirPlayVideoCapable: Bool = false
  /// A load is opening and the engine has no codec facts yet, so
  /// `isAirPlayVideoCapable` is "not known yet" rather than "no". The view keeps
  /// the AirPlay slot (dimmed, inert) instead of dropping it on every zap.
  @Published private(set) var isAirPlayCapabilityPending: Bool = false
  /// Debug overlay için: aktif ses codec'i (AirPlay adaylığı teşhisi).
  @Published private(set) var audioCodecName: String = ""
  /// FFmpeg yolunda: AirPlay butonu önce remux hazırlar, sonra sistem seçiciyi açar.
  @Published private(set) var needsAirPlayPreparation: Bool = false
  /// Cast oturumu sunumda: transport/scrubber cast'e akar, track menüsü pasif.
  @Published private(set) var isCastPresenting: Bool = false
  @Published private(set) var isLocalCastPlayback: Bool = false
  @Published private(set) var canSelectPlaybackTracks = true
  /// Video şu anda AirPlay hedefinde oynuyor (native external ya da remux cast);
  /// yerel yüzeyde "AirPlay'de oynatılıyor" placeholder'ı gösterilir.
  @Published private(set) var isAirPlayPlaybackActive: Bool = false
  /// The cast state machine is preparing (mirror of `CastController.isPreparing`):
  /// the chrome shows "Preparing AirPlay…" and offers Cancel.
  @Published private(set) var isAirPlayPreparing: Bool = false
  /// The preparation in progress is one the user started from the AirPlay button
  /// (mirror of `CastController.isPreparingFromButton`); false for a zap, a
  /// rebuild or a seek refresh of a running cast. Lets the chrome offer Cancel
  /// for the former even when an AirPlay route is already active.
  @Published private(set) var isAirPlayPreparingFromButton: Bool = false
  /// Why the last cast ended or could not start (mirror of
  /// `CastController.lastNotice`). Deliberately separate from
  /// `playbackFailureMessage`: that one is recomputed from the engine on every
  /// change and disables the transport, while a cast notice is a passing remark
  /// over playback that keeps working.
  @Published private(set) var castNotice: CastNotice?
  /// The audio-sync offset can take effect: FFmpeg engine, and no cast presenting.
  @Published private(set) var supportsAudioDelay: Bool = false
  /// Subtitle time offset in effect for the current content (stored per content).
  @Published private(set) var subtitleDelaySeconds: Double = 0
  /// An AirPlay output is the current audio route. Display state, refreshed by the
  /// route-change observer; nothing may start or end a cast from it.
  @Published private(set) var isAirPlayRouteActive: Bool = false
  /// `portName` of that output; nil while the route is not AirPlay.
  @Published private(set) var airPlayRouteName: String?
  /// "Sound on the TV, picture on the phone": an AirPlay route carries the audio
  /// of the FFmpeg engine and no cast engagement exists. Debounced. Display state
  /// only — a cast still starts from the user's tap and nowhere else.
  @Published private(set) var isAudioOnlyAirPlay: Bool = false
  /// Speed the user chose for non-live content. Kept across loads (a new episode
  /// keeps it); live plays at 1x and resets it.
  @Published private(set) var playbackSpeed: Float = 1.0
  /// When the sleep timer will pause playback; nil while no timer runs.
  @Published private(set) var sleepTimerEndsAt: Date?
  /// Mirror of the engine's flag; false while a cast presents (no local video).
  @Published private(set) var isPictureInPicturePossible: Bool = false
  @Published var aspectMode: VideoAspectMode = .fit
  /// Canlı yayın bayrağı: `setPlaybackPresentation` üzerinden güncellenir. PiP sample buffer
  /// delegesi skip kontrollerini gizlemek için bu değeri okur (mpv duration canlıda 0 dönmeyebilir).
  @Published var isLiveStream: Bool = false

  /// Screen brightness and system volume for the edge capsules. Plain `let`s, like
  /// `clock`: only the capsules (and the hidden `MPVolumeView` host) observe them, so
  /// a brightness or volume drag does not re-run the views that observe this object.
  let brightness = ScreenBrightnessModel()
  let systemVolume = SystemVolumeBridge()

  var hdrAvailable: Bool = false

  private struct PendingLoadRequest {
    let url: URL
    let startSeconds: TimeInterval?
    let isLiveStream: Bool
    let userAgent: String?
  }

  private var pendingLoadRequest: PendingLoadRequest?
  /// Son `play(url:)` isteği — AirPlay hazırlığı ve cast devri buradan içerik kurar.
  private var currentLoadRequest: PendingLoadRequest?
  private var isTornDown = false
  private var audioSessionActivated = false
  private var audioSessionLease: UInt64?
  private var playbackPresentation: PlaybackPresentation?
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
  private var seriesEpisodeOnPrevious: (() -> Void)?
  private var seriesEpisodeOnNext: (() -> Void)?
  /// Remote-command'lar yeniden kurulduğunda enable durumunu geri uygulamak için.
  private var episodeNavCanPrevious = false
  private var episodeNavCanNext = false
  private var episodeNavSwapSkip = true
  private var cancellables = Set<AnyCancellable>()

  private var nowPlayingArtwork: UIImage?
  /// One artwork object per fetched image. MediaPlayer reuses its encoded artwork
  /// only while this object's identity is unchanged; a new object per push made it
  /// JPEG-encode the image again every time.
  private var nowPlayingArtworkItem: MPMediaItemArtwork?
  private var artworkFetchTask: URLSessionDataTask?
  private var artworkFetchURL: URL?
  private var seekRequestStartedAt: Date?
  private var seekSourceTimeMs: Int64?
  /// Last measured seek latency (-1 = none); mirrored into `seekLatencyMs` only
  /// while the diagnostics are visible.
  private var measuredSeekLatencyMs = -1
  /// Presented position of the last sync pass. Internal readers use this instead
  /// of the published `timeMs`, which stands still on a live stream.
  private var currentTimeMs: Int64 = 0
  /// The debug statistics are mirrored into their @Published properties only
  /// while something shows them. Starts from the persisted overlay switch
  /// (PlayerView's `player.debugOverlayEnabled`) so the overlay is fed even
  /// before the view reports its visibility.
  private var diagnosticsVisible = UserDefaults.standard.bool(forKey: "player.debugOverlayEnabled")
  /// `play` sonrası ilk `isPlaybackEstablished` olayında kayıtlı parça tercihleri uygulanır.
  private var pendingPreferredTrackSelection = false
  /// Recoverable open failures (timeout / host unreachable) trigger one silent reload
  /// before the error is surfaced. Reset on every explicit `play(url:)`, and re-armed
  /// when a failure follows a long enough stretch of healthy playback, so every
  /// new incident gets its own silent retry instead of only the first one per item.
  private var didAutoRetryCurrentLoad = false

  /// Where a load came from; decides which retry budgets it resets or arms.
  private enum LoadOrigin {
    /// `play(url:)` from the view: new content.
    case newContent
    /// Explicit retry of the current request (Retry button, lock-screen play on a
    /// failed load, the engine asking for a reload).
    case retry
    /// CastController handed playback back to the engine.
    case castExit
    /// The one delayed reload after a failed cast-exit load.
    case postCastRetry
    /// Budgeted reload after a live stream reached end-of-stream.
    case liveReload
  }

  /// Healthy playback this long before a failure re-arms the silent auto-retry
  /// (see `healthyPlaybackSeconds`).
  private static let autoRetryRearmStableSeconds: TimeInterval = 30
  /// Wait before the single extra reload of a failed cast-exit load.
  private static let postCastRetryDelaySeconds: TimeInterval = 2

  /// When the engine last became established (nil while it is not): the clock for
  /// "playback has been stable for N seconds".
  private var playbackEstablishedAt: Date?
  /// Last sync pass that saw the engine established, not buffering and without a
  /// failure (nil until the first one of this load). The stall that precedes a
  /// watchdog failure does not move it.
  private var lastHealthyPlaybackAt: Date?
  /// Edge detector for the engine's failure message (`handleEngineChange` runs on
  /// every engine publish; budget decisions must be taken once per failure).
  private var lastEngineFailed = false
  /// Last presented position of the current content; where a retry resumes from.
  private var lastKnownPositionSeconds: TimeInterval = 0
  /// The current engine load reached native external playback (the engine's own
  /// AVPlayer on the receiver) and the AirPlay route has not been left since.
  /// The TV can drop external playback at a natural end, before the next item is
  /// requested; this is what still makes that request a continuation.
  private var loadWasExternal = false
  /// Direct playback must come back paused: the cast it resumes from was paused.
  /// The load still autoplays (`KSPlayerLayer` only prepares then) and is paused
  /// once established; see `applyPausedResumeIfNeeded`.
  private var pausedResumeArmed = false
  private var pausedResumeIssued = false
  private var pausedResumeEstablishedAt: Date?
  /// Debounce of `isAudioOnlyAirPlay`: the value the running timer will publish.
  private var audioOnlyAirPlayPending: Bool?
  private var audioOnlyAirPlayWork: DispatchWorkItem?
  private var sleepTimerWork: DispatchWorkItem?
  /// A sync pass is already queued for this main-queue turn.
  private var engineSyncScheduled = false
  /// The engine load in flight is the first one after a cast exit. The remux
  /// writer's source connection may still be closing when it opens, and
  /// connection-limited panels refuse the overlap with an error that is not in
  /// the recoverable set — so this load gets one extra reload, whatever the error.
  private var postCastRetryArmed = false
  private var postCastRetryWork: DispatchWorkItem?
  /// The engine load in flight is new content (a zap, an episode change, a first
  /// open) whose failure has not been seen yet. A rejection right after a zap
  /// gets one delayed reload through the post-cast retry machinery; see
  /// `VideoPlayerControllerLogic.zapRetryDecision`. Never set for a load a cast
  /// takes, and the reload it schedules does not arm it again.
  private var zapRetryArmed = false
  /// That load took the place of a layer that was open and had not failed, so
  /// the previous connection was still closing when the new one opened.
  private var zapReplacedActiveLayer = false
  /// Target and time of the last seek sent to a presenting cast that can seek.
  /// Skips that follow before the receiver has landed it add to this target
  /// instead of the receiver's pre-seek time (`VideoPlayerControllerLogic.castSkipBase`).
  private var castSeekTarget: (seconds: TimeInterval, issuedAt: Date)?
  private var liveReloadBudget = LiveReloadBudget()
  private var liveReloadWork: DispatchWorkItem?
  /// Playback was running (or starting) when an audio interruption began and this
  /// controller paused it; only then may the interruption's end resume it.
  private var resumeAfterInterruption = false

  /// Imported external subtitles (`ImportedSubtitleStore`): the content key comes from
  /// PlayerView; once playback is established the stored files are re-added to mpv.
  @Published private(set) var importedSubtitleFiles: [URL] = []
  private var importedSubtitleContentKey: String?

  init() {
    engine = KSPlayerEngine()
    castController = CastController.takeCrossScreenHandoff()
      ?? Self.engagedCastController()
      ?? CastController()
    refreshAirPlayRoute()
    wireEngine()
    wireCastController()
    Self.register(self)
    Self.sweepRemuxLeftoversOnce()
  }

  /// Segment directories of remux casts that an app kill left behind are swept
  /// when `LocalHTTPServer.shared` is first touched, which used to be the first
  /// AirPlay tap: until then gigabytes could sit in the temporary directory. The
  /// first player screen touches it instead, off the main thread (the sweep renames
  /// the leftovers and deletes them on a utility queue itself).
  private static var didSweepRemuxLeftovers = false

  private static func sweepRemuxLeftoversOnce() {
    guard !didSweepRemuxLeftovers else { return }
    didSweepRemuxLeftovers = true
    DispatchQueue.global(qos: .utility).async {
      _ = LocalHTTPServer.shared
    }
  }

  deinit {
    teardown()
  }

  /// Kenar tespiti için son görülen motor durumları (`changePublisher` toplu yayınlar).
  private var lastEngineIsReady = false
  private var lastEngineEstablished = false

  private func wireEngine() {
    // objectWillChange fires BEFORE the value changes and once per @Published
    // mutation; the pass is queued for a later main-queue turn, where the values
    // are current, and coalesced (see `scheduleEngineSync`).
    engine.changePublisher
      .sink { [weak self] in
        self?.scheduleEngineSync()
      }
      .store(in: &cancellables)

    // Both hooks hop to the next main turn: the engine raises them from inside its
    // own delegate callbacks / transport calls, and the answer is a fresh
    // `engine.load`, which must not re-enter the engine mid-call.
    engine.onLiveStreamEnded = { [weak self] in
      DispatchQueue.main.async { self?.handleLiveStreamEnded() }
    }
    engine.onReloadRequested = { [weak self] in
      DispatchQueue.main.async { self?.retryCurrentLoad() }
    }

    // Phone call / Siri / alarm: iOS deactivates our session and mpv's audio output
    // stops. Without this observer the player stays silent until fully reopened.
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] note in
        self?.handleAudioSessionInterruption(note)
      }
      .store(in: &cancellables)

    // Kulaklık çıkarma / Bluetooth kopması: platform geleneği (AVPlayer davranışı)
    // oynatmayı duraklatmaktır — aksi halde ses aniden hoparlörden devam eder.
    // Cast aktifken bu kural İŞLEMEZ: oynatma TV'de, AirPlay rota kararları
    // CastController'ındır (iki gözlemcinin çelişmesi saha bulgusuydu).
    NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] note in
        self?.handleAudioRouteChange(note)
      }
      .store(in: &cancellables)
  }

  private func handleAudioRouteChange(_ note: Notification) {
    // Display state first (AirPlay button tint, the "sound on the TV" hint). It
    // starts nothing: a cast still begins only from the user's tap.
    refreshAirPlayRoute()
    scheduleEngineSync()
    guard let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable,
          isPlaying,
          castController?.isEngaged != true
    else { return }
    engine.pause()
  }

  /// Reads the audio route once and publishes it. Called at init and on every
  /// route change, never per sync pass: `currentRoute` is a call into the audio
  /// server.
  private func refreshAirPlayRoute() {
    let output = AVAudioSession.sharedInstance().currentRoute.outputs
      .first { $0.portType == .airPlay }
    let active = output != nil
    if isAirPlayRouteActive != active { isAirPlayRouteActive = active }
    let name = output?.portName
    if airPlayRouteName != name { airPlayRouteName = name }
    // Once the route has left AirPlay there is nothing left to continue; a route
    // picked again later is a new choice, made for whatever plays then.
    if !active { loadWasExternal = false }
  }

  /// At most one sync pass per main-queue turn, however many publishes arrived.
  /// A single engine tick mutates four to five @Published values and each one
  /// used to run a full pass. `handleEngineChange` is level-driven with its own
  /// edge flags, so skipping intermediate values loses nothing.
  private func scheduleEngineSync() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.scheduleEngineSync() }
      return
    }
    guard !engineSyncScheduled else { return }
    engineSyncScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.engineSyncScheduled = false
      guard !self.isTornDown else { return }
      self.handleEngineChange()
    }
  }

  private func wireCastController() {
    guard let cast = castController else { return }
    cast.objectWillChange
      .sink { [weak self] in
        self?.scheduleEngineSync()
      }
      .store(in: &cancellables)
    cast.attachOwner(
      token: castOwnerToken,
      stopDirectPlayback: { [weak self] in
      guard let self else { return }
      // A cast engagement takes over the source: a reload still waiting for its
      // delay would open a second connection to the stream the remux reads.
      self.cancelScheduledReloads()
      self.postCastRetryArmed = false
      self.clearZapRetry()
      // The cast owns play/pause from here on.
      self.clearPausedResume()
      let stopInterval = Self.signposter.beginInterval("EngineStop")
      self.engine.stopPlayback()
      Self.signposter.endInterval("EngineStop", stopInterval)
      // KSPlayerLayer.deinit removeTarget(nil) ile TÜM remote-command hedeflerini
      // siler; kilit ekranı kontrolleri her layer yıkımından sonra yeniden kurulur.
      self.reinstallRemoteCommands()
      },
      resumeDirectPlayback: { [weak self] content, at in
      guard let self, !self.isTornDown else { return }
      self.startLoad(
        PendingLoadRequest(
          url: content.url,
          startSeconds: content.isLive || at < 2 ? nil : at,
          isLiveStream: content.isLive,
          userAgent: content.userAgent
        ),
        origin: .castExit,
        // A cast that was paused comes back paused on the phone.
        startPaused: content.startPaused
      )
      },
      onTimeTick: { [weak self] seconds in
        self?.engine.updateSubtitleCue(at: seconds)
      }
    )
    // A controller taken from the cross-screen handoff is already presenting;
    // publish that state immediately instead of waiting for its next time tick.
    handleEngineChange()
  }

  private func handleEngineChange() {
    let established = engine.isPlaybackEstablished
    if established != lastEngineEstablished {
      lastEngineEstablished = established
      playbackEstablishedAt = established ? Date() : nil
      lastHealthyPlaybackAt = nil
      if established, pendingPreferredTrackSelection {
        pendingPreferredTrackSelection = false
        // If an imported subtitle is selected, the global subtitle preference must not override it.
        let importedSelected = restoreImportedSubtitles()
        updateTracks(applyPreferences: true, skipSubtitleSelection: importedSelected)
      }
    }
    // The clock of the healthy stretch stops at the last pass that was playable:
    // the engine stays established through a stall and under a failure.
    if established, !engine.isBuffering, engine.playbackFailureMessage == nil {
      lastHealthyPlaybackAt = Date()
    }
    let ready = engine.isReady
    if ready != lastEngineIsReady {
      lastEngineIsReady = ready
      if ready { tryFlushPendingLoad() }
    }
    let castPresenting = castController?.isPresenting ?? false
    let castPreparing = castController?.isPreparing ?? false
    if isAirPlayPreparing != castPreparing { isAirPlayPreparing = castPreparing }
    let castPreparingFromButton = castController?.isPreparingFromButton ?? false
    if isAirPlayPreparingFromButton != castPreparingFromButton {
      isAirPlayPreparingFromButton = castPreparingFromButton
    }
    let notice = castController?.lastNotice
    if castNotice != notice { castNotice = notice }
    applyPausedResumeIfNeeded()
    // Remembered per load: see `loadWasExternal`.
    if !castPresenting, !loadWasExternal, engine.isExternalPlaybackActive {
      loadWasExternal = true
    }
    let engineFailed = !castPresenting && engine.playbackFailureMessage != nil
    let failureJustAppeared = engineFailed && !lastEngineFailed
    lastEngineFailed = engineFailed
    if failureJustAppeared {
      // Decided once, when the failure appears: the engine stays "established"
      // under a surfaced error, so a later check would reload behind an error the
      // user is already looking at. Measured up to the last healthy pass, not up
      // to now: the stall watchdog fails a load only after 20-30 s of waiting, which
      // would otherwise count as a healthy stretch by itself and re-arm the silent
      // retry on every stall of a half-dead source.
      let hadHealthyStretch = healthyPlaybackSeconds() >= Self.autoRetryRearmStableSeconds
      // First engine load after a cast exit: one more attempt after a short wait,
      // whatever the error domain (see `postCastRetryArmed`). A failure that comes
      // after a healthy stretch has nothing to do with the cast exit any more.
      if postCastRetryArmed {
        postCastRetryArmed = false
        if !hadHealthyStretch, currentLoadRequest != nil { schedulePostCastRetry() }
      }
      // New content the source rejected right after a zap: one delayed reload,
      // through the same machinery (hidden while it waits, cancelled by a newer
      // load, a cast start and teardown). Disarmed before anything is scheduled,
      // so a zap gets at most one. Recoverable failures are left to the immediate
      // silent retry below.
      if zapRetryArmed {
        let decision = VideoPlayerControllerLogic.zapRetryDecision(
          retryAlreadyScheduled: postCastRetryWork != nil,
          castOwnsContent: castController?.isEngaged ?? false,
          hadHealthyStretch: hadHealthyStretch,
          failureIsRecoverable: engine.playbackFailureIsRecoverable,
          hasLoadRequest: currentLoadRequest != nil,
          failureWantsDelayedRetry: engine.playbackFailureWantsDelayedRetry,
          isLiveStream: currentLoadRequest?.isLiveStream ?? false,
          replacedActiveLayer: zapReplacedActiveLayer
        )
        clearZapRetry()
        switch decision {
        case .none:
          break
        case .afterForbidden:
          schedulePostCastRetry(after: VideoPlayerControllerLogic.forbiddenRetryDelaySeconds)
        case .afterReplacedLiveLayer:
          schedulePostCastRetry()
        }
      }
      // A failure after a healthy stretch is a new incident and gets its own
      // silent retry.
      if didAutoRetryCurrentLoad, hadHealthyStretch {
        didAutoRetryCurrentLoad = false
      }
    }
    // Auto-retry once on a recoverable open failure (timeout / host unreachable)
    // before surfacing it — flaky IPTV panels frequently succeed on a second attempt.
    // A fresh KSPlayerLayer is built by tryFlushPendingLoad, which also reinstalls the
    // remote commands the previous layer's deinit wiped.
    if !castPresenting,
       postCastRetryWork == nil,
       engine.playbackFailureMessage != nil,
       engine.playbackFailureIsRecoverable,
       !didAutoRetryCurrentLoad,
       let request = currentLoadRequest {
      didAutoRetryCurrentLoad = true
      log.info("Auto-retrying playback after recoverable failure")
      // Resume from the current position, not the original startSeconds — otherwise a
      // mid-stream retry silently rewinds to wherever the user started this load from.
      let resumeAt: TimeInterval? = engine.isPlaybackEstablished && engine.position > 0.5
        ? engine.position
        : request.startSeconds
      pendingLoadRequest = PendingLoadRequest(
        url: request.url,
        startSeconds: resumeAt,
        isLiveStream: request.isLiveStream,
        userAgent: request.userAgent
      )
      tryFlushPendingLoad()
      return
    }
    // While the post-cast retry waits out its delay the failure stays unshown: the
    // reload is already on its way.
    let failure = castPresenting || postCastRetryWork != nil
      ? nil
      : engine.playbackFailureMessage
    if playbackFailureMessage != failure { playbackFailureMessage = failure }
    let ks = engine
    let audioDelaySupported = !castPresenting && ks.supportsAudioDelay
    if supportsAudioDelay != audioDelaySupported { supportsAudioDelay = audioDelaySupported }
    if isPiPActive != ks.isPiPActive { isPiPActive = ks.isPiPActive }
    let pipPossible = !castPresenting && ks.isPictureInPicturePossible
    if isPictureInPicturePossible != pipPossible { isPictureInPicturePossible = pipPossible }
    if audioCodecName != ks.audioCodecName { audioCodecName = ks.audioCodecName }
    // Remux adaylığı: FFmpeg yolu + uyumlu codec'ler.
    let remuxCandidate = ks.isFFmpegBackendActive
      && !ks.videoCodecName.isEmpty
      && RemuxHLSWriter.isCompatible(
        videoFourCC: ks.videoCodecName,
        audioFourCC: ks.audioCodecName.isEmpty ? nil : ks.audioCodecName
      )
    let capable = castPresenting || ks.isAirPlayVideoCapable || remuxCandidate
    if isAirPlayVideoCapable != capable { isAirPlayVideoCapable = capable }
    // The engine publishes "established" and its codec facts in the same
    // main-queue turn, so this coalesced pass sees both together.
    let capabilityPending = VideoPlayerControllerLogic.isAirPlayCapabilityPending(
      capable: capable,
      hasLoadRequest: currentLoadRequest != nil,
      isPlaybackEstablished: ks.isPlaybackEstablished,
      hasFailure: ks.playbackFailureMessage != nil,
      delayedRetryScheduled: postCastRetryWork != nil
    )
    if isAirPlayCapabilityPending != capabilityPending {
      isAirPlayCapabilityPending = capabilityPending
    }
    let needsPrep = !castPresenting && !ks.isAirPlayVideoCapable && remuxCandidate
    if needsAirPlayPreparation != needsPrep { needsAirPlayPreparation = needsPrep }
    let airPlayActive = castPresenting
      ? (castController?.isExternalPlaybackActive ?? false)
      : ks.isExternalPlaybackActive
    if isAirPlayPlaybackActive != airPlayActive { isAirPlayPlaybackActive = airPlayActive }
    if isCastPresenting != castPresenting {
      // The cast player starts every item at 1x; the engine's rate (a chosen
      // speed, a hold) does not carry over to it.
      if castPresenting, rate != 1 { rate = 1 }
      isCastPresenting = castPresenting
      // A seek target belongs to the cast presentation it was sent to.
      castSeekTarget = nil
    }
    let trackSelectionAvailable = !castPresenting || castController?.isRemuxing == true
    if canSelectPlaybackTracks != trackSelectionAvailable {
      canSelectPlaybackTracks = trackSelectionAvailable
    }
    let localCastPlayback = castController?.isContinuingLocally == true
    if isLocalCastPlayback != localCastPlayback {
      isLocalCastPlayback = localCastPlayback
      castController?.setLocalPlaybackSpeed(localCastPlayback ? playbackSpeed : 1)
      if localCastPlayback { rate = playbackSpeed }
      else if castPresenting { rate = 1 }
    }
    updateAudioOnlyAirPlay()
    syncFromEngine()
  }

  // MARK: - Audio-only AirPlay (display state)

  private var audioOnlyAirPlayRaw: Bool {
    VideoPlayerControllerLogic.isAudioOnlyAirPlay(
      routeIsAirPlay: isAirPlayRouteActive,
      castEngaged: castController?.isEngaged ?? false,
      ffmpegBackendActive: engine.isFFmpegBackendActive
    )
  }

  /// Follows the raw condition with a debounce. Publishes a flag and nothing
  /// else: no playback, cast or route action may ever hang off this.
  private func updateAudioOnlyAirPlay() {
    let step = VideoPlayerControllerLogic.audioOnlyAirPlayStep(
      published: isAudioOnlyAirPlay,
      pending: audioOnlyAirPlayPending,
      raw: audioOnlyAirPlayRaw,
      castEngaged: castController?.isEngaged ?? false
    )
    switch step {
    case .keep:
      break
    case .cancelPending:
      cancelAudioOnlyAirPlayDebounce()
    case .commit(let value):
      cancelAudioOnlyAirPlayDebounce()
      if isAudioOnlyAirPlay != value { isAudioOnlyAirPlay = value }
    case .schedule(let value):
      cancelAudioOnlyAirPlayDebounce()
      audioOnlyAirPlayPending = value
      let work = DispatchWorkItem { [weak self] in
        guard let self, !self.isTornDown else { return }
        self.audioOnlyAirPlayWork = nil
        self.audioOnlyAirPlayPending = nil
        // Checked again now: the condition can move without a sync pass.
        guard self.audioOnlyAirPlayRaw == value else { return }
        if self.isAudioOnlyAirPlay != value { self.isAudioOnlyAirPlay = value }
      }
      audioOnlyAirPlayWork = work
      DispatchQueue.main.asyncAfter(
        deadline: .now() + VideoPlayerControllerLogic.audioOnlyAirPlayDebounceSeconds,
        execute: work
      )
    }
  }

  private func cancelAudioOnlyAirPlayDebounce() {
    audioOnlyAirPlayWork?.cancel()
    audioOnlyAirPlayWork = nil
    audioOnlyAirPlayPending = nil
  }

  // MARK: - Paused resume after a cast

  /// Keeps a load that must come back paused (cast exit while paused) paused.
  /// The pause is issued at establishment and again whenever the layer starts
  /// playing by itself inside the window (its start seek autoplays when it lands).
  private func applyPausedResumeIfNeeded() {
    guard pausedResumeArmed, !castPresentingNow else { return }
    let established = engine.isPlaybackEstablished
    if established, pausedResumeEstablishedAt == nil { pausedResumeEstablishedAt = Date() }
    let step = VideoPlayerControllerLogic.pausedResumeStep(
      isEstablished: established,
      pauseIssued: pausedResumeIssued,
      isPaused: engine.isPaused,
      secondsSinceEstablished: pausedResumeEstablishedAt.map { Date().timeIntervalSince($0) } ?? 0
    )
    switch step {
    case .wait, .hold:
      break
    case .pause:
      pausedResumeIssued = true
      engine.pause()
    case .finish:
      clearPausedResume()
    }
  }

  private func clearPausedResume() {
    pausedResumeArmed = false
    pausedResumeIssued = false
    pausedResumeEstablishedAt = nil
  }

  private func handleAudioSessionInterruption(_ note: Notification) {
    guard let info = note.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    switch type {
    case .began:
      // The session is already deactivated by the system; clear the flag so the
      // next setupAudioSession() call is not short-circuited.
      audioSessionActivated = false
      // Remember that this handler stopped playback: `.shouldResume` only says the
      // system allows resuming, not that anything was playing. Set only when we
      // actually pause, so a second `.began` cannot overwrite it. A load still in
      // flight counts too — paused here, it must not start by itself mid-call.
      if isPlaying || isLoadInFlight {
        // A load that must come back paused (cast exit while paused) is not
        // playback to restore when the interruption ends.
        resumeAfterInterruption = !pausedResumeArmed
        routedPause()
      }
    case .ended:
      let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      setupAudioSession()
      let wasPlaying = resumeAfterInterruption
      resumeAfterInterruption = false
      // A video the user had paused before the call / Siri / alarm stays paused.
      if wasPlaying, options.contains(.shouldResume), !isTornDown {
        routedPlay()
      }
    @unknown default:
      break
    }
  }

  /// A load was started and nothing plays yet (engine opening, or a cast preparing
  /// un-paused): there is no playback to pause, but it is on its way.
  private var isLoadInFlight: Bool {
    if let cast = castController, cast.isPresenting {
      return !cast.isPlaybackEstablished && !cast.isPaused
    }
    return currentLoadRequest != nil && engine.isReady
      && !engine.isPlaybackEstablished && engine.playbackFailureMessage == nil
  }

  // MARK: - Transport routing (engine ↔ cast)

  /// Cast oturumu sunumdayken transport cast player'a, aksi halde motora gider.
  private var castPresentingNow: Bool { castController?.isPresenting ?? false }

  private func routedPlay() {
    // An explicit play ends the "come back paused" watch of a cast exit.
    clearPausedResume()
    if let cast = castController, cast.isPresenting {
      cast.play()
    } else if VideoPlayerControllerLogic.playShouldReload(
      engineHasLayer: engine.layer != nil,
      engineHasFailure: engine.playbackFailureMessage != nil
    ) {
      // Nothing is left to resume (see `playShouldReload`): same path as Retry.
      retryCurrentLoad()
    } else {
      engine.play()
    }
  }

  /// Pauses whatever presents (engine or cast). For callers that must never
  /// start playback, such as the player view's close exit: `togglePlayPause()`
  /// would resume a stream that is already paused.
  func pause() {
    // An explicit choice outranks whatever an interruption would restore.
    resumeAfterInterruption = false
    routedPause()
  }

  private func routedPause() {
    if let cast = castController, cast.isPresenting {
      cast.pause()
    } else {
      engine.pause()
    }
  }

  /// Mutlak (kaynak-zamanı) seek; uzaktan kumanda ve scrubber buradan geçer.
  func seekAbsolute(to seconds: TimeInterval) {
    markSeekRequestStart()
    if let cast = castController, cast.isPresenting {
      // Remembered for skips that follow before the receiver has landed this
      // seek (see `jump`). Only where the cast seeks: a refused seek (live remux)
      // must not leave a target behind.
      if cast.isSeekable, seconds.isFinite {
        castSeekTarget = (max(seconds, 0), Date())
      }
      cast.seek(toSource: seconds)
    } else {
      engine.seek(to: seconds)
    }
  }

  /// Sunum kaynağı: cast oturumu aktifken cast, değilse motor. Tek anahtar noktası —
  /// aşağıdaki tüm @Published eşlemeleri bu anlık görüntüden beslenir.
  private struct PresentationSnapshot {
    var position: TimeInterval
    var duration: TimeInterval
    var isPaused: Bool
    var isBuffering: Bool
    var isCompleted: Bool
    var isSeekable: Bool
    var isEstablished: Bool
    var isReady: Bool
    var failureMessage: String?
    var rate: Double
  }

  private func presentationSnapshot() -> PresentationSnapshot {
    if let cast = castController, cast.isPresenting {
      return PresentationSnapshot(
        position: cast.position,
        duration: cast.duration,
        isPaused: cast.isPaused,
        isBuffering: cast.isBuffering,
        isCompleted: cast.isCompleted,
        isSeekable: cast.isSeekable,
        isEstablished: cast.isPlaybackEstablished,
        isReady: true,
        failureMessage: nil,
        rate: Double(rate)
      )
    }
    return PresentationSnapshot(
      position: engine.position,
      duration: engine.duration,
      isPaused: engine.isPaused,
      isBuffering: engine.isBuffering,
      isCompleted: engine.isCompleted,
      isSeekable: engine.isSeekable,
      isEstablished: engine.isPlaybackEstablished,
      isReady: engine.isReady,
      // Hidden while the post-cast retry waits (same rule as `playbackFailureMessage`).
      failureMessage: postCastRetryWork != nil ? nil : engine.playbackFailureMessage,
      rate: engine.playbackRate
    )
  }

  /// Her @Published atama `objectWillChange` fire eder — Swift @Published eşitlik kontrolü yapmaz.
  /// Tüm atamaları `if current != new` ile koru; aksi halde saniyede 8×22 = ~176 gereksiz SwiftUI invalidation olur.
  private func syncFromEngine() {
    let snapshot = presentationSnapshot()
    let pos = snapshot.position
    let dur = snapshot.duration
    let posMs = Int64((pos.isFinite ? pos : 0) * 1000)
    let durMs = Int64((dur.isFinite ? dur : 0) * 1000)
    currentTimeMs = posMs

    let failed = !(snapshot.failureMessage ?? "").isEmpty
    let newState: VideoPlayerState
    if failed {
      newState = .error
    } else if !snapshot.isReady {
      newState = .idle
    } else if snapshot.isCompleted {
      newState = .ended
    } else if snapshot.isBuffering {
      newState = .buffering
    } else if snapshot.isPaused {
      newState = .paused
    } else {
      newState = .playing
    }

    // The clock of a live stream without a duration is on no screen (no scrubber,
    // no time label); republishing it on every tick only re-ran every view that
    // observes this object. It still goes out when the state or duration changes.
    let publishClock = VideoPlayerControllerLogic.publishesClock(
      isLive: currentContentIsLive,
      durationMs: durMs,
      stateChanged: state != newState,
      durationChanged: durationMs != durMs
    )
    // The plain values are written before the clock publishes, so whoever reacts to
    // the clock already reads the new figures from the controller.
    if publishClock, timeMs != posMs { timeMs = posMs }
    if durationMs != durMs { durationMs = durMs }
    clock.setDuration(durMs)
    // Survives the reset a failed reload performs on the engine, so a retry can
    // still resume where playback actually was.
    if snapshot.isEstablished, pos.isFinite, pos > 0 { lastKnownPositionSeconds = pos }

    let newPosition: Float
    if dur > 0, pos.isFinite {
      newPosition = Float(min(max(pos / dur, 0), 1))
    } else {
      newPosition = 0
    }
    if publishClock, position != newPosition { position = newPosition }
    if publishClock {
      clock.setPlayhead(timeMs: posMs, position: newPosition)
      // The buffered stretch of the scrubber. The engine's buffer says nothing
      // about a cast, whose picture is played by another player.
      clock.setCacheAhead(
        seconds: castPresentingNow ? 0 : engine.bufferTimelineEnd - (pos.isFinite ? pos : 0)
      )
    }

    let newIsPlaying =
      !failed && snapshot.isEstablished && snapshot.isReady
      && !snapshot.isPaused && !snapshot.isCompleted
    if isPlaying != newIsPlaying { isPlaying = newIsPlaying }

    let newRate = Float(snapshot.rate)
    if rate != newRate { rate = newRate }

    if isSeekable != snapshot.isSeekable { isSeekable = snapshot.isSeekable }
    // The engine is stopped while a cast presents; a flag it left behind says
    // nothing about the receiver.
    let seekInFlight = castPresentingNow ? false : engine.isSeekInFlight
    if isSeekInFlight != seekInFlight { isSeekInFlight = seekInFlight }

    let newBuf: Float = snapshot.isBuffering ? 0.35 : 0
    if bufferingProgress != newBuf { bufferingProgress = newBuf }

    if videoWidth != engine.videoDisplayWidth { videoWidth = engine.videoDisplayWidth }
    if videoHeight != engine.videoDisplayHeight { videoHeight = engine.videoDisplayHeight }
    // Backend and codec names stay unconditional: they are cheap, change once
    // per load and the codec gates the AirPlay button.
    let newHwdec = castPresentingNow ? "airplay-cast" : engine.hwdecCurrent
    if hwdecCurrent != newHwdec { hwdecCurrent = newHwdec }
    if videoCodecName != engine.videoCodecName { videoCodecName = engine.videoCodecName }

    updateSeekLatencyIfNeeded(currentTimeMs: posMs)
    if diagnosticsVisible { mirrorDiagnostics() }

    if state != newState { state = newState }

    applyIdleTimerPolicy()
    updateNowPlayingInfo()
  }

  /// Copies the debug statistics into their @Published properties. Several of
  /// them change on every tick (A/V sync, cache ahead), so this runs only while
  /// the overlay that shows them is visible; see `setDiagnosticsVisible`.
  private func mirrorDiagnostics() {
    if streamFPS != engine.streamFPS { streamFPS = engine.streamFPS }
    if renderFPS != engine.renderFPS { renderFPS = engine.renderFPS }
    if videoBitrate != engine.videoBitrate { videoBitrate = engine.videoBitrate }
    if droppedFrameCount != engine.droppedFrameCount {
      droppedFrameCount = engine.droppedFrameCount
    }
    if delayedFrameCount != engine.delayedFrameCount {
      delayedFrameCount = engine.delayedFrameCount
    }
    if cacheBufferingState != engine.cacheBufferingState {
      cacheBufferingState = engine.cacheBufferingState
    }
    if cacheDurationSeconds != engine.cacheDurationSeconds {
      cacheDurationSeconds = engine.cacheDurationSeconds
    }
    let newAhead = max(engine.bufferTimelineEnd - (Double(currentTimeMs) / 1000.0), 0)
    if cacheAheadSeconds != newAhead { cacheAheadSeconds = newAhead }
    if avSyncSeconds != engine.avSyncSeconds { avSyncSeconds = engine.avSyncSeconds }
    if networkSpeedBps != engine.networkSpeedBps { networkSpeedBps = engine.networkSpeedBps }
    if seekLatencyMs != measuredSeekLatencyMs { seekLatencyMs = measuredSeekLatencyMs }
  }

  /// The debug overlay reports whether it is on screen. While it is not, the
  /// statistics above keep their last values and publish nothing.
  func setDiagnosticsVisible(_ visible: Bool) {
    guard diagnosticsVisible != visible else { return }
    diagnosticsVisible = visible
    if visible, !isTornDown { mirrorDiagnostics() }
  }

  /// Live flag of the content being presented. The load request knows it first;
  /// the presentation flag covers a controller that has no request of its own.
  private var currentContentIsLive: Bool {
    currentLoadRequest?.isLiveStream ?? isLiveStream
  }

  /// Oynatma sırasında ekranın otomatik kapanmasını engeller; duraklatınca veya ekrandan çıkınca normale döner.
  private func applyIdleTimerPolicy() {
    // The phone may lock once the receiver fetches the video by itself: the
    // engine's own AVPlayer in external playback, or a cast item that is not
    // remuxed. A remux cast keeps the screen awake: the phone is its HTTP origin,
    // and it has not been shown to survive a locked phone.
    let disableIdleTimer = VideoPlayerControllerLogic.shouldDisableIdleTimer(
      isPlaying: isPlaying,
      isNativeExternalPlayback: VideoPlayerControllerLogic.isNativeExternalPlayback(
        castPresenting: castPresentingNow,
        castExternalPlaybackActive: castController?.isExternalPlaybackActive ?? false,
        castIsRemuxing: castController?.isRemuxing ?? false,
        engineExternalPlaybackActive: engine.isExternalPlaybackActive
      )
    )
    // Level-triggered on every pass, because KSPlayerLayer's play/pause/stop write
    // the same flag; but the setter is only called for an actual change.
    let apply = {
      if UIApplication.shared.isIdleTimerDisabled != disableIdleTimer {
        UIApplication.shared.isIdleTimerDisabled = disableIdleTimer
      }
    }
    if Thread.isMainThread {
      apply()
    } else {
      DispatchQueue.main.async(execute: apply)
    }
  }

  private func tryFlushPendingLoad() {
    guard let request = pendingLoadRequest else { return }
    pendingLoadRequest = nil
    log.info("Loading URL into engine: \(Log.redact(request.url), privacy: .public)")
    // The load releases the previous layer and builds the new one synchronously.
    let loadInterval = Self.signposter.beginInterval("EngineLoad")
    engine.load(
      request.url,
      play: true,
      startSeconds: request.startSeconds,
      liveLowLatency: request.isLiveStream,
      userAgent: request.userAgent
    )
    Self.signposter.endInterval("EngineLoad", loadInterval)
    // A new layer starts at 1x while the engine still reports the previous
    // layer's rate: the chosen speed is applied again on every load (new content,
    // silent retry, cast hand-back alike). Live plays at 1x.
    engine.setPlaybackRate(Double(
      VideoPlayerControllerLogic.sanitizedPlaybackSpeed(
        playbackSpeed, isLive: request.isLiveStream
      )
    ))
    // Per-load state of the edge detectors below.
    loadWasExternal = false
    pausedResumeIssued = false
    pausedResumeEstablishedAt = nil
    // Yeni KSPlayerLayer kurulurken eskisinin deinit'i tüm remote-command
    // hedeflerini sildi; kilit ekranı kontrollerini geri kur.
    reinstallRemoteCommands()
    // KSPlayerLayer registers its own interruption observer in init: it pauses on
    // `.began` and plays on `.ended` + shouldResume with no memory of whether
    // anything was playing, so a video the user had paused started by itself after
    // a call. `handleAudioSessionInterruption` is the single owner of that policy;
    // the library's registration (selector-based, made synchronously in init) is
    // removed from the outside — no fork needed. If a future KSPlayer registers
    // differently this becomes a silent no-op.
    if let layer = engine.layer {
      NotificationCenter.default.removeObserver(
        layer, name: AVAudioSession.interruptionNotification, object: nil
      )
    }
    // The load cleared the engine's failure message and established flag; the edge
    // detectors must not carry the previous load's state into this one.
    lastEngineFailed = false
    playbackEstablishedAt = nil
    lastHealthyPlaybackAt = nil
    let saved = SubtitleAppearancePersistence.load()
    engine.applySubtitleAppearanceFromSettings(saved)
    // The time offset belongs to the content, not to the (global) style: a value
    // tuned for one badly timed file used to shift every later title.
    applyStoredSubtitleDelay()
    engine.setAudioDelay(seconds: AudioDelayPersistence.load())
  }

  /// Applies the subtitle time offset stored for the current content (0 when none)
  /// and publishes it. Runs on every load, on the engine and on the cast path alike
  /// (cast ticks drive the same subtitle model).
  private func applyStoredSubtitleDelay() {
    let stored = importedSubtitleContentKey.map { SubtitleDelayStore.delaySeconds(for: $0) } ?? 0
    engine.setSubDelay(seconds: stored)
    if subtitleDelaySeconds != stored { subtitleDelaySeconds = stored }
  }

  func setupAudioSession() {
    if audioSessionActivated { return }
    let lease = Self.claimAudioSessionLease()
    do {
      let activateInterval = Self.signposter.beginInterval("AudioSessionActivate")
      // Ends the interval on the throwing exits as well.
      defer { Self.signposter.endInterval("AudioSessionActivate", activateInterval) }
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
      try session.setActive(true, options: [])
      audioSessionActivated = true
      audioSessionLease = lease.token
    } catch {
      Self.rollBackAudioSessionLease(lease.token, previous: lease.previous)
      log.error("AVAudioSession: \(error.localizedDescription)")
    }
  }

  func play(
    url: URL,
    startSeconds: TimeInterval? = nil,
    isLiveStream: Bool = false,
    userAgent: String? = nil
  ) {
    startLoad(
      PendingLoadRequest(
        url: url,
        startSeconds: startSeconds,
        isLiveStream: isLiveStream,
        userAgent: userAgent
      ),
      origin: .newContent
    )
  }

  /// Single entry for every load of a request — new content, a retry, the resume
  /// after a cast, a budgeted reload. They all take the same cast gating; `origin`
  /// only decides which retry budgets are reset or armed. `startPaused`: the load
  /// must come back paused (a cast exit while paused).
  private func startLoad(
    _ request: PendingLoadRequest, origin: LoadOrigin, startPaused: Bool = false
  ) {
    guard !isTornDown else { return }
    // A newer load supersedes any reload still waiting for its delay.
    cancelScheduledReloads()
    // It also supersedes a cast exit whose resume is still waiting for the remux
    // writer to close: that resume would otherwise fire later and load stale
    // content over this one. (The resume itself arrives here with nothing left to
    // cancel.) This load then opens while the writer's connection may still be
    // closing, exactly like a cast-exit load, so it gets the same extra reload.
    let supersededCastResume = castController?.cancelPendingResume() ?? false
    didAutoRetryCurrentLoad = false
    postCastRetryArmed = origin == .castExit || supersededCastResume
    // Armed below, and only when the engine takes this load.
    clearZapRetry()
    // A seek target belongs to the content it was sent for.
    castSeekTarget = nil
    if origin != .liveReload { liveReloadBudget.reset() }
    if origin == .newContent { lastKnownPositionSeconds = request.startSeconds ?? 0 }
    // The one reload of a failed cast-exit load inherits that load's paused
    // state; every other load decides it anew.
    if origin != .postCastRetry {
      clearPausedResume()
      pausedResumeArmed = startPaused
    }
    // The start position needs no help from here: the engine applies
    // `startSeconds` on both backends (FFmpeg at open, AVPlayer with one seek
    // once the item is seekable).
    currentLoadRequest = request
    // Live always plays at 1x and forgets the chosen speed.
    let speed = VideoPlayerControllerLogic.sanitizedPlaybackSpeed(
      playbackSpeed, isLive: request.isLiveStream
    )
    if playbackSpeed != speed { playbackSpeed = speed }
    applyPlaybackRateCommandEnablement()
    let url = request.url
    let startSeconds = request.startSeconds
    let isLiveStream = request.isLiveStream
    let userAgent = request.userAgent
    // Cast oturumu aktifken (zap / auto-next) içerik cast hattından akar; motor
    // AÇILMAZ — panele ikinci bağlantı açmak bağlantı-limitli panellerde devir
    // hatalarının kök nedeniydi. Native-external oynatma sırasında FFmpeg'lik
    // içeriğe zap da doğrudan remux devriyle sürer. Üçüncü yol: önceki oynatıcı
    // ekranı cast ortasında kapandıysa (film kapat → canlı aç) CastController'ın
    // kendisi yeni ekrana devredilir; `cast.isEngaged` bu yolu doğrudan seçer.
    if let cast = castController {
      // "A plain AVPlayer can play this", not the engine's open order: audio-only
      // files open on FFmpeg first but must still be cast natively (the remux
      // refuses a source without video).
      let nativeNext = KSPlayerEngine.isAVFoundationPlayable(url)
      let overlapsNativeExternalPlayback =
        !cast.isEngaged && Self.hasNativeExternalPlayback(excluding: self)
      if overlapsNativeExternalPlayback {
        CastController.claimNativeExternalPlaybackFromActiveController()
      }
      let hasNativeExternalContinuation = overlapsNativeExternalPlayback
        || (!cast.isEngaged && CastController.takeNativeExternalPlaybackContinuation())
      // In-place content change during native AirPlay (next episode, zap, queue
      // pick). Loading it on the engine would build a new KSPlayerLayer and with
      // it a new AVPlayer: the TV drops out of playback between items and the
      // next one can come back with sound on the TV and the picture on the phone.
      // Instead the item is handed to the cast controller's long-lived player
      // once; every later change is an item swap there. Only an explicit content
      // change gets here (never a retry or a reload), on a route the user chose.
      // The same holds for the remux crossover below: a retry or a timer-driven
      // reload must never start a cast, it reloads on the engine.
      let engineExternal = engine.isExternalPlaybackActive
      // Read from the session at this moment, and only when the answer matters:
      // the published mirror lags a route change by one main-queue hop.
      let routeStillAirPlay = origin == .newContent && !cast.isEngaged && !engineExternal
        && loadWasExternal && cast.isAirPlayRouteActive
      let continuesInPlace = VideoPlayerControllerLogic.continuesNativeExternalPlayback(
        isNewContent: origin == .newContent,
        castEngaged: cast.isEngaged,
        engineExternalPlaybackActive: engineExternal,
        loadWasExternal: loadWasExternal,
        airPlayRouteActive: routeStillAirPlay
      )
      let continueNativeExternalPlayback =
        hasNativeExternalContinuation || (continuesInPlace && nativeNext)
      // An FFmpeg-only next item keeps its existing way in (`startRemuxCast`,
      // with its local preflight); the continuation only widens when it applies.
      let crossoverToRemux =
        origin == .newContent
        && (engineExternal || continuesInPlace)
        && !nativeNext
      if cast.isEngaged || crossoverToRemux || continueNativeExternalPlayback {
        if origin == .newContent {
          // The retained menu belongs to the previous source. Never apply its
          // stream indexes to a new channel or episode.
          videoTracks = []
          audioTracks = []
          subtitleTracks = [TrackMenuOption(id: -1, title: L("player.subtitle_off"))]
          currentAudioTrackId = -1
          currentSubtitleTrackId = -1
        }
        pendingPreferredTrackSelection = false
        setupAudioSession()
        // Motor durdurulmuş; altyazı modeli önceki içeriğin seçimini taşıyor.
        // Cast tikleri cue araması yapmaya devam ettiğinden yanlış içerik altyazısı
        // basılmasın diye seçim temizlenir.
        engine.selectSubtitleTrack(id: -1)
        // The engine is not loaded on this path, but cast ticks still drive its
        // subtitle model: the new content's own time offset applies here too.
        applyStoredSubtitleDelay()
        let content = CastController.Content(
          url: url,
          isLive: isLiveStream,
          userAgent: userAgent,
          startAt: isLiveStream ? 0 : (startSeconds ?? 0),
          knownDuration: 0,
          nativelyPlayable: nativeNext
        )
        let takenByCast: Bool
        if cast.isEngaged {
          // false: the engagement never had a route and was ended instead of
          // carrying the new content — the engine loads it below. That load is
          // the first one after a cast exit, with the writer's connection still
          // closing, so it gets the same extra reload as a resume.
          takenByCast = cast.playContent(content)
          if !takenByCast { postCastRetryArmed = true }
        } else if continueNativeExternalPlayback {
          cast.continueNativeExternalPlayback(with: content)
          takenByCast = true
        } else {
          // false: the preflight refused the cast and left the engine alone, but
          // the engine is still on the previous content — load the new one below.
          // A content change, not the AirPlay button: the preparing pill must not
          // offer Cancel for it on an active route.
          takenByCast = cast.startRemuxCast(content: content, fromButton: false) { _ in }
        }
        if takenByCast { return }
      }
    }
    pendingPreferredTrackSelection = true
    setupAudioSession()
    // Only a content change arms the delayed retry: the reload it schedules
    // arrives as `.postCastRetry`, so there is one per zap. Read before the load,
    // which replaces the engine's layer. A layer that already failed has closed
    // its connection and is not an overlap.
    zapRetryArmed = origin == .newContent
    zapReplacedActiveLayer = zapRetryArmed
      && engine.layer != nil && engine.playbackFailureMessage == nil
    pendingLoadRequest = currentLoadRequest
    tryFlushPendingLoad()
  }

  // MARK: - Retry / reload

  /// Loads the current request again: the way out of a failed playback (Retry in
  /// the UI, lock-screen play on a failed load, the engine asking for a reload of
  /// an ended stream). Goes through `startLoad`, so the silent auto-retry is
  /// re-armed, track preferences are re-applied and the cast gating holds.
  func retryCurrentLoad() {
    guard !isTornDown, let request = currentLoadRequest else { return }
    let start = Self.retryStartSeconds(
      requested: request.startSeconds,
      isLive: request.isLiveStream,
      lastKnownPosition: lastKnownPositionSeconds,
      knownDuration: Double(durationMs) / 1000.0
    )
    log.info("Retrying current load")
    startLoad(
      PendingLoadRequest(
        url: request.url,
        startSeconds: start,
        isLiveStream: request.isLiveStream,
        userAgent: request.userAgent
      ),
      origin: .retry
    )
  }

  /// Where a retry starts. Live has no position. Otherwise the last known position
  /// once playback was more than 5 s in — except at the very end of a known
  /// duration, where resuming would only end again — else the original request.
  static func retryStartSeconds(
    requested: TimeInterval?,
    isLive: Bool,
    lastKnownPosition: TimeInterval,
    knownDuration: TimeInterval
  ) -> TimeInterval? {
    guard !isLive else { return requested }
    guard lastKnownPosition.isFinite, lastKnownPosition > 5 else { return requested }
    if knownDuration > 0, lastKnownPosition > knownDuration - 5 { return requested }
    return lastKnownPosition
  }

  /// How long the engine has been established (0 when it is not).
  private func stablePlaybackSeconds() -> TimeInterval {
    playbackEstablishedAt.map { max(Date().timeIntervalSince($0), 0) } ?? 0
  }

  /// From established to the last healthy sync pass of this load (0 when there was
  /// none): `stablePlaybackSeconds` without the stall that led to a failure.
  private func healthyPlaybackSeconds() -> TimeInterval {
    guard let start = playbackEstablishedAt, let last = lastHealthyPlaybackAt else { return 0 }
    return max(last.timeIntervalSince(start), 0)
  }

  private func cancelScheduledReloads() {
    postCastRetryWork?.cancel()
    postCastRetryWork = nil
    liveReloadWork?.cancel()
    liveReloadWork = nil
  }

  private func clearZapRetry() {
    zapRetryArmed = false
    zapReplacedActiveLayer = false
  }

  /// One reload, shortly after the first engine load following a cast exit
  /// failed. No drain-waiting and no deferred resume: the resume itself stays
  /// immediate; only its failure is given a second chance. Cancelled by a newer
  /// load, by teardown and by a new cast engagement (`cancelScheduledReloads`).
  /// A new-content load that was rejected right after a zap takes the same one
  /// reload, with its own `delay` (see `zapRetryDecision`).
  private func schedulePostCastRetry(
    after delay: TimeInterval = VideoPlayerController.postCastRetryDelaySeconds
  ) {
    postCastRetryWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.isTornDown else { return }
      self.postCastRetryWork = nil
      // The failure must still stand: a load that only timed out keeps opening and
      // may have become ready during the wait; reloading would tear that down.
      guard self.castController?.isEngaged != true,
            self.engine.playbackFailureMessage != nil,
            let request = self.currentLoadRequest
      else {
        self.handleEngineChange()
        return
      }
      self.log.info("Reloading after a failed load (delayed one-shot retry)")
      self.startLoad(request, origin: .postCastRetry)
    }
    postCastRetryWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  /// The engine reports that a live stream reached end-of-stream (it does not mark
  /// the stream completed by itself). Reload the same request within the budget;
  /// when the budget is spent, let the engine present the stream as ended.
  private func handleLiveStreamEnded() {
    guard !isTornDown else { return }
    // Never while a cast owns the source: the engine is stopped, and a reload
    // would open a second connection next to the remux writer.
    guard castController?.isEngaged != true else { return }
    guard let request = currentLoadRequest, request.isLiveStream,
          // A known length means a finite file the classifier called live; reloading
          // it would replay it in a loop.
          engine.duration <= 0,
          let delay = liveReloadBudget.nextDelay(
            stablePlaybackSeconds: stablePlaybackSeconds()
          )
    else {
      engine.markLiveStreamEnded()
      return
    }
    log.info("Live stream ended; reloading in \(delay, privacy: .public)s")
    liveReloadWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.isTornDown else { return }
      self.liveReloadWork = nil
      guard self.castController?.isEngaged != true, let request = self.currentLoadRequest
      else { return }
      self.startLoad(request, origin: .liveReload)
    }
    liveReloadWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  func setupAudioHandler() {
    setupAudioSession()
    setupRemoteCommands()
  }

  func setPlaybackPresentation(_ presentation: PlaybackPresentation) {
    playbackPresentation = presentation
    if isLiveStream != presentation.isLive {
      isLiveStream = presentation.isLive
    }
    applyPlaybackRateCommandEnablement()
    scheduleNowPlayingArtworkFetch(for: presentation)
    updateNowPlayingInfo(force: true)
  }

  func togglePlayPause() {
    // An explicit choice outranks whatever an interruption would restore.
    resumeAfterInterruption = false
    if isPlaying {
      routedPause()
    } else {
      routedPlay()
    }
  }

  /// Play from the lock screen / Control Center / a headset. A failed load has
  /// nothing to resume — the engine's play would at best re-prepare the fallback
  /// player — so it takes the same path as the on-screen Retry.
  private func remotePlay() {
    resumeAfterInterruption = false
    if playbackFailureMessage != nil {
      retryCurrentLoad()
    } else {
      routedPlay()
    }
  }

  func jump(seconds: Int) {
    if castPresentingNow {
      // Chosen at tap time: the cast publishes a seek target at once and the
      // receiver's next tick overwrites it with the pre-seek time, so the
      // presented position alone cannot tell whether the last seek has landed.
      let pending = castSeekTarget
      seekAbsolute(to: VideoPlayerControllerLogic.castSkipTarget(
        reportedSeconds: Double(currentTimeMs) / 1000.0,
        pendingTargetSeconds: pending?.seconds,
        secondsSinceTarget: pending.map { Date().timeIntervalSince($0.issuedAt) } ?? 0,
        delta: Double(seconds),
        durationSeconds: Double(durationMs) / 1000.0
      ))
      return
    }
    markSeekRequestStart()
    engine.jumpRelative(seconds: seconds)
  }

  func seek(to pos: Float) {
    if castPresentingNow {
      let dur = Double(durationMs) / 1000.0
      guard dur > 0 else { return }
      seekAbsolute(to: dur * Double(min(max(pos, 0), 1)))
      return
    }
    markSeekRequestStart()
    engine.seekToFraction(pos)
  }

  /// Momentary rate override (the hold-for-2x gesture). On the engine, `1.0`
  /// ends the override and playback returns to the chosen `playbackSpeed`, not
  /// to 1x. A cast is driven with the rate as given: the chosen speed is not
  /// applied to casts.
  func setRate(_ newRate: Float) {
    let applied: Float
    if let cast = castController, cast.isPresenting {
      applied = cast.isContinuingLocally
        ? VideoPlayerControllerLogic.engineRate(requested: newRate, chosenSpeed: playbackSpeed)
        : newRate
      cast.setRate(applied)
    } else {
      applied = VideoPlayerControllerLogic.engineRate(
        requested: newRate, chosenSpeed: playbackSpeed
      )
      engine.setPlaybackRate(Double(applied))
    }
    if rate != applied { rate = applied }
  }

  // MARK: - Playback speed

  /// Sets the speed for non-live content. It stays chosen across loads (next
  /// episode, retry, cast hand-back); live content keeps 1x and ignores it.
  func setPlaybackSpeed(_ speed: Float) {
    let sanitized = VideoPlayerControllerLogic.sanitizedPlaybackSpeed(
      speed, isLive: currentContentIsLive
    )
    if playbackSpeed != sanitized { playbackSpeed = sanitized }
    // Keep the TV at 1x. After returning to the phone, the retained AVPlayer
    // applies the chosen speed and also keeps it through play/pause.
    if castPresentingNow {
      guard castController?.isContinuingLocally == true else { return }
      castController?.setLocalPlaybackSpeed(sanitized)
    } else {
      engine.setPlaybackRate(Double(sanitized))
    }
    if rate != sanitized { rate = sanitized }
  }

  // MARK: - Sleep timer

  /// Pauses playback after `minutes`; nil (or a non-positive value) cancels.
  /// One timer: a new call replaces the running one.
  func setSleepTimer(minutes: Int?) {
    sleepTimerWork?.cancel()
    sleepTimerWork = nil
    guard !isTornDown,
          let interval = VideoPlayerControllerLogic.sleepTimerInterval(minutes: minutes)
    else {
      if sleepTimerEndsAt != nil { sleepTimerEndsAt = nil }
      return
    }
    let endsAt = Date().addingTimeInterval(interval)
    if sleepTimerEndsAt != endsAt { sleepTimerEndsAt = endsAt }
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.isTornDown else { return }
      self.sleepTimerWork = nil
      if self.sleepTimerEndsAt != nil { self.sleepTimerEndsAt = nil }
      // The timer's pause is the user's own choice, made ahead of time: an
      // interruption that ends later must not resume over it. Routed, so it
      // pauses a cast on the TV as well.
      self.resumeAfterInterruption = false
      self.routedPause()
    }
    sleepTimerWork = work
    // Wall clock: the published end is a date, and the timer must meet it even
    // if the device slept in between.
    DispatchQueue.main.asyncAfter(wallDeadline: .now() + interval, execute: work)
  }

  // MARK: - Picture in Picture

  func startPictureInPicture() {
    engine.startPictureInPicture()
  }

  func stopPictureInPicture() {
    engine.stopPictureInPicture()
  }

  func setVolume(_ value: Double) {
    let clamped = min(max(value, 0), 125)
    if let cast = castController, cast.isPresenting {
      cast.setVolume(clamped)
    } else {
      engine.setVolume(clamped)
    }
  }

  func setAspectMode(_ mode: VideoAspectMode, force: Bool = false) {
    if !force, aspectMode == mode { return }
    aspectMode = mode
  }

  func updateTracks(applyPreferences: Bool = false, skipSubtitleSelection: Bool = false) {
    // Remux owns the connection now; retain the source menu and its stream ids.
    if castController?.isPresenting == true, engine.layer == nil { return }
    engine.reloadTrackList { [weak self] video, audio, subs, vid, aid, sid in
      guard let self else { return }
      // Guarded like the rest of the class: @Published fires objectWillChange even on
      // an unchanged assignment, and this runs on every track-menu open / establish.
      if self.videoTracks != video { self.videoTracks = video }
      if self.audioTracks != audio { self.audioTracks = audio }
      if self.subtitleTracks != subs { self.subtitleTracks = subs }
      if self.currentVideoTrackId != vid { self.currentVideoTrackId = vid }
      if self.currentAudioTrackId != aid { self.currentAudioTrackId = aid }
      if self.currentSubtitleTrackId != sid { self.currentSubtitleTrackId = sid }
      guard applyPreferences else { return }
      let prefs = PlaybackTrackPreferences.load()
      if let pick = PlaybackTrackPreferences.pickVideo(from: video, prefs: prefs) {
        self.engine.selectVideoTrack(id: pick)
        if self.currentVideoTrackId != pick { self.currentVideoTrackId = pick }
      }
      if let pick = PlaybackTrackPreferences.pickAudio(from: audio, prefs: prefs) {
        self.engine.selectAudioTrack(id: pick)
        if self.currentAudioTrackId != pick { self.currentAudioTrackId = pick }
      }
      if !skipSubtitleSelection,
         let pick = PlaybackTrackPreferences.pickSubtitle(from: subs, prefs: prefs)
      {
        self.engine.selectSubtitleTrack(id: pick)
        if self.currentSubtitleTrackId != pick { self.currentSubtitleTrackId = pick }
      }
    }
  }

  func selectVideoTrack(id: Int) {
    engine.selectVideoTrack(id: id)
    currentVideoTrackId = id
    if let opt = videoTracks.first(where: { $0.id == id }) {
      PlaybackTrackPreferences.saveVideo(from: opt)
    }
  }

  func selectAudioTrack(id: Int) {
    let changedCast = castController?.updateRemuxTracks { $0.audioStreamIndex = id } ?? false
    if !changedCast { engine.selectAudioTrack(id: id) }
    currentAudioTrackId = id
    if let opt = audioTracks.first(where: { $0.id == id }) {
      PlaybackTrackPreferences.saveAudio(from: opt)
    }
  }

  func selectSubtitleTrack(id: Int) {
    if castController?.isPresenting != true { engine.selectSubtitleTrack(id: id) }
    currentSubtitleTrackId = id
    let external = selectedExternalSubtitle()
    let embeddedIndex = engine.embeddedSubtitleStreamIndex(id: id)
    castController?.updateRemuxTracks {
      $0.subtitleStreamIndex = embeddedIndex
      $0.subtitleFileURL = external?.url
      $0.subtitleName = external?.name ?? subtitleTracks.first { $0.id == id }?.title
      $0.subtitleLanguage = external?.language ?? subtitleTracks.first { $0.id == id }?.langCode
    }
    if let opt = subtitleTracks.first(where: { $0.id == id }) {
      PlaybackTrackPreferences.saveSubtitle(from: opt)
      if let key = importedSubtitleContentKey {
        // Remember external track selection per content; picking embedded / off resets it.
        let importedName = opt.isExternal && importedFileNames.contains(opt.title) ? opt.title : nil
        ImportedSubtitleStore.setSelectedFileName(importedName, for: key)
      }
    }
  }

  // MARK: - Imported subtitles (issue #98)

  private var importedFileNames: Set<String> {
    Set(importedSubtitleFiles.map(\.lastPathComponent))
  }

  /// Identity of the playing content; set by PlayerView before every `play` call.
  func setImportedSubtitleContext(contentKey: String) {
    importedSubtitleContentKey = contentKey
    importedSubtitleFiles = ImportedSubtitleStore.subtitleFiles(for: contentKey)
  }

  /// Adds the stored files to mpv; returns whether the saved selection was applied.
  private func restoreImportedSubtitles() -> Bool {
    guard let key = importedSubtitleContentKey else { return false }
    let files = ImportedSubtitleStore.subtitleFiles(for: key)
    importedSubtitleFiles = files
    guard !files.isEmpty else { return false }
    let selectedName = ImportedSubtitleStore.selectedFileName(for: key)
    var didSelect = false
    for file in files {
      let name = file.lastPathComponent
      let select = name == selectedName
      didSelect = didSelect || select
      engine.addExternalSubtitle(filePath: file.path, title: name, select: select)
    }
    return didSelect
  }

  func importSubtitleFile(at pickedURL: URL) throws {
    guard let key = importedSubtitleContentKey else { return }
    let saved = try ImportedSubtitleStore.importFile(at: pickedURL, for: key)
    let name = saved.lastPathComponent
    // If a track with the same name was added before, drop the old one (file was overwritten).
    if let existing = subtitleTracks.first(where: { $0.isExternal && $0.title == name }) {
      engine.removeExternalSubtitle(id: existing.id)
    }
    ImportedSubtitleStore.setSelectedFileName(name, for: key)
    importedSubtitleFiles = ImportedSubtitleStore.subtitleFiles(for: key)
    engine.addExternalSubtitle(filePath: saved.path, title: name, select: true)
    updateTracks()
  }

  func deleteImportedSubtitle(_ url: URL) {
    guard let key = importedSubtitleContentKey else { return }
    let name = url.lastPathComponent
    ImportedSubtitleStore.removeFile(url, for: key)
    importedSubtitleFiles = ImportedSubtitleStore.subtitleFiles(for: key)
    if let existing = subtitleTracks.first(where: { $0.isExternal && $0.title == name }) {
      engine.removeExternalSubtitle(id: existing.id)
      updateTracks()
    }
  }

  func applySubtitleAppearanceSettings(_ settings: SubtitleAppearanceSettings) {
    SubtitleAppearancePersistence.save(settings)
    // Style only. The time offset is per content (`commitSubtitleDelaySeconds`);
    // the legacy `settings.delaySeconds` is no longer applied anywhere.
    engine.applySubtitleAppearanceFromSettings(settings)
  }

  /// Live preview of a subtitle time offset: applied to the engine, neither
  /// published nor stored. Revert with `subtitleDelaySeconds`.
  func applySubtitleDelaySeconds(_ seconds: Double) {
    engine.setSubDelay(seconds: seconds)
  }

  /// Makes `seconds` the subtitle time offset of the current content: applied,
  /// published and remembered for the next time this content plays (0 forgets it).
  func commitSubtitleDelaySeconds(_ seconds: Double) {
    let clamped = SubtitleDelayStore.clamp(seconds)
    engine.setSubDelay(seconds: clamped)
    if subtitleDelaySeconds != clamped { subtitleDelaySeconds = clamped }
    if let key = importedSubtitleContentKey {
      SubtitleDelayStore.setDelaySeconds(clamped, for: key)
    }
  }

  // MARK: - AirPlay

  /// Aborts a cast that is still preparing and returns to phone playback. Only
  /// acts in the preparing state: ending a running cast this way would restart
  /// the engine with the AirPlay route still selected (sound on the TV, picture
  /// on the phone) — leaving a running cast is the system route picker's job.
  func cancelAirPlayPreparation() {
    guard let cast = castController, cast.isPreparing else { return }
    cast.stopCasting()
  }

  /// The route picker (the hidden one behind the AirPlay button, or the visible
  /// system button) is about to show its device list. Forwarded only: what an
  /// open picker means for a cast is the cast controller's decision.
  func airPlayPickerWillOpen() {
    castController?.pickerWillOpen()
  }

  /// The route picker closed, after a choice or a cancel.
  func airPlayPickerDidClose() {
    castController?.pickerDidClose()
  }

  /// Localized text for a cast notice; nil for silent reasons. When the cast
  /// failed with its AirPlay route still selected, a second sentence says where
  /// picture and sound are now (see `CastNotice.soundStaysOnRoute`).
  func castNoticeMessage(for notice: CastNotice) -> String? {
    guard let key = notice.reason.messageKey else { return nil }
    let message = L(key)
    guard notice.soundStaysOnRoute else { return message }
    return message + " " + L("player.airplay.notice.sound_stays_on_airplay")
  }

  /// UHF akışı: remux'u kur, hazır olunca completion(true) — UI sistem seçiciyi o anda açar.
  func prepareAirPlay(completion: @escaping (Bool) -> Void) {
    guard let cast = castController else {
      completion(false)
      return
    }
    let ks = engine
    guard needsAirPlayPreparation else {
      completion(true)  // native yol ya da cast zaten sunumda — seçici direkt açılabilir
      return
    }
    guard let request = currentLoadRequest else {
      completion(false)
      return
    }
    // Resume edilmiş içerikte ilk zaman tiki henüz gelmediyse motor 0 raporlar;
    // istekteki başlangıç saniyesine düş (cast 0:00'dan başlamasın).
    let at: TimeInterval
    if ks.isPlaybackEstablished, ks.position > 0.5 {
      at = ks.position
    } else {
      at = request.startSeconds ?? 0
    }
    let subtitle = selectedExternalSubtitle()
    let content = CastController.Content(
      url: request.url,
      isLive: request.isLiveStream,
      userAgent: request.userAgent,
      startAt: request.isLiveStream ? 0 : at,
      knownDuration: ks.duration,
      nativelyPlayable: false,
      startPaused: ks.isPlaybackEstablished && ks.isPaused,
      subtitleFileURL: subtitle?.url,
      subtitleName: subtitle?.name ?? subtitleTracks.first { $0.id == currentSubtitleTrackId }?.title,
      subtitleLanguage: subtitle?.language ?? subtitleTracks.first { $0.id == currentSubtitleTrackId }?.langCode,
      audioStreamIndex: ks.isFFmpegBackendActive && currentAudioTrackId >= 0 ? currentAudioTrackId : nil,
      subtitleStreamIndex: ks.embeddedSubtitleStreamIndex(id: currentSubtitleTrackId),
      subtitleDelaySeconds: subtitleDelaySeconds
    )
    // Experimental and off by default: a live channel whose provider also serves
    // HLS is handed to the receiver as that stream, with no remux. Decided here,
    // at the explicit tap and nowhere else; `content` keeps the original URL, so
    // a failed attempt falls back to the remux below and an exit resumes it.
    let nativeLiveCastEnabled = content.audioStreamIndex == nil
      && content.subtitleStreamIndex == nil && content.subtitleFileURL == nil
      && UserDefaults.standard.bool(
      forKey: CastNativeURL.enabledDefaultsKey
    )
    if let nativeURL = CastNativeURL.candidate(
      enabled: nativeLiveCastEnabled,
      isLive: request.isLiveStream,
      isFFmpegBackendActive: ks.isFFmpegBackendActive,
      avPlayerAlreadyTried: !KSPlayerEngine.prefersFFmpegFirst(for: request.url),
      videoCodec: ks.videoCodecName,
      audioCodec: ks.audioCodecName,
      url: request.url,
      containerFormatName: ks.containerFormatName,
      failureRemembered: nativeLiveCastEnabled
        && CastNativeURL.hasRememberedFailure(for: request.url)
    ) {
      cast.startNativeLiveCast(content: content, nativeURL: nativeURL, completion: completion)
      return
    }
    cast.startRemuxCast(content: content, completion: completion)
  }

  /// The currently-selected EXTERNAL subtitle (imported SRT), mapped to its file — used to
  /// expose it on the AirPlay target as an HLS WebVTT rendition. Returns nil when the
  /// selection is "off" or an embedded track (Phase 1 covers external SRT only).
  private func selectedExternalSubtitle() -> (url: URL, name: String, language: String?)? {
    guard currentSubtitleTrackId >= 0,
          let opt = subtitleTracks.first(where: { $0.id == currentSubtitleTrackId }),
          opt.isExternal,
          let url = importedSubtitleFiles.first(where: { $0.lastPathComponent == opt.title })
    else { return nil }
    return (url, url.deletingPathExtension().lastPathComponent, opt.langCode)
  }

  func applyAudioDelaySeconds(_ seconds: Double) {
    AudioDelayPersistence.save(seconds)
    engine.setAudioDelay(seconds: seconds)
  }

  func teardown() {
    if isTornDown { return }
    isTornDown = true
    Self.unregister(self)
    seriesEpisodeOnPrevious = nil
    seriesEpisodeOnNext = nil
    MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
    MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
    MPRemoteCommandCenter.shared().changePlaybackRateCommand.isEnabled = false
    // The model keeps the pre-adjustment brightness; captured so the restore also
    // runs when this is the deinit path and the hop below outlives the controller.
    let brightnessModel = brightness
    let restoreSystemState = {
      UIApplication.shared.isIdleTimerDisabled = false
      brightnessModel.restoreBrightnessIfAdjusted()
    }
    if Thread.isMainThread {
      restoreSystemState()
    } else {
      DispatchQueue.main.async(execute: restoreSystemState)
    }
    cancellables.removeAll()
    removeRemoteCommands()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    playbackPresentation = nil
    cancelNowPlayingArtworkFetch(clearImage: true)
    pendingLoadRequest = nil
    cancelScheduledReloads()
    postCastRetryArmed = false
    clearZapRetry()
    castSeekTarget = nil
    clearPausedResume()
    cancelAudioOnlyAirPlayDebounce()
    if isAudioOnlyAirPlay { isAudioOnlyAirPlay = false }
    sleepTimerWork?.cancel()
    sleepTimerWork = nil
    if sleepTimerEndsAt != nil { sleepTimerEndsAt = nil }
    let wasActivated = audioSessionActivated
    let leaseToRelease = audioSessionLease
    audioSessionActivated = false
    audioSessionLease = nil
    seekRequestStartedAt = nil
    seekSourceTimeMs = nil
    measuredSeekLatencyMs = -1
    if seekLatencyMs != -1 { seekLatencyMs = -1 }
    playbackFailureMessage = nil
    // Native AirPlay belongs to KSPlayer's screen-scoped AVPlayer. Capture the
    // selected route before disposing that engine so the next screen can promote
    // its item to the long-lived cast player instead of continuing audio-only.
    if castController?.isEngaged != true,
       engine.isExternalPlaybackActive || isAirPlayPlaybackActive {
      CastController.markNativeExternalPlaybackForNextLoad()
    }
    // Keep one external-playback AVPlayer alive while the user leaves a series
    // and opens a live channel. Recreating it here flaps the route and strands
    // the next FFmpeg stream as audio-only AirPlay.
    let castStaysAlive = castController?.parkForCrossScreenHandoff(owner: castOwnerToken) == true
    if !castStaysAlive {
      castController?.dispose()
    }
    // Decided only now, after the park decision: a cast controller that stays
    // alive with an engagement (parked for the next screen, or already owned by
    // it) plays through this very session. Deactivating it half a second after
    // the screen closed cut the session from under the live AirPlay player.
    let castKeepsSession = castStaysAlive && castController?.isEngaged == true
    if wasActivated, let leaseToRelease, !castKeepsSession {
      // Non-mixable .playback oturumu açık bırakılırsa, oynatıcı kapandıktan sonra
      // kestiğimiz uygulama (Music/Spotify) hiçbir zaman devam sinyali alamaz.
      // mpv'nin audio unit'i async dispose olduğundan kısa bir gecikmeyle kapat.
      // A newer controller may claim the process-wide session during this delay;
      // the lease guard then turns this teardown into a no-op.
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
        Self.deactivateAudioSessionIfCurrent(leaseToRelease)
      }
    } else if wasActivated, let leaseToRelease {
      // The cast keeps playing through the session this controller activated, and
      // no screen may be around when it ends. The release is handed to the cast
      // controller, which runs it only if the engagement ends while parked with no
      // owner (it ignores this when a newer screen already owns it). The lease
      // guard still applies: a session a newer controller has claimed stays active.
      castController?.setParkedAudioSessionRelease {
        Self.deactivateAudioSessionIfCurrent(leaseToRelease)
      }
    }
    let teardownInterval = Self.signposter.beginInterval("EngineTeardown")
    engine.dispose()
    Self.signposter.endInterval("EngineTeardown", teardownInterval)
  }

  private func markSeekRequestStart() {
    seekRequestStartedAt = Date()
    seekSourceTimeMs = currentTimeMs
    measuredSeekLatencyMs = -1
    if diagnosticsVisible, seekLatencyMs != -1 { seekLatencyMs = -1 }
    // The elapsed time jumps: the next sync pass pushes it to Now Playing.
    nowPlayingElapsedDirty = true
  }

  private func updateSeekLatencyIfNeeded(currentTimeMs: Int64) {
    guard measuredSeekLatencyMs < 0 else { return }
    guard let startedAt = seekRequestStartedAt, let sourceTimeMs = seekSourceTimeMs else { return }
    let shifted = abs(currentTimeMs - sourceTimeMs) >= 900
    let stalledTooLong = Date().timeIntervalSince(startedAt) >= 5.0
    guard shifted || stalledTooLong else { return }
    measuredSeekLatencyMs = max(Int(Date().timeIntervalSince(startedAt) * 1000), 0)
    seekRequestStartedAt = nil
    seekSourceTimeMs = nil
  }

  // MARK: - Now Playing

  /// Fields of the last written dictionary other than elapsed time (nil until the
  /// first write), and the clock the system has been extrapolating from since.
  private var pushedNowPlayingFields: VideoPlayerControllerLogic.NowPlayingFields?
  private var pushedNowPlayingElapsed: Double = 0
  private var pushedNowPlayingAt: TimeInterval = 0
  /// A seek was requested: write the new elapsed time on the next pass.
  private var nowPlayingElapsedDirty = false
  private var lastNowPlayingRepairCheck: TimeInterval = 0
  /// How often the shared dictionary is read back to see whether it is still ours.
  private static let nowPlayingRepairInterval: TimeInterval = 0.8

  /// Writes the Now Playing dictionary when something other than elapsed time
  /// changed, on explicit pushes (`force`, a seek) and when elapsed time has left
  /// the system's own extrapolation. Elapsed time alone is not a reason to write:
  /// the system advances it from the pushed rate.
  private func updateNowPlayingInfo(force: Bool = false) {
    guard let p = playbackPresentation else { return }
    let now = CFAbsoluteTimeGetCurrent()

    let elapsedSec = max(Double(currentTimeMs) / 1000.0, 0)

    // On live channels with EPG, show the programme as the title and the channel
    // as the artist; otherwise the channel/content title.
    let displayTitle: String
    let displayArtist: String
    if p.isLive, let programme = p.programmeTitle, !programme.isEmpty {
      displayTitle = programme
      displayArtist = p.title
    } else {
      displayTitle = p.title
      displayArtist = p.subtitle ?? "Another IPTV Player"
    }

    let fields = VideoPlayerControllerLogic.NowPlayingFields(
      title: displayTitle,
      artist: displayArtist,
      // Keep the system LIVE badge and no scrubber — do not synthesize a duration
      // from the programme interval (it would misrepresent the transport).
      durationSeconds: p.isLive ? 0 : max(Double(durationMs) / 1000.0, 0),
      rate: isPlaying ? Double(rate) : 0.0,
      isLive: p.isLive,
      artworkID: nowPlayingArtworkItem.map { ObjectIdentifier($0) }
    )
    var push = VideoPlayerControllerLogic.shouldPushNowPlaying(
      force: force || nowPlayingElapsedDirty,
      fields: fields,
      pushed: pushedNowPlayingFields,
      elapsed: elapsedSec,
      pushedElapsed: pushedNowPlayingElapsed,
      secondsSincePush: now - pushedNowPlayingAt
    )
    if !push, now - lastNowPlayingRepairCheck >= Self.nowPlayingRepairInterval {
      // The dictionary is shared with KSPlayerLayer, which wipes it in stop() and
      // deinit (a deinit can run late, after our own write) and starts a new one
      // at ready. Read it back now and then and write ours again if it is gone.
      lastNowPlayingRepairCheck = now
      let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
      push = !VideoPlayerControllerLogic.nowPlayingIsIntact(
        title: current?[MPMediaItemPropertyTitle] as? String,
        artist: current?[MPMediaItemPropertyArtist] as? String,
        durationSeconds: (current?[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue,
        hasArtwork: current?[MPMediaItemPropertyArtwork] != nil,
        expected: fields
      )
    }
    guard push else { return }

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: fields.title,
      MPMediaItemPropertyArtist: fields.artist,
      MPMediaItemPropertyPlaybackDuration: fields.durationSeconds,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSec,
      MPNowPlayingInfoPropertyPlaybackRate: fields.rate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if fields.isLive {
      info[MPNowPlayingInfoPropertyIsLiveStream] = true
    }
    if let artwork = nowPlayingArtworkItem {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    pushedNowPlayingFields = fields
    pushedNowPlayingElapsed = elapsedSec
    pushedNowPlayingAt = now
    nowPlayingElapsedDirty = false
    lastNowPlayingRepairCheck = now
  }

  private func cancelNowPlayingArtworkFetch(clearImage: Bool) {
    artworkFetchTask?.cancel()
    artworkFetchTask = nil
    artworkFetchURL = nil
    if clearImage { setNowPlayingArtwork(nil) }
  }

  /// Image and artwork object change together; the object is built once per image.
  private func setNowPlayingArtwork(_ image: UIImage?) {
    nowPlayingArtwork = image
    nowPlayingArtworkItem = image.map { Self.makeNowPlayingArtwork($0) }
  }

  /// Built outside the main actor on purpose: MediaPlayer calls the handler on
  /// its own queue.
  nonisolated private static func makeNowPlayingArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    let size = image.size
    let bounds = CGSize(width: max(size.width, 1), height: max(size.height, 1))
    // Sistem istenen boyutta tekrar çağırır; tek `UIImage` yeterli.
    return MPMediaItemArtwork(boundsSize: bounds) { _ in image }
  }

  /// Scales a fetched poster down for Now Playing. Runs on the fetch callback's
  /// thread (`preparingThumbnail(of:)` is safe off the main thread).
  nonisolated private static func downscaledForNowPlaying(_ image: UIImage) -> UIImage {
    let target = VideoPlayerControllerLogic.nowPlayingArtworkSize(for: image.size)
    guard target != image.size, let scaled = image.preparingThumbnail(of: target) else {
      return image
    }
    return scaled
  }

  /// Now Playing yalnızca bitmap kabul eder (`MPMediaItemArtwork`); URL’yi biz indiriyoruz.
  private func scheduleNowPlayingArtworkFetch(for presentation: PlaybackPresentation) {
    guard let url = presentation.artworkURL else {
      cancelNowPlayingArtworkFetch(clearImage: true)
      return
    }
    if artworkFetchURL == url, nowPlayingArtwork != nil { return }
    if artworkFetchURL == url, artworkFetchTask != nil { return }

    cancelNowPlayingArtworkFetch(clearImage: true)
    artworkFetchURL = url

    let capturedURL = url
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let decoded = UIImage(data: data) else {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if self.artworkFetchURL == capturedURL {
            self.setNowPlayingArtwork(nil)
            self.artworkFetchTask = nil
            self.artworkFetchURL = nil
            self.updateNowPlayingInfo(force: true)
          }
        }
        return
      }
      // Scaled once, here on the fetch thread: MediaPlayer JPEG-encodes what the
      // artwork handler returns at its full size, and posters can be 2000 px.
      let image = Self.downscaledForNowPlaying(decoded)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard self.artworkFetchURL == capturedURL else { return }
        self.setNowPlayingArtwork(image)
        self.artworkFetchTask = nil
        self.updateNowPlayingInfo(force: true)
      }
    }
    artworkFetchTask = task
    task.resume()
  }

  private func setupRemoteCommands() {
    guard remoteCommandTargets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    let t1 = center.playCommand.addTarget { [weak self] _ in
      self?.remotePlay()
      return .success
    }
    remoteCommandTargets.append((center.playCommand, t1))

    center.pauseCommand.isEnabled = true
    let t2 = center.pauseCommand.addTarget { [weak self] _ in
      self?.resumeAfterInterruption = false
      self?.routedPause()
      return .success
    }
    remoteCommandTargets.append((center.pauseCommand, t2))

    center.togglePlayPauseCommand.isEnabled = true
    let t3 = center.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self else { return .success }
      // Headset button on a failed load: same retry as the play command.
      if self.playbackFailureMessage != nil {
        self.remotePlay()
      } else {
        self.togglePlayPause()
      }
      return .success
    }
    remoteCommandTargets.append((center.togglePlayPauseCommand, t3))

    center.changePlaybackPositionCommand.isEnabled = true
    let tSeek = center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self,
            let e = event as? MPChangePlaybackPositionCommandEvent,
            self.durationMs > 0
      else { return .commandFailed }
      self.seekAbsolute(to: e.positionTime)
      return .success
    }
    remoteCommandTargets.append((center.changePlaybackPositionCommand, tSeek))

    center.skipForwardCommand.isEnabled = true
    center.skipForwardCommand.preferredIntervals = [15]
    let t4 = center.skipForwardCommand.addTarget { [weak self] _ in
      self?.jump(seconds: 15)
      return .success
    }
    remoteCommandTargets.append((center.skipForwardCommand, t4))

    center.skipBackwardCommand.isEnabled = true
    center.skipBackwardCommand.preferredIntervals = [15]
    let t5 = center.skipBackwardCommand.addTarget { [weak self] _ in
      self?.jump(seconds: -15)
      return .success
    }
    remoteCommandTargets.append((center.skipBackwardCommand, t5))

    center.previousTrackCommand.isEnabled = false
    let t6 = center.previousTrackCommand.addTarget { [weak self] _ in
      guard let cb = self?.seriesEpisodeOnPrevious else { return .commandFailed }
      cb()
      return .success
    }
    remoteCommandTargets.append((center.previousTrackCommand, t6))

    center.nextTrackCommand.isEnabled = false
    let t7 = center.nextTrackCommand.addTarget { [weak self] _ in
      guard let cb = self?.seriesEpisodeOnNext else { return .commandFailed }
      cb()
      return .success
    }
    remoteCommandTargets.append((center.nextTrackCommand, t7))

    // Playback speed from system surfaces (CarPlay, accessories; the iOS lock
    // screen shows no control for it). Goes through the same chosen speed as
    // the in-app menu, so both always agree.
    center.changePlaybackRateCommand.supportedPlaybackRates =
      VideoPlayerControllerLogic.supportedPlaybackSpeeds.map { NSNumber(value: $0) }
    let t8 = center.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let self,
            let e = event as? MPChangePlaybackRateCommandEvent,
            !self.currentContentIsLive
      else { return .commandFailed }
      self.setPlaybackSpeed(e.playbackRate)
      return .success
    }
    remoteCommandTargets.append((center.changePlaybackRateCommand, t8))
    applyPlaybackRateCommandEnablement()
  }

  /// Speed is offered for non-live content only (live plays at 1x).
  private func applyPlaybackRateCommandEnablement() {
    guard !remoteCommandTargets.isEmpty else { return }
    let enabled = !currentContentIsLive
    let command = MPRemoteCommandCenter.shared().changePlaybackRateCommand
    if command.isEnabled != enabled { command.isEnabled = enabled }
  }

  /// Kontrol Merkezi / kilit ekranından önceki–sonraki bölüm (yalnızca dizi oynatırken).
  /// - swapSkipForNav: true → skip komutları kapatılır, prev/next gösterilir (dizi & canlı TV).
  ///                   false → skip aktif kalır; filmler için her zaman false.
  func configureSeriesEpisodeSkipping(
    canPrevious: Bool,
    canNext: Bool,
    onPrevious: (() -> Void)?,
    onNext: (() -> Void)?,
    swapSkipForNav: Bool = true
  ) {
    seriesEpisodeOnPrevious = canPrevious ? onPrevious : nil
    seriesEpisodeOnNext = canNext ? onNext : nil
    episodeNavCanPrevious = canPrevious && onPrevious != nil
    episodeNavCanNext = canNext && onNext != nil
    episodeNavSwapSkip = swapSkipForNav
    applyEpisodeNavCommandEnablement()
  }

  private func applyEpisodeNavCommandEnablement() {
    let center = MPRemoteCommandCenter.shared()
    let hasEpisodeNav = episodeNavCanPrevious || episodeNavCanNext
    // iOS hides previousTrack/nextTrack buttons when skipForward/skipBackward are enabled.
    // For series & live TV: swap skip → prev/next. For movies: keep skip enabled.
    let disableSkip = episodeNavSwapSkip && hasEpisodeNav
    center.skipForwardCommand.isEnabled = !disableSkip
    center.skipBackwardCommand.isEnabled = !disableSkip
    center.previousTrackCommand.isEnabled = episodeNavSwapSkip && episodeNavCanPrevious
    center.nextTrackCommand.isEnabled = episodeNavSwapSkip && episodeNavCanNext
  }

  /// `KSPlayerLayer.deinit` koşulsuz `removeTarget(nil)` çağırır ve Now Playing'i
  /// siler — her layer yıkımından (yeni load, cast devri) sonra kendi komutlarımız
  /// ve Now Playing yeniden kurulmalı; aksi halde kilit ekranı ilk zap'tan sonra ölür.
  private func reinstallRemoteCommands() {
    guard !remoteCommandTargets.isEmpty else { return }
    removeRemoteCommands()
    setupRemoteCommands()
    applyEpisodeNavCommandEnablement()
    updateNowPlayingInfo(force: true)
  }

  private func removeRemoteCommands() {
    for (cmd, token) in remoteCommandTargets {
      cmd.removeTarget(token)
    }
    remoteCommandTargets.removeAll()
  }
}
