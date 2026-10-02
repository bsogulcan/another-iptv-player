import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The status text of an Xtream import as the add forms show it: it names a list
/// that is still downloading, and the form learns when the import starts to write.
@MainActor
@Suite("Xtream import progress")
struct XtreamImportProgressTests {

    // MARK: - Which list is named

    @Test
    func theTextNamesTheFirstListStillOutstanding() {
        var progress = XtreamDownloadProgress()
        #expect(progress.message == L("add_playlist.fetching_live"))

        progress.finish(.live)
        #expect(progress.message == L("add_playlist.fetching_movies"))

        progress.finish(.movies)
        #expect(progress.message == L("add_playlist.fetching_series"))

        progress.finish(.series)
        #expect(progress.message == L("add_playlist.fetching_categories"))
    }

    /// Lists arrive in any order. The text never names one that is already in.
    @Test
    func aListThatArrivedEarlyIsNeverNamed() {
        var progress = XtreamDownloadProgress()
        progress.finish(.movies)
        #expect(progress.message == L("add_playlist.fetching_live"))

        progress.finish(.live)
        #expect(progress.message == L("add_playlist.fetching_series"))

        // Finishing twice changes nothing.
        progress.finish(.live)
        #expect(progress.outstanding == [.series])
    }

    // MARK: - Through the client

    /// A client whose panel answers every list request with an empty list.
    private func makeClient(for playlist: Playlist) -> ProgressReportingXtreamClient {
        let host = URLComponents(string: playlist.serverURL)?.host ?? ""
        XtreamStubURLProtocol.setAnswer(.init(status: 200, body: Data("[]".utf8)), forHost: host)
        return ProgressReportingXtreamClient(playlist: playlist, urlSession: XtreamStubURLProtocol.makeSession())
    }

    private func makePlaylist() -> Playlist {
        Playlist(
            name: "Test", serverURL: "https://panel-\(UUID().uuidString.lowercased()).invalid",
            username: "user", password: "pass"
        )
    }

    @Test
    func anImportReportsTheListsAndThenTheWrite() async throws {
        let database = AppDatabase.empty()
        let playlist = makePlaylist()
        let client = makeClient(for: playlist)
        var statuses: [String] = []
        var committedAfter: Int?

        try await client.importCatalog(
            of: playlist,
            database: database,
            status: { statuses.append($0) },
            onCommitting: { committedAfter = statuses.count }
        )

        // The first text is up before any list has arrived, the last one is the write.
        #expect(statuses.first == L("add_playlist.fetching_live"))
        #expect(statuses.last == L("add_playlist.saving_db"))
        // One text when the download starts, one per list that arrives, one for the write.
        #expect(statuses.count == 5)
        #expect(statuses[3] == L("add_playlist.fetching_categories"))
        // Everything before the write is a download text; the form is told about
        // the write before its text is shown.
        #expect(committedAfter == 4)
        #expect(!statuses.dropLast().contains(L("add_playlist.saving_db")))

        let playlistId = playlist.id
        let saved = try await database.read { db in try Playlist.fetchOne(db, key: playlistId) }
        #expect(saved?.name == "Test")
    }

    @Test
    func aFailedDownloadReportsNoWrite() async throws {
        let database = AppDatabase.empty()
        let playlist = makePlaylist()
        // No answer registered for this host: every request fails to connect.
        let client = ProgressReportingXtreamClient(playlist: playlist, urlSession: XtreamStubURLProtocol.makeSession())
        var statuses: [String] = []
        var committed = false

        await #expect(throws: XtreamError.self) {
            try await client.importCatalog(
                of: playlist,
                database: database,
                status: { statuses.append($0) },
                onCommitting: { committed = true }
            )
        }

        #expect(statuses == [L("add_playlist.fetching_live")])
        #expect(!committed)
        let count = try await database.read { db in try Playlist.fetchCount(db) }
        #expect(count == 0)
    }
}
