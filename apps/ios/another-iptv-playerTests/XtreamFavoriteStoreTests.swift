import Combine
import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// `XtreamFavoriteStore` on a store of its own over an in-memory database: what it
/// reads, what it picks up from other writers and what it shows before its own write
/// has landed.
@Suite("Xtream favorite store")
struct XtreamFavoriteStoreTests {

    private let playlist = Playlist(name: "Favourites", serverURL: "http://host:8080")
    private let otherPlaylist = Playlist(name: "Other", serverURL: "http://other:8080")

    private func database() throws -> AppDatabase {
        let database = AppDatabase.empty()
        try database.writeSync { db in
            try playlist.insert(db)
            try otherPlaylist.insert(db)
        }
        return database
    }

    private func insert(_ streamId: Int, _ type: String, in playlist: Playlist, _ database: AppDatabase) async throws {
        let row = DBFavorite(streamId: streamId, playlistId: playlist.id, type: type)
        try await database.write { db in try row.insert(db) }
    }

    private func storedIDs(of playlist: Playlist, in database: AppDatabase) async throws -> XtreamFavoriteIDs {
        let playlistId = playlist.id
        return try await database.read { db in
            try FavoriteWriter.ids(playlistId: playlistId, db: db)
        }
    }

    /// The observation delivers on a later turn of the main queue. Polls instead of
    /// sleeping a fixed time, and gives up after `timeout` so a regression fails the
    /// expectation instead of hanging the run.
    private func eventually(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// A store that has read the playlist's favourites.
    private func trackedStore(_ database: AppDatabase) async -> XtreamFavoriteStore {
        let store = XtreamFavoriteStore(database: database)
        store.track(playlistId: playlist.id)
        let playlistId = playlist.id
        _ = await eventually { store.favoriteState(0, type: "live", playlistId: playlistId) != nil }
        return store
    }

    // MARK: Reading

    @Test
    func knowsNothingBeforeAPlaylistIsTracked() throws {
        let store = XtreamFavoriteStore(database: try database())

        #expect(store.ids == XtreamFavoriteIDs())
        #expect(!store.isFavorite(1, type: "vod"))
        #expect(store.favoriteState(1, type: "vod", playlistId: playlist.id) == nil)
    }

    @Test
    func readsTheStoredFavouritesOfTheTrackedPlaylist() async throws {
        let database = try database()
        try await insert(1, "live", in: playlist, database)
        try await insert(2, "vod", in: playlist, database)
        try await insert(3, "series", in: playlist, database)
        try await insert(4, "vod", in: otherPlaylist, database)

        let store = XtreamFavoriteStore(database: database)
        store.track(playlistId: playlist.id)

        #expect(await eventually { store.ids == XtreamFavoriteIDs(live: [1], vod: [2], series: [3]) })
        #expect(store.isFavorite(1, type: "live"))
        #expect(store.isFavorite(2, type: "vod"))
        #expect(store.isFavorite(3, type: "series"))
        #expect(!store.isFavorite(1, type: "vod"))
        #expect(!store.isFavorite(4, type: "vod"))
        #expect(store.favoriteState(2, type: "vod", playlistId: playlist.id) == true)
        #expect(store.favoriteState(9, type: "vod", playlistId: playlist.id) == false)
        #expect(store.favoriteState(4, type: "vod", playlistId: otherPlaylist.id) == nil)
    }

    /// The detail screens and the player write rows themselves.
    @Test
    func followsRowsOtherWritersInsertAndDelete() async throws {
        let database = try database()
        let store = await trackedStore(database)
        #expect(store.ids == XtreamFavoriteIDs())

        try await insert(5, "live", in: playlist, database)
        #expect(await eventually { store.isFavorite(5, type: "live") })

        let playlistId = playlist.id
        try await database.write { db in
            _ = try DBFavorite
                .filter(Column("streamId") == 5 && Column("playlistId") == playlistId && Column("type") == "live")
                .deleteAll(db)
        }
        #expect(await eventually { !store.isFavorite(5, type: "live") })
    }

    @Test
    func aChangeInAnotherPlaylistIsNotPublished() async throws {
        let database = try database()
        let store = await trackedStore(database)
        var publishes = 0
        let subscription = store.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        try await insert(5, "live", in: otherPlaylist, database)
        try await insert(6, "live", in: playlist, database)

        #expect(await eventually { store.isFavorite(6, type: "live") })
        #expect(publishes == 1)
        #expect(!store.isFavorite(5, type: "live"))
    }

    // MARK: Writing

    @Test
    func settingAFavouriteStoresIt() async throws {
        let database = try database()
        let store = await trackedStore(database)

        await store.setFavorite(true, streamId: 8, type: "vod", playlistId: playlist.id)
        #expect(store.isFavorite(8, type: "vod"))
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs(vod: [8]))

        await store.setFavorite(false, streamId: 8, type: "vod", playlistId: playlist.id)
        #expect(!store.isFavorite(8, type: "vod"))
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs())
    }

    /// The star has to answer the tap, not the database. The writer queue is held
    /// here, so neither the write nor an observation can have produced the state
    /// the store shows.
    @Test
    func theNewStateShowsBeforeTheWriteHasRun() async throws {
        let database = try database()
        let store = await trackedStore(database)
        let playlistId = playlist.id

        let release = DispatchSemaphore(value: 0)
        let (entered, signalEntered) = AsyncStream<Void>.makeStream()
        let blocker = Task.detached {
            try await database.write { _ in
                signalEntered.yield()
                release.wait()
            }
        }
        for await _ in entered { break }

        let write = Task { await store.setFavorite(true, streamId: 8, type: "vod", playlistId: playlistId) }
        let shownEarly = await eventually { store.isFavorite(8, type: "vod") }

        release.signal()
        try await blocker.value
        await write.value

        #expect(shownEarly)
        #expect(store.isFavorite(8, type: "vod"))
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs(vod: [8]))
    }

    @Test
    func settingTheSameStateTwiceIsHarmless() async throws {
        let database = try database()
        let store = await trackedStore(database)

        await store.setFavorite(true, streamId: 8, type: "vod", playlistId: playlist.id)
        await store.setFavorite(true, streamId: 8, type: "vod", playlistId: playlist.id)
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs(vod: [8]))

        await store.setFavorite(false, streamId: 8, type: "vod", playlistId: playlist.id)
        await store.setFavorite(false, streamId: 8, type: "vod", playlistId: playlist.id)
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs())
        #expect(store.ids == XtreamFavoriteIDs())
    }

    @Test
    func toggleFlipsTheState() async throws {
        let database = try database()
        try await insert(1, "series", in: playlist, database)
        let store = await trackedStore(database)

        await store.toggle(1, type: "series", playlistId: playlist.id)
        #expect(!store.isFavorite(1, type: "series"))
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs())

        await store.toggle(1, type: "series", playlistId: playlist.id)
        #expect(store.isFavorite(1, type: "series"))
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs(series: [1]))
    }

    /// Two taps in a row, the second before the first write has finished: each sees
    /// the state the one before it left.
    @Test
    func aDoubleTapOnToggleEndsWhereItStarted() async throws {
        let database = try database()
        let store = await trackedStore(database)
        let playlistId = playlist.id

        async let first: Void = store.toggle(2, type: "live", playlistId: playlistId)
        async let second: Void = store.toggle(2, type: "live", playlistId: playlistId)
        _ = await (first, second)

        #expect(!store.isFavorite(2, type: "live"))
        #expect(try await storedIDs(of: playlist, in: database) == XtreamFavoriteIDs())
    }

    /// The store cannot answer for a playlist it does not follow, so the database
    /// decides which way the toggle goes.
    @Test
    func toggleOfAnUntrackedPlaylistReadsTheStateFromTheDatabase() async throws {
        let database = try database()
        try await insert(4, "vod", in: otherPlaylist, database)
        let store = await trackedStore(database)

        await store.toggle(4, type: "vod", playlistId: otherPlaylist.id)
        #expect(try await storedIDs(of: otherPlaylist, in: database) == XtreamFavoriteIDs())

        await store.toggle(4, type: "vod", playlistId: otherPlaylist.id)
        #expect(try await storedIDs(of: otherPlaylist, in: database) == XtreamFavoriteIDs(vod: [4]))
        #expect(!store.isFavorite(4, type: "vod"))
    }

    @Test
    func aWriteForAnotherPlaylistDoesNotTouchTheTrackedIds() async throws {
        let database = try database()
        let store = await trackedStore(database)

        await store.setFavorite(true, streamId: 4, type: "vod", playlistId: otherPlaylist.id)

        #expect(store.ids == XtreamFavoriteIDs())
        #expect(try await storedIDs(of: otherPlaylist, in: database) == XtreamFavoriteIDs(vod: [4]))
    }

    /// A write that fails must not leave the early update behind: nothing in the
    /// database changed, so no observation would correct it.
    @Test
    func aFailedWriteIsTakenBack() async throws {
        let database = try database()
        let ghost = UUID()
        let store = XtreamFavoriteStore(database: database)
        store.track(playlistId: ghost)
        _ = await eventually { store.favoriteState(0, type: "vod", playlistId: ghost) != nil }

        // No playlist row: the foreign key refuses the favourite.
        await store.setFavorite(true, streamId: 8, type: "vod", playlistId: ghost)

        #expect(!store.isFavorite(8, type: "vod"))
        #expect(store.ids == XtreamFavoriteIDs())
    }

    // MARK: Switching playlists

    @Test
    func trackingAnotherPlaylistDropsTheOldIdsImmediately() async throws {
        let database = try database()
        try await insert(1, "live", in: playlist, database)
        try await insert(2, "live", in: otherPlaylist, database)
        let store = await trackedStore(database)
        #expect(store.isFavorite(1, type: "live"))

        store.track(playlistId: otherPlaylist.id)

        // Stream ids repeat between panels: until the new read arrives the store
        // answers "not a favourite" and "unknown", never with the old playlist's ids.
        #expect(store.ids == XtreamFavoriteIDs())
        #expect(store.favoriteState(1, type: "live", playlistId: otherPlaylist.id) == nil)
        #expect(store.favoriteState(1, type: "live", playlistId: playlist.id) == nil)

        #expect(await eventually { store.isFavorite(2, type: "live") })
        #expect(!store.isFavorite(1, type: "live"))
        #expect(store.trackedPlaylistId == otherPlaylist.id)
    }

    @Test
    func trackingTheSamePlaylistAgainKeepsWhatIsLoaded() async throws {
        let database = try database()
        try await insert(1, "live", in: playlist, database)
        let store = await trackedStore(database)

        store.track(playlistId: playlist.id)

        #expect(store.isFavorite(1, type: "live"))
        #expect(store.favoriteState(1, type: "live", playlistId: playlist.id) == true)
    }
}
