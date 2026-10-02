import Foundation
import Testing
@testable import another_iptv_player

@Suite("Downloads sections")
struct DownloadsSectionsTests {

    private let playlistId = UUID()

    private func item(
        _ id: String,
        status: DownloadStatus,
        type: String = "vod",
        title: String? = nil,
        series: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        createdAt: TimeInterval = 0
    ) -> DBDownloadedItem {
        DBDownloadedItem(
            id: id, playlistId: playlistId, streamId: id, type: type,
            title: title ?? "Title \(id)", secondaryTitle: series, imageURL: nil,
            remoteURL: "http://host/\(id).mkv", localPath: "\(id).mkv", containerExtension: "mkv",
            totalBytes: 0, downloadedBytes: 0, status: status.rawValue, errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 1_000_000 + createdAt), completedAt: nil,
            seriesId: series.map { _ in "7" }, seasonNumber: season, episodeNumber: episode
        )
    }

    @Test
    func nothingToShowIsEmpty() {
        #expect(DownloadsView.sections(of: [], matching: "").isEmpty)
        #expect(DownloadsView.sections(of: [], matching: "abc").isEmpty)
    }

    @Test
    func itemsAreSplitByStatus() {
        let items = [
            item("a", status: .completed),
            item("b", status: .downloading),
            item("c", status: .failed),
            item("d", status: .queued),
        ]
        let sections = DownloadsView.sections(of: items, matching: "")

        #expect(sections.inProgress.map(\.id) == ["b"])
        #expect(sections.queued.map(\.id) == ["d"])
        #expect(sections.failed.map(\.id) == ["c"])
        #expect(sections.completedMovies.map(\.id) == ["a"])
        #expect(sections.completedEpisodeGroups.isEmpty)
        #expect(!sections.isEmpty)
    }

    /// The request returns newest first; the queue shows what starts next on top.
    @Test
    func theQueueIsOldestFirst() {
        let items = [
            item("new", status: .queued, createdAt: 300),
            item("mid", status: .queued, createdAt: 200),
            item("old", status: .queued, createdAt: 100),
        ]
        #expect(DownloadsView.sections(of: items, matching: "").queued.map(\.id) == ["old", "mid", "new"])
    }

    @Test
    func finishedEpisodesAreGroupedBySeriesAndOrderedBySeasonAndEpisode() {
        let items = [
            item("z2", status: .completed, type: "episode", series: "Zeta", season: 1, episode: 2),
            item("a21", status: .completed, type: "episode", series: "alpha", season: 2, episode: 1),
            item("z1", status: .completed, type: "episode", series: "Zeta", season: 1, episode: 1),
            item("a13", status: .completed, type: "episode", series: "alpha", season: 1, episode: 3),
            item("film", status: .completed),
        ]
        let sections = DownloadsView.sections(of: items, matching: "")

        // Case-insensitive title order.
        #expect(sections.completedEpisodeGroups.map(\.title) == ["alpha", "Zeta"])
        #expect(sections.completedEpisodeGroups.map { $0.episodes.map(\.id) } == [["a13", "a21"], ["z1", "z2"]])
        #expect(sections.completedMovies.map(\.id) == ["film"])
    }

    /// An episode that is still downloading is listed with the downloads in
    /// progress, not under its series.
    @Test
    func unfinishedEpisodesStayInTheirStatusSection() {
        let items = [item("e", status: .downloading, type: "episode", series: "Show", season: 1, episode: 1)]
        let sections = DownloadsView.sections(of: items, matching: "")

        #expect(sections.inProgress.map(\.id) == ["e"])
        #expect(sections.completedEpisodeGroups.isEmpty)
    }

    @Test
    func theSearchMatchesTheTitleOrTheSeriesName() {
        let items = [
            item("film", status: .completed, title: "The Matrix"),
            item("ep", status: .completed, type: "episode", title: "Pilot", series: "Matrix Stories", season: 1, episode: 1),
            item("other", status: .downloading, title: "Heat"),
        ]
        let sections = DownloadsView.sections(of: items, matching: "  matrix ")

        #expect(sections.completedMovies.map(\.id) == ["film"])
        #expect(sections.completedEpisodeGroups.map(\.title) == ["Matrix Stories"])
        #expect(sections.inProgress.isEmpty)
    }

    @Test
    func aSearchWithoutAMatchLeavesNothing() {
        let items = [item("film", status: .completed, title: "Heat")]
        #expect(DownloadsView.sections(of: items, matching: "matrix").isEmpty)
        // Blank text is no search.
        #expect(!DownloadsView.sections(of: items, matching: "   ").isEmpty)
    }
}
