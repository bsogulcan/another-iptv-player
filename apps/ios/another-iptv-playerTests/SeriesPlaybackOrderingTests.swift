import Foundation
import Testing
@testable import another_iptv_player

@Suite("SeriesPlaybackOrdering")
struct SeriesPlaybackOrderingTests {

    private func episode(id: String, episodeId: String? = nil) -> DBEpisode {
        DBEpisode(id: id, episodeId: episodeId, seasonId: "season-1")
    }

    @Test
    func indexFindsByEpisodeId() {
        let eps = [
            episode(id: "row-1", episodeId: "ep-100"),
            episode(id: "row-2", episodeId: "ep-200"),
            episode(id: "row-3", episodeId: "ep-300"),
        ]
        #expect(SeriesPlaybackOrdering.index(playbackStreamId: "ep-200", in: eps) == 1)
    }

    @Test
    func indexFallsBackToRowId() {
        let eps = [
            episode(id: "row-1", episodeId: nil),
            episode(id: "row-2", episodeId: nil),
        ]
        #expect(SeriesPlaybackOrdering.index(playbackStreamId: "row-2", in: eps) == 1)
    }

    @Test
    func indexReturnsNilWhenAbsent() {
        let eps = [episode(id: "row-1", episodeId: "ep-100")]
        #expect(SeriesPlaybackOrdering.index(playbackStreamId: "unknown", in: eps) == nil)
    }

    @Test
    func indexInEmptyListIsNil() {
        #expect(SeriesPlaybackOrdering.index(playbackStreamId: "anything", in: []) == nil)
    }

    @Test
    func emptyNavigationContextHasNoNeighbors() {
        let ctx = SeriesPlaybackOrdering.NavigationContext.empty
        #expect(ctx.previous == nil)
        #expect(ctx.next == nil)
    }
}
