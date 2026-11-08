import Foundation

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
