import SwiftUI
import GRDBQuery
import GRDB

struct VODView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

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

    // Filtreleme sonuçları arka planda hesaplanır, main thread'e sadece atama yapılır
    @State private var displayCategories: [DBCategory] = []
    @State private var displayItemsByCategory: [String: [VODWithCategory]] = [:]
    @State private var recentlyAddedVODs: [DBVODStream] = []

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    var body: some View {
        Group {
            if displayCategories.isEmpty {
                if contentStore.isLoading || playlist.id != contentStore.activePlaylistId {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(contentStore.loadingMessage ?? L("vod.empty.preparing"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError = contentStore.loadError, debouncedQuery.isEmpty {
                    CatalogLoadErrorView(message: loadError) {
                        Task { await contentStore.loadPlaylist(playlist) }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "film")
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

                        if !recentlyAddedVODs.isEmpty {
                            RecentlyAddedVODShelf(playlist: playlist, items: recentlyAddedVODs)
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(displayCategories) { category in
                                VODCategoryShelfRow(
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
                    .refreshable {
                        // Bağımsız Task: refreshable iptali isteklere yayılmasın (bkz. LiveStreamsView).
                        let work = Task { await contentStore.refreshFromNetwork(playlist: playlist, only: .vod) }
                        await work.value
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AllVODView(playlist: playlist)
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.body.weight(.semibold))
                }
                .disabled(contentStore.vodStreams.isEmpty)
                .accessibilityLabel(L("browse.all_movies"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCategoryPicker = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.body.weight(.semibold))
                }
                .disabled(contentStore.vodCategories.isEmpty)
                .accessibilityLabel(L("list.jump_to_category"))
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
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: L("vod.search_placeholder"))
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
        .task(id: debouncedQuery) { await recomputeFilter() }
        .task(id: contentStore.streamsLoaded) { await recomputeFilter() }
        .task(id: hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")) { await recomputeFilter() }
        .transaction { $0.animation = nil }
        .navigationDestination(item: $pendingMovieDetail) { movie in
            MovieDetailView(playlist: playlist, movie: movie)
        }
    }

    private func recomputeFilter() async {
        guard playlist.id == contentStore.activePlaylistId else {
            displayCategories = []; displayItemsByCategory = [:]; recentlyAddedVODs = []; return
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")
        let allCats = contentStore.vodCategories.filter { !hidden.contains($0.id) }
        let allByCategory = contentStore.vodStreamsByCategoryId
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayCategories = allCats
            displayItemsByCategory = allByCategory
            let visibleCatIds = Set(allCats.map(\.id))
            let allVODs = contentStore.vodStreams
            recentlyAddedVODs = await Task.detached(priority: .userInitiated) {
                allVODs
                    .lazy
                    .filter { visibleCatIds.contains($0.stream.categoryId ?? "") }
                    .compactMap { vod -> (DBVODStream, Int)? in
                        guard let ts = vod.stream.added.flatMap(Int.init) else { return nil }
                        return (vod.stream, ts)
                    }
                    .sorted { $0.1 > $1.1 }
                    .prefix(20)
                    .map(\.0)
            }.value
            return
        }
        recentlyAddedVODs = []

        // Ağır metin araması arka planda
        let result = await Task.detached(priority: .userInitiated) {
            var cats: [DBCategory] = []
            var byCategory: [String: [VODWithCategory]] = [:]
            for cat in allCats {
                let catMatch = CatalogTextSearch.matches(search: q, text: cat.name)
                let items = allByCategory[cat.id] ?? []
                let filtered = catMatch ? items : items.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
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

    private func presentHistoryPlayer(_ item: DBWatchHistory) {
        let streamIdInt = Int(item.streamId) ?? 0
        Task {
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(vod: playlist.id, streamId: streamIdInt)
            )
            await MainActor.run {
                presentHistoryPlayer(item, localOverrideURL: localURL)
            }
        }
    }

    private func presentHistoryPlayer(_ item: DBWatchHistory, localOverrideURL: URL?) {
        let streamIdInt = Int(item.streamId) ?? 0
        let navigateToDetail: (String, String) -> Void = { type, id in
            Task {
                if type == "vod", let vId = Int(id),
                   let movie = try? await AppDatabase.shared.read({ db in
                    try DBVODStream.filter(Column("streamId") == vId && Column("playlistId") == playlist.id).fetchOne(db)
                }) {
                    await MainActor.run {
                        playerOverlay.dismiss()
                        pendingMovieDetail = movie
                    }
                }
            }
        }

        // İndirilmiş dosya varsa queue'yu atla, local dosyadan oyna.
        if localOverrideURL == nil {
            var queue: [DBVODStream] = []
            var initialMovie: DBVODStream? = nil
            for items in contentStore.vodStreamsByCategoryId.values {
                if let found = items.first(where: { $0.stream.streamId == streamIdInt }) {
                    initialMovie = found.stream
                    queue = items.map(\.stream)
                    break
                }
            }

            if let movie = initialMovie, !queue.isEmpty {
                playerOverlay.present(playlistId: playlist.id) {
                    VODPlayerShell(
                        playlist: playlist,
                        queue: queue,
                        initialMovie: movie,
                        // A finished film starts over instead of reopening in its last seconds.
                        initialResumeMs: item.resumePositionMs(as: .film),
                        onNavigateToDetail: navigateToDetail
                    )
                }
                return
            }
        }

        let url: URL? = localOverrideURL ?? buildURL(for: item)
        guard let url else { return }
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

// MARK: - Recently Added shelf

struct RecentlyAddedVODShelf: View, Equatable {
    let playlist: Playlist
    let items: [DBVODStream]

    static func == (lhs: RecentlyAddedVODShelf, rhs: RecentlyAddedVODShelf) -> Bool {
        lhs.playlist.id == rhs.playlist.id && lhs.items == rhs.items
    }

    @Environment(\.posterMetrics) private var posterMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                NavigationLink {
                    RecentlyAddedVODDetailView(playlist: playlist, items: items)
                } label: {
                    HStack(spacing: 6) {
                        Text(L("recently_added.title"))
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { stream in
                        NavigationLink {
                            MovieDetailView(playlist: playlist, movie: stream, queue: items)
                        } label: {
                            VODStreamCard(
                                playlistId: playlist.id,
                                stream: stream,
                                posterWidth: posterMetrics.shelfPosterWidth,
                                posterHeight: posterMetrics.shelfPosterHeight,
                                imageLoadProfile: .shelf
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: posterMetrics.shelfRowTotalHeight)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Recently Added Detail View
struct RecentlyAddedVODDetailView: View {
    let playlist: Playlist
    let items: [DBVODStream]

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private var wrapped: [VODWithCategory] {
        items.map { VODWithCategory(stream: $0, categoryName: "") }
    }

    private var displayItems: [VODWithCategory] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return wrapped }
        return wrapped.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
    }

    var body: some View {
        VODCategoryContent(playlist: playlist, items: displayItems)
            .equatable()
            .navigationTitle(L("recently_added.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.hidden, for: .tabBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("vod.search_placeholder"))
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
private enum VODCategoryShelf {
    /// İlk görünür posterler için Nuke prefetch (kaydırma `LazyHStack` + görünce yükle).
    static let prefetchHeadCount = 32
}

struct VODCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [VODWithCategory]
    var isStreamsLoading: Bool = false

    static func == (lhs: VODCategoryShelfRow, rhs: VODCategoryShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.category == rhs.category &&
        lhs.items == rhs.items &&
        lhs.isStreamsLoading == rhs.isStreamsLoading
    }

    @Environment(\.posterMetrics) private var posterMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                NavigationLink {
                    VODCategoryDetailView(playlist: playlist, category: category)
                } label: {
                    HStack(spacing: 6) {
                        Text(category.name)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if items.isEmpty {
                if isStreamsLoading {
                    Color.clear.frame(height: posterMetrics.shelfRowTotalHeight)
                } else {
                    Text(L("vod.empty.no_in_category"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                // Kuyruğu raf başına BİR kez kur: NavigationLink destination'ı hücre
                // render'ında değerlendirilir; items.map'i içeride bırakmak her yeni
                // hücrede tüm kategoriyi kopyalıyordu (O(N²) scroll maliyeti).
                let queue = items.map(\.stream)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink {
                                MovieDetailView(playlist: playlist, movie: item.stream, queue: queue)
                            } label: {
                                VODStreamCard(
                                    playlistId: playlist.id,
                                    stream: item.stream,
                                    posterWidth: posterMetrics.shelfPosterWidth,
                                    posterHeight: posterMetrics.shelfPosterHeight,
                                    imageLoadProfile: .shelf
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: posterMetrics.shelfRowTotalHeight)
                .onAppear {
                    prefetchIcons(from: items)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func prefetchIcons(from list: [VODWithCategory]) {
        let urls = list.prefix(VODCategoryShelf.prefetchHeadCount)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(
            urls: urls,
            width: posterMetrics.shelfPosterWidth,
            height: posterMetrics.shelfPosterHeight,
            contentMode: .fill,
            loadProfile: .shelf
        )
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

    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                CachedImage(
                    url: stream.streamIcon.flatMap { URL(string: $0) },
                    width: posterWidth,
                    height: posterHeight,
                    contentMode: SwiftUI.ContentMode.fill,
                    iconName: "film",
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
struct VODCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [VODWithCategory] = []

    var body: some View {
        VODCategoryContent(playlist: playlist, items: displayItems)
            .equatable()
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.hidden, for: .tabBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("vod.search_placeholder"))
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
        let base = contentStore.vodStreamsByCategoryId[category.id] ?? []
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { displayItems = base; return }
        let result = await Task.detached(priority: .userInitiated) {
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            return CatalogTextSearch.sortVODByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }
}

struct VODCategoryContent: View, Equatable {
    let playlist: Playlist
    let items: [VODWithCategory]

    /// Cheap signature compare so a parent re-render (e.g. `applyVODMetadata`'s
    /// @Published storm) doesn't force SwiftUI to re-process a 10k-item view — that
    /// scaled with catalog size and froze "All Movies" for seconds on return.
    /// Internal @State/@Query updates still invalidate normally, independent of this.
    static func == (lhs: VODCategoryContent, rhs: VODCategoryContent) -> Bool {
        lhs.playlist.id == rhs.playlist.id
            && lhs.items.count == rhs.items.count
            && lhs.items.first?.stream.id == rhs.items.first?.stream.id
            && lhs.items.last?.stream.id == rhs.items.last?.stream.id
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Query<WatchProgressMapRequest> private var progressMap: [String: Double]

    @AppStorage(VODSortOption.storageKey) private var sortOption: VODSortOption = .defaultOrder
    /// Screen-local: file types are specific to the currently shown list, so this
    /// intentionally does not persist across screens.
    @State private var fileTypeFilter: Set<String> = []
    /// Sort/filter output, recomputed off the main thread on input changes so large
    /// lists (e.g. "All Movies") don't re-sort on every body pass (watch-progress ticks).
    @State private var displayItems: [VODWithCategory] = []
    /// Prebuilt play queue matching `displayItems`, so body passes don't re-map a
    /// large array on every render (critical for "All Movies" with 10k+ items).
    @State private var streamQueue: [DBVODStream] = []
    /// File types present in the full list, precomputed to keep the menu O(1) to build.
    @State private var fileTypes: [String] = []
    /// Number of cells currently rendered. Paginated so a 10k-item catalog doesn't
    /// build one giant ForEach (froze on first load and when scrolling to the end).
    @State private var visibleCount = Self.pageSize

    private static let pageSize = 90
    private static let gridTopID = "vodGridTop"

    init(playlist: Playlist, items: [VODWithCategory]) {
        self.playlist = playlist
        self.items = items
        _progressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "vod"), in: \.appDatabase)
    }

    private var categoryGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterMetrics.categoryGridPosterWidth), spacing: posterMetrics.gridSpacing)]
    }

    /// Cheap O(1) change signal for `items`; avoids O(n) array equality in `.task(id:)`
    /// on every update pass, which froze navigation on huge lists.
    private var itemsToken: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.stream.id)
        hasher.combine(items.last?.stream.id)
        return hasher.finalize()
    }

    private var isFilterActive: Bool {
        sortOption != .defaultOrder || !fileTypeFilter.isEmpty
    }

    private func recompute() async {
        let source = items
        let sort = sortOption
        let filter = fileTypeFilter
        let (result, queue, types) = await Task.detached(priority: .userInitiated) { () -> ([VODWithCategory], [DBVODStream], [String]) in
            let sorted = sort.apply(to: VODFileType.filter(source, selection: filter))
            // Options come from the full list so toggling one doesn't hide the others.
            return (sorted, sorted.map(\.stream), VODFileType.available(in: source))
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
        streamQueue = queue
        fileTypes = types
        visibleCount = min(Self.pageSize, result.count)
        prefetch(result)
    }

    private func loadMore() {
        guard visibleCount < displayItems.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, displayItems.count)
    }

    var body: some View {
        Group {
            if displayItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("vod.empty.no_movie"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: categoryGridColumns, spacing: posterMetrics.gridRowSpacing) {
                            ForEach(Array(displayItems.prefix(visibleCount).enumerated()), id: \.element.stream.id) { index, item in
                                NavigationLink {
                                    MovieDetailView(playlist: playlist, movie: item.stream, queue: streamQueue)
                                } label: {
                                    VODStreamCard(
                                        playlistId: playlist.id,
                                        stream: item.stream,
                                        posterWidth: posterMetrics.categoryGridPosterWidth,
                                        posterHeight: posterMetrics.categoryGridPosterHeight,
                                        imageLoadProfile: .grid,
                                        watchProgress: progressMap[String(item.stream.streamId)]
                                    )
                                }
                                .buttonStyle(.plain)
                                // Load the next page while cells near the end scroll into view.
                                // Triggered from inside the lazy grid so onAppear is reliable.
                                .onAppear { if index >= visibleCount - 15 { loadMore() } }
                            }
                        }
                        .padding()
                        .id(Self.gridTopID)

                        if visibleCount < displayItems.count {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                    .onChange(of: sortOption) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(Self.gridTopID, anchor: .top)
                        }
                    }
                    .onChange(of: fileTypeFilter) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(Self.gridTopID, anchor: .top)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortFilterMenu
            }
        }
        .task(id: itemsToken) { await recompute() }
        .task(id: sortOption) { await recompute() }
        .task(id: fileTypeFilter) { await recompute() }
    }

    private var sortFilterMenu: some View {
        Menu {
            Picker(L("sort.title"), selection: $sortOption) {
                ForEach(VODSortOption.allCases) { option in
                    Label(L(option.titleKey), systemImage: option.systemImage).tag(option)
                }
            }

            if fileTypes.count > 1 {
                Section(L("filter.file_type")) {
                    ForEach(fileTypes, id: \.self) { ext in
                        Button {
                            toggleFileType(ext)
                        } label: {
                            if fileTypeFilter.contains(ext) {
                                Label(ext.uppercased(), systemImage: "checkmark")
                            } else {
                                Text(ext.uppercased())
                            }
                        }
                    }
                    if !fileTypeFilter.isEmpty {
                        Button(role: .destructive) {
                            fileTypeFilter.removeAll()
                        } label: {
                            Label(L("filter.clear"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel(L("sort.title"))
    }

    private func toggleFileType(_ ext: String) {
        if fileTypeFilter.contains(ext) {
            fileTypeFilter.remove(ext)
        } else {
            fileTypeFilter.insert(ext)
        }
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
    @State private var displayItems: [VODWithCategory] = []

    var body: some View {
        VODCategoryContent(playlist: playlist, items: displayItems)
            .equatable()
            .navigationTitle(L("browse.all_movies"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.hidden, for: .tabBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("vod.search_placeholder"))
            .onChange(of: searchText) { _, new in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { debouncedQuery = new }
                }
            }
            .onDisappear { debounceTask?.cancel(); debounceTask = nil }
            .task(id: debouncedQuery) { await recompute() }
            .task(id: contentStore.streamsLoaded) { await recompute() }
            .task(id: hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")) { await recompute() }
    }

    private func recompute() async {
        guard playlist.id == contentStore.activePlaylistId else { displayItems = []; return }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")
        let source = contentStore.vodStreams
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        // Everything (hidden-filter, search, relevance sort) runs off the main thread —
        // the catalog can be hundreds of thousands of rows, so even the hidden-filter
        // is too heavy to run on-main (it froze the "All" screen on open).
        let result = await Task.detached(priority: .userInitiated) {
            let base = source.filter { !hidden.contains($0.stream.categoryId ?? "") }
            if q.isEmpty { return base }
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            return CatalogTextSearch.sortVODByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
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
