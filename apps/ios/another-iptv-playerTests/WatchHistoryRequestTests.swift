import Foundation
import Testing
@testable import another_iptv_player

@Suite("WatchHistoryRequest")
struct WatchHistoryRequestTests {

    private let minute = 60_000
    private let playlistId = UUID()

    private func history(
        streamId: String,
        type: String,
        lastTimeMs: Int,
        durationMs: Int,
        seriesId: String? = nil,
        watchedAt: TimeInterval = 0
    ) -> DBWatchHistory {
        DBWatchHistory(
            id: "\(playlistId)_\(type)_\(streamId)",
            playlistId: playlistId,
            streamId: streamId,
            type: type,
            lastTimeMs: lastTimeMs,
            durationMs: durationMs,
            lastWatchedAt: Date(timeIntervalSince1970: 1_000_000 + watchedAt),
            seriesId: seriesId,
            title: "t",
            secondaryTitle: nil,
            imageURL: nil,
            containerExtension: nil
        )
    }

    // MARK: Rounding helper

    @Test
    func unknownDurationHasNoFraction() {
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 10 * minute, durationMs: 0) == nil)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 10 * minute, durationMs: -1) == nil)
    }

    @Test
    func fractionIsRoundedToHundredths() {
        let duration = 10_000_000
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 3_700_000, durationMs: duration) == 0.37)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 3_740_000, durationMs: duration) == 0.37)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 3_760_000, durationMs: duration) == 0.38)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 5_000_000, durationMs: duration) == 0.5)
    }

    @Test
    func fractionIsClampedToTheBar() {
        let duration = 40 * minute
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 0, durationMs: duration) == 0)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: -5_000, durationMs: duration) == 0)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: duration, durationMs: duration) == 1)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 41 * minute, durationMs: duration) == 1)
        // 99.6 % rounds up to a full bar.
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 9_960_000, durationMs: 10_000_000) == 1)
    }

    @Test
    func justStartedTitleKeepsItsSliver() {
        // The cards draw the bar only for progress > 0. Five seconds into a
        // two-hour film is 0.07 %, which plain rounding would turn into 0.
        let film = 120 * minute
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 5_000, durationMs: film) == 0.01)
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 1, durationMs: film) == 0.01)
        // 0.4 % also rounds to 0 without the floor.
        #expect(WatchProgressMapRequest.displayFraction(lastTimeMs: 40_000, durationMs: 10_000_000) == 0.01)
    }

    @Test
    func aMinuteOfFiveSecondSavesCrossesOneStep() {
        // 100-minute film: one step of the bar is one minute, so the twelve saves
        // of a minute produce two values instead of twelve.
        let film = 100 * minute
        let start = 30 * minute
        let values = (0..<12).compactMap {
            WatchProgressMapRequest.displayFraction(lastTimeMs: start + $0 * 5_000, durationMs: film)
        }
        #expect(values.count == 12)
        #expect(Set(values) == [0.3, 0.31])
    }

    @Test
    func repeatedSavesInsideOneStepCompareEqual() {
        // What removeDuplicates relies on: the same step gives the same Double.
        let film = 100 * minute
        let a = WatchProgressMapRequest.displayFraction(lastTimeMs: 45 * minute + 5_000, durationMs: film)
        let b = WatchProgressMapRequest.displayFraction(lastTimeMs: 45 * minute + 10_000, durationMs: film)
        #expect(a == b)
        #expect(a == 0.45)
    }

    // MARK: Map keys

    @Test
    func filmMapIsKeyedByStreamId() {
        let rows = [
            history(streamId: "101", type: "vod", lastTimeMs: 30 * minute, durationMs: 120 * minute),
            history(streamId: "102", type: "vod", lastTimeMs: 90 * minute, durationMs: 120 * minute, seriesId: "7"),
        ]
        let map = WatchProgressMapRequest.progressMap(from: rows, type: "vod")
        #expect(map == ["101": 0.25, "102": 0.75])
    }

    @Test
    func seriesMapIsKeyedBySeriesId() {
        // The series cards look the map up by series id; an episode id must not
        // appear as a key.
        let rows = [
            history(streamId: "9001", type: "series", lastTimeMs: 10 * minute, durationMs: 40 * minute, seriesId: "7"),
            history(streamId: "9101", type: "series", lastTimeMs: 20 * minute, durationMs: 40 * minute, seriesId: "8"),
        ]
        let map = WatchProgressMapRequest.progressMap(from: rows, type: "series")
        #expect(map == ["7": 0.25, "8": 0.5])
    }

    @Test
    func seriesMapShowsTheEpisodeWatchedLast() {
        let older = history(streamId: "9001", type: "series", lastTimeMs: 38 * minute, durationMs: 40 * minute,
                            seriesId: "7", watchedAt: 100)
        let newer = history(streamId: "9002", type: "series", lastTimeMs: 10 * minute, durationMs: 40 * minute,
                            seriesId: "7", watchedAt: 200)
        // Independent of the order the rows come back in.
        #expect(WatchProgressMapRequest.progressMap(from: [older, newer], type: "series") == ["7": 0.25])
        #expect(WatchProgressMapRequest.progressMap(from: [newer, older], type: "series") == ["7": 0.25])
    }

    @Test
    func seriesRowsWithoutASeriesIdAreLeftOut() {
        let rows = [
            history(streamId: "9001", type: "series", lastTimeMs: 10 * minute, durationMs: 40 * minute, seriesId: nil),
            history(streamId: "9002", type: "series", lastTimeMs: 10 * minute, durationMs: 40 * minute, seriesId: ""),
        ]
        #expect(WatchProgressMapRequest.progressMap(from: rows, type: "series").isEmpty)
    }

    @Test
    func rowsWithUnknownDurationAreLeftOut() {
        let film = history(streamId: "101", type: "vod", lastTimeMs: 10 * minute, durationMs: 0)
        let episode = history(streamId: "9001", type: "series", lastTimeMs: 10 * minute, durationMs: 0, seriesId: "7")
        #expect(WatchProgressMapRequest.progressMap(from: [film], type: "vod").isEmpty)
        #expect(WatchProgressMapRequest.progressMap(from: [episode], type: "series").isEmpty)
    }

    @Test
    func unstartedTitleStaysInTheMapWithZero() {
        // Unchanged from before the rounding: the entry exists, the card hides
        // the bar because it tests progress > 0.
        let film = history(streamId: "101", type: "vod", lastTimeMs: 0, durationMs: 120 * minute)
        #expect(WatchProgressMapRequest.progressMap(from: [film], type: "vod") == ["101": 0])
    }
}
