import Foundation
import GRDB
import GRDBQuery
import Combine

struct PlaylistRequest: Queryable, Equatable {
    static var defaultValue: [Playlist]? { nil }

    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[Playlist]?, Never> {
        ValueObservation
            .tracking { db in try Playlist.fetchAll(db) }
            .publisher(in: appDatabase.reader)
            .map { $0 as [Playlist]? }
            .catch { _ in Just([] as [Playlist]?) }
            .eraseToAnyPublisher()
    }
}

/// Most-recently-watched items for a playlist, optionally filtered by type
/// ("live" / "vod" / "series"). Used by the "Continue Watching" shelf at
/// the top of each dashboard tab.
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
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}

/// One entry in the series-focused Continue Watching shelf: the series
/// identity plus the most recent episode's progress, so the shelf can show
/// the series poster while still rendering a progress bar.
struct RecentSeriesHistoryEntry: Identifiable, Equatable {
    let series: DBSeries
    let lastWatchedAt: Date
    let recentStreamId: String
    let lastTimeMs: Int
    let durationMs: Int
    var id: String { series.id }
}

/// Deduplicates series watch history by `seriesId`, keeping only the most
/// recent row per series, and joins the matching `DBSeries` for cover/title.
struct RecentSeriesHistoryRequest: Queryable, Equatable {
    static var defaultValue: [RecentSeriesHistoryEntry] { [] }

    let playlistId: UUID
    var limit: Int = 15

    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[RecentSeriesHistoryEntry], Never> {
        ValueObservation
            .tracking { db -> [RecentSeriesHistoryEntry] in
                let histories = try DBWatchHistory
                    .filter(Column("playlistId") == playlistId && Column("type") == "series")
                    .order(Column("lastWatchedAt").desc)
                    .fetchAll(db)

                var seenSeriesIds = Set<String>()
                var uniqueHistories: [DBWatchHistory] = []
                for h in histories {
                    guard let sid = h.seriesId, !seenSeriesIds.contains(sid) else { continue }
                    seenSeriesIds.insert(sid)
                    uniqueHistories.append(h)
                    if uniqueHistories.count >= limit { break }
                }

                let seriesIdInts = uniqueHistories.compactMap { $0.seriesId.flatMap(Int.init) }
                guard !seriesIdInts.isEmpty else { return [] }

                let seriesRows = try DBSeries
                    .filter(Column("playlistId") == playlistId
                            && seriesIdInts.contains(Column("seriesId")))
                    .fetchAll(db)
                let seriesMap = Dictionary(
                    uniqueKeysWithValues: seriesRows.map { (String($0.seriesId), $0) }
                )

                return uniqueHistories.compactMap { h in
                    guard let sid = h.seriesId, let s = seriesMap[sid] else { return nil }
                    return RecentSeriesHistoryEntry(
                        series: s,
                        lastWatchedAt: h.lastWatchedAt,
                        recentStreamId: h.streamId,
                        lastTimeMs: h.lastTimeMs,
                        durationMs: h.durationMs
                    )
                }
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}
