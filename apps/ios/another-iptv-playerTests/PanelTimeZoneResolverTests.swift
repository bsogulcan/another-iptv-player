import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The resolver asks the panel for its time zone and stores the answer in the
/// playlist row. It is handed a `Playlist` value that can be older than the row.
@Suite("Panel time zone resolver")
struct PanelTimeZoneResolverTests {

    private func makePlaylist(servingTimezone timezone: String) -> Playlist {
        let host = "panel-\(UUID().uuidString.lowercased()).invalid"
        let body = """
        {"user_info": {"auth": 1, "username": "user", "status": "Active"},
         "server_info": {"timezone": "\(timezone)", "time_now": "2026-07-22 14:30:00", "timestamp_now": 1784719800}}
        """
        XtreamStubURLProtocol.setAnswer(.init(status: 200, body: Data(body.utf8)), forHost: host)
        return Playlist(name: "Panel", serverURL: "http://\(host)", username: "user", password: "pass")
    }

    @Test
    func thePanelsTimeZoneIsStoredWithoutTouchingOtherColumns() async throws {
        let database = AppDatabase.empty()
        let staleCopy = makePlaylist(servingTimezone: "Europe/Istanbul")
        try await database.write { db in try staleCopy.insert(db) }
        // Saved by settings after the copy was taken.
        try await database.updatePlaylist(id: staleCopy.id) {
            $0.filterAdultContent = true
            $0.epgEnabled = false
        }

        let zone = await PanelTimeZoneResolver.resolve(playlist: staleCopy, database: database,
                                                       urlSession: XtreamStubURLProtocol.makeSession())

        #expect(zone.identifier == "Europe/Istanbul")
        let stored = try #require(try await database.read { db in try Playlist.fetchOne(db, key: staleCopy.id) })
        #expect(stored.serverTimezone == "Europe/Istanbul")
        #expect(stored.filterAdultContent)
        #expect(!stored.epgEnabled)
    }

    /// The playlist was deleted while the panel was being asked. The answer is
    /// still returned, and the row is not created again.
    @Test
    func aDeletedPlaylistIsNotInsertedAgain() async throws {
        let database = AppDatabase.empty()
        let playlist = makePlaylist(servingTimezone: "Europe/Berlin")

        let zone = await PanelTimeZoneResolver.resolve(playlist: playlist, database: database,
                                                       urlSession: XtreamStubURLProtocol.makeSession())

        #expect(zone.identifier == "Europe/Berlin")
        let count = try await database.read { db in try Playlist.fetchCount(db) }
        #expect(count == 0)
    }

    @Test
    func aStoredTimeZoneNeedsNoRequest() async {
        // Nothing is served for this playlist; a request would fail and yield GMT.
        let playlist = Playlist(name: "Panel", serverURL: "http://unanswered.invalid", username: "u", password: "p",
                                serverTimezone: "Asia/Tokyo")

        let zone = await PanelTimeZoneResolver.resolve(playlist: playlist, database: AppDatabase.empty(),
                                                       urlSession: XtreamStubURLProtocol.makeSession())

        #expect(zone.identifier == "Asia/Tokyo")
    }
}
