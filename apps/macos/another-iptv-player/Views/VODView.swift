import SwiftUI
import GRDBQuery
import GRDB

struct VODView: View {
    let playlist: Playlist
    @Binding var externalSearch: String
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @ObservedObject private var playerOverlay: PlayerOverlayController = .shared

    @State private var pendingMovieDetail: DBVODStream?

    init(playlist: Playlist, externalSearch: Binding<String> = .constant("")) {
        self.playlist = playlist
        self._externalSearch = externalSearch
    }

    private var pickerEntries: [CategoryPickerSheet.Entry] {
        contentStore.vodCategories.map { cat in
            CategoryPickerSheet.Entry(
                id: cat.id,
                name: cat.name,
                count: contentStore.vodStreamsByCategoryId[cat.id]?.count ?? 0
            )
        }
    }

    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    // Filtreleme sonuçları arka planda hesaplanır, main thread'e sadece atama yapılır
    @State private var displayCategories: [DBCategory] = []
    @State private var displayItemsByCategory: [String: [VODWithCategory]] = [:]
    @State private var recentlyAddedVODs: [DBVODStream] = []

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    var body: some View {
        // Pre-capture env-bound playerOverlay (navigationDestination crash fix).
        let overlayCapture: PlayerOverlayController = playerOverlay
        return Group {
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
                type: "vod"
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
        .task(id: hiddenStore.hiddenIds(playlistId: playlist.id, type: "vod")) { await recomputeFilter() }
        .transaction { $0.animation = nil }
        .navigationDestination(item: $pendingMovieDetail) { movie in
            MovieDetailView(playlist: playlist, movie: movie)
                .environmentObject(overlayCapture)
                .trackDetailDepth()
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
                        initialResumeMs: item.lastTimeMs,
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
                resumeTimeMs: item.lastTimeMs,
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
            ) { stream in
                vodCardLink(stream: stream)
            }
            .frame(height: posterMetrics.shelfRowTotalHeight)
        }
        .padding(.vertical, 6)
    }

    /// Card tıklaması: selector varsa sidebar selection (.item) — duplicate back butonu olmaz.
    /// Yoksa eski NavigationLink push.
    @ViewBuilder
    private func vodCardLink(stream: DBVODStream) -> some View {
        let card = VODStreamCard(
            playlistId: playlist.id,
            stream: stream,
            posterWidth: posterMetrics.shelfPosterWidth,
            posterHeight: posterMetrics.shelfPosterHeight,
            imageLoadProfile: .shelf
        )
        if let selector = sidebarCategorySelector {
            Button {
                let catId = stream.categoryId ?? ""
                selector.navigate(.item(playlist.id, .movies, catId, String(stream.streamId)))
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                MovieDetailView(playlist: playlist, movie: stream, queue: items)
                    .trackDetailDepth()
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    /// Selector enjekte edilmişse Button (sidebar selection → .recentlyAdded; ek back butonu
    /// üretmez). Yoksa eski NavigationLink push davranışı.
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
                selector.select(.movies, "__recently_added__")
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                RecentlyAddedVODDetailView(playlist: playlist, items: items)
                    .trackDetailDepth()
            } label: {
                label
            }
        }
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
            .navigationTitle(L("recently_added.title"))
            
            .macSearchable(text: $searchText, prompt: L("vod.search_placeholder"))
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
                    Text(L("vod.empty.no_in_category"))
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
                    vodCategoryCardLink(item: item)
                }
                .frame(height: posterMetrics.shelfRowTotalHeight)
                .onAppear {
                    prefetchIcons(from: items)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func vodCategoryCardLink(item: VODWithCategory) -> some View {
        let card = VODStreamCard(
            playlistId: playlist.id,
            stream: item.stream,
            posterWidth: posterMetrics.shelfPosterWidth,
            posterHeight: posterMetrics.shelfPosterHeight,
            imageLoadProfile: .shelf
        )
        if let selector = sidebarCategorySelector {
            Button {
                selector.navigate(.item(playlist.id, .movies, category.id, String(item.stream.streamId)))
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                MovieDetailView(playlist: playlist, movie: item.stream, queue: items.map(\.stream))
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    private func prefetchIcons(from list: [VODWithCategory]) {
        let urls = list.prefix(VODCategoryShelf.prefetchHeadCount)
            .compactMap { $0.stream.streamIcon }
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
                selector.select(.movies, category.id)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                VODCategoryDetailView(playlist: playlist, category: category)
                    .trackDetailDepth()
            } label: {
                label
            }
        }
    }
}

struct VODStreamCard: View {
    let stream: DBVODStream
    var categoryName: String? = nil
    var posterWidth: CGFloat = 160
    var posterHeight: CGFloat = 240
    var imageLoadProfile: ImageLoadProfile = .standard
    /// Kart başına @Query açmak yerine üst view'dan geçilir (nil = progress bar gizli).
    /// Eski tasarımda her görünen kart kendi DB subscription'ını açıyordu (50+ kart × shelf = onlarca aktif query → ciddi kasma).
    var watchProgress: Double? = nil

    init(
        playlistId: UUID,
        stream: DBVODStream,
        categoryName: String? = nil,
        posterWidth: CGFloat = 160,
        posterHeight: CGFloat = 240,
        imageLoadProfile: ImageLoadProfile = .standard,
        watchProgress: Double? = nil
    ) {
        self.stream = stream
        self.categoryName = categoryName
        self.posterWidth = posterWidth
        self.posterHeight = posterHeight
        self.imageLoadProfile = imageLoadProfile
        self.watchProgress = watchProgress
        _ = playlistId  // imza uyumluluğu için tutuluyor; artık per-card query yok.
    }

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
            .navigationTitle(category.name)
            
            .macSearchable(text: $searchText, prompt: L("vod.search_placeholder"))
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

struct VODCategoryContent: View {
    let playlist: Playlist
    let items: [VODWithCategory]

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.sidebarCategorySelector) private var sidebarCategorySelector
    @Query<WatchProgressMapRequest> private var progressMap: [String: Double]

    init(playlist: Playlist, items: [VODWithCategory]) {
        self.playlist = playlist
        self.items = items
        _progressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "vod"), in: \.appDatabase)
    }

    private var categoryGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterMetrics.categoryGridPosterWidth), spacing: posterMetrics.gridSpacing)]
    }

    var body: some View {
        Group {
            if items.isEmpty {
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
                ScrollView {
                    LazyVGrid(columns: categoryGridColumns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(items) { item in
                            vodGridCardLink(item: item)
                        }
                    }
                    .padding()
                }
                .onChange(of: items) { _, newValue in
                    let urls = newValue.compactMap { $0.stream.streamIcon }.compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
                .onAppear {
                    let urls = items.compactMap { $0.stream.streamIcon }.compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
            }
        }
    }

    @ViewBuilder
    private func vodGridCardLink(item: VODWithCategory) -> some View {
        let card = VODStreamCard(
            playlistId: playlist.id,
            stream: item.stream,
            posterWidth: posterMetrics.categoryGridPosterWidth,
            posterHeight: posterMetrics.categoryGridPosterHeight,
            imageLoadProfile: .grid,
            watchProgress: progressMap[String(item.stream.streamId)]
        )
        if let selector = sidebarCategorySelector {
            Button {
                let catId = item.stream.categoryId ?? ""
                selector.navigate(.item(playlist.id, .movies, catId, String(item.stream.streamId)))
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                MovieDetailView(playlist: playlist, movie: item.stream, queue: items.map(\.stream))
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - VOD Player Shell

/// Film listesinden açılan player; kaynakla aynı kuyrukta önceki/sonraki film desteği sağlar.
struct VODPlayerShell: View {
    let playlist: Playlist
    let queue: [DBVODStream]
    var onNavigateToDetail: ((String, String) -> Void)? = nil

    @State private var currentMovie: DBVODStream
    @State private var resumeMs: Int?
    @State private var instanceId = UUID()

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
            .id(instanceId)
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
                resumeMs = history?.lastTimeMs
                instanceId = UUID()
            }
        }
    }
}
