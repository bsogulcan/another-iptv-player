import Foundation
import GRDB
@testable import another_iptv_player

/// Builders shared by the catalog store, importer and panel client tests.
enum PlaylistCatalogFixture {
    static func playlist(filterAdult: Bool = false) -> Playlist {
        Playlist(
            name: "Test", serverURL: "http://panel.invalid", username: "u", password: "p",
            filterAdultContent: filterAdult
        )
    }

    /// An in-memory database that already holds `playlist`: the catalog tables
    /// reference it.
    static func database(with playlist: Playlist) async throws -> AppDatabase {
        let database = AppDatabase.empty()
        try await database.write { db in try playlist.insert(db) }
        return database
    }

    static func category(_ id: String, type: String, sortIndex: Int = 0, in playlist: Playlist) -> DBCategory {
        DBCategory(
            id: id, name: "Category \(id)", parentId: nil, type: type, sortIndex: sortIndex, playlistId: playlist.id
        )
    }

    static func live(_ id: Int, category: String?, in playlist: Playlist) -> DBLiveStream {
        DBLiveStream(
            streamId: id, name: "Channel \(id)", streamIcon: nil, epgChannelId: nil,
            categoryId: category, sortIndex: id, playlistId: playlist.id
        )
    }

    static func vod(_ id: Int, category: String?, added: String? = nil, in playlist: Playlist) -> DBVODStream {
        var row = DBVODStream(
            streamId: id, name: "Movie \(id)", streamIcon: nil, categoryId: category,
            rating: nil, containerExtension: nil, sortIndex: id, playlistId: playlist.id
        )
        row.added = added
        return row
    }

    static func series(_ id: Int, category: String?, lastModified: String? = nil, in playlist: Playlist) -> DBSeries {
        var row = DBSeries(
            seriesId: id, name: "Series \(id)", cover: nil, categoryId: category,
            sortIndex: id, playlistId: playlist.id
        )
        row.lastModified = lastModified
        return row
    }

    /// The panel models only have `init(from:)`, so tests build them from JSON objects.
    static func panelObjects<T: Decodable>(_ objects: [[String: Any]]) throws -> [T] {
        let data = try JSONSerialization.data(withJSONObject: objects)
        return try JSONDecoder().decode([T].self, from: data)
    }

    // MARK: - Row counts and ids, for assertions

    static func ids(_ column: String, in table: String, type: String? = nil, database: AppDatabase) async throws -> [String] {
        try await database.read { db in
            if let type {
                return try String.fetchAll(
                    db, sql: "SELECT CAST(\(column) AS TEXT) FROM \(table) WHERE type = ? ORDER BY sortIndex, \(column)",
                    arguments: [type]
                )
            }
            return try String.fetchAll(db, sql: "SELECT CAST(\(column) AS TEXT) FROM \(table) ORDER BY sortIndex, \(column)")
        }
    }

    static func count(_ table: String, database: AppDatabase) async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }
}

/// A panel client that answers from memory. Every request counts, runs `onRequest`
/// and then either fails with `failure` or returns its part of `payload`.
final class CannedXtreamAPIClient: XtreamAPIClient {
    struct Payload {
        var liveCategories: [XtreamCategory] = []
        var vodCategories: [XtreamCategory] = []
        var seriesCategories: [XtreamCategory] = []
        var liveStreams: [XtreamLiveStream] = []
        var vodStreams: [XtreamVODStream] = []
        var series: [XtreamSeries] = []
    }

    var payload: Payload
    var failure: Error?
    var onRequest: (() -> Void)?
    private(set) var requestCount = 0

    init(playlist: Playlist, payload: Payload = Payload(), failure: Error? = nil) {
        self.payload = payload
        self.failure = failure
        super.init(playlist: playlist)
    }

    private func answer<T>(_ value: T) throws -> T {
        requestCount += 1
        onRequest?()
        if let failure { throw failure }
        return value
    }

    override func getLiveCategories() async throws -> [XtreamCategory] {
        try answer(payload.liveCategories)
    }

    override func getVODCategories() async throws -> [XtreamCategory] {
        try answer(payload.vodCategories)
    }

    override func getSeriesCategories() async throws -> [XtreamCategory] {
        try answer(payload.seriesCategories)
    }

    override func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamLiveStream] {
        try answer(payload.liveStreams)
    }

    override func getVODStreams(categoryId: String? = nil) async throws -> [XtreamVODStream] {
        try answer(payload.vodStreams)
    }

    override func getSeries(categoryId: String? = nil) async throws -> [XtreamSeries] {
        try answer(payload.series)
    }
}

extension CannedXtreamAPIClient.Payload {
    /// Two categories per type, the second one adult by name, plus one stream in
    /// each and one live / movie stream flagged `is_adult` in the clean category.
    static func withAdultContent() throws -> Self {
        var payload = Self()
        payload.liveCategories = try PlaylistCatalogFixture.panelObjects([
            ["category_id": "1", "category_name": "News"],
            ["category_id": "2", "category_name": "XXX Adults"],
        ])
        payload.liveStreams = try PlaylistCatalogFixture.panelObjects([
            ["stream_id": 1, "name": "News One", "category_id": "1"],
            ["stream_id": 2, "name": "Late", "category_id": "2"],
            ["stream_id": 3, "name": "Flagged", "category_id": "1", "is_adult": 1],
        ])
        payload.vodCategories = try PlaylistCatalogFixture.panelObjects([
            ["category_id": "10", "category_name": "Drama"],
            ["category_id": "11", "category_name": "Adult 18+"],
        ])
        payload.vodStreams = try PlaylistCatalogFixture.panelObjects([
            ["stream_id": 100, "name": "Film", "category_id": "10", "added": "1700000000"],
            ["stream_id": 101, "name": "Late film", "category_id": "11"],
            ["stream_id": 102, "name": "Flagged film", "category_id": "10", "is_adult": "1"],
        ])
        payload.seriesCategories = try PlaylistCatalogFixture.panelObjects([
            ["category_id": "20", "category_name": "Shows"],
            ["category_id": "21", "category_name": "Erotic"],
        ])
        payload.series = try PlaylistCatalogFixture.panelObjects([
            ["series_id": 500, "name": "Show", "category_id": "20", "cast": "A, B", "director": "C",
             "releaseDate": "2020-01-01", "youtube_trailer": "abc", "last_modified": "1700000500"],
            ["series_id": 501, "name": "Late show", "category_id": "21"],
        ])
        return payload
    }
}
