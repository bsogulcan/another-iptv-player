import SwiftUI
import GRDB
import GRDBQuery

/// İndirilen ve indirilmekte olan içerikleri listeler. Tamamlananlarda tıklayınca local dosyadan oynatır.
struct DownloadsView: View {
    let playlist: Playlist

    @ObservedObject private var playerOverlay: PlayerOverlayController = .shared
    @ObservedObject private var manager = DownloadManager.shared
    @Query<AllDownloadsRequest> private var items: [DBDownloadedItem]
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isSearchActive: Bool = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var pendingMovieDetail: DBVODStream?
    @State private var pendingSeriesDetail: DBSeries?

    init(playlist: Playlist) {
        self.playlist = playlist
        _items = Query(AllDownloadsRequest(playlistId: playlist.id), in: \.appDatabase)
    }

    private var filteredItems: [DBDownloadedItem] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            CatalogTextSearch.matches(search: q, text: item.title)
                || CatalogTextSearch.matches(search: q, text: item.secondaryTitle ?? "")
        }
    }

    private var inProgress: [DBDownloadedItem] { filteredItems.filter { $0.downloadStatus == .downloading } }
    /// Kuyruk `createdAt` artan sırayla gösterilir — sıradaki (en eski) en üstte.
    /// `AllDownloadsRequest` varsayılan olarak desc döner, burada özellikle ters çeviriyoruz.
    private var queued: [DBDownloadedItem] {
        filteredItems
            .filter { $0.downloadStatus == .queued }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var completed: [DBDownloadedItem] { filteredItems.filter { $0.downloadStatus == .completed } }
    private var failed: [DBDownloadedItem] { filteredItems.filter { $0.downloadStatus == .failed } }

    private var completedMovies: [DBDownloadedItem] {
        completed.filter { $0.type == "vod" }
    }

    /// Tamamlanan bölümleri seri bazlı gruplar. Anahtar seriesId + secondaryTitle pair'i,
    /// böylece seriesId nil ise ada göre gruplayabiliriz.
    private var completedEpisodeGroups: [(title: String, episodes: [DBDownloadedItem])] {
        let episodes = completed.filter { $0.type == "episode" }
        let grouped = Dictionary(grouping: episodes) { $0.secondaryTitle ?? $0.seriesId ?? "-" }
        return grouped
            .map { (key, items) in
                let sorted = items.sorted { lhs, rhs in
                    let ls = lhs.seasonNumber ?? 0, rs = rhs.seasonNumber ?? 0
                    if ls != rs { return ls < rs }
                    return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
                }
                return (key, sorted)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        let overlayCapture: PlayerOverlayController = playerOverlay
        return Group {
            if items.isEmpty {
                ContentUnavailableView(
                    L("download.empty.title"),
                    systemImage: "arrow.down.circle",
                    description: Text(L("download.empty.message"))
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    if !inProgress.isEmpty {
                        Section(L("download.status.downloading")) {
                            ForEach(inProgress) { item in
                                actionableRow(item)
                            }
                        }
                    }
                    if !queued.isEmpty {
                        Section(L("download.status.queued")) {
                            ForEach(queued) { item in
                                actionableRow(item)
                            }
                        }
                    }
                    if !failed.isEmpty {
                        Section(L("download.status.failed")) {
                            ForEach(failed) { item in
                                actionableRow(item)
                            }
                        }
                    }
                    if !completedMovies.isEmpty {
                        Section(L("dashboard.movies")) {
                            ForEach(completedMovies) { item in
                                actionableRow(item)
                            }
                        }
                    }

                    ForEach(completedEpisodeGroups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.episodes) { item in
                                actionableRow(item)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(L("download.title"))
        
        .macSearchable(text: $searchText, prompt: L("download.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onChange(of: isSearchActive) { _, active in
            if !active { searchText = ""; debouncedQuery = "" }
        }
        .navigationDestination(item: $pendingMovieDetail) { movie in
            MovieDetailView(playlist: playlist, movie: movie)
                .environmentObject(overlayCapture)
        }
        .navigationDestination(item: $pendingSeriesDetail) { series in
            SeriesDetailView(playlist: playlist, series: series)
                .environmentObject(overlayCapture)
        }
    }

    /// Tek tap = birincil aksiyon (tekrar dene/oynat),
    /// trailing swipe = sil/iptal. Bu pattern tüm download statülerine uygulanır.
    @ViewBuilder
    private func actionableRow(_ item: DBDownloadedItem) -> some View {
        Button {
            performPrimaryAction(item)
        } label: {
            row(item)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            switch item.downloadStatus {
            case .downloading, .queued:
                Button(role: .destructive) {
                    manager.cancel(id: item.id)
                } label: {
                    Label(L("download.cancel"), systemImage: "xmark")
                }
            case .completed, .failed:
                Button(role: .destructive) {
                    Task { await manager.delete(id: item.id) }
                } label: {
                    Label(L("download.delete"), systemImage: "trash")
                }
            }
        }
    }

    private func performPrimaryAction(_ item: DBDownloadedItem) {
        switch item.downloadStatus {
        case .downloading, .queued:
            break
        case .failed:
            // Retry: sadece aynı id ile yeniden enqueue. Manager zaten failed row'un üzerine yazar.
            guard let url = URL(string: item.remoteURL) else { return }
            Task {
                await manager.enqueue(
                    id: item.id,
                    playlistId: item.playlistId,
                    streamId: item.streamId,
                    type: item.type,
                    title: item.title,
                    secondaryTitle: item.secondaryTitle,
                    imageURL: item.imageURL,
                    remoteURL: url,
                    containerExtension: item.containerExtension,
                    seriesId: item.seriesId,
                    seasonNumber: item.seasonNumber,
                    episodeNumber: item.episodeNumber
                )
            }
        case .completed:
            play(item)
        }
    }

    @ViewBuilder
    private func row(_ item: DBDownloadedItem) -> some View {
        HStack(spacing: 12) {
            CachedImage(
                url: item.imageURL.flatMap { URL(string: $0) },
                width: 56, height: 56,
                iconName: item.type == "episode" ? "play.tv" : "film",
                loadProfile: .grid
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let sub = item.secondaryTitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                footer(for: item)
            }
            Spacer()
            primaryActionIcon(for: item)
        }
        .padding(.vertical, 2)
    }

    /// Satırın birincil aksiyonunu görsel olarak bildirir (tıklanabilir değil — tüm satır butondur).
    @ViewBuilder
    private func primaryActionIcon(for item: DBDownloadedItem) -> some View {
        switch item.downloadStatus {
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .queued:
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.orange)
        case .completed:
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func footer(for item: DBDownloadedItem) -> some View {
        switch item.downloadStatus {
        case .downloading:
            let p = manager.progress[item.id]
            let fraction = p?.fraction ?? 0
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text(L("download.downloading_format", Int(fraction * 100)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let p, p.totalBytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: p.totalBytes, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .queued:
            Text(L("download.status.queued"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .completed:
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.totalBytes), countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Text(item.errorMessage ?? L("common.unknown_error"))
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func play(_ item: DBDownloadedItem) {
        Task {
            guard let localURL = try? DownloadStorage.absoluteURL(forRelativePath: item.localPath),
                  FileManager.default.fileExists(atPath: localURL.path) else { return }

            // Bölüm ise history.type "series", film ise "vod" olarak DB'de saklanır.
            let historyType = item.type == "episode" ? "series" : "vod"
            let existingHistory: DBWatchHistory? = try? await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(
                        Column("playlistId") == playlist.id
                        && Column("type") == historyType
                        && Column("streamId") == item.streamId
                    )
                    .fetchOne(db)
            }

            await MainActor.run {
                if item.type == "episode" {
                    // Diziye ait — HistorySeriesPlayerShell hem resume hem de bir sonraki/önceki
                    // bölüme geçişi yönetir (sıralama dizinin kendi episode order'ı, indirme sırası değil).
                    let history = existingHistory ?? DBWatchHistory(
                        id: "\(playlist.id)_series_\(item.streamId)",
                        playlistId: playlist.id,
                        streamId: item.streamId,
                        type: "series",
                        lastTimeMs: 0,
                        durationMs: 0,
                        lastWatchedAt: Date(),
                        seriesId: item.seriesId,
                        title: item.title,
                        secondaryTitle: item.secondaryTitle,
                        imageURL: item.imageURL,
                        containerExtension: item.containerExtension
                    )
                    playerOverlay.present(skipDownloadCheck: true, playlistId: playlist.id) {
                        HistorySeriesPlayerShell(
                            playlist: playlist,
                            history: history,
                            url: localURL,
                            onNavigateToDetail: navigateToSeriesDetail
                        )
                    }
                } else {
                    // Film — prev/next yok, sadece local oynatım + resume.
                    playerOverlay.present(skipDownloadCheck: true, playlistId: playlist.id) {
                        PlayerView(
                            url: localURL,
                            title: item.title,
                            subtitle: item.secondaryTitle,
                            artworkURL: item.imageURL.flatMap { URL(string: $0) },
                            isLiveStream: false,
                            playlistId: playlist.id,
                            streamId: item.streamId,
                            type: "vod",
                            seriesId: item.seriesId,
                            resumeTimeMs: existingHistory?.lastTimeMs,
                            containerExtension: item.containerExtension,
                            onNavigateToDetail: navigateToMovieDetail
                        )
                    }
                }
            }
        }
    }

    /// Player'da başlığa tıklandığında film detayına git.
    private func navigateToMovieDetail(type: String, id: String) {
        guard type == "vod", let vId = Int(id) else { return }
        Task {
            guard let movie = try? await AppDatabase.shared.read({ db in
                try DBVODStream
                    .filter(Column("streamId") == vId && Column("playlistId") == playlist.id)
                    .fetchOne(db)
            }) else { return }
            await MainActor.run {
                playerOverlay.dismiss()
                pendingMovieDetail = movie
            }
        }
    }

    /// Player'da başlığa tıklandığında dizi detayına git.
    private func navigateToSeriesDetail(type: String, id: String) {
        guard let sId = Int(id) else { return }
        Task {
            guard let series = try? await AppDatabase.shared.read({ db in
                try DBSeries
                    .filter(Column("seriesId") == sId && Column("playlistId") == playlist.id)
                    .fetchOne(db)
            }) else { return }
            await MainActor.run {
                playerOverlay.dismiss()
                pendingSeriesDetail = series
            }
        }
    }
}
