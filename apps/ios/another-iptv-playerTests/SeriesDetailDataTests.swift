import Combine
import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The database side of the series page: which episode "Watch" starts with, which
/// season the page opens on, what a season's rows carry, how the answer of
/// `get_series_info` is stored, and the row the player shell is started with.
@Suite("Series detail data")
struct SeriesDetailDataTests {

    private let playlist = Playlist(name: "Series", serverURL: "http://host:8080")
    private let otherPlaylist = Playlist(name: "Other", serverURL: "http://other:8080")
    private let seriesId = 7
    private let watchedAt = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Fixtures

    /// Both playlists, each with a row for the series (the same panel id on purpose).
    private func seededDatabase() throws -> AppDatabase {
        let database = AppDatabase.empty()
        try database.writeSync { db in
            for owner in [playlist, otherPlaylist] {
                try owner.insert(db)
                try DBSeries(seriesId: seriesId, name: "Show", cover: "show.jpg", playlistId: owner.id).insert(db)
            }
        }
        return database
    }

    private func seasonId(_ number: Int, in owner: Playlist? = nil) -> String {
        DBSeason.scopedId(playlistId: (owner ?? playlist).id, seriesId: seriesId, seasonNumber: number)
    }

    /// Inserts a season and one episode per entry of `episodes` (panel id, episode number).
    private func addSeason(
        _ number: Int, episodes: [(id: String, num: Int)] = [], in owner: Playlist? = nil, db: Database
    ) throws {
        let owner = owner ?? playlist
        let id = seasonId(number, in: owner)
        try DBSeason(id: id, seasonNumber: number, seriesId: seriesId, playlistId: owner.id).insert(db)
        for episode in episodes {
            try DBEpisode(
                id: DBEpisode.scopedId(playlistId: owner.id, panelEpisodeId: episode.id),
                episodeId: episode.id,
                episodeNum: episode.num,
                title: "Episode \(episode.id)",
                containerExtension: "mkv",
                seasonId: id
            ).insert(db)
        }
    }

    private func history(
        streamId: String,
        lastTimeMs: Int = 60_000,
        durationMs: Int = 600_000,
        after seconds: TimeInterval = 0,
        type: String = "series",
        in owner: Playlist? = nil
    ) -> DBWatchHistory {
        let owner = owner ?? playlist
        return DBWatchHistory(
            id: "\(owner.id)_\(type)_\(streamId)",
            playlistId: owner.id,
            streamId: streamId,
            type: type,
            lastTimeMs: lastTimeMs,
            durationMs: durationMs,
            lastWatchedAt: watchedAt.addingTimeInterval(seconds),
            seriesId: String(seriesId),
            title: "Stored title",
            secondaryTitle: "Stored show",
            imageURL: "stored.jpg",
            containerExtension: "avi"
        )
    }

    private func firstEpisode(in database: AppDatabase, of owner: Playlist? = nil) throws -> DBEpisode? {
        try database.writeSync { db in
            try SeriesDetailData.firstEpisode(seriesId: seriesId, playlistId: (owner ?? playlist).id, db: db)
        }
    }

    private func anchor(in database: AppDatabase) throws -> SeriesSeasonAnchor {
        try database.writeSync { db in
            try SeriesDetailData.seasonAnchor(seriesId: seriesId, playlistId: playlist.id, db: db)
        }
    }

    private func decodeInfo(_ json: String) throws -> XtreamSeriesInfoResponse {
        try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: Data(json.utf8))
    }

    // MARK: First episode

    /// The shape of PR #107: season 1 is declared, the episodes are under season 2.
    @Test
    func firstEpisodePassesOverSeasonsWithoutEpisodes() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, db: db)
            try addSeason(2, episodes: [(id: "202", num: 2), (id: "201", num: 1)], db: db)
        }
        #expect(try firstEpisode(in: database)?.episodeId == "201")
    }

    @Test
    func firstEpisodeIsTheOneThePlayerOrdersFirst() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1), (id: "102", num: 2)], db: db)
            try addSeason(0, episodes: [(id: "9", num: 3), (id: "8", num: 2)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
        }
        let ordered = try database.writeSync { db in
            try SeriesPlaybackOrdering.orderedEpisodes(seriesId: seriesId, playlistId: playlist.id, db: db)
        }
        let first = try firstEpisode(in: database)
        #expect(first?.episodeId == "8")
        #expect(first == ordered.first)
    }

    @Test
    func nothingToPlayWithoutEpisodeRows() throws {
        let database = try seededDatabase()
        #expect(try firstEpisode(in: database) == nil)
        try database.writeSync { db in
            try addSeason(1, db: db)
            try addSeason(2, db: db)
        }
        #expect(try firstEpisode(in: database) == nil)
    }

    @Test
    func firstEpisodeStaysInsideItsPlaylist() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1)], in: otherPlaylist, db: db)
            try addSeason(1, db: db)
        }
        #expect(try firstEpisode(in: database) == nil)
        #expect(try firstEpisode(in: database, of: otherPlaylist)?.seasonId == seasonId(1, in: otherPlaylist))
    }

    // MARK: Episode of a history row

    @Test
    func historyLookupReturnsTheRowOfItsOwnPlaylist() throws {
        let database = try seededDatabase()
        // The other playlist's row is inserted first: an unscoped match would return it.
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "500", num: 1)], in: otherPlaylist, db: db)
            try addSeason(1, episodes: [(id: "500", num: 1)], db: db)
        }
        let found = try database.writeSync { db in
            try SeriesDetailData.episode(streamId: "500", playlistId: playlist.id, db: db)
        }
        #expect(found?.id == DBEpisode.scopedId(playlistId: playlist.id, panelEpisodeId: "500"))
        #expect(found?.seasonId == seasonId(1))
    }

    /// An episode the panel sent without an id is played, and filed in the history,
    /// under its row id.
    @Test
    func episodeWithoutPanelIdIsFoundByItsRowId() throws {
        let database = try seededDatabase()
        let rowId = "\(playlist.id.uuidString)_generated"
        try database.writeSync { db in
            try addSeason(1, db: db)
            try DBEpisode(id: rowId, episodeId: nil, episodeNum: 1, seasonId: seasonId(1)).insert(db)
        }
        let found = try database.writeSync { db in
            try SeriesDetailData.episode(streamId: rowId, playlistId: playlist.id, db: db)
        }
        #expect(found?.id == rowId)
    }

    @Test
    func unknownHistoryStreamHasNoEpisode() throws {
        let database = try seededDatabase()
        try database.writeSync { db in try addSeason(1, episodes: [(id: "101", num: 1)], db: db) }
        let found = try database.writeSync { db in
            try SeriesDetailData.episode(streamId: "999", playlistId: playlist.id, db: db)
        }
        #expect(found == nil)
    }

    // MARK: Opening season

    @Test
    func pageOpensOnTheSeasonOfTheLatestWatchedEpisode() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
            try addSeason(3, episodes: [(id: "301", num: 1)], db: db)
            try history(streamId: "301", after: 10).insert(db)
            try history(streamId: "201", after: 60).insert(db)
            try history(streamId: "101", after: 30).insert(db)
        }
        let anchor = try anchor(in: database)
        #expect(anchor.watchedSeasonId == seasonId(2))
        #expect(anchor.initialSeasonId == seasonId(2))
    }

    @Test
    func unwatchedSeriesOpensWhereWatchWouldStart() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
        }
        let anchor = try anchor(in: database)
        #expect(anchor.watchedSeasonId == nil)
        #expect(anchor.initialSeasonId == seasonId(2))
    }

    @Test
    func seriesWithoutEpisodeRowsOpensOnItsFirstSeason() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(2, db: db)
            try addSeason(1, db: db)
        }
        let anchor = try anchor(in: database)
        #expect(anchor.watchedSeasonId == nil)
        #expect(anchor.initialSeasonId == seasonId(1))
    }

    /// The history survives a catalog refresh, the episode rows may not.
    @Test
    func historyOfAMissingEpisodeDoesNotDecideTheSeason() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1)], db: db)
            try history(streamId: "777").insert(db)
        }
        let anchor = try anchor(in: database)
        #expect(anchor.watchedSeasonId == nil)
        #expect(anchor.initialSeasonId == seasonId(1))
    }

    @Test
    func historyOfAnotherPlaylistIsNotUsed() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], in: otherPlaylist, db: db)
            try history(streamId: "201", in: otherPlaylist).insert(db)
        }
        let anchor = try anchor(in: database)
        #expect(anchor.watchedSeasonId == nil)
        #expect(anchor.initialSeasonId == seasonId(1))
    }

    @Test
    func noSeasonsMeansNoSelection() throws {
        let database = try seededDatabase()
        #expect(try anchor(in: database) == SeriesSeasonAnchor())
    }

    // MARK: A season's rows

    @Test
    func seasonRowsComeWithTheHistoryOfTheirOwnEpisodes() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "102", num: 2), (id: "101", num: 1), (id: "103", num: 3)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
            try addSeason(1, episodes: [(id: "101", num: 1)], in: otherPlaylist, db: db)
            try history(streamId: "102").insert(db)
            // None of these belongs to a row of season 1 of this playlist.
            try history(streamId: "201").insert(db)
            try history(streamId: "101", in: otherPlaylist).insert(db)
            try history(streamId: "103", type: "vod").insert(db)
        }
        let season = try database.writeSync { db in
            try SeriesDetailData.seasonEpisodes(seasonId: seasonId(1), playlistId: playlist.id, db: db)
        }
        #expect(season.episodes.map(\.episodeId) == ["101", "102", "103"])
        #expect(Set(season.history.keys) == ["102"])
        #expect(season.history["102"]?.playlistId == playlist.id)
    }

    /// What lets the panel ignore the player's saves for other content: the value
    /// only differs when a row of the season itself changed.
    @Test
    func seasonValueChangesOnlyWithItsOwnHistory() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
            try history(streamId: "101").insert(db)
        }
        func season() throws -> SeasonEpisodes {
            try database.writeSync { db in
                try SeriesDetailData.seasonEpisodes(seasonId: seasonId(1), playlistId: playlist.id, db: db)
            }
        }
        let before = try season()
        try database.writeSync { db in try history(streamId: "201", lastTimeMs: 90_000).insert(db) }
        #expect(try season() == before)
        try database.writeSync { db in try history(streamId: "101", lastTimeMs: 90_000).save(db) }
        #expect(try season() != before)
    }

    @Test
    func seasonWithoutEpisodesIsEmpty() throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, db: db)
            try history(streamId: "101").insert(db)
        }
        let season = try database.writeSync { db in
            try SeriesDetailData.seasonEpisodes(seasonId: seasonId(1), playlistId: playlist.id, db: db)
        }
        #expect(season == SeasonEpisodes())
    }

    /// The page keeps its length through a season switch because the list is never
    /// empty in between: the previous rows remain until the asynchronous read arrives.
    @Test
    func seasonSwitchReplacesTheRowsInOneStep() async throws {
        let database = try seededDatabase()
        try database.writeSync { db in
            try addSeason(1, episodes: [(id: "101", num: 1), (id: "102", num: 2)], db: db)
            try addSeason(2, episodes: [(id: "201", num: 1)], db: db)
            try history(streamId: "201").insert(db)
        }
        let observer = SeasonEpisodesObserver()
        var published: [SeasonEpisodes?] = []
        let subscription = observer.$season.sink { published.append($0) }
        defer { subscription.cancel() }
        // Nothing read yet: the panel shows its loading state, not "no episodes".
        #expect(observer.season == nil)

        observer.load(seasonId: seasonId(1), playlistId: playlist.id, db: database)
        for _ in 0..<100 where observer.season == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observer.season?.episodes.map(\.episodeId) == ["101", "102"])

        observer.load(seasonId: seasonId(2), playlistId: playlist.id, db: database)
        #expect(observer.season?.episodes.map(\.episodeId) == ["101", "102"])
        for _ in 0..<100 where observer.season?.episodes.first?.episodeId != "201" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observer.season?.episodes.map(\.episodeId) == ["201"])
        #expect(observer.season?.history["201"] != nil)

        // The initial nil, then one value per season.
        #expect(published.count == 3)
        #expect(published.dropFirst().allSatisfy { $0?.episodes.isEmpty == false })

        // Appearing again with the season already shown starts nothing new.
        observer.load(seasonId: seasonId(2), playlistId: playlist.id, db: database)
        #expect(published.count == 3)
    }

    // MARK: Storing the series info

    private let infoJSON = #"""
    {"seasons": [{"season_number": 1, "name": "First", "episode_count": 8}],
     "info": {"plot": "New plot", "cast": "A, B", "backdrop_path": ["backdrop.jpg"], "episode_run_time": "45"},
     "episodes": {"2": [{"id": "201", "episode_num": 1, "title": "Pilot", "container_extension": "mkv"},
                        {"id": "202", "episode_num": 2, "title": "Second", "container_extension": "mkv"}]}}
    """#

    @Test
    func storingStartsFromTheStoredRow() throws {
        let database = try seededDatabase()
        // The catalog was refreshed after the screen had been handed its copy of the row.
        try database.writeSync { db in
            try db.execute(
                sql: "UPDATE series SET name = ?, categoryId = ?, sortIndex = ? WHERE seriesId = ? AND playlistId = ?",
                arguments: ["Renamed", "new-category", 12, seriesId, playlist.id]
            )
        }
        let info = try decodeInfo(infoJSON)
        let stored = try database.writeSync { db in
            try SeriesDetailData.store(info, seriesId: seriesId, playlistId: playlist.id, db: db)
        }
        #expect(stored == 2)

        let row = try database.writeSync { db in
            try DBSeries.filter(Column("seriesId") == seriesId && Column("playlistId") == playlist.id).fetchOne(db)
        }
        #expect(row?.seasonsLoaded == true)
        #expect(row?.name == "Renamed")
        #expect(row?.categoryId == "new-category")
        #expect(row?.sortIndex == 12)
        #expect(row?.cover == "show.jpg")
        #expect(row?.plot == "New plot")
        #expect(row?.cast == "A, B")
        #expect(row?.backdropPath == "backdrop.jpg")
        #expect(row?.episodeRunTime == "45")

        // Season 1 is declared without episodes, season 2 only exists as an episode bucket.
        let seasons = try database.writeSync { db in
            try DBSeason.filter(Column("playlistId") == playlist.id).order(Column("seasonNumber")).fetchAll(db)
        }
        #expect(seasons.map(\.id) == [seasonId(1), seasonId(2)])
        #expect(seasons.map(\.episodeCount) == [8, 2])
        #expect(try firstEpisode(in: database)?.episodeId == "201")
        #expect(try database.writeSync { db in
            try SeriesDetailData.seasonsLoaded(seriesId: seriesId, playlistId: playlist.id, db: db)
        } == true)
        // The other playlist's series with the same panel id is untouched.
        #expect(try database.writeSync { db in
            try SeriesDetailData.seasonsLoaded(seriesId: seriesId, playlistId: otherPlaylist.id, db: db)
        } == false)
    }

    @Test
    func answerWithoutInfoBlockKeepsEarlierDetails() throws {
        let database = try seededDatabase()
        let first = try decodeInfo(infoJSON)
        let second = try decodeInfo(#"{"seasons": [], "episodes": {}}"#)
        let row = try database.writeSync { db -> DBSeries? in
            _ = try SeriesDetailData.store(first, seriesId: seriesId, playlistId: playlist.id, db: db)
            _ = try SeriesDetailData.store(second, seriesId: seriesId, playlistId: playlist.id, db: db)
            return try DBSeries.filter(Column("seriesId") == seriesId && Column("playlistId") == playlist.id).fetchOne(db)
        }
        #expect(row?.plot == "New plot")
        #expect(row?.backdropPath == "backdrop.jpg")
        #expect(row?.seasonsLoaded == true)
    }

    @Test
    func nothingIsStoredForASeriesThatIsGone() throws {
        let database = try seededDatabase()
        let info = try decodeInfo(infoJSON)
        let stored = try database.writeSync { db in
            try SeriesDetailData.store(info, seriesId: 999, playlistId: playlist.id, db: db)
        }
        #expect(stored == nil)
        #expect(try database.writeSync { db in try DBSeason.fetchCount(db) } == 0)
        #expect(try database.writeSync { db in try DBEpisode.fetchCount(db) } == 0)
        #expect(try database.writeSync { db in
            try SeriesDetailData.seasonsLoaded(seriesId: 999, playlistId: playlist.id, db: db)
        } == nil)
    }

    // MARK: Favourite

    @Test
    func settingTheFavouriteTwiceKeepsOneRow() throws {
        let database = try seededDatabase()
        func count() throws -> Int {
            try database.writeSync { db in
                try DBFavorite.filter(Column("playlistId") == playlist.id && Column("type") == "series").fetchCount(db)
            }
        }
        try database.writeSync { db in
            try SeriesDetailData.setFavorite(true, seriesId: seriesId, playlistId: playlist.id, db: db)
            try SeriesDetailData.setFavorite(true, seriesId: seriesId, playlistId: playlist.id, db: db)
        }
        #expect(try count() == 1)
        try database.writeSync { db in
            try SeriesDetailData.setFavorite(false, seriesId: seriesId, playlistId: playlist.id, db: db)
            try SeriesDetailData.setFavorite(false, seriesId: seriesId, playlistId: playlist.id, db: db)
        }
        #expect(try count() == 0)
    }

    // MARK: Seed for the player shell

    private let series = DBSeries(seriesId: 7, name: "Show", cover: "show.jpg", playlistId: UUID())

    private func episode(cover: String? = "episode.jpg", title: String? = " Pilot ") -> DBEpisode {
        DBEpisode(
            id: "row-101", episodeId: "101", episodeNum: 3, title: title,
            containerExtension: "mkv", cover: cover, seasonId: "season-1"
        )
    }

    @Test
    func episodeTitleCarriesItsNumber() {
        #expect(SeriesDetailData.episodeTitle(episode()) == "3. Pilot")
        var unnumbered = episode()
        unnumbered.episodeNum = nil
        #expect(SeriesDetailData.episodeTitle(unnumbered) == "Pilot")
        #expect(SeriesDetailData.episodeTitle(episode(title: "  ")) == "3. " + L("detail.episode_fallback"))
    }

    @Test
    func seedForAnUnwatchedEpisodeStartsAtTheBeginning() {
        let seed = SeriesDetailData.playbackSeed(
            episode: episode(), history: nil, resumesFinished: false,
            series: series, playlistId: playlist.id, now: watchedAt
        )
        #expect(seed.id == "\(playlist.id)_series_101")
        #expect(seed.playlistId == playlist.id)
        #expect(seed.streamId == "101")
        #expect(seed.type == "series")
        #expect(seed.lastTimeMs == 0)
        #expect(seed.seriesId == "7")
        #expect(seed.title == "3. Pilot")
        #expect(seed.secondaryTitle == "Show")
        #expect(seed.imageURL == "episode.jpg")
        #expect(seed.containerExtension == "mkv")
        #expect(seed.lastWatchedAt == watchedAt)
    }

    @Test(arguments: [nil, "", "  ", "\n"] as [String?])
    func seedFallsBackToTheSeriesCover(cover: String?) {
        let seed = SeriesDetailData.playbackSeed(
            episode: episode(cover: cover), history: nil, resumesFinished: false,
            series: series, playlistId: playlist.id
        )
        #expect(seed.imageURL == "show.jpg")
    }

    /// The episode row is current; what an old history row stored about it is not.
    @Test
    func seedTakesTheEpisodeRowOverStoredHistoryTexts() {
        var stored = history(streamId: "101", lastTimeMs: 120_000, durationMs: 600_000)
        stored.seriesId = nil
        let seed = SeriesDetailData.playbackSeed(
            episode: episode(), history: stored, resumesFinished: false,
            series: series, playlistId: playlist.id
        )
        #expect(seed.id == stored.id)
        #expect(seed.lastTimeMs == 120_000)
        #expect(seed.durationMs == 600_000)
        #expect(seed.seriesId == "7")
        #expect(seed.title == "3. Pilot")
        #expect(seed.secondaryTitle == "Show")
        #expect(seed.imageURL == "episode.jpg")
        #expect(seed.containerExtension == "mkv")
    }

    @Test
    func finishedEpisodeStartsOverFromTheListButNotFromResume() {
        let finished = history(streamId: "101", lastTimeMs: 590_000, durationMs: 600_000)
        let picked = SeriesDetailData.playbackSeed(
            episode: episode(), history: finished, resumesFinished: false,
            series: series, playlistId: playlist.id
        )
        let resumed = SeriesDetailData.playbackSeed(
            episode: episode(), history: finished, resumesFinished: true,
            series: series, playlistId: playlist.id
        )
        #expect(picked.lastTimeMs == 0)
        #expect(resumed.lastTimeMs == 590_000)
    }
}
