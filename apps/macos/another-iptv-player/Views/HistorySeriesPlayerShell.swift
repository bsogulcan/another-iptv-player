import GRDB
import SwiftUI

/// “Kaldığın yerden” / geçmişten açılan dizi oynatıcısı; aynı dizi içinde önceki–sonraki bölüme geçer.
struct HistorySeriesPlayerShell: View {
    let playlist: Playlist

    @State private var session: SeriesPlaybackSession
    @State private var neighborPrev: DBEpisode?
    @State private var neighborNext: DBEpisode?
    
    var onNavigateToDetail: ((String, String) -> Void)? = nil

    init(playlist: Playlist, history: DBWatchHistory, url: URL, onNavigateToDetail: ((String, String) -> Void)? = nil) {
        self.playlist = playlist
        _session = State(initialValue: SeriesPlaybackSession(history: history, url: url))
        self.onNavigateToDetail = onNavigateToDetail
    }

    var body: some View {
        PlayerView(
            url: session.url,
            title: session.title,
            subtitle: session.subtitle,
            artworkURL: session.artworkURL,
            isLiveStream: false,
            playlistId: playlist.id,
            streamId: session.streamId,
            type: "series",
            seriesId: session.seriesId,
            resumeTimeMs: session.resumeTimeMs,
            containerExtension: session.containerExtension,
            canGoToPreviousEpisode: neighborPrev != nil,
            canGoToNextEpisode: neighborNext != nil,
            onPreviousEpisode: { jumpTo(neighborPrev) },
            onNextEpisode: { jumpTo(neighborNext) },
            onNavigateToDetail: onNavigateToDetail
        )
        .task(id: session.streamId) {
            await refreshNeighbors()
        }
    }

    private func refreshNeighbors() async {
        guard let seriesIdStr = session.seriesId, let seriesId = Int(seriesIdStr) else {
            await MainActor.run { neighborPrev = nil; neighborNext = nil }
            return
        }

        // Sync sonrası cascade silinmiş olabilir; seasonsLoaded = false ise API'dan çek
        let episodesMissing = (try? await AppDatabase.shared.read { db in
            try DBSeries
                .filter(Column("seriesId") == seriesId && Column("playlistId") == playlist.id)
                .fetchOne(db)
                .map { !$0.seasonsLoaded } ?? true
        }) ?? true

        if episodesMissing {
            await loadEpisodesFromAPI(seriesId: seriesId)
        }

        let ctx = try? await AppDatabase.shared.read { db in
            try SeriesPlaybackOrdering.navigationContext(
                playlistId: playlist.id,
                playbackStreamId: session.streamId,
                seriesIdHint: seriesIdStr,
                db: db
            )
        }
        await MainActor.run {
            neighborPrev = ctx?.previous
            neighborNext = ctx?.next
        }
    }

    private func loadEpisodesFromAPI(seriesId: Int) async {
        let client = XtreamAPIClient(playlist: playlist)
        guard let info = try? await client.getSeriesInfo(seriesId: seriesId) else { return }

        let episodesDict = info.episodes ?? [:]
        var processedSeasons = info.seasons ?? []

        // Sezon verisi yoksa bölüm anahtarlarından sanal sezon üret
        if processedSeasons.isEmpty && !episodesDict.isEmpty {
            for key in episodesDict.keys.sorted(by: { Int($0) ?? 0 < Int($1) ?? 0 }) {
                if let seasonNum = Int(key),
                   let data = "{\"season_number\": \(seasonNum), \"name\": \"Sezon \(seasonNum)\"}".data(using: .utf8),
                   let virtual = try? JSONDecoder().decode(XtreamSeason.self, from: data) {
                    processedSeasons.append(virtual)
                }
            }
        }

        try? await AppDatabase.shared.write { db in
            for apiSeason in processedSeasons {
                let seasonNum = apiSeason.seasonNumber ?? 0
                let seasonId = "\(seriesId)_\(seasonNum)"
                let dbSeason = DBSeason(
                    id: seasonId,
                    seasonNumber: seasonNum,
                    name: apiSeason.name ?? "Sezon \(seasonNum)",
                    overview: apiSeason.overview,
                    cover: apiSeason.cover,
                    airDate: apiSeason.airDate,
                    episodeCount: apiSeason.episodeCount,
                    voteAverage: apiSeason.voteAverage,
                    seriesId: seriesId,
                    playlistId: playlist.id
                )
                try dbSeason.save(db)

                for ep in episodesDict[String(seasonNum)] ?? [] {
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

            // Bir dahaki açılışta tekrar çekilmesin
            if var s = try DBSeries
                .filter(Column("seriesId") == seriesId && Column("playlistId") == playlist.id)
                .fetchOne(db) {
                s.seasonsLoaded = true
                try s.save(db)
            }
        }
    }

    private func jumpTo(_ episode: DBEpisode?) {
        guard let ep = episode else { return }
        Task {
            let sid = ep.episodeId ?? ep.id
            // Bölüm indirilmişse local dosyadan oynat; yoksa remote URL kullan.
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(episode: playlist.id, episodeId: sid)
            )
            let url: URL
            if let localURL {
                url = localURL
            } else {
                let builder = PlaybackURLBuilder(playlist: playlist)
                guard let remoteURL = builder.seriesURL(streamId: sid, containerExtension: ep.containerExtension) else { return }
                url = remoteURL
            }
            let hist: DBWatchHistory? = try? await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(
                        Column("streamId") == sid && Column("playlistId") == playlist.id && Column("type") == "series"
                    )
                    .fetchOne(db)
            }
            let seriesIdStr = session.seriesId
            let seriesTitle = session.subtitle
            await MainActor.run {
                session = SeriesPlaybackSession(
                    episode: ep,
                    url: url,
                    seriesId: seriesIdStr,
                    seriesTitle: seriesTitle,
                    resumeHistory: hist
                )
            }
        }
    }
}

private struct SeriesPlaybackSession: Equatable {
    var url: URL
    var streamId: String
    var title: String
    var subtitle: String?
    var artworkURL: URL?
    var resumeTimeMs: Int?
    var containerExtension: String?
    var seriesId: String?

    init(history: DBWatchHistory, url: URL) {
        self.url = url
        streamId = history.streamId
        title = history.title
        subtitle = history.secondaryTitle
        artworkURL = history.imageURL.flatMap { URL(string: $0) }
        resumeTimeMs = history.lastTimeMs
        containerExtension = history.containerExtension
        seriesId = history.seriesId
    }

    init(episode: DBEpisode, url: URL, seriesId: String?, seriesTitle: String?, resumeHistory: DBWatchHistory?) {
        self.url = url
        streamId = episode.episodeId ?? episode.id
        title = {
            let num = episode.episodeNum.map { "\($0). " } ?? ""
            let raw = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let t = raw.isEmpty ? L("detail.episode_fallback") : raw
            return num + t
        }()
        subtitle = seriesTitle
        artworkURL = episode.cover.flatMap { URL(string: $0) }
        resumeTimeMs = resumeHistory?.lastTimeMs
        containerExtension = episode.containerExtension
        self.seriesId = seriesId
    }
}
