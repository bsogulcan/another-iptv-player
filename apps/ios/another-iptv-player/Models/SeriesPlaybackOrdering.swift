import Foundation
import GRDB

/// Dizi bölümlerini playlist veritabanındaki sezon / bölüm sırasına göre dizer; önceki–sonraki bölüm için kullanılır.
enum SeriesPlaybackOrdering {
    struct NavigationContext {
        var previous: DBEpisode?
        var next: DBEpisode?

        static let empty = NavigationContext(previous: nil, next: nil)
    }

    static func orderedEpisodes(seriesId: Int, playlistId: UUID, db: Database) throws -> [DBEpisode] {
        let seasons = try DBSeason
            .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
            .order(Column("seasonNumber").asc)
            .fetchAll(db)
        var out: [DBEpisode] = []
        for s in seasons {
            let eps = try DBEpisode
                .filter(Column("seasonId") == s.id)
                .order(Column("episodeNum").asc)
                .fetchAll(db)
            out.append(contentsOf: eps)
        }
        return out
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
        var seriesIdInt: Int?
        if let ep = try DBEpisode
            .filter(Column("episodeId") == playbackStreamId || Column("id") == playbackStreamId)
            .fetchOne(db),
            let season = try DBSeason
                .filter(Column("id") == ep.seasonId && Column("playlistId") == playlistId)
                .fetchOne(db)
        {
            seriesIdInt = season.seriesId
        }
        if seriesIdInt == nil, let hint = seriesIdHint.flatMap({ Int($0) }) {
            seriesIdInt = hint
        }
        guard let sid = seriesIdInt else { return .empty }
        return try neighbors(playbackStreamId: playbackStreamId, seriesId: sid, playlistId: playlistId, db: db)
    }
}
