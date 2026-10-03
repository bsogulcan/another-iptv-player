import SwiftUI
import GRDB
import GRDBQuery

/// İndirilen ve indirilmekte olan içerikleri listeler. Tamamlananlarda tıklayınca local dosyadan oynatır.
struct DownloadsView: View {
    let playlist: Playlist

    @Environment(\.playerOverlayController) private var playerOverlay
    @ObservedObject private var manager = DownloadManager.shared
    /// `nil` until the database has answered; see `LoadedRequest`.
    @Query<LoadedRequest<AllDownloadsRequest>> private var loadedItems: [DBDownloadedItem]?
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isSearchActive: Bool = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var pendingMovieDetail: DBVODStream?
    @State private var pendingSeriesDetail: DBSeries?
    /// "Tamamlandı" görünen ama dosyası diskte olmayan kayıt (cihaz geri yükleme sonrası
    /// tipik durum — Downloads klasörü yedeğe girmez). Alert ile yeniden indirme önerilir.
    @State private var missingFileItem: DBDownloadedItem?

    init(playlist: Playlist) {
        self.playlist = playlist
        _loadedItems = Query(LoadedRequest(AllDownloadsRequest(playlistId: playlist.id)), in: \.appDatabase)
    }

    /// The list as the screen shows it: one section per unfinished status, the
    /// finished films, then the finished episodes grouped by series.
    struct Sections: Equatable {
        struct EpisodeGroup: Equatable {
            let title: String
            let episodes: [DBDownloadedItem]
        }

        var inProgress: [DBDownloadedItem] = []
        /// Kuyruk `createdAt` artan sırayla gösterilir — sıradaki (en eski) en üstte.
        /// `AllDownloadsRequest` varsayılan olarak desc döner, burada özellikle ters çeviriyoruz.
        var queued: [DBDownloadedItem] = []
        var failed: [DBDownloadedItem] = []
        var completedMovies: [DBDownloadedItem] = []
        /// Tamamlanan bölümleri seri bazlı gruplar. Anahtar seriesId + secondaryTitle pair'i,
        /// böylece seriesId nil ise ada göre gruplayabiliriz.
        var completedEpisodeGroups: [EpisodeGroup] = []

        var isEmpty: Bool {
            inProgress.isEmpty && queued.isEmpty && failed.isEmpty
                && completedMovies.isEmpty && completedEpisodeGroups.isEmpty
        }
    }

    /// Filters and splits the list in one pass. The body runs again for every
    /// published percent of a running download, so the search match is done once
    /// per item here instead of once per section.
    static func sections(of items: [DBDownloadedItem], matching search: String) -> Sections {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = q.isEmpty ? nil : CatalogTextSearch.Query(q)
        var sections = Sections()
        var episodes: [String: [DBDownloadedItem]] = [:]
        for item in items {
            if let query, !query.matches(item.title), !query.matches(item.secondaryTitle ?? "") { continue }
            switch item.downloadStatus {
            case .downloading: sections.inProgress.append(item)
            case .queued: sections.queued.append(item)
            case .failed: sections.failed.append(item)
            case .completed:
                if item.type == "vod" {
                    sections.completedMovies.append(item)
                } else if item.type == "episode" {
                    episodes[item.secondaryTitle ?? item.seriesId ?? "-", default: []].append(item)
                }
            }
        }
        sections.queued.sort { $0.createdAt < $1.createdAt }
        sections.completedEpisodeGroups = episodes
            .map { title, items in
                let sorted = items.sorted { lhs, rhs in
                    let ls = lhs.seasonNumber ?? 0, rs = rhs.seasonNumber ?? 0
                    if ls != rs { return ls < rs }
                    return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
                }
                return Sections.EpisodeGroup(title: title, episodes: sorted)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return sections
    }

    var body: some View {
        let items = loadedItems ?? []
        let sections = Self.sections(of: items, matching: debouncedQuery)
        Group {
            if loadedItems == nil {
                // Nothing delivered yet: drawing "No downloads" here would flash it
                // in front of a list that arrives a moment later.
                Color.clear
            } else if items.isEmpty {
                CatalogEmptyView(.message(
                    title: L("download.empty.title"),
                    systemImage: "arrow.down.circle",
                    description: L("download.empty.message")
                ))
            } else if sections.isEmpty {
                CatalogEmptyView(.noSearchResults)
            } else {
                List {
                    if !sections.inProgress.isEmpty {
                        Section(L("download.status.downloading")) {
                            ForEach(sections.inProgress) { item in
                                actionableRow(item)
                            }
                        }
                    }
                    if !sections.queued.isEmpty {
                        Section(L("download.status.queued")) {
                            ForEach(sections.queued) { item in
                                actionableRow(item)
                            }
                        }
                    }
                    if !sections.failed.isEmpty {
                        Section(L("download.status.failed")) {
                            ForEach(sections.failed) { item in
                                actionableRow(item)
                            }
                        }
                    }
                    if !sections.completedMovies.isEmpty {
                        Section(L("dashboard.movies")) {
                            ForEach(sections.completedMovies) { item in
                                actionableRow(item)
                            }
                        }
                    }

                    ForEach(sections.completedEpisodeGroups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.episodes) { item in
                                actionableRow(item)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // A row whose status changes travels to its new section, and a
                // cancelled or deleted one leaves, instead of the list jumping.
                // Keyed on the stored rows, which change on status changes only:
                // neither a progress tick nor typing in the search field animates.
                .animation(.default, value: items)
            }
        }
        .navigationTitle(L("download.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: L("download.search_placeholder"))
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
        }
        .navigationDestination(item: $pendingSeriesDetail) { series in
            SeriesDetailView(playlist: playlist, series: series)
        }
        .alert(
            L("download.missing_file.title"),
            isPresented: Binding(
                get: { missingFileItem != nil },
                set: { if !$0 { missingFileItem = nil } }
            ),
            presenting: missingFileItem
        ) { item in
            Button(L("download.retry")) {
                redownload(item)
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(L("download.missing_file.message"))
        }
    }

    /// Dosyası kaybolmuş kaydı aynı id ile yeniden kuyruğa alır (failed retry ile aynı yol).
    private func redownload(_ item: DBDownloadedItem) {
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
    }

    /// Tek tap = birincil aksiyon (tekrar dene/oynat),
    /// trailing swipe = sil/iptal. Bu pattern tüm download statülerine uygulanır.
    @ViewBuilder
    private func actionableRow(_ item: DBDownloadedItem) -> some View {
        let isFinished = item.downloadStatus == .completed || item.downloadStatus == .failed
        Group {
            if isFinished {
                // The list's own button style: the system highlights the row and
                // takes the tap anywhere across it.
                Button {
                    performPrimaryAction(item)
                } label: {
                    row(item)
                }
            } else {
                // A running or queued download has no primary action, so its row is
                // not a button; the stop control at its trailing edge is.
                row(item)
            }
        }
        // A cancel throws the partial file away: an unfinished download takes a
        // tap on the revealed button, a full swipe alone does not fire it.
        .swipeActions(edge: .trailing, allowsFullSwipe: isFinished) {
            removalButton(for: item)
        }
        .contextMenu {
            switch item.downloadStatus {
            case .downloading, .queued:
                EmptyView()
            case .failed:
                Button {
                    redownload(item)
                } label: {
                    Label(L("download.retry"), systemImage: "arrow.clockwise")
                }
            case .completed:
                Button {
                    play(item)
                } label: {
                    Label(L("download.play"), systemImage: "play")
                }
            }
            removalButton(for: item)
        }
    }

    /// Cancel for an unfinished download, delete for a finished or failed one.
    @ViewBuilder
    private func removalButton(for item: DBDownloadedItem) -> some View {
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

    private func performPrimaryAction(_ item: DBDownloadedItem) {
        switch item.downloadStatus {
        case .downloading, .queued:
            break
        case .failed:
            // Retry: sadece aynı id ile yeniden enqueue. Manager zaten failed row'un üzerine yazar.
            redownload(item)
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

            // Concrete colours throughout the row: inside the list's button style a
            // hierarchical `.primary` / `.secondary` resolves against the accent tint.
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                if let sub = item.secondaryTitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                footer(for: item)
            }
            Spacer()
            trailingAccessory(for: item)
        }
        .foregroundStyle(Color.primary)
        .padding(.vertical, 2)
    }

    /// Finished and failed rows: an icon that tells what a tap on the row does (the
    /// row is the button). Unfinished rows: the stop control.
    @ViewBuilder
    private func trailingAccessory(for item: DBDownloadedItem) -> some View {
        switch item.downloadStatus {
        case .downloading, .queued:
            cancelMenu(for: item)
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

    /// The stop control of an unfinished download. It opens a menu instead of
    /// cancelling on the first touch, because a cancel discards what was downloaded.
    private func cancelMenu(for item: DBDownloadedItem) -> some View {
        Menu {
            removalButton(for: item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.secondary)
                // Widens the touch target without moving the icon off the trailing edge.
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        // Keeps the control's own hit area inside the list row.
        .buttonStyle(.borderless)
        .accessibilityLabel(L("download.cancel"))
    }

    @ViewBuilder
    private func footer(for item: DBDownloadedItem) -> some View {
        switch item.downloadStatus {
        case .downloading:
            DownloadProgressFooter(
                progress: manager.progress[item.id],
                stored: DownloadProgress(totalBytes: Int64(item.totalBytes), downloadedBytes: Int64(item.downloadedBytes))
            )
        case .queued:
            Text(L("download.status.queued"))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        case .completed:
            Text(Self.byteCount(Int64(item.totalBytes)))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        case .failed:
            Text(Self.failureText(item.errorMessage))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
        }
    }

    /// A file size in the app's language and the device's region.
    static func byteCount(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(AppLocale.current))
    }

    /// The stored reason of a failed download. Only the text survives the failure, so
    /// an empty or missing one falls back to the generic sentence `NetworkErrorText`
    /// uses for an error it cannot name.
    static func failureText(_ stored: String?) -> String {
        let text = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L("kit.error.generic") : text
    }

    private func play(_ item: DBDownloadedItem) {
        Task {
            guard let localURL = try? DownloadStorage.absoluteURL(forRelativePath: item.localPath),
                  FileManager.default.fileExists(atPath: localURL.path) else {
                // Sessizce yutma: satır "tamamlandı" görünürken hiçbir şey olmaması
                // kullanıcıya donmuş gibi gelir. Alert + yeniden indirme yolu sun.
                await MainActor.run { missingFileItem = item }
                return
            }

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
                    var history = existingHistory ?? DBWatchHistory(
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
                    // Picking a finished episode starts it over. The shell resumes from
                    // history.lastTimeMs (its Continue Watching entry relies on that), so
                    // the stale position is dropped here; the shell reads nothing else
                    // that depends on it.
                    if history.resumePositionMs(as: .episode) == nil { history.lastTimeMs = 0 }
                    playerOverlay.injected?.present(skipDownloadCheck: true, playlistId: playlist.id) {
                        HistorySeriesPlayerShell(
                            playlist: playlist,
                            history: history,
                            url: localURL,
                            onNavigateToDetail: navigateToSeriesDetail
                        )
                    }
                } else {
                    // Film — prev/next yok, sadece local oynatım + resume.
                    playerOverlay.injected?.present(skipDownloadCheck: true, playlistId: playlist.id) {
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
                            // A finished film starts over instead of reopening in its last seconds.
                            resumeTimeMs: existingHistory?.resumePositionMs(as: .film),
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
                playerOverlay.injected?.dismiss()
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
                playerOverlay.injected?.dismiss()
                pendingSeriesDetail = series
            }
        }
    }
}

/// Keep the last live value while the database observation removes a finished row.
/// The manager can remove its progress entry one frame before that observation.
private struct DownloadProgressFooter: View {
    let progress: DownloadProgress?
    let stored: DownloadProgress
    @State private var lastProgress: DownloadProgress?

    var body: some View {
        let shown = progress ?? lastProgress ?? stored
        let fraction = shown.fraction
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .animation(progress == nil ? nil : .linear(duration: 0.4), value: fraction)
            HStack {
                Text(DetailFormatting.percent(fraction))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
                if shown.totalBytes > 0 {
                    Text(DownloadsView.byteCount(shown.totalBytes))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .onChange(of: progress, initial: true) { _, value in
            if let value { lastProgress = value }
        }
    }
}
