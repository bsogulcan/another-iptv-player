import Foundation
import GRDB

/// Fetches all Xtream content (categories, live, VOD, series) and writes it to the
/// database together with the playlist. Shared by the Xtream add/edit flow and the
/// M3U flow's Xtream auto-detection.
enum XtreamImporter {

    /// Full sync: downloads everything from the panel, then saves playlist + content.
    /// The playlist row is saved before content so it stays visible even if a later
    /// step fails. `progress` receives localized status messages on the main actor.
    static func syncAndSave(
        playlist: Playlist,
        client: XtreamAPIClient,
        progress: @escaping @MainActor (String) -> Void
    ) async throws {
        print("--- XTREAM IMPORT: SYNC STARTED (SQLITE) ---")
        let totalStartTime = Date()

        let catStart = Date()
        await progress(L("add_playlist.fetching_categories"))
        let liveCats = try await client.getLiveCategories()
        let vodCats = try await client.getVODCategories()
        let seriesCats = try await client.getSeriesCategories()
        print("NETWORK: Categories fetched in \(Date().timeIntervalSince(catStart)) seconds")

        let liveStart = Date()
        await progress(L("add_playlist.fetching_live"))
        let liveStreams = try await client.getLiveStreams()
        print("NETWORK: Live Streams fetched in \(Date().timeIntervalSince(liveStart)) seconds | Count: \(liveStreams.count)")

        let vodStart = Date()
        await progress(L("add_playlist.fetching_movies"))
        let vods = try await client.getVODStreams()
        print("NETWORK: VODs fetched in \(Date().timeIntervalSince(vodStart)) seconds | Count: \(vods.count)")

        let seriesStart = Date()
        await progress(L("add_playlist.fetching_series"))
        let series = try await client.getSeries()
        print("NETWORK: Series fetched in \(Date().timeIntervalSince(seriesStart)) seconds | Count: \(series.count)")

        // 1. Save the playlist first so it shows up in the list even if content insertion fails.
        try await AppDatabase.shared.write { db in
            try playlist.save(db)
        }
        print("DATABASE: Playlist saved successfully")

        await progress(L("add_playlist.saving_db"))
        let insertStart = Date()

        // Adult content filter
        let filterAdult = playlist.filterAdultContent
        let adultLiveCatIds   = filterAdult ? AdultContentFilter.adultCategoryIds(from: liveCats)   : []
        let adultVodCatIds    = filterAdult ? AdultContentFilter.adultCategoryIds(from: vodCats)    : []
        let adultSeriesCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: seriesCats) : []

        // 2. Save content (upsert avoids conflicts).
        try await AppDatabase.shared.write { db in
            // Categories
            for (index, cat) in liveCats.enumerated() {
                if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "live", sortIndex: index, playlistId: playlist.id)
                try dbCat.save(db)
            }
            for (index, cat) in vodCats.enumerated() {
                if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "vod", sortIndex: index, playlistId: playlist.id)
                try dbCat.save(db)
            }
            for (index, cat) in seriesCats.enumerated() {
                if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "series", sortIndex: index, playlistId: playlist.id)
                try dbCat.save(db)
            }

            // Live Streams
            for (index, stream) in liveStreams.enumerated() {
                if filterAdult, AdultContentFilter.isAdultLiveStream(stream, adultCategoryIds: adultLiveCatIds) { continue }
                let dbStream = DBLiveStream(streamId: stream.id, name: stream.name ?? L("content.unnamed"), streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId, categoryId: stream.categoryId, sortIndex: index, playlistId: playlist.id)
                try dbStream.save(db)
            }

            // VODs
            for (index, stream) in vods.enumerated() {
                if filterAdult, AdultContentFilter.isAdultVODStream(stream, adultCategoryIds: adultVodCatIds) { continue }
                var dbVOD = DBVODStream(streamId: stream.id, name: stream.name ?? L("content.unnamed"), streamIcon: stream.streamIcon, categoryId: stream.categoryId, rating: stream.rating, containerExtension: stream.containerExtension, sortIndex: index, playlistId: playlist.id)
                dbVOD.added = stream.added
                try dbVOD.save(db)
            }

            // Series
            for (index, s) in series.enumerated() {
                if filterAdult, let cid = s.categoryId, adultSeriesCatIds.contains(cid) { continue }
                var dbSeries = DBSeries(seriesId: s.id, name: s.name ?? L("content.unnamed"), cover: s.cover, plot: s.plot, genre: s.genre, rating: s.rating, categoryId: s.categoryId, sortIndex: index, playlistId: playlist.id)
                dbSeries.lastModified = s.lastModified
                try dbSeries.save(db)
            }
        }

        print("DATABASE: Total Insertion completed in \(Date().timeIntervalSince(insertStart)) seconds")
        print("--- TOTAL SYNC TIME: \(Date().timeIntervalSince(totalStartTime)) seconds ---")
    }
}
