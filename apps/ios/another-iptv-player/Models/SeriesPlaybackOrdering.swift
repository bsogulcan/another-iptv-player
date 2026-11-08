import Foundation
import GRDB

/// Dizi bölümlerini playlist veritabanındaki sezon / bölüm sırasına göre dizer; önceki–sonraki bölüm için kullanılır.
enum SeriesPlaybackOrdering {
    struct NavigationContext {
        var previous: DBEpisode?
        var next: DBEpisode?

        static let empty = NavigationContext(previous: nil, next: nil)
    }

    static func orderedEpisodes(seriesId: Int, playlistId: UUID, seasonId: String? = nil,
                                firstOnly: Bool = false, db: Database) throws -> [DBEpisode] {
        var arguments: StatementArguments = [seriesId, playlistId]
        if let seasonId { arguments += [seasonId] }
        return try DBEpisode.fetchAll(db, sql: """
            SELECT * FROM (
                SELECT e.*, s.seasonNumber,
                       ROW_NUMBER() OVER (
                           PARTITION BY COALESCE(e.episodeId, e.id)
                           ORDER BY (e.episodeId IS NULL), s.seasonNumber, s.id, e.episodeNum, e.id
                       ) AS occurrence
                FROM episode e JOIN season s ON s.id = e.seasonId
                WHERE s.seriesId = ? AND s.playlistId = ?
            )
            WHERE occurrence = 1 \(seasonId == nil ? "" : "AND seasonId = ?")
            ORDER BY seasonNumber, seasonId, episodeNum, id
            \(firstOnly ? "LIMIT 1" : "")
            """, arguments: arguments)
    }

    static func index(playbackStreamId: String, in episodes: [DBEpisode]) -> Int? {
        episodes.firstIndex { ep in
            (ep.episodeId ?? ep.id) == playbackStreamId || ep.id == playbackStreamId
        }
    }

    static func neighbors(playbackStreamId: String, seriesId: Int, playlistId: UUID, db: Database) throws -> NavigationContext {
        let all = try orderedEpisodes(seriesId: seriesId, playlistId: playlistId, db: db)
        guard let i = index(playbackStreamId: playbackStreamId, in: all) else { return .empty }
        let prev = i > 0 ? all[i - 1] : nil
        let next = i < all.count - 1 ? all[i + 1] : nil
        return NavigationContext(previous: prev, next: next)
    }

    /// `seriesIdHint`: watch history veya UI’den gelen dizi kimliği (bölüm satırı bulunamazsa kullanılır).
    static func navigationContext(
        playlistId: UUID,
        playbackStreamId: String,
        seriesIdHint: String?,
        db: Database
    ) throws -> NavigationContext {
        let storedSeries = try Int.fetchOne(db, sql: """
            SELECT s.seriesId FROM episode e JOIN season s ON s.id = e.seasonId
            WHERE s.playlistId = ? AND (e.episodeId = ? OR e.id = ?)
            ORDER BY (e.episodeId IS NULL), s.seasonNumber, s.id, e.episodeNum, e.id
            LIMIT 1
            """, arguments: [playlistId, playbackStreamId, playbackStreamId])
        guard let sid = storedSeries ?? seriesIdHint.flatMap(Int.init) else { return .empty }
        return try neighbors(playbackStreamId: playbackStreamId, seriesId: sid, playlistId: playlistId, db: db)
    }
}
