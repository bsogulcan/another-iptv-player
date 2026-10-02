import GRDB
import SwiftUI

/// “Kaldığın yerden” / geçmişten açılan dizi oynatıcısı; aynı dizi içinde önceki–sonraki bölüme geçer.
struct HistorySeriesPlayerShell: View {
    let playlist: Playlist
    private let initialHistory: DBWatchHistory
    private let initialURL: URL

    @State private var session: SeriesPlaybackSession
    @State private var neighborPrev: DBEpisode?
    @State private var neighborNext: DBEpisode?
    @Environment(\.playerOverlayPresentationID) private var overlayPresentationID
    
    var onNavigateToDetail: ((String, String) -> Void)? = nil

    init(playlist: Playlist, history: DBWatchHistory, url: URL, onNavigateToDetail: ((String, String) -> Void)? = nil) {
        self.playlist = playlist
        self.initialHistory = history
        self.initialURL = url
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
        .onChange(of: overlayPresentationID) { _, _ in
            applyInitialSelectionIfNeeded()
        }
    }

    private func applyInitialSelectionIfNeeded() {
        let target = SeriesPlaybackSession(history: initialHistory, url: initialURL)
        guard session != target else { return }
        neighborPrev = nil
        neighborNext = nil
        session = target
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

        let episodesBySeason = info.episodesBySeasonNumber

        try? await AppDatabase.shared.write { db in
            for (seasonNum, apiSeason) in info.resolvedSeasons {
                let seasonId = DBSeason.scopedId(playlistId: playlist.id, seriesId: seriesId, seasonNumber: seasonNum)
                let eps = episodesBySeason[seasonNum] ?? []

                let dbSeason = DBSeason(
                    id: seasonId,
                    seasonNumber: seasonNum,
                    name: apiSeason?.name,
                    overview: apiSeason?.overview,
                    cover: apiSeason?.cover,
                    airDate: apiSeason?.airDate,
                    episodeCount: eps.isEmpty ? apiSeason?.episodeCount : eps.count,
                    voteAverage: apiSeason?.voteAverage,
                    seriesId: seriesId,
                    playlistId: playlist.id
                )
                try dbSeason.save(db)

                for ep in eps {
                    let dbEp = DBEpisode(
                        id: DBEpisode.scopedId(playlistId: playlist.id, panelEpisodeId: ep.id),
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
        let targetSid = ep.episodeId ?? ep.id
        // Aynı bölüme (hızlı çift tap / bayat buton) atlamayı yut ve komşuları hemen
        // sıfırla: refreshNeighbors ağ turu bitene dek eski bölümün komşuları
        // butonlarda/Control Center'da geçerli kalıyordu.
        guard targetSid != session.streamId else { return }
        neighborPrev = nil
        neighborNext = nil
        Task {
            let sid = targetSid
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
        // Neighbour steps (next / previous / auto-advance) must not land in the last seconds
        // of an episode that was already watched: it would end at once and cascade onward.
        // The item opened from Continue Watching keeps its raw position (init above).
        resumeTimeMs = resumeHistory?.resumePositionMs(as: .episode)
        containerExtension = episode.containerExtension
        self.seriesId = seriesId
    }
}
