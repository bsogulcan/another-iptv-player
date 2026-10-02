import SwiftUI

struct SearchView: View {
    let playlist: Playlist
    @Binding var searchText: String
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedFilter: SearchFilter = .all

    enum SearchFilter: String, CaseIterable {
        case all, live, movies, series

        var displayName: String {
            switch self {
            case .all:    return L("search.all")
            case .live:   return L("dashboard.live")
            case .movies: return L("dashboard.movies")
            case .series: return L("dashboard.series")
            }
        }
    }

    /// Shorter text is not searched: one letter matches most of a large catalog.
    private static let minimumQueryLength = 2

    private var trimmedText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // One results view for the whole life of the tab, also while the text is too
        // short to search: its rows and its scroll position are still there when the
        // character that was deleted is typed again.
        SearchResultsView(
            playlist: playlist,
            query: debouncedQuery,
            isFieldEmpty: trimmedText.isEmpty,
            filter: $selectedFilter
        )
        .navigationTitle(L("search.title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("search.placeholder"))
        .searchScopes($selectedFilter, activation: .onSearchPresentation) {
            ForEach(SearchFilter.allCases, id: \.self) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedFilter)
        .onChange(of: searchText) { _, _ in
            debounceTask?.cancel()
            guard let q = pendingQuery else { return }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = q }
            }
        }
        // The rows must not change under a detail page opened from them: a row that
        // goes away takes the link that pushed the page with it, and the page pops.
        // Text typed just before a result was opened is searched on the way back.
        .onDisappear { debounceTask?.cancel() }
        .onAppear {
            if let q = pendingQuery { debouncedQuery = q }
        }
    }

    /// What the field asks to be searched, or nil when that is already on screen
    /// (a space typed after a word, or a deletion back to the searched text).
    /// Empty while the text is shorter than the minimum.
    private var pendingQuery: String? {
        let q = trimmedText
        let next = q.count >= Self.minimumQueryLength ? q : ""
        return next == debouncedQuery ? nil : next
    }
}

// MARK: - Results

/// Everything a result set depends on; the search runs again when any of it changes.
/// The revisions are there for a catalog reload that leaves `streamsLoaded` alone.
nonisolated private struct SearchKey: Equatable {
    let query: String
    let playlistId: UUID
    let streamsLoaded: Bool
    let liveRevision: Int
    let vodRevision: Int
    let seriesRevision: Int
    let hiddenVersion: Int
}

/// The catalog scan behind the Search tab, apart from the views so that it can be tested.
nonisolated enum GlobalSearch {
    /// The three content types side by side: the catalog going in, the hits coming out.
    struct Items: Sendable {
        var live: [LiveStreamWithCategory] = []
        var movies: [VODWithCategory] = []
        var series: [SeriesWithCategory] = []
    }

    /// Hidden category ids per content type; panels reuse the same ids across types.
    struct HiddenCategories: Sendable {
        var live: Set<String> = []
        var movies: Set<String> = []
        var series: Set<String> = []
    }

    /// The hits of `query` in every content type, best match first, hidden categories
    /// left out. The types are scanned side by side, off the main actor.
    ///
    /// Cancelling the calling task gives the scans up; what comes back then is empty
    /// and must be thrown away, not shown as "no results".
    static func hits(for query: String, in catalog: Items, hidden: HiddenCategories) async -> Items {
        // Text without a letter or digit ("--") finds nothing, and needs no scan to.
        guard !CatalogTextSearch.Query(query).isEmpty else { return Items() }
        async let live = rankedHits(
            in: catalog.live, query: query, hiddenCategories: hidden.live,
            categoryId: { $0.stream.categoryId }, name: { $0.stream.name }
        )
        async let movies = rankedHits(
            in: catalog.movies, query: query, hiddenCategories: hidden.movies,
            categoryId: { $0.stream.categoryId }, name: { $0.stream.name }
        )
        async let series = rankedHits(
            in: catalog.series, query: query, hiddenCategories: hidden.series,
            categoryId: { $0.series.categoryId }, name: { $0.series.name }
        )
        return await Items(live: live, movies: movies, series: series)
    }

    /// `query` must have a searchable word.
    private static func rankedHits<Item: Sendable>(
        in items: [Item],
        query: String,
        hiddenCategories: Set<String>,
        categoryId: @escaping @Sendable (Item) -> String?,
        name: @escaping @Sendable (Item) -> String
    ) async -> [Item] {
        await CatalogTextSearch.detached {
            CatalogTextSearch.rankedFilter(items, search: query) { item in
                // An item of a hidden category is searched under an empty name, which
                // no word can match. Removing those items first would copy most of the
                // catalog, and removing them afterwards would rank hits nobody sees.
                if !hiddenCategories.isEmpty, hiddenCategories.contains(categoryId(item) ?? "") {
                    return ""
                }
                return name(item)
            }
        }
    }
}

private struct SearchResultsView: View {
    let playlist: Playlist
    /// The debounced search text; empty while the field holds less than the minimum.
    let query: String
    /// The field holds no text at all, as opposed to text that is too short.
    let isFieldEmpty: Bool
    @Binding var filter: SearchView.SearchFilter

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay

    @State private var liveResults: [LiveStreamWithCategory] = []
    @State private var movieResults: [VODWithCategory] = []
    @State private var seriesResults: [SeriesWithCategory] = []
    /// What the three arrays were computed for; nil until a search has finished.
    @State private var resultsKey: SearchKey?
    /// The text went below the minimum after the arrays were computed.
    @State private var wentBelowMinimum = false
    /// Rows rendered in a section that lists all its hits. A short query on a large
    /// catalog has tens of thousands of them, and a List asks every row it is given
    /// for its identity on each update.
    @State private var visibleLimit = Self.pageSize
    /// Never read in `body`.
    @State private var isScrolledDown = false
    @State private var listGeneration = 0

    private static let pageSize = 100
    /// Rows per section while all three types are listed together.
    private static let previewCount = 4
    /// How many rows before the end of a page the next one is asked for.
    private static let pagingLeadRows = 15

    private var searchKey: SearchKey {
        SearchKey(
            query: query,
            playlistId: playlist.id,
            streamsLoaded: contentStore.streamsLoaded,
            liveRevision: contentStore.liveRevision,
            vodRevision: contentStore.vodRevision,
            seriesRevision: contentStore.seriesRevision,
            hiddenVersion: hiddenStore.version
        )
    }

    /// Nothing is listed under the selected scope.
    private var visibleIsEmpty: Bool {
        switch filter {
        case .all:    liveResults.isEmpty && movieResults.isEmpty && seriesResults.isEmpty
        case .live:   liveResults.isEmpty
        case .movies: movieResults.isEmpty
        case .series: seriesResults.isEmpty
        }
    }

    /// The rows on hand were searched while the streams were still being read (or
    /// are being read now), so an empty outcome says nothing about the catalog yet.
    private var awaitsCatalog: Bool {
        !contentStore.streamsLoaded || resultsKey?.streamsLoaded == false
    }

    /// "No results" is the outcome of a finished search over a loaded catalog, never
    /// the state before one. It stays up while the next query of the same session is
    /// searched ("zz", "zzz"), as rows do. After the text dropped below the minimum it
    /// only stands for the very query it was found for, so typing something else does
    /// not open with it.
    private var showsNoResults: Bool {
        guard let done = resultsKey, done.streamsLoaded else { return false }
        return done.query == query || !wentBelowMinimum
    }

    var body: some View {
        let key = searchKey
        List {
            section(.live, title: L("dashboard.live"), items: liveResults, id: \.stream.streamId) { item in
                Button { playLive(item) } label: {
                    ResultRow(name: item.stream.name,
                              subtitle: item.categoryName,
                              iconURL: item.stream.streamIcon.flatMap { URL(string: $0) },
                              typeIcon: "tv",
                              artwork: .logo)
                }
                .accessibilityIdentifier("card.live.\(item.stream.streamId)")
            }

            section(.movies, title: L("dashboard.movies"), items: movieResults, id: \.stream.streamId) { item in
                NavigationLink {
                    MovieResultDestination(playlist: playlist, movie: item.stream)
                } label: {
                    ResultRow(name: item.stream.name,
                              subtitle: item.categoryName,
                              iconURL: item.stream.streamIcon.flatMap { URL(string: $0) },
                              typeIcon: "film",
                              artwork: .poster,
                              rating: item.stream.rating)
                }
                .accessibilityIdentifier("card.vod.\(item.stream.streamId)")
            }

            section(.series, title: L("dashboard.series"), items: seriesResults, id: \.series.seriesId) { item in
                NavigationLink {
                    SeriesDetailView(playlist: playlist, series: item.series)
                } label: {
                    ResultRow(name: item.series.name,
                              subtitle: item.categoryName,
                              iconURL: item.series.cover.flatMap { URL(string: $0) },
                              typeIcon: "play.tv",
                              artwork: .poster,
                              rating: item.series.rating)
                }
                .accessibilityIdentifier("card.series.\(item.series.seriesId)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 4
        } action: { _, scrolled in
            isScrolledDown = scrolled
        }
        .id(listGeneration)
        // The rows of the last query stay under the hint; nothing may reach them there.
        .accessibilityHidden(query.isEmpty)
        .overlay { stateOverlay }
        .onChange(of: filter) { _, _ in
            visibleLimit = Self.pageSize
            startAtTop()
        }
        .onChange(of: query) { _, newQuery in
            if newQuery.isEmpty {
                wentBelowMinimum = true
            } else if newQuery == resultsKey?.query {
                // Back on the text the rows were found for: they hold for it again, and
                // for the next query of the session as before. No scan follows to say so.
                wentBelowMinimum = false
            }
        }
        .onChange(of: isFieldEmpty) { _, isEmpty in
            // An emptied field ends the session: what is typed next is a new search,
            // and must not open on the rows of the old one.
            if isEmpty { clearResults() }
        }
        // One task for every input. It also starts again each time the list comes back
        // on screen (a pop from a detail page, a tab switch), which `runSearch` answers
        // without a scan when nothing changed.
        .task(id: key) { await runSearch(for: key) }
    }

    // MARK: Sections

    /// One content type: the best few hits while all types are listed together, every
    /// hit, a page at a time, under its own scope.
    @ViewBuilder
    private func section<Item, ID: Hashable, Row: View>(
        _ scope: SearchView.SearchFilter,
        title: String,
        items: [Item],
        id: KeyPath<Item, ID>,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if (filter == .all || filter == scope) && !items.isEmpty {
            let listsAll = filter == scope
            let limit = visibleLimit
            let shown = items.prefix(listsAll ? limit : Self.previewCount)
            let hasMore = shown.count < items.count
            // Asking from a row before the end keeps a fling from running into the
            // end of the page.
            let pagingRow: ID? = listsAll && hasMore
                ? shown[shown.endIndex - min(Self.pagingLeadRows, shown.count)][keyPath: id]
                : nil
            Section {
                ForEach(shown, id: id) { item in
                    row(item)
                        .onAppear {
                            if item[keyPath: id] == pagingRow { showNextPage(after: limit) }
                        }
                }
                if hasMore {
                    if listsAll {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            // One identity per page: a reused spinner row stops
                            // animating and does not appear a second time.
                            .id(limit)
                            .onAppear { showNextPage(after: limit) }
                    } else {
                        Button {
                            filter = scope
                        } label: {
                            Text(L("search.more_results_format", items.count - shown.count))
                        }
                    }
                }
            } header: {
                SectionHeader(title: title, count: items.count)
            }
        }
    }

    private func showNextPage(after limit: Int) {
        // The row near the end and the spinner under it both ask for the same page.
        guard visibleLimit == limit else { return }
        visibleLimit = limit + Self.pageSize
    }

    // MARK: States

    @ViewBuilder
    private var stateOverlay: some View {
        if query.isEmpty {
            CatalogEmptyView(.message(
                title: L("search.title"),
                systemImage: "magnifyingglass",
                description: L("search.min_chars")
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        } else if visibleIsEmpty {
            if awaitsCatalog {
                // The catalog is still loading: "no results" here would look as if the
                // content were gone. The search runs again once the streams are in, and
                // this stays up until that search is done.
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L("common.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if showsNoResults {
                CatalogEmptyView(.noSearchResults)
            }
        }
    }

    // MARK: Search

    private func runSearch(for key: SearchKey) async {
        // Too short to search. The rows of the last query stay where they are, under
        // the hint.
        guard !key.query.isEmpty else { return }
        guard key != resultsKey else { return }

        let catalog = GlobalSearch.Items(
            live: contentStore.liveStreams,
            movies: contentStore.vodStreams,
            series: contentStore.seriesItems
        )
        let hidden = GlobalSearch.HiddenCategories(
            live: hiddenStore.hiddenIds(playlistId: playlist.id, type: "live"),
            movies: hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod"),
            series: hiddenStore.hiddenIds(playlistId: playlist.id, type: "series")
        )
        let hits = await GlobalSearch.hits(for: key.query, in: catalog, hidden: hidden)
        // A cancelled scan hands back nothing, which must not be taken for "no results".
        guard !Task.isCancelled else { return }

        let isNewQuery = resultsKey?.query != key.query
        liveResults = hits.live
        movieResults = hits.movies
        seriesResults = hits.series
        resultsKey = key
        wentBelowMinimum = false
        // A reload of the catalog or a hidden category changes the rows of the query
        // on screen; the reader keeps their place then.
        if isNewQuery {
            visibleLimit = Self.pageSize
            startAtTop()
        }
    }

    private func clearResults() {
        liveResults = []
        movieResults = []
        seriesResults = []
        resultsKey = nil
        wentBelowMinimum = false
        visibleLimit = Self.pageSize
    }

    /// The hits of another query or scope are read from the best match down. Scrolling
    /// a List to its first row leaves the header above that row cut off, so a scrolled
    /// list is replaced instead; one that is already at the top is left alone.
    private func startAtTop() {
        guard isScrolledDown else { return }
        isScrolledDown = false
        listGeneration += 1
    }

    private func playLive(_ item: LiveStreamWithCategory) {
        // Tek geçişte grupla (O(N)); kategori başına filter+first taraması geniş
        // sorgularda tap anında main thread'i milyonlarca karşılaştırmayla kilitliyordu.
        let sections: [LiveChannelCategorySection] = {
            var seen = Set<String>()
            var ids: [String] = []
            for i in liveResults {
                let cid = i.stream.categoryId ?? "other"
                if seen.insert(cid).inserted { ids.append(cid) }
            }
            let grouped = Dictionary(grouping: liveResults) { $0.stream.categoryId ?? "other" }
            return ids.compactMap { cid -> LiveChannelCategorySection? in
                guard let items = grouped[cid], let first = items.first else { return nil }
                return LiveChannelCategorySection(id: cid, title: first.categoryName, streams: items.map(\.stream))
            }
        }()
        playerOverlay.injected?.present(playlistId: playlist.id) {
            LivePlayerShell(
                playlist: playlist,
                queue: liveResults.map(\.stream),
                sections: sections,
                initialStream: item.stream,
                initialHistory: nil,
                subtitle: nil
            )
        }
    }
}

/// The detail page of a movie hit, opened with the catalog's current copy of the movie.
/// The result arrays are not rebuilt on the way back from a detail page, so their copy
/// lacks the metadata that page fetched, and handing it out again would make the page
/// fetch it a second time. Looked up here because the body of a destination only runs
/// when its link is followed.
private struct MovieResultDestination: View {
    let playlist: Playlist
    let movie: DBVODStream

    var body: some View {
        MovieDetailView(playlist: playlist, movie: currentCopy ?? movie)
    }

    private var currentCopy: DBVODStream? {
        let store = PlaylistContentStore.shared
        guard store.activePlaylistId == playlist.id else { return nil }
        // A movie whose category is not listed sits in the uncategorized bucket.
        for key in [movie.categoryId ?? "", PlaylistContentStore.uncategorizedCategoryId] {
            if let hit = store.vodStreamsByCategoryId[key]?.first(where: { $0.stream.streamId == movie.streamId }) {
                return hit.stream
            }
        }
        return nil
    }
}

private struct ResultRow: View {
    enum Artwork {
        /// A channel logo: square, shown whole on a tile.
        case logo
        /// A movie or series poster: 2:3, filling its frame.
        case poster
    }

    let name: String
    let subtitle: String
    let iconURL: URL?
    let typeIcon: String
    let artwork: Artwork
    var rating: String? = nil

    /// Logos and posters share their width, so titles and separators line up between
    /// the sections.
    private static let artworkWidth: CGFloat = 44
    private static let artworkCornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                // Concrete colours: inside the list's button style a hierarchical
                // `.primary` / `.secondary` resolves against the accent tint.
                Text(name)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(artwork == .poster ? 2 : 1)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                    if let ratingText = ContentRating.displayText(rating) {
                        RatingLabel(rating: rating)
                            .layoutPriority(1)
                            // The star symbol alone would be read out as "favorite".
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: "\(L("movie.rating")) \(ratingText)"))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch artwork {
        case .logo:
            CachedImage(
                url: iconURL,
                width: Self.artworkWidth,
                height: Self.artworkWidth,
                cornerRadius: Self.artworkCornerRadius,
                iconName: typeIcon,
                loadProfile: .grid,
                showsTile: true
            )
        case .poster:
            CachedImage(
                url: iconURL,
                width: Self.artworkWidth,
                height: Self.artworkWidth * 1.5,
                cornerRadius: Self.artworkCornerRadius,
                contentMode: .fill,
                iconName: typeIcon,
                loadProfile: .grid
            )
        }
    }
}

private struct SectionHeader: View {
    let title: String
    /// All hits of the section, not only the rows that are listed.
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number)
        }
        .accessibilityElement(children: .combine)
    }
}
