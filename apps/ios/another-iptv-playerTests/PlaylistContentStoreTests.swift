import Combine
import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// `PlaylistContentStore` driven as a private instance over an in-memory database:
/// the change signals, what is in place when they fire, the refresh error channel
/// and the adult-content flag a sync obeys.
@MainActor
@Suite("Playlist content store")
struct PlaylistContentStoreTests {
    private let playlist = PlaylistCatalogFixture.playlist()
    private let uncategorized = PlaylistContentStore.uncategorizedCategoryId

    /// Two live categories with three channels (one without a category), one movie
    /// category with three movies (one in an unknown category), one series category
    /// with two series.
    private func seededDatabase() async throws -> AppDatabase {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let categories = [
            PlaylistCatalogFixture.category("1", type: "live", sortIndex: 0, in: playlist),
            PlaylistCatalogFixture.category("2", type: "live", sortIndex: 1, in: playlist),
            PlaylistCatalogFixture.category("10", type: "vod", in: playlist),
            PlaylistCatalogFixture.category("20", type: "series", in: playlist),
        ]
        let live = [
            PlaylistCatalogFixture.live(1, category: "1", in: playlist),
            PlaylistCatalogFixture.live(2, category: "2", in: playlist),
            PlaylistCatalogFixture.live(3, category: nil, in: playlist),
        ]
        let movies = [
            PlaylistCatalogFixture.vod(100, category: "10", added: "200", in: playlist),
            PlaylistCatalogFixture.vod(101, category: "10", added: "300", in: playlist),
            PlaylistCatalogFixture.vod(102, category: "77", added: "100", in: playlist),
        ]
        let shows = [
            PlaylistCatalogFixture.series(500, category: "20", lastModified: "50", in: playlist),
            PlaylistCatalogFixture.series(501, category: "20", lastModified: "60", in: playlist),
        ]
        try await database.write { db in
            for row in categories { try row.insert(db) }
            for row in live { try row.insert(db) }
            for row in movies { try row.insert(db) }
            for row in shows { try row.insert(db) }
        }
        return database
    }

    private func revisions(_ store: PlaylistContentStore) -> [Int] {
        [store.liveRevision, store.vodRevision, store.seriesRevision]
    }

    // MARK: - Load

    /// What the store looks like at the moment `liveRevision` changes.
    private struct LoadStep: Equatable {
        var revision: Int
        var isLoading: Bool
        var streamsLoaded: Bool
        var categories: [String]
        var streams: Int
    }

    @Test
    func loadSignalsTheCategoriesFirstAndTheStreamsSecond() async throws {
        let database = try await seededDatabase()
        let store = PlaylistContentStore(database: database)
        var steps: [LoadStep] = []
        // A revision is the last assignment of a change, so everything else the store
        // publishes already has its new value when this fires.
        let watch = store.$liveRevision.dropFirst().sink { revision in
            steps.append(LoadStep(
                revision: revision,
                isLoading: store.isLoading,
                streamsLoaded: store.streamsLoaded,
                categories: store.liveCategories.map(\.id),
                streams: store.liveStreams.count
            ))
        }

        await store.loadPlaylist(playlist)
        watch.cancel()

        // 1: the previous catalog is cleared. 2: categories. 3: streams.
        #expect(steps.count == 3)
        #expect(steps.map(\.revision) == [1, 2, 3])
        #expect(steps.first == LoadStep(
            revision: 1, isLoading: true, streamsLoaded: false, categories: [], streams: 0
        ))
        #expect(steps.dropFirst().first == LoadStep(
            revision: 2, isLoading: false, streamsLoaded: false, categories: ["1", "2"], streams: 0
        ))
        #expect(steps.last == LoadStep(
            revision: 3, isLoading: false, streamsLoaded: true, categories: ["1", "2", uncategorized], streams: 3
        ))
        #expect(revisions(store) == [3, 3, 3])
        #expect(store.loadError == nil)
        #expect(store.activePlaylistId == playlist.id)
    }

    @Test
    func aNormalLoadHasTheUncategorizedBucketAndItsCategory() async throws {
        let store = PlaylistContentStore(database: try await seededDatabase())

        await store.loadPlaylist(playlist)

        #expect(store.liveCategories.map(\.id) == ["1", "2", uncategorized])
        #expect(store.liveStreamsByCategoryId[uncategorized]?.map(\.stream.streamId) == [3])
        #expect(store.vodCategories.map(\.id) == ["10", uncategorized])
        #expect(store.vodStreamsByCategoryId[uncategorized]?.map(\.stream.streamId) == [102])
        #expect(store.vodStreamsByCategoryId["77"] == nil)
        // Nothing to bucket: no synthetic category.
        #expect(store.seriesCategories.map(\.id) == ["20"])
        #expect(store.seriesItemsByCategoryId.keys.sorted() == ["20"])
    }

    @Test
    func aLoadPublishesTheRecentCandidatesWithTheStreams() async throws {
        let store = PlaylistContentStore(database: try await seededDatabase())
        var candidatesAtBump: [[Int]] = []
        let watch = store.$vodRevision.dropFirst().sink { _ in
            candidatesAtBump.append(store.recentVODCandidates.map(\.streamId))
        }

        await store.loadPlaylist(playlist)
        watch.cancel()

        // Movie 102 sits in a category the panel does not list: no shelf shows it.
        #expect(store.recentVODCandidates.map(\.streamId) == [101, 100])
        #expect(store.recentSeriesCandidates.map(\.seriesId) == [501, 500])
        // In place before the revision that announces the streams.
        #expect(candidatesAtBump.last == [101, 100])
    }

    /// What the store says about itself at the moment `liveRevision` changes.
    private struct StoreState: Equatable {
        var revision: Int
        var activePlaylistId: UUID?
        var isLoading: Bool
        var streamsLoaded: Bool
        var categories: [String]
        var streams: Int
        var loadError: String?
        var refreshError: String?
    }

    private func watchLiveRevision(
        of store: PlaylistContentStore, into states: @escaping (StoreState) -> Void
    ) -> AnyCancellable {
        store.$liveRevision.dropFirst().sink { revision in
            states(StoreState(
                revision: revision,
                activePlaylistId: store.activePlaylistId,
                isLoading: store.isLoading,
                streamsLoaded: store.streamsLoaded,
                categories: store.liveCategories.map(\.id),
                streams: store.liveStreams.count,
                loadError: store.loadError,
                refreshError: store.refreshError
            ))
        }
    }

    @Test
    func aPlaylistSwitchSignalsTheClearedCatalogUnderTheNewPlaylist() async throws {
        let database = try await seededDatabase()
        // A second playlist with a catalog of its own, so opening it reads the
        // database and never asks a panel.
        let other = PlaylistCatalogFixture.playlist()
        let otherCategory = PlaylistCatalogFixture.category("7", type: "live", in: other)
        let otherChannel = PlaylistCatalogFixture.live(70, category: "7", in: other)
        try await database.write { db in
            try other.insert(db)
            try otherCategory.insert(db)
            try otherChannel.insert(db)
        }
        let store = PlaylistContentStore(database: database)
        await store.loadPlaylist(playlist)
        store.refreshError = "left over from the first playlist"

        var states: [StoreState] = []
        let watch = watchLiveRevision(of: store) { states.append($0) }
        await store.loadPlaylist(other)
        watch.cancel()

        // The revision that announces the empty catalog must not be readable as "the
        // first playlist finished loading and has nothing".
        #expect(states.first == StoreState(
            revision: 4, activePlaylistId: other.id, isLoading: true, streamsLoaded: false,
            categories: [], streams: 0, loadError: nil, refreshError: nil
        ))
        #expect(states.map(\.revision) == [4, 5, 6])
        #expect(states.last == StoreState(
            revision: 6, activePlaylistId: other.id, isLoading: false, streamsLoaded: true,
            categories: ["7"], streams: 1, loadError: nil, refreshError: nil
        ))
    }

    // MARK: - Reload

    @Test
    func aScopedReloadBumpsOnlyItsTypeAndLeavesStreamsLoadedAlone() async throws {
        let database = try await seededDatabase()
        let store = PlaylistContentStore(database: database)
        await store.loadPlaylist(playlist)

        let channel = PlaylistCatalogFixture.live(9, category: "1", in: playlist)
        let movie = PlaylistCatalogFixture.vod(109, category: "10", added: "900", in: playlist)
        let show = PlaylistCatalogFixture.series(509, category: "20", lastModified: "900", in: playlist)
        try await database.write { db in
            try channel.insert(db)
            try movie.insert(db)
            try show.insert(db)
        }

        var streamsLoadedWrites = 0
        let flagWatch = store.$streamsLoaded.dropFirst().sink { _ in streamsLoadedWrites += 1 }
        var liveIdsAtBump: [Int] = []
        let liveWatch = store.$liveRevision.dropFirst().sink { _ in
            liveIdsAtBump = store.liveStreams.map(\.stream.streamId)
        }

        await store.reloadFromDatabaseIfActive(playlistId: playlist.id, only: .live)
        #expect(revisions(store) == [4, 3, 3])
        #expect(liveIdsAtBump == [1, 2, 3, 9])
        #expect(store.liveStreamsByCategoryId["1"]?.map(\.stream.streamId) == [1, 9])
        // The other types still hold what the load gave them.
        #expect(store.vodStreams.count == 3)
        #expect(store.seriesItems.count == 2)

        await store.reloadFromDatabaseIfActive(playlistId: playlist.id, only: .vod)
        #expect(revisions(store) == [4, 4, 3])
        #expect(store.vodStreams.map(\.stream.streamId) == [100, 101, 102, 109])
        #expect(store.recentVODCandidates.first?.streamId == 109)
        #expect(store.vodCategories.map(\.id) == ["10", uncategorized])

        await store.reloadFromDatabaseIfActive(playlistId: playlist.id, only: .series)
        #expect(revisions(store) == [4, 4, 4])
        #expect(store.seriesItems.map(\.series.seriesId) == [500, 501, 509])
        #expect(store.recentSeriesCandidates.first?.seriesId == 509)

        flagWatch.cancel()
        liveWatch.cancel()
        #expect(streamsLoadedWrites == 0)
        #expect(store.streamsLoaded)
        #expect(store.loadError == nil)
    }

    @Test
    func aFullReloadLowersStreamsLoadedWhileItReadsAndBumpsEveryTypeOnce() async throws {
        let database = try await seededDatabase()
        let store = PlaylistContentStore(database: database)
        await store.loadPlaylist(playlist)

        let channel = PlaylistCatalogFixture.live(9, category: "2", in: playlist)
        try await database.write { db in try channel.insert(db) }

        // `$streamsLoaded` publishes the value about to be stored, together with the
        // lists as they are at that moment.
        var flagWrites: [Bool] = []
        var liveCountAtFlagWrite: [Int] = []
        let flagWatch = store.$streamsLoaded.dropFirst().sink { value in
            flagWrites.append(value)
            liveCountAtFlagWrite.append(store.liveStreams.count)
        }
        var states: [StoreState] = []
        let liveWatch = watchLiveRevision(of: store) { states.append($0) }

        await store.reloadFromDatabaseIfActive(playlistId: playlist.id)
        flagWatch.cancel()
        liveWatch.cancel()

        // Down with the old lists still in place, up once the new ones are.
        #expect(flagWrites == [false, true])
        #expect(liveCountAtFlagWrite == [3, 4])
        #expect(states == [StoreState(
            revision: 4, activePlaylistId: playlist.id, isLoading: false, streamsLoaded: true,
            categories: ["1", "2", uncategorized], streams: 4, loadError: nil, refreshError: nil
        )])
        #expect(revisions(store) == [4, 4, 4])
        #expect(store.liveStreams.map(\.stream.streamId) == [1, 2, 3, 9])
        #expect(store.streamsLoaded)
    }

    @Test
    func aFullReloadThatFailsKeepsTheCatalogAndRaisesStreamsLoadedAgain() async throws {
        let database = try await seededDatabase()
        let store = PlaylistContentStore(database: database)
        await store.loadPlaylist(playlist)
        // Makes the live read fail; the other two still succeed.
        try await database.write { db in try db.execute(sql: "DROP TABLE liveStream") }

        await store.reloadFromDatabaseIfActive(playlistId: playlist.id)

        #expect(store.loadError != nil)
        #expect(store.streamsLoaded)
        #expect(revisions(store) == [3, 3, 3])
        #expect(store.liveStreams.count == 3)
        #expect(store.vodStreams.count == 3)
        #expect(store.seriesItems.count == 2)
    }

    @Test
    func aReloadForAPlaylistThatIsNotOpenChangesNothing() async throws {
        let store = PlaylistContentStore(database: try await seededDatabase())
        await store.loadPlaylist(playlist)
        let other = UUID()

        await store.reloadFromDatabaseIfActive(playlistId: other)
        await store.reloadFromDatabaseIfActive(playlistId: other, only: .live)
        try await store.reloadFromDatabase(playlistId: other)

        #expect(revisions(store) == [3, 3, 3])
        #expect(store.liveStreams.count == 3)
        #expect(store.streamsLoaded)
    }

    @Test
    func unloadClearsTheCatalogAndBumpsEveryType() async throws {
        let store = PlaylistContentStore(database: try await seededDatabase())
        await store.loadPlaylist(playlist)
        store.loadError = "stale"
        store.refreshError = "stale"
        store.loadingMessage = "stale"
        store.isLoading = true

        var states: [StoreState] = []
        let watch = watchLiveRevision(of: store) { states.append($0) }
        store.unload()
        watch.cancel()

        // One signal, and everything unload resets is already reset when it fires.
        #expect(states == [StoreState(
            revision: 4, activePlaylistId: nil, isLoading: false, streamsLoaded: false,
            categories: [], streams: 0, loadError: nil, refreshError: nil
        )])
        #expect(store.loadingMessage == nil)
        #expect(revisions(store) == [4, 4, 4])
        #expect(store.activePlaylistId == nil)
        #expect(!store.streamsLoaded)
        #expect(store.liveCategories.isEmpty)
        #expect(store.liveStreams.isEmpty)
        #expect(store.vodStreamsByCategoryId.isEmpty)
        #expect(store.recentVODCandidates.isEmpty)
        #expect(store.recentSeriesCandidates.isEmpty)
    }

    @Test
    func aMetadataPatchReachesTheCopiesButNotTheRevisions() async throws {
        let store = PlaylistContentStore(database: try await seededDatabase())
        await store.loadPlaylist(playlist)
        var updated = try #require(store.recentVODCandidates.first)
        updated.plot = "A plot"
        updated.metadataLoaded = true

        store.applyVODMetadata(updated)

        #expect(revisions(store) == [3, 3, 3])
        #expect(store.recentVODCandidates.first == updated)
        #expect(store.vodStreams.first { $0.stream.streamId == updated.streamId }?.stream == updated)
        #expect(store.vodStreamsByCategoryId["10"]?.first { $0.stream.streamId == updated.streamId }?.stream == updated)
    }

    // MARK: - Refresh errors

    @Test
    func aFailedRefreshIsReportedApartFromLoadErrors() async throws {
        let client = CannedXtreamAPIClient(playlist: playlist, failure: XtreamError.serverError("HTTP 500"))
        let store = PlaylistContentStore(database: try await seededDatabase(), makeClient: { _ in client })
        await store.loadPlaylist(playlist)
        // The seeded catalog is read from the database; nothing asked the panel yet.
        #expect(client.requestCount == 0)

        await store.refreshFromNetwork(playlist: playlist, only: .vod)

        let message = XtreamError.serverError("HTTP 500").localizedDescription
        #expect(store.refreshError == message)
        #expect(store.loadError == nil)
        #expect(store.loadingMessage == nil)
        // The catalog on screen survives a failed refresh.
        #expect(store.vodStreams.count == 3)
        #expect(revisions(store) == [3, 3, 3])

        store.refreshError = nil
        await store.refreshFromNetwork(playlist: playlist)
        #expect(store.refreshError == message)
        #expect(store.loadError == nil)
    }

    @Test
    func aRefreshThatFailsAfterItsPlaylistWasClosedIsDropped() async throws {
        let client = CannedXtreamAPIClient(playlist: playlist, failure: XtreamError.serverError("HTTP 500"))
        let store = PlaylistContentStore(database: try await seededDatabase(), makeClient: { _ in client })
        await store.loadPlaylist(playlist)
        // The user leaves the playlist while the panel is still answering.
        client.onRequest = { store.unload() }

        await store.refreshFromNetwork(playlist: playlist, only: .live)
        #expect(store.refreshError == nil)
        #expect(store.loadError == nil)

        await store.refreshFromNetwork(playlist: playlist)
        #expect(store.refreshError == nil)
        #expect(store.loadError == nil)
    }

    @Test
    func aNewRefreshClearsThePreviousError() async throws {
        let client = CannedXtreamAPIClient(playlist: playlist, failure: XtreamError.serverError("HTTP 500"))
        let store = PlaylistContentStore(database: try await seededDatabase(), makeClient: { _ in client })
        await store.loadPlaylist(playlist)
        await store.refreshFromNetwork(playlist: playlist, only: .live)
        #expect(store.refreshError != nil)

        client.failure = nil
        client.payload = try .withAdultContent()
        await store.refreshFromNetwork(playlist: playlist, only: .live)

        #expect(store.refreshError == nil)
        #expect(store.liveStreams.map(\.stream.streamId) == [1, 2, 3])
        #expect(revisions(store) == [4, 3, 3])
    }

    // MARK: - Adult filter of a sync

    @Test
    func aScopedRefreshObeysTheStoredAdultFlagNotTheCallersCopy() async throws {
        // The row says "filter"; the copy the screens hold was taken before the switch.
        let stored = PlaylistCatalogFixture.playlist(filterAdult: true)
        var stale = stored
        stale.filterAdultContent = false
        let database = try await PlaylistCatalogFixture.database(with: stored)
        let client = CannedXtreamAPIClient(playlist: stale, payload: try .withAdultContent())
        let store = PlaylistContentStore(database: database, makeClient: { _ in client })
        // An empty catalog bootstraps from the panel, through the same sync.
        await store.loadPlaylist(stale)
        #expect(store.loadError == nil)

        await store.refreshFromNetwork(playlist: stale, only: .live)
        await store.refreshFromNetwork(playlist: stale, only: .vod)
        await store.refreshFromNetwork(playlist: stale, only: .series)

        #expect(store.refreshError == nil)
        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", type: "live", database: database) == ["1"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "liveStream", database: database) == ["1"])
        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", type: "vod", database: database) == ["10"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "vodStream", database: database) == ["100"])
        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", type: "series", database: database) == ["20"])
        #expect(try await PlaylistCatalogFixture.ids("seriesId", in: "series", database: database) == ["500"])
        #expect(store.liveStreams.map(\.stream.streamId) == [1])
        #expect(store.vodStreams.map(\.stream.streamId) == [100])
        #expect(store.seriesItems.map(\.series.seriesId) == [500])
    }

    @Test
    func aFullSyncObeysTheStoredAdultFlagInBothDirections() async throws {
        // Filter off in the row, on in the caller's copy: nothing may be dropped.
        let stored = PlaylistCatalogFixture.playlist(filterAdult: false)
        var stale = stored
        stale.filterAdultContent = true
        let database = try await PlaylistCatalogFixture.database(with: stored)
        let client = CannedXtreamAPIClient(playlist: stale, payload: try .withAdultContent())
        let store = PlaylistContentStore(database: database, makeClient: { _ in client })

        try await store.syncFromNetworkReplacingLocal(playlist: stale) { _ in }

        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "liveStream", database: database) == ["1", "2", "3"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "vodStream", database: database) == ["100", "101", "102"])
        #expect(try await PlaylistCatalogFixture.ids("seriesId", in: "series", database: database) == ["500", "501"])

        // Now the switch is flipped in Settings: only the row changes.
        var flipped = stored
        flipped.filterAdultContent = true
        let row = flipped
        try await database.write { db in try row.update(db) }
        stale.filterAdultContent = false

        try await store.syncFromNetworkReplacingLocal(playlist: stale) { _ in }

        #expect(try await PlaylistCatalogFixture.ids("id", in: "category", database: database) == ["1", "10", "20"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "liveStream", database: database) == ["1"])
        #expect(try await PlaylistCatalogFixture.ids("streamId", in: "vodStream", database: database) == ["100"])
        #expect(try await PlaylistCatalogFixture.ids("seriesId", in: "series", database: database) == ["500"])
    }

    @Test
    func theCallersFlagOnlyDecidesWhenThePlaylistRowIsMissing() async throws {
        let stored = PlaylistCatalogFixture.playlist(filterAdult: true)
        let database = try await PlaylistCatalogFixture.database(with: stored)
        let storedId = stored.id
        let missingId = UUID()

        let (fromRow, fromFallback) = try await database.read { db in
            (
                try PlaylistContentStore.adultFilterEnabled(playlistId: storedId, fallback: false, db: db),
                try PlaylistContentStore.adultFilterEnabled(playlistId: missingId, fallback: true, db: db)
            )
        }

        #expect(fromRow)
        #expect(fromFallback)
    }

    // MARK: - Rewrite helpers

    @Test
    func aStreamIdThePanelSendsTwiceKeepsTheLastEntry() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let categories: [XtreamCategory] = try PlaylistCatalogFixture.panelObjects([
            ["category_id": "10", "category_name": "Drama"],
        ])
        let streams: [XtreamVODStream] = try PlaylistCatalogFixture.panelObjects([
            ["stream_id": 7, "name": "First", "category_id": "10"],
            ["stream_id": 8, "name": "Other", "category_id": "10"],
            ["stream_id": 7, "name": "Second", "category_id": "10"],
        ])

        try await database.write { db in
            try PlaylistContentStore.replaceVODCatalog(
                db: db, pid: pid, categories: categories, streams: streams, filterAdult: false
            )
        }

        let names = try await database.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM vodStream ORDER BY streamId")
        }
        #expect(names == ["Second", "Other"])
    }
}
