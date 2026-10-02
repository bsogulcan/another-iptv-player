import CoreGraphics
import Foundation
import Testing
@testable import another_iptv_player

/// Decisions of `VideoPlayerController` that need no player, no audio session and no
/// system state. The controller has no seam for a fake engine, so its rules for the
/// audio-only AirPlay hint, the native AirPlay continuation, the idle timer, the
/// playback clock, speed, sleep timer, paused resume and Now Playing live in pure
/// functions and are locked here. (Source: ios-player-airplay-review.md.)

// MARK: - Audio-only AirPlay ("sound on the TV, picture on the phone")

struct AudioOnlyAirPlayTests {
    private typealias Logic = VideoPlayerControllerLogic

    /// All three must hold: AirPlay route, no cast engagement, FFmpeg backend.
    @Test func needsRouteFFmpegBackendAndNoEngagement() {
        #expect(Logic.isAudioOnlyAirPlay(
            routeIsAirPlay: true, castEngaged: false, ffmpegBackendActive: true
        ))
        // No AirPlay route: the sound is on the phone.
        #expect(!Logic.isAudioOnlyAirPlay(
            routeIsAirPlay: false, castEngaged: false, ffmpegBackendActive: true
        ))
        // A cast engagement sends (or is about to send) the video too.
        #expect(!Logic.isAudioOnlyAirPlay(
            routeIsAirPlay: true, castEngaged: true, ffmpegBackendActive: true
        ))
        // AVPlayer backend: native external playback carries the video itself.
        #expect(!Logic.isAudioOnlyAirPlay(
            routeIsAirPlay: true, castEngaged: false, ffmpegBackendActive: false
        ))
    }

    @Test func debounceIsAboutOneAndAHalfSeconds() {
        #expect(Logic.audioOnlyAirPlayDebounceSeconds == 1.5)
    }

    /// A change of the raw condition is not published at once: it starts the wait.
    @Test func rawChangeSchedulesInBothDirections() {
        #expect(Logic.audioOnlyAirPlayStep(
            published: false, pending: nil, raw: true, castEngaged: false
        ) == .schedule(true))
        #expect(Logic.audioOnlyAirPlayStep(
            published: true, pending: nil, raw: false, castEngaged: false
        ) == .schedule(false))
    }

    /// Later passes with the same raw value must not restart the running wait, or
    /// the 5 Hz sync would push it out forever.
    @Test func runningWaitIsNotRestarted() {
        #expect(Logic.audioOnlyAirPlayStep(
            published: false, pending: true, raw: true, castEngaged: false
        ) == .keep)
        #expect(Logic.audioOnlyAirPlayStep(
            published: true, pending: false, raw: false, castEngaged: false
        ) == .keep)
    }

    /// A zap clears the backend flag for a moment and a stopping player flaps the
    /// route: when the raw value returns before the wait is over, nothing was shown.
    @Test func flapCancelsThePendingChange() {
        #expect(Logic.audioOnlyAirPlayStep(
            published: true, pending: false, raw: true, castEngaged: false
        ) == .cancelPending)
        #expect(Logic.audioOnlyAirPlayStep(
            published: false, pending: true, raw: false, castEngaged: false
        ) == .cancelPending)
    }

    @Test func steadyStateDoesNothing() {
        #expect(Logic.audioOnlyAirPlayStep(
            published: false, pending: nil, raw: false, castEngaged: false
        ) == .keep)
        #expect(Logic.audioOnlyAirPlayStep(
            published: true, pending: nil, raw: true, castEngaged: false
        ) == .keep)
    }

    /// The tap on the hint starts a cast: the hint must go at once, not 1.5 s later,
    /// and a wait that was about to show it is dropped.
    @Test func castEngagementClearsWithoutWaiting() {
        #expect(Logic.audioOnlyAirPlayStep(
            published: true, pending: nil, raw: false, castEngaged: true
        ) == .commit(false))
        #expect(Logic.audioOnlyAirPlayStep(
            published: false, pending: true, raw: false, castEngaged: true
        ) == .commit(false))
        #expect(Logic.audioOnlyAirPlayStep(
            published: false, pending: nil, raw: false, castEngaged: true
        ) == .keep)
    }
}

// MARK: - Native AirPlay continuation (in-place content change)

struct NativeAirPlayContinuationTests {
    private typealias Logic = VideoPlayerControllerLogic

    /// Next episode / zap while the engine's AVPlayer is on the TV: continue through
    /// the cast controller instead of rebuilding the AVPlayer.
    @Test func contentChangeDuringExternalPlaybackContinues() {
        #expect(Logic.continuesNativeExternalPlayback(
            isNewContent: true, castEngaged: false, engineExternalPlaybackActive: true,
            loadWasExternal: true, airPlayRouteActive: true
        ))
        // The engine's own flag is enough; the route read is not consulted.
        #expect(Logic.continuesNativeExternalPlayback(
            isNewContent: true, castEngaged: false, engineExternalPlaybackActive: true,
            loadWasExternal: false, airPlayRouteActive: false
        ))
    }

    /// At a natural end the TV may already have left external playback. The load was
    /// external and the route is still selected: still a continuation.
    @Test func endedItemWithRouteStillSelectedContinues() {
        #expect(Logic.continuesNativeExternalPlayback(
            isNewContent: true, castEngaged: false, engineExternalPlaybackActive: false,
            loadWasExternal: true, airPlayRouteActive: true
        ))
    }

    /// The user left AirPlay (route gone): the next item plays on the phone.
    @Test func routeGoneMeansNoContinuation() {
        #expect(!Logic.continuesNativeExternalPlayback(
            isNewContent: true, castEngaged: false, engineExternalPlaybackActive: false,
            loadWasExternal: true, airPlayRouteActive: false
        ))
    }

    /// A route alone starts nothing: a TV picked in Control Center while local
    /// content plays must not pull the next item into a cast (no ambient trigger).
    @Test func routeAloneIsNotAContinuation() {
        #expect(!Logic.continuesNativeExternalPlayback(
            isNewContent: true, castEngaged: false, engineExternalPlaybackActive: false,
            loadWasExternal: false, airPlayRouteActive: true
        ))
    }

    /// Retries, cast hand-backs and budgeted reloads are not content changes.
    @Test func onlyAnExplicitContentChangeQualifies() {
        #expect(!Logic.continuesNativeExternalPlayback(
            isNewContent: false, castEngaged: false, engineExternalPlaybackActive: true,
            loadWasExternal: true, airPlayRouteActive: true
        ))
    }

    /// An engaged cast controller already carries content changes (`playContent`).
    @Test func engagedCastIsNotThisPath() {
        #expect(!Logic.continuesNativeExternalPlayback(
            isNewContent: true, castEngaged: true, engineExternalPlaybackActive: true,
            loadWasExternal: true, airPlayRouteActive: true
        ))
    }
}

// MARK: - Idle timer

struct IdleTimerPolicyTests {
    private typealias Logic = VideoPlayerControllerLogic

    @Test func screenStaysAwakeWhilePlayingLocally() {
        #expect(Logic.shouldDisableIdleTimer(isPlaying: true, isNativeExternalPlayback: false))
    }

    @Test func pausedPlaybackLetsThePhoneSleep() {
        #expect(!Logic.shouldDisableIdleTimer(isPlaying: false, isNativeExternalPlayback: false))
        #expect(!Logic.shouldDisableIdleTimer(isPlaying: false, isNativeExternalPlayback: true))
    }

    /// The video is on the TV through the engine's own AVPlayer: the phone may
    /// auto-lock. A remux cast is passed as `false` by the controller and stays awake.
    @Test func nativeExternalPlaybackReleasesTheTimer() {
        #expect(!Logic.shouldDisableIdleTimer(isPlaying: true, isNativeExternalPlayback: true))
    }
}

// MARK: - Playback clock publication

struct PlaybackClockTests {
    private typealias Logic = VideoPlayerControllerLogic

    /// VOD (and live with a known length) shows a clock: publish every pass.
    @Test func contentWithADurationPublishesEveryPass() {
        #expect(Logic.publishesClock(
            isLive: false, durationMs: 3_600_000, stateChanged: false, durationChanged: false
        ))
        #expect(Logic.publishesClock(
            isLive: true, durationMs: 3_600_000, stateChanged: false, durationChanged: false
        ))
    }

    /// A non-live item whose duration is not known yet still ticks: its clock is on
    /// screen as soon as the duration arrives.
    @Test func nonLiveWithoutADurationStillPublishes() {
        #expect(Logic.publishesClock(
            isLive: false, durationMs: 0, stateChanged: false, durationChanged: false
        ))
    }

    /// Live without a duration: nothing shows the clock, so ticks publish nothing.
    @Test func liveWithoutADurationIsSilentOnTicks() {
        #expect(!Logic.publishesClock(
            isLive: true, durationMs: 0, stateChanged: false, durationChanged: false
        ))
    }

    @Test func liveStillPublishesOnStateOrDurationChange() {
        #expect(Logic.publishesClock(
            isLive: true, durationMs: 0, stateChanged: true, durationChanged: false
        ))
        // The previous item's duration just went away: the stale clock is replaced.
        #expect(Logic.publishesClock(
            isLive: true, durationMs: 0, stateChanged: false, durationChanged: true
        ))
    }
}

// MARK: - Playback speed

struct PlaybackSpeedTests {
    private typealias Logic = VideoPlayerControllerLogic

    @Test func supportedSpeedsAreTheMenuValues() {
        #expect(Logic.supportedPlaybackSpeeds == [0.5, 0.75, 1, 1.25, 1.5, 2])
    }

    @Test func supportedSpeedsPassThrough() {
        for speed in Logic.supportedPlaybackSpeeds {
            #expect(Logic.sanitizedPlaybackSpeed(speed, isLive: false) == speed)
        }
    }

    /// Live is delivered at 1x; a faster rate only drains the two-second buffer.
    @Test func liveAlwaysPlaysAtNormalSpeed() {
        #expect(Logic.sanitizedPlaybackSpeed(1.5, isLive: true) == 1)
        #expect(Logic.sanitizedPlaybackSpeed(0.5, isLive: true) == 1)
    }

    @Test func outOfRangeRequestsAreClamped() {
        #expect(Logic.sanitizedPlaybackSpeed(4, isLive: false) == 2)
        #expect(Logic.sanitizedPlaybackSpeed(0.1, isLive: false) == 0.5)
    }

    @Test func garbageBecomesNormalSpeed() {
        #expect(Logic.sanitizedPlaybackSpeed(0, isLive: false) == 1)
        #expect(Logic.sanitizedPlaybackSpeed(-2, isLive: false) == 1)
        #expect(Logic.sanitizedPlaybackSpeed(.nan, isLive: false) == 1)
        #expect(Logic.sanitizedPlaybackSpeed(.infinity, isLive: false) == 1)
    }

    /// Hold-for-2x: the hold plays at 2x, and letting go returns to the speed the
    /// user chose, not to 1x ("never implicitly override the chosen playback speed").
    @Test func holdOverridesAndReleaseRestoresTheChosenSpeed() {
        #expect(Logic.engineRate(requested: 2, chosenSpeed: 1.5) == 2)
        #expect(Logic.engineRate(requested: 1, chosenSpeed: 1.5) == 1.5)
        #expect(Logic.engineRate(requested: 1, chosenSpeed: 0.75) == 0.75)
    }

    @Test func withoutAChosenSpeedNothingChanges() {
        #expect(Logic.engineRate(requested: 1, chosenSpeed: 1) == 1)
        #expect(Logic.engineRate(requested: 2, chosenSpeed: 1) == 2)
    }

    @Test func invalidOverrideFallsBackToTheChosenSpeed() {
        #expect(Logic.engineRate(requested: 0, chosenSpeed: 1.25) == 1.25)
        #expect(Logic.engineRate(requested: .nan, chosenSpeed: 1.25) == 1.25)
    }
}

// MARK: - Sleep timer

struct SleepTimerTests {
    private typealias Logic = VideoPlayerControllerLogic

    @Test func minutesBecomeSeconds() {
        #expect(Logic.sleepTimerInterval(minutes: 15) == 900)
        #expect(Logic.sleepTimerInterval(minutes: 60) == 3600)
    }

    @Test func nilOrNonPositiveCancels() {
        #expect(Logic.sleepTimerInterval(minutes: nil) == nil)
        #expect(Logic.sleepTimerInterval(minutes: 0) == nil)
        #expect(Logic.sleepTimerInterval(minutes: -5) == nil)
    }

    @Test func absurdRequestsAreCappedAtADay() {
        #expect(Logic.sleepTimerInterval(minutes: 100_000)
            == TimeInterval(Logic.maximumSleepTimerMinutes) * 60)
        #expect(Logic.maximumSleepTimerMinutes == 24 * 60)
    }
}

// MARK: - Paused resume after a cast

struct PausedResumeTests {
    private typealias Logic = VideoPlayerControllerLogic

    /// The load must autoplay until it is established: `KSPlayerLayer` only prepares
    /// when it is created with autoplay, so pausing earlier would never open the source.
    @Test func nothingHappensBeforeEstablishment() {
        #expect(Logic.pausedResumeStep(
            isEstablished: false, pauseIssued: false, isPaused: true, secondsSinceEstablished: 0
        ) == .wait)
        #expect(Logic.pausedResumeStep(
            isEstablished: false, pauseIssued: false, isPaused: false, secondsSinceEstablished: 0
        ) == .wait)
    }

    /// The first pause does not trust the engine's paused flag: the layer is about
    /// to play whatever the flag says at that instant.
    @Test func firstPauseIsUnconditional() {
        #expect(Logic.pausedResumeStep(
            isEstablished: true, pauseIssued: false, isPaused: true, secondsSinceEstablished: 0
        ) == .pause)
        #expect(Logic.pausedResumeStep(
            isEstablished: true, pauseIssued: false, isPaused: false, secondsSinceEstablished: 0
        ) == .pause)
    }

    /// AVPlayer path: the start seek autoplays when it lands, seconds after ready.
    @Test func layerStartingByItselfInsideTheWindowIsPausedAgain() {
        #expect(Logic.pausedResumeStep(
            isEstablished: true, pauseIssued: true, isPaused: false, secondsSinceEstablished: 3
        ) == .pause)
        #expect(Logic.pausedResumeStep(
            isEstablished: true, pauseIssued: true, isPaused: true, secondsSinceEstablished: 3
        ) == .hold)
    }

    /// After the window the paused state is the player's own; nothing is forced any
    /// more, so playback that starts later is left alone.
    @Test func windowEnds() {
        let end = Logic.pausedResumeEnforceSeconds
        #expect(Logic.pausedResumeStep(
            isEstablished: true, pauseIssued: true, isPaused: false, secondsSinceEstablished: end
        ) == .finish)
        #expect(Logic.pausedResumeStep(
            isEstablished: true, pauseIssued: true, isPaused: true, secondsSinceEstablished: end + 30
        ) == .finish)
        #expect(end == 10)
    }
}

// MARK: - Now Playing

struct NowPlayingPushTests {
    private typealias Logic = VideoPlayerControllerLogic

    private func fields(
        title: String = "Episode 1",
        artist: String = "Series",
        duration: Double = 2700,
        rate: Double = 1,
        isLive: Bool = false,
        artworkID: ObjectIdentifier? = nil
    ) -> Logic.NowPlayingFields {
        Logic.NowPlayingFields(
            title: title, artist: artist, durationSeconds: duration, rate: rate,
            isLive: isLive, artworkID: artworkID
        )
    }

    @Test func firstPushAlwaysGoesOut() {
        #expect(Logic.shouldPushNowPlaying(
            force: false, fields: fields(), pushed: nil,
            elapsed: 0, pushedElapsed: 0, secondsSincePush: 0
        ))
    }

    /// Steady playback: elapsed time advances exactly as the system extrapolates it,
    /// so there is nothing to write, however long it has been.
    @Test func steadyPlaybackWritesNothing() {
        for seconds in [0.2, 1.0, 5.0, 60.0, 600.0] {
            #expect(!Logic.shouldPushNowPlaying(
                force: false, fields: fields(), pushed: fields(),
                elapsed: 100 + seconds, pushedElapsed: 100, secondsSincePush: seconds
            ), "after \(seconds) s")
        }
    }

    /// The extrapolation uses the pushed rate, so 1.5x playback is steady too.
    @Test func steadyPlaybackAtAChosenSpeedWritesNothing() {
        #expect(!Logic.shouldPushNowPlaying(
            force: false, fields: fields(rate: 1.5), pushed: fields(rate: 1.5),
            elapsed: 100 + 60, pushedElapsed: 100, secondsSincePush: 40
        ))
    }

    @Test func pausedPlaybackWritesNothing() {
        #expect(!Logic.shouldPushNowPlaying(
            force: false, fields: fields(rate: 0), pushed: fields(rate: 0),
            elapsed: 100, pushedElapsed: 100, secondsSincePush: 300
        ))
    }

    /// Play, pause and a speed change go out at once (with a fresh elapsed time),
    /// even right after the previous push.
    @Test func playPauseAndSpeedChangesPushImmediately() {
        #expect(Logic.shouldPushNowPlaying(
            force: false, fields: fields(rate: 0), pushed: fields(rate: 1),
            elapsed: 100, pushedElapsed: 100, secondsSincePush: 0.05
        ))
        #expect(Logic.shouldPushNowPlaying(
            force: false, fields: fields(rate: 1.5), pushed: fields(rate: 1),
            elapsed: 100, pushedElapsed: 100, secondsSincePush: 0.05
        ))
    }

    /// Seeks and presentation changes are forced by the controller.
    @Test func forcedPushIgnoresTheMinimumInterval() {
        #expect(Logic.shouldPushNowPlaying(
            force: true, fields: fields(), pushed: fields(),
            elapsed: 100, pushedElapsed: 100, secondsSincePush: 0.01
        ))
    }

    @Test func otherFieldChangesPushAfterTheMinimumInterval() {
        let changed = fields(duration: 2701)
        #expect(!Logic.shouldPushNowPlaying(
            force: false, fields: changed, pushed: fields(),
            elapsed: 100.3, pushedElapsed: 100, secondsSincePush: 0.3
        ))
        #expect(Logic.shouldPushNowPlaying(
            force: false, fields: changed, pushed: fields(),
            elapsed: 101, pushedElapsed: 100, secondsSincePush: 1
        ))
        #expect(Logic.nowPlayingMinimumInterval == 0.8)
    }

    @Test func titleArtistLiveAndArtworkAreFields() {
        final class Token {}
        let token = Token()
        let variants: [Logic.NowPlayingFields] = [
            fields(title: "Episode 2"),
            fields(artist: "Other"),
            fields(isLive: true),
            fields(artworkID: ObjectIdentifier(token)),
        ]
        for variant in variants {
            #expect(Logic.shouldPushNowPlaying(
                force: false, fields: variant, pushed: fields(),
                elapsed: 101, pushedElapsed: 100, secondsSincePush: 1
            ))
        }
    }

    /// A stall, or a seek the player made by itself (start position, live edge):
    /// elapsed time leaves the extrapolation and is pushed again.
    @Test func driftBeyondTheTolerancePushesElapsedTime() {
        // Stalled for 5 s while the system kept counting.
        #expect(Logic.shouldPushNowPlaying(
            force: false, fields: fields(), pushed: fields(),
            elapsed: 100, pushedElapsed: 100, secondsSincePush: 5
        ))
        // Jumped ahead.
        #expect(Logic.shouldPushNowPlaying(
            force: false, fields: fields(), pushed: fields(),
            elapsed: 500, pushedElapsed: 100, secondsSincePush: 1
        ))
        // Tick granularity (the engine publishes every 0.12 s) stays inside it.
        #expect(!Logic.shouldPushNowPlaying(
            force: false, fields: fields(), pushed: fields(),
            elapsed: 110.4, pushedElapsed: 100, secondsSincePush: 10
        ))
        #expect(Logic.nowPlayingDriftToleranceSeconds == 2)
    }

    @Test func extrapolationFollowsThePushedRate() {
        #expect(Logic.extrapolatedElapsed(pushedElapsed: 100, pushedRate: 1, secondsSincePush: 10) == 110)
        #expect(Logic.extrapolatedElapsed(pushedElapsed: 100, pushedRate: 2, secondsSincePush: 10) == 120)
        #expect(Logic.extrapolatedElapsed(pushedElapsed: 100, pushedRate: 0, secondsSincePush: 10) == 100)
        // A clock that went backwards must not rewind the estimate.
        #expect(Logic.extrapolatedElapsed(pushedElapsed: 100, pushedRate: 1, secondsSincePush: -3) == 100)
    }

    // MARK: Repair after KSPlayerLayer rewrote the shared dictionary

    @Test func ourOwnDictionaryIsIntact() {
        #expect(Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Series", durationSeconds: 2700, hasArtwork: false,
            expected: fields()
        ))
        // The library overwrites the duration with its player's value: rounding
        // differences are not a reason to write again.
        #expect(Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Series", durationSeconds: 2700.04, hasArtwork: false,
            expected: fields()
        ))
    }

    /// stop() and deinit set the dictionary to nil.
    @Test func wipedDictionaryIsNotIntact() {
        #expect(!Logic.nowPlayingIsIntact(
            title: nil, artist: nil, durationSeconds: nil, hasArtwork: false, expected: fields()
        ))
    }

    /// At ready the library creates `[duration]` and adds the stream's own metadata
    /// title; the lock screen would show the file's internal title.
    @Test func libraryMadeDictionaryIsNotIntact() {
        #expect(!Logic.nowPlayingIsIntact(
            title: "movie.mkv", artist: nil, durationSeconds: 2700, hasArtwork: false,
            expected: fields()
        ))
        #expect(!Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Encoder", durationSeconds: 2700, hasArtwork: false,
            expected: fields()
        ))
    }

    /// A live item's player duration is not finite; ours says 0 (LIVE badge).
    @Test func foreignDurationIsNotIntact() {
        let live = fields(duration: 0, isLive: true)
        #expect(!Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Series", durationSeconds: .nan, hasArtwork: false,
            expected: live
        ))
        #expect(!Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Series", durationSeconds: 5400, hasArtwork: false,
            expected: fields()
        ))
    }

    @Test func missingArtworkIsNotIntactWhenWeHaveOne() {
        final class Token {}
        let token = Token()
        let withArtwork = fields(artworkID: ObjectIdentifier(token))
        #expect(!Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Series", durationSeconds: 2700, hasArtwork: false,
            expected: withArtwork
        ))
        #expect(Logic.nowPlayingIsIntact(
            title: "Episode 1", artist: "Series", durationSeconds: 2700, hasArtwork: true,
            expected: withArtwork
        ))
    }

    // MARK: Artwork size

    /// MediaPlayer JPEG-encodes what the artwork handler returns; a 2000 px poster
    /// is scaled to 600 px on its longer side, keeping its shape.
    @Test func largePosterIsScaledDown() {
        #expect(Logic.nowPlayingArtworkSize(for: CGSize(width: 2000, height: 3000))
            == CGSize(width: 400, height: 600))
        #expect(Logic.nowPlayingArtworkSize(for: CGSize(width: 1920, height: 1080))
            == CGSize(width: 600, height: 338))
    }

    @Test func smallImagesAreNeverScaledUp() {
        #expect(Logic.nowPlayingArtworkSize(for: CGSize(width: 300, height: 450))
            == CGSize(width: 300, height: 450))
        #expect(Logic.nowPlayingArtworkSize(for: CGSize(width: 600, height: 600))
            == CGSize(width: 600, height: 600))
    }

    @Test func extremeShapesKeepAtLeastOnePoint() {
        #expect(Logic.nowPlayingArtworkSize(for: CGSize(width: 10_000, height: 4))
            == CGSize(width: 600, height: 1))
        #expect(Logic.nowPlayingArtworkSize(for: .zero) == .zero)
    }
}

// MARK: - Delayed retry after a rejected zap

struct ZapRetryDecisionTests {
    private typealias Logic = VideoPlayerControllerLogic

    /// A new-content load that just failed with a non-recoverable error, no retry
    /// pending, no cast, a request to reload. Each test changes what it is about.
    private func decision(
        retryAlreadyScheduled: Bool = false,
        castOwnsContent: Bool = false,
        hadHealthyStretch: Bool = false,
        failureIsRecoverable: Bool = false,
        hasLoadRequest: Bool = true,
        failureWantsDelayedRetry: Bool = false,
        isLiveStream: Bool = false,
        replacedActiveLayer: Bool = false
    ) -> Logic.ZapRetryDecision {
        Logic.zapRetryDecision(
            retryAlreadyScheduled: retryAlreadyScheduled,
            castOwnsContent: castOwnsContent,
            hadHealthyStretch: hadHealthyStretch,
            failureIsRecoverable: failureIsRecoverable,
            hasLoadRequest: hasLoadRequest,
            failureWantsDelayedRetry: failureWantsDelayedRetry,
            isLiveStream: isLiveStream,
            replacedActiveLayer: replacedActiveLayer
        )
    }

    /// HTTP 403 before playback: the panel still counts the previous connection.
    /// Any content, also a first open and a film.
    @Test func forbiddenBeforePlaybackRetriesWhateverTheContent() {
        #expect(decision(failureWantsDelayedRetry: true) == .afterForbidden)
        #expect(decision(
            failureWantsDelayedRetry: true, isLiveStream: true, replacedActiveLayer: true
        ) == .afterForbidden)
        #expect(Logic.forbiddenRetryDelaySeconds == 1)
    }

    /// A live zap over a running layer, rejected with some other error (a panel
    /// that answers the overlap with 404, 5xx or a closed connection).
    @Test func rejectedLiveZapOverARunningLayerRetries() {
        #expect(decision(isLiveStream: true, replacedActiveLayer: true) == .afterReplacedLiveLayer)
    }

    /// Without an overlap there is nothing a wait would fix: a first open, a zap
    /// away from a channel that had already failed, and films.
    @Test func noOverlapOrNotLiveShowsTheFailure() {
        #expect(decision(isLiveStream: true, replacedActiveLayer: false) == .none)
        #expect(decision(isLiveStream: false, replacedActiveLayer: true) == .none)
        #expect(decision() == .none)
    }

    /// Timeout / unreachable belong to the immediate silent retry; a dead channel
    /// must not get a third attempt.
    @Test func recoverableFailuresAreLeftToTheSilentRetry() {
        #expect(decision(
            failureIsRecoverable: true, isLiveStream: true, replacedActiveLayer: true
        ) == .none)
        #expect(decision(failureIsRecoverable: true, failureWantsDelayedRetry: true) == .none)
    }

    /// The post-cast retry already took this failure: one reload, not two.
    @Test func aRetryAlreadyScheduledIsNotDoubled() {
        #expect(decision(retryAlreadyScheduled: true, failureWantsDelayedRetry: true) == .none)
        #expect(decision(
            retryAlreadyScheduled: true, isLiveStream: true, replacedActiveLayer: true
        ) == .none)
    }

    /// A reload next to a cast would be a second connection to the stream.
    @Test func neverWhileACastOwnsTheContent() {
        #expect(decision(castOwnsContent: true, failureWantsDelayedRetry: true) == .none)
        #expect(decision(
            castOwnsContent: true, isLiveStream: true, replacedActiveLayer: true
        ) == .none)
    }

    /// A failure after a healthy stretch has nothing to do with the zap any more.
    @Test func failureAfterAHealthyStretchIsNotAZapRejection() {
        #expect(decision(hadHealthyStretch: true, failureWantsDelayedRetry: true) == .none)
        #expect(decision(
            hadHealthyStretch: true, isLiveStream: true, replacedActiveLayer: true
        ) == .none)
    }

    @Test func nothingToReloadMeansNoRetry() {
        #expect(decision(hasLoadRequest: false, failureWantsDelayedRetry: true) == .none)
    }
}

// MARK: - Skips while a cast presents

struct CastSkipTargetTests {
    private typealias Logic = VideoPlayerControllerLogic

    @Test func withoutAPendingSeekTheReportedTimeIsTheBase() {
        #expect(Logic.castSkipBase(
            reportedSeconds: 100, pendingTargetSeconds: nil, secondsSinceTarget: 0
        ) == 100)
    }

    /// The receiver still reports its pre-seek time: the skip adds to the target.
    @Test func receiverStillOnItsWayUsesTheTarget() {
        #expect(Logic.castSkipBase(
            reportedSeconds: 100.3, pendingTargetSeconds: 115, secondsSinceTarget: 0.4
        ) == 115)
        // Backwards too.
        #expect(Logic.castSkipBase(
            reportedSeconds: 100.2, pendingTargetSeconds: 85, secondsSinceTarget: 0.3
        ) == 85)
    }

    /// The cast publishes the target at once; reading it back changes nothing.
    @Test func optimisticallyPublishedTargetIsTheBaseEitherWay() {
        #expect(Logic.castSkipBase(
            reportedSeconds: 115, pendingTargetSeconds: 115, secondsSinceTarget: 0.1
        ) == 115)
    }

    /// Once the receiver is where the seek put it, its own time is the truth:
    /// right at the target (inside the 1 s seek tolerance) and after playing on.
    @Test func landedSeekUsesTheReportedTime() {
        #expect(Logic.castSkipBase(
            reportedSeconds: 114.2, pendingTargetSeconds: 115, secondsSinceTarget: 0.8
        ) == 114.2)
        #expect(Logic.castSkipBase(
            reportedSeconds: 116.5, pendingTargetSeconds: 115, secondsSinceTarget: 1.5
        ) == 116.5)
        // Four seconds of playback after the seek: still the receiver's time, not
        // the target it has long passed.
        #expect(Logic.castSkipBase(
            reportedSeconds: 119, pendingTargetSeconds: 115, secondsSinceTarget: 4.5
        ) == 119)
        // Hold-for-2x after the seek.
        #expect(Logic.castSkipBase(
            reportedSeconds: 121, pendingTargetSeconds: 115, secondsSinceTarget: 3
        ) == 121)
    }

    /// A seek that never landed must not pin later skips to its target.
    @Test func targetExpires() {
        let age = Logic.castSeekTargetMaxAgeSeconds
        #expect(Logic.castSkipBase(
            reportedSeconds: 100, pendingTargetSeconds: 115, secondsSinceTarget: age
        ) == 100)
        #expect(Logic.castSkipBase(
            reportedSeconds: 100, pendingTargetSeconds: 115, secondsSinceTarget: age - 0.1
        ) == 115)
        #expect(age == 5)
    }

    /// A wall clock that went backwards gives no usable age.
    @Test func negativeAgeFallsBackToTheReportedTime() {
        #expect(Logic.castSkipBase(
            reportedSeconds: 100, pendingTargetSeconds: 115, secondsSinceTarget: -3
        ) == 100)
    }

    @Test func garbageReportedTimeUsesTheTarget() {
        #expect(Logic.castSkipBase(
            reportedSeconds: .nan, pendingTargetSeconds: 115, secondsSinceTarget: 1
        ) == 115)
    }

    /// The landing band must be wider than the cast player's seek tolerance (1 s),
    /// or a seek that landed on a keyframe just before the target reads as pending.
    @Test func landedToleranceIsAboveTheSeekTolerance() {
        #expect(Logic.castSeekLandedToleranceSeconds > 1)
    }

    /// The symptom: +15 twice in quick succession lands on +30, not +15.
    @Test func quickTapsAccumulate() {
        #expect(Logic.castSkipTarget(
            reportedSeconds: 100.3, pendingTargetSeconds: 115, secondsSinceTarget: 0.4,
            delta: 15, durationSeconds: 3600
        ) == 130)
        #expect(Logic.castSkipTarget(
            reportedSeconds: 99.8, pendingTargetSeconds: 70, secondsSinceTarget: 0.6,
            delta: -15, durationSeconds: 3600
        ) == 55)
    }

    @Test func aLoneTapMovesByItsInterval() {
        #expect(Logic.castSkipTarget(
            reportedSeconds: 100, pendingTargetSeconds: nil, secondsSinceTarget: 0,
            delta: 15, durationSeconds: 3600
        ) == 115)
    }

    @Test func targetStaysInsideTheContent() {
        #expect(Logic.castSkipTarget(
            reportedSeconds: 5, pendingTargetSeconds: nil, secondsSinceTarget: 0,
            delta: -15, durationSeconds: 3600
        ) == 0)
        #expect(Logic.castSkipTarget(
            reportedSeconds: 3590, pendingTargetSeconds: nil, secondsSinceTarget: 0,
            delta: 15, durationSeconds: 3600
        ) == 3600)
        // Accumulated taps cannot run past the end either.
        #expect(Logic.castSkipTarget(
            reportedSeconds: 3570, pendingTargetSeconds: 3595, secondsSinceTarget: 0.3,
            delta: 15, durationSeconds: 3600
        ) == 3600)
    }

    /// No duration yet (a cast still preparing): only the lower bound applies.
    @Test func unknownDurationOnlyBoundsAtZero() {
        #expect(Logic.castSkipTarget(
            reportedSeconds: 50, pendingTargetSeconds: nil, secondsSinceTarget: 0,
            delta: 15, durationSeconds: 0
        ) == 65)
        #expect(Logic.castSkipTarget(
            reportedSeconds: 5, pendingTargetSeconds: nil, secondsSinceTarget: 0,
            delta: -15, durationSeconds: 0
        ) == 0)
    }
}

// MARK: - AirPlay capability while a load opens

struct AirPlayCapabilityPendingTests {
    private typealias Logic = VideoPlayerControllerLogic

    /// Between the load start and the engine's codec facts: not known yet.
    @Test func openingLoadIsPending() {
        #expect(Logic.isAirPlayCapabilityPending(
            capable: false, hasLoadRequest: true, isPlaybackEstablished: false,
            hasFailure: false, delayedRetryScheduled: false
        ))
    }

    /// A verdict ends it, whichever way it went.
    @Test func aVerdictEndsIt() {
        #expect(!Logic.isAirPlayCapabilityPending(
            capable: true, hasLoadRequest: true, isPlaybackEstablished: false,
            hasFailure: false, delayedRetryScheduled: false
        ))
        // Established and not castable (an unsupported codec, audio only).
        #expect(!Logic.isAirPlayCapabilityPending(
            capable: false, hasLoadRequest: true, isPlaybackEstablished: true,
            hasFailure: false, delayedRetryScheduled: false
        ))
    }

    @Test func nothingLoadedIsNotPending() {
        #expect(!Logic.isAirPlayCapabilityPending(
            capable: false, hasLoadRequest: false, isPlaybackEstablished: false,
            hasFailure: false, delayedRetryScheduled: false
        ))
    }

    /// A failure on screen ends the wait; one hidden behind a delayed retry does
    /// not, or the slot would blink for the second the retry waits.
    @Test func shownFailureEndsItHiddenFailureDoesNot() {
        #expect(!Logic.isAirPlayCapabilityPending(
            capable: false, hasLoadRequest: true, isPlaybackEstablished: false,
            hasFailure: true, delayedRetryScheduled: false
        ))
        #expect(Logic.isAirPlayCapabilityPending(
            capable: false, hasLoadRequest: true, isPlaybackEstablished: false,
            hasFailure: true, delayedRetryScheduled: true
        ))
    }
}
