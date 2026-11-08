import Foundation
import GRDB

/// Fetches all Xtream content (categories, live, VOD, series) and writes it to the
/// database together with the playlist. Shared by the Xtream add/edit flow and the
/// M3U flow's Xtream auto-detection.
enum XtreamImporter {

    /// Stage of an import, for callers whose UI depends on it: cancelling the task
    /// only has an effect while `.downloading`.
    enum Phase {
        case downloading
        case saving
    }

    /// Full sync: downloads everything from the panel, then saves playlist + content.
    /// The playlist row is saved before content so it stays visible even if a later
    /// step fails. `progress` receives localized status messages on the main actor.
    ///
    /// The catalog is replaced, not merged: on an edit (same playlist id) rows the new
    /// payload no longer contains, or that the adult filter now excludes, are removed,
    /// exactly as a refresh from Settings does.
    ///
    /// Cancelling the calling task while the download runs throws and leaves the
    /// database untouched. Once `.saving` has been reported the import completes
    /// regardless of cancellation.
    @discardableResult
    static func syncAndSave(
        playlist: Playlist,
        client: XtreamAPIClient,
        database: AppDatabase = .shared,
        editing original: Playlist? = nil,
        progress: @escaping @MainActor (String) -> Void,
        onPhase: (@MainActor (Phase) -> Void)? = nil
    ) async throws -> Playlist {
        // Altı endpoint bağımsız — sıralı beklemek toplam süreyi altı gidiş-dönüşün
        // TOPLAMI yapıyordu; paralel çekim yavaş panellerde süreyi yarıdan fazla kısaltır.
        let fetchStart = Date()
        onPhase?(.downloading)
        progress(L("add_playlist.fetching_categories"))
        async let liveCatsTask = client.getLiveCategories()
        async let vodCatsTask = client.getVODCategories()
        async let seriesCatsTask = client.getSeriesCategories()
        async let liveStreamsTask = client.getLiveStreams()
        async let vodsTask = client.getVODStreams()
        async let seriesTask = client.getSeries()
        let (liveCats, vodCats, seriesCats, liveStreams, vods, series) = try await (
            liveCatsTask, vodCatsTask, seriesCatsTask, liveStreamsTask, vodsTask, seriesTask
        )
        let fetchSeconds = Date().timeIntervalSince(fetchStart)

        // Last exit for a cancel. The requests fail on their own when the task is
        // cancelled, but the decode that follows them does not notice, so a cancel
        // that lands late arrives here with a complete payload.
        try Task.checkCancellation()

        onPhase?(.saving)
        progress(L("add_playlist.saving_db"))
        let saveStart = Date()

        let pid = playlist.id
        let saved = try await Task {
            // Preserve the add flow's early playlist row. An edit commits the row
            // and the catalogue together so an old response cannot split them.
            if original == nil {
                try await database.write { db in try playlist.save(db) }
            }
            return try await database.write { db in
                let stored: Playlist
                if let original {
                    stored = try playlist.mergingImportEdit(from: original, in: db)
                    try stored.update(db)
                } else {
                    guard let row = try Playlist.fetchOne(db, key: pid), row.usesSameProvider(as: playlist) else { throw PlaylistImportConflict.changed }
                    stored = row
                }
                let filterAdult = stored.filterAdultContent
                try PlaylistContentStore.replaceLiveCatalog(db: db, pid: pid, categories: liveCats, streams: liveStreams, filterAdult: filterAdult)
                try PlaylistContentStore.replaceVODCatalog(db: db, pid: pid, categories: vodCats, streams: vods, filterAdult: filterAdult)
                try PlaylistContentStore.replaceSeriesCatalog(db: db, pid: pid, categories: seriesCats, series: series, filterAdult: filterAdult)
                return stored
            }
        }.value

        Log.info("XtreamImport", String(
            format: "live=%d vod=%d series=%d fetched in %.2fs, saved in %.2fs",
            liveStreams.count, vods.count, series.count, fetchSeconds, Date().timeIntervalSince(saveStart)
        ))
        return saved
    }
}
