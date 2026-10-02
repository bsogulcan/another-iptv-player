import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// `XtreamImporter.syncAndSave`: an edit replaces the catalog, and a cancel either
/// leaves nothing behind or comes too late to matter.
@MainActor
@Suite("Xtream importer")
struct XtreamImporterTests {

    /// Lets a callback cancel the task that is running it. The task does not exist
    /// yet when the callback is written.
    private final class TaskCanceller {
        var cancel: (() -> Void)?
    }

    private func importCatalog(
        _ payload: CannedXtreamAPIClient.Payload, into database: AppDatabase, as playlist: Playlist
    ) async throws {
        let client = CannedXtreamAPIClient(playlist: playlist, payload: payload)
        try await XtreamImporter.syncAndSave(playlist: playlist, client: client, database: database) { _ in }
    }

    // MARK: - Add and edit

    @Test
    func aFirstImportSavesThePlaylistAndItsCatalog() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()
        var phases: [XtreamImporter.Phase] = []
        var messages: [String] = []
        let client = CannedXtreamAPIClient(playlist: playlist, payload: try .withAdultContent())

        try await XtreamImporter.syncAndSave(
            playlist: playlist, client: client, database: database,
            progress: { messages.append($0) },
            onPhase: { phases.append($0) }
        )

        #expect(phases == [.downloading, .saving])
        #expect(messages == [L("add_playlist.fetching_categories"), L("add_playlist.saving_db")])
        #expect(client.requestCount == 6)
        let playlistId = playlist.id
        let saved = try await database.read { db in try Playlist.fetchOne(db, key: playlistId) }
        #expect(saved?.name == playlist.name)
        #expect(saved?.serverURL == playlist.serverURL)
        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", database: database) == ["1", "10", "20", "11", "2", "21"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "liveStream", database: database) == ["1", "2", "3"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "vodStream", database: database) == ["100", "101", "102"])
        #expect(try await PlaylistCatalogFixture.ids("seriesId", in: "series", database: database) == ["500", "501"])
    }

    @Test
    func seriesAreStoredWithTheirFullColumnSet() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()

        try await importCatalog(try .withAdultContent(), into: database, as: playlist)

        let show = try await database.read { db in
            try DBSeries.filter(Column("seriesId") == 500).fetchOne(db)
        }
        #expect(show?.cast == "A, B")
        #expect(show?.director == "C")
        #expect(show?.releaseDate == "2020-01-01")
        #expect(show?.youtubeTrailer == "abc")
        #expect(show?.lastModified == "1700000500")
        let movie = try await database.read { db in
            try DBVODStream.filter(Column("streamId") == 100).fetchOne(db)
        }
        #expect(movie?.added == "1700000000")
    }

    @Test
    func anEditRemovesWhatTheNewPayloadNoLongerContains() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()
        try await importCatalog(try .withAdultContent(), into: database, as: playlist)

        // Same playlist id, another server: a different, smaller catalog.
        var edited = playlist
        edited.serverURL = "http://other.invalid"
        var payload = CannedXtreamAPIClient.Payload()
        payload.liveCategories = try PlaylistCatalogFixture.panelObjects([
            ["category_id": "5", "category_name": "Sports"],
        ])
        payload.liveStreams = try PlaylistCatalogFixture.panelObjects([
            ["stream_id": 3, "name": "Kept id", "category_id": "5"],
            ["stream_id": 40, "name": "New", "category_id": "5"],
        ])
        try await importCatalog(payload, into: database, as: edited)

        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", database: database) == ["5"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "liveStream", database: database) == ["3", "40"])
        #expect(try await PlaylistCatalogFixture.count("vodStream", database: database) == 0)
        #expect(try await PlaylistCatalogFixture.count("series", database: database) == 0)
        let playlistId = playlist.id
        let saved = try await database.read { db in try Playlist.fetchOne(db, key: playlistId) }
        #expect(saved?.serverURL == "http://other.invalid")
        #expect(try await PlaylistCatalogFixture.count("playlist", database: database) == 1)
    }

    @Test
    func anEditThatTurnsTheAdultFilterOnRemovesTheAdultRows() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist(filterAdult: false)
        try await importCatalog(try .withAdultContent(), into: database, as: playlist)
        #expect(try await PlaylistCatalogFixture.count("liveStream", database: database) == 3)

        var edited = playlist
        edited.filterAdultContent = true
        try await importCatalog(try .withAdultContent(), into: database, as: edited)

        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", database: database) == ["1", "10", "20"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "liveStream", database: database) == ["1"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "vodStream", database: database) == ["100"])
        #expect(try await PlaylistCatalogFixture.ids("seriesId", in: "series", database: database) == ["500"])
    }

    /// Replacing the catalog deletes the series rows, and their cached seasons go
    /// with them, as on a refresh from Settings. They are fetched again on demand.
    @Test
    func anEditDropsCachedSeasonsLikeARefreshDoes() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()
        try await importCatalog(try .withAdultContent(), into: database, as: playlist)
        let season = DBSeason(
            id: DBSeason.scopedId(playlistId: playlist.id, seriesId: 500, seasonNumber: 1),
            seasonNumber: 1, name: "Season 1", overview: nil, cover: nil, airDate: nil,
            episodeCount: nil, voteAverage: nil, seriesId: 500, playlistId: playlist.id
        )
        try await database.write { db in try season.insert(db) }
        #expect(try await PlaylistCatalogFixture.count("season", database: database) == 1)

        try await importCatalog(try .withAdultContent(), into: database, as: playlist)

        #expect(try await PlaylistCatalogFixture.count("season", database: database) == 0)
        #expect(try await PlaylistCatalogFixture.count("series", database: database) == 2)
    }

    // MARK: - Cancellation

    @Test
    func aCancelDuringTheDownloadLeavesTheDatabaseUntouched() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()
        let client = CannedXtreamAPIClient(playlist: playlist, payload: try .withAdultContent())
        let canceller = TaskCanceller()
        // The canned answers ignore cancellation, the way the detached JSON decode of
        // the real client does: all six requests still deliver their payload.
        client.onRequest = { canceller.cancel?() }
        var phases: [XtreamImporter.Phase] = []

        let task = Task {
            try await XtreamImporter.syncAndSave(
                playlist: playlist, client: client, database: database,
                progress: { _ in },
                onPhase: { phases.append($0) }
            )
        }
        canceller.cancel = { task.cancel() }
        let result = await task.result

        switch result {
        case .success:
            Issue.record("a cancelled import must throw")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(client.requestCount == 6)
        #expect(phases == [.downloading])
        #expect(try await PlaylistCatalogFixture.count("playlist", database: database) == 0)
        #expect(try await PlaylistCatalogFixture.count("category", database: database) == 0)
        #expect(try await PlaylistCatalogFixture.count("liveStream", database: database) == 0)
    }

    @Test
    func aCancelledEditKeepsTheOldRowAndCatalog() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()
        try await importCatalog(try .withAdultContent(), into: database, as: playlist)

        var edited = playlist
        edited.username = "someone-else"
        let client = CannedXtreamAPIClient(playlist: edited)
        let canceller = TaskCanceller()
        client.onRequest = { canceller.cancel?() }
        let editedPlaylist = edited
        let task = Task {
            try await XtreamImporter.syncAndSave(playlist: editedPlaylist, client: client, database: database) { _ in }
        }
        canceller.cancel = { task.cancel() }
        _ = await task.result

        let playlistId = playlist.id
        let saved = try await database.read { db in try Playlist.fetchOne(db, key: playlistId) }
        #expect(saved?.username == "u")
        #expect(try await PlaylistCatalogFixture.count("liveStream", database: database) == 3)
        #expect(try await PlaylistCatalogFixture.count("vodStream", database: database) == 3)
    }

    @Test
    func aCancelOnceSavingHasStartedDoesNotInterruptTheImport() async throws {
        let database = AppDatabase.empty()
        let playlist = PlaylistCatalogFixture.playlist()
        let client = CannedXtreamAPIClient(playlist: playlist, payload: try .withAdultContent())
        let canceller = TaskCanceller()

        let task = Task {
            try await XtreamImporter.syncAndSave(
                playlist: playlist, client: client, database: database,
                progress: { _ in },
                onPhase: { phase in
                    if phase == .saving { canceller.cancel?() }
                }
            )
        }
        canceller.cancel = { task.cancel() }
        let result = await task.result

        if case .failure(let error) = result {
            Issue.record("the save phase must run to the end, got \(error)")
        }
        #expect(task.isCancelled)
        // Both writes went through: no playlist without content, no content without playlist.
        #expect(try await PlaylistCatalogFixture.count("playlist", database: database) == 1)
        #expect(try await PlaylistCatalogFixture.count("category", database: database) == 6)
        #expect(try await PlaylistCatalogFixture.count("liveStream", database: database) == 3)
        #expect(try await PlaylistCatalogFixture.count("vodStream", database: database) == 3)
        #expect(try await PlaylistCatalogFixture.count("series", database: database) == 2)
    }
}
