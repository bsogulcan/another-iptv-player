import CoreGraphics
import Testing
@testable import another_iptv_player

struct PlayerTimelineTests {
    private typealias Policy = PlayerTimelineScrubPolicy

    // MARK: Vertical band -> rate

    @Test func fingerOnTheTrackScrubsAtFullSpeed() {
        #expect(Policy.rate(verticalDistance: 0) == .full)
        // The touch band is 44 pt tall, so a finger anywhere on it is within 22 pt.
        #expect(Policy.rate(verticalDistance: 22) == .full)
        #expect(Policy.rate(verticalDistance: Policy.halfSpeedDistance - 0.5) == .full)
    }

    @Test func movingAwayFromTheTrackSlowsTheThumbInBands() {
        #expect(Policy.rate(verticalDistance: Policy.halfSpeedDistance) == .half)
        #expect(Policy.rate(verticalDistance: Policy.quarterSpeedDistance - 0.5) == .half)
        #expect(Policy.rate(verticalDistance: Policy.quarterSpeedDistance) == .quarter)
        #expect(Policy.rate(verticalDistance: 600) == .quarter)
    }

    @Test func bandsAreSymmetricAboveAndBelowTheTrack() {
        #expect(Policy.rate(verticalDistance: -Policy.halfSpeedDistance) == .half)
        #expect(Policy.rate(verticalDistance: -Policy.quarterSpeedDistance) == .quarter)
        #expect(Policy.rate(verticalDistance: -10) == .full)
    }

    @Test func rateFactorsAreFullHalfAndQuarter() {
        #expect(Policy.Rate.full.rawValue == 1)
        #expect(Policy.Rate.half.rawValue == 0.5)
        #expect(Policy.Rate.quarter.rawValue == 0.25)
        #expect(Policy.halfSpeedDistance < Policy.quarterSpeedDistance)
        // The first slow band must start outside the bar's own touch band.
        #expect(Policy.halfSpeedDistance > 22)
    }

    // MARK: Tap slop

    @Test func aTouchThatDoesNotMoveIsNotAScrub() {
        #expect(!Policy.isDeliberate(horizontalTravel: 0))
        #expect(!Policy.isDeliberate(horizontalTravel: 2.9))
        #expect(!Policy.isDeliberate(horizontalTravel: -2.9))
        #expect(Policy.isDeliberate(horizontalTravel: Policy.minimumTravel))
        #expect(Policy.isDeliberate(horizontalTravel: -Policy.minimumTravel))
        #expect(Policy.minimumTravel == 3)
    }

    @Test func crossingTheSlopCountsOnlyTheTravelBeyondIt() {
        // A slow drag starts from zero: no jump when the slop is crossed.
        #expect(Policy.travelPastSlop(Policy.minimumTravel) == 0)
        #expect(Policy.travelPastSlop(-Policy.minimumTravel) == 0)
        #expect(Policy.travelPastSlop(1) == 0)
        // A fast first movement is kept, in its direction.
        #expect(Policy.travelPastSlop(30) == 27)
        #expect(Policy.travelPastSlop(-30) == -27)
    }

    // MARK: Travel -> value

    @Test func thumbMovesByTheFingerTravelNotToTheFinger() {
        // 50 pt on a 200 pt track is a quarter of the timeline, wherever the finger is.
        let moved = Policy.advanced(value: 0.4, horizontalDelta: 50, trackWidth: 200, rate: .full)
        #expect(abs(moved - 0.65) < 1e-9)
        let back = Policy.advanced(value: 0.4, horizontalDelta: -50, trackWidth: 200, rate: .full)
        #expect(abs(back - 0.15) < 1e-9)
    }

    @Test func noTravelLeavesTheValueUntouched() {
        #expect(Policy.advanced(value: 0.37, horizontalDelta: 0, trackWidth: 200, rate: .full) == 0.37)
    }

    @Test func slowBandsScaleTheTravel() {
        let half = Policy.advanced(value: 0.4, horizontalDelta: 50, trackWidth: 200, rate: .half)
        #expect(abs(half - 0.525) < 1e-9)
        let quarter = Policy.advanced(value: 0.4, horizontalDelta: 50, trackWidth: 200, rate: .quarter)
        #expect(abs(quarter - 0.4625) < 1e-9)
    }

    @Test func changingTheBandMidDragDoesNotJump() {
        // 40 pt at full speed, then the finger lifts away and travels 40 pt at quarter
        // speed. Integrating per event keeps what was already scrubbed; recomputing
        // from the drag start (start + translation * rate) would snap back to 0.2.
        var value = 0.1
        value = Policy.advanced(value: value, horizontalDelta: 40, trackWidth: 200, rate: .full)
        #expect(abs(value - 0.3) < 1e-9)
        // The band changes with no horizontal movement: nothing moves.
        let held = Policy.advanced(value: value, horizontalDelta: 0, trackWidth: 200, rate: .quarter)
        #expect(held == value)
        value = Policy.advanced(value: value, horizontalDelta: 40, trackWidth: 200, rate: .quarter)
        #expect(abs(value - 0.35) < 1e-9)
    }

    @Test func valueStaysInsideTheTimeline() {
        #expect(Policy.advanced(value: 0.9, horizontalDelta: 500, trackWidth: 200, rate: .full) == 1)
        #expect(Policy.advanced(value: 0.1, horizontalDelta: -500, trackWidth: 200, rate: .full) == 0)
        // Out-of-range or broken input is clamped rather than propagated.
        #expect(Policy.advanced(value: 1.4, horizontalDelta: 0, trackWidth: 200, rate: .full) == 1)
        #expect(Policy.advanced(value: -.infinity, horizontalDelta: 10, trackWidth: 200, rate: .full) == 0.05)
        #expect(Policy.advanced(value: .nan, horizontalDelta: 0, trackWidth: 200, rate: .full) == 0)
    }

    @Test func degenerateTrackDoesNotMoveTheThumb() {
        #expect(Policy.advanced(value: 0.5, horizontalDelta: 40, trackWidth: 0, rate: .full) == 0.5)
        #expect(Policy.advanced(value: 0.5, horizontalDelta: .nan, trackWidth: 200, rate: .full) == 0.5)
    }

    // MARK: Buffered range

    @Test func bufferedRangeRunsFromThePlayheadToTheCacheEnd() throws {
        let range = try #require(
            Policy.bufferedRange(positionSeconds: 600, cacheAheadSeconds: 60, durationSeconds: 6_000)
        )
        #expect(abs(range.lowerBound - 0.1) < 1e-9)
        #expect(abs(range.upperBound - 0.11) < 1e-9)
    }

    @Test func bufferedRangeIsClampedToTheEndOfTheItem() throws {
        let range = try #require(
            Policy.bufferedRange(positionSeconds: 95, cacheAheadSeconds: 30, durationSeconds: 100)
        )
        #expect(abs(range.lowerBound - 0.95) < 1e-9)
        #expect(range.upperBound == 1)
    }

    @Test func nothingIsDrawnWithoutCacheOrDuration() {
        #expect(Policy.bufferedRange(positionSeconds: 10, cacheAheadSeconds: 0, durationSeconds: 100) == nil)
        #expect(Policy.bufferedRange(positionSeconds: 10, cacheAheadSeconds: -4, durationSeconds: 100) == nil)
        #expect(Policy.bufferedRange(positionSeconds: 10, cacheAheadSeconds: 5, durationSeconds: 0) == nil)
        #expect(Policy.bufferedRange(positionSeconds: 10, cacheAheadSeconds: .nan, durationSeconds: 100) == nil)
        #expect(Policy.bufferedRange(positionSeconds: 10, cacheAheadSeconds: 5, durationSeconds: .infinity) == nil)
        // Playhead already at the end: no room for a buffered stretch.
        #expect(Policy.bufferedRange(positionSeconds: 100, cacheAheadSeconds: 5, durationSeconds: 100) == nil)
    }

    // MARK: Remaining time

    @Test func remainingTimeAddsUpWithTheElapsedLabel() {
        // Labels truncate to whole seconds: 0:01 elapsed of 1:00 must read -0:59.
        #expect(Policy.remainingMs(elapsedMs: 1_900, durationMs: 60_400) == 59_000)
        #expect(Policy.remainingMs(elapsedMs: 0, durationMs: 60_000) == 60_000)
        #expect(Policy.remainingMs(elapsedMs: 60_000, durationMs: 60_000) == 0)
    }

    @Test func remainingTimeNeverGoesNegative() {
        #expect(Policy.remainingMs(elapsedMs: 75_000, durationMs: 60_000) == 0)
        #expect(Policy.remainingMs(elapsedMs: -5_000, durationMs: 60_000) == 60_000)
        #expect(Policy.remainingMs(elapsedMs: 10_000, durationMs: 0) == 0)
        #expect(Policy.remainingMs(elapsedMs: 10_000, durationMs: -1) == 0)
    }
}
