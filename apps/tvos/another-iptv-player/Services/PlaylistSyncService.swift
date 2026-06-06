import Foundation
import GRDB

/// Single source of truth for "refresh a playlist's catalog from its Xtream server".
///
/// Used by both the Add/Edit playlist flow (first-time bootstrap) and the
/// Settings > Refresh action (re-sync). Wipes local catalog rows for the given
/// playlist, then reinserts what the server returns, optionally filtering
/// adult content.
enum PlaylistSyncService {
    enum Phase {
        case clearing
        case fetchCategories
        case fetchLive
        case fetchMovies
        case fetchSeries
        case saving

        var localizedMessage: String {
            switch self {
            case .clearing:        return L("phase.clearing_content")
            case .fetchCategories: return L("phase.fetch_categories")
            case .fetchLive:       return L("phase.fetch_live")
            case .fetchMovies:     return L("phase.fetch_movies")
            case .fetchSeries:     return L("phase.fetch_series")
            case .saving:          return L("phase.save_db")
            }
        }
    }

    /// Replaces the local catalog for `playlist` with what the Xtream server
    /// currently returns. Progress callback fires on phase transitions.
    ///
    /// - Parameter persistPlaylistRow: when `true`, the playlist row itself is
    ///   saved inside the same write transaction — needed for the Add/Edit
    ///   flow where the playlist is brand new. Refresh callers pass `false`.
    static func syncReplacingLocal(
        playlist: Playlist,
        persistPlaylistRow: Bool = false,
        progress: @escaping (Phase) -> Void
    ) async throws {
        let client = XtreamAPIClient(playlist: playlist)
        let pid = playlist.id

        progress(.clearing)
        try await AppDatabase.shared.write { db in
            try db.execute(sql: "DELETE FROM category WHERE playlistId = ?", arguments: [pid])
            try db.execute(sql: "DELETE FROM liveStream WHERE playlistId = ?", arguments: [pid])
            try db.execute(sql: "DELETE FROM vodStream WHERE playlistId = ?", arguments: [pid])
            try db.execute(sql: "DELETE FROM series WHERE playlistId = ?", arguments: [pid])
        }

        progress(.fetchCategories)
        let liveCats   = try await client.getLiveCategories()
        let vodCats    = try await client.getVODCategories()
        let seriesCats = try await client.getSeriesCategories()

        progress(.fetchLive)
        let liveStreams = try await client.getLiveStreams()

        progress(.fetchMovies)
        let vods = try await client.getVODStreams()

        progress(.fetchSeries)
        let series = try await client.getSeries()

        let filterAdult = playlist.filterAdultContent
        let adultLiveCatIds   = filterAdult ? AdultContentFilter.adultCategoryIds(from: liveCats)   : []
        let adultVodCatIds    = filterAdult ? AdultContentFilter.adultCategoryIds(from: vodCats)    : []
        let adultSeriesCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: seriesCats) : []

        progress(.saving)
        try await AppDatabase.shared.write { db in
            if persistPlaylistRow {
                try playlist.save(db)
            }

            try insertCategories(liveCats,   type: "live",   pid: pid, filterAdult: filterAdult, db: db)
            try insertCategories(vodCats,    type: "vod",    pid: pid, filterAdult: filterAdult, db: db)
            try insertCategories(seriesCats, type: "series", pid: pid, filterAdult: filterAdult, db: db)

            for (index, stream) in liveStreams.enumerated() {
                if filterAdult, AdultContentFilter.isAdultLiveStream(stream, adultCategoryIds: adultLiveCatIds) { continue }
                try DBLiveStream(
                    streamId: stream.id,
                    name: stream.name ?? L("content.unnamed"),
                    streamIcon: stream.streamIcon,
                    epgChannelId: stream.epgChannelId,
                    categoryId: stream.categoryId,
                    sortIndex: index,
                    playlistId: pid
                ).save(db)
            }

            for (index, stream) in vods.enumerated() {
                if filterAdult, AdultContentFilter.isAdultVODStream(stream, adultCategoryIds: adultVodCatIds) { continue }
                var dbVOD = DBVODStream(
                    streamId: stream.id,
                    name: stream.name ?? L("content.unnamed"),
                    streamIcon: stream.streamIcon,
                    categoryId: stream.categoryId,
                    rating: stream.rating,
                    containerExtension: stream.containerExtension,
                    sortIndex: index,
                    playlistId: pid
                )
                dbVOD.added = stream.added
                try dbVOD.save(db)
            }

            for (index, s) in series.enumerated() {
                if filterAdult, let cid = s.categoryId, adultSeriesCatIds.contains(cid) { continue }
                try DBSeries(
                    seriesId: s.id,
                    name: s.name ?? L("content.unnamed"),
                    cover: s.cover,
                    plot: s.plot,
                    cast: s.cast,
                    director: s.director,
                    genre: s.genre,
                    releaseDate: s.releaseDate,
                    rating: s.rating,
                    lastModified: s.lastModified,
                    youtubeTrailer: s.youtubeTrailer,
                    categoryId: s.categoryId,
                    sortIndex: index,
                    playlistId: pid
                ).save(db)
            }
        }
    }

    private static func insertCategories(
        _ cats: [XtreamCategory],
        type: String,
        pid: UUID,
        filterAdult: Bool,
        db: Database
    ) throws {
        for (index, cat) in cats.enumerated() {
            if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
            try DBCategory(
                id: cat.id,
                name: cat.categoryName ?? L("content.unnamed"),
                parentId: cat.parentId,
                type: type,
                sortIndex: index,
                playlistId: pid
            ).save(db)
        }
    }
}
