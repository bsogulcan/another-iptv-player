import CoreGraphics
import Testing
@testable import another_iptv_player

struct PlayerGestureTests {
    private let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let compactTrack = CGSize(width: 52, height: 160)

    @Test func edgeSliderExclusionMatchesCapsulesInsteadOfFullHeightStrips() {
        #expect(isExcluded(CGPoint(x: 42, y: 422)))
        #expect(isExcluded(CGPoint(x: 348, y: 422)))

        // Same horizontal strips, but outside the vertically centered capsules:
        // these remain valid video tap/long-press targets.
        #expect(!isExcluded(CGPoint(x: 42, y: 120)))
        #expect(!isExcluded(CGPoint(x: 348, y: 724)))
    }

    @Test func centerVideoSurfaceRemainsInteractive() {
        #expect(!isExcluded(CGPoint(x: bounds.midX, y: bounds.midY - 140)))
        #expect(!isExcluded(CGPoint(x: bounds.midX, y: bounds.midY + 140)))
    }

    @Test func sliderHitSlopProtectsSlowGestureStarts() {
        // Capsule begins at x=16 and is 52pt wide. The 8pt slop protects a
        // hesitant touch immediately beside it without swallowing the edge.
        #expect(isExcluded(CGPoint(x: 9, y: bounds.midY)))
        #expect(!isExcluded(CGPoint(x: 7, y: bounds.midY)))
    }

    @Test func activeSpeedHoldSurvivesTransientBuffering() {
        #expect(
            PlayerSpeedHoldGesturePolicy.recognizerEnabled(
                canBegin: false,
                isActive: true
            )
        )
        #expect(
            !PlayerSpeedHoldGesturePolicy.recognizerEnabled(
                canBegin: false,
                isActive: false
            )
        )
    }

    @Test func speedHoldIsNeverArmedOnLiveStreams() {
        // 2x drains the small live buffer (fed at 1x) and stalls into buffering.
        #expect(
            !PlayerSpeedHoldGesturePolicy.canBegin(
                settingEnabled: true,
                isPlaying: true,
                isLiveStream: true,
                isDismissDragActive: false
            )
        )
        // VOD and catch-up (played with isLiveStream == false) keep the hold, whether
        // or not the panel reports them as seekable.
        #expect(
            PlayerSpeedHoldGesturePolicy.canBegin(
                settingEnabled: true,
                isPlaying: true,
                isLiveStream: false,
                isDismissDragActive: false
            )
        )
    }

    @Test func speedHoldKeepsItsOtherGates() {
        #expect(
            !PlayerSpeedHoldGesturePolicy.canBegin(
                settingEnabled: false,
                isPlaying: true,
                isLiveStream: false,
                isDismissDragActive: false
            )
        )
        #expect(
            !PlayerSpeedHoldGesturePolicy.canBegin(
                settingEnabled: true,
                isPlaying: false,
                isLiveStream: false,
                isDismissDragActive: false
            )
        )
        #expect(
            !PlayerSpeedHoldGesturePolicy.canBegin(
                settingEnabled: true,
                isPlaying: true,
                isLiveStream: false,
                isDismissDragActive: true
            )
        )
    }

    @Test func liveGateDoesNotCancelAnActiveHold() {
        // A hold that is already running keeps its recognizer even when it could not
        // begin anew; finger-up stays the single end condition.
        let canBegin = PlayerSpeedHoldGesturePolicy.canBegin(
            settingEnabled: true,
            isPlaying: true,
            isLiveStream: true,
            isDismissDragActive: false
        )
        #expect(
            PlayerSpeedHoldGesturePolicy.recognizerEnabled(canBegin: canBegin, isActive: true)
        )
        #expect(
            !PlayerSpeedHoldGesturePolicy.recognizerEnabled(canBegin: canBegin, isActive: false)
        )
    }

    @Test func speedHoldToleranceFailsBeforePullDownActivates() {
        // A drag must fail the hold long before it reaches the pull-down slop;
        // the earlier 80 pt tolerance let slow pull-downs become a 2x hold.
        #expect(PlayerSpeedHoldGesturePolicy.allowableMovement == 10)
        #expect(
            PlayerSpeedHoldGesturePolicy.allowableMovement
                < FullscreenPlayerPullDownPolicy.activationDistance
        )
    }

    @Test func pullDownRequiresIntentionalVerticalTravel() {
        #expect(
            !FullscreenPlayerPullDownPolicy.shouldActivate(
                translation: CGSize(width: 2, height: 30)
            )
        )
        #expect(
            !FullscreenPlayerPullDownPolicy.shouldActivate(
                translation: CGSize(width: 46, height: 50)
            )
        )
        #expect(
            FullscreenPlayerPullDownPolicy.shouldActivate(
                translation: CGSize(width: 10, height: 60)
            )
        )
    }

    @Test func pullDownProgressStartsWithoutVisualJump() {
        let fullDistance: CGFloat = 260
        #expect(
            FullscreenPlayerPullDownPolicy.progress(
                translationHeight: FullscreenPlayerPullDownPolicy.activationDistance,
                fullDistance: fullDistance
            ) == 0
        )
        #expect(
            FullscreenPlayerPullDownPolicy.progress(
                translationHeight: fullDistance,
                fullDistance: fullDistance
            ) == 1
        )
    }

    @Test func pullDownFlickNeedsMinimumPhysicalProgress() {
        #expect(
            !FullscreenPlayerPullDownPolicy.shouldCommit(
                progress: 0.1,
                projectedProgress: 1,
                velocityY: 1_500
            )
        )
        #expect(
            FullscreenPlayerPullDownPolicy.shouldCommit(
                progress: 0.2,
                projectedProgress: 0.75,
                velocityY: 1_200
            )
        )
        #expect(
            FullscreenPlayerPullDownPolicy.shouldCommit(
                progress: 0.53,
                projectedProgress: 0.53,
                velocityY: 0
            )
        )
    }

    @Test func pullDownProgressIsMeasuredFromTheLockPoint() {
        let fullDistance: CGFloat = 260
        let activeDistance = FullscreenPlayerPullDownPolicy.activeDistance(fullDistance: fullDistance)
        // A drag that wandered 100 pt sideways only satisfies the dominance rule at
        // 126 pt of height. Anchored at the slop, that frame was already a third of the
        // way into the morph; anchored at the lock point it starts from rest.
        let lateLock = CGSize(width: 100, height: 126)
        #expect(FullscreenPlayerPullDownPolicy.shouldActivate(translation: lateLock))
        #expect(
            FullscreenPlayerPullDownPolicy.progress(
                translationHeight: lateLock.height,
                fullDistance: fullDistance
            ) > 0.3
        )
        #expect(
            FullscreenPlayerPullDownPolicy.progress(
                translationHeight: lateLock.height,
                activationHeight: lateLock.height,
                fullDistance: fullDistance
            ) == 0
        )
        // The same active travel completes the morph from wherever it locked.
        #expect(
            FullscreenPlayerPullDownPolicy.progress(
                translationHeight: lateLock.height + activeDistance,
                activationHeight: lateLock.height,
                fullDistance: fullDistance
            ) == 1
        )
    }

    @Test func pullDownLockAtTheSlopKeepsTheOriginalMapping() {
        let fullDistance: CGFloat = 260
        let slop = FullscreenPlayerPullDownPolicy.activationDistance
        for height: CGFloat in [44, 80, 150, 260, 400] {
            #expect(
                FullscreenPlayerPullDownPolicy.progress(
                    translationHeight: height,
                    activationHeight: slop,
                    fullDistance: fullDistance
                ) == FullscreenPlayerPullDownPolicy.progress(
                    translationHeight: height,
                    fullDistance: fullDistance
                )
            )
        }
        // The anchor never moves in front of the 44 pt slop.
        #expect(
            FullscreenPlayerPullDownPolicy.progress(
                translationHeight: slop,
                activationHeight: 10,
                fullDistance: fullDistance
            ) == 0
        )
    }

    @Test func pullDownFollowKeepsTheGrabbedPointUnderTheFinger() {
        // Landscape, grabbed well left of and below the screen centre.
        let anchor = CGPoint(x: 426, y: 196.5)
        let grab = CGPoint(x: 120, y: 300)
        let activation = CGSize(width: 6, height: 48)
        let translation = CGSize(width: -30, height: 150)
        let scale: CGFloat = 0.6
        let offset = FullscreenPlayerPullDownPolicy.followOffset(
            translation: translation,
            activationTranslation: activation,
            grabPoint: grab,
            anchor: anchor,
            scale: scale
        )
        // Where the grabbed point is drawn (scaled about the anchor, then offset)
        // against where the finger is now.
        let drawn = CGPoint(
            x: anchor.x + scale * (grab.x - anchor.x) + offset.width,
            y: anchor.y + scale * (grab.y - anchor.y) + offset.height
        )
        let finger = CGPoint(
            x: grab.x + translation.width - activation.width,
            y: grab.y + translation.height - activation.height
        )
        #expect(abs(drawn.x - finger.x) < 0.001)
        #expect(abs(drawn.y - finger.y) < 0.001)
    }

    @Test func pullDownFollowStartsAtRestAndNeverRisesAboveTheLockPoint() {
        let anchor = CGPoint(x: 196.5, y: 367)
        let grab = CGPoint(x: 80, y: 500)
        let activation = CGSize(width: 4, height: 46)
        // On the frame the axis locks nothing has moved yet.
        #expect(
            FullscreenPlayerPullDownPolicy.followOffset(
                translation: activation,
                activationTranslation: activation,
                grabPoint: grab,
                anchor: anchor,
                scale: 1
            ) == .zero
        )
        // A finger that goes back above the lock point does not lift the player.
        let above = FullscreenPlayerPullDownPolicy.followOffset(
            translation: CGSize(width: 4, height: 20),
            activationTranslation: activation,
            grabPoint: grab,
            anchor: anchor,
            scale: 1
        )
        #expect(above.height == 0)
    }

    @Test func pullDownChromeBandsDoNotCountTheBottomInsetTwice() {
        // Landscape phone: the container is the safe area (734 x 372).
        let container = CGSize(width: 734, height: 372)
        // The bottom band is 168 pt of the container. Adding the 21 pt home-indicator
        // inset on top used to swallow this start point as well.
        #expect(
            !FullscreenPlayerDismissZonePolicy.startsOnChrome(
                start: CGPoint(x: 367, y: 190),
                container: container
            )
        )
        #expect(
            FullscreenPlayerDismissZonePolicy.startsOnChrome(
                start: CGPoint(x: 367, y: 204),
                container: container
            )
        )
        // The top band is unchanged.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsOnChrome(
                start: CGPoint(x: 367, y: 96),
                container: container
            )
        )
    }

    @Test func pullDownHasNoFullHeightSideBands() {
        // The 110 pt side strips are gone: between the top and bottom bands every x
        // may start a pull-down, as far as the bands are concerned.
        let landscape = CGSize(width: 734, height: 372)
        for x: CGFloat in [0, 20, 110, 367, 734 - 110, 734] {
            #expect(
                !FullscreenPlayerDismissZonePolicy.startsOnChrome(
                    start: CGPoint(x: x, y: 150),
                    container: landscape
                )
            )
        }
        let portrait = CGSize(width: 393, height: 759)
        for x: CGFloat in [10, 100, 300, 385] {
            #expect(
                !FullscreenPlayerDismissZonePolicy.startsOnChrome(
                    start: CGPoint(x: x, y: 200),
                    container: portrait
                )
            )
        }
        // The bands still span the full width.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsOnChrome(
                start: CGPoint(x: 10, y: 96), container: portrait
            )
        )
        #expect(
            FullscreenPlayerDismissZonePolicy.startsOnChrome(
                start: CGPoint(x: 385, y: 759 - 168), container: portrait
            )
        )
    }

    @Test func dismissDragNeverStartsOnAnEdgeSliderCapsule() {
        // Landscape phone: 59 pt side insets, 21 pt at the bottom. In the container's
        // space the leading capsule is x 16...68, centred on the screen's mid-height
        // (196.5): y 116.5...276.5, plus 8 pt of slop all round.
        let landscape = MiniPlayerMetrics.screenFrame(
            container: CGSize(width: 734, height: 372),
            top: 0, left: 59, bottom: 21, right: 59
        )
        #expect(startsOnSlider(CGPoint(x: 40, y: 150), screen: landscape, left: 59, right: 59))
        #expect(startsOnSlider(CGPoint(x: 75, y: 150), screen: landscape, left: 59, right: 59))
        // The trailing capsule is x 666...718.
        #expect(startsOnSlider(CGPoint(x: 700, y: 150), screen: landscape, left: 59, right: 59))
        // Beside a capsule, where the side strip used to reach: free for the pull-down.
        #expect(!startsOnSlider(CGPoint(x: 77, y: 150), screen: landscape, left: 59, right: 59))
        #expect(!startsOnSlider(CGPoint(x: 110, y: 150), screen: landscape, left: 59, right: 59))
        #expect(!startsOnSlider(CGPoint(x: 734 - 110, y: 150), screen: landscape, left: 59, right: 59))
        // Above the capsule, in the same column.
        #expect(!startsOnSlider(CGPoint(x: 40, y: 100), screen: landscape, left: 59, right: 59))
        // The centre of the picture.
        #expect(!startsOnSlider(CGPoint(x: 367, y: 150), screen: landscape, left: 59, right: 59))
    }

    @Test func edgeBackZoneOverlapsTheCapsuleOnlyWithoutASideInset() {
        // Portrait phone: no side inset, so the capsule (x 16...68, slop from 8) lies
        // inside the 36 pt edge-back margin. The screen's mid-height is y 367 in the
        // container (59 pt top inset), the capsule y 287...447.
        let portrait = MiniPlayerMetrics.screenFrame(
            container: CGSize(width: 393, height: 759),
            top: 59, left: 0, bottom: 34, right: 0
        )
        let onCapsule = CGPoint(x: 20, y: 367)
        #expect(
            FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: onCapsule.x, containerWidth: 393, leadingInset: 0, isRightToLeft: false
            )
        )
        #expect(startsOnSlider(onCapsule, screen: portrait, left: 0, right: 0))
        // The bare screen edge and the edge above the capsule still start an edge-back.
        #expect(!startsOnSlider(CGPoint(x: 5, y: 367), screen: portrait, left: 0, right: 0))
        #expect(!startsOnSlider(CGPoint(x: 20, y: 200), screen: portrait, left: 0, right: 0))
        #expect(!startsOnSlider(CGPoint(x: 20, y: 600), screen: portrait, left: 0, right: 0))

        // Right-to-left starts from the right edge, where a capsule sits as well
        // (x 325...377).
        let onTrailingCapsule = CGPoint(x: 373, y: 367)
        #expect(
            FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: onTrailingCapsule.x, containerWidth: 393, leadingInset: 0, isRightToLeft: true
            )
        )
        #expect(startsOnSlider(onTrailingCapsule, screen: portrait, left: 0, right: 0))
        #expect(!startsOnSlider(CGPoint(x: 390, y: 367), screen: portrait, left: 0, right: 0))

        // iPad draws a 64 x 180 capsule: x 16...80, still inside the margin.
        let pad = MiniPlayerMetrics.screenFrame(
            container: CGSize(width: 820, height: 1136),
            top: 24, left: 0, bottom: 20, right: 0
        )
        #expect(
            startsOnSlider(
                CGPoint(x: 30, y: pad.midY), screen: pad, left: 0, right: 0,
                track: CGSize(width: 64, height: 180)
            )
        )
        #expect(
            !startsOnSlider(
                CGPoint(x: 30, y: pad.midY - 120), screen: pad, left: 0, right: 0,
                track: CGSize(width: 64, height: 180)
            )
        )

        // With a 59 pt side inset the edge-back zone ends 23 pt outside the container
        // and never reaches the capsule.
        let landscape = MiniPlayerMetrics.screenFrame(
            container: CGSize(width: 734, height: 372),
            top: 0, left: 59, bottom: 21, right: 59
        )
        #expect(
            FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: -30, containerWidth: 734, leadingInset: 59, isRightToLeft: false
            )
        )
        #expect(!startsOnSlider(CGPoint(x: -30, y: 196), screen: landscape, left: 59, right: 59))
    }

    @Test func topSystemBandHangsFromThePhysicalTopEdge() {
        // Portrait with a 59 pt top inset: the band is 99 pt of screen, which is 40 pt
        // of the container. Comparing container y with 99 doubled the inset.
        #expect(
            FullscreenPlayerDismissZonePolicy.topSystemGestureBandHeight(
                safeAreaTop: 59,
                containerHeight: 759
            ) == 99
        )
        #expect(
            FullscreenPlayerDismissZonePolicy.startsInTopSystemGestureBand(
                startY: 40, safeAreaTop: 59, containerHeight: 759
            )
        )
        #expect(
            !FullscreenPlayerDismissZonePolicy.startsInTopSystemGestureBand(
                startY: 41, safeAreaTop: 59, containerHeight: 759
            )
        )
        // A touch inside the inset has a negative container y and is in the band.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsInTopSystemGestureBand(
                startY: -20, safeAreaTop: 59, containerHeight: 759
            )
        )
        // Landscape without a top inset keeps the 72 pt minimum.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsInTopSystemGestureBand(
                startY: 72, safeAreaTop: 0, containerHeight: 372
            )
        )
        #expect(
            !FullscreenPlayerDismissZonePolicy.startsInTopSystemGestureBand(
                startY: 73, safeAreaTop: 0, containerHeight: 372
            )
        )
    }

    @Test func edgeBackMarginIsMeasuredFromThePhysicalEdge() {
        // Landscape with a 59 pt leading inset: container x = -59 is the screen edge.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: -30, containerWidth: 734, leadingInset: 59, isRightToLeft: false
            )
        )
        // 69 pt from the screen edge; the safe-area-relative rule (x < 36) took this.
        #expect(
            !FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: 10, containerWidth: 734, leadingInset: 59, isRightToLeft: false
            )
        )
        // Portrait has no leading inset, so nothing changes there.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: 35, containerWidth: 393, leadingInset: 0, isRightToLeft: false
            )
        )
        #expect(
            !FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: 36, containerWidth: 393, leadingInset: 0, isRightToLeft: false
            )
        )
        // Right-to-left starts from the other physical edge.
        #expect(
            FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: 734 + 30, containerWidth: 734, leadingInset: 59, isRightToLeft: true
            )
        )
        #expect(
            !FullscreenPlayerDismissZonePolicy.startsEdgeBack(
                startX: 734 - 10, containerWidth: 734, leadingInset: 59, isRightToLeft: true
            )
        )
    }

    @Test func edgeBackCommitsOnPositionOnly() {
        // 28 % of a 393 pt container is about 110 pt; wide containers cap at 130 pt.
        // There is no velocity input: a flick that stops short springs back.
        #expect(
            !FullscreenPlayerDismissZonePolicy.edgeBackShouldCommit(
                progressed: 110, containerWidth: 393
            )
        )
        #expect(
            FullscreenPlayerDismissZonePolicy.edgeBackShouldCommit(
                progressed: 111, containerWidth: 393
            )
        )
        #expect(
            !FullscreenPlayerDismissZonePolicy.edgeBackShouldCommit(
                progressed: 130, containerWidth: 852
            )
        )
        #expect(
            FullscreenPlayerDismissZonePolicy.edgeBackShouldCommit(
                progressed: 131, containerWidth: 852
            )
        )
    }

    @Test func screenFrameIsTheContainerGrownByItsInsets() {
        // Portrait phone: 59 pt above the container, 34 pt below it.
        let frame = MiniPlayerMetrics.screenFrame(
            container: CGSize(width: 393, height: 759),
            top: 59, left: 0, bottom: 34, right: 0
        )
        #expect(frame.size == CGSize(width: 393, height: 852))
        #expect(frame.midX == 196.5)
        // The screen centre sits 12.5 pt above the container centre (379.5); the morph
        // anchors there, not on the container centre.
        #expect(frame.midY == 367)

        // Landscape: equal side insets keep the centre on the container's x axis.
        let landscape = MiniPlayerMetrics.screenFrame(
            container: CGSize(width: 734, height: 372),
            top: 0, left: 59, bottom: 21, right: 59
        )
        #expect(landscape.size == CGSize(width: 852, height: 393))
        #expect(landscape.midX == 367)
        #expect(landscape.midY == 196.5)
    }

    @Test func forcedLandscapeAsksForPortraitOnlyWhenThePhoneIsUpright() {
        #expect(
            PlayerOrientationLock.shouldRequestPortrait(
                appForcedLandscape: true,
                deviceIsPhysicallyLandscape: false
            )
        )
        // Rotation unlocked and the phone held sideways: stay in landscape.
        #expect(
            !PlayerOrientationLock.shouldRequestPortrait(
                appForcedLandscape: true,
                deviceIsPhysicallyLandscape: true
            )
        )
        // Nothing was forced: never rotate the interface.
        #expect(
            !PlayerOrientationLock.shouldRequestPortrait(
                appForcedLandscape: false,
                deviceIsPhysicallyLandscape: false
            )
        )
    }

    private func startsOnSlider(
        _ start: CGPoint,
        screen: CGRect,
        left: CGFloat,
        right: CGFloat,
        track: CGSize = CGSize(width: 52, height: 160)
    ) -> Bool {
        FullscreenPlayerDismissZonePolicy.startsOnEdgeSlider(
            start: start,
            screen: screen,
            trackSize: track,
            leftInset: left,
            rightInset: right
        )
    }

    private func isExcluded(_ point: CGPoint) -> Bool {
        PlayerEdgeSliderGestureExclusion.contains(
            point,
            in: bounds,
            trackSize: compactTrack,
            leadingInset: 16,
            trailingInset: 16
        )
    }
}

// MARK: - Double-tap seek and pinch Fit/Fill snap

extension PlayerGestureTests {
    @Test func doubleTapZonesAreTheOuterSidesOnly() {
        let width: CGFloat = 400  // 35 % = 140 pt per side
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 20, width: width) == .backward)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 139, width: width) == .backward)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 141, width: width) == nil)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 200, width: width) == nil)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 259, width: width) == nil)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 261, width: width) == .forward)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 399, width: width) == .forward)
        // Outside the view, or before layout: never a seek zone.
        #expect(PlayerDoubleTapSeekPolicy.side(atX: -1, width: width) == nil)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 401, width: width) == nil)
        #expect(PlayerDoubleTapSeekPolicy.side(atX: 10, width: 0) == nil)
    }

    @Test func firstTapAlwaysTogglesTheChromeAndTheSecondSeeks() {
        var tracker = PlayerDoubleTapSeekPolicy.Tracker()
        // The single tap is not delayed: it toggles at once.
        #expect(tracker.register(side: .forward, at: 10, seekEnabled: true) == .toggleChrome)
        // The second tap on that side takes the toggle back and seeks.
        #expect(
            tracker.register(side: .forward, at: 10.2, seekEnabled: true)
                == .seek(.forward, undoChromeToggle: true)
        )
        // Further taps add to the seek and leave the chrome alone.
        #expect(
            tracker.register(side: .forward, at: 10.6, seekEnabled: true)
                == .seek(.forward, undoChromeToggle: false)
        )
        // Past the continuation window it is a plain tap again.
        #expect(tracker.register(side: .forward, at: 11.2, seekEnabled: true) == .toggleChrome)
        #expect(
            tracker.register(side: .forward, at: 11.4, seekEnabled: true)
                == .seek(.forward, undoChromeToggle: true)
        )
    }

    @Test func slowOrMismatchedSecondTapIsAPlainTap() {
        var slow = PlayerDoubleTapSeekPolicy.Tracker()
        #expect(slow.register(side: .backward, at: 5, seekEnabled: true) == .toggleChrome)
        #expect(slow.register(side: .backward, at: 5.35, seekEnabled: true) == .toggleChrome)

        var otherSide = PlayerDoubleTapSeekPolicy.Tracker()
        #expect(otherSide.register(side: .backward, at: 5, seekEnabled: true) == .toggleChrome)
        #expect(otherSide.register(side: .forward, at: 5.1, seekEnabled: true) == .toggleChrome)
        // That tap starts a pair of its own.
        #expect(
            otherSide.register(side: .forward, at: 5.2, seekEnabled: true)
                == .seek(.forward, undoChromeToggle: true)
        )

        var afterReset = PlayerDoubleTapSeekPolicy.Tracker()
        #expect(afterReset.register(side: .forward, at: 5, seekEnabled: true) == .toggleChrome)
        afterReset.reset()
        #expect(afterReset.register(side: .forward, at: 5.1, seekEnabled: true) == .toggleChrome)
    }

    @Test func centreTapsAndLiveNeverSeek() {
        var centre = PlayerDoubleTapSeekPolicy.Tracker()
        #expect(centre.register(side: nil, at: 1, seekEnabled: true) == .toggleChrome)
        #expect(centre.register(side: nil, at: 1.1, seekEnabled: true) == .toggleChrome)
        // A centre tap followed by a side tap is not a pair either.
        #expect(centre.register(side: .forward, at: 1.2, seekEnabled: true) == .toggleChrome)

        // Live TV / non-seekable content: exactly today's behaviour, tap by tap.
        var live = PlayerDoubleTapSeekPolicy.Tracker()
        #expect(live.register(side: .forward, at: 1, seekEnabled: false) == .toggleChrome)
        #expect(live.register(side: .forward, at: 1.1, seekEnabled: false) == .toggleChrome)
        #expect(live.register(side: .forward, at: 1.2, seekEnabled: false) == .toggleChrome)
    }

    @Test func seekIndicatorAddsUpWhileItShowsTheSameSide() {
        #expect(PlayerDoubleTapSeekPolicy.jumpSeconds == 10)
        #expect(PlayerDoubleTapSeekPolicy.indicatorSeconds(showing: nil, tapped: .forward) == 10)
        #expect(
            PlayerDoubleTapSeekPolicy.indicatorSeconds(
                showing: (side: .forward, seconds: 20), tapped: .forward
            ) == 30
        )
        #expect(
            PlayerDoubleTapSeekPolicy.indicatorSeconds(
                showing: (side: .forward, seconds: 20), tapped: .backward
            ) == 10
        )
    }

    @Test func coverScaleIsWhatMakesTheFittedPictureFillTheContainer() {
        #expect(
            PlayerPinchAspectSnapPolicy.coverScale(
                fitted: CGSize(width: 400, height: 200),
                container: CGSize(width: 500, height: 200)
            ) == 1.25
        )
        #expect(
            PlayerPinchAspectSnapPolicy.coverScale(
                fitted: CGSize(width: 500, height: 200),
                container: CGSize(width: 500, height: 200)
            ) == 1
        )
        // Sizes not known yet: no scale, and therefore no snap.
        #expect(
            PlayerPinchAspectSnapPolicy.coverScale(
                fitted: .zero, container: CGSize(width: 500, height: 200)
            ) == 1
        )
    }

    @Test func pinchOutFromFitLandsOnFill() {
        let cover: CGFloat = 1.25
        // Below the threshold nothing changes.
        #expect(pinchOutcome(.fit, from: 1, to: 1.04, cover: cover) == .freeZoom)
        // Past it, and up to a little beyond the cover scale, the pinch lands on Fill.
        #expect(pinchOutcome(.fit, from: 1, to: 1.06, cover: cover) == .snapToFill)
        #expect(pinchOutcome(.fit, from: 1, to: 1.25, cover: cover) == .snapToFill)
        #expect(pinchOutcome(.fit, from: 1, to: 1.39, cover: cover) == .snapToFill)
        // Beyond Fill the zoom stays free.
        #expect(pinchOutcome(.fit, from: 1, to: 1.45, cover: cover) == .freeZoom)
        #expect(pinchOutcome(.fit, from: 1, to: 3, cover: cover) == .freeZoom)
        // Only the first step snaps: a pinch that starts zoomed is a free zoom.
        #expect(pinchOutcome(.fit, from: 2, to: 1.2, cover: cover) == .freeZoom)
    }

    @Test func deepCropFillOnlySnapsNearItsCoverScale() {
        // 16:9 on a portrait phone (393 x 852): Fill is a 3.86x crop, and the pinch
        // stops at 4x. The zoom below it has to stay reachable.
        let portrait: CGFloat = 3.86
        #expect(pinchOutcome(.fit, from: 1, to: 1.2, cover: portrait) == .freeZoom)
        #expect(pinchOutcome(.fit, from: 1, to: 2, cover: portrait) == .freeZoom)
        #expect(pinchOutcome(.fit, from: 1, to: 3.4, cover: portrait) == .freeZoom)
        #expect(pinchOutcome(.fit, from: 1, to: 3.8, cover: portrait) == .snapToFill)
        #expect(pinchOutcome(.fit, from: 1, to: 4, cover: portrait) == .snapToFill)
        // 4:3 on a landscape phone is a shallow crop and keeps the whole first detent.
        let landscape: CGFloat = 1.63
        #expect(pinchOutcome(.fit, from: 1, to: 1.2, cover: landscape) == .snapToFill)
        #expect(pinchOutcome(.fit, from: 1, to: 1.63, cover: landscape) == .snapToFill)
        // Fill to Fit is unchanged by the depth of the crop.
        #expect(pinchOutcome(.fill, from: 1, to: 0.5, cover: portrait) == .snapToFit)
    }

    @Test func pinchInFromFillLandsOnFit() {
        let cover: CGFloat = 1.25
        #expect(
            PlayerPinchAspectSnapPolicy.minimumZoom(
                mode: .fill, committedZoom: 1, coverScale: cover
            ) == 1 / cover
        )
        #expect(pinchOutcome(.fill, from: 1, to: 0.85, cover: cover) == .snapToFit)
        // Let go too early: back to Fill, never a resting zoom below 1x.
        #expect(pinchOutcome(.fill, from: 1, to: 0.97, cover: cover) == .returnToFill)
        #expect(pinchOutcome(.fill, from: 1, to: 1, cover: cover) == .freeZoom)
        #expect(pinchOutcome(.fill, from: 1, to: 1.6, cover: cover) == .freeZoom)

        // A cover scale so small that 0.95 lies below the floor: halfway is enough.
        let small: CGFloat = 1.04
        #expect(PlayerPinchAspectSnapPolicy.fitSnapLimit(coverScale: small) > 0.95)
        #expect(pinchOutcome(.fill, from: 1, to: 0.97, cover: small) == .snapToFit)
        #expect(pinchOutcome(.fill, from: 1, to: 0.99, cover: small) == .returnToFill)
    }

    @Test func pinchFloorOpensOnlyInFillAtRest() {
        let cover: CGFloat = 1.25
        #expect(
            PlayerPinchAspectSnapPolicy.minimumZoom(mode: .fit, committedZoom: 1, coverScale: cover) == 1
        )
        #expect(
            PlayerPinchAspectSnapPolicy.minimumZoom(mode: .center, committedZoom: 1, coverScale: cover) == 1
        )
        #expect(
            PlayerPinchAspectSnapPolicy.minimumZoom(mode: .fill, committedZoom: 2, coverScale: cover) == 1
        )
        // While the snap towards Fit is settling the committed zoom is below 1.
        #expect(
            PlayerPinchAspectSnapPolicy.minimumZoom(mode: .fill, committedZoom: 0.8, coverScale: cover)
                == 1 / cover
        )
    }

    @Test func pinchNeverSnapsWhenFitAndFillLookTheSame() {
        // 16:9 video on a 16:9 screen: a switch would only rewrite the saved mode.
        let cover: CGFloat = 1.02
        #expect(pinchOutcome(.fit, from: 1, to: 1.08, cover: cover) == .freeZoom)
        #expect(
            PlayerPinchAspectSnapPolicy.minimumZoom(mode: .fill, committedZoom: 1, coverScale: cover) == 1
        )
        // 1:1 has no Fit/Fill step at all.
        #expect(pinchOutcome(.center, from: 1, to: 1.2, cover: 1.25) == .freeZoom)
    }

    @Test func cancelledPinchNeverChangesTheAspectMode() {
        let cover: CGFloat = 1.25
        // Same reset as an end, minus the mode switch.
        #expect(pinchOutcome(.fit, from: 1, to: 1.2, cover: cover, cancelled: true) == .freeZoom)
        #expect(pinchOutcome(.fill, from: 1, to: 0.85, cover: cover, cancelled: true) == .returnToFill)
        #expect(pinchOutcome(.fill, from: 1, to: 1.5, cover: cover, cancelled: true) == .freeZoom)
    }

    private func pinchOutcome(
        _ mode: VideoAspectMode,
        from committedZoom: CGFloat,
        to endZoom: CGFloat,
        cover: CGFloat,
        cancelled: Bool = false
    ) -> PlayerPinchAspectSnapPolicy.Outcome {
        PlayerPinchAspectSnapPolicy.outcome(
            mode: mode,
            committedZoom: committedZoom,
            endZoom: endZoom,
            coverScale: cover,
            cancelled: cancelled
        )
    }
}
