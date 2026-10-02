import Foundation
import Testing
@testable import another_iptv_player

@Suite("WatchResume")
struct WatchResumeTests {

    private let minute = 60_000

    private func history(lastTimeMs: Int, durationMs: Int, type: String = "series") -> DBWatchHistory {
        DBWatchHistory(
            id: "p_\(type)_1",
            playlistId: UUID(),
            streamId: "1",
            type: type,
            lastTimeMs: lastTimeMs,
            durationMs: durationMs,
            lastWatchedAt: Date(),
            seriesId: nil,
            title: "t",
            secondaryTitle: nil,
            imageURL: nil,
            containerExtension: nil
        )
    }

    // MARK: Lower bound

    @Test
    func positionAtOrBelowFiveSecondsIsNotResumed() {
        for kind in [WatchResume.Kind.episode, .film] {
            #expect(WatchResume.positionMs(lastTimeMs: 0, durationMs: 40 * minute, kind: kind) == nil)
            #expect(WatchResume.positionMs(lastTimeMs: 5_000, durationMs: 40 * minute, kind: kind) == nil)
            #expect(WatchResume.positionMs(lastTimeMs: 5_001, durationMs: 40 * minute, kind: kind) == 5_001)
        }
    }

    @Test
    func negativePositionIsNotResumed() {
        #expect(WatchResume.positionMs(lastTimeMs: -1, durationMs: 40 * minute, kind: .episode) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: -1, durationMs: 0, kind: .film) == nil)
    }

    // MARK: Unknown duration

    @Test
    func unknownDurationKeepsThePositionAboveTheLowerBound() {
        for kind in [WatchResume.Kind.episode, .film] {
            #expect(WatchResume.positionMs(lastTimeMs: 90 * minute, durationMs: 0, kind: kind) == 90 * minute)
            #expect(WatchResume.positionMs(lastTimeMs: 90 * minute, durationMs: -1, kind: kind) == 90 * minute)
            #expect(WatchResume.positionMs(lastTimeMs: 5_000, durationMs: 0, kind: kind) == nil)
        }
    }

    // MARK: Episodes

    @Test
    func episodeMidwayResumes() {
        let duration = 40 * minute
        #expect(WatchResume.positionMs(lastTimeMs: 20 * minute, durationMs: duration, kind: .episode) == 20 * minute)
    }

    @Test
    func episodeAtWatchedThresholdStartsOver() {
        // 95 % is the "Watched" label threshold of the episode list.
        let duration = 40 * minute
        let watched = duration * 95 / 100
        #expect(WatchResume.positionMs(lastTimeMs: watched, durationMs: duration, kind: .episode) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: duration, durationMs: duration, kind: .episode) == nil)
        // Just below 95 % and more than 30 s from the end (40 min * 5 % = 2 min left).
        #expect(WatchResume.positionMs(lastTimeMs: watched - 1_000, durationMs: duration, kind: .episode) == watched - 1_000)
    }

    @Test
    func episodeWithinThirtySecondsOfTheEndStartsOver() {
        // Short episode: 30 s from the end is only 90 %, so the tail rule decides.
        let duration = 5 * minute
        #expect(WatchResume.positionMs(lastTimeMs: duration - 30_000, durationMs: duration, kind: .episode) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: duration - 10_000, durationMs: duration, kind: .episode) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: duration - 30_001, durationMs: duration, kind: .episode) == duration - 30_001)
    }

    @Test
    func episodePositionPastTheDurationStartsOver() {
        #expect(WatchResume.positionMs(lastTimeMs: 41 * minute, durationMs: 40 * minute, kind: .episode) == nil)
    }

    // MARK: Films

    @Test
    func filmKeepsNinetyEightPercentRule() {
        let duration = 120 * minute
        let finished = duration * 98 / 100
        #expect(WatchResume.positionMs(lastTimeMs: finished, durationMs: duration, kind: .film) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: duration, durationMs: duration, kind: .film) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: finished - 1_000, durationMs: duration, kind: .film) == finished - 1_000)
    }

    @Test
    func filmBetweenEpisodeAndFilmThresholdsStillResumes() {
        // 96 % of a two-hour film is almost five minutes before the end.
        let duration = 120 * minute
        let position = duration * 96 / 100
        #expect(WatchResume.positionMs(lastTimeMs: position, durationMs: duration, kind: .film) == position)
        #expect(WatchResume.positionMs(lastTimeMs: position, durationMs: duration, kind: .episode) == nil)
    }

    @Test
    func filmHasNoThirtySecondTailRule() {
        // 20 s before the end of a 20-minute film is 98.3 %: dropped by the percentage
        // rule. 20 s before the end of a 10-minute clip is 96.7 %: still resumed.
        #expect(WatchResume.positionMs(lastTimeMs: 20 * minute - 20_000, durationMs: 20 * minute, kind: .film) == nil)
        #expect(WatchResume.positionMs(lastTimeMs: 10 * minute - 20_000, durationMs: 10 * minute, kind: .film) == 10 * minute - 20_000)
    }

    // MARK: DBWatchHistory convenience

    @Test
    func historyConvenienceForwardsToTheHelper() {
        let finishedEpisode = history(lastTimeMs: 40 * minute, durationMs: 40 * minute)
        #expect(finishedEpisode.resumePositionMs(as: .episode) == nil)

        let midEpisode = history(lastTimeMs: 12 * minute, durationMs: 40 * minute)
        #expect(midEpisode.resumePositionMs(as: .episode) == 12 * minute)

        let unknownDuration = history(lastTimeMs: 12 * minute, durationMs: 0, type: "vod")
        #expect(unknownDuration.resumePositionMs(as: .film) == 12 * minute)
    }
}
