import SwiftUI
import Foundation
import Combine
import GRDB
import GRDBQuery

// MARK: - Browse logic

/// The parts of the series browse screens that are plain functions of the catalog.
/// Stateless and nonisolated: the scans run in detached tasks.
nonisolated enum SeriesBrowse {
    /// How many series the Recently Added shelf and its list hold.
    static let recentLimit = 20

    /// The Recently Added shelf: the store's candidates (newest first) without the series
    /// of categories the home does not show.
    static func recentShelf(
        from candidates: [DBSeries],
        visibleCategoryIds: Set<String>,
        limit: Int = recentLimit
    ) -> [DBSeries] {
        guard limit > 0 else { return [] }
        var shelf: [DBSeries] = []
        for series in candidates where visibleCategoryIds.contains(series.categoryId ?? "") {
            shelf.append(series)
            if shelf.count == limit { break }
        }
        return shelf
    }

    /// Whether `recentShelf` may be missing series. The candidate list is capped, so when
    /// it is full and hidden categories took most of it, older series of visible
    /// categories never got in. Only then is a pass over the whole catalog worth its cost.
    static func recentShelfNeedsCatalogPass(
        shelfCount: Int,
        candidateCount: Int,
        limit: Int = recentLimit,
        candidateLimit: Int = PlaylistContentStore.recentCandidateLimit
    ) -> Bool {
        shelfCount < limit && candidateCount >= candidateLimit
    }

    /// `recentShelf` from the whole catalog, by the rules the store applies to its
    /// candidates: a numeric `lastModified`, newest first, ties in catalog order.
    static func recentShelfFromCatalog(
        _ items: [SeriesWithCategory],
        visibleCategoryIds: Set<String>,
        limit: Int = recentLimit
    ) -> [DBSeries] {
        let newest = PlaylistContentStore.newestIndices(count: items.count, limit: limit) { index in
            let series = items[index].series
            guard visibleCategoryIds.contains(series.categoryId ?? "") else { return nil }
            return series.lastModified.flatMap { Int($0) }
        }
        return newest.map { items[$0].series }
    }

    /// The home's shelves for a search.
    nonisolated struct ShelfMatches: Sendable {
        let categories: [DBCategory]
        let itemsByCategory: [String: [SeriesWithCategory]]
    }

    /// Filters the shelves by a search text. A category whose name matches keeps all its
    /// series; any other category keeps the series that match and is dropped when none
    /// does. Order is untouched. Returns nil once the task is cancelled.
    static func shelves(
        matching search: String,
        categories: [DBCategory],
        itemsByCategory: [String: [SeriesWithCategory]]
    ) -> ShelfMatches? {
        let query = CatalogTextSearch.Query(search)
        var matched: [DBCategory] = []
        var matchedItems: [String: [SeriesWithCategory]] = [:]
        for category in categories {
            if Task.isCancelled { return nil }
            let items = itemsByCategory[category.id] ?? []
            if query.matches(category.name) {
                matched.append(category)
                matchedItems[category.id] = items
                continue
            }
            let hits = items.filter { query.matches($0.series.name) }
            if !hits.isEmpty {
                matched.append(category)
                matchedItems[category.id] = hits
            }
        }
        return ShelfMatches(categories: matched, itemsByCategory: matchedItems)
    }

    /// The cover prefetch a shelf row has queued: what it passed to `ListImagePrefetch`,
    /// so the stop can name exactly the requests the start made.
    nonisolated struct HeadPrefetch: Equatable, Sendable {
        var urls: [URL]
        var width: CGFloat
        var height: CGFloat
    }

    /// What to stop and what to start when a row's prefetch moves from `old` to `new`
    /// (nil = nothing queued). Covers in both heads are left alone: stopping and starting
    /// them again would cancel a download that is still wanted. A size change rebuilds
    /// every request, because the decode size is part of the cache key.
    static func prefetchChange(
        from old: HeadPrefetch?,
        to new: HeadPrefetch?
    ) -> (stop: HeadPrefetch?, start: HeadPrefetch?) {
        guard old != new else { return (nil, nil) }
        guard let old, let new, old.width == new.width, old.height == new.height else {
            return (old, new)
        }
        let kept = Set(old.urls).intersection(new.urls)
        var stop = old
        stop.urls.removeAll { kept.contains($0) }
        var start = new
        start.urls.removeAll { kept.contains($0) }
        return (stop.urls.isEmpty ? nil : stop, start.urls.isEmpty ? nil : start)
    }
}

struct SeriesView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay

    @State private var pendingSeriesDetail: DBSeries?

    private var pickerEntries: [CategoryPickerSheet.Entry] {
        contentStore.seriesCategories.map { cat in
            CategoryPickerSheet.Entry(
                id: cat.id,
                name: cat.name,
                count: contentStore.seriesItemsByCategoryId[cat.id]?.count ?? 0
            )
        }
    }

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    /// Everything the async part of this screen depends on. One task is keyed on it, so
    /// a change of any input runs the work once and a change of none runs nothing.
    private nonisolated struct ShelfKey: Equatable {
        /// Trimmed; empty means "no search".
        let query: String
        let streamsLoaded: Bool
        let revision: Int
        let hiddenVersion: Int
        let playlistId: UUID
        let activePlaylistId: UUID?
    }

    /// Shelves of a search, with what the catalog looked like when they were filtered.
    private struct SearchShelves {
        let categories: [DBCategory]
        let itemsByCategory: [String: [SeriesWithCategory]]
        let streamsLoaded: Bool
    }

    /// Recently Added from a pass over the whole catalog, with the inputs it was made for.
    private struct CatalogRecents {
        let revision: Int
        let hiddenVersion: Int
        let playlistId: UUID
        let items: [DBSeries]

        func isCurrent(for key: ShelfKey) -> Bool {
            revision == key.revision && hiddenVersion == key.hiddenVersion && playlistId == key.playlistId
        }
    }

    /// What one body pass draws.
    private struct Shelves {
        var categories: [DBCategory] = []
        var itemsByCategory: [String: [SeriesWithCategory]] = [:]
        /// The series are still being read: a shelf without any shows a placeholder
        /// instead of saying that the category is empty.
        var isLoading = false
        var recents: [DBSeries] = []
        var isRecentsLoading = false
    }

    // Without a search the shelves are read from the store in `body`, never copied into
    // state: a copy has to be refreshed by a task, and every store change that the task
    // was not keyed on (the categories landing before the streams, a pull-to-refresh)
    // left it stale. Only what needs work off the main actor is state.
    @State private var searchShelves: SearchShelves?
    @State private var catalogRecents: CatalogRecents?
    /// The key the state above was last brought up to date for. `.task` starts again on
    /// every appearance; with an unchanged key there is nothing to do.
    @State private var appliedKey: ShelfKey?

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    private var shelfKey: ShelfKey {
        ShelfKey(
            query: debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines),
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.seriesRevision,
            hiddenVersion: hiddenStore.version,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    /// The store's "streams loaded" flag is down, and not because the load failed.
    private var isCatalogLoading: Bool {
        !contentStore.streamsLoaded && contentStore.loadError == nil
    }

    private func currentShelves(for key: ShelfKey) -> Shelves {
        guard key.playlistId == key.activePlaylistId else { return Shelves() }

        // Until the first result of a search arrives the unfiltered shelves stay up.
        if !key.query.isEmpty, let search = searchShelves {
            return Shelves(
                categories: search.categories,
                itemsByCategory: search.itemsByCategory,
                isLoading: !search.streamsLoaded && contentStore.loadError == nil
            )
        }

        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")
        let allCategories = contentStore.seriesCategories
        var result = Shelves(
            categories: hidden.isEmpty ? allCategories : allCategories.filter { !hidden.contains($0.id) },
            itemsByCategory: contentStore.seriesItemsByCategoryId,
            isLoading: isCatalogLoading
        )
        guard key.query.isEmpty else { return result }

        let candidates = contentStore.recentSeriesCandidates
        let shelf = SeriesBrowse.recentShelf(
            from: candidates,
            visibleCategoryIds: Set(result.categories.map(\.id))
        )
        if SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: shelf.count, candidateCount: candidates.count) {
            if let fromCatalog = catalogRecents, fromCatalog.isCurrent(for: key) {
                result.recents = fromCatalog.items
            } else {
                // The catalog pass is on its way. What the candidates gave is the head
                // of its result, so the shelf only grows at its end.
                result.recents = shelf
                result.isRecentsLoading = shelf.isEmpty
            }
        } else {
            result.recents = shelf
            // The shelf keeps its place while the series are read, so that it fills in
            // like the category shelves instead of pushing them down afterwards.
            result.isRecentsLoading = shelf.isEmpty && isCatalogLoading
        }
        return result
    }

    var body: some View {
        let key = shelfKey
        let shelves = currentShelves(for: key)
        // A load that failed before the series were in has nothing to show under the
        // category titles; a reload that failed leaves the previous catalog in place.
        let loadFailed = contentStore.loadError != nil && !contentStore.streamsLoaded
        Group {
            if shelves.categories.isEmpty || (loadFailed && key.query.isEmpty) {
                if key.playlistId != key.activePlaylistId || contentStore.isLoading {
                    loadingPlaceholder
                } else if let loadError = contentStore.loadError, key.query.isEmpty {
                    CatalogLoadErrorView(message: loadError) {
                        Task { await contentStore.loadPlaylist(playlist) }
                    }
                } else if isCatalogLoading {
                    // The category list is not final before the series are in (the
                    // "uncategorized" shelf only appears with them), so "nothing here"
                    // cannot be said yet.
                    loadingPlaceholder
                } else {
                    CatalogEmptyView(key.query.isEmpty ? .noCategories(systemImage: "play.tv") : .noSearchResults)
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

                        if shelves.isRecentsLoading || !shelves.recents.isEmpty {
                            RecentlyAddedSeriesShelf(
                                playlist: playlist,
                                items: shelves.recents,
                                isLoading: shelves.isRecentsLoading
                            )
                            .equatable()
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(shelves.categories) { category in
                                let items = shelves.itemsByCategory[category.id] ?? []
                                SeriesCategoryShelfRow(
                                    playlist: playlist,
                                    category: category,
                                    items: items,
                                    // Only a shelf without series looks at the flag; passing
                                    // it to the others would re-render them when it flips.
                                    isStreamsLoading: items.isEmpty && shelves.isLoading
                                )
                                .equatable()
                                .id(category.id)
                            }
                        }
                    }
                    .refreshable {
                        // Bağımsız Task: refreshable iptali isteklere yayılmasın (bkz. LiveStreamsView).
                        let work = Task { await contentStore.refreshFromNetwork(playlist: playlist, only: .series) }
                        await work.value
                    }
                    .onChange(of: pendingScrollTarget) { _, target in
                        guard let target else { return }
                        // A jump, not a scroll: an animated one builds every shelf it
                        // passes, each with its own image prefetch.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AllSeriesView(playlist: playlist)
                } label: {
                    Label(L("browse.all_series"), systemImage: "square.grid.2x2")
                }
                .disabled(contentStore.seriesItems.isEmpty)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Cleared when the picker opens, so that choosing the category that
                    // was chosen last time is a change again.
                    pendingScrollTarget = nil
                    showingCategoryPicker = true
                } label: {
                    Label(L("list.jump_to_category"), systemImage: "list.bullet.indent")
                }
                .disabled(contentStore.seriesCategories.isEmpty)
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
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L("series.search_placeholder")
        )
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
        .task(id: key) { await recompute(for: key) }
        .transaction { $0.animation = nil }
        .navigationDestination(item: $pendingSeriesDetail) { series in
            SeriesDetailView(playlist: playlist, series: series)
        }
        .onPlayerDetailRequest(from: playerOverlay) { request in
            guard case .series(let series) = request else { return false }
            showDetail(series)
            return true
        }
    }

    /// Pushes the page of `series` unless the page pushed last is already that series'.
    private func showDetail(_ series: DBSeries) {
        guard pendingSeriesDetail?.seriesId != series.seriesId else { return }
        pendingSeriesDetail = series
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(contentStore.loadingMessage ?? L("series.empty.preparing"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        playerOverlay.injected?.dismiss()
                        showDetail(series)
                    }
                }
            }
        }
        if item.type == "series" {
            playerOverlay.injected?.present(skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
                HistorySeriesPlayerShell(playlist: playlist, history: item, url: url, onNavigateToDetail: navigateToDetail)
            }
        } else {
            playerOverlay.injected?.present(skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
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
                    // Non-episode fallback: a finished item starts over instead of
                    // reopening in its last seconds.
                    resumeTimeMs: item.resumePositionMs(as: .film),
                    containerExtension: item.containerExtension,
                    onNavigateToDetail: navigateToDetail
                )
            }
        }
    }

    /// Brings the search shelves and the catalog-wide Recently Added up to date for `key`.
    /// The key is marked as applied only once its result is stored: a run that was
    /// cancelled on the way must be repeated when the screen comes back.
    private func recompute(for key: ShelfKey) async {
        guard key != appliedKey else { return }
        guard key.playlistId == key.activePlaylistId else {
            if searchShelves != nil { searchShelves = nil }
            if catalogRecents != nil { catalogRecents = nil }
            appliedKey = key
            return
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")
        let categories = contentStore.seriesCategories.filter { !hidden.contains($0.id) }

        if key.query.isEmpty {
            if searchShelves != nil { searchShelves = nil }
            guard await loadCatalogRecentsIfNeeded(for: key, visibleCategories: categories) else { return }
            appliedKey = key
            return
        }

        let itemsByCategory = contentStore.seriesItemsByCategoryId
        let search = key.query
        let matches = await CatalogTextSearch.detached {
            SeriesBrowse.shelves(matching: search, categories: categories, itemsByCategory: itemsByCategory)
        }
        guard !Task.isCancelled, let matches else { return }
        searchShelves = SearchShelves(
            categories: matches.categories,
            itemsByCategory: matches.itemsByCategory,
            streamsLoaded: key.streamsLoaded
        )
        appliedKey = key
    }

    /// Runs the catalog pass for Recently Added when the store's candidates cannot fill
    /// the shelf (see `SeriesBrowse.recentShelfNeedsCatalogPass`), unless its result for
    /// this catalog and this set of hidden categories is already there. Returns false
    /// when the task was cancelled before the result could be stored.
    private func loadCatalogRecentsIfNeeded(for key: ShelfKey, visibleCategories: [DBCategory]) async -> Bool {
        let candidates = contentStore.recentSeriesCandidates
        let visibleIds = Set(visibleCategories.map(\.id))
        let shelf = SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: visibleIds)
        guard SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: shelf.count, candidateCount: candidates.count) else {
            if catalogRecents != nil { catalogRecents = nil }
            return true
        }
        if let current = catalogRecents, current.isCurrent(for: key) { return true }

        let items = contentStore.seriesItems
        let recents = await CatalogTextSearch.detached {
            SeriesBrowse.recentShelfFromCatalog(items, visibleCategoryIds: visibleIds)
        }
        guard !Task.isCancelled else { return false }
        catalogRecents = CatalogRecents(
            revision: key.revision,
            hiddenVersion: key.hiddenVersion,
            playlistId: key.playlistId,
            items: recents
        )
        return true
    }

    private func buildURL(for item: DBWatchHistory) -> URL? {
        let builder = PlaybackURLBuilder(playlist: playlist)
        // Series tab olduğu için series varsayımı
        return builder.seriesURL(streamId: item.streamId, containerExtension: item.containerExtension)
    }
}

// MARK: - Shelf placeholder

/// Stands in for the cards of a poster shelf whose series are not known yet: the same
/// outlines at the same height, so the page does not move when the cards arrive.
private struct SeriesShelfSkeleton: View {
    @Environment(\.posterMetrics) private var posterMetrics

    private static let cardCount = 8

    var body: some View {
        // A scroll view only for its clipping: a plain stack of this many cards is wider
        // than a phone and would widen the whole row with it.
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: SeriesCategoryShelf.cardSpacing) {
                ForEach(0..<Self.cardCount, id: \.self) { _ in
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .frame(width: posterMetrics.shelfPosterWidth, height: posterMetrics.shelfPosterHeight)
                        Text(verbatim: "Placeholder")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .redacted(reason: .placeholder)
                            .frame(width: posterMetrics.shelfPosterWidth)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollDisabled(true)
        .frame(height: posterMetrics.shelfRowTotalHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Recently Added shelf

struct RecentlyAddedSeriesShelf: View, Equatable {
    let playlist: Playlist
    let items: [DBSeries]
    /// The newest series are not known yet; the shelf holds its place with a placeholder.
    var isLoading: Bool = false

    static func == (lhs: RecentlyAddedSeriesShelf, rhs: RecentlyAddedSeriesShelf) -> Bool {
        lhs.playlist.id == rhs.playlist.id && lhs.items == rhs.items && lhs.isLoading == rhs.isLoading
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(L("recently_added.title")) {
                RecentlyAddedSeriesDetailView(playlist: playlist, items: items)
            }
            .disabled(items.isEmpty)

            if items.isEmpty && isLoading {
                SeriesShelfSkeleton()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: SeriesCategoryShelf.cardSpacing) {
                        ForEach(items) { series in
                            NavigationLink {
                                SeriesDetailView(playlist: playlist, series: series)
                                    .posterZoomDestination(id: series.seriesId, in: zoom)
                            } label: {
                                SeriesCard(
                                    playlistId: playlist.id,
                                    stream: series,
                                    posterWidth: posterMetrics.shelfPosterWidth,
                                    posterHeight: posterMetrics.shelfPosterHeight,
                                    imageLoadProfile: .shelf,
                                    zoomNamespace: zoom
                                )
                            }
                            .seriesCardInteractions(seriesId: series.seriesId, playlistId: playlist.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: posterMetrics.shelfRowTotalHeight)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Recently Added Detail View
struct RecentlyAddedSeriesDetailView: View {
    let playlist: Playlist
    let items: [DBSeries]

    private var wrapped: [SeriesWithCategory] {
        items.map { SeriesWithCategory(series: $0, categoryName: "") }
    }

    var body: some View {
        // A list this short has no search field, and it stays in the order its title
        // promises whatever sort is stored for the other grids.
        SeriesCategoryContent(playlist: playlist, items: wrapped, allowsSorting: false)
            .equatable()
            .navigationTitle(L("recently_added.title"))
            .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Category shelf
private enum SeriesCategoryShelf {
    /// Gap between two cards of a shelf.
    static let cardSpacing: CGFloat = 14
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
    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(category.name) {
                SeriesCategoryDetailView(playlist: playlist, category: category)
            }
            .contextMenu {
                HideCategoryMenuButton(categoryId: category.id, type: "series", playlistId: playlist.id)
            }

            if items.isEmpty {
                if isStreamsLoading {
                    SeriesShelfSkeleton()
                } else {
                    Text(L("series.empty.no_in_category"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: SeriesCategoryShelf.cardSpacing) {
                        ForEach(items) { item in
                            NavigationLink {
                                SeriesDetailView(playlist: playlist, series: item.series)
                                    .posterZoomDestination(id: item.series.seriesId, in: zoom)
                            } label: {
                                SeriesCard(
                                    playlistId: playlist.id,
                                    stream: item.series,
                                    posterWidth: posterMetrics.shelfPosterWidth,
                                    posterHeight: posterMetrics.shelfPosterHeight,
                                    imageLoadProfile: .shelf,
                                    zoomNamespace: zoom
                                )
                            }
                            .seriesCardInteractions(seriesId: item.series.seriesId, playlistId: playlist.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: posterMetrics.shelfRowTotalHeight)
                .onAppear { movePrefetch(to: headPrefetch) }
                // A shelf that was flung past must not keep downloading covers nobody
                // will see.
                .onDisappear { movePrefetch(to: nil) }
                // The row stays mounted while a search narrows it or a refresh changes its
                // first series, and gets no new onAppear for that.
                .onChange(of: headPrefetch) { _, head in
                    guard queuedPrefetch != nil else { return }
                    movePrefetch(to: head)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// The prefetch this row has queued. The stop must name the requests the start made,
    /// not a head recomputed from whatever `items` holds by then.
    @State private var queuedPrefetch: SeriesBrowse.HeadPrefetch?

    /// Covers of the cards one swipe can reach.
    private var headPrefetch: SeriesBrowse.HeadPrefetch {
        let head = ListImagePrefetch.headCount(
            itemWidth: posterMetrics.shelfPosterWidth,
            spacing: SeriesCategoryShelf.cardSpacing,
            containerWidth: UIScreen.main.bounds.width
        )
        let urls = items.prefix(head)
            .compactMap { $0.series.cover }
            .compactMap { URL(string: $0) }
        return SeriesBrowse.HeadPrefetch(
            urls: urls,
            width: posterMetrics.shelfPosterWidth,
            height: posterMetrics.shelfPosterHeight
        )
    }

    private func movePrefetch(to head: SeriesBrowse.HeadPrefetch?) {
        let change = SeriesBrowse.prefetchChange(from: queuedPrefetch, to: head)
        if let stop = change.stop {
            ListImagePrefetch.stop(
                urls: stop.urls, width: stop.width, height: stop.height,
                contentMode: .fill, loadProfile: .shelf
            )
        }
        if let start = change.start {
            ListImagePrefetch.start(
                urls: start.urls, width: start.width, height: start.height,
                contentMode: .fill, loadProfile: .shelf
            )
        }
        queuedPrefetch = head
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
    /// The namespace of the link that pushes the detail page, which zooms out of the poster.
    var zoomNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading) {
            artwork
                .cardHover(cornerRadius: BrowseMetrics.posterCornerRadius)

            Text(stream.name)
                .posterTitleStyle(width: posterWidth)

            if let catName = categoryName {
                Text(catName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: posterWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let zoomNamespace {
            poster.posterZoomSource(id: stream.seriesId, in: zoomNamespace)
        } else {
            poster
        }
    }

    private var poster: some View {
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
    }
}

extension View {
    /// Press feedback, favourite menu and test identifier of a series card's link.
    fileprivate func seriesCardInteractions(seriesId: Int, playlistId: UUID) -> some View {
        self
            .buttonStyle(.cardPress)
            .cardContextMenuShape(cornerRadius: BrowseMetrics.posterCornerRadius)
            .contextMenu {
                FavoriteMenuButton(streamId: seriesId, type: "series", playlistId: playlistId)
            }
            .accessibilityIdentifier("card.series.\(seriesId)")
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

    /// The inputs of a search in this category.
    private nonisolated struct SearchKey: Equatable {
        /// Trimmed; empty means "no search".
        let query: String
        let streamsLoaded: Bool
        let revision: Int
        let playlistId: UUID
        let activePlaylistId: UUID?
    }

    /// Ranked hits of the last search. Without a search the grid is handed the store's
    /// own array in `body`, so it has its posters in the first frame of the push.
    @State private var searchResults: [SeriesWithCategory]?
    @State private var appliedKey: SearchKey?

    private var searchKey: SearchKey {
        SearchKey(
            query: debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines),
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.seriesRevision,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    var body: some View {
        let key = searchKey
        let isActive = key.playlistId == key.activePlaylistId
        let source = isActive ? (contentStore.seriesItemsByCategoryId[category.id] ?? []) : []
        let isSearching = !key.query.isEmpty
        SeriesCategoryContent(
            playlist: playlist,
            // The hits of the previous query stay up while the next one is scanned.
            items: isSearching ? (searchResults ?? source) : source,
            isSourceLoading: !isActive
                || (!contentStore.streamsLoaded && contentStore.loadError == nil)
                || (isSearching && key != appliedKey)
        )
        .equatable()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("series.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .task(id: key) { await recompute(for: key) }
    }

    private func recompute(for key: SearchKey) async {
        guard key != appliedKey else { return }
        guard !key.query.isEmpty, key.playlistId == key.activePlaylistId else {
            searchResults = nil
            appliedKey = key
            return
        }
        let base = contentStore.seriesItemsByCategoryId[category.id] ?? []
        let search = key.query
        let ranked = await CatalogTextSearch.detached {
            CatalogTextSearch.rankedFilter(base, search: search) { $0.series.name }
        }
        // A cancelled scan returns an empty list; it must not be taken for "no hits".
        guard !Task.isCancelled else { return }
        searchResults = ranked
        appliedKey = key
    }
}

struct SeriesCategoryContent: View, Equatable {
    let playlist: Playlist
    let items: [SeriesWithCategory]
    /// The list `items` is taken from is not complete yet: the catalog is still being
    /// read, or the caller's own filter is still running. An empty grid then waits
    /// instead of saying that there are no series.
    var isSourceLoading: Bool = false
    /// Off for a list whose order is its meaning (Recently Added): the stored sort is
    /// not applied and the menu does not offer one.
    var allowsSorting: Bool = true

    /// Cheap signature compare so a parent @Published re-render doesn't force SwiftUI
    /// to re-process a huge item list. Internal @State/@Query updates still invalidate.
    static func == (lhs: SeriesCategoryContent, rhs: SeriesCategoryContent) -> Bool {
        lhs.playlist.id == rhs.playlist.id
            && lhs.items.count == rhs.items.count
            && lhs.items.first?.series.seriesId == rhs.items.first?.series.seriesId
            && lhs.items.last?.series.seriesId == rhs.items.last?.series.seriesId
            && lhs.isSourceLoading == rhs.isSourceLoading
            && lhs.allowsSorting == rhs.allowsSorting
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Query<WatchProgressMapRequest> private var progressMap: [String: Double]
    @Namespace private var zoom

    @AppStorage(SeriesSortOption.storageKey) private var sortOption: SeriesSortOption = .defaultOrder
    /// Screen-local: genres are specific to the currently shown list.
    @State private var genreFilter: Set<String> = []
    /// Sort/filter output, recomputed off the main thread on input changes. With the
    /// default order and no filter it is `items` itself (the same buffer, not a copy).
    @State private var displayItems: [SeriesWithCategory] = []
    /// Genres present in the full list, precomputed to keep the menu O(1) to build.
    @State private var genres: [String] = []
    /// Paginated render count so a huge catalog doesn't build one giant ForEach.
    @State private var visibleCount = Self.pageSize
    /// The inputs `displayItems` was computed for. `.task` starts again every time the
    /// grid re-appears (back from a detail, back from the player, a tab switch); with
    /// unchanged inputs it must leave the page count and the scroll offset alone.
    @State private var appliedKey: InputKey?
    /// The `itemsToken` `genres` was collected for.
    @State private var genresToken: Int?
    /// Written only to send the grid back to its top when its content is replaced.
    @State private var scrollPosition = ScrollPosition(idType: Never.self)

    private static let pageSize = 90

    /// Everything the grid's content depends on.
    private nonisolated struct InputKey: Equatable {
        let items: Int
        let sort: SeriesSortOption
        let genres: Set<String>

        /// Default order without a filter: the output is the input itself.
        var isIdentity: Bool { sort == .defaultOrder && genres.isEmpty }
    }

    init(
        playlist: Playlist,
        items: [SeriesWithCategory],
        isSourceLoading: Bool = false,
        allowsSorting: Bool = true
    ) {
        self.playlist = playlist
        self.items = items
        self.isSourceLoading = isSourceLoading
        self.allowsSorting = allowsSorting
        _progressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "series"), in: \.appDatabase)
    }

    private var categoryGridColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: posterMetrics.categoryGridPosterWidth),
            spacing: posterMetrics.gridSpacing,
            alignment: .top
        )]
    }

    /// Cheap O(1) change signal for `items`; avoids O(n) array equality in `.task(id:)`.
    private var itemsToken: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.series.seriesId)
        hasher.combine(items.last?.series.seriesId)
        return hasher.finalize()
    }

    private var effectiveSort: SeriesSortOption {
        allowsSorting ? sortOption : .defaultOrder
    }

    private var inputKey: InputKey {
        InputKey(items: itemsToken, sort: effectiveSort, genres: genreFilter)
    }

    private var isFilterActive: Bool {
        effectiveSort != .defaultOrder || !genreFilter.isEmpty
    }

    private func recompute(for key: InputKey) async {
        let source = items
        let isApplied = key == appliedKey
        if !isApplied, key.isIdentity {
            // Nothing to compute, so the list is swapped in this same turn instead of
            // after a hop to another thread and back.
            apply(source, for: key)
        }
        let needsSort = !isApplied && !key.isIdentity
        let needsGenres = genresToken != key.items
        guard needsSort || needsGenres else { return }

        let sort = key.sort
        let filter = key.genres
        let output = await CatalogTextSearch.detached { () -> (sorted: [SeriesWithCategory]?, genres: [String]?) in
            let sorted = needsSort ? sort.apply(to: SeriesGenre.filter(source, selection: filter)) : nil
            if Task.isCancelled { return (nil, nil) }
            // Options come from the full list so toggling one doesn't hide the others.
            return (sorted, needsGenres ? SeriesGenre.available(in: source) : nil)
        }
        // A sort that was superseded while it ran must not overwrite the newer one.
        guard !Task.isCancelled else { return }
        if let sorted = output.sorted {
            apply(sorted, for: key)
        }
        if let available = output.genres {
            genres = available
            genresToken = key.items
        }
    }

    /// Swaps the content. The new list, its first page and the top position are one
    /// state update, so the grid is never seen with the new order at the old offset.
    private func apply(_ result: [SeriesWithCategory], for key: InputKey) {
        stopPrefetch()
        displayItems = result
        visibleCount = Self.pageSize
        // The first content of a freshly pushed grid is at the top already.
        if appliedKey != nil {
            scrollPosition.scrollTo(edge: .top)
        }
        appliedKey = key
        prefetch(result)
    }

    private func loadMore(upTo total: Int) {
        guard visibleCount < total else { return }
        visibleCount = min(visibleCount + Self.pageSize, total)
    }

    var body: some View {
        let key = inputKey
        // Before anything was applied, identity inputs are drawn straight from `items`,
        // so a pushed grid has its posters in its first frame. From then on the grid
        // keeps the list that was applied last until `apply` replaces it.
        let drawsItems = appliedKey == nil && key.isIdentity
        let shown = drawsItems ? items : displayItems
        let isSettled = drawsItems || key == appliedKey
        let total = shown.count
        Group {
            if shown.isEmpty {
                if isSourceLoading || !isSettled {
                    // Not known to be empty yet.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CatalogEmptyView(.noItems(title: L("series.empty.no_series"), systemImage: "play.tv"))
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: categoryGridColumns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(Indexed(shown.prefix(visibleCount)), id: \.element.series.seriesId) { index, item in
                            NavigationLink {
                                SeriesDetailView(playlist: playlist, series: item.series)
                                    .posterZoomDestination(id: item.series.seriesId, in: zoom)
                            } label: {
                                SeriesCard(
                                    playlistId: playlist.id,
                                    stream: item.series,
                                    posterWidth: posterMetrics.categoryGridPosterWidth,
                                    posterHeight: posterMetrics.categoryGridPosterHeight,
                                    imageLoadProfile: .grid,
                                    watchProgress: progressMap[String(item.series.seriesId)],
                                    zoomNamespace: zoom
                                )
                            }
                            .seriesCardInteractions(seriesId: item.series.seriesId, playlistId: playlist.id)
                            // Load the next page while cells near the end scroll into view.
                            // Triggered from inside the lazy grid so onAppear is reliable.
                            .onAppear { if index >= visibleCount - 15 { loadMore(upTo: total) } }
                        }
                    }
                    .padding()
                }
                .scrollPosition($scrollPosition)
            }
        }
        .toolbar {
            if showsMenu {
                ToolbarItem(placement: .navigationBarTrailing) {
                    sortFilterMenu
                }
            }
        }
        .task(id: key) { await recompute(for: key) }
        .onDisappear { stopPrefetch() }
    }

    /// Without the sort picker the menu is only the genre filter, and a list without
    /// genres would open an empty menu.
    private var showsMenu: Bool {
        allowsSorting || !genres.isEmpty
    }

    private var sortFilterMenu: some View {
        Menu {
            if allowsSorting {
                Picker(L("sort.title"), selection: $sortOption) {
                    ForEach(SeriesSortOption.allCases) { option in
                        Label(L(option.titleKey), systemImage: option.systemImage).tag(option)
                    }
                }
            }

            if !genres.isEmpty {
                Section(L("filter.genre")) {
                    ForEach(genres, id: \.self) { genre in
                        Toggle(genre, isOn: genreBinding(genre))
                    }
                    // The switches leave the menu open so several genres can be ticked
                    // in one go; "Clear filter" closes it like any other action.
                    .menuActionDismissBehavior(.disabled)

                    if !genreFilter.isEmpty {
                        Button {
                            genreFilter.removeAll()
                        } label: {
                            Label(L("filter.clear"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
        } label: {
            Label(
                allowsSorting ? L("sort.title") : L("filter.title"),
                systemImage: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private func genreBinding(_ genre: String) -> Binding<Bool> {
        Binding(
            get: { genreFilter.contains(genre) },
            set: { isOn in
                if isOn {
                    genreFilter.insert(genre)
                } else {
                    genreFilter.remove(genre)
                }
            }
        )
    }

    private func headCoverURLs(of list: [SeriesWithCategory]) -> [URL] {
        list.prefix(ListImagePrefetch.maxBatch)
            .compactMap { $0.series.cover }
            .compactMap { URL(string: $0) }
    }

    private func prefetch(_ list: [SeriesWithCategory]) {
        ListImagePrefetch.start(
            urls: headCoverURLs(of: list),
            width: posterMetrics.categoryGridPosterWidth,
            height: posterMetrics.categoryGridPosterHeight,
            contentMode: .fill,
            loadProfile: .grid
        )
    }

    /// Lets go of what `prefetch` queued for the list that was applied last
    /// (`displayItems` is that list, also for identity inputs).
    private func stopPrefetch() {
        ListImagePrefetch.stop(
            urls: headCoverURLs(of: displayItems),
            width: posterMetrics.categoryGridPosterWidth,
            height: posterMetrics.categoryGridPosterHeight,
            contentMode: .fill,
            loadProfile: .grid
        )
    }
}

// MARK: - All Series (flat, sortable/filterable browse)

/// Flat grid of every series across categories. Reuses `SeriesCategoryContent`, so
/// it inherits the sort menu and genre filter for free.
struct AllSeriesView: View {
    let playlist: Playlist

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    /// The inputs of the list when it is not simply the store's.
    private nonisolated struct FilterKey: Equatable {
        /// Trimmed; empty means "no search".
        let query: String
        let streamsLoaded: Bool
        let revision: Int
        let hiddenVersion: Int
        let playlistId: UUID
        let activePlaylistId: UUID?
    }

    /// The catalog without hidden categories, narrowed and ranked by the search.
    /// Stays nil while neither applies: the grid then gets the store's own array.
    @State private var filteredItems: [SeriesWithCategory]?
    @State private var appliedKey: FilterKey?

    private var filterKey: FilterKey {
        FilterKey(
            query: debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines),
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.seriesRevision,
            hiddenVersion: hiddenStore.version,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    var body: some View {
        let key = filterKey
        let isActive = key.playlistId == key.activePlaylistId
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")
        let source = isActive ? contentStore.seriesItems : []
        // Nothing hidden and nothing typed: no copy of the catalog and no wait for one.
        let isUnfiltered = hidden.isEmpty && key.query.isEmpty
        SeriesCategoryContent(
            playlist: playlist,
            // The previous list stays up while the next one is computed. Before the
            // first one, only a catalog without hidden categories may stand in.
            items: isUnfiltered ? source : (filteredItems ?? (hidden.isEmpty ? source : [])),
            isSourceLoading: !isActive
                || (!contentStore.streamsLoaded && contentStore.loadError == nil)
                || (!isUnfiltered && key != appliedKey)
        )
        .equatable()
        .navigationTitle(L("browse.all_series"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("series.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .task(id: key) { await recompute(for: key) }
    }

    private func recompute(for key: FilterKey) async {
        guard key != appliedKey else { return }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")
        guard key.playlistId == key.activePlaylistId, !hidden.isEmpty || !key.query.isEmpty else {
            filteredItems = nil
            appliedKey = key
            return
        }
        let source = contentStore.seriesItems
        let search = key.query
        // All work off the main thread; the catalog can be very large.
        let result = await CatalogTextSearch.detached { () -> [SeriesWithCategory] in
            let base = hidden.isEmpty ? source : source.filter { !hidden.contains($0.series.categoryId ?? "") }
            if Task.isCancelled { return [] }
            // Without a search this returns `base` as it is.
            return CatalogTextSearch.rankedFilter(base, search: search) { $0.series.name }
        }
        // A cancelled scan returns an empty list; it must not be taken for "no hits".
        guard !Task.isCancelled else { return }
        filteredItems = result
        appliedKey = key
    }
}

// MARK: - Series Detail View (Lazy Loading Seasons)
struct SeriesDetailView: View {
    let playlist: Playlist
    var series: DBSeries

    /// The page's own `get_series_info` request. Once seasons exist, the stored row and
    /// the seasons query decide what is shown; this only covers the time before that.
    private enum SeasonsPhase: Equatable {
        /// Nothing requested by this page: the stored row says whether seasons are still to come.
        case idle
        case loading
        case failed(String)
        /// The catalog row is gone (a refresh dropped the series): nothing to attach seasons to.
        case missing
    }

    /// What the season selection depends on: it is looked at again when either part changes.
    private struct SeasonSelectionKey: Equatable {
        var seasonIds: [String]
        var latestStreamId: String?
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.playerOverlayController) private var playerOverlay
    @State private var seasonsPhase: SeasonsPhase = .idle
    /// Bumped by every `get_series_info` request, so that only the latest one settles `seasonsPhase`.
    @State private var seasonsRequestToken = 0
    @State private var selectedSeasonId: String?
    /// Season of the episode the series' newest history row belongs to, as last resolved.
    /// That row is what playback writes, so a change here means playback moved on.
    @State private var watchedSeasonId: String?
    @State private var enlargedImage: IdentifiableURL?
    @State private var showNavTitle: Bool = false
    /// The star's value between a tap and the database catching up with it.
    @State private var favoriteOverride: Bool?
    @State private var favoriteTapCount = 0
    /// Whether any season holds an episode; nil until read. The primary button is
    /// disabled once the seasons are stored and there is nothing to play.
    @State private var hasEpisodes: Bool?
    @Query<SeriesByIDRequest> private var seriesRecord: DBSeries?
    @Query<SeasonsRequest> private var seasons: [DBSeason]
    @Query<IsFavoriteRequest> private var isFavorite: Bool
    @Query<LatestSeriesWatchHistoryRequest> private var watchHistory: DBWatchHistory?

    init(playlist: Playlist, series: DBSeries) {
        self.playlist = playlist
        self.series = series
        // Read while the page subscribes: the first frame already has the stored row,
        // the seasons, the star and the resume state, instead of changing right after the push.
        _seriesRecord = Query(SeriesByIDRequest(seriesId: series.seriesId, playlistId: playlist.id, immediate: true), in: \.appDatabase)
        _seasons = Query(SeasonsRequest(seriesId: series.seriesId, playlistId: playlist.id, immediate: true), in: \.appDatabase)
        _isFavorite = Query(IsFavoriteRequest(streamId: series.seriesId, playlistId: playlist.id, type: "series", immediate: true), in: \.appDatabase)
        _watchHistory = Query(LatestSeriesWatchHistoryRequest(seriesId: String(series.seriesId), playlistId: playlist.id, immediate: true), in: \.appDatabase)
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

    private var showsFavorite: Bool {
        favoriteOverride ?? isFavorite
    }

    private var isPrimaryDisabled: Bool {
        !hasResume && currentSeries.seasonsLoaded && !isAwaitingSeasons && hasEpisodes == false
    }

    /// What the episode probe depends on.
    private struct EpisodeProbeKey: Equatable {
        var seasonIds: [String]
        var seasonsLoaded: Bool
    }

    var body: some View {
        // Always the page itself: everything above the seasons comes from the catalog row,
        // so loading and failure of the seasons request stay inside the seasons block.
        contentScroll
            // Constant, so the back-stack menu and VoiceOver have the name from the start.
            // What the bar shows is the principal item below.
            .navigationTitle(currentSeries.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                navigationTitleItem
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleFavorite) {
                        Image(systemName: showsFavorite ? "star.fill" : "star")
                            .foregroundColor(showsFavorite ? .yellow : .primary)
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.default, value: showsFavorite)
                    }
                    .accessibilityLabel(showsFavorite ? L("favorites.remove") : L("favorites.add"))
                    .accessibilityIdentifier("detail.favorite")
                }
            }
            .fullScreenCover(item: $enlargedImage) { wrapper in
                FullscreenImageViewer(url: wrapper.url)
            }
            // On the page rather than on the bar button, and driven by taps only: the star
            // also changes when the stored value arrives, which must not play a haptic.
            .sensoryFeedback(.impact(weight: .light), trigger: favoriteTapCount)
            .onChange(of: isFavorite) { _, stored in
                // An earlier write landing first must not flip the star back.
                if favoriteOverride == stored { favoriteOverride = nil }
            }
            .onChange(of: seasons.isEmpty) { _, isEmpty in
                // Seasons on screen end whatever the request was showing in their place.
                if !isEmpty { seasonsPhase = .idle }
            }
            // Keyed on the stored flag: a catalog refresh recreates the row without its
            // seasons while the page may still be on a stack.
            .task(id: currentSeries.seasonsLoaded) {
                await loadSeasonsIfNeeded()
            }
            .task(id: SeasonSelectionKey(seasonIds: seasons.map(\.id), latestStreamId: watchHistory?.streamId)) {
                await syncSeasonSelection()
            }
            .task(id: EpisodeProbeKey(seasonIds: seasons.map(\.id), seasonsLoaded: currentSeries.seasonsLoaded)) {
                await probeEpisodes()
            }
            .onReceive(NetworkStatus.shared.$reconnectCount.dropFirst()) { _ in
                // One more try once the connection is back, only while the failure is shown.
                if seasons.isEmpty, case .failed = seasonsPhase {
                    Task { await fetchSeriesInfo() }
                }
            }
    }

    /// The bar title as a view of its own: a navigation title string cannot fade in and
    /// out at the scroll threshold, a principal item can.
    @ToolbarContentBuilder
    private var navigationTitleItem: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .principal) { navigationTitleLabel }
                // The label is transparent while the hero is on screen; it must not leave
                // an empty glass capsule behind.
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { navigationTitleLabel }
        }
    }

    private var navigationTitleLabel: some View {
        Text(currentSeries.name)
            .font(.headline)
            .lineLimit(1)
            .opacity(showNavTitle ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showNavTitle)
            // The navigation title already names the screen.
            .accessibilityHidden(true)
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
                    trailerURL: trailerURL,
                    primaryDisabled: isPrimaryDisabled
                )

                if let plot = currentSeries.plot?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
                    DetailPlotBlock(plot: plot)
                        .padding(.top, 4)
                }

                if let director = currentSeries.director?.trimmingCharacters(in: .whitespacesAndNewlines), !director.isEmpty {
                    DetailInfoTextBlock(label: L("movie.director"), value: director)
                }

                if let cast = currentSeries.cast?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty {
                    DetailInfoTextBlock(label: L("movie.cast"), value: cast, lineLimit: 3)
                }

                seasonsSection
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y > 240
        } action: { _, newValue in
            showNavTitle = newValue
        }
        .ignoresSafeArea(edges: .top)
    }

    /// The heading of the seasons block. A single season needs no selector, so its name
    /// takes the heading's place.
    private var seasonsHeading: String {
        guard seasons.count == 1, let only = seasons.first else { return L("series.seasons") }
        return only.name ?? L("series.season_format", only.seasonNumber)
    }

    /// Seasons are still to come: requested now, or about to be because the stored row has none.
    private var isAwaitingSeasons: Bool {
        switch seasonsPhase {
        case .loading: return true
        case .idle: return !currentSeries.seasonsLoaded
        case .failed, .missing: return false
        }
    }

    @ViewBuilder
    private var seasonsSection: some View {
        if !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(seasonsHeading)
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

                if seasons.count > 1 {
                    DetailSeasonTabBar(seasons: seasons, selectedId: $selectedSeasonId)
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
                        play(ep, history: history, resumesFinished: false)
                    }
                }
            }
            .padding(.top, 8)
        } else if case .failed(let message) = seasonsPhase {
            // Only without seasons: a request that fails over seasons already stored
            // leaves them on screen.
            VStack(alignment: .leading, spacing: 10) {
                Text(L("series.seasons"))
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                InlineErrorRow(message: message) {
                    Task { await fetchSeriesInfo() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else if isAwaitingSeasons {
            SeasonsLoadingPlaceholder()
        } else {
            Text(L("series.no_seasons_info"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: Playback

    private func resumeLatestEpisode() {
        // The live row at the moment of the tap: a copy taken earlier would resume at an old position.
        guard let history = watchHistory else {
            playFirstEpisode()
            return
        }
        let playlistId = playlist.id
        Task {
            let episode = try? await AppDatabase.shared.read { db in
                try SeriesDetailData.episode(streamId: history.streamId, playlistId: playlistId, db: db)
            }
            if let episode {
                play(episode, history: history, resumesFinished: true)
            } else {
                // The episode rows are gone (a refresh dropped them, or the request for them
                // failed). The history row has all the player needs, as on Continue Watching.
                present(seed: history)
            }
        }
    }

    private func playFirstEpisode() {
        let seriesId = series.seriesId
        let playlistId = playlist.id
        Task {
            let first = try? await AppDatabase.shared.read { db in
                try SeriesDetailData.firstEpisode(seriesId: seriesId, playlistId: playlistId, db: db)
            }
            guard let first else { return }
            play(first, history: nil, resumesFinished: false)
        }
    }

    /// `resumesFinished`: the Resume button reopens its episode where it stopped, whatever
    /// the position. An episode picked from the list starts over once it counts as watched,
    /// instead of replaying its last seconds and running into the next one.
    private func play(_ episode: DBEpisode, history: DBWatchHistory?, resumesFinished: Bool) {
        present(seed: SeriesDetailData.playbackSeed(
            episode: episode,
            history: history,
            resumesFinished: resumesFinished,
            series: currentSeries,
            playlistId: playlist.id
        ))
    }

    /// Hands the episode to the player shell that owns next / previous / auto-advance.
    /// The page keeps no playback state of its own, so stepping goes on after it was popped
    /// and a step never re-presents (which would pull a minimised player back to full screen).
    private func present(seed: DBWatchHistory) {
        Task {
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(episode: playlist.id, episodeId: seed.streamId)
            )
            let remoteURL = PlaybackURLBuilder(playlist: playlist).seriesURL(
                streamId: seed.streamId, containerExtension: seed.containerExtension
            )
            guard let url = localURL ?? remoteURL else { return }
            playerOverlay.injected?.present(skipDownloadCheck: localURL != nil, playlistId: playlist.id) {
                HistorySeriesPlayerShell(playlist: playlist, history: seed, url: url, onNavigateToDetail: { _, _ in })
            }
        }
    }

    // Sezon kapakları hiçbir yerde render edilmiyor; prefetch etmek yalnızca boşa ağ
    // trafiği ve pil tüketiyordu (bkz. inceleme bulgusu). Kapaklar ileride gösterilirse
    // render parametreleriyle birebir aynı prefetch yeniden eklenmeli.

    /// Reads whether the series has an episode to start with. A failed read leaves the
    /// last answer, so the button is never disabled on a guess.
    private func probeEpisodes() async {
        let seriesId = series.seriesId
        let playlistId = playlist.id
        do {
            let first = try await AppDatabase.shared.read { db in
                try SeriesDetailData.firstEpisode(seriesId: seriesId, playlistId: playlistId, db: db)
            }
            guard !Task.isCancelled else { return }
            let found = first != nil
            if hasEpisodes != found { hasEpisodes = found }
        } catch {
            return
        }
    }

    // MARK: Season selection

    /// Gives a page without a (valid) selection its opening season, and moves the page along
    /// when playback crosses into another season.
    private func syncSeasonSelection() async {
        let seasonIds = seasons.map(\.id)
        guard !seasonIds.isEmpty else { return }
        let seriesId = series.seriesId
        let playlistId = playlist.id
        // Read here rather than taken from the queries above: the history row, its episode
        // and the seasons then come from one snapshot, whichever query delivered first.
        let anchor = try? await AppDatabase.shared.read { db in
            try SeriesDetailData.seasonAnchor(seriesId: seriesId, playlistId: playlistId, db: db)
        }
        guard let anchor, !Task.isCancelled else { return }

        let previouslyWatched = watchedSeasonId
        if let watched = anchor.watchedSeasonId { watchedSeasonId = watched }

        guard let selected = selectedSeasonId, seasonIds.contains(selected) else {
            selectedSeasonId = anchor.initialSeasonId
            return
        }
        // Follow only from the season that was playing. Someone browsing another season
        // next to the mini player keeps their place.
        if let previouslyWatched, let watched = anchor.watchedSeasonId,
           watched != previouslyWatched, selected == previouslyWatched {
            selectedSeasonId = watched
        }
    }

    // MARK: Seasons request

    /// Decides from the stored row. The value the list handed over is as old as that list:
    /// a series opened earlier in the session, or completed by the player's own episode
    /// stepping, would otherwise be requested again on every visit.
    private func loadSeasonsIfNeeded() async {
        let seriesId = series.seriesId
        let playlistId = playlist.id
        let loaded = try? await AppDatabase.shared.read { db in
            try SeriesDetailData.seasonsLoaded(seriesId: seriesId, playlistId: playlistId, db: db)
        }
        guard !Task.isCancelled else { return }
        switch loaded {
        case .some(true):
            // `.loading` is left alone: a request of this page may still be waiting for
            // its seasons to be delivered.
            if seasonsPhase != .loading { seasonsPhase = .idle }
        case .some(false):
            await fetchSeriesInfo()
        case .none:
            if seasonsPhase != .loading { seasonsPhase = .missing }
        }
    }

    private func fetchSeriesInfo() async {
        seasonsRequestToken += 1
        let token = seasonsRequestToken
        seasonsPhase = .loading
        let seriesId = series.seriesId
        let playlistId = playlist.id
        do {
            let info = try await XtreamAPIClient(playlist: playlist).getSeriesInfo(seriesId: seriesId)
            let storedSeasons = try await AppDatabase.shared.write { db in
                try SeriesDetailData.store(info, seriesId: seriesId, playlistId: playlistId, db: db)
            }
            guard token == seasonsRequestToken else { return }
            guard let storedSeasons else {
                seasonsPhase = .missing
                return
            }
            // The seasons query delivers a turn after the write. Until it has, the block
            // keeps its placeholder, so "no season info" cannot flash in between.
            seasonsPhase = (storedSeasons > 0 && seasons.isEmpty) ? .loading : .idle
        } catch {
            guard token == seasonsRequestToken else { return }
            // A page that leaves the screen cancels its request; that is not a failure to
            // show. The request starts again when the page is back.
            seasonsPhase = Task.isCancelled ? .idle : .failed(NetworkErrorText.describe(error))
        }
    }

    // MARK: Favourite

    private func toggleFavorite() {
        let target = !showsFavorite
        favoriteOverride = target
        favoriteTapCount += 1
        let tap = favoriteTapCount
        // Copied here: the write closure runs on the database queue and must not read view state.
        let seriesId = series.seriesId
        let playlistId = playlist.id
        Task {
            do {
                try await AppDatabase.shared.write { db in
                    try SeriesDetailData.setFavorite(target, seriesId: seriesId, playlistId: playlistId, db: db)
                }
                // Usually the query delivers the new value a turn later and clears the
                // override itself. When the stored value already matches, nothing will arrive.
                if tap == favoriteTapCount, isFavorite == target { favoriteOverride = nil }
            } catch {
                // Back to the stored value, unless a later tap has taken over.
                if tap == favoriteTapCount { favoriteOverride = nil }
            }
        }
    }

}

/// Stands in for the seasons block while its request runs: the heading and a few rows in
/// the shape of the episode list, so the page keeps its length when the real rows arrive.
private struct SeasonsLoadingPlaceholder: View {
    @Environment(\.posterMetrics) private var posterMetrics

    private static let rowCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("series.seasons"))
                .font(.title3.weight(.bold))
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        bar
                            .frame(width: posterMetrics.episodeThumbWidth, height: posterMetrics.episodeThumbHeight)
                        VStack(alignment: .leading, spacing: 8) {
                            bar.frame(width: 150, height: 14)
                            bar.frame(width: 64, height: 10)
                            bar.frame(height: 10)
                            bar.frame(height: 10)
                                .padding(.trailing, 40)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < Self.rowCount - 1 {
                        Divider()
                            .padding(.leading, posterMetrics.episodeRowDividerLeading)
                    }
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("series.loading_seasons"))
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(UIColor.tertiarySystemFill))
    }
}

/// @Query + `.id(seasonId)` ScrollView kaydırma konumunu sıfırlıyordu; sezon değişince aynı panelde abonelik yenilenir.
final class SeasonEpisodesObserver: ObservableObject {
    /// nil only until the first season has been read, so that the panel shows its loading
    /// state instead of "no episodes" in the meantime. A season switch keeps the previous
    /// season's rows until the new ones exist: emptying the list in between collapses the
    /// page under the reader and the scroll view clamps its offset.
    @Published private(set) var season: SeasonEpisodes?
    private var seasonId: String?
    private var cancellable: AnyCancellable?

    func load(seasonId: String, playlistId: UUID, db: AppDatabase) {
        guard seasonId != self.seasonId else { return }
        self.seasonId = seasonId
        cancellable?.cancel()
        cancellable = ValueObservation
            .tracking { db in
                try SeriesDetailData.seasonEpisodes(seasonId: seasonId, playlistId: playlistId, db: db)
            }
            // The first value arrives during subscription, so the rows change in the same
            // update as the season chip. One season through two indexes is a small read
            // for the main thread, where this is always called from.
            .publisher(in: db.reader, scheduling: .immediate)
            // The player saves a history row every few seconds and the observation
            // re-fetches on each of them; the panel only hears about its own episodes.
            .removeDuplicates()
            .catch { _ in Just(SeasonEpisodes()) }
            .sink { [weak self] season in
                self?.season = season
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
            if let season = observer.season {
                if season.episodes.isEmpty {
                    Text(L("series.no_episodes_in_season"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(season.episodes.enumerated()), id: \.element.id) { index, episode in
                            EpisodeDetailRow(
                                playlist: playlist,
                                episode: episode,
                                history: season.history[episode.episodeId ?? episode.id],
                                seriesId: seriesId,
                                seriesName: seriesName,
                                seriesCover: seriesCover
                            ) { ep, history in
                                onEpisodeSelected(ep, history)
                            }
                            // The season's history changes with every save of the player;
                            // only the row whose own values changed is drawn again.
                            .equatable()
                            if index < season.episodes.count - 1 {
                                Divider()
                                    .padding(.leading, posterMetrics.episodeRowDividerLeading)
                            }
                        }
                    }
                    .onChange(of: season.episodes) { _, newValue in
                        let urls = newValue.compactMap(\.cover).compactMap { URL(string: $0) }
                        ListImagePrefetch.start(urls: urls, width: posterMetrics.episodeThumbWidth, height: posterMetrics.episodeThumbHeight, contentMode: .fill, loadProfile: .grid)
                    }
                    .onAppear {
                        let urls = season.episodes.compactMap(\.cover).compactMap { URL(string: $0) }
                        ListImagePrefetch.start(urls: urls, width: posterMetrics.episodeThumbWidth, height: posterMetrics.episodeThumbHeight, contentMode: .fill, loadProfile: .grid)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .onAppear {
            load(seasonId)
        }
        .onChange(of: seasonId) { _, newId in
            load(newId)
        }
    }

    private func load(_ seasonId: String) {
        // The season chip changes inside a spring; the list swaps in one step rather than
        // having two seasons' rows move through each other.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            observer.load(seasonId: seasonId, playlistId: playlist.id, db: appDatabase)
        }
    }
}

private struct EpisodeDetailRow: View, Equatable {
    let playlist: Playlist
    let episode: DBEpisode
    /// Handed down with the season's rows; a row does not observe the database itself.
    let history: DBWatchHistory?
    let seriesId: String
    let seriesName: String
    let seriesCover: String?
    var onStreamSelected: (DBEpisode, DBWatchHistory?) -> Void

    @Environment(\.posterMetrics) private var posterMetrics

    /// Everything the row draws. The closure is left out: it only forwards the row's own
    /// values, and what it reaches behind that is looked up when it is called.
    static func == (lhs: EpisodeDetailRow, rhs: EpisodeDetailRow) -> Bool {
        lhs.episode == rhs.episode
            && lhs.history == rhs.history
            && lhs.playlist == rhs.playlist
            && lhs.seriesId == rhs.seriesId
            && lhs.seriesName == rhs.seriesName
            && lhs.seriesCover == rhs.seriesCover
    }

    private var remoteURL: URL? {
        PlaybackURLBuilder(playlist: playlist).seriesURL(
            streamId: episode.episodeId ?? episode.id,
            containerExtension: episode.containerExtension
        )
    }

    var body: some View {
        let remoteURL = remoteURL
        HStack(alignment: .top, spacing: 0) {
            Button {
                onStreamSelected(episode, history)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail
                    textColumn
                }
                // The row's margins are part of the label, so the whole band starts the
                // episode: picture, text and the space around them.
                .padding(.leading, 16)
                .padding(.trailing, remoteURL == nil ? 16 : 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dimPress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)

            // Next to the row button, never inside it: its taps and its menu must not
            // start playback.
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
                    // seasonId "<playlistUUID>_<seriesId>_<seasonNum>" — son bileşen
                    // sezon numarası. Geçilmeyince DownloadsView S02E01'i S01E02'nin
                    // önüne diziyordu (hepsi season 0 sayılıyordu).
                    seasonNumber: episode.seasonId.split(separator: "_").last.flatMap { Int($0) },
                    episodeNumber: episode.episodeNum,
                    compact: true
                )
                .padding(.vertical, 12)
                .padding(.trailing, 16)
            }
        }
    }

    private var thumbnail: some View {
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

            if let history, history.durationMs > 0 {
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
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(episodeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            FlowMetaRow(episode: episode)

            if let history, history.durationMs > 0 {
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
    }

    private var episodeTitle: String {
        SeriesDetailData.episodeTitle(episode)
    }

    /// What VoiceOver reads for the row: title, length, how far it was watched, then the plot.
    private var accessibilityText: String {
        var parts = [episodeTitle]
        if let d = episode.duration?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            parts.append(d)
        }
        if let history, history.durationMs > 0 {
            let progress = Double(history.lastTimeMs) / Double(history.durationMs)
            parts.append(progress >= 0.95
                ? L("detail.watched")
                : L("detail.remaining_format", formatWatchMs(history.durationMs - history.lastTimeMs)))
        }
        if let plot = episode.info?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
            parts.append(plot)
        }
        return parts.joined(separator: ", ")
    }

    private func formatWatchMs(_ ms: Int) -> String {
        DetailFormatting.formatMs(ms)
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

// MARK: - Series detail data

/// One season's episode rows together with the watch history of those episodes.
nonisolated struct SeasonEpisodes: Equatable, Sendable {
    var episodes: [DBEpisode] = []
    /// Keyed by the id playback uses for an episode (`episodeId ?? id`).
    var history: [String: DBWatchHistory] = [:]
}

/// Where the season selection of a series page stands.
nonisolated struct SeriesSeasonAnchor: Equatable, Sendable {
    /// Season of the most recently watched episode, when that episode is still stored.
    var watchedSeasonId: String?
    /// The season a page without a selection opens on.
    var initialSeasonId: String?
}

/// The database side of the series page and the rules its buttons share. The `db`
/// functions run inside GRDB's read and write closures, off the main actor.
enum SeriesDetailData {

    // MARK: Seasons request

    /// The stored `seasonsLoaded` flag; nil when the series has no row (any more).
    nonisolated static func seasonsLoaded(seriesId: Int, playlistId: UUID, db: Database) throws -> Bool? {
        try storedSeries(seriesId: seriesId, playlistId: playlistId, db: db)?.seasonsLoaded
    }

    /// Stores the answer of `get_series_info` and returns the number of seasons written,
    /// or nil, with nothing written, when the series row no longer exists.
    ///
    /// The row is fetched inside the transaction and only the fields of the answer are
    /// changed on it. Writing back the copy a screen was opened with would undo whatever
    /// a catalog refresh stored in between, and wipe the details of an earlier answer when
    /// this one comes without an info block.
    nonisolated static func store(
        _ info: XtreamSeriesInfoResponse, seriesId: Int, playlistId: UUID, db: Database
    ) throws -> Int? {
        guard var row = try storedSeries(seriesId: seriesId, playlistId: playlistId, db: db) else { return nil }

        let episodesBySeason = info.episodesBySeasonNumber
        let resolvedSeasons = info.resolvedSeasons
        for (seasonNum, apiSeason) in resolvedSeasons {
            let seasonId = DBSeason.scopedId(playlistId: playlistId, seriesId: seriesId, seasonNumber: seasonNum)
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
                playlistId: playlistId
            )
            try dbSeason.save(db)

            for ep in eps {
                let dbEp = DBEpisode(
                    id: DBEpisode.scopedId(playlistId: playlistId, panelEpisodeId: ep.id),
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

        row.seasonsLoaded = true
        if let i = info.info {
            row.cast = i.cast
            row.director = i.director
            row.genre = i.genre
            row.plot = i.plot
            row.releaseDate = i.releaseDate
            row.rating = i.rating
            row.lastModified = i.lastModified
            row.rating5Based = i.rating5Based
            row.backdropPath = i.backdropPath?.first
            row.youtubeTrailer = i.youtubeTrailer
            row.episodeRunTime = i.episodeRunTime
        }
        try row.update(db)
        return resolvedSeasons.count
    }

    nonisolated private static func storedSeries(seriesId: Int, playlistId: UUID, db: Database) throws -> DBSeries? {
        try DBSeries
            .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
            .fetchOne(db)
    }

    // MARK: Episodes

    /// The episode a history row of this playlist belongs to.
    ///
    /// Matched on the row id, which carries the playlist: the panel's own episode id
    /// repeats across playlists. The second term covers episodes the panel sent without
    /// an id; their history is filed under the row id itself.
    nonisolated static func episode(streamId: String, playlistId: UUID, db: Database) throws -> DBEpisode? {
        try DBEpisode
            .filter(
                Column("id") == DBEpisode.scopedId(playlistId: playlistId, panelEpisodeId: streamId)
                    || Column("id") == streamId
            )
            .fetchOne(db)
    }

    /// The episode "Watch" starts with: the first one in play order. Seasons a panel
    /// declares without episodes are passed over.
    ///
    /// The order is that of `SeriesPlaybackOrdering.orderedEpisodes`, which the player
    /// steps through (seasons by number, episodes by number within a season). It is read
    /// season by season here, so that one row is loaded instead of the whole series.
    nonisolated static func firstEpisode(seriesId: Int, playlistId: UUID, db: Database) throws -> DBEpisode? {
        try firstEpisode(inSeasons: seasonIds(seriesId: seriesId, playlistId: playlistId, db: db), db: db)
    }

    nonisolated private static func firstEpisode(inSeasons seasonIds: [String], db: Database) throws -> DBEpisode? {
        for seasonId in seasonIds {
            if let episode = try DBEpisode
                .filter(Column("seasonId") == seasonId)
                .order(Column("episodeNum").asc)
                .fetchOne(db) {
                return episode
            }
        }
        return nil
    }

    /// The series' season ids, lowest season number first.
    nonisolated private static func seasonIds(seriesId: Int, playlistId: UUID, db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            DBSeason
                .select(Column("id"))
                .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
                .order(Column("seasonNumber").asc)
        )
    }

    /// The episodes of one season in list order, with the history rows of exactly those episodes.
    nonisolated static func seasonEpisodes(seasonId: String, playlistId: UUID, db: Database) throws -> SeasonEpisodes {
        let episodes = try DBEpisode
            .filter(Column("seasonId") == seasonId)
            .order(Column("episodeNum"))
            .fetchAll(db)
        guard !episodes.isEmpty else { return SeasonEpisodes() }

        // By episode id rather than by the history's series id, which older rows lack.
        let streamIds = episodes.map { $0.episodeId ?? $0.id }
        let rows = try DBWatchHistory
            .filter(
                Column("playlistId") == playlistId
                    && Column("type") == "series"
                    && streamIds.contains(Column("streamId"))
            )
            .fetchAll(db)
        var history: [String: DBWatchHistory] = [:]
        for row in rows { history[row.streamId] = row }
        return SeasonEpisodes(episodes: episodes, history: history)
    }

    // MARK: Season selection

    /// One rule for the season a page opens on: the season of the most recently watched
    /// episode, else the season "Watch" would start in, else the first season. The history
    /// row is read here, in the same snapshot as its episode and the seasons.
    nonisolated static func seasonAnchor(seriesId: Int, playlistId: UUID, db: Database) throws -> SeriesSeasonAnchor {
        let seasonIds = try seasonIds(seriesId: seriesId, playlistId: playlistId, db: db)
        guard let firstSeasonId = seasonIds.first else { return SeriesSeasonAnchor() }

        let latest = try DBWatchHistory
            .filter(Column("seriesId") == String(seriesId) && Column("playlistId") == playlistId)
            .order(Column("lastWatchedAt").desc)
            .fetchOne(db)
        if let latest,
           let watched = try episode(streamId: latest.streamId, playlistId: playlistId, db: db),
           seasonIds.contains(watched.seasonId) {
            return SeriesSeasonAnchor(watchedSeasonId: watched.seasonId, initialSeasonId: watched.seasonId)
        }

        let first = try firstEpisode(inSeasons: seasonIds, db: db)
        return SeriesSeasonAnchor(watchedSeasonId: nil, initialSeasonId: first?.seasonId ?? firstSeasonId)
    }

    // MARK: Favourite

    /// Sets the favourite to `isFavorite` whatever is stored: two quick taps are two
    /// writes of a known value each, not two toggles reading the same old state.
    nonisolated static func setFavorite(_ isFavorite: Bool, seriesId: Int, playlistId: UUID, db: Database) throws {
        if isFavorite {
            try DBFavorite(streamId: seriesId, playlistId: playlistId, type: "series")
                .insert(db, onConflict: .ignore)
        } else {
            try DBFavorite
                .filter(Column("streamId") == seriesId && Column("playlistId") == playlistId && Column("type") == "series")
                .deleteAll(db)
        }
    }

    // MARK: Playback

    /// "3. Title", the form the player shell and the downloads use for an episode.
    static func episodeTitle(_ episode: DBEpisode) -> String {
        let num = episode.episodeNum.map { "\($0). " } ?? ""
        let raw = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = raw.isEmpty ? L("detail.episode_fallback") : raw
        return "\(num)\(title)"
    }

    /// The history row `HistorySeriesPlayerShell` is started with for an episode of the page.
    ///
    /// The shell reads the stream, the texts, the artwork and the position from it. They
    /// are taken from the episode row, which is current, on top of `history` when the
    /// episode has one. `resumesFinished` keeps the stored position even when the episode
    /// counts as watched; otherwise such an episode starts over.
    static func playbackSeed(
        episode: DBEpisode,
        history: DBWatchHistory?,
        resumesFinished: Bool,
        series: DBSeries,
        playlistId: UUID,
        now: Date = Date()
    ) -> DBWatchHistory {
        let streamId = episode.episodeId ?? episode.id
        var seed = history ?? DBWatchHistory(
            id: "\(playlistId)_series_\(streamId)",
            playlistId: playlistId,
            streamId: streamId,
            type: "series",
            lastTimeMs: 0,
            durationMs: 0,
            lastWatchedAt: now,
            seriesId: nil,
            title: "",
            secondaryTitle: nil,
            imageURL: nil,
            containerExtension: nil
        )
        // Without the series id the shell has no neighbours to step to.
        seed.seriesId = String(series.seriesId)
        seed.title = episodeTitle(episode)
        seed.secondaryTitle = series.name
        seed.imageURL = episode.cover ?? series.cover
        seed.containerExtension = episode.containerExtension
        if !resumesFinished, seed.resumePositionMs(as: .episode) == nil {
            seed.lastTimeMs = 0
        }
        return seed
    }
}
