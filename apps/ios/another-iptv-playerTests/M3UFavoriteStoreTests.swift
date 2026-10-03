import Foundation
import GRDB
import Testing
@testable import another_iptv_player

@Suite("M3U favorite store")
struct M3UFavoriteStoreTests {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test
    func switchingPlaylistsDropsOldIDsBeforeTheNewReadArrives() async throws {
        let database = AppDatabase.empty()
        let first = EPGTestSupport.m3uPlaylist()
        let second = EPGTestSupport.m3uPlaylist()
        try await database.write { db in
            try first.insert(db)
            try second.insert(db)
            try DBM3UFavorite(channelId: "first", playlistId: first.id).insert(db)
            try DBM3UFavorite(channelId: "second", playlistId: second.id).insert(db)
        }
        let store = M3UFavoriteStore(database: database)
        #expect(!store.isLoaded(for: first.id))
        store.track(playlistId: first.id)
        #expect(await eventually { store.isLoaded(for: first.id) })
        #expect(store.favoriteIds == ["first"])

        store.track(playlistId: second.id)
        #expect(store.favoriteIds.isEmpty)
        #expect(!store.isLoaded(for: second.id))
        #expect(!store.isLoaded(for: first.id))
        #expect(await eventually { store.isLoaded(for: second.id) })
        #expect(store.favoriteIds == ["second"])

        store.track(playlistId: second.id)
        #expect(store.isLoaded(for: second.id))
        #expect(store.favoriteIds == ["second"])
    }

    @Test
    func emptyIsKnownOnlyAfterTheReadAndExternalWritesStayVisible() async throws {
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.m3uPlaylist()
        try await database.write { db in try playlist.insert(db) }
        let store = M3UFavoriteStore(database: database)
        store.track(playlistId: playlist.id)
        #expect(!store.isLoaded(for: playlist.id))
        #expect(await eventually { store.isLoaded(for: playlist.id) })
        #expect(store.favoriteIds.isEmpty)
        try await database.write { db in
            try DBM3UFavorite(channelId: "added", playlistId: playlist.id).insert(db)
        }
        #expect(await eventually { store.favoriteIds == ["added"] })
        try await database.write { db in
            try db.execute(sql: "DELETE FROM m3uFavorite WHERE playlistId = ?", arguments: [playlist.id])
        }
        #expect(await eventually { store.favoriteIds.isEmpty })
        #expect(store.isLoaded(for: playlist.id))
    }
}

extension M3UFavoriteStoreTests {
    @Test
    func failedObservationCanBeRetriedForTheSamePlaylist() async throws {
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.m3uPlaylist()
        try await database.write { db in
            try playlist.insert(db)
            try DBM3UFavorite(channelId: "stored", playlistId: playlist.id).insert(db)
            try db.execute(sql: "ALTER TABLE m3uFavorite RENAME TO unavailableFavorites")
        }
        let store = M3UFavoriteStore(database: database)
        store.track(playlistId: playlist.id)
        #expect(await eventually { store.error(for: playlist.id) != nil })
        #expect(!store.isLoaded(for: playlist.id))
        try await database.write { db in
            try db.execute(sql: "ALTER TABLE unavailableFavorites RENAME TO m3uFavorite")
        }
        store.track(playlistId: playlist.id)
        #expect(store.error(for: playlist.id) == nil)
        #expect(await eventually { store.isLoaded(for: playlist.id) })
        #expect(store.favoriteIds == ["stored"])
    }
}
