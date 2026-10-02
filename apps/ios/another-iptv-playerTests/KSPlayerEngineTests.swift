import AVFoundation
import Foundation
import KSPlayer
import Testing
@testable import another_iptv_player

/// Decisions of `KSPlayerEngine` that do not need a player: the engine has no seam for
/// a fake `KSPlayerLayer`, so its seek, start-position, audio-delay and end-of-stream
/// rules live in pure functions and are locked here.

// MARK: - Seek target clamp and skip accumulation

struct SeekTargetTests {
    private typealias Math = KSPlayerEngineMath

    @Test func targetInsideTheItemIsKept() {
        #expect(Math.clampedSeekTarget(0, duration: 3600) == 0)
        #expect(Math.clampedSeekTarget(125.5, duration: 3600) == 125.5)
    }

    @Test func negativeTargetBecomesZero() {
        #expect(Math.clampedSeekTarget(-15, duration: 3600) == 0)
        #expect(Math.clampedSeekTarget(-15, duration: 0) == 0)
    }

    /// Landing on the end would finish the item again immediately.
    @Test func targetStopsJustBelowTheEnd() {
        let limit = 3600 - Math.seekEndMargin
        #expect(Math.clampedSeekTarget(3600, duration: 3600) == limit)
        #expect(Math.clampedSeekTarget(5000, duration: 3600) == limit)
        #expect(limit < 3600)
    }

    /// Live streams and items that have not reported a length yet have no upper bound.
    @Test func unknownDurationDoesNotClampTheUpperEnd() {
        #expect(Math.clampedSeekTarget(5000, duration: 0) == 5000)
        #expect(Math.clampedSeekTarget(5000, duration: .nan) == 5000)
        #expect(Math.clampedSeekTarget(5000, duration: .infinity) == 5000)
    }

    @Test func veryShortItemNeverYieldsANegativeTarget() {
        #expect(Math.clampedSeekTarget(10, duration: 0.2) == 0)
    }

    @Test func nonFiniteTargetBecomesZero() {
        #expect(Math.clampedSeekTarget(.nan, duration: 3600) == 0)
        #expect(Math.clampedSeekTarget(.infinity, duration: 0) == 0)
    }

    /// Without a pending seek a skip starts from the published position.
    @Test func skipStartsFromThePosition() {
        let target = Math.accumulatedSeekTarget(
            position: 100, pendingTarget: nil, delta: 15, duration: 3600
        )
        #expect(target == 115)
    }

    /// While paused the position never advances, so three taps must add up through the
    /// pending target instead of repeating the same jump.
    @Test func burstOfSkipsAccumulatesOnThePendingTarget() {
        var pending: TimeInterval?
        for _ in 0..<3 {
            pending = Math.accumulatedSeekTarget(
                position: 100, pendingTarget: pending, delta: 15, duration: 3600
            )
        }
        #expect(pending == 145)
    }

    @Test func skipsInBothDirectionsCancelOut() {
        let forward = Math.accumulatedSeekTarget(
            position: 100, pendingTarget: nil, delta: 15, duration: 3600
        )
        let back = Math.accumulatedSeekTarget(
            position: 100, pendingTarget: forward, delta: -15, duration: 3600
        )
        #expect(back == 100)
    }

    @Test func accumulatedSkipIsClamped() {
        #expect(Math.accumulatedSeekTarget(position: 5, pendingTarget: nil, delta: -15, duration: 3600) == 0)
        #expect(
            Math.accumulatedSeekTarget(position: 0, pendingTarget: 3590, delta: 15, duration: 3600)
                == 3600 - Math.seekEndMargin
        )
    }
}

// MARK: - Start position on the AVPlayer path

struct PendingStartTests {
    private typealias Math = KSPlayerEngineMath

    /// KSAVPlayer ignores `KSOptions.startPlayTime`; the engine seeks once it can.
    @Test func avPlayerSeeksToTheStartOnceSeekable() {
        let action = Math.pendingStartAction(
            start: 1200, isFFmpegPlayer: false, isSeekable: true, duration: 3600
        )
        #expect(action == .seek(1200))
    }

    @Test func avPlayerWaitsUntilTheItemCanSeek() {
        let action = Math.pendingStartAction(
            start: 1200, isFFmpegPlayer: false, isSeekable: false, duration: 3600
        )
        #expect(action == .wait)
    }

    /// The FFmpeg player already opened at `startPlayTime`; a second seek would reopen
    /// the connection for nothing.
    @Test func ffmpegPlayerNeverSeeksASecondTime() {
        #expect(
            Math.pendingStartAction(start: 1200, isFFmpegPlayer: true, isSeekable: true, duration: 3600)
                == .discard
        )
        #expect(
            Math.pendingStartAction(start: 1200, isFFmpegPlayer: true, isSeekable: false, duration: 0)
                == .discard
        )
    }

    @Test func startBeyondTheEndIsClamped() {
        let action = Math.pendingStartAction(
            start: 4000, isFFmpegPlayer: false, isSeekable: true, duration: 3600
        )
        #expect(action == .seek(3600 - Math.seekEndMargin))
    }

    @Test func meaninglessStartIsDropped() {
        #expect(Math.pendingStartAction(start: 0, isFFmpegPlayer: false, isSeekable: true, duration: 3600) == .discard)
        #expect(Math.pendingStartAction(start: .nan, isFFmpegPlayer: false, isSeekable: true, duration: 3600) == .discard)
    }
}

// MARK: - Audio delay

struct AudioDelayTests {
    private typealias Math = KSPlayerEngineMath

    /// "Positive values delay the audio": the video has to run ahead of the audio clock,
    /// which is a negative `KSOptions.videoDelay`.
    @Test func settingIsNegatedForTheVideoClock() {
        #expect(Math.videoDelay(forAudioDelay: 0.5, isFFmpegPlayer: true, hasEnabledAudioTrack: true) == -0.5)
        #expect(Math.videoDelay(forAudioDelay: -0.25, isFFmpegPlayer: true, hasEnabledAudioTrack: true) == 0.25)
    }

    @Test func avPlayerGetsNoDelay() {
        #expect(Math.videoDelay(forAudioDelay: 0.5, isFFmpegPlayer: false, hasEnabledAudioTrack: true) == 0)
    }

    /// Without audio the FFmpeg player paces video against its own clock; an offset
    /// would become slow motion or dropped frames.
    @Test func videoOnlyStreamGetsNoDelay() {
        #expect(Math.videoDelay(forAudioDelay: 0.5, isFFmpegPlayer: true, hasEnabledAudioTrack: false) == 0)
    }

    @Test func zeroAndNonFiniteSettingsGiveZero() {
        let zero = Math.videoDelay(forAudioDelay: 0, isFFmpegPlayer: true, hasEnabledAudioTrack: true)
        #expect(zero == 0)
        #expect(zero.sign == .plus)
        #expect(Math.videoDelay(forAudioDelay: .nan, isFFmpegPlayer: true, hasEnabledAudioTrack: true) == 0)
        #expect(Math.videoDelay(forAudioDelay: .infinity, isFFmpegPlayer: true, hasEnabledAudioTrack: true) == 0)
    }
}

// MARK: - End of a live stream

struct LiveStreamEndTests {
    private typealias Math = KSPlayerEngineMath

    @Test func liveLoadWithoutDurationEndsAsLiveStream() {
        #expect(Math.isLiveStreamEnd(isLive: true, duration: 0))
        #expect(Math.isLiveStreamEnd(isLive: true, duration: .nan))
    }

    /// The M3U classifier labels unknown URLs as live; a finite file must still end
    /// like a film instead of reloading forever.
    @Test func finiteFileLabelledLiveEndsNormally() {
        #expect(!Math.isLiveStreamEnd(isLive: true, duration: 5400))
    }

    @Test func vodNeverEndsAsLiveStream() {
        #expect(!Math.isLiveStreamEnd(isLive: false, duration: 0))
        #expect(!Math.isLiveStreamEnd(isLive: false, duration: 5400))
    }

    /// VOD behaviour is unchanged: a finished film restarts from the beginning.
    @Test func finishedSeekableItemRestarts() {
        #expect(
            Math.playAction(isCompleted: true, isSeekable: true, liveStreamEnded: false, canReload: true)
                == .restartFromBeginning
        )
        #expect(
            Math.playAction(isCompleted: true, isSeekable: true, liveStreamEnded: false, canReload: false)
                == .restartFromBeginning
        )
    }

    /// Seeking a non-seekable source to 0 does nothing; only a new load can play it.
    @Test func finishedNonSeekableItemAsksForAReload() {
        #expect(
            Math.playAction(isCompleted: true, isSeekable: false, liveStreamEnded: false, canReload: true)
                == .reload
        )
    }

    @Test func endedLiveStreamAsksForAReloadEvenBeforeItIsMarkedCompleted() {
        #expect(
            Math.playAction(isCompleted: false, isSeekable: false, liveStreamEnded: true, canReload: true)
                == .reload
        )
        #expect(
            Math.playAction(isCompleted: true, isSeekable: true, liveStreamEnded: true, canReload: true)
                == .reload
        )
    }

    /// Without a reload handler the previous behaviour is kept.
    @Test func withoutAReloadHandlerTheSeekToZeroIsKept() {
        #expect(
            Math.playAction(isCompleted: true, isSeekable: false, liveStreamEnded: true, canReload: false)
                == .restartFromBeginning
        )
    }

    @Test func playingItemSimplyResumes() {
        #expect(
            Math.playAction(isCompleted: false, isSeekable: true, liveStreamEnded: false, canReload: true)
                == .resume
        )
        #expect(
            Math.playAction(isCompleted: false, isSeekable: false, liveStreamEnded: false, canReload: true)
                == .resume
        )
    }
}

// MARK: - Container name and buffered range

struct EngineStatePublishingTests {
    private typealias Math = KSPlayerEngineMath

    @Test func containerNameIsWhatFFmpegDetected() {
        #expect(Math.containerFormatName(isFFmpegPlayer: true, detected: "mpegts") == "mpegts")
        #expect(
            Math.containerFormatName(isFFmpegPlayer: true, detected: "matroska,webm") == "matroska,webm"
        )
    }

    /// `KSOptions.formatName` starts as an empty string and is only written once the
    /// source has opened.
    @Test func containerNameIsNilUntilTheSourceOpened() {
        #expect(Math.containerFormatName(isFFmpegPlayer: true, detected: "") == nil)
        #expect(Math.containerFormatName(isFFmpegPlayer: true, detected: nil) == nil)
    }

    /// After a swap to AVPlayer the options still hold the name of the FFmpeg attempt.
    @Test func containerNameIsNilOnTheAVPlayerPath() {
        #expect(Math.containerFormatName(isFFmpegPlayer: false, detected: "mpegts") == nil)
        #expect(Math.containerFormatName(isFFmpegPlayer: false, detected: nil) == nil)
    }

    /// A seek resets the buffered end; the player's old value must not come back
    /// before the seek has landed.
    @Test func bufferedEndIsHeldBackWhileASeekIsPending() {
        #expect(Math.publishesBufferTimeline(playable: 42, seekPending: false))
        #expect(!Math.publishesBufferTimeline(playable: 42, seekPending: true))
        #expect(!Math.publishesBufferTimeline(playable: .nan, seekPending: false))
        #expect(!Math.publishesBufferTimeline(playable: .infinity, seekPending: false))
    }

    /// The codec gates the AirPlay button, so a time tick keeps reading the track list
    /// until it is known.
    @Test func trackFactsAreReadOnEveryTickUntilTheCodecIsKnown() {
        #expect(Math.refreshesTrackFacts(videoCodecKnown: false, now: 100, lastRefresh: 100))
        #expect(Math.refreshesTrackFacts(videoCodecKnown: false, now: 100.12, lastRefresh: 100))
    }

    /// Afterwards the list is read on a slow heartbeat, not eight times a second.
    @Test func trackFactsAreReadOnAHeartbeatOnceTheCodecIsKnown() {
        let interval = Math.trackFactsInterval
        #expect(interval == 2)
        #expect(!Math.refreshesTrackFacts(videoCodecKnown: true, now: 100.12, lastRefresh: 100))
        #expect(!Math.refreshesTrackFacts(videoCodecKnown: true, now: 100 + interval - 0.01, lastRefresh: 100))
        #expect(Math.refreshesTrackFacts(videoCodecKnown: true, now: 100 + interval, lastRefresh: 100))
        // A new load resets the time of the last read to 0.
        #expect(Math.refreshesTrackFacts(videoCodecKnown: true, now: 100, lastRefresh: 0))
    }

    /// The times are wall-clock readings; a clock that was set back must not stop
    /// the heartbeat until it has caught up.
    @Test func trackFactsHeartbeatSurvivesAClockSetBack() {
        #expect(Math.refreshesTrackFacts(videoCodecKnown: true, now: 40, lastRefresh: 100))
    }
}

// MARK: - Failure classification (FFmpeg errors reach the engine)

struct PlaybackFailureTests {
    private typealias Policy = KSPlayerLoadPolicy
    private typealias Libav = KSPlayerLoadPolicy.LibavError

    private func ffmpegFailure(_ stage: KSPlayerErrorCode, _ avCode: Int32) -> Policy.Failure {
        Policy.failure(domain: KSPlayerErrorDomain, code: stage.rawValue, avErrorCode: avCode)
    }

    @Test func httpStatusesGetTheirOwnMessage() {
        #expect(ffmpegFailure(.formatOpenInput, Libav.httpUnauthorized.code) == .unauthorized)
        #expect(ffmpegFailure(.formatOpenInput, Libav.httpForbidden.code) == .forbidden)
        #expect(ffmpegFailure(.formatOpenInput, Libav.httpNotFound.code) == .notFound)
        #expect(Policy.Failure.unauthorized.messageKey == "playback.error.unauthorized")
        #expect(Policy.Failure.forbidden.messageKey == "playback.error.forbidden")
        #expect(Policy.Failure.notFound.messageKey == "playback.error.not_found")
    }

    /// The server has answered: neither a silent retry nor a second request from
    /// another player can change a 4xx.
    @Test func httpStatusesAreNeitherRetriedNorRescued() {
        let codes = [
            Libav.httpBadRequest.code, Libav.httpUnauthorized.code, Libav.httpForbidden.code,
            Libav.httpNotFound.code, Libav.httpOther4xx.code, Libav.httpServerError.code,
        ]
        for code in codes {
            let failure = ffmpegFailure(.formatOpenInput, code)
            #expect(!failure.isRecoverable, "\(code) must not be retried silently")
            #expect(!failure.isAVPlayerRescueCandidate, "\(code) must not reach AVPlayer")
        }
        #expect(ffmpegFailure(.formatOpenInput, Libav.httpOther4xx.code) == .other)
        #expect(ffmpegFailure(.formatOpenInput, Libav.httpServerError.code) == .other)
    }

    /// A connection-limited panel answers a zap with 403 while it still counts the
    /// previous channel's socket. That is the one HTTP status worth a later attempt,
    /// and it stays apart from the immediate silent retry.
    @Test func onlyForbiddenAsksForADelayedRetry() {
        #expect(ffmpegFailure(.formatOpenInput, Libav.httpForbidden.code).isDelayedRetryCandidate)
        #expect(Policy.Failure.forbidden.isDelayedRetryCandidate)
        #expect(!Policy.Failure.forbidden.isRecoverable)
        #expect(!Policy.Failure.forbidden.isAVPlayerRescueCandidate)
        let others: [Policy.Failure] = [
            .unauthorized, .notFound, .timeout, .unreachable, .unreadableSource, .openFailed, .other,
        ]
        for failure in others {
            #expect(!failure.isDelayedRetryCandidate, "\(failure) must not be retried after a delay")
        }
        // The other HTTP statuses have no case of their own and are not candidates either.
        let codes = [
            Libav.httpBadRequest.code, Libav.httpUnauthorized.code, Libav.httpNotFound.code,
            Libav.httpOther4xx.code, Libav.httpServerError.code,
        ]
        for code in codes {
            #expect(!ffmpegFailure(.formatOpenInput, code).isDelayedRetryCandidate, "\(code)")
        }
    }

    @Test func timeoutsAreRecoverable() {
        #expect(ffmpegFailure(.formatOpenInput, -ETIMEDOUT) == .timeout)
        #expect(ffmpegFailure(.readFrame, -ETIMEDOUT) == .timeout)
        #expect(Policy.Failure.timeout.isRecoverable)
        #expect(Policy.Failure.timeout.messageKey == "playback.error.timeout")
    }

    @Test func resetsAndUnreachableHostsAreRecoverable() {
        for code in [ECONNRESET, ECONNREFUSED, EHOSTUNREACH, ENETUNREACH, EPIPE, EIO] {
            #expect(ffmpegFailure(.formatOpenInput, -code) == .unreachable, "errno \(code) at open")
            #expect(ffmpegFailure(.readFrame, -code) == .unreachable, "errno \(code) mid-stream")
        }
        #expect(Policy.Failure.unreachable.isRecoverable)
        #expect(!Policy.Failure.unreachable.isAVPlayerRescueCandidate)
        #expect(Policy.Failure.unreachable.messageKey == "playback.error.cannot_reach")
    }

    /// What FFmpeg returns for an extensionless HLS or MP4 link it cannot probe.
    @Test func unrecognisedDataAtOpenIsARescueCandidate() {
        let failure = ffmpegFailure(.formatOpenInput, Libav.invalidData.code)
        #expect(failure == .unreadableSource)
        #expect(failure.isAVPlayerRescueCandidate)
        #expect(!failure.isRecoverable)
        #expect(failure.messageKey == "playback.error.unsupported")
        #expect(ffmpegFailure(.formatFindStreamInfo, Libav.invalidData.code) == .unreadableSource)
        #expect(ffmpegFailure(.formatOpenInput, Libav.demuxerNotFound.code) == .unreadableSource)
    }

    @Test func otherOpenErrorsAreRescueCandidatesToo() {
        let failure = ffmpegFailure(.formatOpenInput, -ENOENT)
        #expect(failure == .openFailed)
        #expect(failure.isAVPlayerRescueCandidate)
        #expect(failure.messageKey == "playback.error.failed_to_start")
    }

    /// Broken data in the middle of a stream says nothing about the container, and
    /// AVPlayer would restart the title from its original position.
    @Test func midStreamErrorsAreNeverRescueCandidates() {
        #expect(ffmpegFailure(.readFrame, Libav.invalidData.code) == .other)
        #expect(ffmpegFailure(.readFrame, -ENOENT) == .other)
        #expect(!Policy.Failure.other.isAVPlayerRescueCandidate)
        #expect(Policy.Failure.other.messageKey == "playback.error.failed_check_network")
    }

    /// The reader was interrupted by a shutdown; that is not a verdict on the source.
    @Test func interruptedOpenIsNotARescueCandidate() {
        #expect(ffmpegFailure(.formatOpenInput, Libav.exit.code) == .other)
    }

    @Test func urlErrorsKeepTheirMapping() {
        func urlFailure(_ code: Int) -> Policy.Failure {
            Policy.failure(domain: NSURLErrorDomain, code: code, avErrorCode: nil)
        }
        #expect(urlFailure(NSURLErrorTimedOut) == .timeout)
        #expect(urlFailure(NSURLErrorCannotFindHost) == .unreachable)
        #expect(urlFailure(NSURLErrorCannotConnectToHost) == .unreachable)
        #expect(urlFailure(NSURLErrorNotConnectedToInternet) == .unreachable)
        #expect(urlFailure(NSURLErrorBadServerResponse) == .other)
    }

    @Test func unknownDomainsAndMissingCodesAreGeneric() {
        #expect(Policy.failure(domain: AVFoundationErrorDomain, code: -11800, avErrorCode: nil) == .other)
        #expect(
            Policy.failure(
                domain: KSPlayerErrorDomain, code: KSPlayerErrorCode.formatCreate.rawValue, avErrorCode: nil
            ) == .other
        )
    }

    /// Pins how KSPlayer hands over the libav code at the pinned revision.
    @Test func libavCodeIsReadFromTheUnderlyingError() {
        let error = NSError(errorCode: .formatOpenInput, avErrorCode: Libav.httpForbidden.code)
        #expect(error.domain == KSPlayerErrorDomain)
        #expect(Policy.underlyingAVErrorCode(of: error) == Libav.httpForbidden.code)
        let failure = Policy.failure(
            domain: error.domain, code: error.code,
            avErrorCode: Policy.underlyingAVErrorCode(of: error)
        )
        #expect(failure == .forbidden)
        #expect(Policy.underlyingAVErrorCode(of: NSError(domain: NSURLErrorDomain, code: -1001)) == nil)
    }

    @Test func rescueRunsOncePerFFmpegOnlyLoadBeforeItIsReady() {
        func rescue(
            _ failure: Policy.Failure, ffmpegOnly: Bool = true, ran: Bool = false, established: Bool = false
        ) -> Bool {
            Policy.shouldRescueWithAVPlayer(
                failure, isFFmpegOnlyLoad: ffmpegOnly, rescueAlreadyRan: ran,
                isPlaybackEstablished: established
            )
        }
        #expect(rescue(.unreadableSource))
        #expect(rescue(.openFailed))
        #expect(!rescue(.unreadableSource, ran: true))
        #expect(!rescue(.unreadableSource, ffmpegOnly: false))
        #expect(!rescue(.unreadableSource, established: true))
        for failure in [Policy.Failure.unauthorized, .forbidden, .notFound, .timeout, .unreachable, .other] {
            #expect(!rescue(failure), "\(failure) must not start an AVPlayer attempt")
        }
    }
}

// MARK: - Undecodable tracks at ready

struct UndecodableMediaTypeTests {
    private typealias Policy = KSPlayerLoadPolicy

    /// H.264 video with WavPack-only audio: the audio queue would never fill.
    @Test func mediaTypeWithOnlyUndecodableTracksFails() {
        #expect(Policy.hasUndecodableMediaType(videoTrackIDs: [0], audioTrackIDs: [1], undecodable: [1]))
        #expect(Policy.hasUndecodableMediaType(videoTrackIDs: [0], audioTrackIDs: [1, 2], undecodable: [1, 2]))
        #expect(Policy.hasUndecodableMediaType(videoTrackIDs: [0], audioTrackIDs: [], undecodable: [0]))
    }

    /// One decodable alternative is enough: the guard selects it.
    @Test func decodableAlternativeKeepsTheLoadAlive() {
        #expect(!Policy.hasUndecodableMediaType(videoTrackIDs: [0], audioTrackIDs: [1, 2], undecodable: [1]))
        #expect(!Policy.hasUndecodableMediaType(videoTrackIDs: [0], audioTrackIDs: [1], undecodable: []))
    }

    @Test func missingMediaTypeIsNotAFailure() {
        #expect(!Policy.hasUndecodableMediaType(videoTrackIDs: [], audioTrackIDs: [1], undecodable: []))
        #expect(!Policy.hasUndecodableMediaType(videoTrackIDs: [], audioTrackIDs: [], undecodable: [7]))
    }

    /// Cover art is taken out of the video list before the check, so an audio file
    /// with a PNG picture is not reported as unsupported.
    @Test func coverArtCodecsAreRecognised() {
        #expect(Policy.isStillImageCodec("png"))
        #expect(Policy.isStillImageCodec("PNG (something)"))
        #expect(Policy.isStillImageCodec("mjpeg (Baseline)"))
        #expect(!Policy.isStillImageCodec("h264 (High)"))
        #expect(!Policy.isStillImageCodec("theora"))
        #expect(!Policy.isStillImageCodec(""))
    }
}

// MARK: - Progress watchdog after ready

struct ProgressWatchdogTests {
    private typealias Watchdog = KSPlayerLoadPolicy.ProgressWatchdog

    private func sample(
        playing: Bool = true, buffering: Bool = true, bytes: Int64 = 1000, playable: TimeInterval = 0
    ) -> Watchdog.Sample {
        Watchdog.Sample(isPlaying: playing, isBuffering: buffering, bytesRead: bytes, playableTime: playable)
    }

    /// Ticks needed to accumulate `seconds`.
    private func ticks(_ seconds: TimeInterval) -> Int {
        Int((seconds / Watchdog.tickInterval).rounded(.up))
    }

    @Test func noFirstFrameAndNoDataFailsAfterTheIdleLimit() {
        var watchdog = Watchdog(isLive: true)
        // The first sample always counts as progress: nothing was seen before it.
        #expect(watchdog.tick(sample()) == .healthy)
        let needed = ticks(Watchdog.firstFrameIdleLimit)
        for _ in 0..<(needed - 1) {
            #expect(watchdog.tick(sample()) == .healthy)
        }
        #expect(watchdog.tick(sample()) == .firstFrameTimeout)
    }

    /// A slow start that keeps receiving data must not be failed by a flat limit.
    @Test func slowStartThatStillReceivesDataIsLeftAlone() {
        var watchdog = Watchdog(isLive: false)
        var bytes: Int64 = 0
        for _ in 0..<60 {
            bytes += 50_000
            #expect(watchdog.tick(sample(bytes: bytes)) == .healthy)
        }
        #expect(!watchdog.hasPlayed)
    }

    /// FFmpeg HLS reads its segments through nested contexts the byte counter does
    /// not see; growing queues count as progress as well.
    @Test func growingBufferCountsAsProgress() {
        var watchdog = Watchdog(isLive: false)
        var playable: TimeInterval = 0
        for _ in 0..<60 {
            playable += 0.2
            #expect(watchdog.tick(sample(playable: playable)) == .healthy)
        }
    }

    @Test func nonFinitePlayableTimeIsNotProgress() {
        var watchdog = Watchdog(isLive: false)
        var verdict = Watchdog.Verdict.healthy
        for _ in 0...ticks(Watchdog.firstFrameIdleLimit) {
            verdict = watchdog.tick(sample(playable: .nan))
        }
        #expect(verdict == .firstFrameTimeout)
    }

    @Test func pausedPlaybackNeverFails() {
        var watchdog = Watchdog(isLive: true)
        for _ in 0..<100 {
            #expect(watchdog.tick(sample(playing: false)) == .healthy)
        }
        #expect(watchdog.idleSeconds == 0)
        #expect(watchdog.bufferingSeconds == 0)
    }

    /// A pause in the middle of a stall starts the count over.
    @Test func pauseResetsTheCount() {
        var watchdog = Watchdog(isLive: true)
        for _ in 0..<(ticks(Watchdog.firstFrameIdleLimit) - 1) {
            _ = watchdog.tick(sample())
        }
        #expect(watchdog.tick(sample(playing: false)) == .healthy)
        #expect(watchdog.tick(sample()) == .healthy)
        #expect(watchdog.idleSeconds == Watchdog.tickInterval)
    }

    /// Live cannot wait: data that trickles in too slowly to play is a stall too.
    @Test func liveFailsAfterAnUninterruptedRebufferEvenWithData() {
        var watchdog = Watchdog(isLive: true)
        #expect(watchdog.tick(sample(buffering: false)) == .healthy)
        #expect(watchdog.hasPlayed)
        var bytes: Int64 = 1000
        let needed = ticks(Watchdog.liveStallLimit)
        for _ in 0..<(needed - 1) {
            bytes += 500
            #expect(watchdog.tick(sample(bytes: bytes)) == .healthy)
        }
        bytes += 500
        #expect(watchdog.tick(sample(bytes: bytes)) == .stalled)
    }

    @Test func playingAgainEndsTheRebufferCount() {
        var watchdog = Watchdog(isLive: true)
        watchdog.notePlaying()
        for _ in 0..<(ticks(Watchdog.liveStallLimit) - 1) {
            #expect(watchdog.tick(sample()) == .healthy)
        }
        // The layer reported `.bufferFinished` between two ticks.
        watchdog.notePlaying()
        #expect(watchdog.bufferingSeconds == 0)
        #expect(watchdog.tick(sample()) == .healthy)
    }

    /// A slow link that still delivers may need longer than any fixed limit to refill.
    @Test func vodRebufferWithDataIsLeftAlone() {
        var watchdog = Watchdog(isLive: false)
        watchdog.notePlaying()
        var bytes: Int64 = 0
        for _ in 0..<100 {
            bytes += 20_000
            #expect(watchdog.tick(sample(bytes: bytes)) == .healthy)
        }
    }

    @Test func vodRebufferWithoutDataFailsAfterTheIdleLimit() {
        var watchdog = Watchdog(isLive: false)
        watchdog.notePlaying()
        #expect(watchdog.tick(sample()) == .healthy)
        let needed = ticks(Watchdog.vodStallIdleLimit)
        for _ in 0..<(needed - 1) {
            #expect(watchdog.tick(sample()) == .healthy)
        }
        #expect(watchdog.tick(sample()) == .stalled)
    }

    @Test func limitsStayInTheirIntendedOrder() {
        #expect(Watchdog.tickInterval > 0)
        #expect(Watchdog.firstFrameIdleLimit == 12)
        #expect(Watchdog.liveStallLimit == 20)
        #expect(Watchdog.vodStallIdleLimit > Watchdog.liveStallLimit)
    }
}

// MARK: - Background video suspension (FFmpeg path)

private struct StubCapacity: CapacityProtocol {
    var fps: Float = 25
    var packetCount = 0
    var frameCount = 0
    var frameMaxCount = 16
    var isEndOfFile = false
    var mediaType: AVFoundation.AVMediaType
}

struct BackgroundVideoSuspensionTests {
    private typealias Policy = KSPlayerLoadPolicy

    private func background(
        playing: Bool = true, pip: Bool = false, video: Bool = true, audio: Bool = true,
        live: Bool = true, seekable: Bool = false, byteSeek: Bool = false
    ) -> Policy.BackgroundAction {
        Policy.backgroundAction(
            isPlaying: playing, isPictureInPictureActive: pip, hasEnabledVideoTrack: video,
            hasEnabledAudioTrack: audio, isLive: live, isSeekable: seekable, seeksByBytes: byteSeek
        )
    }

    @Test func playingStreamWithoutPiPIsSuspended() {
        #expect(background() == .suspendVideo)
        #expect(background(live: false, seekable: true) == .suspendVideo)
    }

    /// PiP draws the frames; its window can be closed later while still in background.
    @Test func activePiPIsCheckedAgainInsteadOfSuspended() {
        #expect(background(pip: true) == .checkAgain)
        #expect(background(playing: false, pip: true) == .checkAgain)
    }

    @Test func pausedOrSingleTrackPlaybackIsLeftAlone() {
        #expect(background(playing: false) == .leave)
        #expect(background(video: false) == .leave)
        #expect(background(audio: false) == .leave)
    }

    /// The return seek of a byte-seeking container would rewind to where the picture
    /// stopped; live has no seek on return and is not affected.
    @Test func seekableByteSeekingVODIsLeftAlone() {
        #expect(background(live: false, seekable: true, byteSeek: true) == .leave)
        #expect(background(live: false, seekable: false, byteSeek: true) == .suspendVideo)
        #expect(background(live: true, seekable: true, byteSeek: true) == .suspendVideo)
    }

    @Test func suspensionWaitsAFewSeconds() {
        #expect(Policy.backgroundSuspendDelay >= 3)
        #expect(Policy.backgroundSuspendDelay <= 10)
    }

    @Test func returnPathDependsOnTheContent() {
        #expect(Policy.foregroundAction(isPlaying: true, isLive: true, canReload: true, canSeek: false) == .reload)
        #expect(
            Policy.foregroundAction(isPlaying: true, isLive: false, canReload: true, canSeek: true)
                == .seekToCurrentPosition
        )
    }

    /// Paused playback must stay paused, and without a reload handler or a seekable
    /// source only the player's own track switch is left.
    @Test func returnFallsBackToTheTrackSwitch() {
        #expect(Policy.foregroundAction(isPlaying: false, isLive: true, canReload: true, canSeek: false) == .reselectTrack)
        #expect(Policy.foregroundAction(isPlaying: false, isLive: false, canReload: true, canSeek: true) == .reselectTrack)
        #expect(Policy.foregroundAction(isPlaying: true, isLive: true, canReload: false, canSeek: false) == .reselectTrack)
        #expect(Policy.foregroundAction(isPlaying: true, isLive: false, canReload: true, canSeek: false) == .reselectTrack)
    }

    @Test func mpegContainersSeekByBytes() {
        #expect(DemuxerProbe.seeksByBytes(formatName: "mpegts"))
        #expect(!DemuxerProbe.seeksByBytes(formatName: "matroska,webm"))
        #expect(!DemuxerProbe.seeksByBytes(formatName: "mov,mp4,m4a,3gp,3g2,mj2"))
        #expect(!DemuxerProbe.seeksByBytes(formatName: "ogg"))
        #expect(!DemuxerProbe.seeksByBytes(formatName: ""))
        #expect(!DemuxerProbe.seeksByBytes(formatName: "not-a-demuxer"))
    }

    @Test func audioCapacitiesAreSingledOut() {
        let video = StubCapacity(mediaType: .video)
        let audio = StubCapacity(mediaType: .audio)
        #expect(GuardedKSOptions.audioCapacities(of: [video, audio]).map(\.mediaType) == [.audio])
        // Without audio the full list stays: an empty one reads as "end of file".
        #expect(GuardedKSOptions.audioCapacities(of: [video]).map(\.mediaType) == [.video])
    }

    /// A flushed, switched-off video track stays empty. Counted, it would keep the
    /// player in buffering for good; ignored, the audio decides.
    @Test func suspendedVideoDoesNotHoldBackPlayback() {
        let options = GuardedKSOptions()
        let emptyVideo = StubCapacity(mediaType: .video)
        let fullAudio = StubCapacity(fps: 50, packetCount: 400, frameCount: 50, mediaType: .audio)
        let tracks: [CapacityProtocol] = [emptyVideo, fullAudio]

        #expect(!options.playable(capacitys: tracks, isFirst: false, isSeek: false).isPlayable)

        options.isVideoSuspended = true
        let suspended = options.playable(capacitys: tracks, isFirst: false, isSeek: false)
        #expect(suspended.isPlayable)
        #expect(suspended.frameCount == 50)
        #expect(!suspended.isEndOfFile)

        options.isVideoSuspended = false
        #expect(!options.playable(capacitys: tracks, isFirst: false, isSeek: false).isPlayable)
    }
}

// MARK: - KSPlayerLayer's repeating timer (leaked on every zap)

@MainActor
struct KSPlayerLayerTimerTests {
    /// Pins the private property name the guard reads at the pinned KSPlayer revision.
    /// Nothing is opened: the layer is built without autoplay and never prepared.
    @Test func progressTimerIsFoundAndInvalidated() {
        let previousFirst = KSOptions.firstPlayerType
        KSOptions.firstPlayerType = KSMEPlayer.self
        defer { KSOptions.firstPlayerType = previousFirst }
        let options = GuardedKSOptions()
        // No Metal view: the test only needs the layer's stored properties.
        options.videoDisable = true
        options.registerRemoteControll = false
        let layer = KSPlayerLayer(
            url: URL(fileURLWithPath: "/dev/null"), isAutoPlay: false, options: options
        )
        defer { layer.stop() }

        // The lazy timer does not exist until the layer plays or pauses.
        #expect(KSPlayerRunLoopGuard.progressTimer(of: layer) == nil)
        #expect(!KSPlayerRunLoopGuard.invalidateProgressTimer(of: layer))

        layer.pause()
        let timer = KSPlayerRunLoopGuard.progressTimer(of: layer)
        #expect(timer != nil, "KSPlayerLayer no longer stores a lazy `timer`")
        #expect(timer?.timeInterval == 0.1)
        #expect(timer?.isValid == true)

        #expect(KSPlayerRunLoopGuard.invalidateProgressTimer(of: layer))
        #expect(timer?.isValid == false)
    }

    /// The same timer drives the position and the subtitle cues. KSPlayer schedules it
    /// in the default run-loop mode only, where it stops while a list scrolls.
    @Test func progressTimerIsPromotedToTheCommonModesOnceItExists() throws {
        let previousFirst = KSOptions.firstPlayerType
        KSOptions.firstPlayerType = KSMEPlayer.self
        defer { KSOptions.firstPlayerType = previousFirst }
        let options = GuardedKSOptions()
        options.videoDisable = true
        options.registerRemoteControll = false
        let layer = KSPlayerLayer(
            url: URL(fileURLWithPath: "/dev/null"), isAutoPlay: false, options: options
        )
        defer {
            KSPlayerRunLoopGuard.invalidateProgressTimer(of: layer)
            layer.stop()
        }

        // Before the layer has played or paused there is nothing to promote, and
        // asking must not create the timer.
        #expect(!KSPlayerRunLoopGuard.promoteProgressTimer(of: layer))
        #expect(KSPlayerRunLoopGuard.progressTimer(of: layer) == nil)

        layer.pause()
        let timer = try #require(KSPlayerRunLoopGuard.progressTimer(of: layer))
        let mainLoop = CFRunLoopGetMain()
        #expect(CFRunLoopContainsTimer(mainLoop, timer, .defaultMode))
        #expect(!CFRunLoopContainsTimer(mainLoop, timer, .commonModes))

        #expect(KSPlayerRunLoopGuard.promoteProgressTimer(of: layer))
        #expect(CFRunLoopContainsTimer(mainLoop, timer, .commonModes))
        // `pause()` parked the timer; promoting it must not make it fire. (The run
        // loop clamps the parked date, so it is not compared with `distantFuture`.)
        #expect(timer.fireDate.timeIntervalSinceNow > 365 * 86_400)
        // A second call finds it promoted already and changes nothing.
        #expect(KSPlayerRunLoopGuard.promoteProgressTimer(of: layer))
        #expect(timer.isValid)

        // A released layer's timer is gone for good.
        #expect(KSPlayerRunLoopGuard.invalidateProgressTimer(of: layer))
        #expect(!KSPlayerRunLoopGuard.promoteProgressTimer(of: layer))
        #expect(!CFRunLoopContainsTimer(mainLoop, timer, .commonModes))
    }
}
