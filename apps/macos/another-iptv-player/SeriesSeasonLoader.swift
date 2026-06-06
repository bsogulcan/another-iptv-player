import Foundation
import GRDB

/// Bir serinin sezon + bölümlerini API'den yükleyip DB'ye yazar. Aynı seri için eşzamanlı
/// çağrıları dedupe eder. Mantık `SeriesDetailView.fetchSeriesInfo`'nun bir özetidir —
/// sidebar lazy expansion + SeriesDetailView aynı veri yükleme yolu için ortak nokta.
@MainActor
final class SeriesSeasonLoader {
    static let shared = SeriesSeasonLoader()
    private var inflight: Set<Int> = []

    /// Sezonlar daha önce yüklenmediyse API çağrısı yapar ve DB'ye yazar.
    /// İnflight dedup: aynı seri için paralel çağrılar engellenir.
    /// Caller hatayı kendi UI state'iyle bağlamak isterse do/catch ile sarmalayabilir;
    /// fire-and-forget kullanım için `loadIgnoringErrors(_:playlist:)` var.
    func ensureLoaded(series: DBSeries, playlist: Playlist) async throws {
        guard !series.seasonsLoaded, !inflight.contains(series.seriesId) else { return }
        inflight.insert(series.seriesId)
        defer { inflight.remove(series.seriesId) }

        let client = XtreamAPIClient(playlist: playlist)
        let info = try await client.getSeriesInfo(seriesId: series.seriesId)
        try await persist(info: info, series: series, playlist: playlist)
    }

    /// Sidebar lazy expansion path — hata yutulur, kullanıcı tekrar deneyebilir.
    func loadIgnoringErrors(_ series: DBSeries, playlist: Playlist) async {
        do {
            try await ensureLoaded(series: series, playlist: playlist)
        } catch {
            print("SeriesSeasonLoader error: \(error)")
        }
    }

    private func persist(info: XtreamSeriesInfoResponse, series: DBSeries, playlist: Playlist) async throws {
        try await AppDatabase.shared.write { db in
            let apiSeasons = info.seasons ?? []
            let episodesDict = info.episodes ?? [:]
            var processedSeasons: [XtreamSeason] = apiSeasons

            if processedSeasons.isEmpty && !episodesDict.isEmpty {
                for key in episodesDict.keys.sorted(by: { Int($0) ?? 0 < Int($1) ?? 0 }) {
                    if let seasonNum = Int(key),
                       let virtual = try? JSONDecoder().decode(XtreamSeason.self, from: """
                       {"season_number": \(seasonNum), "name": "Sezon \(seasonNum)"}
                       """.data(using: .utf8)!) {
                        processedSeasons.append(virtual)
                    }
                }
            }

            for apiSeason in processedSeasons {
                let seasonNum = apiSeason.seasonNumber ?? 0
                let seasonId = "\(series.seriesId)_\(seasonNum)"
                let dbSeason = DBSeason(
                    id: seasonId,
                    seasonNumber: seasonNum,
                    name: apiSeason.name ?? "Sezon \(seasonNum)",
                    overview: apiSeason.overview,
                    cover: apiSeason.cover,
                    airDate: apiSeason.airDate,
                    episodeCount: apiSeason.episodeCount,
                    voteAverage: apiSeason.voteAverage,
                    seriesId: series.seriesId,
                    playlistId: playlist.id
                )
                try dbSeason.save(db)

                if let eps = episodesDict[String(seasonNum)] {
                    for ep in eps {
                        let dbEp = DBEpisode(
                            id: ep.id ?? UUID().uuidString,
                            episodeId: ep.id,
                            episodeNum: ep.episodeNum,
                            title: ep.title,
                            containerExtension: ep.containerExtension,
                            info: ep.info?.plot,
                            cover: ep.info?.movieImage ?? ep.info?.cover,
                            duration: ep.info?.duration,
                            rating: ep.info?.rating,
                            seasonId: seasonId
                        )
                        try dbEp.save(db)
                    }
                }
            }

            var updatedSeries = series
            updatedSeries.seasonsLoaded = true
            if let i = info.info {
                updatedSeries.cast = i.cast
                updatedSeries.director = i.director
                updatedSeries.genre = i.genre
                updatedSeries.plot = i.plot
                updatedSeries.releaseDate = i.releaseDate
                updatedSeries.rating = i.rating
                updatedSeries.lastModified = i.lastModified
                updatedSeries.rating5Based = i.rating5Based
                updatedSeries.backdropPath = i.backdropPath?.first
                updatedSeries.youtubeTrailer = i.youtubeTrailer
                updatedSeries.episodeRunTime = i.episodeRunTime
            }
            try updatedSeries.update(db)
        }
    }
}
