import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// `AppDatabase.updatePlaylist` and the two lookup indexes added next to it.
@Suite("Playlist row updates")
struct PlaylistRowUpdateTests {

    private func insertedPlaylist(in database: AppDatabase) async throws -> Playlist {
        let playlist = Playlist(
            name: "Home", serverURL: "http://host:8080", username: "user", password: "secret",
            serverTimezone: "Europe/Istanbul", timeshiftStyle: "php"
        )
        try await database.write { db in try playlist.insert(db) }
        return playlist
    }

    // MARK: updatePlaylist

    /// Two screens hold the row as it was when they opened. Each changes its own
    /// column; neither may put the other's column back.
    @Test
    func updatesMadeFromStaleCopiesBothSurvive() async throws {
        let database = AppDatabase.empty()
        let original = try await insertedPlaylist(in: database)
        let guideScreenCopy = original
        let filterScreenCopy = original

        let afterGuide = try await database.updatePlaylist(id: guideScreenCopy.id) { $0.epgEnabled = false }
        let afterFilter = try await database.updatePlaylist(id: filterScreenCopy.id) { $0.filterAdultContent = true }

        #expect(afterGuide?.epgEnabled == false)
        #expect(afterGuide?.filterAdultContent == false)
        // The second write started from the stored row, not from its caller's copy.
        #expect(afterFilter?.epgEnabled == false)
        #expect(afterFilter?.filterAdultContent == true)

        let stored = try await database.read { db in try Playlist.fetchOne(db, key: original.id) }
        #expect(stored?.epgEnabled == false)
        #expect(stored?.filterAdultContent == true)
        // Untouched columns are as they were.
        #expect(stored?.name == "Home")
        #expect(stored?.serverURL == "http://host:8080")
        #expect(stored?.username == "user")
        #expect(stored?.password == "secret")
        #expect(stored?.serverTimezone == "Europe/Istanbul")
        #expect(stored?.timeshiftStyle == "php")
        #expect(stored == afterFilter)
    }

    /// A column written behind the caller's back (the catch-up probe does this
    /// during playback) is not reverted by a later settings write.
    @Test
    func updateKeepsColumnsWrittenByOthers() async throws {
        let database = AppDatabase.empty()
        let original = try await insertedPlaylist(in: database)
        try await database.write { db in
            _ = try Playlist.filter(key: original.id)
                .updateAll(db, [Column("timeshiftStyle").set(to: "m3u8"),
                                Column("epgURLOverride").set(to: "https://guide.example/xmltv")])
        }

        let saved = try await database.updatePlaylist(id: original.id) { $0.serverTimezone = "UTC" }

        #expect(saved?.serverTimezone == "UTC")
        #expect(saved?.timeshiftStyle == "m3u8")
        #expect(saved?.epgURLOverride == "https://guide.example/xmltv")
    }

    @Test
    func updateOfAMissingPlaylistReturnsNilAndInsertsNothing() async throws {
        let database = AppDatabase.empty()

        let saved = try await database.updatePlaylist(id: UUID()) { $0.filterAdultContent = true }

        #expect(saved == nil)
        let count = try await database.read { db in try Playlist.fetchCount(db) }
        #expect(count == 0)
    }

    @Test
    func updateWithoutAChangeReturnsTheStoredRow() async throws {
        let database = AppDatabase.empty()
        let original = try await insertedPlaylist(in: database)

        let saved = try await database.updatePlaylist(id: original.id) { $0.epgEnabled = true }

        let stored = try await database.read { db in try Playlist.fetchOne(db, key: original.id) }
        #expect(saved == stored)
        #expect(saved?.epgEnabled == true)
    }

    // MARK: Indexes

    @Test
    func channelListIsReadInOrderWithoutASortStep() async throws {
        let database = AppDatabase.empty()
        let plan = try await database.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT * FROM m3uChannel WHERE playlistId = ? ORDER BY sortIndex
                """, arguments: [UUID()])
                .map { $0["detail"] as String }
        }
        #expect(plan.contains { $0.contains("idx_m3uChannel_playlist_sort") })
        #expect(!plan.contains { $0.contains("TEMP B-TREE") })
    }

    @Test
    func watchHistoryLookupUsesItsIndex() async throws {
        let database = AppDatabase.empty()
        let plan = try await database.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT * FROM watchHistory WHERE streamId = ? AND playlistId = ? AND type = ?
                """, arguments: ["5", UUID(), "vod"])
                .map { $0["detail"] as String }
        }
        #expect(plan.contains { $0.contains("idx_watchHistory_playlist_type_stream") })
        #expect(!plan.contains { $0.hasPrefix("SCAN") })
    }

    @Test
    func bothIndexesExistWithTheirColumns() async throws {
        let database = AppDatabase.empty()
        let (channelIndexes, historyIndexes) = try await database.read { db in
            (try db.indexes(on: "m3uChannel"), try db.indexes(on: "watchHistory"))
        }
        #expect(channelIndexes.first { $0.name == "idx_m3uChannel_playlist_sort" }?.columns
                == ["playlistId", "sortIndex"])
        #expect(historyIndexes.first { $0.name == "idx_watchHistory_playlist_type_stream" }?.columns
                == ["playlistId", "type", "streamId"])
    }
}
