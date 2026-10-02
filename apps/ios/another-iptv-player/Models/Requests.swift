import Foundation
import GRDB
import GRDBQuery
import Combine

struct PlaylistRequest: Queryable, Equatable {
    static var defaultValue: [Playlist]? { nil }
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[Playlist]?, Never> {
        print("DATABASE: PlaylistRequest publisher called")
        return ValueObservation
            .tracking { db in
                let playlists = try Playlist.fetchAll(db)
                print("DATABASE: FetchAll(playlist) returns \(playlists.count) items")
                return playlists
            }
            .publisher(in: appDatabase.reader)
            .map { $0 as [Playlist]? }
            .catch { error in
                print("DATABASE: PlaylistRequest error: \(error)")
                return Just([] as [Playlist]?)
            }
            .eraseToAnyPublisher()
    }
}

struct CategoriesRequest: Queryable, Equatable {
    static var defaultValue: [DBCategory] { [] }
    
    let playlistId: UUID
    let type: String
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[DBCategory], Never> {
        ValueObservation
            .tracking { db in
                try DBCategory
                    .filter(Column("playlistId") == playlistId && Column("type") == type)
                    .order(Column("sortIndex"))
                    .fetchAll(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct LiveStreamsRequest: Queryable, Equatable {
    static var defaultValue: [LiveStreamWithCategory] { [] }
    
    let playlistId: UUID
    let categoryId: String?
    let searchText: String?
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[LiveStreamWithCategory], Never> {
        ValueObservation
            .tracking { db in
                var sql = """
                SELECT liveStream.*, COALESCE(category.name, ?) AS categoryName
                FROM liveStream
                LEFT JOIN category ON liveStream.categoryId = category.id
                             AND liveStream.playlistId = category.playlistId
                             AND category.type = 'live'
                WHERE liveStream.playlistId = ?
                """
                var arguments: [DatabaseValueConvertible] = [L("content.uncategorized"), playlistId]
                
                if let catId = categoryId {
                    sql += " AND liveStream.categoryId = ?"
                    arguments.append(catId)
                }
                
                if let search = searchText, !search.isEmpty {
                    sql += " AND localized_contains(liveStream.name, ?)"
                    arguments.append(search)
                    
                    sql += """
                     ORDER BY 
                        localized_equals(liveStream.name, ?) DESC,
                        localized_starts_with(liveStream.name, ?) DESC,
                        liveStream.name COLLATE NOCASE ASC
                    """
                    arguments.append(contentsOf: [search, search])
                } else {
                    sql += " ORDER BY liveStream.sortIndex"
                }
                
                return try LiveStreamWithCategory.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct VODStreamsRequest: Queryable, Equatable {
    static var defaultValue: [VODWithCategory] { [] }
    
    let playlistId: UUID
    let categoryId: String?
    let searchText: String?
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[VODWithCategory], Never> {
        ValueObservation
            .tracking { db in
                var sql = """
                SELECT vodStream.*, COALESCE(category.name, ?) AS categoryName
                FROM vodStream
                LEFT JOIN category ON vodStream.categoryId = category.id
                             AND vodStream.playlistId = category.playlistId
                             AND category.type = 'vod'
                WHERE vodStream.playlistId = ?
                """
                var arguments: [DatabaseValueConvertible] = [L("content.uncategorized"), playlistId]
                
                if let catId = categoryId {
                    sql += " AND vodStream.categoryId = ?"
                    arguments.append(catId)
                }
                
                if let search = searchText, !search.isEmpty {
                    sql += " AND localized_contains(vodStream.name, ?)"
                    arguments.append(search)
                    
                    sql += """
                     ORDER BY 
                        localized_equals(vodStream.name, ?) DESC,
                        localized_starts_with(vodStream.name, ?) DESC,
                        vodStream.name COLLATE NOCASE ASC
                    """
                    arguments.append(contentsOf: [search, search])
                } else {
                    sql += " ORDER BY vodStream.sortIndex"
                }
                
                return try VODWithCategory.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct SeriesRequest: Queryable, Equatable {
    static var defaultValue: [SeriesWithCategory] { [] }
    
    let playlistId: UUID
    let categoryId: String?
    let searchText: String?
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[SeriesWithCategory], Never> {
        ValueObservation
            .tracking { db in
                var sql = """
                SELECT series.*, COALESCE(category.name, ?) AS categoryName
                FROM series
                LEFT JOIN category ON series.categoryId = category.id
                             AND series.playlistId = category.playlistId
                             AND category.type = 'series'
                WHERE series.playlistId = ?
                """
                var arguments: [DatabaseValueConvertible] = [L("content.uncategorized"), playlistId]
                
                if let catId = categoryId {
                    sql += " AND series.categoryId = ?"
                    arguments.append(catId)
                }
                
                if let search = searchText, !search.isEmpty {
                    sql += " AND localized_contains(series.name, ?)"
                    arguments.append(search)
                    
                    sql += """
                     ORDER BY 
                        localized_equals(series.name, ?) DESC,
                        localized_starts_with(series.name, ?) DESC,
                        series.name COLLATE NOCASE ASC
                    """
                    arguments.append(contentsOf: [search, search])
                } else {
                    sql += " ORDER BY series.sortIndex"
                }
                
                return try SeriesWithCategory.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct SeriesByIDRequest: Queryable, Equatable {
    static var defaultValue: DBSeries? { nil }
    
    let seriesId: Int
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<DBSeries?, Never> {
        ValueObservation
            .tracking { db in
                try DBSeries
                    .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
                    .fetchOne(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just(nil) }
            .eraseToAnyPublisher()
    }
}

struct SeasonsRequest: Queryable, Equatable {
    static var defaultValue: [DBSeason] { [] }
    
    let seriesId: Int
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[DBSeason], Never> {
        ValueObservation
            .tracking { db in
                try DBSeason
                    .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
                    .order(Column("seasonNumber"))
                    .fetchAll(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct EpisodesRequest: Queryable, Equatable {
    static var defaultValue: [DBEpisode] { [] }
    
    let seasonId: String
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[DBEpisode], Never> {
        ValueObservation
            .tracking { db in
                try DBEpisode
                    .filter(Column("seasonId") == seasonId)
                    .order(Column("episodeNum"))
                    .fetchAll(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}
struct VODByIDRequest: Queryable, Equatable {
    static var defaultValue: DBVODStream? { nil }
    
    let streamId: Int
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<DBVODStream?, Never> {
        ValueObservation
            .tracking { db in
                try DBVODStream
                    .filter(Column("streamId") == streamId && Column("playlistId") == playlistId)
                    .fetchOne(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just(nil) }
            .eraseToAnyPublisher()
    }
}

// MARK: - Favorites

struct IsFavoriteRequest: Queryable, Equatable {
    static var defaultValue: Bool { false }
    
    let streamId: Int
    let playlistId: UUID
    let type: String
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<Bool, Never> {
        ValueObservation
            .tracking { db in
                let count = try DBFavorite
                    .filter(Column("streamId") == streamId)
                    .filter(Column("playlistId") == playlistId)
                    .filter(Column("type") == type)
                    .fetchCount(db)
                return count > 0
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just(false) }
            .eraseToAnyPublisher()
    }
}

struct FavoriteVODRequest: Queryable, Equatable {
    static var defaultValue: [VODWithCategory] { [] }
    
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[VODWithCategory], Never> {
        ValueObservation
            .tracking { db in
                let sql = """
                SELECT vodStream.*, COALESCE(category.name, ?) AS categoryName
                FROM favorite
                JOIN vodStream ON favorite.streamId = vodStream.streamId
                               AND favorite.playlistId = vodStream.playlistId
                LEFT JOIN category ON vodStream.categoryId = category.id
                             AND vodStream.playlistId = category.playlistId
                             AND category.type = 'vod'
                WHERE favorite.playlistId = ? AND favorite.type = 'vod'
                ORDER BY favorite.createdAt DESC
                """
                return try VODWithCategory.fetchAll(db, sql: sql, arguments: [L("content.uncategorized"), playlistId])
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct FavoriteSeriesRequest: Queryable, Equatable {
    static var defaultValue: [SeriesWithCategory] { [] }
    
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[SeriesWithCategory], Never> {
        ValueObservation
            .tracking { db in
                let sql = """
                SELECT series.*, COALESCE(category.name, ?) AS categoryName
                FROM favorite
                JOIN series ON favorite.streamId = series.seriesId
                           AND favorite.playlistId = series.playlistId
                LEFT JOIN category ON series.categoryId = category.id
                             AND series.playlistId = category.playlistId
                             AND category.type = 'series'
                WHERE favorite.playlistId = ? AND favorite.type = 'series'
                ORDER BY favorite.createdAt DESC
                """
                return try SeriesWithCategory.fetchAll(db, sql: sql, arguments: [L("content.uncategorized"), playlistId])
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

struct FavoriteLiveRequest: Queryable, Equatable {
    static var defaultValue: [LiveStreamWithCategory] { [] }
    
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[LiveStreamWithCategory], Never> {
        ValueObservation
            .tracking { db in
                let sql = """
                SELECT liveStream.*, COALESCE(category.name, ?) AS categoryName
                FROM favorite
                JOIN liveStream ON favorite.streamId = liveStream.streamId
                               AND favorite.playlistId = liveStream.playlistId
                LEFT JOIN category ON liveStream.categoryId = category.id
                             AND liveStream.playlistId = category.playlistId
                             AND category.type = 'live'
                WHERE favorite.playlistId = ? AND favorite.type = 'live'
                ORDER BY favorite.createdAt DESC
                """
                return try LiveStreamWithCategory.fetchAll(db, sql: sql, arguments: [L("content.uncategorized"), playlistId])
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

// MARK: - Watch History

struct WatchHistoryRequest: Queryable, Equatable {
    static var defaultValue: DBWatchHistory? { nil }
    
    let streamId: String
    let playlistId: UUID
    let type: String
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<DBWatchHistory?, Never> {
        ValueObservation
            .tracking { db in
                try DBWatchHistory
                    .filter(Column("streamId") == streamId && Column("playlistId") == playlistId && Column("type") == type)
                    .fetchOne(db)
            }
            .publisher(in: appDatabase.reader)
            // The player saves a history row every few seconds and the observation
            // re-fetches on every write to the table. Without this, each mounted
            // episode row and detail screen re-renders for a row that is not theirs.
            .removeDuplicates()
            .catch { _ in Just(nil) }
            .eraseToAnyPublisher()
    }
}

struct RecentWatchHistoryRequest: Queryable, Equatable {
    static var defaultValue: [DBWatchHistory] { [] }
    
    let playlistId: UUID
    var limit: Int = 20
    var type: String? = nil
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[DBWatchHistory], Never> {
        ValueObservation
            .tracking { db in
                var request = DBWatchHistory.filter(Column("playlistId") == playlistId)
                
                if let type = type {
                    request = request.filter(Column("type") == type)
                }
                
                return try request
                    .order(Column("lastWatchedAt").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
            .publisher(in: appDatabase.reader)
            // A type-filtered list (the Movies or Series shelf) does not change while
            // something of another type plays; do not re-render it on those writes.
            // The playing item's own list still differs in its first row, so the
            // comparison stops there.
            .removeDuplicates()
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

/// Bir playlist'teki tüm izleme ilerlemelerini tek sorguda döner.
/// Kart başına ayrı @Query açmak yerine bu kullanılır: streamId → ilerleme (0…1)
///
/// For `type == "series"` the key is the series id, not the episode id: the series
/// cards look the map up by `seriesId`, and a history row of that type is an
/// episode. The value is the progress of the most recently watched episode, the
/// same row `LatestSeriesWatchHistoryRequest` resumes from.
struct WatchProgressMapRequest: Queryable, Equatable {
    static var defaultValue: [String: Double] { [:] }
    let playlistId: UUID
    let type: String

    /// Progress as the poster cards draw it: clamped to 0…1 and rounded to 0.01,
    /// about one point of a card's bar. The player saves the position every few
    /// seconds; comparing the exact fraction made the map differ on every save and
    /// re-rendered each grid that observes it. Rounded, a film changes it about
    /// once a minute.
    ///
    /// Anything above zero is kept at 0.01 or more, because the cards draw the bar
    /// only for `progress > 0` and a title that was just started must keep its
    /// sliver. Returns nil when the duration is unknown.
    nonisolated static func displayFraction(lastTimeMs: Int, durationMs: Int) -> Double? {
        guard durationMs > 0 else { return nil }
        let raw = min(max(Double(lastTimeMs) / Double(durationMs), 0), 1)
        guard raw > 0 else { return 0 }
        return max((raw * 100).rounded() / 100, 0.01)
    }

    /// Builds the map from history rows of one playlist and `type`.
    nonisolated static func progressMap(from rows: [DBWatchHistory], type: String) -> [String: Double] {
        guard type == "series" else {
            var map: [String: Double] = [:]
            for row in rows {
                guard let fraction = displayFraction(lastTimeMs: row.lastTimeMs, durationMs: row.durationMs) else { continue }
                map[row.streamId] = fraction
            }
            return map
        }
        // Several episodes share a series id: the one watched last wins, whatever
        // order the rows arrive in. A row without a series id belongs to no card.
        var map: [String: Double] = [:]
        var newest: [String: Date] = [:]
        for row in rows {
            guard let key = row.seriesId, !key.isEmpty,
                  let fraction = displayFraction(lastTimeMs: row.lastTimeMs, durationMs: row.durationMs)
            else { continue }
            if let seen = newest[key], seen >= row.lastWatchedAt { continue }
            newest[key] = row.lastWatchedAt
            map[key] = fraction
        }
        return map
    }

    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[String: Double], Never> {
        ValueObservation
            .tracking { db in
                let rows = try DBWatchHistory
                    .filter(Column("playlistId") == playlistId
                            && Column("type") == type
                            && Column("durationMs") > 0)
                    .fetchAll(db)
                return Self.progressMap(from: rows, type: type)
            }
            .publisher(in: appDatabase.reader)
            .removeDuplicates()
            .catch { _ in Just([:]) }
            .eraseToAnyPublisher()
    }
}

struct LatestSeriesWatchHistoryRequest: Queryable, Equatable {
    static var defaultValue: DBWatchHistory? { nil }
    
    let seriesId: String
    let playlistId: UUID
    
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<DBWatchHistory?, Never> {
        ValueObservation
            .tracking { db in
                try DBWatchHistory
                    .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
                    .order(Column("lastWatchedAt").desc)
                    .fetchOne(db)
            }
            .publisher(in: appDatabase.reader)
            // Same reason as WatchHistoryRequest: a series detail screen should not
            // re-render while an episode of another series (or a film) is playing.
            .removeDuplicates()
            .catch { _ in Just(nil) }
            .eraseToAnyPublisher()
    }
}
