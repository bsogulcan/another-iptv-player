import SwiftUI
import GRDB
import GRDBQuery

struct LiveStreamsView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    @State private var displayCategories: [DBCategory] = []
    @State private var displayItemsByCategory: [String: [LiveStreamWithCategory]] = [:]

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    private var livePlaybackQueue: [DBLiveStream] {
        displayCategories.flatMap { displayItemsByCategory[$0.id]?.map(\.stream) ?? [] }
    }

    private var pickerEntries: [CategoryPickerSheet.Entry] {
        contentStore.liveCategories.map { cat in
            CategoryPickerSheet.Entry(
                id: cat.id,
                name: cat.name,
                count: contentStore.liveStreamsByCategoryId[cat.id]?.count ?? 0
            )
        }
    }

    private var liveChannelSections: [LiveChannelCategorySection] {
        displayCategories.compactMap { cat in
            let streams = displayItemsByCategory[cat.id]?.map(\.stream) ?? []
            guard !streams.isEmpty else { return nil }
            return LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams)
        }
    }

    private func liveQueueIndex(for stream: DBLiveStream) -> Int? {
        livePlaybackQueue.firstIndex(where: { $0.streamId == stream.streamId })
    }

    var body: some View {
        Group {
            if displayCategories.isEmpty {
                if contentStore.isLoading || playlist.id != contentStore.activePlaylistId {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(contentStore.loadingMessage ?? L("live.empty.preparing"))
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
                        Image(systemName: "tv.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(debouncedQuery.isEmpty ? L("live.empty.no_category") : L("list.no_result"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                contentList
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: L("live.search_placeholder"))
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
        .task(id: hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")) { await recomputeFilter() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    EPGGuideView(source: .xtream(playlist))
                } label: {
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(L("epg.guide.title"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AllLiveView(playlist: playlist)
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.body.weight(.semibold))
                }
                .disabled(contentStore.liveStreams.isEmpty)
                .accessibilityLabel(L("browse.all_live"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCategoryPicker = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.body.weight(.semibold))
                }
                .disabled(contentStore.liveCategories.isEmpty)
                .accessibilityLabel(L("list.jump_to_category"))
            }
        }
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerSheet(
                title: L("category_picker.title"),
                entries: pickerEntries,
                playlistId: playlist.id,
                type: "live"
            ) { id in
                showingCategoryPicker = false
                pendingScrollTarget = id
            }
        }
    }

    private func presentLiveSelection(_ selection: LivePlayerSelection) {
        playerOverlay.present(playlistId: playlist.id) {
            LivePlayerShell(
                playlist: playlist,
                queue: livePlaybackQueue,
                sections: liveChannelSections,
                initialStream: selection.stream,
                initialHistory: selection.history,
                subtitle: nil
            )
        }
    }

    private func presentHistoryItem(_ item: DBWatchHistory) {
        guard let url = historyURL(for: item) else { return }
        if item.type == "series" {
            playerOverlay.present(playlistId: playlist.id) {
                HistorySeriesPlayerShell(playlist: playlist, history: item, url: url)
            }
        } else if item.type == "live" {
            let stream = liveStream(for: item) ?? DBLiveStream(
                streamId: Int(item.streamId) ?? 0,
                name: item.title,
                streamIcon: item.imageURL,
                categoryId: nil,
                sortIndex: 0,
                playlistId: item.playlistId
            )
            playerOverlay.present(playlistId: playlist.id) {
                LivePlayerShell(
                    playlist: playlist,
                    queue: livePlaybackQueue,
                    sections: liveChannelSections,
                    initialStream: stream,
                    initialHistory: item,
                    subtitle: nil
                )
            }
        } else {
            playerOverlay.present(playlistId: playlist.id) {
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
                    resumeTimeMs: item.lastTimeMs
                )
            }
        }
    }

    private var contentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ContinueWatchingRow(
                    playlist: playlist,
                    typeFilter: "live",
                    destination: {
                        WatchHistoryListView(playlist: playlist, typeFilter: "live") { item in
                            presentHistoryItem(item)
                        }
                    },
                    onPlay: { item in
                        presentHistoryItem(item)
                    }
                )

                LazyVStack(spacing: 0) {
                    ForEach(displayCategories) { category in
                        LiveCategoryShelfRow(
                            playlist: playlist,
                            category: category,
                            items: displayItemsByCategory[category.id] ?? [],
                            onStreamSelected: { stream, history in
                                presentLiveSelection(LivePlayerSelection(stream: stream, history: history))
                            },
                            isStreamsLoading: !contentStore.streamsLoaded
                        )
                        .equatable()
                        .id(category.id)
                    }
                }
            }
            .refreshable {
                // SwiftUI, ScrollView yeniden çizilince refreshable task'ını iptal
                // edebiliyor; iptal child URLSession isteklerine yayılıp "cancelled"
                // hatası üretiyordu. Bağımsız Task iptalden etkilenmez; await task.value
                // spinner'ı iş bitene dek tutar.
                let work = Task { await contentStore.refreshFromNetwork(playlist: playlist, only: .live) }
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

    private func historyURL(for item: DBWatchHistory) -> URL? {
        let builder = PlaybackURLBuilder(playlist: playlist)
        switch item.type {
        case "live":
            return builder.liveURL(streamId: Int(item.streamId) ?? 0)
        case "vod":
            // MovieDetailView stores streamId as string, builder needs int
            return builder.movieURL(streamId: Int(item.streamId) ?? 0, containerExtension: nil)
        case "series":
            // EpisodeId might be an integer or string in different IPTV setups
            return builder.seriesURL(streamId: item.streamId, containerExtension: nil)
        default:
            return nil
        }
    }

    private func recomputeFilter() async {
        guard playlist.id == contentStore.activePlaylistId else {
            displayCategories = []; displayItemsByCategory = [:]; return
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
        let allCats = contentStore.liveCategories.filter { !hidden.contains($0.id) }
        let allByCategory = contentStore.liveStreamsByCategoryId
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayCategories = allCats
            displayItemsByCategory = allByCategory
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            var cats: [DBCategory] = []
            var byCategory: [String: [LiveStreamWithCategory]] = [:]
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

    private func liveStream(for item: DBWatchHistory) -> DBLiveStream? {
        let streamId = Int(item.streamId) ?? 0
        if let match = livePlaybackQueue.first(where: { $0.streamId == streamId }) {
            return match
        }
        // Lazy arama: eager flatMap+map tüm katalogu iki kez kopyalayıp tap gecikmesine
        // onlarca ms ekliyordu; .lazy.joined() ara dizi kurmaz, .first eşleşmede durur.
        return contentStore.liveStreamsByCategoryId.values
            .lazy
            .joined()
            .first(where: { $0.stream.streamId == streamId })?
            .stream
    }
}

// MARK: - Category shelf (horizontal preview)
private enum CategoryShelf {
    static let prefetchHeadCount = 32
}

struct LiveCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [LiveStreamWithCategory]
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil
    var isStreamsLoading: Bool = false

    static func == (lhs: LiveCategoryShelfRow, rhs: LiveCategoryShelfRow) -> Bool {
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
                    LiveCategoryDetailView(playlist: playlist, category: category)
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
                    Color.clear.frame(height: posterMetrics.liveShelfIcon + 30)
                } else {
                    Text(L("live.empty.no_channel_in_category"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            LiveStreamCard(
                                playlistId: playlist.id,
                                stream: item.stream,
                                width: posterMetrics.liveShelfLabelWidth,
                                iconSize: posterMetrics.liveShelfIcon,
                                imageLoadProfile: .shelf
                            ) { stream, history in
                                onStreamSelected?(stream, history)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear {
                    prefetchIcons(from: items)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func prefetchIcons(from list: [LiveStreamWithCategory]) {
        let urls = list.prefix(CategoryShelf.prefetchHeadCount)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(
            urls: urls,
            width: posterMetrics.liveShelfIcon,
            height: posterMetrics.liveShelfIcon,
            loadProfile: .shelf
        )
    }
}

struct LiveStreamCard: View {
    let playlistId: UUID
    let stream: DBLiveStream
    var width: CGFloat = 120
    var iconSize: CGFloat = 120
    var imageLoadProfile: ImageLoadProfile = .standard
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil

    @Environment(\.epgSnapshot) private var epgSnapshot

    var body: some View {
        Button(action: {
            onStreamSelected?(stream, nil)
        }) {
            VStack(alignment: .center, spacing: 10) {
                CachedImage(
                    url: stream.streamIcon.flatMap { URL(string: $0) },
                    width: iconSize,
                    height: iconSize,
                    cornerRadius: 12,
                    iconName: "tv",
                    loadProfile: imageLoadProfile
                )

                Text(stream.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width)
                    .foregroundColor(.primary)

                if let snapshot = epgSnapshot {
                    EPGNowNextLine(nowNext: snapshot[EPGChannelKey.forXtream(stream)],
                                   width: width, reserveSpace: true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Detail View
struct LiveCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [LiveStreamWithCategory] = []

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    private var currentStreams: [DBLiveStream] { displayItems.map(\.stream) }

    var body: some View {
        LiveCategoryContent(
            playlist: playlist,
            items: displayItems,
            onStreamSelected: { stream, history in
                let selection = LivePlayerSelection(stream: stream, history: history)
                playerOverlay.present(playlistId: playlist.id) {
                    LivePlayerShell(
                        playlist: playlist,
                        queue: currentStreams,
                        sections: [LiveChannelCategorySection(id: category.id, title: category.name, streams: currentStreams)],
                        initialStream: selection.stream,
                        initialHistory: selection.history,
                        subtitle: category.name
                    )
                }
            }
        )
        .equatable()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("live.search_placeholder"))
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
        let base = contentStore.liveStreamsByCategoryId[category.id] ?? []
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { displayItems = base; return }
        let result = await Task.detached(priority: .userInitiated) {
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            return CatalogTextSearch.sortLiveByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }
}

struct LiveCategoryContent: View, Equatable {
    let playlist: Playlist
    let items: [LiveStreamWithCategory]
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil

    /// Cheap signature compare (ignores the selection closure) so a parent @Published
    /// re-render doesn't force SwiftUI to re-process a huge channel list. Internal
    /// @State updates still invalidate normally.
    static func == (lhs: LiveCategoryContent, rhs: LiveCategoryContent) -> Bool {
        lhs.playlist.id == rhs.playlist.id
            && lhs.items.count == rhs.items.count
            && lhs.items.first?.stream.streamId == rhs.items.first?.stream.streamId
            && lhs.items.last?.stream.streamId == rhs.items.last?.stream.streamId
    }

    @Environment(\.posterMetrics) private var posterMetrics

    @AppStorage(LiveSortOption.storageKey) private var sortOption: LiveSortOption = .defaultOrder
    /// Screen-local toggle filters (catch-up / EPG).
    @State private var filter: LiveStreamFilter = []
    /// Sort/filter output, recomputed off the main thread on input changes.
    @State private var displayItems: [LiveStreamWithCategory] = []
    /// Paginated render count so a huge catalog doesn't build one giant ForEach.
    @State private var visibleCount = Self.pageSize

    private static let pageSize = 90

    /// Cheap O(1) change signal for `items`; avoids O(n) array equality in `.task(id:)`
    /// on every update pass, which froze navigation on huge lists ("All Channels").
    private var itemsToken: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.stream.streamId)
        hasher.combine(items.last?.stream.streamId)
        return hasher.finalize()
    }

    private var isFilterActive: Bool {
        sortOption != .defaultOrder || !filter.isEmpty
    }

    private func recompute() async {
        let source = items
        let sort = sortOption
        let activeFilter = filter
        let result = await Task.detached(priority: .userInitiated) {
            sort.apply(to: LiveStreamFilter.apply(source, activeFilter))
        }.value
        displayItems = result
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
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("list.no_channel"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: posterMetrics.liveGridIconSize), spacing: posterMetrics.gridSpacing)
                ]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(Array(displayItems.prefix(visibleCount).enumerated()), id: \.element.stream.streamId) { index, item in
                            LiveStreamCard(
                                playlistId: playlist.id,
                                stream: item.stream,
                                width: posterMetrics.liveGridIconSize,
                                iconSize: posterMetrics.liveGridIconSize,
                                imageLoadProfile: .grid,
                                onStreamSelected: onStreamSelected
                            )
                            .onAppear { if index >= visibleCount - 15 { loadMore() } }
                        }
                    }
                    .padding()

                    if visibleCount < displayItems.count {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
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
        .task(id: filter.rawValue) { await recompute() }
    }

    private var sortFilterMenu: some View {
        Menu {
            Picker(L("sort.title"), selection: $sortOption) {
                ForEach(LiveSortOption.allCases) { option in
                    Label(L(option.titleKey), systemImage: option.systemImage).tag(option)
                }
            }

            Section(L("filter.title")) {
                Button {
                    filter.formSymmetricDifference(.catchup)
                } label: {
                    if filter.contains(.catchup) {
                        Label(L("filter.catchup"), systemImage: "checkmark")
                    } else {
                        Text(L("filter.catchup"))
                    }
                }
                Button {
                    filter.formSymmetricDifference(.hasEPG)
                } label: {
                    if filter.contains(.hasEPG) {
                        Label(L("filter.has_epg"), systemImage: "checkmark")
                    } else {
                        Text(L("filter.has_epg"))
                    }
                }
                if !filter.isEmpty {
                    Button(role: .destructive) {
                        filter = []
                    } label: {
                        Label(L("filter.clear"), systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel(L("sort.title"))
    }

    private func prefetch(_ list: [LiveStreamWithCategory]) {
        let urls = list.prefix(ListImagePrefetch.maxBatch)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(urls: urls, width: posterMetrics.liveGridIconSize, height: posterMetrics.liveGridIconSize, loadProfile: .grid)
    }
}

// MARK: - All Live (flat, sortable/filterable browse)

/// Flat grid of every channel across categories. Reuses `LiveCategoryContent`, so
/// it inherits the sort menu and catch-up/EPG filters for free.
struct AllLiveView: View {
    let playlist: Playlist

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [LiveStreamWithCategory] = []

    private var currentStreams: [DBLiveStream] { displayItems.map(\.stream) }

    var body: some View {
        LiveCategoryContent(
            playlist: playlist,
            items: displayItems,
            onStreamSelected: { stream, history in
                let all = currentStreams
                playerOverlay.present(playlistId: playlist.id) {
                    LivePlayerShell(
                        playlist: playlist,
                        queue: all,
                        sections: [LiveChannelCategorySection(id: "all", title: L("browse.all_live"), streams: all)],
                        initialStream: stream,
                        initialHistory: history,
                        subtitle: L("browse.all_live")
                    )
                }
            }
        )
        .equatable()
        .navigationTitle(L("browse.all_live"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("live.search_placeholder"))
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
        .task(id: hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")) { await recompute() }
    }

    private func recompute() async {
        guard playlist.id == contentStore.activePlaylistId else { displayItems = []; return }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
        let source = contentStore.liveStreams
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        // All work off the main thread; the catalog can be very large.
        let result = await Task.detached(priority: .userInitiated) {
            let base = source.filter { !hidden.contains($0.stream.categoryId ?? "") }
            if q.isEmpty { return base }
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            return CatalogTextSearch.sortLiveByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }
}

struct LivePlayerSelection: Identifiable {
    let id = UUID()
    let stream: DBLiveStream
    let history: DBWatchHistory?
}

struct LivePlayerShell: View {
    let playlist: Playlist
    let queue: [DBLiveStream]
    let sections: [LiveChannelCategorySection]
    let subtitle: String?
    private let initialStream: DBLiveStream
    private let initialHistory: DBWatchHistory?

    @State private var session: LivePlaybackSession
    @State private var showChannelSidePanel: Bool = false
    @State private var isFavorite = false
    @Environment(\.playerOverlayPresentationID) private var overlayPresentationID

    init(
        playlist: Playlist,
        queue: [DBLiveStream],
        sections: [LiveChannelCategorySection],
        initialStream: DBLiveStream,
        initialHistory: DBWatchHistory?,
        subtitle: String?
    ) {
        self.playlist = playlist
        self.queue = queue
        self.sections = sections
        self.subtitle = subtitle
        self.initialStream = initialStream
        self.initialHistory = initialHistory
        // Sections shell ömrü boyunca değişmez; her body değerlendirmesinde (kanal zap,
        // panel aç/kapa) on binlerce kanalı yeniden map'lemek yerine bir kez kur.
        self.panelSections = sections.map { section in
            ChannelPanelSection(
                id: section.id,
                title: section.title,
                items: section.streams.map { stream in
                    ChannelPanelItem(
                        id: String(stream.streamId),
                        name: stream.name,
                        iconURL: stream.streamIcon.flatMap { URL(string: $0) }
                    )
                }
            )
        }
        let initialURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: initialStream.streamId)
        _session = State(initialValue: LivePlaybackSession(
            stream: initialStream,
            url: initialURL,
            resumeTimeMs: initialHistory?.lastTimeMs
        ))
    }

    private var currentIndex: Int? {
        queue.firstIndex(where: { $0.streamId == session.stream.streamId })
    }

    /// Category name of the channel on screen, shown under the title. Derived from the
    /// current stream so it updates on zap, and never echoes the channel name itself.
    private var liveSubtitle: String? {
        if let categoryId = session.stream.categoryId,
           let name = PlaylistContentStore.shared.liveCategories.first(where: { $0.id == categoryId })?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let subtitle, subtitle != session.stream.name { return subtitle }
        return nil
    }

    private let panelSections: [ChannelPanelSection]

    var body: some View {
        if let url = session.url {
            ZStack(alignment: .bottom) {
                PlayerView(
                    url: url,
                    title: session.stream.name,
                    subtitle: liveSubtitle,
                    artworkURL: session.stream.streamIcon.flatMap { URL(string: $0) },
                    isLiveStream: true,
                    playlistId: playlist.id,
                    streamId: String(session.stream.streamId),
                    type: "live",
                    resumeTimeMs: session.resumeTimeMs,
                    epgChannelKey: EPGChannelKey.forXtream(session.stream),
                    canGoToPreviousChannel: (currentIndex ?? 0) > 0,
                    canGoToNextChannel: {
                        guard let index = currentIndex else { return false }
                        return index < queue.count - 1
                    }(),
                    onPreviousChannel: { jump(offset: -1) },
                    onNextChannel: { jump(offset: 1) },
                    channelPanelSections: panelSections,
                    currentChannelPanelItemId: String(session.stream.streamId),
                    onSelectChannelPanelItem: { id in selectPanelItem(id: id) },
                    isLiveChannelSidePanelVisible: showChannelSidePanel,
                    onToggleLiveChannelSidePanel: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showChannelSidePanel.toggle()
                        }
                    },
                    onVideoSurfaceTap: {
                        guard showChannelSidePanel else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showChannelSidePanel = false
                        }
                    },
                    isFavorite: isFavorite,
                    onToggleFavorite: toggleFavorite
                )

                if showChannelSidePanel, !sections.isEmpty {
                    LiveChannelSidePanel(
                        sections: panelSections,
                        currentItemId: String(session.stream.streamId),
                        onSelectChannel: { id in selectPanelItem(id: id) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .task(id: "\(playlist.id.uuidString)-\(session.stream.streamId)") {
                await refreshFavorite()
            }
            .onChange(of: overlayPresentationID) { _, _ in
                applyInitialSelectionIfNeeded()
            }
        }
    }

    private func applyInitialSelectionIfNeeded() {
        let targetURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: initialStream.streamId)
        let targetResume = initialHistory?.lastTimeMs
        guard session.stream.streamId != initialStream.streamId
                || session.url != targetURL
                || session.resumeTimeMs != targetResume else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            showChannelSidePanel = false
            session = LivePlaybackSession(
                stream: initialStream,
                url: targetURL,
                resumeTimeMs: targetResume
            )
        }
    }

    private func selectPanelItem(id: String) {
        guard let streamId = Int(id) else { return }
        guard let stream = queue.first(where: { $0.streamId == streamId })
            ?? sections.flatMap(\.streams).first(where: { $0.streamId == streamId }) else { return }
        switchTo(stream: stream, resumeTimeMs: nil)
    }

    private func jump(offset: Int) {
        guard let index = currentIndex else { return }
        let target = index + offset
        guard target >= 0, target < queue.count else { return }
        let targetStream = queue[target]
        switchTo(stream: targetStream, resumeTimeMs: nil)
    }

    private func switchTo(stream: DBLiveStream, resumeTimeMs: Int?) {
        let targetURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: stream.streamId)
        if session.stream.streamId == stream.streamId, session.url == targetURL {
            return
        }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            session = LivePlaybackSession(
                stream: stream,
                url: targetURL,
                resumeTimeMs: resumeTimeMs
            )
        }
    }

    private func refreshFavorite() async {
        let streamId = session.stream.streamId
        let value = (try? await AppDatabase.shared.read { db in
            try DBFavorite
                .filter(Column("streamId") == streamId
                    && Column("playlistId") == playlist.id
                    && Column("type") == "live")
                .fetchCount(db) > 0
        }) ?? false
        guard !Task.isCancelled, session.stream.streamId == streamId else { return }
        isFavorite = value
    }

    private func toggleFavorite() {
        let streamId = session.stream.streamId
        let nextValue = !isFavorite
        isFavorite = nextValue
        Task {
            do {
                try await AppDatabase.shared.write { db in
                    if nextValue {
                        try DBFavorite(
                            streamId: streamId, playlistId: playlist.id, type: "live"
                        ).insert(db)
                    } else {
                        try DBFavorite
                            .filter(Column("streamId") == streamId
                                && Column("playlistId") == playlist.id
                                && Column("type") == "live")
                            .deleteAll(db)
                    }
                }
                SyncEngine.shared.enqueueFavoriteChange(
                    playlistId: playlist.id, contentType: "live", itemId: String(streamId), favorited: nextValue
                )
            } catch {
                if session.stream.streamId == streamId { isFavorite.toggle() }
            }
        }
    }
}

struct LivePlaybackSession: Equatable {
    var stream: DBLiveStream
    var url: URL?
    var resumeTimeMs: Int?
}
