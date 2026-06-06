import SwiftUI
import Foundation
import Combine
import GRDB
import GRDBQuery

struct SeriesView: View {
    let playlist: Playlist
    @Binding var externalSearch: String
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @ObservedObject private var playerOverlay: PlayerOverlayController = .shared

    @State private var pendingSeriesDetail: DBSeries?

    init(playlist: Playlist, externalSearch: Binding<String> = .constant("")) {
        self.playlist = playlist
        self._externalSearch = externalSearch
    }

    private var pickerEntries: [CategoryPickerSheet.Entry] {
        contentStore.seriesCategories.map { cat in
            CategoryPickerSheet.Entry(
                id: cat.id,
                name: cat.name,
                count: contentStore.seriesItemsByCategoryId[cat.id]?.count ?? 0
            )
        }
    }

    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var displayCategories: [DBCategory] = []
    @State private var displayItemsByCategory: [String: [SeriesWithCategory]] = [:]
    @State private var recentlyAddedSeries: [DBSeries] = []

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    var body: some View {
        // Body içinde env-bound playerOverlay'i pre-capture et — navigationDestination
        // closure'ı çalışırken @EnvironmentObject lookup'ı başarısız oluyor (NSHosting
        // controller içinde push destination SwiftUI env'i kaybediyor). Kapatma ile
        // local referans verilince crash bypass edilir.
        let overlayCapture: PlayerOverlayController = playerOverlay
        return Group {
            if displayCategories.isEmpty {
                if contentStore.isLoading || playlist.id != contentStore.activePlaylistId {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(contentStore.loadingMessage ?? L("series.empty.preparing"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "play.tv")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(debouncedQuery.isEmpty ? L("live.empty.no_category") : L("list.no_result"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        ContinueWatchingRow(
                            playlist: playlist,
                            typeFilter: "series",
                            destination: {
                                WatchHistoryListView(playlist: playlist, typeFilter: "series") { item in
                                    presentSeriesHistoryItem(item)
                                }
                            },
                            onPlay: { item in
                                presentSeriesHistoryItem(item)
                            }
                        )

                        if !recentlyAddedSeries.isEmpty {
                            RecentlyAddedSeriesShelf(playlist: playlist, items: recentlyAddedSeries)
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(displayCategories) { category in
                                SeriesCategoryShelfRow(
                                    playlist: playlist,
                                    category: category,
                                    items: displayItemsByCategory[category.id] ?? [],
                                    isStreamsLoading: !contentStore.streamsLoaded
                                )
                                .equatable()
                                .id(category.id)
                            }
                        }
                    }
                    .onChange(of: pendingScrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            pendingScrollTarget = nil
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerSheet(
                title: L("category_picker.title"),
                entries: pickerEntries,
                playlistId: playlist.id,
                type: "series"
            ) { id in
                showingCategoryPicker = false
                pendingScrollTarget = id
            }
        }
        .onChange(of: externalSearch) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .task(id: debouncedQuery) { await recomputeFilter() }
        .task(id: contentStore.streamsLoaded) { await recomputeFilter() }
        .task(id: hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")) { await recomputeFilter() }
        .transaction { $0.animation = nil }
        .navigationDestination(item: $pendingSeriesDetail) { series in
            SeriesDetailView(playlist: playlist, series: series)
                .environmentObject(overlayCapture)
        }
    }

    private func presentSeriesHistoryItem(_ item: DBWatchHistory) {
        Task {
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(episode: playlist.id, episodeId: item.streamId)
            )
            await MainActor.run {
                presentSeriesHistoryItem(item, localOverrideURL: localURL)
            }
        }
    }

    private func presentSeriesHistoryItem(_ item: DBWatchHistory, localOverrideURL: URL?) {
        let url: URL? = localOverrideURL ?? buildURL(for: item)
        guard let url else { return }
        let navigateToDetail: (String, String) -> Void = { type, id in
            Task {
                if let sId = Int(id),
                   let series = try? await AppDatabase.shared.read({ db in
                    try DBSeries.filter(Column("seriesId") == sId && Column("playlistId") == playlist.id).fetchOne(db)
                }) {
                    await MainActor.run {
                        playerOverlay.dismiss()
                        pendingSeriesDetail = series
                    }
                }
            }
        }
        if item.type == "series" {
            playerOverlay.present(skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
                HistorySeriesPlayerShell(playlist: playlist, history: item, url: url, onNavigateToDetail: navigateToDetail)
            }
        } else {
            playerOverlay.present(skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
                PlayerView(
                    url: url,
                    title: item.title,
                    subtitle: item.secondaryTitle,
                    artworkURL: item.imageURL.flatMap { URL(string: $0) },
                    isLiveStream: false,
                    playlistId: playlist.id,
                    streamId: item.streamId,
                    type: item.type,
                    seriesId: item.seriesId,
                    resumeTimeMs: item.lastTimeMs,
                    containerExtension: item.containerExtension,
                    onNavigateToDetail: navigateToDetail
                )
            }
        }
    }

    private func recomputeFilter() async {
        guard playlist.id == contentStore.activePlaylistId else {
            displayCategories = []; displayItemsByCategory = [:]; recentlyAddedSeries = []; return
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")
        let allCats = contentStore.seriesCategories.filter { !hidden.contains($0.id) }
        let allByCategory = contentStore.seriesItemsByCategoryId
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayCategories = allCats
            displayItemsByCategory = allByCategory
            let visibleCatIds = Set(allCats.map(\.id))
            let allSeries = contentStore.seriesItems
            recentlyAddedSeries = await Task.detached(priority: .userInitiated) {
                allSeries
                    .lazy
                    .filter { visibleCatIds.contains($0.series.categoryId ?? "") }
                    .compactMap { item -> (DBSeries, Int)? in
                        guard let ts = item.series.lastModified.flatMap(Int.init) else { return nil }
                        return (item.series, ts)
                    }
                    .sorted { $0.1 > $1.1 }
                    .prefix(20)
                    .map(\.0)
            }.value
            return
        }
        recentlyAddedSeries = []

        let result = await Task.detached(priority: .userInitiated) {
            var cats: [DBCategory] = []
            var byCategory: [String: [SeriesWithCategory]] = [:]
            for cat in allCats {
                let catMatch = CatalogTextSearch.matches(search: q, text: cat.name)
                let items = allByCategory[cat.id] ?? []
                let filtered = catMatch ? items : items.filter { CatalogTextSearch.matches(search: q, text: $0.series.name) }
                if catMatch || !filtered.isEmpty {
                    cats.append(cat)
                    byCategory[cat.id] = filtered
                }
            }
            return (cats, byCategory)
        }.value

        guard !Task.isCancelled else { return }
        displayCategories = result.0
        displayItemsByCategory = result.1
    }

    private func buildURL(for item: DBWatchHistory) -> URL? {
        let builder = PlaybackURLBuilder(playlist: playlist)
        // Series tab olduğu için series varsayımı
        return builder.seriesURL(streamId: item.streamId, containerExtension: item.containerExtension)
    }
}

// MARK: - Recently Added shelf

struct RecentlyAddedSeriesShelf: View, Equatable {
    let playlist: Playlist
    let items: [DBSeries]

    static func == (lhs: RecentlyAddedSeriesShelf, rhs: RecentlyAddedSeriesShelf) -> Bool {
        lhs.playlist.id == rhs.playlist.id && lhs.items == rhs.items
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.sidebarCategorySelector) private var sidebarCategorySelector

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                recentlyAddedHeader
                Spacer()
            }
            .padding(.horizontal, 16)

            PagedHorizontalShelf(
                items: items,
                itemWidth: posterMetrics.shelfPosterWidth,
                itemSpacing: 14,
                horizontalPadding: 16
            ) { series in
                seriesCardLink(series: series)
            }
            .frame(height: posterMetrics.shelfRowTotalHeight)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func seriesCardLink(series: DBSeries) -> some View {
        let card = SeriesCard(
            playlistId: playlist.id,
            stream: series,
            posterWidth: posterMetrics.shelfPosterWidth,
            posterHeight: posterMetrics.shelfPosterHeight,
            imageLoadProfile: .shelf
        )
        if let selector = sidebarCategorySelector {
            Button {
                let catId = series.categoryId ?? ""
                selector.navigate(.item(playlist.id, .series, catId, String(series.seriesId)))
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                SeriesDetailView(playlist: playlist, series: series)
                    .trackDetailDepth()
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recentlyAddedHeader: some View {
        let label = HStack(spacing: 6) {
            Text(L("recently_added.title"))
                .font(.headline)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)

        if let selector = sidebarCategorySelector {
            Button {
                selector.select(.series, "__recently_added__")
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                RecentlyAddedSeriesDetailView(playlist: playlist, items: items)
                    .trackDetailDepth()
            } label: {
                label
            }
        }
    }
}

// MARK: - Recently Added Detail View
struct RecentlyAddedSeriesDetailView: View {
    let playlist: Playlist
    let items: [DBSeries]

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private var wrapped: [SeriesWithCategory] {
        items.map { SeriesWithCategory(series: $0, categoryName: "") }
    }

    private var displayItems: [SeriesWithCategory] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return wrapped }
        return wrapped.filter { CatalogTextSearch.matches(search: q, text: $0.series.name) }
    }

    var body: some View {
        SeriesCategoryContent(playlist: playlist, items: displayItems)
            .navigationTitle(L("recently_added.title"))
            
            .macSearchable(text: $searchText, prompt: L("series.search_placeholder"))
            .onChange(of: searchText) { _, new in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { debouncedQuery = new }
                }
            }
            .onDisappear { debounceTask?.cancel(); debounceTask = nil }
    }
}

// MARK: - Category shelf
private enum SeriesCategoryShelf {
    static let prefetchHeadCount = 32
}

struct SeriesCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [SeriesWithCategory]
    var isStreamsLoading: Bool = false

    static func == (lhs: SeriesCategoryShelfRow, rhs: SeriesCategoryShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.category == rhs.category &&
        lhs.items == rhs.items &&
        lhs.isStreamsLoading == rhs.isStreamsLoading
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.sidebarCategorySelector) private var sidebarCategorySelector

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                categoryHeader
                Spacer()
            }
            .padding(.horizontal, 16)

            if items.isEmpty {
                if isStreamsLoading {
                    Color.clear.frame(height: posterMetrics.shelfRowTotalHeight)
                } else {
                    Text(L("series.empty.no_in_category"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                PagedHorizontalShelf(
                    items: items,
                    itemWidth: posterMetrics.shelfPosterWidth,
                    itemSpacing: 14,
                    horizontalPadding: 16
                ) { item in
                    seriesCategoryCardLink(item: item)
                }
                .frame(height: posterMetrics.shelfRowTotalHeight)
                .onAppear {
                    prefetchCovers(from: items)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func seriesCategoryCardLink(item: SeriesWithCategory) -> some View {
        let card = SeriesCard(
            playlistId: playlist.id,
            stream: item.series,
            posterWidth: posterMetrics.shelfPosterWidth,
            posterHeight: posterMetrics.shelfPosterHeight,
            imageLoadProfile: .shelf
        )
        if let selector = sidebarCategorySelector {
            Button {
                selector.navigate(.item(playlist.id, .series, category.id, String(item.series.seriesId)))
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                SeriesDetailView(playlist: playlist, series: item.series)
                    .trackDetailDepth()
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    private func prefetchCovers(from list: [SeriesWithCategory]) {
        let urls = list.prefix(SeriesCategoryShelf.prefetchHeadCount)
            .compactMap { $0.series.cover }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics, isShelf: true)
    }

    @ViewBuilder
    private var categoryHeader: some View {
        let label = HStack(spacing: 6) {
            Text(category.name)
                .font(.headline)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)

        if let selector = sidebarCategorySelector {
            Button {
                selector.select(.series, category.id)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                SeriesCategoryDetailView(playlist: playlist, category: category)
                    .trackDetailDepth()
            } label: {
                label
            }
        }
    }
}

struct SeriesCard: View {
    let playlistId: UUID
    let stream: DBSeries
    var categoryName: String? = nil
    var posterWidth: CGFloat = 160
    var posterHeight: CGFloat = 240
    var imageLoadProfile: ImageLoadProfile = .standard
    /// Kart başına @Query açmak yerine üst view'dan geçilir (nil = progress bar gizli)
    var watchProgress: Double? = nil

    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                CachedImage(
                    url: stream.cover.flatMap { URL(string: $0) },
                    width: posterWidth,
                    height: posterHeight,
                    contentMode: SwiftUI.ContentMode.fill,
                    iconName: "play.tv",
                    loadProfile: imageLoadProfile
                )

                if let progress = watchProgress, progress > 0 {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 4)
                        .frame(width: posterWidth * progress)
                        .frame(maxWidth: posterWidth, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(2)
                        .padding(.bottom, 2)
                        .padding(.horizontal, 4)
                }

                PosterRatingBadge(rating: stream.rating)
                    .padding(6)
            }

            Text(stream.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: posterWidth)
                .foregroundColor(.primary)

            if let catName = categoryName {
                Text(catName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: posterWidth)
            }
        }
    }
}

// MARK: - Category Detail View
struct SeriesCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [SeriesWithCategory] = []

    var body: some View {
        SeriesCategoryContent(playlist: playlist, items: displayItems)
            .navigationTitle(category.name)
            
            .macSearchable(text: $searchText, prompt: L("series.search_placeholder"))
            .onChange(of: searchText) { _, new in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { debouncedQuery = new }
                }
            }
            .onDisappear { debounceTask?.cancel(); debounceTask = nil }
            .task(id: debouncedQuery) { await recomputeItems() }
            .task(id: contentStore.streamsLoaded) { await recomputeItems() }
    }

    private func recomputeItems() async {
        guard playlist.id == contentStore.activePlaylistId else { displayItems = []; return }
        let base = contentStore.seriesItemsByCategoryId[category.id] ?? []
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { displayItems = base; return }
        let result = await Task.detached(priority: .userInitiated) {
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.series.name) }
            return CatalogTextSearch.sortSeriesByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }
}

struct SeriesCategoryContent: View {
    let playlist: Playlist
    let items: [SeriesWithCategory]

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.sidebarCategorySelector) private var sidebarCategorySelector
    @Query<WatchProgressMapRequest> private var progressMap: [String: Double]

    init(playlist: Playlist, items: [SeriesWithCategory]) {
        self.playlist = playlist
        self.items = items
        _progressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "series"), in: \.appDatabase)
    }

    private var categoryGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterMetrics.categoryGridPosterWidth), spacing: posterMetrics.gridSpacing)]
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "play.tv")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("series.empty.no_series"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: categoryGridColumns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(items) { item in
                            seriesGridCardLink(item: item)
                        }
                    }
                    .padding()
                }
                .onChange(of: items) { _, newValue in
                    let urls = newValue.compactMap { $0.series.cover }.compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
                .onAppear {
                    let urls = items.compactMap { $0.series.cover }.compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
            }
        }
    }

    @ViewBuilder
    private func seriesGridCardLink(item: SeriesWithCategory) -> some View {
        let card = SeriesCard(
            playlistId: playlist.id,
            stream: item.series,
            posterWidth: posterMetrics.categoryGridPosterWidth,
            posterHeight: posterMetrics.categoryGridPosterHeight,
            imageLoadProfile: .grid,
            watchProgress: progressMap[String(item.series.seriesId)]
        )
        if let selector = sidebarCategorySelector {
            Button {
                let catId = item.series.categoryId ?? ""
                selector.navigate(.item(playlist.id, .series, catId, String(item.series.seriesId)))
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                SeriesDetailView(playlist: playlist, series: item.series)
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Series Detail View (Lazy Loading Seasons)
struct SeriesDetailView: View {
    let playlist: Playlist
    var series: DBSeries

    @Environment(\.posterMetrics) private var posterMetrics
    @ObservedObject private var playerOverlay: PlayerOverlayController = .shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSeasonId: String?
    @State private var enlargedImage: IdentifiableURL?
    @State private var showNavTitle: Bool = false
    @State private var selectedEpisode: (DBEpisode, DBWatchHistory?)?
    @State private var episodeNavPrevious: DBEpisode?
    @State private var episodeNavNext: DBEpisode?
    @Query<SeriesByIDRequest> private var seriesRecord: DBSeries?
    @Query<SeasonsRequest> private var seasons: [DBSeason]
    @Query<IsFavoriteRequest> private var isFavorite: Bool
    @Query<LatestSeriesWatchHistoryRequest> private var watchHistory: DBWatchHistory?

    init(playlist: Playlist, series: DBSeries) {
        self.playlist = playlist
        self.series = series
        _seriesRecord = Query(SeriesByIDRequest(seriesId: series.seriesId, playlistId: playlist.id), in: \.appDatabase)
        _seasons = Query(SeasonsRequest(seriesId: series.seriesId, playlistId: playlist.id), in: \.appDatabase)
        _isFavorite = Query(IsFavoriteRequest(streamId: series.seriesId, playlistId: playlist.id, type: "series"), in: \.appDatabase)
        _watchHistory = Query(LatestSeriesWatchHistoryRequest(seriesId: String(series.seriesId), playlistId: playlist.id), in: \.appDatabase)
    }

    private var currentSeries: DBSeries {
        seriesRecord ?? series
    }

    private var heroConfig: DetailHeroConfig {
        DetailHeroConfig(
            title: currentSeries.name,
            backdropURL: currentSeries.backdropPath.flatMap { URL(string: $0) },
            posterURL: currentSeries.cover.flatMap { URL(string: $0) },
            year: DetailFormatting.year(from: currentSeries.releaseDate),
            runtime: DetailFormatting.seriesRuntime(currentSeries.episodeRunTime),
            rating10: currentSeries.rating5Based.map { $0 * 2 },
            ratingText: currentSeries.rating,
            posterIconName: "play.tv",
            backdropIconName: "play.tv"
        )
    }

    private var trailerURL: URL? {
        guard let raw = currentSeries.youtubeTrailer?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        if raw.lowercased().hasPrefix("http") { return URL(string: raw) }
        return URL(string: "https://www.youtube.com/watch?v=\(raw)")
    }

    private var hasResume: Bool {
        guard let h = watchHistory else { return false }
        return h.lastTimeMs > 5000
    }

    private var resumeProgress: Double? {
        guard let h = watchHistory, h.durationMs > 0 else { return nil }
        let p = Double(h.lastTimeMs) / Double(h.durationMs)
        return (p > 0.02 && p < 0.98) ? p : nil
    }

    private var resumeSubtitle: String? {
        guard let h = watchHistory, hasResume else { return nil }
        let time = DetailFormatting.formatMs(h.lastTimeMs)
        return h.title.isEmpty ? time : "\(h.title) · \(time)"
    }

    var body: some View {
        Group {
            if isLoading && !currentSeries.seasonsLoaded {
                ProgressView(L("detail.loading_series"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                contentScroll
            }
        }
        .navigationTitle(showNavTitle ? currentSeries.name : "")
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await toggleFavorite() } }) {
                    Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: isFavorite ? "star.fill" : "star")
                }
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
        .sheet(item: $enlargedImage) { wrapper in
            FullscreenImageViewer(url: wrapper.url)
        }
        .task {
            if !currentSeries.seasonsLoaded {
                await fetchSeriesInfo()
            }
        }
    }

    private func presentEpisodeOverlay(ep: DBEpisode, history: DBWatchHistory?) {
        Task {
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(episode: playlist.id, episodeId: ep.episodeId ?? ep.id)
            )
            await MainActor.run {
                presentEpisodeOverlay(ep: ep, history: history, localOverrideURL: localURL)
            }
        }
    }

    private func presentEpisodeOverlay(ep: DBEpisode, history: DBWatchHistory?, localOverrideURL: URL?) {
        let remoteURL = PlaybackURLBuilder(playlist: playlist).seriesURL(
            streamId: ep.episodeId ?? ep.id, containerExtension: ep.containerExtension
        )
        guard let url = localOverrideURL ?? remoteURL else { return }
        let cover = ep.cover.flatMap { URL(string: $0) } ?? currentSeries.cover.flatMap { URL(string: $0) }
        playerOverlay.present(onDismiss: { selectedEpisode = nil }, skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
            PlayerView(
                url: url,
                title: ep.title ?? L("detail.episode_fallback"),
                subtitle: currentSeries.name,
                artworkURL: cover,
                isLiveStream: false,
                playlistId: playlist.id,
                streamId: ep.episodeId ?? ep.id,
                type: "series",
                seriesId: String(currentSeries.seriesId),
                resumeTimeMs: history?.lastTimeMs,
                containerExtension: ep.containerExtension,
                canGoToPreviousEpisode: episodeNavPrevious != nil,
                canGoToNextEpisode: episodeNavNext != nil,
                onPreviousEpisode: { selectAdjacentEpisode(goBack: true) },
                onNextEpisode: { selectAdjacentEpisode(goBack: false) },
                onNavigateToDetail: { _, _ in }
            )
            .task(id: ep.id) {
                await loadEpisodeNeighbors(for: ep)
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Text(L("common.error"))
                .font(.headline)
            Text(error)
                .foregroundStyle(Color(NSColor.systemRed))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(L("common.try_again")) {
                Task { await fetchSeriesInfo() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHero(config: heroConfig, heroHeight: 380) { url in
                    enlargedImage = IdentifiableURL(url: url)
                }

                GenreChipRow(genres: DetailFormatting.genreList(currentSeries.genre))

                DetailActionBar(
                    primaryTitle: hasResume ? L("detail.resume") : L("detail.watch"),
                    primarySubtitle: resumeSubtitle,
                    primaryIcon: hasResume ? "play.circle.fill" : "play.fill",
                    progress: resumeProgress,
                    onPrimary: {
                        if hasResume { resumeLatestEpisode() } else { playFirstEpisode() }
                    },
                    trailerURL: trailerURL
                )

                if let plot = currentSeries.plot?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
                    DetailPlotBlock(plot: plot)
                        .padding(.top, 4)
                }

                if let director = currentSeries.director?.trimmingCharacters(in: .whitespacesAndNewlines), !director.isEmpty {
                    DetailInfoTextBlock(label: L("movie.director"), value: director)
                }

                if let cast = currentSeries.cast?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty {
                    DetailInfoTextBlock(label: "Oyuncular", value: cast, lineLimit: 3)
                }

                seasonsSection
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        // onScrollGeometryChange macOS 15+; macOS 14 hedefinde devre dışı.
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var seasonsSection: some View {
        if seasons.isEmpty {
            Text(currentSeries.seasonsLoaded ? L("series.no_seasons_info") : L("series.loading_seasons"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("series.seasons"))
                        .font(.title3.weight(.bold))
                    Spacer()
                    if let sid = selectedSeasonId,
                       let s = seasons.first(where: { $0.id == sid }),
                       let count = s.episodeCount {
                        Text(L("detail.episode_count_plural", count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)

                DetailSeasonTabBar(seasons: seasons, selectedId: $selectedSeasonId)
                    .onAppear {
                        prefetchSeasonCovers(seasons)
                        if selectedSeasonId == nil {
                            Task { selectedSeasonId = await resolveInitialSeasonId(from: seasons) }
                        }
                    }
                    .onChange(of: seasons) { _, newSeasons in
                        if selectedSeasonId == nil {
                            Task { selectedSeasonId = await resolveInitialSeasonId(from: newSeasons) }
                        }
                    }

                if let sid = selectedSeasonId {
                    if let season = seasons.first(where: { $0.id == sid }),
                       let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !overview.isEmpty {
                        Text(overview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    EpisodesPanel(
                        seasonId: sid,
                        playlist: playlist,
                        seriesId: String(currentSeries.seriesId),
                        seriesName: currentSeries.name,
                        seriesCover: currentSeries.cover
                    ) { ep, history in
                        selectedEpisode = (ep, history)
                        presentEpisodeOverlay(ep: ep, history: history)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func resumeLatestEpisode() {
        guard let history = watchHistory else { return }
        Task {
            if let ep = try? await AppDatabase.shared.read({ db in
                try DBEpisode.filter(Column("episodeId") == history.streamId || Column("id") == history.streamId).fetchOne(db)
            }) {
                await MainActor.run {
                    selectedEpisode = (ep, history)
                    presentEpisodeOverlay(ep: ep, history: history)
                }
            }
        }
    }

    private func playFirstEpisode() {
        Task {
            guard let firstSeasonId = seasons.first?.id else { return }
            if let first = try? await AppDatabase.shared.read({ db in
                try DBEpisode
                    .filter(Column("seasonId") == firstSeasonId)
                    .order(Column("episodeNum"))
                    .fetchOne(db)
            }) {
                await MainActor.run {
                    selectedEpisode = (first, nil)
                    presentEpisodeOverlay(ep: first, history: nil)
                }
            }
        }
    }

    private func prefetchSeasonCovers(_ list: [DBSeason]) {
        let urls = list.compactMap(\.cover).compactMap { URL(string: $0) }
        ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
    }

    /// En son izlenen bölümün sezonunu döner; izlenmiş bölüm yoksa ilk sezonu döner.
    private func resolveInitialSeasonId(from seasons: [DBSeason]) async -> String? {
        guard let history = watchHistory else {
            return seasons.first?.id
        }
        let streamId = history.streamId
        if let episode = try? await AppDatabase.shared.read({ db in
            try DBEpisode
                .filter(Column("episodeId") == streamId || Column("id") == streamId)
                .fetchOne(db)
        }), seasons.contains(where: { $0.id == episode.seasonId }) {
            return episode.seasonId
        }
        return seasons.first?.id
    }

    private func loadEpisodeNeighbors(for ep: DBEpisode) async {
        let playId = ep.episodeId ?? ep.id
        let ctx = try? await AppDatabase.shared.read { db in
            try SeriesPlaybackOrdering.navigationContext(
                playlistId: playlist.id,
                playbackStreamId: playId,
                seriesIdHint: String(currentSeries.seriesId),
                db: db
            )
        }
        await MainActor.run {
            let oldPrev = episodeNavPrevious
            let oldNext = episodeNavNext
            episodeNavPrevious = ctx?.previous
            episodeNavNext = ctx?.next
            let neighborsChanged =
                oldPrev?.id != episodeNavPrevious?.id || oldNext?.id != episodeNavNext?.id
            if neighborsChanged,
               let sel = selectedEpisode,
               (sel.0.episodeId ?? sel.0.id) == playId
            {
                presentEpisodeOverlay(ep: sel.0, history: sel.1)
            }
        }
    }

    private func selectAdjacentEpisode(goBack: Bool) {
        let target = goBack ? episodeNavPrevious : episodeNavNext
        guard let ep = target else { return }
        Task {
            let sid = ep.episodeId ?? ep.id
            let hist: DBWatchHistory? = try? await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(
                        Column("streamId") == sid && Column("playlistId") == playlist.id && Column("type") == "series"
                    )
                    .fetchOne(db)
            }
            await MainActor.run {
                selectedEpisode = (ep, hist)
                presentEpisodeOverlay(ep: ep, history: hist)
            }
        }
    }

    /// Sezon + bölüm yüklemesi `SeriesSeasonLoader`'a delege edilir — aynı mantığı sidebar lazy
    /// expansion da kullanıyor. View tarafında sadece UI state (isLoading/errorMessage) yönetilir.
    private func fetchSeriesInfo() async {
        isLoading = true
        errorMessage = nil
        do {
            try await SeriesSeasonLoader.shared.ensureLoaded(series: series, playlist: playlist)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func toggleFavorite() async {
        do {
            try await AppDatabase.shared.write { db in
                if isFavorite {
                    try DBFavorite
                        .filter(Column("streamId") == series.seriesId && Column("playlistId") == playlist.id && Column("type") == "series")
                        .deleteAll(db)
                } else {
                    let fav = DBFavorite(streamId: series.seriesId, playlistId: playlist.id, type: "series")
                    try fav.insert(db)
                }
            }
        } catch {
            print("Failed to toggle favorite: \(error)")
        }
    }

}

/// @Query + `.id(seasonId)` ScrollView kaydırma konumunu sıfırlıyordu; sezon değişince aynı panelde abonelik yenilenir.
private final class SeasonEpisodesObserver: ObservableObject {
    @Published private(set) var episodes: [DBEpisode] = []
    private var cancellable: AnyCancellable?

    func load(seasonId: String, db: AppDatabase) {
        cancellable?.cancel()
        cancellable = EpisodesRequest(seasonId: seasonId)
            .publisher(in: db)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                self?.episodes = list
            }
    }

    deinit {
        cancellable?.cancel()
    }
}

struct EpisodesPanel: View {
    let seasonId: String
    let playlist: Playlist
    let seriesId: String
    let seriesName: String
    let seriesCover: String?
    var onEpisodeSelected: (DBEpisode, DBWatchHistory?) -> Void

    @Environment(\.appDatabase) private var appDatabase
    @Environment(\.posterMetrics) private var posterMetrics
    @StateObject private var observer = SeasonEpisodesObserver()

    var body: some View {
        Group {
            if observer.episodes.isEmpty {
                Text(L("series.no_episodes_in_season"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(observer.episodes.enumerated()), id: \.element.id) { index, episode in
                        EpisodeDetailRow(
                            playlist: playlist,
                            episode: episode,
                            seriesId: seriesId,
                            seriesName: seriesName,
                            seriesCover: seriesCover
                        ) { ep, history in
                            onEpisodeSelected(ep, history)
                        }
                        if index < observer.episodes.count - 1 {
                            Divider()
                                .padding(.leading, posterMetrics.episodeRowDividerLeading)
                        }
                    }
                }
                .onChange(of: observer.episodes) { _, newValue in
                    let urls = newValue.compactMap(\.cover).compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
                .onAppear {
                    let urls = observer.episodes.compactMap(\.cover).compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
            }
        }
        .onAppear {
            observer.load(seasonId: seasonId, db: appDatabase)
        }
        .onChange(of: seasonId) { _, newId in
            observer.load(seasonId: newId, db: appDatabase)
        }
    }
}

private struct EpisodeDetailRow: View {
    let playlist: Playlist
    let episode: DBEpisode
    let seriesId: String
    let seriesName: String
    let seriesCover: String?
    var onStreamSelected: (DBEpisode, DBWatchHistory?) -> Void

    @Environment(\.posterMetrics) private var posterMetrics
    @Query<WatchHistoryRequest> private var watchHistory: DBWatchHistory?

    init(
        playlist: Playlist,
        episode: DBEpisode,
        seriesId: String,
        seriesName: String,
        seriesCover: String?,
        onStreamSelected: @escaping (DBEpisode, DBWatchHistory?) -> Void
    ) {
        self.playlist = playlist
        self.episode = episode
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.seriesCover = seriesCover
        self.onStreamSelected = onStreamSelected
        _watchHistory = Query(WatchHistoryRequest(streamId: episode.episodeId ?? episode.id, playlistId: playlist.id, type: "series"), in: \.appDatabase)
    }

    private var remoteURL: URL? {
        PlaybackURLBuilder(playlist: playlist).seriesURL(
            streamId: episode.episodeId ?? episode.id,
            containerExtension: episode.containerExtension
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottom) {
                    CachedImage(
                        url: episode.cover.flatMap { URL(string: $0) },
                        width: posterMetrics.episodeThumbWidth,
                        height: posterMetrics.episodeThumbHeight,
                        cornerRadius: 8,
                        contentMode: .fill,
                        iconName: "play.rectangle.fill",
                        loadProfile: .grid
                    )
                    
                    if let history = watchHistory, history.durationMs > 0 {
                        let progress = Double(history.lastTimeMs) / Double(history.durationMs)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 3)
                            .frame(width: posterMetrics.episodeThumbWidth * min(max(progress, 0), 1))
                            .frame(maxWidth: posterMetrics.episodeThumbWidth, alignment: .leading)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(1.5)
                            .padding(.bottom, 2)
                            .padding(.horizontal, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(episodeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    FlowMetaRow(episode: episode)

                    if let history = watchHistory, history.durationMs > 0 {
                        let progress = Double(history.lastTimeMs) / Double(history.durationMs)
                        if progress >= 0.95 {
                            Label(L("detail.watched"), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            let remainingMs = history.durationMs - history.lastTimeMs
                            Label(L("detail.remaining_format", formatWatchMs(remainingMs)), systemImage: "play.circle")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .labelStyle(.titleAndIcon)
                        }
                    }

                    if let plot = episode.info?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
                        Text(plot)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onStreamSelected(episode, watchHistory)
                }

                if let remoteURL {
                    DownloadButton(
                        id: DownloadManager.idFor(episode: playlist.id, episodeId: episode.episodeId ?? episode.id),
                        playlistId: playlist.id,
                        streamId: episode.episodeId ?? episode.id,
                        type: "episode",
                        title: episodeTitle,
                        secondaryTitle: seriesName,
                        imageURL: episode.cover ?? seriesCover,
                        remoteURL: remoteURL,
                        containerExtension: episode.containerExtension,
                        seriesId: seriesId,
                        episodeNumber: episode.episodeNum,
                        compact: true
                    )
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var episodeTitle: String {
        let num = episode.episodeNum.map { "\($0). " } ?? ""
        let raw = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = raw.isEmpty ? L("detail.episode_fallback") : raw
        return "\(num)\(title)"
    }

    private func formatWatchMs(_ ms: Int) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}


private struct FlowMetaRow: View {
    let episode: DBEpisode

    var body: some View {
        HStack(spacing: 12) {
            if let d = episode.duration?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                Label(d, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if ContentRating.displayText(episode.rating) != nil {
                RatingLabel(rating: episode.rating, style: .compact)
            }
        }
    }
}
