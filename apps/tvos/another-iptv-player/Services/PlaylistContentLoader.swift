import Foundation
import GRDB

/// Reads a playlist's catalog out of the local database.
///
/// All methods here run inside a GRDB read transaction and return plain
/// value types — safe to call from any actor.
enum PlaylistContentLoader {
    struct CategoriesBundle: Equatable {
        let live: [DBCategory]
        let vod: [DBCategory]
        let series: [DBCategory]
    }

    struct LiveStreamsData: Equatable {
        let streams: [LiveStreamWithCategory]
        let byCategory: [String: [LiveStreamWithCategory]]
    }

    struct VODStreamsData: Equatable {
        let streams: [VODWithCategory]
        let byCategory: [String: [VODWithCategory]]
    }

    struct SeriesData: Equatable {
        let items: [SeriesWithCategory]
        let byCategory: [String: [SeriesWithCategory]]
    }

    static func hasAnyCategory(playlistId: UUID) async throws -> Bool {
        try await AppDatabase.shared.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM category WHERE playlistId = ?",
                arguments: [playlistId]
            ) ?? 0
            return count > 0
        }
    }

    static func fetchCategories(playlistId: UUID) async throws -> CategoriesBundle {
        try await AppDatabase.shared.read { db in
            try fetchCategories(playlistId: playlistId, db: db)
        }
    }

    static func fetchLiveStreams(playlistId: UUID) async throws -> LiveStreamsData {
        try await AppDatabase.shared.read { db in
            try fetchLiveStreams(playlistId: playlistId, db: db)
        }
    }

    static func fetchVODStreams(playlistId: UUID) async throws -> VODStreamsData {
        try await AppDatabase.shared.read { db in
            try fetchVODStreams(playlistId: playlistId, db: db)
        }
    }

    static func fetchSeries(playlistId: UUID) async throws -> SeriesData {
        try await AppDatabase.shared.read { db in
            try fetchSeries(playlistId: playlistId, db: db)
        }
    }

    // MARK: - Raw fetch (inside an existing read txn)

    static func fetchCategories(playlistId: UUID, db: Database) throws -> CategoriesBundle {
        let live = try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == "live")
            .order(Column("sortIndex"))
            .fetchAll(db)
        let vod = try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == "vod")
            .order(Column("sortIndex"))
            .fetchAll(db)
        let series = try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == "series")
            .order(Column("sortIndex"))
            .fetchAll(db)
        return CategoriesBundle(live: live, vod: vod, series: series)
    }

    static func fetchLiveStreams(playlistId: UUID, db: Database) throws -> LiveStreamsData {
        let sql = """
        SELECT liveStream.*, category.name AS categoryName
        FROM liveStream
        JOIN category ON liveStream.categoryId = category.id
                     AND liveStream.playlistId = category.playlistId
                     AND category.type = 'live'
        WHERE liveStream.playlistId = ?
        ORDER BY liveStream.sortIndex
        """
        let streams = try LiveStreamWithCategory.fetchAll(db, sql: sql, arguments: [playlistId])
        return LiveStreamsData(
            streams: streams,
            byCategory: Dictionary(grouping: streams) { $0.stream.categoryId ?? "" }
        )
    }

    static func fetchVODStreams(playlistId: UUID, db: Database) throws -> VODStreamsData {
        let sql = """
        SELECT vodStream.*, category.name AS categoryName
        FROM vodStream
        JOIN category ON vodStream.categoryId = category.id
                     AND vodStream.playlistId = category.playlistId
                     AND category.type = 'vod'
        WHERE vodStream.playlistId = ?
        ORDER BY vodStream.sortIndex
        """
        let streams = try VODWithCategory.fetchAll(db, sql: sql, arguments: [playlistId])
        return VODStreamsData(
            streams: streams,
            byCategory: Dictionary(grouping: streams) { $0.stream.categoryId ?? "" }
        )
    }

    static func fetchSeries(playlistId: UUID, db: Database) throws -> SeriesData {
        let sql = """
        SELECT series.*, category.name AS categoryName
        FROM series
        JOIN category ON series.categoryId = category.id
                     AND series.playlistId = category.playlistId
                     AND category.type = 'series'
        WHERE series.playlistId = ?
        ORDER BY series.sortIndex
        """
        let items = try SeriesWithCategory.fetchAll(db, sql: sql, arguments: [playlistId])
        return SeriesData(
            items: items,
            byCategory: Dictionary(grouping: items) { $0.series.categoryId ?? "" }
        )
    }
}
