import SwiftUI
import UIKit
import GRDBQuery
import GRDB

/// Everything the Movies screens derive from the store and from their search field.
/// Each screen keys one `.task(id:)` on it and remembers the key it applied last:
/// SwiftUI restarts a task whenever its view comes back (tab switch, pop), and that
/// alone must not repeat the work.
private nonisolated struct VODCatalogKey: Equatable {
    let query: String
    let streamsLoaded: Bool
    /// `PlaylistContentStore.vodRevision`, the only signal of a scoped reload.
    let revision: Int
    let hiddenVersion: Int
    let playlistId: UUID
    let activePlaylistId: UUID?
}

struct VODView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay

    @State private var pendingMovieDetail: DBVODStream?

    private var pickerEntries: [CategoryPickerSheet.Entry] {
        contentStore.vodCategories.map { cat in
            CategoryPickerSheet.Entry(
                id: cat.id,
                name: cat.name,
                count: contentStore.vodStreamsByCategoryId[cat.id]?.count ?? 0
            )
        }
    }

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    /// Shelves of the current search, filtered off the main actor. Without a search the
    /// shelves are read from the store in `body`: a copy kept here goes stale whenever
    /// the store changes in a way this view is not told about.
    @State private var searchShelves: VODShelfSearch.Match?
    /// "Recently added" computed from the whole catalog, for the one case the store's
    /// candidates cannot cover (see `VODRecentlyAdded.isCutShort`).
    @State private var recentBackfill: RecentBackfill?
    /// The key the two states above were last computed for.
    @State private var appliedKey: VODCatalogKey?

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil
    /// Width of the shelf list. Seeded with the screen width so the first pass already
    /// has a usable value; the measured one replaces it where the two differ (iPad
    /// sidebar, split view).
    @State private var shelfWidth: CGFloat = UIScreen.main.bounds.width

    private struct RecentKey: Equatable {
        let revision: Int
        let hiddenVersion: Int
    }

    private struct RecentBackfill {
        let key: RecentKey
        let items: [DBVODStream]
    }

    /// What the shelf list draws in one body pass.
    private struct ShelfList {
        var categories: [DBCategory]
        var itemsByCategory: [String: [VODWithCategory]]
        /// The categories are known and the movies are not. It comes from the same
        /// store state as `itemsByCategory`, so a shelf never sees "loaded" together
        /// with a list that has not arrived yet.
        var isStreamsLoading: Bool
        var recentlyAdded: [DBVODStream] = []
        /// Keeps the place of "recently added" while its movies are not known yet, so
        /// that it does not push the shelves down when they arrive.
        var reservesRecentlyAdded = false
    }

    private enum Phase {
        case preparing
        case failed(String)
        case empty(isSearch: Bool)
        case shelves(ShelfList)
    }

    private var catalogKey: VODCatalogKey {
        VODCatalogKey(
            query: debouncedQuery,
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.vodRevision,
            hiddenVersion: hiddenStore.version,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    private var recentKey: RecentKey {
        RecentKey(revision: contentStore.vodRevision, hiddenVersion: hiddenStore.version)
    }

    private func visibleCategories(hidden: Set<String>) -> [DBCategory] {
        let all = contentStore.vodCategories
        return hidden.isEmpty ? all : all.filter { !hidden.contains($0.id) }
    }

    /// Decides what is on screen. Runs once per body pass and only does O(categories)
    /// work: the per-category lists are the store's own arrays, handed on as they are,
    /// which also keeps the `==` of the shelf rows on its same-buffer fast path.
    private var phase: Phase {
        let itemsByCategory = contentStore.vodStreamsByCategoryId
        // The hidden set is a UserDefaults read: once per pass, not once per shelf.
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")
        let categories = visibleCategories(hidden: hidden)

        let isStreamsLoading: Bool
        switch VODHomeStatus.resolve(
            isActivePlaylist: playlist.id == contentStore.activePlaylistId,
            isLoading: contentStore.isLoading,
            loadError: contentStore.loadError,
            streamsLoaded: contentStore.streamsLoaded,
            hasItems: !itemsByCategory.isEmpty,
            hasVisibleCategories: !categories.isEmpty
        ) {
        case .preparing: return .preparing
        case .failed(let error): return .failed(error)
        case .noCategory: return .empty(isSearch: false)
        case .shelves(let loading): isStreamsLoading = loading
        }

        let query = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty, let match = searchShelves {
            if match.categories.isEmpty {
                // No hit while the movies are still coming in says nothing yet.
                return match.isStreamsLoading ? .preparing : .empty(isSearch: true)
            }
            return .shelves(ShelfList(
                categories: match.categories,
                itemsByCategory: match.itemsByCategory,
                isStreamsLoading: match.isStreamsLoading
            ))
        }

        let candidates = contentStore.recentVODCandidates
        var recent = VODRecentlyAdded.shelfItems(from: candidates, hidden: hidden)
        // Only a catalog whose last load had dated movies holds the place: for one
        // without `added` the slot would collapse under the shelves on every launch.
        var reservesRecent = isStreamsLoading
            && RecentlyAddedReservation.isReserved(playlistId: playlist.id, type: "vod")
        if VODRecentlyAdded.isCutShort(shelfCount: recent.count, candidateCount: candidates.count) {
            if let backfill = recentBackfill, backfill.key == recentKey {
                recent = backfill.items
            } else if recent.isEmpty {
                reservesRecent = true
            }
        }
        return .shelves(ShelfList(
            categories: categories,
            itemsByCategory: itemsByCategory,
            isStreamsLoading: isStreamsLoading,
            recentlyAdded: recent,
            reservesRecentlyAdded: reservesRecent
        ))
    }

    var body: some View {
        let key = catalogKey
        Group {
            switch phase {
            case .preparing:
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(contentStore.loadingMessage ?? L("vod.empty.preparing"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                CatalogLoadErrorView(message: message) {
                    Task { await contentStore.loadPlaylist(playlist) }
                }
            case .empty(let isSearch):
                CatalogEmptyView(isSearch ? .noSearchResults : .noCategories(systemImage: "film"))
            case .shelves(let shelves):
                shelfList(shelves)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AllVODView(playlist: playlist)
                } label: {
                    Label(L("browse.all_movies"), systemImage: "square.grid.2x2")
                }
                .disabled(contentStore.vodStreams.isEmpty)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Re-armed here, not after the jump: picking the same category twice
                    // in a row has to be a change of the target both times.
                    pendingScrollTarget = nil
                    showingCategoryPicker = true
                } label: {
                    Label(L("list.jump_to_category"), systemImage: "list.bullet.indent")
                }
                .disabled(contentStore.vodCategories.isEmpty)
            }
        }
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerSheet(
                title: L("category_picker.title"),
                entries: pickerEntries,
                playlistId: playlist.id,
                type: "vod"
            ) { id in
                showingCategoryPicker = false
                pendingScrollTarget = id
            }
        }
        // The drawer keeps the field under the title on iPad as well; left to itself the
        // system turns it into a second magnifier next to the Search tab's.
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L("vod.search_placeholder")
        )
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                debouncedQuery = ""
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onChange(of: isSearchActive) { _, active in
            if !active { searchText = ""; debouncedQuery = "" }
        }
        .task(id: key) { await refresh(for: key) }
        .transaction { $0.animation = nil }
        .navigationDestination(item: $pendingMovieDetail) { movie in
            MovieDetailView(playlist: playlist, movie: movie)
        }
        .onPlayerDetailRequest(from: playerOverlay) { request in
            guard case .movie(let movie) = request else { return false }
            showDetail(movie)
            return true
        }
    }

    /// Pushes the page of `movie` unless the page pushed last is already that film's.
    private func showDetail(_ movie: DBVODStream) {
        guard !BrowseDetailPresence.shared.contains(.init(playlistId: playlist.id, type: "vod", streamId: movie.streamId)) else { return }
        guard pendingMovieDetail?.streamId != movie.streamId else { return }
        pendingMovieDetail = movie
    }

    private func shelfList(_ shelves: ShelfList) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                ContinueWatchingRow(
                    playlist: playlist,
                    typeFilter: "vod",
                    destination: {
                        WatchHistoryListView(playlist: playlist, typeFilter: "vod") { item in
                            presentHistoryPlayer(item)
                        }
                    },
                    onPlay: { item in
                        presentHistoryPlayer(item)
                    }
                )

                if shelves.reservesRecentlyAdded || !shelves.recentlyAdded.isEmpty {
                    RecentlyAddedVODShelf(
                        playlist: playlist,
                        items: shelves.recentlyAdded,
                        containerWidth: shelfWidth
                    )
                    .equatable()
                }

                LazyVStack(spacing: 0) {
                    ForEach(shelves.categories) { category in
                        VODCategoryShelfRow(
                            playlist: playlist,
                            category: category,
                            items: shelves.itemsByCategory[category.id] ?? [],
                            isStreamsLoading: shelves.isStreamsLoading,
                            containerWidth: shelfWidth
                        )
                        .equatable()
                        .id(category.id)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
            .refreshable {
                // Bağımsız Task: refreshable iptali isteklere yayılmasın (bkz. LiveStreamsView).
                let work = Task { await contentStore.refreshFromNetwork(playlist: playlist, only: .vod) }
                await work.value
            }
            .onChange(of: pendingScrollTarget) { _, target in
                guard let target else { return }
                // A jump, not a glide: an animated scroll draws every lazy shelf it
                // passes, and each of those starts loading its posters.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// Brings `searchShelves` and `recentBackfill` in line with `key`. The key is marked
    /// as applied only once a result was assigned: a run that was cancelled half way
    /// (the tab went away) has to happen again when the view is back.
    private func refresh(for key: VODCatalogKey) async {
        guard key != appliedKey else { return }
        guard playlist.id == contentStore.activePlaylistId else {
            searchShelves = nil
            recentBackfill = nil
            appliedKey = key
            return
        }
        if key.streamsLoaded {
            // The candidates are published together with the streams, so this is the
            // answer of a complete load, kept for the first frames of the next one.
            RecentlyAddedReservation.remember(
                !contentStore.recentVODCandidates.isEmpty,
                playlistId: playlist.id,
                type: "vod"
            )
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")
        let categories = visibleCategories(hidden: hidden)
        let query = key.query.trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else {
            searchShelves = nil
            guard await backfillRecentlyAdded(visible: categories, hidden: hidden) else { return }
            appliedKey = key
            return
        }

        let itemsByCategory = contentStore.vodStreamsByCategoryId
        let isStreamsLoading = !contentStore.streamsLoaded && itemsByCategory.isEmpty
        // Ağır metin araması arka planda
        let match = await CatalogTextSearch.detached {
            VODShelfSearch.shelves(matching: query, categories: categories, itemsByCategory: itemsByCategory)
        }
        guard !Task.isCancelled, var match else { return }
        match.isStreamsLoading = isStreamsLoading
        searchShelves = match
        appliedKey = key
    }

    /// Fills `recentBackfill` when the store's candidates were used up by hidden
    /// categories. The result is kept per catalog revision and hidden set, so leaving
    /// a search does not compute it again. Returns false when the task was cancelled.
    private func backfillRecentlyAdded(visible categories: [DBCategory], hidden: Set<String>) async -> Bool {
        let candidates = contentStore.recentVODCandidates
        let shelf = VODRecentlyAdded.shelfItems(from: candidates, hidden: hidden)
        guard VODRecentlyAdded.isCutShort(shelfCount: shelf.count, candidateCount: candidates.count) else {
            recentBackfill = nil
            return true
        }
        let key = recentKey
        if recentBackfill?.key == key { return true }
        let streams = contentStore.vodStreams
        let visibleIds = Set(categories.map(\.id))
        let items = await CatalogTextSearch.detached {
            VODRecentlyAdded.newest(in: streams, visibleCategoryIds: visibleIds)
        }
        guard !Task.isCancelled else { return false }
        recentBackfill = RecentBackfill(key: key, items: items)
        return true
    }

    private func presentHistoryPlayer(_ item: DBWatchHistory) {
        let streamIdInt = Int(item.streamId) ?? 0
        Task {
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(vod: playlist.id, streamId: streamIdInt)
            )
            // İndirilmiş dosya varsa queue'yu atla, local dosyadan oyna.
            var queued: VODHistoryQueue.Match?
            if localURL == nil {
                // The film can sit in the last of several hundred buckets (or in none):
                // that scan does not belong on the main actor between tap and player.
                let buckets = contentStore.vodStreamsByCategoryId
                queued = await Task.detached(priority: .userInitiated) {
                    VODHistoryQueue.locate(streamId: streamIdInt, in: buckets)
                }.value
            }
            presentHistoryPlayer(item, localOverrideURL: localURL, queued: queued)
        }
    }

    private func presentHistoryPlayer(_ item: DBWatchHistory, localOverrideURL: URL?, queued: VODHistoryQueue.Match?) {
        let navigateToDetail: (String, String) -> Void = { type, id in
            Task {
                if type == "vod", let vId = Int(id),
                   let movie = try? await AppDatabase.shared.read({ db in
                    try DBVODStream.filter(Column("streamId") == vId && Column("playlistId") == playlist.id).fetchOne(db)
                }) {
                    await MainActor.run {
                        playerOverlay.injected?.dismiss()
                        showDetail(movie)
                    }
                }
            }
        }

        if let queued {
            playerOverlay.injected?.present(playlistId: playlist.id) {
                VODPlayerShell(
                    playlist: playlist,
                    queue: queued.queue,
                    initialMovie: queued.movie,
                    // A finished film starts over instead of reopening in its last seconds.
                    initialResumeMs: item.resumePositionMs(as: .film),
                    onNavigateToDetail: navigateToDetail
                )
            }
            return
        }

        let url: URL? = localOverrideURL ?? buildURL(for: item)
        guard let url else { return }
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
                resumeTimeMs: item.resumePositionMs(as: .film),
                containerExtension: item.containerExtension,
                onNavigateToDetail: navigateToDetail
            )
        }
    }

    private func buildURL(for item: DBWatchHistory) -> URL? {
        let builder = PlaybackURLBuilder(playlist: playlist)
        // VOD tab olduğu için vod varsayımı (zaten typeFilter: "vod" ile çekiyoruz)
        let streamIdInt = Int(item.streamId) ?? 0
        return builder.movieURL(streamId: streamIdInt, containerExtension: item.containerExtension)
    }
}

// MARK: - Shelf data

/// What the Movies home has to show for a given state of the catalog store.
nonisolated enum VODHomeStatus: Equatable {
    /// Nothing to draw yet: the playlist is being opened or its catalog downloaded.
    case preparing
    case failed(String)
    /// The catalog is loaded and has no category the user has not hidden.
    case noCategory
    /// `isStreamsLoading`: the categories are known and the movies are not.
    case shelves(isStreamsLoading: Bool)

    /// `hasItems` is whether the store holds any movie list. A reload keeps the old
    /// lists in place while `streamsLoaded` is down, and that is no reason to blank
    /// shelves that have something to show; a load error only replaces the shelves
    /// when it left them without content.
    static func resolve(
        isActivePlaylist: Bool,
        isLoading: Bool,
        loadError: String?,
        streamsLoaded: Bool,
        hasItems: Bool,
        hasVisibleCategories: Bool
    ) -> VODHomeStatus {
        guard isActivePlaylist else { return .preparing }
        let isStreamsLoading = !streamsLoaded && !hasItems
        if isStreamsLoading, !isLoading, let loadError { return .failed(loadError) }
        guard hasVisibleCategories else {
            if isLoading { return .preparing }
            if let loadError { return .failed(loadError) }
            // "No category" is only true once the streams are in: they can still
            // bring the "uncategorized" shelf.
            return streamsLoaded ? .noCategory : .preparing
        }
        return .shelves(isStreamsLoading: isStreamsLoading)
    }
}

/// Text search over the shelves of the Movies home.
nonisolated enum VODShelfSearch {
    nonisolated struct Match: Sendable {
        var categories: [DBCategory] = []
        var itemsByCategory: [String: [VODWithCategory]] = [:]
        /// Set by the caller: the search ran before the movies were in.
        var isStreamsLoading = false
    }

    /// How many names are tested between two looks at the task's cancellation flag.
    private static let cancellationStride = 2048

    /// Keeps the shelf layout: a category whose name matches stays whole, any other
    /// keeps the movies whose name matches and drops out when none does.
    /// Meant to run inside `CatalogTextSearch.detached`: returns nil once the task is
    /// cancelled, so a search superseded by the next keystroke stops scanning.
    static func shelves(
        matching search: String,
        categories: [DBCategory],
        itemsByCategory: [String: [VODWithCategory]]
    ) -> Match? {
        let query = CatalogTextSearch.Query(search)
        var match = Match()
        for category in categories {
            if Task.isCancelled { return nil }
            let items = itemsByCategory[category.id] ?? []
            if query.matches(category.name) {
                match.categories.append(category)
                match.itemsByCategory[category.id] = items
                continue
            }
            var hits: [VODWithCategory] = []
            for (offset, item) in items.enumerated() {
                if offset % cancellationStride == cancellationStride - 1, Task.isCancelled { return nil }
                if query.matches(item.stream.name) { hits.append(item) }
            }
            if !hits.isEmpty {
                match.categories.append(category)
                match.itemsByCategory[category.id] = hits
            }
        }
        return match
    }
}

/// The "recently added" shelf of the Movies home.
nonisolated enum VODRecentlyAdded {
    static let shelfLimit = 20

    /// The newest movies of the categories on screen. `candidates` are the store's:
    /// newest first and only from listed categories, so dropping the hidden ones is all
    /// that is left, and that is cheap enough for a body pass.
    static func shelfItems(from candidates: [DBVODStream], hidden: Set<String>) -> [DBVODStream] {
        guard !hidden.isEmpty else { return Array(candidates.prefix(shelfLimit)) }
        var items: [DBVODStream] = []
        for candidate in candidates where !hidden.contains(candidate.categoryId ?? "") {
            items.append(candidate)
            if items.count == shelfLimit { break }
        }
        return items
    }

    /// Whether hidden categories used up the store's candidate list before the shelf
    /// was full. Only then can older movies of the visible categories be missing, and
    /// only then is a pass over the whole catalog worth its cost.
    static func isCutShort(shelfCount: Int, candidateCount: Int) -> Bool {
        shelfCount < shelfLimit && candidateCount >= PlaylistContentStore.recentCandidateLimit
    }

    /// The shelf computed from the whole catalog, by the store's own rule: a numeric
    /// `added`, newest first, equal timestamps in catalog order. The store's candidates
    /// are a prefix of this list, so swapping one for the other only adds at the end.
    static func newest(in streams: [VODWithCategory], visibleCategoryIds: Set<String>) -> [DBVODStream] {
        PlaylistContentStore.newestIndices(count: streams.count, limit: shelfLimit) { index in
            let stream = streams[index].stream
            guard visibleCategoryIds.contains(stream.categoryId ?? "") else { return nil }
            return stream.added.flatMap { Int($0) }
        }.map { streams[$0].stream }
    }
}

/// Whether a home screen keeps the place of its "recently added" shelf while the
/// catalog of a playlist is still loading. Answered from the playlist's last complete
/// load: a panel that sends no dates never fills the shelf, and a slot held for it
/// would vanish under the category shelves once the catalog is in. A playlist that was
/// never loaded holds no place; its shelf appears once, with the movies.
enum RecentlyAddedReservation {
    private static func key(playlistId: UUID, type: String) -> String {
        "browse.recentReserved.\(type).\(playlistId.uuidString)"
    }

    /// `type` is the content type of the shelf, "vod" or "series".
    static func isReserved(playlistId: UUID, type: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(playlistId: playlistId, type: type))
    }

    /// Records whether the load that just completed had anything to put on the shelf.
    /// Writes only when the answer changed, since every completed recompute calls it.
    static func remember(_ hasRecents: Bool, playlistId: UUID, type: String, defaults: UserDefaults = .standard) {
        let key = key(playlistId: playlistId, type: type)
        guard defaults.bool(forKey: key) != hasRecents else { return }
        if hasRecents {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Drops the flags of a deleted playlist.
    static func forget(playlistId: UUID, defaults: UserDefaults = .standard) {
        for type in ["vod", "series"] {
            defaults.removeObject(forKey: key(playlistId: playlistId, type: type))
        }
    }
}

/// Finds the play queue of a film opened from the watch history.
nonisolated enum VODHistoryQueue {
    typealias Match = (movie: DBVODStream, queue: [DBVODStream])

    /// The film and the rest of its category, in catalog order. Nil when the film is no
    /// longer in the catalog; it is then played on its own.
    static func locate(streamId: Int, in buckets: [String: [VODWithCategory]]) -> Match? {
        for items in buckets.values {
            if let found = items.first(where: { $0.stream.streamId == streamId }) {
                return (found.stream, items.map(\.stream))
            }
        }
        return nil
    }
}

private enum VODCategoryShelf {
    static let cardSpacing: CGFloat = 14
    static let horizontalInset: CGFloat = 16
}

/// Stand-in for the cards of a shelf whose movies are not in yet. It is built like the
/// loaded strip (same stack, insets and height), so nothing below it moves when the
/// cards replace it, and its tiles are the ones a poster shows while it downloads.
private struct VODShelfPlaceholder: View {
    let containerWidth: CGFloat

    @Environment(\.posterMetrics) private var posterMetrics

    private var cardCount: Int {
        let stride = posterMetrics.shelfPosterWidth + VODCategoryShelf.cardSpacing
        guard stride > 0, containerWidth > 0, containerWidth.isFinite else { return 4 }
        return min(12, max(3, Int((containerWidth / stride).rounded(.up))))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: VODCategoryShelf.cardSpacing) {
                ForEach(0..<cardCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                        .frame(width: posterMetrics.shelfPosterWidth, height: posterMetrics.shelfPosterHeight)
                }
            }
            .padding(.horizontal, VODCategoryShelf.horizontalInset)
        }
        .posterShelfFrame()
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Recently Added shelf

struct RecentlyAddedVODShelf: View, Equatable {
    let playlist: Playlist
    /// Empty while the movies are not known yet: the shelf then holds its place with a
    /// placeholder. The home view does not show it at all when there is nothing to add.
    let items: [DBVODStream]
    var containerWidth: CGFloat = 0

    static func == (lhs: RecentlyAddedVODShelf, rhs: RecentlyAddedVODShelf) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.items == rhs.items &&
        lhs.containerWidth == rhs.containerWidth
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(L("recently_added.title")) {
                RecentlyAddedVODDetailView(playlist: playlist, items: items)
            }
            .disabled(items.isEmpty)

            if items.isEmpty {
                VODShelfPlaceholder(containerWidth: containerWidth)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: VODCategoryShelf.cardSpacing) {
                        ForEach(items) { stream in
                            NavigationLink {
                                MovieDetailView(playlist: playlist, movie: stream, queue: items)
                                    .posterZoomDestination(id: stream.streamId, in: zoom)
                            } label: {
                                VODStreamCard(
                                    playlistId: playlist.id,
                                    stream: stream,
                                    posterWidth: posterMetrics.shelfPosterWidth,
                                    posterHeight: posterMetrics.shelfPosterHeight,
                                    imageLoadProfile: .shelf,
                                    zoomNamespace: zoom
                                )
                            }
                            .vodCardInteractions(streamId: stream.streamId, playlistId: playlist.id)
                        }
                    }
                    .padding(.horizontal, VODCategoryShelf.horizontalInset)
                }
                .posterShelfFrame()
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Recently Added Detail View
struct RecentlyAddedVODDetailView: View {
    let playlist: Playlist
    let items: [DBVODStream]

    private var wrapped: [VODWithCategory] {
        items.map { VODWithCategory(stream: $0, categoryName: "") }
    }

    var body: some View {
        // Newest first is what the title promises, so the stored sort does not apply
        // here; and a list of twenty needs no search field.
        VODCategoryContent(playlist: playlist, items: wrapped, allowsSorting: false)
            .equatable()
            .navigationTitle(L("recently_added.title"))
            .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Category shelf

struct VODCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [VODWithCategory]
    var isStreamsLoading: Bool = false
    /// Width of the list the shelf sits in: how many posters fit decides how many are
    /// warmed up, and how many tiles the placeholder draws.
    var containerWidth: CGFloat = 0

    static func == (lhs: VODCategoryShelfRow, rhs: VODCategoryShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.category == rhs.category &&
        lhs.items == rhs.items &&
        lhs.isStreamsLoading == rhs.isStreamsLoading &&
        lhs.containerWidth == rhs.containerWidth
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(category.name) {
                VODCategoryDetailView(playlist: playlist, category: category)
            }
            .accessibilityIdentifier("home.shelf.header.\(category.id)")
            .contextMenu {
                HideCategoryMenuButton(categoryId: category.id, type: "vod", playlistId: playlist.id)
            }

            if items.isEmpty {
                if isStreamsLoading {
                    VODShelfPlaceholder(containerWidth: containerWidth)
                } else {
                    Text(L("vod.empty.no_in_category"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, VODCategoryShelf.horizontalInset)
                }
            } else {
                // Kuyruğu raf başına BİR kez kur: NavigationLink destination'ı hücre
                // render'ında değerlendirilir; items.map'i içeride bırakmak her yeni
                // hücrede tüm kategoriyi kopyalıyordu (O(N²) scroll maliyeti).
                let queue = items.map(\.stream)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: VODCategoryShelf.cardSpacing) {
                        ForEach(items) { item in
                            NavigationLink {
                                MovieDetailView(playlist: playlist, movie: item.stream, queue: queue)
                                    .posterZoomDestination(id: item.stream.streamId, in: zoom)
                            } label: {
                                VODStreamCard(
                                    playlistId: playlist.id,
                                    stream: item.stream,
                                    posterWidth: posterMetrics.shelfPosterWidth,
                                    posterHeight: posterMetrics.shelfPosterHeight,
                                    imageLoadProfile: .shelf,
                                    zoomNamespace: zoom
                                )
                            }
                            .vodCardInteractions(streamId: item.stream.streamId, playlistId: playlist.id)
                        }
                    }
                    .padding(.horizontal, VODCategoryShelf.horizontalInset)
                }
                .posterShelfFrame()
                .onAppear { movePrefetch(to: headPrefetch) }
                // A shelf that scrolled away during a fling would otherwise keep
                // downloading posters nobody is looking at.
                .onDisappear { movePrefetch(to: nil) }
                .onChange(of: headPrefetch) { _, head in
                    guard queuedPrefetch != nil else { return }
                    movePrefetch(to: head)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @State private var queuedPrefetch: SeriesBrowse.HeadPrefetch?

    private var headPrefetch: SeriesBrowse.HeadPrefetch {
        let headCount = ListImagePrefetch.headCount(
            itemWidth: posterMetrics.shelfPosterWidth,
            spacing: VODCategoryShelf.cardSpacing,
            containerWidth: containerWidth
        )
        let urls = items.prefix(headCount)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        return SeriesBrowse.HeadPrefetch(urls: urls, width: posterMetrics.shelfPosterWidth,
                                        height: posterMetrics.shelfPosterHeight)
    }

    private func movePrefetch(to head: SeriesBrowse.HeadPrefetch?) {
        let change = SeriesBrowse.prefetchChange(from: queuedPrefetch, to: head)
        if let stop = change.stop {
            ListImagePrefetch.stop(urls: stop.urls, width: stop.width, height: stop.height,
                                   contentMode: .fill, loadProfile: .shelf)
        }
        if let start = change.start {
            ListImagePrefetch.start(urls: start.urls, width: start.width, height: start.height,
                                    contentMode: .fill, loadProfile: .shelf)
        }
        queuedPrefetch = head
    }
}

struct VODStreamCard: View {
    let playlistId: UUID
    let stream: DBVODStream
    var categoryName: String? = nil
    var posterWidth: CGFloat = 160
    var posterHeight: CGFloat = 240
    var imageLoadProfile: ImageLoadProfile = .standard
    /// Kart başına @Query açmak yerine üst view'dan geçilir (nil = progress bar gizli)
    var watchProgress: Double? = nil
    /// The namespace of the link that pushes the detail page, which zooms out of the poster.
    var zoomNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            artwork
                .cardHover(cornerRadius: BrowseMetrics.posterCornerRadius)

            Text(stream.name)
                .posterTitleStyle(width: posterWidth)

            if let catName = categoryName {
                Text(catName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: posterWidth, alignment: .leading)
            }
        }
        .posterAccessibility(title: stream.name, rating: stream.rating,
                             category: categoryName, progress: watchProgress)
    }

    @ViewBuilder
    private var artwork: some View {
        if let zoomNamespace {
            poster.posterZoomSource(id: stream.streamId, in: zoomNamespace)
        } else {
            poster
        }
    }

    private var poster: some View {
        ZStack(alignment: .topTrailing) {
            CachedImage(
                url: stream.streamIcon.flatMap { URL(string: $0) },
                width: posterWidth,
                height: posterHeight,
                contentMode: SwiftUI.ContentMode.fill,
                iconName: "film",
                loadProfile: imageLoadProfile
            )


            PosterRatingBadge(rating: stream.rating)
                .padding(6)
        }
        .overlay(alignment: .bottom) {
            if let progress = watchProgress, progress > 0 {
                CardProgressBar(fraction: progress).padding(6)
            }
        }
    }
}

extension View {
    /// Press feedback, favourite menu and test identifier of a movie card's link.
    fileprivate func vodCardInteractions(streamId: Int, playlistId: UUID) -> some View {
        self
            .buttonStyle(.cardPress)
            .cardContextMenuShape(cornerRadius: BrowseMetrics.posterCornerRadius)
            .contextMenu {
                FavoriteMenuButton(streamId: streamId, type: "vod", playlistId: playlistId)
            }
            .accessibilityIdentifier("card.vod.\(streamId)")
    }
}

// MARK: - Category Detail View
struct VODCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// Ranked hits of the current search. Without a search the grid gets the store's
    /// list for this category as it is: no copy, no task, and it is there in the first
    /// frame of the push.
    @State private var searchResults: [VODWithCategory]?
    @State private var appliedKey: VODCatalogKey?

    var body: some View {
        let isActive = playlist.id == contentStore.activePlaylistId
        let bucket = isActive ? (contentStore.vodStreamsByCategoryId[category.id] ?? []) : []
        let isSearching = !debouncedQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let key = VODCatalogKey(
            query: debouncedQuery,
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.vodRevision,
            hiddenVersion: 0,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
        VODCategoryContent(
            playlist: playlist,
            // Until the first hits of a search are in, the full list stays up.
            items: isSearching ? (searchResults ?? bucket) : bucket,
            isSourceLoading: !isActive || (bucket.isEmpty && !contentStore.streamsLoaded)
        )
        .equatable()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("vod.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                debouncedQuery = ""
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .task(id: key) { await search(for: key) }
    }

    private func search(for key: VODCatalogKey) async {
        guard key != appliedKey else { return }
        let q = key.query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, playlist.id == contentStore.activePlaylistId else {
            searchResults = nil
            appliedKey = key
            return
        }
        let base = contentStore.vodStreamsByCategoryId[category.id] ?? []
        let result = await CatalogTextSearch.detached {
            CatalogTextSearch.rankedFilter(base, search: q) { $0.stream.name }
        }
        // A cancelled scan returns an empty list, which must not pass for "no hits".
        guard !Task.isCancelled else { return }
        searchResults = result
        appliedKey = key
    }
}

struct VODCategoryContent: View, Equatable {
    let playlist: Playlist
    let items: [VODWithCategory]
    /// The list `items` is taken from is not complete yet (the catalog is still loading,
    /// or the parent's own filter has not finished), so an empty `items` does not mean
    /// that there are no movies.
    var isSourceLoading: Bool = false
    /// Off for a list whose order is its point ("Recently Added"): the stored sort is
    /// ignored and the menu offers the filter only.
    var allowsSorting: Bool = true

    /// Cheap signature compare so a parent re-render (e.g. a metadata
    /// @Published storm) doesn't force SwiftUI to re-process a 10k-item view — that
    /// scaled with catalog size and froze "All Movies" for seconds on return.
    /// Internal @State/@Query updates still invalidate normally, independent of this.
    static func == (lhs: VODCategoryContent, rhs: VODCategoryContent) -> Bool {
        lhs.playlist.id == rhs.playlist.id
            && lhs.items.count == rhs.items.count
            && lhs.items.first?.stream.streamId == rhs.items.first?.stream.streamId
            && lhs.items.last?.stream.streamId == rhs.items.last?.stream.streamId
            && lhs.isSourceLoading == rhs.isSourceLoading
            && lhs.allowsSorting == rhs.allowsSorting
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Query<WatchProgressMapRequest> private var progressMap: [String: Double]
    @Namespace private var zoom

    @AppStorage(VODSortOption.storageKey) private var sortOption: VODSortOption = .defaultOrder
    /// Screen-local: file types are specific to the currently shown list, so this
    /// intentionally does not persist across screens.
    @State private var fileTypeFilter: Set<String> = []
    /// Sort/filter output, recomputed off the main thread on input changes so large
    /// lists (e.g. "All Movies") don't re-sort on every body pass (watch-progress ticks).
    /// Not what is drawn in the identity case, see `body`.
    @State private var displayItems: [VODWithCategory] = []
    /// Prebuilt play queue matching `displayItems`, so body passes don't re-map a
    /// large array on every render (critical for "All Movies" with 10k+ items).
    @State private var streamQueue: [DBVODStream] = []
    /// File types present in the full list, precomputed to keep the menu O(1) to build.
    @State private var fileTypes: [String] = []
    /// Number of cells currently rendered. Paginated so a 10k-item catalog doesn't
    /// build one giant ForEach (froze on first load and when scrolling to the end).
    @State private var visibleCount = Self.pageSize
    /// The inputs the three computed states above belong to. Coming back from a film
    /// restarts the task with the same key; that must neither sort again nor touch the
    /// page count, or the grid would collapse to its first page under the user.
    @State private var appliedKey: InputKey?
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private static let pageSize = 90

    /// What the sorted list, the play queue and the file types are computed from.
    private nonisolated struct InputKey: Equatable {
        let items: Int
        let sort: VODSortOption
        let fileTypes: Set<String>

        /// Default order and no filter: the list to show is `items` itself.
        var isIdentity: Bool { sort == .defaultOrder && fileTypes.isEmpty }
    }

    init(playlist: Playlist, items: [VODWithCategory], isSourceLoading: Bool = false, allowsSorting: Bool = true) {
        self.playlist = playlist
        self.items = items
        self.isSourceLoading = isSourceLoading
        self.allowsSorting = allowsSorting
        _progressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "vod"), in: \.appDatabase)
    }

    private var categoryGridColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: posterMetrics.categoryGridPosterWidth),
            spacing: posterMetrics.gridSpacing,
            alignment: .top
        )]
    }

    /// Cheap O(1) change signal for `items`; avoids O(n) array equality in `.task(id:)`
    /// on every update pass, which froze navigation on huge lists.
    private var itemsToken: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.stream.streamId)
        hasher.combine(items.last?.stream.streamId)
        return hasher.finalize()
    }

    private var effectiveSort: VODSortOption {
        allowsSorting ? sortOption : .defaultOrder
    }

    private var inputKey: InputKey {
        InputKey(items: itemsToken, sort: effectiveSort, fileTypes: fileTypeFilter)
    }

    private var isFilterActive: Bool {
        effectiveSort != .defaultOrder || !fileTypeFilter.isEmpty
    }

    private func recompute(for key: InputKey) async {
        let interval = BrowsePerformance.begin("VODGridRecompute")
        defer { BrowsePerformance.end("VODGridRecompute", interval) }
        guard key != appliedKey else { return }
        let source = items
        let computed = await CatalogTextSearch.detached { () -> (items: [VODWithCategory], queue: [DBVODStream], fileTypes: [String])? in
            let sorted = key.sort.apply(to: VODFileType.filter(source, selection: key.fileTypes))
            if Task.isCancelled { return nil }
            let queue = sorted.map(\.stream)
            if Task.isCancelled { return nil }
            // Options come from the full list so toggling one doesn't hide the others.
            return (sorted, queue, VODFileType.available(in: source))
        }
        guard !Task.isCancelled, let computed else { return }
        displayItems = computed.items
        streamQueue = computed.queue
        fileTypes = computed.fileTypes
        // The new order goes on screen with this assignment, so the page count and the
        // scroll offset follow in the same update. In the identity case the list was
        // swapped (and the position reset) when the key changed, see `body`.
        if !key.isIdentity { showFirstPage() }
        appliedKey = key
        prefetch(computed.items)
    }

    /// One page, from the top: where a list in a new order starts.
    private func showFirstPage() {
        visibleCount = Self.pageSize
        scrollPosition.scrollTo(edge: .top)
    }

    private func loadMore(upTo count: Int) {
        guard visibleCount < count else { return }
        visibleCount = min(visibleCount + Self.pageSize, count)
    }

    var body: some View {
        let key = inputKey
        let isComputed = appliedKey == key
        // With the default order and no filter the sorted list is `items` itself, so it
        // is drawn directly: the grid is there in the first frame of a push instead of
        // after a round trip through a background task. Any other order shows the last
        // computed list until the new one is ready.
        let shown = key.isIdentity ? items : displayItems
        Group {
            if !shown.isEmpty {
                // The queue of another list would send previous / next to the wrong
                // films; until this one's is built a film opens on its own.
                grid(shown, queue: isComputed ? streamQueue : [])
            } else if isSourceLoading || !(key.isIdentity || isComputed) {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CatalogEmptyView(.noItems(title: L("vod.empty.no_movie"), systemImage: "film"))
            }
        }
        .toolbar {
            // Without the sort picker the menu only has the file types to offer, and
            // those need at least two to choose from.
            if allowsSorting || fileTypes.count > 1 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    sortFilterMenu
                }
            }
        }
        .task(id: key) { await recompute(for: key) }
        .onChange(of: key) { _, new in
            // The identity list is on screen as soon as the key changes (a search
            // narrowed `items`, or the sort went back to default), so this is the
            // update in which the content is swapped.
            if new.isIdentity { showFirstPage() }
        }
    }

    private func grid(_ shown: [VODWithCategory], queue: [DBVODStream]) -> some View {
        ScrollView {
            LazyVGrid(columns: categoryGridColumns, spacing: posterMetrics.gridRowSpacing) {
                ForEach(Indexed(shown.prefix(visibleCount)), id: \.element.stream.streamId) { index, item in
                    NavigationLink {
                        MovieDetailView(playlist: playlist, movie: item.stream, queue: queue)
                            .posterZoomDestination(id: item.stream.streamId, in: zoom)
                    } label: {
                        VODStreamCard(
                            playlistId: playlist.id,
                            stream: item.stream,
                            posterWidth: posterMetrics.categoryGridPosterWidth,
                            posterHeight: posterMetrics.categoryGridPosterHeight,
                            imageLoadProfile: .grid,
                            watchProgress: progressMap[String(item.stream.streamId)],
                            zoomNamespace: zoom
                        )
                    }
                    .vodCardInteractions(streamId: item.stream.streamId, playlistId: playlist.id)
                    // Load the next page while cells near the end scroll into view.
                    // Triggered from inside the lazy grid so onAppear is reliable.
                    .onAppear { if index >= visibleCount - 15 { loadMore(upTo: shown.count) } }
                }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
    }

    private var sortFilterMenu: some View {
        Menu {
            if allowsSorting {
                Picker(L("sort.title"), selection: $sortOption) {
                    ForEach(VODSortOption.allCases) { option in
                        Label(L(option.titleKey), systemImage: option.systemImage).tag(option)
                    }
                }
            }

            if fileTypes.count > 1 {
                Section(L("filter.file_type")) {
                    ForEach(fileTypes, id: \.self) { ext in
                        Toggle(ext.uppercased(), isOn: fileTypeBinding(ext))
                    }
                    // Several types can be ticked in one go; choosing a sort or
                    // clearing the filter still closes the menu.
                    .menuActionDismissBehavior(.disabled)

                    if !fileTypeFilter.isEmpty {
                        Button {
                            fileTypeFilter.removeAll()
                        } label: {
                            Label(L("filter.clear"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
        } label: {
            Label(L(allowsSorting ? "sort.title" : "filter.title"), systemImage: sortFilterSymbol)
        }
    }

    private var sortFilterSymbol: String {
        if isFilterActive { return "line.3.horizontal.decrease.circle.fill" }
        // The iOS 26 bar draws its items inside a circle of its own.
        if #available(iOS 26, *) { return "line.3.horizontal.decrease" }
        return "line.3.horizontal.decrease.circle"
    }

    private func fileTypeBinding(_ ext: String) -> Binding<Bool> {
        Binding(
            get: { fileTypeFilter.contains(ext) },
            set: { isOn in
                if isOn {
                    fileTypeFilter.insert(ext)
                } else {
                    fileTypeFilter.remove(ext)
                }
            }
        )
    }

    private func prefetch(_ list: [VODWithCategory]) {
        // Only the head is ever prefetched (start() caps to maxBatch); building URLs
        // for the whole 10k list first would be wasted O(n) work on the main thread.
        let urls = list.prefix(ListImagePrefetch.maxBatch)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(
            urls: urls,
            width: posterMetrics.categoryGridPosterWidth,
            height: posterMetrics.categoryGridPosterHeight,
            contentMode: .fill,
            loadProfile: .grid
        )
    }
}

// MARK: - All Movies (flat, sortable/filterable browse)

/// Flat grid of every movie across categories. Reuses `VODCategoryContent`, so it
/// inherits the sort menu and file-type filter for free.
struct AllVODView: View {
    let playlist: Playlist

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// The catalog without the hidden categories, narrowed and ranked by the search.
    /// Nil until it was computed once, and whenever the store's own list is what the
    /// screen shows.
    @State private var filtered: [VODWithCategory]?
    @State private var appliedKey: VODCatalogKey?

    var body: some View {
        let isActive = playlist.id == contentStore.activePlaylistId
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")
        let isSearching = !debouncedQuery.trimmingCharacters(in: .whitespaces).isEmpty
        // Nothing hidden and nothing searched for: the list is the store's own array.
        // Handing it on as it is shares one buffer instead of filtering a six-figure
        // catalog into a second one, and the grid is there in the first frame.
        let showsWholeCatalog = hidden.isEmpty && !isSearching
        let items = catalogItems(isActive: isActive, showsWholeCatalog: showsWholeCatalog, nothingHidden: hidden.isEmpty)
        let key = VODCatalogKey(
            query: debouncedQuery,
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.vodRevision,
            hiddenVersion: hiddenStore.version,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
        VODCategoryContent(
            playlist: playlist,
            items: items,
            isSourceLoading: items.isEmpty
                && (!isActive || !contentStore.streamsLoaded || (!showsWholeCatalog && filtered == nil))
        )
        .equatable()
        .navigationTitle(L("browse.all_movies"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("vod.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                debouncedQuery = ""
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .task(id: key) { await recompute(for: key) }
    }

    private func catalogItems(isActive: Bool, showsWholeCatalog: Bool, nothingHidden: Bool) -> [VODWithCategory] {
        guard isActive else { return [] }
        if showsWholeCatalog { return contentStore.vodStreams }
        if let filtered { return filtered }
        // The first search is still running: the full list stays up until its hits are
        // in. With hidden categories there is no list yet that may be shown.
        return nothingHidden ? contentStore.vodStreams : []
    }

    private func recompute(for key: VODCatalogKey) async {
        let interval = BrowsePerformance.begin("VODCatalogRecompute")
        defer { BrowsePerformance.end("VODCatalogRecompute", interval) }
        guard key != appliedKey else { return }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")
        let q = key.query.trimmingCharacters(in: .whitespaces)
        guard playlist.id == contentStore.activePlaylistId, !(hidden.isEmpty && q.isEmpty) else {
            filtered = nil
            appliedKey = key
            return
        }
        let source = contentStore.vodStreams
        // Everything (hidden-filter, search, relevance sort) runs off the main thread —
        // the catalog can be hundreds of thousands of rows, so even the hidden-filter
        // is too heavy to run on-main (it froze the "All" screen on open).
        let result = await CatalogTextSearch.detached {
            let base = hidden.isEmpty ? source : source.filter { !hidden.contains($0.stream.categoryId ?? "") }
            return CatalogTextSearch.rankedFilter(base, search: q) { $0.stream.name }
        }
        // A cancelled scan returns an empty list, which must not pass for "no hits".
        guard !Task.isCancelled else { return }
        filtered = result
        appliedKey = key
    }
}

// MARK: - VOD Player Shell

/// Film listesinden açılan player; kaynakla aynı kuyrukta önceki/sonraki film desteği sağlar.
struct VODPlayerShell: View {
    let playlist: Playlist
    let queue: [DBVODStream]
    var onNavigateToDetail: ((String, String) -> Void)? = nil
    private let initialMovie: DBVODStream
    private let initialResumeMs: Int?

    @State private var currentMovie: DBVODStream
    @State private var resumeMs: Int?
    @Environment(\.playerOverlayPresentationID) private var overlayPresentationID

    init(
        playlist: Playlist,
        queue: [DBVODStream],
        initialMovie: DBVODStream,
        initialResumeMs: Int?,
        onNavigateToDetail: ((String, String) -> Void)? = nil
    ) {
        self.playlist = playlist
        self.queue = queue
        self.onNavigateToDetail = onNavigateToDetail
        self.initialMovie = initialMovie
        self.initialResumeMs = initialResumeMs
        _currentMovie = State(initialValue: initialMovie)
        _resumeMs = State(initialValue: initialResumeMs)
    }

    private var currentIndex: Int? {
        queue.firstIndex(where: { $0.streamId == currentMovie.streamId })
    }

    var body: some View {
        if let url = PlaybackURLBuilder(playlist: playlist).movieURL(
            streamId: currentMovie.streamId,
            containerExtension: currentMovie.containerExtension
        ) {
            let parts = [currentMovie.genre, currentMovie.releaseDate]
                .compactMap { $0 }.filter { !$0.isEmpty }
            PlayerView(
                url: url,
                title: currentMovie.name,
                subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                artworkURL: currentMovie.streamIcon.flatMap { URL(string: $0) },
                isLiveStream: false,
                playlistId: playlist.id,
                streamId: String(currentMovie.streamId),
                type: "vod",
                resumeTimeMs: resumeMs,
                containerExtension: currentMovie.containerExtension,
                canGoToPreviousChannel: (currentIndex ?? 0) > 0,
                canGoToNextChannel: {
                    guard let idx = currentIndex else { return false }
                    return idx < queue.count - 1
                }(),
                onPreviousChannel: { jump(by: -1) },
                onNextChannel: { jump(by: 1) },
                onNavigateToDetail: onNavigateToDetail
            )
            .onChange(of: overlayPresentationID) { _, _ in
                applyInitialSelectionIfNeeded()
            }
        }
    }

    private func applyInitialSelectionIfNeeded() {
        guard currentMovie.streamId != initialMovie.streamId
                || resumeMs != initialResumeMs else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            currentMovie = initialMovie
            resumeMs = initialResumeMs
        }
    }

    private func jump(by offset: Int) {
        guard let idx = currentIndex else { return }
        let newIdx = idx + offset
        guard newIdx >= 0, newIdx < queue.count else { return }
        let movie = queue[newIdx]
        Task {
            let history = try? await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(
                        Column("streamId") == String(movie.streamId)
                            && Column("playlistId") == playlist.id
                            && Column("type") == "vod"
                    )
                    .fetchOne(db)
            }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                currentMovie = movie
                // Previous / next in the film queue: a finished film starts over.
                resumeMs = history?.resumePositionMs(as: .film)
            }
        }
    }
}
