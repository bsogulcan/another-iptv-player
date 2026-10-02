import Combine
import Foundation
import GRDB
import GRDBQuery
import Testing
@testable import another_iptv_player

/// The `immediate` flag of the database requests: with it the first value is there
/// before `sink` returns, which is what lets a view's first body use it; without
/// it the request keeps delivering one main-queue turn later.
///
/// Every test is a main-actor function: an immediate observation must start on the
/// main thread, as it does under `@Query`.
@Suite("Request scheduling")
struct RequestSchedulingTests {

    private let playlist = Playlist(name: "Scheduling", serverURL: "http://host:8080")
    private let watchedAt = Date(timeIntervalSince1970: 1_000_000)

    private var movieHistory: DBWatchHistory {
        DBWatchHistory(
            id: "\(playlist.id)_vod_5", playlistId: playlist.id, streamId: "5", type: "vod",
            lastTimeMs: 60_000, durationMs: 600_000, lastWatchedAt: watchedAt,
            seriesId: nil, title: "Film", secondaryTitle: nil, imageURL: nil, containerExtension: "mkv"
        )
    }

    private var episodeHistory: DBWatchHistory {
        DBWatchHistory(
            id: "\(playlist.id)_series_100", playlistId: playlist.id, streamId: "100", type: "series",
            lastTimeMs: 30_000, durationMs: 300_000, lastWatchedAt: watchedAt.addingTimeInterval(60),
            seriesId: "1", title: "Episode", secondaryTitle: "Show", imageURL: nil, containerExtension: nil
        )
    }

    /// A playlist with one film, one series (one season, one episode), a favourite
    /// and two history rows.
    private func seededDatabase() throws -> AppDatabase {
        let database = AppDatabase.empty()
        let pid = playlist.id
        try database.writeSync { db in
            try playlist.insert(db)
            try DBVODStream(streamId: 5, name: "Film", playlistId: pid).insert(db)
            try DBSeries(seriesId: 1, name: "Show", seasonsLoaded: true, playlistId: pid).insert(db)
            try DBSeason(id: "season-1", seasonNumber: 1, seriesId: 1, playlistId: pid).insert(db)
            try DBEpisode(id: "episode-1", episodeId: "100", episodeNum: 1, title: "Pilot", seasonId: "season-1").insert(db)
            try DBFavorite(streamId: 5, playlistId: pid, type: "vod",
                           createdAt: Date(timeIntervalSince1970: 1_000)).insert(db)
            try movieHistory.insert(db)
            try episodeHistory.insert(db)
        }
        return database
    }

    /// Subscribes and returns what had been delivered by the time `sink` returned.
    private func valuesOnSubscription<Request: Queryable>(
        _ request: Request, in database: AppDatabase
    ) throws -> [Request.Value] where Request.Context == AppDatabase {
        var received: [Request.Value] = []
        let cancellable = try request.publisher(in: database)
            .sink(receiveCompletion: { _ in }, receiveValue: { received.append($0) })
        cancellable.cancel()
        return received
    }

    // MARK: Immediate

    @Test
    func playlistListIsAlwaysDeliveredOnSubscription() throws {
        let database = try seededDatabase()
        let values = try valuesOnSubscription(PlaylistRequest(), in: database)
        // Compared by id: `createdAt` comes back from the database at millisecond precision.
        #expect(values.map { $0?.map(\.id) } == [[playlist.id]])
    }

    @Test
    func immediateByIDRequestsDeliverTheStoredRowOnSubscription() throws {
        let database = try seededDatabase()
        let pid = playlist.id

        let films = try valuesOnSubscription(
            VODByIDRequest(streamId: 5, playlistId: pid, immediate: true), in: database)
        #expect(films.count == 1)
        #expect(films.first??.name == "Film")

        let series = try valuesOnSubscription(
            SeriesByIDRequest(seriesId: 1, playlistId: pid, immediate: true), in: database)
        #expect(series.count == 1)
        #expect(series.first??.seasonsLoaded == true)

        let seasons = try valuesOnSubscription(
            SeasonsRequest(seriesId: 1, playlistId: pid, immediate: true), in: database)
        #expect(seasons.map { $0.map(\.id) } == [["season-1"]])

        let episodes = try valuesOnSubscription(
            EpisodesRequest(seasonId: "season-1", immediate: true), in: database)
        #expect(episodes.map { $0.map(\.id) } == [["episode-1"]])
    }

    @Test
    func immediateFavouriteAndHistoryRequestsDeliverOnSubscription() throws {
        let database = try seededDatabase()
        let pid = playlist.id

        let favourite = try valuesOnSubscription(
            IsFavoriteRequest(streamId: 5, playlistId: pid, type: "vod", immediate: true), in: database)
        #expect(favourite == [true])

        let history = try valuesOnSubscription(
            WatchHistoryRequest(streamId: "5", playlistId: pid, type: "vod", immediate: true), in: database)
        #expect(history == [movieHistory])

        let recent = try valuesOnSubscription(
            RecentWatchHistoryRequest(playlistId: pid, limit: 10, immediate: true), in: database)
        // Newest first.
        #expect(recent.map { $0.map(\.streamId) } == [["100", "5"]])

        let recentFilms = try valuesOnSubscription(
            RecentWatchHistoryRequest(playlistId: pid, limit: 10, type: "vod", immediate: true), in: database)
        #expect(recentFilms.map { $0.map(\.streamId) } == [["5"]])

        let latestEpisode = try valuesOnSubscription(
            LatestSeriesWatchHistoryRequest(seriesId: "1", playlistId: pid, immediate: true), in: database)
        #expect(latestEpisode == [episodeHistory])
    }

    /// A missing row is still an answer: the view must be able to tell "not there"
    /// from "not delivered yet" on its first pass.
    @Test
    func immediateRequestDeliversAnAbsentRowAsItsValue() throws {
        let database = try seededDatabase()
        let pid = playlist.id

        let history = try valuesOnSubscription(
            WatchHistoryRequest(streamId: "999", playlistId: pid, type: "vod", immediate: true), in: database)
        #expect(history == [nil])

        let favourite = try valuesOnSubscription(
            IsFavoriteRequest(streamId: 999, playlistId: pid, type: "vod", immediate: true), in: database)
        #expect(favourite == [false])
    }

    // MARK: Default

    @Test
    func flagDefaultsToOffAndIsPartOfEquality() {
        let pid = playlist.id
        #expect(VODByIDRequest(streamId: 5, playlistId: pid).immediate == false)
        #expect(SeriesByIDRequest(seriesId: 1, playlistId: pid).immediate == false)
        #expect(SeasonsRequest(seriesId: 1, playlistId: pid).immediate == false)
        #expect(EpisodesRequest(seasonId: "season-1").immediate == false)
        #expect(IsFavoriteRequest(streamId: 5, playlistId: pid, type: "vod").immediate == false)
        #expect(WatchHistoryRequest(streamId: "5", playlistId: pid, type: "vod").immediate == false)
        #expect(RecentWatchHistoryRequest(playlistId: pid).immediate == false)
        #expect(LatestSeriesWatchHistoryRequest(seriesId: "1", playlistId: pid).immediate == false)

        // `@Query` restarts its observation when the request changes, so the flag
        // has to take part in the comparison.
        #expect(WatchHistoryRequest(streamId: "5", playlistId: pid, type: "vod")
                != WatchHistoryRequest(streamId: "5", playlistId: pid, type: "vod", immediate: true))
        #expect(IsFavoriteRequest(streamId: 5, playlistId: pid, type: "vod")
                != IsFavoriteRequest(streamId: 5, playlistId: pid, type: "vod", immediate: true))
    }

    @Test
    func defaultSchedulingStillDeliversAfterSubscription() async throws {
        let database = try seededDatabase()
        var received: [Bool] = []
        let cancellable = IsFavoriteRequest(streamId: 5, playlistId: playlist.id, type: "vod")
            .publisher(in: database)
            .sink { received.append($0) }
        defer { cancellable.cancel() }

        // The value is dispatched to the main queue, and this function has not
        // left the main actor yet.
        #expect(received.isEmpty)

        var waits = 0
        while received.isEmpty, waits < 1_000 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waits += 1
        }
        #expect(received == [true])
    }
}
