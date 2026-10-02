import Foundation
import Testing
@testable import another_iptv_player

/// Regression locks for the pure decisions behind the cast state machine and the
/// player controller's retry logic. CastController has no session seam, so the
/// decisions live in small static functions and are tested here in isolation.
/// (Source: ios-player-airplay-review.md.)

// MARK: - Cast end reasons: what is told to the user, what stays silent

struct CastEndReasonTests {
    private static let allReasons: [CastEndReason] = [
        .userStopped, .contentChanged, .routeDropped, .noDeviceSelected, .noWiFi,
        .localServerUnavailable, .sourceOpenFailed, .sourceTooSlow, .incompatibleStreams,
        .sourceLost, .receiverFailed, .receiverUnreachable, .routeHasNoVideo, .storageFull,
    ]

    /// An explicit stop or cancel, a content change and a confirmed route drop are the
    /// user's own doing: no notice. Everything else must say something.
    @Test func onlyUserCausedEndingsAreSilent() {
        let silent = Self.allReasons.filter(\.isSilent)
        #expect(silent == [.userStopped, .contentChanged, .routeDropped])
    }

    /// The picker timeout with no device chosen is NOT silent: the stream reloads by
    /// itself 30 s after the tap and the user is owed a reason.
    @Test func pickerTimeoutGetsAMessage() {
        #expect(!CastEndReason.noDeviceSelected.isSilent)
        #expect(CastEndReason.noDeviceSelected.messageKey == "player.airplay.notice.no_device")
    }

    @Test func messageKeyExistsExactlyForAudibleReasons() {
        for reason in Self.allReasons {
            #expect((reason.messageKey == nil) == reason.isSilent, "\(reason)")
        }
    }

    /// The keys are a contract with the string tables; each reason has its own.
    @Test func messageKeysMatchTheStringContract() {
        let keys = Self.allReasons.compactMap(\.messageKey)
        #expect(Set(keys).count == keys.count, "two reasons share a message")
        #expect(Set(keys) == [
            "player.airplay.notice.no_wifi",
            "player.airplay.notice.no_local_server",
            "player.airplay.notice.source_open_failed",
            "player.airplay.notice.source_too_slow",
            "player.airplay.notice.incompatible",
            "player.airplay.notice.source_lost",
            "player.airplay.notice.receiver_failed",
            "player.airplay.notice.receiver_unreachable",
            "player.airplay.notice.no_video_on_route",
            "player.airplay.notice.no_device",
            "player.airplay.notice.storage_full",
        ])
    }

    /// A cast that ends because the route never took the picture reloads the stream
    /// on the phone by itself: the user is owed the reason.
    @Test func routeWithoutVideoGetsItsOwnMessage() {
        #expect(!CastEndReason.routeHasNoVideo.isSilent)
        #expect(CastEndReason.routeHasNoVideo.messageKey == "player.airplay.notice.no_video_on_route")
        #expect(CastEndReason.routeHasNoVideo != .receiverUnreachable)
        #expect(CastEndReason.routeHasNoVideo != .routeDropped)
    }

    /// Two notices with the same reason are still two notices (the UI reacts to change).
    @Test func noticesWithTheSameReasonDifferById() {
        #expect(CastNotice(id: 1, reason: .noWiFi) != CastNotice(id: 2, reason: .noWiFi))
        #expect(CastNotice(id: 1, reason: .noWiFi) == CastNotice(id: 1, reason: .noWiFi))
    }
}

// MARK: - Error → reason mapping

struct CastErrorMappingTests {
    typealias RemuxError = RemuxHLSWriter.RemuxError

    private func sessionError(_ code: AirPlayRemuxSession.ErrorCode) -> NSError {
        NSError(domain: AirPlayRemuxSession.errorDomain, code: code.rawValue)
    }

    @Test func sessionErrorCodes() {
        #expect(CastController.endReason(for: sessionError(.noLANAddress), duringStart: true) == .noWiFi)
        #expect(CastController.endReason(for: sessionError(.playlistTimeout), duringStart: true) == .sourceTooSlow)
        #expect(CastController.endReason(for: sessionError(.localServerUnreachable), duringStart: true)
            == .localServerUnavailable)
    }

    /// A listener that started without a port is the phone's own server failing. It
    /// used to be reported as "no LAN address", which told the user to connect to
    /// Wi-Fi; the phase does not change what it means.
    @Test func listenerWithoutAPortIsALocalServerFailure() {
        #expect(CastController.endReason(for: sessionError(.listenerNotReady), duringStart: true)
            == .localServerUnavailable)
        #expect(CastController.endReason(for: sessionError(.listenerNotReady), duringStart: false)
            == .localServerUnavailable)
        #expect(CastController.endReason(for: sessionError(.listenerNotReady), duringStart: true) != .noWiFi)
        #expect(AirPlayRemuxSession.ErrorCode.listenerNotReady.rawValue == 4)
    }

    @Test func writerErrorsDuringStart() {
        #expect(CastController.endReason(for: RemuxError.openInputFailed(-5), duringStart: true)
            == .sourceOpenFailed)
        #expect(CastController.endReason(for: RemuxError.noCompatibleStreams, duringStart: true)
            == .incompatibleStreams)
        #expect(CastController.endReason(for: RemuxError.openOutputFailed(-22), duringStart: true)
            == .incompatibleStreams)
        #expect(CastController.endReason(for: RemuxError.writeFailed(-22), duringStart: true)
            == .incompatibleStreams)
        #expect(CastController.endReason(for: RemuxError.readFailed(-5), duringStart: true)
            == .sourceOpenFailed)
        // No keyframe in the probe window even after the retry: worth another try by
        // the user, so it must not read as "cannot be cast".
        #expect(CastController.endReason(for: RemuxError.videoParametersUnknown, duringStart: true)
            == .sourceTooSlow)
        // The same for an audio stream that still has no sample rate after probing:
        // it used to surface as openOutputFailed(-22), i.e. "cannot be cast".
        #expect(CastController.endReason(for: RemuxError.audioParametersUnknown, duringStart: true)
            == .sourceTooSlow)
        #expect(CastController.endReason(for: RemuxError.audioParametersUnknown, duringStart: false)
            == .sourceTooSlow)
    }

    @Test func writerErrorsWhileCasting() {
        #expect(CastController.endReason(for: RemuxError.readFailed(-5), duringStart: false) == .sourceLost)
        #expect(CastController.endReason(for: RemuxError.writeFailed(-22), duringStart: false) == .sourceLost)
    }

    /// "Storage full" is claimed only for ENOSPC; any other write failure is a mux error.
    @Test func storageFullOnlyForENOSPC() {
        #expect(CastController.endReason(for: RemuxError.writeFailed(-ENOSPC), duringStart: false)
            == .storageFull)
        #expect(CastController.endReason(for: RemuxError.writeFailed(-ENOSPC), duringStart: true)
            == .storageFull)
        #expect(CastController.endReason(for: RemuxError.openOutputFailed(-ENOSPC), duringStart: true)
            == .storageFull)
        #expect(CastController.endReason(for: RemuxError.writeFailed(-EIO), duringStart: false)
            != .storageFull)
        #expect(CastController.endReason(for: RemuxError.readFailed(-ENOSPC), duringStart: false)
            != .storageFull)

        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        #expect(CastController.endReason(for: posix, duringStart: true) == .storageFull)
        let cocoa = NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
            userInfo: [NSUnderlyingErrorKey: posix]
        )
        #expect(CastController.endReason(for: cocoa, duringStart: true) == .storageFull)
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: posix]
        )
        #expect(CastController.endReason(for: wrapped, duringStart: true) == .storageFull)
    }

    /// Unknown errors: at start they come from the local side (listener, temp
    /// directory), at runtime from the source.
    @Test func unknownErrorsFallBackByPhase() {
        let unknown = NSError(domain: "SomeOtherDomain", code: 42)
        #expect(CastController.endReason(for: unknown, duringStart: true) == .localServerUnavailable)
        #expect(CastController.endReason(for: unknown, duringStart: false) == .sourceLost)
        // A code of another domain that happens to equal a session code is not a session error.
        let lookalike = NSError(domain: "SomeOtherDomain", code: AirPlayRemuxSession.ErrorCode.noLANAddress.rawValue)
        #expect(CastController.endReason(for: lookalike, duringStart: true) != .noWiFi)
    }

    @Test func preflightFailures() {
        #expect(CastController.endReason(forPreflight: .noLANAddress) == .noWiFi)
        #expect(CastController.endReason(forPreflight: .serverUnavailable) == .localServerUnavailable)
    }

    /// One retry for transient start failures: 8 s for connection-limit collisions,
    /// about 2 s when only the video or audio parameters were missing; nothing else
    /// retries.
    @Test func startRetryDelays() {
        #expect(CastController.startRetryDelay(for: RemuxError.openInputFailed(-5)) == 8)
        #expect(CastController.startRetryDelay(for: sessionError(.playlistTimeout)) == 8)
        #expect(CastController.startRetryDelay(for: RemuxError.videoParametersUnknown) == 2)
        #expect(CastController.startRetryDelay(for: RemuxError.audioParametersUnknown) == 2)

        #expect(CastController.startRetryDelay(for: RemuxError.noCompatibleStreams) == nil)
        #expect(CastController.startRetryDelay(for: RemuxError.openOutputFailed(-22)) == nil)
        #expect(CastController.startRetryDelay(for: RemuxError.writeFailed(-ENOSPC)) == nil)
        #expect(CastController.startRetryDelay(for: sessionError(.noLANAddress)) == nil)
        #expect(CastController.startRetryDelay(for: sessionError(.listenerNotReady)) == nil)
        #expect(CastController.startRetryDelay(for: sessionError(.localServerUnreachable)) == nil)
        #expect(CastController.startRetryDelay(for: NSError(domain: "SomeOtherDomain", code: 2)) == nil)
    }
}

// MARK: - Park predicate and content-change rule (ghost cast)

struct CastEngagementDecisionTests {
    /// Parking (and sharing a live controller with a new screen) keeps an AirPlay
    /// route alive across screens. With no route ever involved there is nothing to keep.
    @Test func routeLessEngagementIsNotPreserved() {
        #expect(!CastController.shouldPreserveEngagement(
            routeWasActive: false, routeActiveNow: false, externalPlaybackActive: false
        ))
    }

    @Test func anyRouteEvidencePreservesTheEngagement() {
        // Route active right now (zap during a cast).
        #expect(CastController.shouldPreserveEngagement(
            routeWasActive: false, routeActiveNow: true, externalPlaybackActive: false
        ))
        // Route was active and is momentarily gone (flap while the screen closes):
        // the 4 s drop confirmation decides, not the close.
        #expect(CastController.shouldPreserveEngagement(
            routeWasActive: true, routeActiveNow: false, externalPlaybackActive: false
        ))
        // The cast player is in external playback.
        #expect(CastController.shouldPreserveEngagement(
            routeWasActive: false, routeActiveNow: false, externalPlaybackActive: true
        ))
    }

    /// A content change during a route-less engagement ends it (the engine loads the
    /// new content); with a route the content stays in the cast pipeline.
    @Test func contentChangeDecisionFollowsTheRoute() {
        #expect(CastController.contentChangeDecision(hasRouteToPreserve: false) == .endEngagement)
        #expect(CastController.contentChangeDecision(hasRouteToPreserve: true) == .continueCasting)
    }

    /// `playContent` reports whether it took the content. An idle controller never
    /// does, so the caller falls through to its normal engine load.
    @Test func idleControllerDoesNotTakeContent() {
        let cast = CastController()
        defer { cast.dispose() }
        let content = CastController.Content(
            url: URL(string: "http://host/live/user/pass/1.ts")!,
            isLive: true,
            userAgent: nil,
            startAt: 0,
            knownDuration: 0,
            nativelyPlayable: false
        )
        #expect(!cast.playContent(content))
        #expect(!cast.isEngaged)
        #expect(!cast.isPreparing)
        #expect(cast.lastNotice == nil)
    }

    /// Stopping a controller that is not engaged does nothing and says nothing.
    @Test func stopCastingWhileIdleIsSilent() {
        let cast = CastController()
        defer { cast.dispose() }
        cast.stopCasting()
        #expect(!cast.isEngaged)
        #expect(cast.lastNotice == nil)
    }
}

// MARK: - Route picker presentation and parked route drops

struct CastPickerDecisionTests {
    /// 30 s is only the fallback for a picker that never reported opening. While a
    /// picker is on screen the wait is the long backstop, and after it closed the
    /// short settle.
    @Test func waitLengthFollowsWhatThePickerReported() {
        #expect(CastController.pickerGraceSeconds(pickerPresented: false) == 30)
        #expect(CastController.pickerGraceSeconds(pickerPresented: true)
            == CastController.pickerOpenBackstopSeconds)
        #expect(CastController.pickerOpenBackstopSeconds > CastController.pickerFallbackGraceSeconds)
        // 12 s: the lower bound the audit asked for (a TV that has to wake up).
        #expect(CastController.pickerCloseSettleSeconds == 12)
        #expect(CastController.pickerCloseSettleSeconds < CastController.pickerFallbackGraceSeconds)
    }

    /// A cancelled picker ends a route-less engagement after the settle instead of
    /// leaving it for 30 s.
    @Test func closingThePickerWithoutARouteStartsTheSettle() {
        #expect(CastController.shouldSettleAfterPickerClose(
            isEngaged: true, routeWasActive: false, routeActiveNow: false, externalPlaybackActive: false
        ))
    }

    /// The callbacks never act on an idle controller (visible picker used with the
    /// engine playing): nothing to end, and they must not start anything.
    @Test func closingThePickerWhileIdleDoesNothing() {
        #expect(!CastController.shouldSettleAfterPickerClose(
            isEngaged: false, routeWasActive: false, routeActiveNow: false, externalPlaybackActive: false
        ))
    }

    /// The same callback arrives after a choice. An engagement that has, or had, a
    /// route belongs to the 4 s drop confirmation: switching receivers in the picker
    /// drops the route for a moment.
    @Test func closingThePickerWithRouteEvidenceLeavesTheEngagementAlone() {
        #expect(!CastController.shouldSettleAfterPickerClose(
            isEngaged: true, routeWasActive: false, routeActiveNow: true, externalPlaybackActive: false
        ))
        #expect(!CastController.shouldSettleAfterPickerClose(
            isEngaged: true, routeWasActive: true, routeActiveNow: false, externalPlaybackActive: false
        ))
        #expect(!CastController.shouldSettleAfterPickerClose(
            isEngaged: true, routeWasActive: false, routeActiveNow: false, externalPlaybackActive: true
        ))
    }

    @Test func expiredWaitEndsARouteLessEngagement() {
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: false, externalPlaybackActive: false,
            appIsInactive: false, wasDeferred: false
        ) == .endEngagement)
    }

    /// A device that connected in the meantime, or an engagement that is already
    /// gone, leaves nothing for the timer to do.
    @Test func expiredWaitStandsDownWhenThereIsNothingToEnd() {
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: true, externalPlaybackActive: false,
            appIsInactive: false, wasDeferred: false
        ) == .keepEngagement)
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: false, externalPlaybackActive: true,
            appIsInactive: false, wasDeferred: false
        ) == .keepEngagement)
        #expect(CastController.pickerGraceExpiry(
            isEngaged: false, routeActiveNow: false, externalPlaybackActive: false,
            appIsInactive: false, wasDeferred: false
        ) == .keepEngagement)
        // A route wins over the inactive check: nothing is polled for a live cast.
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: true, externalPlaybackActive: false,
            appIsInactive: true, wasDeferred: true
        ) == .keepEngagement)
    }

    /// System UI over the app (the device list, a TV's AirPlay code prompt) holds the
    /// wait: the engagement is not ended underneath it, only looked at again.
    @Test func inactiveAppDefersTheEnd() {
        let expected = CastController.PickerGraceExpiry.recheck(
            after: CastController.pickerInactiveRecheckSeconds, deferred: true
        )
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: false, externalPlaybackActive: false,
            appIsInactive: true, wasDeferred: false
        ) == expected)
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: false, externalPlaybackActive: false,
            appIsInactive: true, wasDeferred: true
        ) == expected)
    }

    /// Back in front after a deferral: the route gets one full settle, and only the
    /// expiry after that ends the engagement.
    @Test func returningToTheAppGrantsOneSettleBeforeTheEnd() {
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: false, externalPlaybackActive: false,
            appIsInactive: false, wasDeferred: true
        ) == .recheck(after: CastController.pickerCloseSettleSeconds, deferred: false))
        #expect(CastController.pickerGraceExpiry(
            isEngaged: true, routeActiveNow: false, externalPlaybackActive: false,
            appIsInactive: false, wasDeferred: false
        ) == .endEngagement)
    }

    /// Finished content with an owner: the auto-next countdown owns the window, the
    /// drop is ignored. Parked (no owner) it has to end the engagement, or nothing
    /// ever would.
    @Test func routeDropOfFinishedContentIsConfirmedOnlyWithoutAnOwner() {
        #expect(!CastController.shouldConfirmRouteDrop(contentCompleted: true, ownerAttached: true))
        #expect(CastController.shouldConfirmRouteDrop(contentCompleted: true, ownerAttached: false))
        // Content still playing: a drop is always confirmed, parked or not.
        #expect(CastController.shouldConfirmRouteDrop(contentCompleted: false, ownerAttached: true))
        #expect(CastController.shouldConfirmRouteDrop(contentCompleted: false, ownerAttached: false))
    }

    /// The route can go while the owner's countdown still runs; closing the player
    /// afterwards parks an engagement no later route change would end.
    @Test func parkingFinishedContentWithoutARouteConfirmsTheDrop() {
        #expect(CastController.parkingMustConfirmRouteDrop(
            contentCompleted: true, routeActiveNow: false, externalPlaybackActive: false
        ))
        // The route is still there: parking keeps it for the next screen.
        #expect(!CastController.parkingMustConfirmRouteDrop(
            contentCompleted: true, routeActiveNow: true, externalPlaybackActive: false
        ))
        #expect(!CastController.parkingMustConfirmRouteDrop(
            contentCompleted: true, routeActiveNow: false, externalPlaybackActive: true
        ))
        // Unfinished content is covered by the ordinary drop confirmation.
        #expect(!CastController.parkingMustConfirmRouteDrop(
            contentCompleted: false, routeActiveNow: false, externalPlaybackActive: false
        ))
    }

    /// The picker callbacks can only shorten or end an engagement. On an idle
    /// controller they change nothing and publish nothing.
    @Test func pickerCallbacksNeverStartAnEngagement() {
        let cast = CastController()
        defer { cast.dispose() }
        cast.pickerWillOpen()
        #expect(!cast.isEngaged)
        #expect(!cast.isPreparing)
        cast.pickerDidClose()
        #expect(!cast.isEngaged)
        #expect(!cast.isPreparing)
        #expect(!cast.isPresenting)
        #expect(cast.lastNotice == nil)
    }
}

// MARK: - Live reload budget

struct LiveReloadBudgetTests {
    @Test func delaysAreSpacedAndBounded() {
        var budget = LiveReloadBudget()
        #expect(budget.nextDelay(stablePlaybackSeconds: 0) == 0.5)
        #expect(budget.nextDelay(stablePlaybackSeconds: 3) == 2)
        #expect(budget.nextDelay(stablePlaybackSeconds: 3) == 5)
        // Spent: the stream is presented as ended instead of reloading forever
        // (two devices on a one-connection account would otherwise kick each other).
        #expect(budget.nextDelay(stablePlaybackSeconds: 3) == nil)
        #expect(budget.nextDelay(stablePlaybackSeconds: 0) == nil)
    }

    @Test func stablePlaybackRestoresTheBudget() {
        var budget = LiveReloadBudget()
        for _ in 0..<3 { _ = budget.nextDelay(stablePlaybackSeconds: 0) }
        #expect(budget.nextDelay(stablePlaybackSeconds: 59) == nil)
        #expect(budget.nextDelay(stablePlaybackSeconds: 60) == 0.5)
        #expect(budget.nextDelay(stablePlaybackSeconds: 5) == 2)
    }

    @Test func aRecoveredStreamStartsOverFromTheShortestDelay() {
        var budget = LiveReloadBudget()
        #expect(budget.nextDelay(stablePlaybackSeconds: 0) == 0.5)
        #expect(budget.nextDelay(stablePlaybackSeconds: 600) == 0.5)
    }

    @Test func resetRestoresTheBudget() {
        var budget = LiveReloadBudget()
        for _ in 0..<3 { _ = budget.nextDelay(stablePlaybackSeconds: 0) }
        budget.reset()
        #expect(budget == LiveReloadBudget())
        #expect(budget.nextDelay(stablePlaybackSeconds: 0) == 0.5)
    }
}

// MARK: - Retry start position

struct RetryStartPositionTests {
    @Test func liveNeverResumesFromAPosition() {
        #expect(VideoPlayerController.retryStartSeconds(
            requested: nil, isLive: true, lastKnownPosition: 900, knownDuration: 0
        ) == nil)
    }

    @Test func vodResumesFromLastKnownPositionPastFiveSeconds() {
        #expect(VideoPlayerController.retryStartSeconds(
            requested: nil, isLive: false, lastKnownPosition: 754, knownDuration: 5400
        ) == 754)
        // Still within the first seconds: start as originally requested.
        #expect(VideoPlayerController.retryStartSeconds(
            requested: nil, isLive: false, lastKnownPosition: 4, knownDuration: 5400
        ) == nil)
        #expect(VideoPlayerController.retryStartSeconds(
            requested: 120, isLive: false, lastKnownPosition: 0, knownDuration: 0
        ) == 120)
    }

    /// Resuming at the very end of a known duration would only end again.
    @Test func endOfContentFallsBackToTheRequest() {
        #expect(VideoPlayerController.retryStartSeconds(
            requested: nil, isLive: false, lastKnownPosition: 5398, knownDuration: 5400
        ) == nil)
        // Duration unknown (the failed reload reset it): the position is still used.
        #expect(VideoPlayerController.retryStartSeconds(
            requested: nil, isLive: false, lastKnownPosition: 5398, knownDuration: 0
        ) == 5398)
    }
}

// MARK: - Subtitle time offset per content

struct SubtitleDelayStoreTests {
    /// A private suite per test: nothing leaks into (or from) the app's own defaults.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "SubtitleDelayStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func unknownContentHasNoOffset() {
        withDefaults { defaults in
            #expect(SubtitleDelayStore.delaySeconds(for: "p_movie_1", defaults: defaults) == 0)
        }
    }

    @Test func offsetIsStoredPerContent() {
        withDefaults { defaults in
            SubtitleDelayStore.setDelaySeconds(2.5, for: "p_movie_1", defaults: defaults)
            SubtitleDelayStore.setDelaySeconds(-1.2, for: "p_movie_2", defaults: defaults)
            #expect(SubtitleDelayStore.delaySeconds(for: "p_movie_1", defaults: defaults) == 2.5)
            #expect(SubtitleDelayStore.delaySeconds(for: "p_movie_2", defaults: defaults) == -1.2)
            // The offset of one title never leaks into another.
            #expect(SubtitleDelayStore.delaySeconds(for: "p_movie_3", defaults: defaults) == 0)
        }
    }

    @Test func zeroRemovesTheEntry() {
        withDefaults { defaults in
            SubtitleDelayStore.setDelaySeconds(2.5, for: "p_movie_1", defaults: defaults)
            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == 1)
            SubtitleDelayStore.setDelaySeconds(0, for: "p_movie_1", defaults: defaults)
            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == 0)
            #expect(SubtitleDelayStore.delaySeconds(for: "p_movie_1", defaults: defaults) == 0)
            // Zero for content that has no entry stores nothing either.
            SubtitleDelayStore.setDelaySeconds(0, for: "p_movie_2", defaults: defaults)
            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == 0)
        }
    }

    @Test func valuesAreClampedToTheSliderRange() {
        withDefaults { defaults in
            SubtitleDelayStore.setDelaySeconds(99, for: "a", defaults: defaults)
            SubtitleDelayStore.setDelaySeconds(-99, for: "b", defaults: defaults)
            SubtitleDelayStore.setDelaySeconds(.nan, for: "c", defaults: defaults)
            #expect(SubtitleDelayStore.delaySeconds(for: "a", defaults: defaults)
                == SubtitleDelayStore.range.upperBound)
            #expect(SubtitleDelayStore.delaySeconds(for: "b", defaults: defaults)
                == SubtitleDelayStore.range.lowerBound)
            #expect(SubtitleDelayStore.delaySeconds(for: "c", defaults: defaults) == 0)
            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == 2)
        }
    }

    /// Bounded: the least recently changed entries make room for new ones.
    @Test func oldestEntriesAreEvictedBeyondTheLimit() {
        withDefaults { defaults in
            let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
            let total = SubtitleDelayStore.maxEntries + 5
            for i in 0..<total {
                SubtitleDelayStore.setDelaySeconds(
                    1, for: "content_\(i)", defaults: defaults,
                    now: base.addingTimeInterval(Double(i))
                )
            }
            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == SubtitleDelayStore.maxEntries)
            #expect(SubtitleDelayStore.delaySeconds(for: "content_0", defaults: defaults) == 0)
            #expect(SubtitleDelayStore.delaySeconds(for: "content_4", defaults: defaults) == 0)
            #expect(SubtitleDelayStore.delaySeconds(for: "content_5", defaults: defaults) == 1)
            #expect(SubtitleDelayStore.delaySeconds(for: "content_\(total - 1)", defaults: defaults) == 1)
        }
    }

    /// Changing an entry again makes it recent: it is not the one evicted next.
    @Test func updatingAnEntryRefreshesItsAge() {
        withDefaults { defaults in
            let base = Date(timeIntervalSinceReferenceDate: 2_000_000)
            for i in 0..<SubtitleDelayStore.maxEntries {
                SubtitleDelayStore.setDelaySeconds(
                    1, for: "content_\(i)", defaults: defaults,
                    now: base.addingTimeInterval(Double(i))
                )
            }
            SubtitleDelayStore.setDelaySeconds(
                3, for: "content_0", defaults: defaults, now: base.addingTimeInterval(10_000)
            )
            SubtitleDelayStore.setDelaySeconds(
                1, for: "newcomer", defaults: defaults, now: base.addingTimeInterval(10_001)
            )
            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == SubtitleDelayStore.maxEntries)
            #expect(SubtitleDelayStore.delaySeconds(for: "content_0", defaults: defaults) == 3)
            #expect(SubtitleDelayStore.delaySeconds(for: "content_1", defaults: defaults) == 0)
            #expect(SubtitleDelayStore.delaySeconds(for: "newcomer", defaults: defaults) == 1)
        }
    }
}

// MARK: - Cast sessions: one source connection, retries, in-place rebuilds

struct CastSessionDecisionTests {
    typealias RemuxError = RemuxHLSWriter.RemuxError

    private func sessionError(_ code: AirPlayRemuxSession.ErrorCode) -> NSError {
        NSError(domain: AirPlayRemuxSession.errorDomain, code: code.rawValue)
    }

    /// A first start, an in-place rebuild and a seek refresh share one rule: a
    /// transient failure waits and tries once more.
    @Test func transientStartFailureGetsOneRetry() {
        #expect(CastController.startFailureAction(retryUsed: false, error: RemuxError.openInputFailed(-5))
            == .retry(after: 8))
        #expect(CastController.startFailureAction(retryUsed: false, error: sessionError(.playlistTimeout))
            == .retry(after: 8))
        #expect(CastController.startFailureAction(retryUsed: false, error: RemuxError.videoParametersUnknown)
            == .retry(after: 2))
        #expect(CastController.startFailureAction(retryUsed: false, error: RemuxError.audioParametersUnknown)
            == .retry(after: 2))
    }

    /// The seek refresh no longer has a connected session to fall back to (its
    /// writer was stopped first), so a spent retry ends the cast with a reason
    /// instead of snapping back to the old position.
    @Test func spentRetryEndsTheCastWithAReason() {
        #expect(CastController.startFailureAction(retryUsed: true, error: RemuxError.openInputFailed(-5))
            == .endCast(.sourceOpenFailed))
        #expect(CastController.startFailureAction(retryUsed: true, error: sessionError(.playlistTimeout))
            == .endCast(.sourceTooSlow))
        #expect(CastController.startFailureAction(retryUsed: true, error: RemuxError.videoParametersUnknown)
            == .endCast(.sourceTooSlow))
        #expect(CastController.startFailureAction(retryUsed: true, error: RemuxError.audioParametersUnknown)
            == .endCast(.sourceTooSlow))
    }

    @Test func permanentStartFailureEndsTheCastWithoutRetry() {
        #expect(CastController.startFailureAction(retryUsed: false, error: RemuxError.noCompatibleStreams)
            == .endCast(.incompatibleStreams))
        #expect(CastController.startFailureAction(retryUsed: false, error: sessionError(.noLANAddress))
            == .endCast(.noWiFi))
        #expect(CastController.startFailureAction(retryUsed: false, error: sessionError(.localServerUnreachable))
            == .endCast(.localServerUnavailable))
        #expect(CastController.startFailureAction(retryUsed: false, error: sessionError(.listenerNotReady))
            == .endCast(.localServerUnavailable))
        #expect(CastController.startFailureAction(retryUsed: false, error: RemuxError.writeFailed(-ENOSPC))
            == .endCast(.storageFull))
    }

    /// A writer that supersedes an in-flight one can wait on a single session. While
    /// the session the in-flight writer drains is still closing, that writer has not
    /// opened the source: the connection to wait for is the older one.
    @Test func supersedingWriterDrainsTheSessionThatCanStillHoldTheSource() {
        #expect(CastController.drainChoice(hasInFlightSession: true, inFlightDrainTargetClosed: false)
            == .inFlightDrainTarget)
        // The older session has closed, so the in-flight writer may have opened.
        #expect(CastController.drainChoice(hasInFlightSession: true, inFlightDrainTargetClosed: true)
            == .inFlightSession)
        // Waiting for a delayed retry: nothing is in flight.
        #expect(CastController.drainChoice(hasInFlightSession: false, inFlightDrainTargetClosed: true)
            == .inFlightDrainTarget)
        #expect(CastController.drainChoice(hasInFlightSession: false, inFlightDrainTargetClosed: false)
            == .inFlightDrainTarget)
    }

    /// One in-place rebuild per 30 s for a source error; the second ends the cast.
    @Test func sourceErrorRebuildsOnceThenEndsTheCast() {
        #expect(CastController.runtimeRebuildDecision(cause: .sourceError, secondsSinceLastGuardedRebuild: nil)
            == .rebuild(countsAgainstGuard: true))
        #expect(CastController.runtimeRebuildDecision(cause: .sourceError, secondsSinceLastGuardedRebuild: 5)
            == .endCast)
        #expect(CastController.runtimeRebuildDecision(
            cause: .sourceError,
            secondsSinceLastGuardedRebuild: CastController.runtimeRebuildGuardSeconds - 0.1
        ) == .endCast)
        #expect(CastController.runtimeRebuildDecision(
            cause: .sourceError,
            secondsSinceLastGuardedRebuild: CastController.runtimeRebuildGuardSeconds
        ) == .rebuild(countsAgainstGuard: true))
        #expect(CastController.runtimeRebuildGuardSeconds == 30)
    }

    /// The live self-heal, a restarted local server and the storage budget repair
    /// something local while the source is healthy: they neither use up the guard
    /// nor are refused by it.
    @Test func localRepairsStayOutsideTheRebuildLoopGuard() {
        let causes: [CastController.RebuildCause] = [
            .fellBehindLiveWindow, .localServerLost, .storageBudgetExceeded,
        ]
        for cause in causes {
            #expect(CastController.runtimeRebuildDecision(cause: cause, secondsSinceLastGuardedRebuild: nil)
                == .rebuild(countsAgainstGuard: false), "\(cause)")
            #expect(CastController.runtimeRebuildDecision(cause: cause, secondsSinceLastGuardedRebuild: 1)
                == .rebuild(countsAgainstGuard: false), "\(cause)")
        }
    }

    /// A session's URLs carry the port they were minted with.
    @Test func localServerRebuildsOnPortChangeOrFailedHealthCheck() {
        #expect(CastController.localServerNeedsRebuild(portChanged: true, healthy: nil))
        #expect(CastController.localServerNeedsRebuild(portChanged: true, healthy: true))
        #expect(CastController.localServerNeedsRebuild(portChanged: false, healthy: false))
        // Same port and it answers, or the check has not reported yet: leave the cast alone.
        #expect(!CastController.localServerNeedsRebuild(portChanged: false, healthy: true))
        #expect(!CastController.localServerNeedsRebuild(portChanged: false, healthy: nil))
    }

    /// Transport calls on an idle controller reach the local-server repair and the
    /// live-edge seek; neither may start anything.
    @Test func transportOnAnIdleControllerStartsNothing() {
        let cast = CastController()
        defer { cast.dispose() }
        cast.play()
        cast.pause()
        cast.seek(toSource: 120)
        #expect(!cast.isEngaged)
        #expect(!cast.isPreparing)
        #expect(!cast.isPaused)
        #expect(cast.lastNotice == nil)
    }
}

// MARK: - Receiver reachability watchdog

struct CastReceiverWatchdogTests {
    @Test func unreachableReceiverGetsItsOwnMessage() {
        #expect(!CastEndReason.receiverUnreachable.isSilent)
        #expect(CastEndReason.receiverUnreachable.messageKey
            == "player.airplay.notice.receiver_unreachable")
        #expect(CastEndReason.receiverUnreachable != .receiverFailed)
    }

    /// One sign of life is enough: a healthy cast must never be ended.
    @Test func anySignOfLifeIsHealthy() {
        #expect(CastController.receiverWatchdogVerdict(
            receiverFetched: true, timeAdvanced: false, isPaused: false
        ) == .healthy)
        // A receiver whose requests are not told apart from the phone's own still plays.
        #expect(CastController.receiverWatchdogVerdict(
            receiverFetched: false, timeAdvanced: true, isPaused: false
        ) == .healthy)
        #expect(CastController.receiverWatchdogVerdict(
            receiverFetched: true, timeAdvanced: false, isPaused: true
        ) == .healthy)
    }

    @Test func noFetchAndNoProgressWhilePlayingIsUnreachable() {
        #expect(CastController.receiverWatchdogVerdict(
            receiverFetched: false, timeAdvanced: false, isPaused: false
        ) == .unreachable)
    }

    /// A paused cast makes no progress by definition; nothing is concluded from it.
    @Test func pausedCastIsLookedAtAgainLater() {
        #expect(CastController.receiverWatchdogVerdict(
            receiverFetched: false, timeAdvanced: false, isPaused: true
        ) == .waitLonger)
    }

    @Test func watchdogWaitsAboutFifteenSeconds() {
        #expect(CastController.receiverWatchdogSeconds == 15)
    }
}

// MARK: - Live window: resume after a long pause, fell-behind self-heal

struct CastLiveWindowTests {
    @Test func playheadBeforeTheFirstServedSegmentIsBehind() {
        #expect(CastController.isBehindServedWindow(localTime: 2, windowStart: 20, windowEnd: 30))
        // Within a second of the window start is still inside.
        #expect(!CastController.isBehindServedWindow(localTime: 19.5, windowStart: 20, windowEnd: 30))
        #expect(!CastController.isBehindServedWindow(localTime: 25, windowStart: 20, windowEnd: 30))
        // No seekable range reported yet: nothing to compare against.
        #expect(!CastController.isBehindServedWindow(localTime: 0, windowStart: 0, windowEnd: 0))
        #expect(!CastController.isBehindServedWindow(localTime: 0, windowStart: 1.5, windowEnd: 2))
    }

    /// play() after a pause longer than the sliding window rejoins near the live
    /// edge with a seek, which keeps the writer and its source connection.
    @Test func resumeBehindTheWindowSeeksToTheLiveEdge() {
        #expect(CastController.liveResumeSeekTarget(localTime: 2, windowStart: 20, windowEnd: 30)
            == 30 - CastController.liveEdgeMarginSeconds)
        #expect(CastController.liveResumeSeekTarget(localTime: 25, windowStart: 20, windowEnd: 30) == nil)
        // A window narrower than the margin: never seek before its start.
        #expect(CastController.liveResumeSeekTarget(localTime: 0, windowStart: 10, windowEnd: 11) == 10)
    }

    @Test func selfHealRunsOnlyWhilePlayingAndNotDuringALiveEdgeSeek() {
        #expect(CastController.shouldSelfHeal(
            localTime: 2, windowStart: 20, windowEnd: 30, isPaused: false, liveEdgeSeekSettling: false
        ))
        // Paused: the window slides under the playhead, but nothing is fetched.
        #expect(!CastController.shouldSelfHeal(
            localTime: 2, windowStart: 20, windowEnd: 30, isPaused: true, liveEdgeSeekSettling: false
        ))
        // play() just sought to the live edge: the tick must not rebuild underneath it.
        #expect(!CastController.shouldSelfHeal(
            localTime: 2, windowStart: 20, windowEnd: 30, isPaused: false, liveEdgeSeekSettling: true
        ))
        #expect(!CastController.shouldSelfHeal(
            localTime: 25, windowStart: 20, windowEnd: 30, isPaused: false, liveEdgeSeekSettling: false
        ))
        #expect(CastController.liveEdgeSeekGraceSeconds == 3)
    }

    /// A playing live cast that falls behind its window (a receiver stall, a Wi-Fi
    /// hiccup, a pause lifted with the TV remote) first gets a seek to the live
    /// edge, which keeps the writer and its source connection. Only when that seek
    /// was already tried is the session rebuilt.
    @Test func liveFallBehindSeeksOnceBeforeItRebuilds() {
        #expect(CastController.fellBehindAction(isLive: true, liveEdgeSeekTried: false) == .seekToLiveEdge)
        #expect(CastController.fellBehindAction(isLive: true, liveEdgeSeekTried: true) == .rebuildSession)
    }

    /// AirPlay may report a growing event range ahead of its VOD playhead. The
    /// writer retains these segments; refreshing here repeats the previous GOP.
    @Test func vodDoesNotRebuildWhenReceiverRangeAdvances() {
        #expect(!CastController.shouldSelfHeal(
            localTime: 14, windowStart: 20, windowEnd: 35,
            isPaused: false, liveEdgeSeekSettling: false, isLive: false
        ))
        #expect(CastController.shouldSelfHeal(
            localTime: 14, windowStart: 20, windowEnd: 35,
            isPaused: false, liveEdgeSeekSettling: false, isLive: true
        ))
    }

    /// The one-shot is armed again once a seek that was tried has settled and the
    /// playhead is back inside the window: the next fall-behind gets its seek.
    @Test func recoveredLiveEdgeSeekArmsTheOneShotAgain() {
        #expect(CastController.liveEdgeSeekRecovered(
            seekTried: true, seekSettling: false, localTime: 27, windowStart: 20, windowEnd: 30
        ))
        // Within a second of the window start counts as inside, as for the self-heal.
        #expect(CastController.liveEdgeSeekRecovered(
            seekTried: true, seekSettling: false, localTime: 19.5, windowStart: 20, windowEnd: 30
        ))
    }

    @Test func oneShotStaysSpentUntilTheSeekIsShownToHaveWorked() {
        // Nothing to re-arm.
        #expect(!CastController.liveEdgeSeekRecovered(
            seekTried: false, seekSettling: false, localTime: 27, windowStart: 20, windowEnd: 30
        ))
        // Still settling: the grace decides, not this.
        #expect(!CastController.liveEdgeSeekRecovered(
            seekTried: true, seekSettling: true, localTime: 27, windowStart: 20, windowEnd: 30
        ))
        // Still behind after the grace: the latch stays set, so the tick rebuilds.
        #expect(!CastController.liveEdgeSeekRecovered(
            seekTried: true, seekSettling: false, localTime: 2, windowStart: 20, windowEnd: 30
        ))
        // No seekable range reported: proves nothing, and re-arming on it would let
        // a playhead that never recovered seek over and over.
        #expect(!CastController.liveEdgeSeekRecovered(
            seekTried: true, seekSettling: false, localTime: 0, windowStart: 0, windowEnd: 0
        ))
        #expect(!CastController.liveEdgeSeekRecovered(
            seekTried: true, seekSettling: false, localTime: 1.8, windowStart: 1.5, windowEnd: 2
        ))
    }

    /// The two decisions never disagree: a playhead is either behind (self-heal) or
    /// recovered, and with no window it is neither.
    @Test func behindAndRecoveredAreMutuallyExclusive() {
        let samples: [(time: TimeInterval, start: TimeInterval, end: TimeInterval)] = [
            (2, 20, 30), (19.5, 20, 30), (25, 20, 30), (0, 0, 0), (1.8, 1.5, 2), (0, 10, 11),
        ]
        for sample in samples {
            let behind = CastController.shouldSelfHeal(
                localTime: sample.time, windowStart: sample.start, windowEnd: sample.end,
                isPaused: false, liveEdgeSeekSettling: false
            )
            let recovered = CastController.liveEdgeSeekRecovered(
                seekTried: true, seekSettling: false,
                localTime: sample.time, windowStart: sample.start, windowEnd: sample.end
            )
            #expect(!(behind && recovered), "\(sample)")
        }
    }
}

// MARK: - Cast exit keeps the play / pause state

struct CastExitPausedStateTests {
    @Test func playingCastResumesPlaying() {
        #expect(!CastController.resumeStartsPaused(
            castPaused: false, pausedByTransportCall: false,
            secondsSincePauseObserved: nil, isCompleted: false
        ))
        // A stale flag never pauses a cast that is playing.
        #expect(!CastController.resumeStartsPaused(
            castPaused: false, pausedByTransportCall: true,
            secondsSincePauseObserved: 120, isCompleted: false
        ))
    }

    /// Paused from the phone: direct playback must not start by itself.
    @Test func castPausedFromThePhoneResumesPaused() {
        #expect(CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: true,
            secondsSincePauseObserved: nil, isCompleted: false
        ))
        #expect(CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: true,
            secondsSincePauseObserved: 0.5, isCompleted: false
        ))
    }

    /// Paused with the TV remote some time ago: also the user's pause.
    @Test func castPausedOnTheReceiverResumesPaused() {
        #expect(CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: false,
            secondsSincePauseObserved: 60, isCompleted: false
        ))
        #expect(CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: false,
            secondsSincePauseObserved: CastController.exitPauseAttributionSeconds, isCompleted: false
        ))
    }

    /// The cast player stops by itself when its route or item goes away, moments
    /// before the cast ends (the route-drop confirmation takes 4 s). That is not the
    /// user's pause: playback carries on on the phone.
    @Test func pauseCausedByTheEndingItselfResumesPlaying() {
        #expect(!CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: false,
            secondsSincePauseObserved: 4.2, isCompleted: false
        ))
        #expect(!CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: false,
            secondsSincePauseObserved: 0, isCompleted: false
        ))
        #expect(!CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: false,
            secondsSincePauseObserved: nil, isCompleted: false
        ))
    }

    /// A finished item is paused at its end; that is not a pause to carry over.
    @Test func finishedContentIsNotResumedPaused() {
        #expect(!CastController.resumeStartsPaused(
            castPaused: true, pausedByTransportCall: true,
            secondsSincePauseObserved: 60, isCompleted: true
        ))
    }
}

// MARK: - Route picker opened on the AirPlay tap, while the session still prepares

struct CastPickerOnTapTests {
    /// The device list now opens on the tap. A close with no route while nothing
    /// plays yet waits longer than one under a cast that already plays locally: a
    /// TV that has to wake up must not lose the cast the user did pick.
    @Test func closeWhilePreparingSettlesLonger() {
        #expect(CastController.pickerCloseSettle(isPreparing: true) == 15)
        #expect(CastController.pickerCloseSettle(isPreparing: true)
            == CastController.pickerClosePreparingSettleSeconds)
        #expect(CastController.pickerCloseSettle(isPreparing: false)
            == CastController.pickerCloseSettleSeconds)
        #expect(CastController.pickerCloseSettleSeconds == 12)
        // Still the shorter of the two: a cast that already plays locally has less
        // to lose from ending than one that shows nothing yet.
        #expect(CastController.pickerCloseSettleSeconds
            < CastController.pickerClosePreparingSettleSeconds)
    }

    /// The session became ready after the picker had closed without a route: what is
    /// left of that settle is armed, not the 30 s fallback (no picker is on screen,
    /// so nothing could be chosen during it).
    @Test func readySessionGetsWhatIsLeftOfTheSettle() {
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: false, secondsUntilSettleDeadline: 10
        ) == 10)
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: false, secondsUntilSettleDeadline: 15
        ) == 15)
    }

    /// A prepare that outlasted the settle still leaves the route a last moment.
    @Test func remainingSettleIsNeverShorterThanTwoSeconds() {
        #expect(CastController.pickerCloseMinimumRemainingSeconds == 2)
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: false, secondsUntilSettleDeadline: 0.5
        ) == 2)
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: false, secondsUntilSettleDeadline: -40
        ) == 2)
    }

    /// A picker still on screen (its close never reported) keeps the long backstop,
    /// whatever an earlier close left behind.
    @Test func openPickerKeepsTheLongBackstop() {
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: true, secondsUntilSettleDeadline: nil
        ) == CastController.pickerOpenBackstopSeconds)
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: true, secondsUntilSettleDeadline: 3
        ) == CastController.pickerOpenBackstopSeconds)
    }

    /// No picker ever reported anything: the pre-delegate fallback.
    @Test func noPickerReportKeepsTheFallback() {
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: false, secondsUntilSettleDeadline: nil
        ) == CastController.pickerFallbackGraceSeconds)
        #expect(CastController.routeLessWaitSeconds(
            pickerPresented: false, secondsUntilSettleDeadline: nil
        ) == CastController.pickerGraceSeconds(pickerPresented: false))
    }
}

// MARK: - Cast exit: the resume waits for the remux writers to close

struct CastExitDrainTests {
    typealias RemuxError = RemuxHLSWriter.RemuxError

    @Test func waitParametersMatchTheWritersOwnDrain() {
        #expect(CastController.resumeDrainPollSeconds == 0.05)
        #expect(CastController.resumeDrainCapSeconds == 3)
        #expect(CastController.resumeDrainSettleSeconds == 0.3)
    }

    /// A writer that still holds the source is polled; an exit caused by a writer
    /// error (already closed) or one with no session at all resumes at once.
    @Test func planFollowsWhatCanStillHoldTheSource() {
        #expect(CastController.resumeDrainPlan(openSourceCount: 1, castPlayerHeldSource: false)
            == .pollThenSettle)
        #expect(CastController.resumeDrainPlan(openSourceCount: 3, castPlayerHeldSource: false)
            == .pollThenSettle)
        #expect(CastController.resumeDrainPlan(openSourceCount: 0, castPlayerHeldSource: false)
            == .resumeNow)
        // A natively cast item has no "closed" signal: only the short settle.
        #expect(CastController.resumeDrainPlan(openSourceCount: 0, castPlayerHeldSource: true)
            == .settleOnly)
        // An open writer wins over the cast player (a zap from native to remux).
        #expect(CastController.resumeDrainPlan(openSourceCount: 1, castPlayerHeldSource: true)
            == .pollThenSettle)
    }

    /// Poll until every writer reports closed, then settle; at the cap resume at
    /// once: there is no player in the meantime, so the wait must be bounded.
    @Test func stepPollsUntilClosedOrTheCap() {
        #expect(CastController.resumeDrainStep(openSourceCount: 1, elapsedSeconds: 0.05) == .poll)
        #expect(CastController.resumeDrainStep(openSourceCount: 2, elapsedSeconds: 2.95) == .poll)
        #expect(CastController.resumeDrainStep(openSourceCount: 0, elapsedSeconds: 0.05) == .settle)
        #expect(CastController.resumeDrainStep(openSourceCount: 0, elapsedSeconds: 2.9) == .settle)
        #expect(CastController.resumeDrainStep(
            openSourceCount: 1, elapsedSeconds: CastController.resumeDrainCapSeconds
        ) == .resume)
        #expect(CastController.resumeDrainStep(openSourceCount: 1, elapsedSeconds: 10) == .resume)
    }

    /// A session whose writer never ran never reports its source closed; waiting on
    /// it would always burn the cap.
    @Test func writerThatNeverRanIsNotWaitedFor() {
        let noLAN = NSError(
            domain: AirPlayRemuxSession.errorDomain,
            code: AirPlayRemuxSession.ErrorCode.noLANAddress.rawValue
        )
        #expect(!CastController.startFailureLeavesWriter(noLAN))
        // A listener without a port is reported before the writer starts as well.
        let listenerNotReady = NSError(
            domain: AirPlayRemuxSession.errorDomain,
            code: AirPlayRemuxSession.ErrorCode.listenerNotReady.rawValue
        )
        #expect(!CastController.startFailureLeavesWriter(listenerNotReady))
        // A listener that could not be started: not an error of the session's domain.
        #expect(!CastController.startFailureLeavesWriter(NSError(domain: "SomeOtherDomain", code: 48)))

        let timeout = NSError(
            domain: AirPlayRemuxSession.errorDomain,
            code: AirPlayRemuxSession.ErrorCode.playlistTimeout.rawValue
        )
        #expect(CastController.startFailureLeavesWriter(timeout))
        let unreachable = NSError(
            domain: AirPlayRemuxSession.errorDomain,
            code: AirPlayRemuxSession.ErrorCode.localServerUnreachable.rawValue
        )
        #expect(CastController.startFailureLeavesWriter(unreachable))
        #expect(CastController.startFailureLeavesWriter(RemuxError.openInputFailed(-5)))
        #expect(CastController.startFailureLeavesWriter(RemuxError.noCompatibleStreams))
    }

    /// The owner's cancel hook on a controller with nothing pending changes nothing
    /// and reports that nothing was dropped (so no extra reload is armed for it).
    @Test func cancelHookWithoutAPendingResumeIsANoOp() {
        let cast = CastController()
        defer { cast.dispose() }
        #expect(!cast.cancelPendingResume())
        #expect(!cast.isPresenting)
        #expect(!cast.isEngaged)
        #expect(!cast.isRemuxing)
        #expect(cast.lastNotice == nil)
    }
}

// MARK: - Cast exit with the route still selected: the notice says where the sound is

struct CastExitRouteNoticeTests {
    /// A zap or rebuild that fails at content level while the AirPlay route stays
    /// selected hands the stream back to the FFmpeg engine, whose sound follows the
    /// route: the notice carries that, next to the reason.
    @Test func contentFailureWithActiveRouteMentionsTheSound() {
        for reason in [CastEndReason.incompatibleStreams, .sourceOpenFailed, .sourceLost, .sourceTooSlow] {
            #expect(CastController.exitLeavesSoundOnRoute(
                reason: reason, resumesDirectPlayback: true,
                routeActiveAtExit: true, resumesOnFFmpegEngine: true
            ), "\(reason)")
        }
    }

    @Test func noRemarkWithoutARouteOrWithoutAResume() {
        #expect(!CastController.exitLeavesSoundOnRoute(
            reason: .incompatibleStreams, resumesDirectPlayback: true,
            routeActiveAtExit: false, resumesOnFFmpegEngine: true
        ))
        #expect(!CastController.exitLeavesSoundOnRoute(
            reason: .incompatibleStreams, resumesDirectPlayback: false,
            routeActiveAtExit: true, resumesOnFFmpegEngine: true
        ))
        // Content the engine's own AVPlayer plays goes to the receiver with its picture.
        #expect(!CastController.exitLeavesSoundOnRoute(
            reason: .receiverFailed, resumesDirectPlayback: true,
            routeActiveAtExit: true, resumesOnFFmpegEngine: false
        ))
    }

    /// Silent endings stay silent: there is no notice to attach the remark to.
    @Test func silentReasonsNeverCarryTheRemark() {
        for reason in [CastEndReason.userStopped, .contentChanged, .routeDropped] {
            #expect(!CastController.exitLeavesSoundOnRoute(
                reason: reason, resumesDirectPlayback: true,
                routeActiveAtExit: true, resumesOnFFmpegEngine: true
            ), "\(reason)")
        }
    }

    @Test func noticeCarriesTheRemarkAsPartOfItsValue() {
        #expect(!CastNotice(id: 1, reason: .incompatibleStreams).soundStaysOnRoute)
        #expect(CastNotice(id: 1, reason: .incompatibleStreams)
            != CastNotice(id: 1, reason: .incompatibleStreams, soundStaysOnRoute: true))
    }
}

// MARK: - Start refusals and retries added for wave 3

struct CastStartGuardTests {
    typealias RemuxError = RemuxHLSWriter.RemuxError

    /// A timestamp jump inside the start window (fMP4 path) is transient: a fresh
    /// session starts on the new timeline.
    @Test func timestampJumpAtStartIsRetriedAfterTwoSeconds() {
        #expect(CastController.startRetryDelay(for: RemuxError.timestampDiscontinuity) == 2)
        #expect(CastController.startFailureAction(retryUsed: false, error: RemuxError.timestampDiscontinuity)
            == .retry(after: 2))
        // The retry is still a single one.
        if case .retry = CastController.startFailureAction(
            retryUsed: true, error: RemuxError.timestampDiscontinuity
        ) {
            Issue.record("a spent retry must end the cast")
        }
    }

    /// A VOD remux cast is refused, with the engine still playing, when the disk
    /// cannot hold even the session's budget floor.
    @Test func vodCastNeedsTheBudgetFloorOfFreeSpace() {
        let floor = AirPlayRemuxSession.minimumStorageBudgetBytes
        #expect(!CastController.hasStorageForVODCast(availableCapacity: floor - 1))
        #expect(!CastController.hasStorageForVODCast(availableCapacity: 1))
        #expect(CastController.hasStorageForVODCast(availableCapacity: floor))
        #expect(CastController.hasStorageForVODCast(availableCapacity: 64 * 1024 * 1024 * 1024))
    }

    /// Unknown free space (nil, or the 0 the system reports when it cannot tell) is
    /// not a reason to refuse a cast.
    @Test func unknownFreeSpaceDoesNotRefuse() {
        #expect(CastController.hasStorageForVODCast(availableCapacity: nil))
        #expect(CastController.hasStorageForVODCast(availableCapacity: 0))
    }

    /// The audio session is given up only by an engagement that ended with no screen
    /// attached, and only when the owner that left handed the release over.
    @Test func audioSessionIsReleasedOnlyByAnOwnerlessEnd() {
        #expect(CastController.shouldReleaseAudioSession(ownerAttached: false, releaseInstalled: true))
        #expect(!CastController.shouldReleaseAudioSession(ownerAttached: true, releaseInstalled: true))
        #expect(!CastController.shouldReleaseAudioSession(ownerAttached: false, releaseInstalled: false))
    }

    /// The release is only taken from a parked, ownerless engagement; an idle
    /// controller does not keep it, so nothing is left to run when it stops.
    @Test func idleControllerIgnoresAParkedRelease() {
        let cast = CastController()
        defer { cast.dispose() }
        cast.setParkedAudioSessionRelease {}
        #expect(!cast.hasParkedAudioSessionRelease)
        cast.stopCasting()
        #expect(!cast.isEngaged)
    }
}

// MARK: - Native live cast (experimental): start watchdog

struct CastNativeStartProbeTests {
    typealias Probe = CastController.NativeStartProbe

    @Test func watchdogLimitsAndPolling() {
        #expect(CastController.nativeStartWatchdogSeconds == 8)
        #expect(CastController.nativeStartDelaySeconds == 1)
        #expect(Probe.pollSeconds == 1)
    }

    /// Ready and moving between two samples: the attempt worked.
    @Test func movingPictureConfirmsTheAttempt() {
        var probe = Probe(limitSeconds: 8)
        #expect(probe.sample(isReadyToPlay: false, currentTime: 0, isPaused: false) == .keepWatching)
        // First ready sample is only the baseline (a live item starts at any time).
        #expect(probe.sample(isReadyToPlay: true, currentTime: 20, isPaused: false) == .keepWatching)
        #expect(probe.sample(isReadyToPlay: true, currentTime: 21, isPaused: false) == .playing)
    }

    /// An item that never becomes ready falls back when the limit is reached.
    @Test func itemThatNeverGetsReadyFallsBack() {
        var probe = Probe(limitSeconds: 8)
        for _ in 0..<7 {
            #expect(probe.sample(isReadyToPlay: false, currentTime: 0, isPaused: false) == .keepWatching)
        }
        #expect(probe.sample(isReadyToPlay: false, currentTime: 0, isPaused: false) == .fallBack)
    }

    /// Ready but stuck (a playlist whose segments never arrive) is not "playing".
    @Test func readyButStalledItemFallsBack() {
        var probe = Probe(limitSeconds: 3)
        #expect(probe.sample(isReadyToPlay: true, currentTime: 12, isPaused: false) == .keepWatching)
        #expect(probe.sample(isReadyToPlay: true, currentTime: 12.1, isPaused: false) == .keepWatching)
        #expect(probe.sample(isReadyToPlay: true, currentTime: 12.2, isPaused: false) == .fallBack)
    }

    /// A paused, ready item makes no progress by definition: the time does not count,
    /// and it is confirmed once it plays.
    @Test func pausedReadyItemIsNeitherConfirmedNorFailed() {
        var probe = Probe(limitSeconds: 2)
        for _ in 0..<10 {
            #expect(probe.sample(isReadyToPlay: true, currentTime: 5, isPaused: true) == .keepWatching)
        }
        #expect(probe.elapsedSeconds == 0)
        #expect(probe.sample(isReadyToPlay: true, currentTime: 6, isPaused: false) == .playing)
    }

    /// Paused but not even ready still runs into the limit: the item has to load.
    @Test func pausedItemThatNeverLoadsFallsBack() {
        var probe = Probe(limitSeconds: 2)
        #expect(probe.sample(isReadyToPlay: false, currentTime: 0, isPaused: true) == .keepWatching)
        #expect(probe.sample(isReadyToPlay: false, currentTime: 0, isPaused: true) == .fallBack)
    }
}

// MARK: - Native live cast (experimental): the HLS twin of a stream URL

struct CastNativeURLTests {
    private func twin(_ string: String, container: String? = "mpegts") -> String? {
        CastNativeURL.hlsTwin(of: URL(string: string)!, containerFormatName: container)?.absoluteString
    }

    @Test func switchKeyMatchesTheContract() {
        #expect(CastNativeURL.enabledDefaultsKey == "player.airplayNativeLiveCastEnabled")
    }

    /// The three Xtream live shapes all become /live/user/pass/<id>.m3u8.
    @Test func xtreamLiveShapesBecomeTheHLSOutput() {
        #expect(twin("http://host.tv/user/pass/123") == "http://host.tv/live/user/pass/123.m3u8")
        #expect(twin("http://host.tv/user/pass/123.ts") == "http://host.tv/live/user/pass/123.m3u8")
        #expect(twin("http://host.tv/live/user/pass/123.ts") == "http://host.tv/live/user/pass/123.m3u8")
        #expect(twin("http://host.tv/live/user/pass/123.TS") == "http://host.tv/live/user/pass/123.m3u8")
    }

    @Test func schemePortAndEncodedCredentialsAreKept() {
        #expect(twin("https://host.tv:8443/user/pass/7") == "https://host.tv:8443/live/user/pass/7.m3u8")
        #expect(twin("http://10.0.0.5:8080/us%23er/p%2Fa%20ss/42.ts")
            == "http://10.0.0.5:8080/live/us%23er/p%2Fa%20ss/42.m3u8")
    }

    @Test func otherShapesHaveNoTwin() {
        // Not a stream id.
        #expect(twin("http://host.tv/user/pass/abc") == nil)
        #expect(twin("http://host.tv/user/pass/12a.ts") == nil)
        // Other extensions, other depths, VOD prefixes.
        #expect(twin("http://host.tv/user/pass/123.mkv") == nil)
        #expect(twin("http://host.tv/movie/user/pass/123.mkv") == nil)
        #expect(twin("http://host.tv/series/user/pass/123.ts") == nil)
        #expect(twin("http://host.tv/live/user/pass/123") == nil)
        #expect(twin("http://host.tv/panel/live/user/pass/123.ts") == nil)
        #expect(twin("http://host.tv/user/123") == nil)
        #expect(twin("http://host.tv/user/pass/123/") == nil)
        #expect(twin("http://host.tv/user/pass/123.ts.bak") == nil)
        // A query or a non-HTTP scheme is not one of the plain shapes.
        #expect(twin("http://host.tv/user/pass/123?token=1") == nil)
        #expect(twin("rtmp://host.tv/user/pass/123") == nil)
        #expect(twin("http://host.tv/get.php?username=u&password=p&type=m3u") == nil)
    }

    /// What FFmpeg already reads as HLS is its own twin, whatever its path looks like,
    /// except for a local file.
    @Test func hlsContainerIsItsOwnTwin() {
        #expect(twin("http://cdn.tv/play/abc?token=1", container: "hls")
            == "http://cdn.tv/play/abc?token=1")
        #expect(twin("http://host.tv/user/pass/123", container: "hls") == "http://host.tv/user/pass/123")
        #expect(twin("http://cdn.tv/play/abc", container: "hls,applehttp") == "http://cdn.tv/play/abc")
        #expect(CastNativeURL.hlsTwin(
            of: URL(fileURLWithPath: "/tmp/stream/index.m3u8"), containerFormatName: "hls"
        ) == nil)
        #expect(twin("http://cdn.tv/play/abc", container: nil) == nil)
        #expect(twin("http://cdn.tv/play/abc", container: "matroska,webm") == nil)
    }

    @Test func onlyH264WithCommonAudioIsCastNatively() {
        for audio in ["aac", "mp3", "ac3", "eac3", "aac (LC)"] {
            #expect(CastNativeURL.codecsAreNativelyCastable(video: "h264", audio: audio), "\(audio)")
        }
        #expect(CastNativeURL.codecsAreNativelyCastable(video: "h264 (High)", audio: "aac"))
        #expect(CastNativeURL.codecsAreNativelyCastable(video: "avc1", audio: "mp4a"))
        // HEVC stays on the remux path; so do MP2 / DTS audio and an unknown audio codec.
        #expect(!CastNativeURL.codecsAreNativelyCastable(video: "hevc", audio: "aac"))
        #expect(!CastNativeURL.codecsAreNativelyCastable(video: "h264", audio: "mp2"))
        #expect(!CastNativeURL.codecsAreNativelyCastable(video: "h264", audio: "dts"))
        #expect(!CastNativeURL.codecsAreNativelyCastable(video: "h264", audio: ""))
        #expect(!CastNativeURL.codecsAreNativelyCastable(video: "", audio: "aac"))
    }

    private func candidate(
        enabled: Bool = true,
        isLive: Bool = true,
        ffmpeg: Bool = true,
        avPlayerTried: Bool = false,
        video: String = "h264",
        audio: String = "aac",
        url: String = "http://host.tv/user/pass/123",
        container: String? = "mpegts",
        remembered: Bool = false
    ) -> URL? {
        CastNativeURL.candidate(
            enabled: enabled, isLive: isLive, isFFmpegBackendActive: ffmpeg,
            avPlayerAlreadyTried: avPlayerTried, videoCodec: video, audioCodec: audio,
            url: URL(string: url)!, containerFormatName: container, failureRemembered: remembered
        )
    }

    @Test func candidateNeedsEveryCondition() {
        #expect(candidate()?.absoluteString == "http://host.tv/live/user/pass/123.m3u8")
        // Off by default: the switch decides first.
        #expect(candidate(enabled: false) == nil)
        #expect(candidate(isLive: false) == nil)
        #expect(candidate(ffmpeg: false) == nil)
        #expect(candidate(video: "hevc") == nil)
        #expect(candidate(audio: "mp2") == nil)
        #expect(candidate(url: "http://host.tv/some/other/path/x.ts") == nil)
        // A host the attempt failed on goes straight to the remux.
        #expect(candidate(remembered: true) == nil)
        // AVPlayer already failed on this very URL: do not hand it to another AVPlayer.
        #expect(candidate(avPlayerTried: true, url: "http://cdn.tv/a/b.m3u8", container: "hls") == nil)
    }
}

// MARK: - Native live cast (experimental): remembered failures

struct CastNativeFailureMemoryTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "CastNativeFailureMemoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    private let live = URL(string: "http://Host.TV:8080/user/pass/123")!
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Remembered by host and port only: the path carries the credentials.
    @Test func hostKeyHoldsNoCredentials() {
        #expect(CastNativeURL.hostKey(for: live) == "host.tv:8080")
        #expect(CastNativeURL.hostKey(for: URL(string: "https://host.tv/u/p/1")!) == "host.tv")
        #expect(CastNativeURL.hostKey(for: URL(fileURLWithPath: "/tmp/a.ts")) == nil)
    }

    @Test func failureIsRememberedForSevenDays() {
        #expect(CastNativeURL.failureMemorySeconds == 7 * 24 * 60 * 60)
        withDefaults { defaults in
            #expect(!CastNativeURL.hasRememberedFailure(for: live, defaults: defaults, now: base))
            CastNativeURL.rememberFailure(for: live, defaults: defaults, now: base)
            #expect(CastNativeURL.hasRememberedFailure(for: live, defaults: defaults, now: base))
            // Any channel of the same host, also in the HLS shape.
            let other = URL(string: "http://host.tv:8080/live/user/pass/999.m3u8")!
            #expect(CastNativeURL.hasRememberedFailure(for: other, defaults: defaults, now: base))
            let almost = base.addingTimeInterval(CastNativeURL.failureMemorySeconds - 1)
            #expect(CastNativeURL.hasRememberedFailure(for: live, defaults: defaults, now: almost))
            let after = base.addingTimeInterval(CastNativeURL.failureMemorySeconds)
            #expect(!CastNativeURL.hasRememberedFailure(for: live, defaults: defaults, now: after))
        }
    }

    @Test func otherHostsAndPortsAreNotAffected() {
        withDefaults { defaults in
            CastNativeURL.rememberFailure(for: live, defaults: defaults, now: base)
            #expect(!CastNativeURL.hasRememberedFailure(
                for: URL(string: "http://other.tv:8080/user/pass/123")!, defaults: defaults, now: base
            ))
            #expect(!CastNativeURL.hasRememberedFailure(
                for: URL(string: "http://host.tv:9090/user/pass/123")!, defaults: defaults, now: base
            ))
        }
    }

    /// Switching the developer toggle on forgets the list (the way to try again early).
    @Test func forgettingClearsEveryHost() {
        withDefaults { defaults in
            CastNativeURL.rememberFailure(for: live, defaults: defaults, now: base)
            CastNativeURL.forgetFailures(defaults: defaults)
            #expect(!CastNativeURL.hasRememberedFailure(for: live, defaults: defaults, now: base))
        }
    }

    /// The record drops expired hosts when it is written and stays bounded.
    @Test func recordIsPrunedAndBounded() {
        let now = base.timeIntervalSinceReferenceDate
        let expired = now - CastNativeURL.failureMemorySeconds - 1
        let record = CastNativeURL.failures(
            ["old.tv": expired, "recent.tv": now - 60], rememberingFailureOf: "new.tv", now: base
        )
        #expect(Set(record.keys) == ["recent.tv", "new.tv"])
        #expect(record["new.tv"] == now)

        var full: [String: Double] = [:]
        for index in 0..<CastNativeURL.maxRememberedHosts {
            full["host\(index).tv"] = now - Double(CastNativeURL.maxRememberedHosts - index)
        }
        let bounded = CastNativeURL.failures(full, rememberingFailureOf: "newest.tv", now: base)
        #expect(bounded.count == CastNativeURL.maxRememberedHosts)
        #expect(bounded["newest.tv"] != nil)
        // The oldest entry made room.
        #expect(bounded["host0.tv"] == nil)
        #expect(bounded["host1.tv"] != nil)
    }

    /// A clock that was set back must not make a failure last forever.
    @Test func timestampFromTheFutureExpiresToo() {
        let now = base
        let nearFuture = now.timeIntervalSinceReferenceDate + 3600
        #expect(CastNativeURL.isRemembered(failedAt: nearFuture, now: now))
        let farFuture = now.timeIntervalSinceReferenceDate + CastNativeURL.failureMemorySeconds + 1
        #expect(!CastNativeURL.isRemembered(failedAt: farFuture, now: now))
    }
}

// MARK: - Controller decisions added with the cast-native lane

struct VideoPlayerControllerCastLaneLogicTests {
    /// A natively cast item (the receiver fetches it itself) lets the phone lock like
    /// the engine's own external playback; a remux cast never does.
    @Test func nativeExternalPlaybackCoversNativelyCastItems() {
        #expect(VideoPlayerControllerLogic.isNativeExternalPlayback(
            castPresenting: true, castExternalPlaybackActive: true,
            castIsRemuxing: false, engineExternalPlaybackActive: false
        ))
        #expect(!VideoPlayerControllerLogic.isNativeExternalPlayback(
            castPresenting: true, castExternalPlaybackActive: true,
            castIsRemuxing: true, engineExternalPlaybackActive: false
        ))
        // Still on the phone's own screen (no device chosen yet).
        #expect(!VideoPlayerControllerLogic.isNativeExternalPlayback(
            castPresenting: true, castExternalPlaybackActive: false,
            castIsRemuxing: false, engineExternalPlaybackActive: false
        ))
        // The engine's flag is stale while a cast presents.
        #expect(!VideoPlayerControllerLogic.isNativeExternalPlayback(
            castPresenting: true, castExternalPlaybackActive: false,
            castIsRemuxing: false, engineExternalPlaybackActive: true
        ))
        #expect(VideoPlayerControllerLogic.isNativeExternalPlayback(
            castPresenting: false, castExternalPlaybackActive: false,
            castIsRemuxing: false, engineExternalPlaybackActive: true
        ))
        #expect(!VideoPlayerControllerLogic.isNativeExternalPlayback(
            castPresenting: false, castExternalPlaybackActive: true,
            castIsRemuxing: false, engineExternalPlaybackActive: false
        ))
    }

    /// Play on an engine that retired its layer after a failure reloads; in every
    /// other state it is a plain play.
    @Test func playReloadsOnlyWhenTheFailedEngineHasNoLayer() {
        #expect(VideoPlayerControllerLogic.playShouldReload(engineHasLayer: false, engineHasFailure: true))
        #expect(!VideoPlayerControllerLogic.playShouldReload(engineHasLayer: true, engineHasFailure: true))
        // Stopped for a cast: no layer, but nothing failed.
        #expect(!VideoPlayerControllerLogic.playShouldReload(engineHasLayer: false, engineHasFailure: false))
        #expect(!VideoPlayerControllerLogic.playShouldReload(engineHasLayer: true, engineHasFailure: false))
    }

    /// The aspect names come from the string tables; "1:1" is the same everywhere.
    @Test func aspectModeTitlesAreLocalized() {
        #expect(VideoAspectMode.fit.title == L("player.aspect_fit"))
        #expect(VideoAspectMode.fill.title == L("player.aspect_fill"))
        #expect(VideoAspectMode.center.title == "1:1")
        for mode in VideoAspectMode.allCases {
            #expect(mode.accessibilityLabel == "\(L("player.aspect.title")): \(mode.title)")
        }
    }
}

// MARK: - A failed cast item: lost listener or failing receiver

struct CastItemFailureTests {
    typealias Action = CastController.CastItemFailureAction

    private func action(
        remux: Bool = true, completed: Bool = false,
        wasServing: Bool = true, portChanged: Bool = false, healthy: Bool? = nil
    ) -> Action {
        CastController.castItemFailureAction(
            isRemuxSession: remux, contentCompleted: completed,
            listenerWasServing: wasServing, portChanged: portChanged, healthy: healthy
        )
    }

    /// iOS reclaims the listener of a suspended app. A receiver that fails the item
    /// because of that says nothing about the stream: the session is rebuilt on the
    /// listener that serves now instead of ending the cast.
    @Test func lostOrReplacedListenerRebuildsInPlace() {
        // The listener was gone when the item failed (it is restarted for the rebuild,
        // possibly on the same port).
        #expect(action(wasServing: false) == .rebuildInPlace)
        // It came back on another port: every URL of the session is stale.
        #expect(action(portChanged: true) == .rebuildInPlace)
        #expect(action(wasServing: false, portChanged: true) == .rebuildInPlace)
        // It looked alive but did not answer the probe.
        #expect(action(healthy: false) == .rebuildInPlace)
    }

    /// A listener that looks alive is probed first: after a suspension only a request
    /// shows whether it accepts connections.
    @Test func listenerThatLooksAliveIsProbed() {
        #expect(action() == .probeListener)
    }

    /// The loop guard: a healthy listener always ends the cast, so an item the
    /// receiver really cannot play is never rebuilt over and over.
    @Test func healthyListenerEndsTheCast() {
        #expect(action(healthy: true) == .endCast)
    }

    /// Items this phone does not serve (a natively cast URL) and finished content
    /// keep the old behaviour, whatever the listener looks like.
    @Test func otherItemsEndTheCastAsBefore() {
        for wasServing in [true, false] {
            for portChanged in [true, false] {
                for healthy in [Bool?.none, true, false] {
                    #expect(action(
                        remux: false, wasServing: wasServing, portChanged: portChanged, healthy: healthy
                    ) == .endCast)
                    #expect(action(
                        completed: true, wasServing: wasServing, portChanged: portChanged, healthy: healthy
                    ) == .endCast)
                }
            }
        }
    }
}

// MARK: - Low-space rebuild needs a source that can seek

struct CastStorageRebuildTests {
    /// The rebuild restarts the remux at the current position, which is a seek on
    /// the source. A session that started at 0:00 never tried one, so its honoured
    /// start proves nothing; without the writer's own answer the film would restart
    /// at 0:00 on the TV.
    @Test func sourceThatCannotSeekIsLeftPlaying() {
        #expect(!CastController.storageRebuildAllowed(
            contentCompleted: false, startSeekHonoured: true, sourceCanSeek: false
        ))
    }

    @Test func seekableSourceIsRebuilt() {
        #expect(CastController.storageRebuildAllowed(
            contentCompleted: false, startSeekHonoured: true, sourceCanSeek: true
        ))
    }

    /// A refused start seek and finished content rule the rebuild out as before.
    @Test func refusedStartSeekOrFinishedContentIsLeftAlone() {
        #expect(!CastController.storageRebuildAllowed(
            contentCompleted: false, startSeekHonoured: false, sourceCanSeek: true
        ))
        #expect(!CastController.storageRebuildAllowed(
            contentCompleted: false, startSeekHonoured: false, sourceCanSeek: false
        ))
        #expect(!CastController.storageRebuildAllowed(
            contentCompleted: true, startSeekHonoured: true, sourceCanSeek: true
        ))
    }
}

// MARK: - A route that never takes the picture (AirPlay speaker)

struct CastExternalWaitTests {
    typealias Verdict = CastController.ExternalWaitVerdict

    private func verdict(
        casting: Bool = true, route: Bool = true, external: Bool = false, seen: Bool = false,
        paused: Bool = false, buffering: Bool = false, inactive: Bool = false
    ) -> Verdict {
        CastController.externalWaitVerdict(
            isCasting: casting, routeActiveNow: route, externalPlaybackActive: external,
            externalPlaybackSeen: seen, isPaused: paused, isBuffering: buffering,
            appIsInactive: inactive
        )
    }

    @Test func waitIsTwentySeconds() {
        #expect(CastController.externalWaitSeconds == 20)
        // Longer than the watchdog a receiver gets once it has the picture.
        #expect(CastController.externalWaitSeconds > CastController.receiverWatchdogSeconds)
    }

    /// The wait is armed only for a cast that plays with a route selected and has
    /// never been external in this engagement.
    @Test func armedOnlyForARouteThatNeverTookThePicture() {
        #expect(CastController.shouldArmExternalWait(
            isCasting: true, routeActiveNow: true, externalPlaybackActive: false, externalPlaybackSeen: false
        ))
        // No route: the picker wait owns the engagement.
        #expect(!CastController.shouldArmExternalWait(
            isCasting: true, routeActiveNow: false, externalPlaybackActive: false, externalPlaybackSeen: false
        ))
        // On the receiver right now, or at any earlier time (a TV between two items).
        #expect(!CastController.shouldArmExternalWait(
            isCasting: true, routeActiveNow: true, externalPlaybackActive: true, externalPlaybackSeen: false
        ))
        #expect(!CastController.shouldArmExternalWait(
            isCasting: true, routeActiveNow: true, externalPlaybackActive: false, externalPlaybackSeen: true
        ))
        // Preparing, refreshing or idle.
        #expect(!CastController.shouldArmExternalWait(
            isCasting: false, routeActiveNow: true, externalPlaybackActive: false, externalPlaybackSeen: false
        ))
    }

    /// Expiry: the cast plays on the phone, its sound goes to the route and the
    /// receiver never took the picture. That engagement ends.
    @Test func expiryEndsACastThatPlaysOnThePhone() {
        #expect(verdict() == .routeHasNoVideo)
    }

    /// An engagement that has been external at any time is never ended by this wait.
    @Test func externalPlaybackSeenStandsDown() {
        #expect(verdict(seen: true) == .standDown)
        #expect(verdict(external: true) == .standDown)
        #expect(verdict(external: true, seen: true) == .standDown)
        // Also when everything else says "playing on the phone".
        #expect(verdict(seen: true, paused: false, buffering: false, inactive: false) == .standDown)
    }

    /// The route went away while the wait ran: the drop confirmation owns that.
    @Test func routeGoneStandsDown() {
        #expect(verdict(route: false) == .standDown)
        #expect(verdict(route: false, paused: true) == .standDown)
    }

    /// Not casting any more (preparing, refreshing, idle): nothing to judge.
    @Test func notCastingStandsDown() {
        #expect(verdict(casting: false) == .standDown)
        #expect(verdict(casting: false, paused: true) == .standDown)
    }

    /// A paused cast proves nothing about the route: the wait is armed again.
    @Test func pausedCastWaitsLonger() {
        #expect(verdict(paused: true) == .waitLonger)
    }

    /// Neither does an item that is loading or stalled (a hand-over to the receiver
    /// looks like that), nor a moment in which system UI covers the app.
    @Test func stalledItemOrCoveredAppWaitsLonger() {
        #expect(verdict(buffering: true) == .waitLonger)
        #expect(verdict(inactive: true) == .waitLonger)
        #expect(verdict(paused: true, buffering: true, inactive: true) == .waitLonger)
    }

    /// Of all inputs, exactly one combination ends the engagement.
    @Test func onlyOneCombinationEndsTheEngagement() {
        var endings = 0
        for casting in [true, false] {
            for route in [true, false] {
                for external in [true, false] {
                    for seen in [true, false] {
                        for paused in [true, false] {
                            for buffering in [true, false] {
                                for inactive in [true, false] {
                                    let result = verdict(
                                        casting: casting, route: route, external: external, seen: seen,
                                        paused: paused, buffering: buffering, inactive: inactive
                                    )
                                    if result == .routeHasNoVideo { endings += 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(endings == 1)
    }

    /// The route is still selected at this exit and the stream goes back to the
    /// FFmpeg engine, whose sound follows the route: the notice says so as well.
    @Test func exitNoticeAlsoSaysWhereTheSoundIs() {
        #expect(CastController.exitLeavesSoundOnRoute(
            reason: .routeHasNoVideo, resumesDirectPlayback: true,
            routeActiveAtExit: true, resumesOnFFmpegEngine: true
        ))
    }
}

// MARK: - Cast diagnostics (record-only)

struct CastDiagnosticsTests {
    /// The message of a failed item hides which layer failed; the log line carries
    /// the domain and code of the error and of the error underneath it.
    @Test func itemErrorLineCarriesDomainAndCode() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        let error = NSError(
            domain: "AVFoundationErrorDomain", code: -11800,
            userInfo: [
                NSLocalizedDescriptionKey: "The operation could not be completed",
                NSUnderlyingErrorKey: underlying,
            ]
        )
        #expect(CastController.logDescription(of: error)
            == "The operation could not be completed [AVFoundationErrorDomain -11800; "
            + "underlying NSURLErrorDomain -1004]")
    }

    @Test func itemErrorLineWithoutAnUnderlyingError() {
        let error = NSError(
            domain: "AirPlayCastPlayer", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "cast item failed"]
        )
        #expect(CastController.logDescription(of: error) == "cast item failed [AirPlayCastPlayer 1]")
    }

    /// The saved log of the last engagement holds the lines of the cast files, under
    /// the key the copy actions read.
    @Test func sessionLogContract() {
        #expect(CastController.sessionLogKey == "airplay.lastSessionLog")
        #expect(CastController.sessionLogTags == ["AirPlayCast", "AirPlayRemux"])
        // The copy actions keep their own copy of both values (they are read outside
        // the main actor): the writer and the readers must not drift apart.
        #expect(AirPlayLogExport.persistedKey == CastController.sessionLogKey)
        #expect(AirPlayLogExport.tags == CastController.sessionLogTags)
    }

    /// What "Copy AirPlay log" puts on the pasteboard: the lines of this app session
    /// win, the saved record of the last cast is labelled as such, and the saved
    /// record is not even read while there are live lines.
    @Test func copiedLogPrefersLiveLinesAndLabelsTheSavedRecord() {
        var persistedReads = 0
        func persisted() -> [String] {
            persistedReads += 1
            return ["old 1", "old 2"]
        }
        #expect(AirPlayLogExport.text(live: ["a", "b"], persisted: persisted()) == "a\nb")
        #expect(persistedReads == 0)
        #expect(AirPlayLogExport.text(live: [], persisted: persisted())
            == "Last saved AirPlay session:\nold 1\nold 2")
        #expect(persistedReads == 1)
        #expect(AirPlayLogExport.text(live: [], persisted: []) == "No AirPlay log lines recorded.")
    }

    /// Cancel on an active route is offered only for a prepare the user started
    /// from the AirPlay button; an idle controller is not preparing at all.
    @Test func idleControllerIsNotPreparingFromTheButton() {
        let cast = CastController()
        defer { cast.dispose() }
        #expect(!cast.isPreparingFromButton)
        cast.pickerWillOpen()
        cast.pickerDidClose()
        cast.play()
        #expect(!cast.isPreparingFromButton)
        #expect(!cast.isEngaged)
    }
}
