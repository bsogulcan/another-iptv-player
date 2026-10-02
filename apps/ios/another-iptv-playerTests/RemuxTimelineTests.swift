import Foundation
import Testing
@testable import another_iptv_player

/// Table tests for the cast controller's source-time bookkeeping, and for the rows
/// of its pure decisions that CastControllerLogicTests does not reach: the runtime
/// phase of the error mapping, the agreement between the three start-failure
/// functions, and the full input grids of the small predicates.
/// (ios-player-airplay-review.md, cast-state-machine-10: the first step that needs
/// no seams in CastController.)

// MARK: - RemuxTimeline

struct RemuxTimelineTests {
    /// The local HLS timeline starts at 0 and stands for `offset` seconds inside the
    /// source: what the scrubber shows is offset + local.
    @Test func sourceTimeIsOffsetPlusLocal() {
        let rows: [(offset: TimeInterval, local: TimeInterval, source: TimeInterval)] = [
            (0, 0, 0),
            (0, 12.5, 12.5),
            (600, 0, 600),
            (600, 12.5, 612.5),
            (5400.25, 0.5, 5400.75),
        ]
        for row in rows {
            let timeline = RemuxTimeline(offset: row.offset, knownDuration: 0)
            #expect(timeline.sourceTime(fromLocal: row.local) == row.source, "\(row)")
        }
    }

    /// A seek target in source time becomes a position on the local timeline. A
    /// target before the session's start has no local position: it clamps to 0, the
    /// first thing this session wrote, and never goes negative.
    @Test func localTargetIsSourceMinusOffsetAndNeverNegative() {
        let rows: [(offset: TimeInterval, source: TimeInterval, local: TimeInterval)] = [
            (0, 0, 0),
            (0, 30, 30),
            (600, 612.5, 12.5),
            (600, 7200, 6600),
            (600, 600, 0),
            (600, 599, 0),
            (600, 0, 0),
            (600, -5, 0),
        ]
        for row in rows {
            let timeline = RemuxTimeline(offset: row.offset, knownDuration: 0)
            #expect(timeline.localTarget(forSource: row.source) == row.local, "\(row)")
        }
    }

    /// Reporting a position and seeking back to it lands on the same local time;
    /// a target before the offset comes back as the offset itself.
    @Test func sourceAndLocalTimeRoundTrip() {
        for offset: TimeInterval in [0, 600, 3599.5] {
            let timeline = RemuxTimeline(offset: offset, knownDuration: 0)
            for local: TimeInterval in [0, 0.25, 12, 1800] {
                let source = timeline.sourceTime(fromLocal: local)
                #expect(timeline.localTarget(forSource: source) == local, "offset \(offset), local \(local)")
            }
            for early: TimeInterval in [0, offset / 2, offset] {
                let local = timeline.localTarget(forSource: early)
                #expect(timeline.sourceTime(fromLocal: local) == offset, "offset \(offset), target \(early)")
            }
        }
    }

    /// A session whose input seek failed remuxes from 0:00 and reports offset 0;
    /// so does every live session. Local time is then source time.
    @Test func zeroOffsetIsTheIdentity() {
        let timeline = RemuxTimeline(offset: 0, knownDuration: 5400)
        for seconds: TimeInterval in [0, 1.5, 754, 5399] {
            #expect(timeline.sourceTime(fromLocal: seconds) == seconds)
            #expect(timeline.localTarget(forSource: seconds) == seconds)
        }
    }

    /// The real source duration, when known, is what the scrubber shows: it does
    /// not depend on how much this session has written, nor on where it started.
    @Test func knownDurationIsTheTotal() {
        let rows: [(offset: TimeInterval, local: TimeInterval)] = [
            (0, 0), (0, 120), (600, 120), (5300, 60),
            // The written range overshoots the stated duration (container metadata
            // a little short): the stated duration still wins.
            (5300, 200),
        ]
        for row in rows {
            let timeline = RemuxTimeline(offset: row.offset, knownDuration: 5400)
            #expect(timeline.totalDuration(localPlayerDuration: row.local) == 5400, "\(row)")
        }
    }

    /// Unknown duration (0, or a negative value from a container that reports
    /// none): the total is the range written so far, which grows with the playlist.
    @Test func unknownDurationFollowsTheWrittenRange() {
        let rows: [(known: TimeInterval, offset: TimeInterval, local: TimeInterval, total: TimeInterval)] = [
            (0, 0, 0, 0),
            (0, 0, 42, 42),
            (0, 600, 0, 600),
            (0, 600, 120, 720),
            (-1, 600, 120, 720),
        ]
        for row in rows {
            let timeline = RemuxTimeline(offset: row.offset, knownDuration: row.known)
            #expect(timeline.totalDuration(localPlayerDuration: row.local) == row.total, "\(row)")
        }
    }

    /// A seek refresh replaces the timeline: same film, new offset. The two values
    /// differ, and the same source second maps to different local times.
    @Test func timelinesWithDifferentOffsetsAreDifferentValues() {
        let before = RemuxTimeline(offset: 0, knownDuration: 5400)
        var after = before
        #expect(after == before)
        after.offset = 1800
        #expect(after != before)
        #expect(before.localTarget(forSource: 1830) == 1830)
        #expect(after.localTarget(forSource: 1830) == 30)
        #expect(after.totalDuration(localPlayerDuration: 30) == before.totalDuration(localPlayerDuration: 1830))
        #expect(RemuxTimeline(offset: 0, knownDuration: 0) != before)
    }
}

// MARK: - Decision tables

struct CastDecisionTableTests {
    typealias RemuxError = RemuxHLSWriter.RemuxError

    private static func sessionError(_ code: AirPlayRemuxSession.ErrorCode) -> Error {
        NSError(domain: AirPlayRemuxSession.errorDomain, code: code.rawValue)
    }

    /// AVERROR_EXIT: what a read carries when the writer's stall watchdog cut it.
    private static let avErrorExit: Int32 = -1_414_092_869
    /// AVERROR_HTTP_FORBIDDEN: a panel at its connection limit answering 403.
    private static let avErrorHTTPForbidden: Int32 = -858_797_304

    /// Every error a session start or a running session can report.
    private static let errors: [Error] = [
        RemuxError.openInputFailed(-5),
        RemuxError.openInputFailed(-ETIMEDOUT),
        RemuxError.openInputFailed(avErrorHTTPForbidden),
        RemuxError.noCompatibleStreams,
        RemuxError.openOutputFailed(-22),
        RemuxError.openOutputFailed(-ENOSPC),
        RemuxError.writeFailed(-22),
        RemuxError.writeFailed(-ENOSPC),
        RemuxError.readFailed(-5),
        RemuxError.readFailed(avErrorExit),
        RemuxError.videoParametersUnknown,
        RemuxError.audioParametersUnknown,
        RemuxError.timestampDiscontinuity,
        sessionError(.noLANAddress),
        sessionError(.playlistTimeout),
        sessionError(.localServerUnreachable),
        sessionError(.listenerNotReady),
        NSError(domain: "SomeOtherDomain", code: 2),
        CocoaError(.fileWriteOutOfSpace),
        URLError(.timedOut),
    ]

    /// The three start-failure functions agree for every error: a spent retry
    /// always ends the cast with the start-phase reason, and a fresh failure
    /// retries exactly when (and for as long as) `startRetryDelay` says so.
    @Test func startFailureActionAgreesWithRetryDelayAndEndReason() {
        for error in Self.errors {
            let reason = CastController.endReason(for: error, duringStart: true)
            #expect(
                CastController.startFailureAction(retryUsed: true, error: error) == .endCast(reason),
                "\(error)"
            )
            let fresh: CastController.StartFailureAction
            if let delay = CastController.startRetryDelay(for: error) {
                fresh = .retry(after: delay)
                // A retry of zero seconds would reopen into the connection that is
                // still closing.
                #expect(delay > 0, "\(error)")
            } else {
                fresh = .endCast(reason)
            }
            #expect(
                CastController.startFailureAction(retryUsed: false, error: error) == fresh,
                "\(error)"
            )
        }
    }

    /// A failure always tells the user something, in either phase, and it is never
    /// blamed on the user, the route or the receiver.
    @Test func noErrorEndsTheCastSilentlyOrBlamesTheReceiver() {
        let notAnErrorReason: [CastEndReason] = [
            .userStopped, .contentChanged, .routeDropped, .noDeviceSelected,
            .receiverFailed, .receiverUnreachable,
        ]
        for error in Self.errors {
            for duringStart in [true, false] {
                let reason = CastController.endReason(for: error, duringStart: duringStart)
                #expect(!reason.isSilent, "\(error), duringStart \(duringStart)")
                #expect(reason.messageKey != nil, "\(error), duringStart \(duringStart)")
                #expect(!notAnErrorReason.contains(reason), "\(error), duringStart \(duringStart)")
            }
        }
    }

    /// Writer errors after the cast was running: the rows CastErrorMappingTests
    /// leaves out. These are what the user reads when the in-place rebuild has
    /// been used up.
    @Test func writerErrorsWhileCasting() {
        let rows: [(error: RemuxError, reason: CastEndReason)] = [
            (.openInputFailed(-5), .sourceOpenFailed),
            (.noCompatibleStreams, .incompatibleStreams),
            (.openOutputFailed(-22), .incompatibleStreams),
            (.videoParametersUnknown, .sourceTooSlow),
            // A copied audio stream whose sample rate probing never found.
            (.audioParametersUnknown, .sourceTooSlow),
            // The stall watchdog cutting a blocked read.
            (.readFailed(Self.avErrorExit), .sourceLost),
            // fMP4 cannot splice a restarted source clock; the rebuild did not help.
            (.timestampDiscontinuity, .sourceLost),
        ]
        for row in rows {
            #expect(
                CastController.endReason(for: row.error, duringStart: false) == row.reason,
                "\(row.error)"
            )
        }
    }

    /// The session's own error codes name their cause; the phase does not change it.
    @Test func sessionErrorCodesMeanTheSameInBothPhases() {
        let rows: [(code: AirPlayRemuxSession.ErrorCode, reason: CastEndReason)] = [
            (.noLANAddress, .noWiFi),
            (.playlistTimeout, .sourceTooSlow),
            (.localServerUnreachable, .localServerUnavailable),
            // A listener without a port: the phone's server, not the Wi-Fi.
            (.listenerNotReady, .localServerUnavailable),
        ]
        for row in rows {
            let error = Self.sessionError(row.code)
            #expect(CastController.endReason(for: error, duringStart: true) == row.reason, "\(row.code)")
            #expect(CastController.endReason(for: error, duringStart: false) == row.reason, "\(row.code)")
        }
    }

    /// All eight inputs of the receiver watchdog: only "no fetch, no progress"
    /// leaves doubt, and only while playing is that doubt a verdict.
    @Test func receiverWatchdogTruthTable() {
        typealias Verdict = CastController.ReceiverWatchdogVerdict
        let rows: [(fetched: Bool, advanced: Bool, paused: Bool, verdict: Verdict)] = [
            (false, false, false, .unreachable),
            (false, false, true, .waitLonger),
            (false, true, false, .healthy),
            (false, true, true, .healthy),
            (true, false, false, .healthy),
            (true, false, true, .healthy),
            (true, true, false, .healthy),
            (true, true, true, .healthy),
        ]
        for row in rows {
            #expect(
                CastController.receiverWatchdogVerdict(
                    receiverFetched: row.fetched, timeAdvanced: row.advanced, isPaused: row.paused
                ) == row.verdict,
                "\(row)"
            )
        }
    }

    /// Whatever the pause bookkeeping says, direct playback resumes paused only
    /// after a cast that is paused and not finished.
    @Test func resumeIsNeverPausedWithoutAPausedUnfinishedCast() {
        let elapsedValues: [TimeInterval?] = [nil, 0, 5.9, CastController.exitPauseAttributionSeconds, 600]
        for byTransport in [false, true] {
            for elapsed in elapsedValues {
                #expect(!CastController.resumeStartsPaused(
                    castPaused: false, pausedByTransportCall: byTransport,
                    secondsSincePauseObserved: elapsed, isCompleted: false
                ), "playing, transport \(byTransport), \(String(describing: elapsed))")
                #expect(!CastController.resumeStartsPaused(
                    castPaused: false, pausedByTransportCall: byTransport,
                    secondsSincePauseObserved: elapsed, isCompleted: true
                ), "playing and finished, transport \(byTransport), \(String(describing: elapsed))")
                #expect(!CastController.resumeStartsPaused(
                    castPaused: true, pausedByTransportCall: byTransport,
                    secondsSincePauseObserved: elapsed, isCompleted: true
                ), "finished, transport \(byTransport), \(String(describing: elapsed))")
            }
        }
        // The attribution window is closed at its end: one tick short is still the
        // ending's own pause.
        #expect(!CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: false,
            secondsSincePauseObserved: CastController.exitPauseAttributionSeconds - 0.001,
            isCompleted: false
        ))
    }

    /// The edges of "behind the served window": one second of slack before the
    /// window start, and no verdict until the player reports a range past 2 s.
    @Test func servedWindowBoundaries() {
        #expect(!CastController.isBehindServedWindow(localTime: 19, windowStart: 20, windowEnd: 30))
        #expect(CastController.isBehindServedWindow(localTime: 18.999, windowStart: 20, windowEnd: 30))
        #expect(!CastController.isBehindServedWindow(localTime: 0, windowStart: 1.9, windowEnd: 2))
        #expect(CastController.isBehindServedWindow(localTime: 0, windowStart: 1.9, windowEnd: 2.001))
        // At or past the end of the window is ahead, not behind.
        #expect(!CastController.isBehindServedWindow(localTime: 30, windowStart: 20, windowEnd: 30))
        #expect(!CastController.isBehindServedWindow(localTime: 45, windowStart: 20, windowEnd: 30))
    }

    /// Over a grid of playheads and windows the three live-window functions stay
    /// consistent: a seek target exists exactly when the playhead is behind, it
    /// lies inside the window and ahead of the playhead, and the self-heal is the
    /// same verdict gated by "playing" and "no live-edge seek settling".
    @Test func liveWindowFunctionsAgreeOverAGrid() {
        let localTimes: [TimeInterval] = [0, 5, 18.5, 19, 19.5, 25, 31]
        let windows: [(start: TimeInterval, end: TimeInterval)] = [
            (0, 0), (0, 2), (0, 30), (1.5, 2), (10, 11), (10, 30), (20, 30), (20, 21.5),
        ]
        for localTime in localTimes {
            for window in windows {
                let label = "local \(localTime), window \(window)"
                let behind = CastController.isBehindServedWindow(
                    localTime: localTime, windowStart: window.start, windowEnd: window.end
                )
                let target = CastController.liveResumeSeekTarget(
                    localTime: localTime, windowStart: window.start, windowEnd: window.end
                )
                #expect((target != nil) == behind, "\(label)")
                if let target {
                    #expect(target >= window.start, "\(label)")
                    #expect(target <= window.end, "\(label)")
                    #expect(target > localTime, "\(label)")
                }
                for isPaused in [false, true] {
                    for settling in [false, true] {
                        #expect(
                            CastController.shouldSelfHeal(
                                localTime: localTime, windowStart: window.start, windowEnd: window.end,
                                isPaused: isPaused, liveEdgeSeekSettling: settling
                            ) == (behind && !isPaused && !settling),
                            "\(label), paused \(isPaused), settling \(settling)"
                        )
                    }
                }
            }
        }
        // The grid must contain both verdicts, or the checks above prove nothing.
        #expect(CastController.isBehindServedWindow(localTime: 5, windowStart: 20, windowEnd: 30))
        #expect(!CastController.isBehindServedWindow(localTime: 25, windowStart: 20, windowEnd: 30))
    }
}
