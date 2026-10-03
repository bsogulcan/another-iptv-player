import GRDB
import Foundation

/// Applies only detail endpoint fields. Catalog names, categories and transport
/// fields must come from the current database row, not an old navigation value.
nonisolated enum DetailMetadata {
    static func movie(_ base: DBVODStream, response: XtreamVODInfoResponse) -> DBVODStream {
        var row = base
        row.metadataLoaded = true
        if let info = response.info {
            row.cast = info.cast
            row.director = info.director
            row.genre = info.genre
            row.plot = info.plot
            row.releaseDate = info.releaseDate
            row.rating = info.rating
            row.backdropPath = info.backdropPath?.first
            row.youtubeTrailer = info.youtubeTrailer
            row.duration = info.duration
            row.tmdbId = info.tmdbId
            row.kinopoiskURL = info.kinopoiskURL
            if let rating = info.rating.flatMap(Double.init) { row.rating5Based = rating / 2 }
        }
        return row
    }

    @discardableResult
    static func storeMovie(_ response: XtreamVODInfoResponse, streamId: Int, playlistId: UUID, db: Database) throws -> Bool {
        guard let current = try DBVODStream.filter(Column("streamId") == streamId)
            .filter(Column("playlistId") == playlistId).fetchOne(db) else { return false }
        try movie(current, response: response).update(db)
        return true
    }

    /// Does not mark seasons loaded: the episode list still waits for its commit.
    static func series(_ base: DBSeries, response: XtreamSeriesInfoResponse) -> DBSeries {
        var row = base
        if let info = response.info {
            row.cast = info.cast
            row.director = info.director
            row.genre = info.genre
            row.plot = info.plot
            row.releaseDate = info.releaseDate
            row.rating = info.rating
            row.lastModified = info.lastModified
            row.rating5Based = info.rating5Based
            row.backdropPath = info.backdropPath?.first
            row.youtubeTrailer = info.youtubeTrailer
            row.episodeRunTime = info.episodeRunTime
        }
        return row
    }
}
