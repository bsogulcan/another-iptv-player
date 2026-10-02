import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// `FavoriteWriter` and `WatchHistoryWriter`: statements that say which row they
/// want, so repeating one changes nothing.
@Suite("Favorite writer")
struct FavoriteWriterTests {

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

    private func rows(in database: AppDatabase) async throws -> [DBFavorite] {
        try await database.read { db in
            try DBFavorite.order(Column("streamId"), Column("type")).fetchAll(db)
        }
    }

    private func ids(of playlist: Playlist, in database: AppDatabase) async throws -> XtreamFavoriteIDs {
        let playlistId = playlist.id
        return try await database.read { db in
            try FavoriteWriter.ids(playlistId: playlistId, db: db)
        }
    }

    // MARK: set

    @Test
    func addingWritesARowTheExistingReadersUnderstand() async throws {
        let database = try database()

        try await FavoriteWriter.set(true, streamId: 7, type: "vod", playlistId: playlist.id, in: database)

        // Decoded through the record type the detail screens and requests use: the
        // playlist id and the date have to be stored the way that type stores them.
        let stored = try await rows(in: database)
        #expect(stored.count == 1)
        #expect(stored.first?.streamId == 7)
        #expect(stored.first?.type == "vod")
        #expect(stored.first?.playlistId == playlist.id)
        let age = Date().timeIntervalSince(try #require(stored.first?.createdAt))
        #expect(age >= -1 && age < 60)
    }

    /// The double tap: the second insert must neither fail on the primary key nor
    /// replace the row.
    @Test
    func addingTwiceKeepsTheFirstRow() async throws {
        let database = try database()
        let firstDate = Date(timeIntervalSince1970: 1_000)
        try database.writeSync { db in
            try DBFavorite(streamId: 7, playlistId: playlist.id, type: "vod", createdAt: firstDate).insert(db)
        }

        try await FavoriteWriter.set(true, streamId: 7, type: "vod", playlistId: playlist.id, in: database)
        try await FavoriteWriter.set(true, streamId: 7, type: "vod", playlistId: playlist.id, in: database)

        let stored = try await rows(in: database)
        #expect(stored.count == 1)
        #expect(stored.first?.createdAt == firstDate)
    }

    @Test
    func removingDeletesTheRowAnExistingWriterInserted() async throws {
        let database = try database()
        try database.writeSync { db in
            try DBFavorite(streamId: 7, playlistId: playlist.id, type: "vod").insert(db)
        }

        try await FavoriteWriter.set(false, streamId: 7, type: "vod", playlistId: playlist.id, in: database)

        #expect(try await rows(in: database).isEmpty)
    }

    @Test
    func removingAMissingRowIsNotAnError() async throws {
        let database = try database()

        try await FavoriteWriter.set(false, streamId: 7, type: "vod", playlistId: playlist.id, in: database)
        try await FavoriteWriter.set(false, streamId: 7, type: "vod", playlistId: playlist.id, in: database)

        #expect(try await rows(in: database).isEmpty)
    }

    /// Stream ids repeat between content types and between panels.
    @Test
    func aRowIsKeyedByStreamTypeAndPlaylist() async throws {
        let database = try database()
        try await FavoriteWriter.set(true, streamId: 7, type: "vod", playlistId: playlist.id, in: database)
        try await FavoriteWriter.set(true, streamId: 7, type: "series", playlistId: playlist.id, in: database)
        try await FavoriteWriter.set(true, streamId: 7, type: "vod", playlistId: otherPlaylist.id, in: database)

        try await FavoriteWriter.set(false, streamId: 7, type: "vod", playlistId: playlist.id, in: database)

        let mine = try await ids(of: playlist, in: database)
        let theirs = try await ids(of: otherPlaylist, in: database)
        #expect(mine == XtreamFavoriteIDs(series: [7]))
        #expect(theirs == XtreamFavoriteIDs(vod: [7]))
    }

    @Test
    func aFavouriteOfAPlaylistThatDoesNotExistIsRefused() async throws {
        let database = try database()

        await #expect(throws: (any Error).self) {
            try await FavoriteWriter.set(true, streamId: 7, type: "vod", playlistId: UUID(), in: database)
        }
        #expect(try await rows(in: database).isEmpty)
    }

    // MARK: toggle

    @Test
    func toggleFlipsTheStoredStateAndReportsIt() async throws {
        let database = try database()

        let first = try await FavoriteWriter.toggle(streamId: 3, type: "live", playlistId: playlist.id, in: database)
        #expect(first == true)
        #expect(try await ids(of: playlist, in: database) == XtreamFavoriteIDs(live: [3]))

        let second = try await FavoriteWriter.toggle(streamId: 3, type: "live", playlistId: playlist.id, in: database)
        #expect(second == false)
        #expect(try await ids(of: playlist, in: database) == XtreamFavoriteIDs())
    }

    // MARK: ids

    @Test
    func idsAreGroupedByType() async throws {
        let database = try database()
        try database.writeSync { db in
            try DBFavorite(streamId: 1, playlistId: playlist.id, type: "live").insert(db)
            try DBFavorite(streamId: 2, playlistId: playlist.id, type: "live").insert(db)
            try DBFavorite(streamId: 2, playlistId: playlist.id, type: "vod").insert(db)
            try DBFavorite(streamId: 9, playlistId: playlist.id, type: "series").insert(db)
            try DBFavorite(streamId: 5, playlistId: otherPlaylist.id, type: "vod").insert(db)
        }

        let stored = try await ids(of: playlist, in: database)

        #expect(stored == XtreamFavoriteIDs(live: [1, 2], vod: [2], series: [9]))
        #expect(stored.contains(2, type: "live"))
        #expect(stored.contains(2, type: "vod"))
        #expect(!stored.contains(2, type: "series"))
        #expect(!stored.contains(2, type: "episode"))
    }

    @Test
    func anUnknownTypeIsNeverAFavourite() {
        var ids = XtreamFavoriteIDs()
        ids.set(true, streamId: 1, type: "episode")
        #expect(ids == XtreamFavoriteIDs())

        ids.set(true, streamId: 1, type: "live")
        ids.set(false, streamId: 1, type: "vod")
        #expect(ids == XtreamFavoriteIDs(live: [1]))
    }

    // MARK: Watch history

    private func history(_ streamId: String) -> DBWatchHistory {
        DBWatchHistory(
            id: "\(playlist.id)_vod_\(streamId)", playlistId: playlist.id, streamId: streamId, type: "vod",
            lastTimeMs: 60_000, durationMs: 600_000, lastWatchedAt: Date(timeIntervalSince1970: 1_000_000),
            seriesId: nil, title: "Film \(streamId)", secondaryTitle: nil, imageURL: nil, containerExtension: nil
        )
    }

    @Test
    func removingAHistoryRowLeavesTheOthers() async throws {
        let database = try database()
        let first = history("1")
        let second = history("2")
        try database.writeSync { db in
            try first.insert(db)
            try second.insert(db)
        }

        try await WatchHistoryWriter.remove(id: first.id, in: database)
        // Already gone: the second tap of a double tap.
        try await WatchHistoryWriter.remove(id: first.id, in: database)

        let left = try await database.read { db in try DBWatchHistory.fetchAll(db) }
        #expect(left.map(\.id) == [second.id])
    }
}
