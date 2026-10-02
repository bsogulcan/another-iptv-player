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

    /// Flattened queue + per-category sections for the display model above. Built on the
    /// first channel tap after a filter change and reused for later taps, so opening the
    /// player no longer copies the whole catalog twice on the main thread every time.
    @State private var playbackModelMemo = LivePlaybackModelMemo()

    private var livePlaybackModel: LivePlaybackModelMemo.Model {
        if let model = playbackModelMemo.model { return model }
        let sections = displayCategories.compactMap { cat -> LiveChannelCategorySection? in
            let streams = displayItemsByCategory[cat.id]?.map(\.stream) ?? []
            guard !streams.isEmpty else { return nil }
            return LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams)
        }
        // Empty categories contribute nothing, so this is the same queue the old
        // per-tap flatMap over `displayCategories` produced.
        let model = LivePlaybackModelMemo.Model(queue: sections.flatMap(\.streams), sections: sections)
        playbackModelMemo.model = model
        return model
    }

    private var livePlaybackQueue: [DBLiveStream] {
        livePlaybackModel.queue
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
        livePlaybackModel.sections
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
                    // Same rule as VODView: a finished film starts over instead of
                    // reopening in its last seconds.
                    resumeTimeMs: item.resumePositionMs(as: .film)
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
            displayCategories = []; displayItemsByCategory = [:]
            playbackModelMemo.model = nil
            return
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
        let allCats = contentStore.liveCategories.filter { !hidden.contains($0.id) }
        let allByCategory = contentStore.liveStreamsByCategoryId
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayCategories = allCats
            displayItemsByCategory = allByCategory
            playbackModelMemo.model = nil
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
        playbackModelMemo.model = nil
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

    /// What the player is loading or playing. During a prev/next burst it lags
    /// `visibleStream` until the zap debounce fires.
    @State private var session: LivePlaybackSession
    /// Channel a prev/next burst has landed on but that is not loaded yet. The chrome
    /// (title, EPG strip, highlighted row) follows it at once; playback waits for the
    /// burst to end so only its last channel opens a connection.
    @State private var pendingZapStream: DBLiveStream?
    @State private var pendingZapTask: Task<Void, Never>?
    /// Channel that was playing before the current one, for last-channel recall.
    @State private var lastChannelStream: DBLiveStream?
    /// Full panel model, set once the categories missing at init were built off-main.
    @State private var completedPanel: CompletedPanel?
    @State private var showChannelSidePanel: Bool = false
    @State private var isFavorite = false
    /// The presentation revision PlayerView sees. PlayerView treats a new revision with
    /// an unchanged stream as "the viewer asked for this channel again" (the shell
    /// itself cannot see whether playback ended or failed), so it gets a fresh one when
    /// the channel that is already playing is picked again. It also carries the
    /// overlay's own revision, adopted together with the selection of a new
    /// presentation: passed straight through, the new revision reached PlayerView one
    /// update before the new channel did, and a failed or ended old channel was
    /// reloaded first.
    @State private var reselectRevision: UUID?
    @Environment(\.playerOverlayPresentationID) private var overlayPresentationID
    @Environment(\.playerOverlayMode) private var overlayMode
    @Environment(\.epgSnapshot) private var epgSnapshot

    /// Trailing debounce for prev/next presses.
    private static let zapDebounceNanoseconds: UInt64 = 250_000_000
    /// Wait before the short-EPG fallback asks the panel, so channels that are only
    /// zapped past cost no request.
    private static let shortEPGDelayNanoseconds: UInt64 = 1_500_000_000

    private struct CompletedPanel {
        let token: UUID
        let sections: [ChannelPanelSection]
    }

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
        // Panel items come from a per-category cache, so reopening the player does not map
        // (and parse an icon URL for) every channel of the catalog again. On a cold cache
        // of a large catalog only the current category is built here; the rest is filled
        // in off the main thread by `completePanelSections()`.
        let panel = LiveChannelPanelSectionCache.shared.resolve(
            sections, playlistId: playlist.id, currentStreamId: initialStream.streamId
        )
        self.initialPanelSections = panel.sections
        self.panelBuildToken = panel.isComplete ? nil : UUID()
        let initialURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: initialStream.streamId)
        _session = State(initialValue: LivePlaybackSession(
            stream: initialStream,
            url: initialURL,
            resumeTimeMs: initialHistory?.lastTimeMs
        ))
    }

    /// Channel the chrome presents: the pending zap target while a burst is being
    /// coalesced, otherwise the one that is playing.
    private var visibleStream: DBLiveStream {
        pendingZapStream ?? session.stream
    }

    private var currentIndex: Int? {
        let streamId = visibleStream.streamId
        return queue.firstIndex(where: { $0.streamId == streamId })
    }

    /// Category name of the channel on screen, shown under the title. Derived from the
    /// current stream so it updates on zap, and never echoes the channel name itself.
    private var liveSubtitle: String? {
        let stream = visibleStream
        if let categoryId = stream.categoryId,
           let name = PlaylistContentStore.shared.liveCategories.first(where: { $0.id == categoryId })?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let subtitle, subtitle != stream.name { return subtitle }
        return nil
    }

    /// Panel model available at init: every cached category plus the current one.
    private let initialPanelSections: [ChannelPanelSection]
    /// Non-nil while `initialPanelSections` is missing categories; identifies this
    /// presentation's off-main completion (the shell's @State outlives a re-presentation).
    private let panelBuildToken: UUID?

    private var panelSections: [ChannelPanelSection] {
        if let token = panelBuildToken, let completed = completedPanel, completed.token == token {
            return completed.sections
        }
        return initialPanelSections
    }

    // MARK: Last-channel recall

    /// Channel that was playing before the current one, or nil when there is nothing to
    /// jump back to. Channels skipped inside a prev/next burst never played and are not
    /// remembered.
    var lastChannel: DBLiveStream? {
        guard let last = lastChannelStream,
              last.playlistId == playlist.id,
              last.streamId != session.stream.streamId else { return nil }
        return last
    }

    /// Ready-made action for a player-chrome button: nil when there is no last channel.
    var onRecallLastChannel: (() -> Void)? {
        guard lastChannel != nil else { return nil }
        return { recallLastChannel() }
    }

    /// Jumps back to `lastChannel`. The channel being left becomes the new last channel,
    /// so calling this repeatedly toggles between the two.
    func recallLastChannel() {
        guard let last = lastChannel else { return }
        switchTo(stream: last, resumeTimeMs: nil)
    }

    var body: some View {
        if let url = session.url {
            // `url` + `streamId` are PlayerView's playback identity, so they stay on the
            // playing channel until a zap burst settles; everything the viewer reads
            // (title, artwork, EPG, highlighted row, favourite) follows `visible` at once.
            let visible = visibleStream
            let visibleItemId = String(visible.streamId)
            ZStack(alignment: .bottom) {
                PlayerView(
                    url: url,
                    title: visible.name,
                    subtitle: liveSubtitle,
                    artworkURL: visible.streamIcon.flatMap { URL(string: $0) },
                    isLiveStream: true,
                    playlistId: playlist.id,
                    streamId: String(session.stream.streamId),
                    type: "live",
                    resumeTimeMs: session.resumeTimeMs,
                    epgChannelKey: EPGChannelKey.forXtream(visible),
                    canGoToPreviousChannel: (currentIndex ?? 0) > 0,
                    canGoToNextChannel: {
                        guard let index = currentIndex else { return false }
                        return index < queue.count - 1
                    }(),
                    onPreviousChannel: { jump(offset: -1) },
                    onNextChannel: { jump(offset: 1) },
                    canRecallLastChannel: lastChannel != nil,
                    onRecallLastChannel: onRecallLastChannel,
                    channelPanelSections: panelSections,
                    currentChannelPanelItemId: visibleItemId,
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
                .environment(\.playerOverlayPresentationID, reselectRevision ?? overlayPresentationID)

                // Its own container: the mode-driven removal below animates the panel
                // without putting an implicit animation on the player next to it.
                ZStack(alignment: .bottom) {
                    // Never over the mini card: there the strip covered the card and the
                    // tab bar, and nothing in reach could close it.
                    if showChannelSidePanel, overlayMode == .fullscreen, !sections.isEmpty {
                        LiveChannelSidePanel(
                            sections: panelSections,
                            currentItemId: visibleItemId,
                            onSelectChannel: { id in selectPanelItem(id: id) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: overlayMode)
                .zIndex(1)
            }
            .task(id: "\(playlist.id.uuidString)-\(visible.streamId)") {
                await refreshFavorite()
            }
            .task(id: panelBuildToken) {
                await completePanelSections()
            }
            .task(id: shortEPGTaskKey(for: visible)) {
                await loadShortEPGIfMissing(for: visible)
            }
            .onAppear {
                // From here on PlayerView gets the revision from this shell's state
                // (see `reselectRevision`); the value is the one it already has.
                if reselectRevision == nil { reselectRevision = overlayPresentationID }
            }
            .onChange(of: overlayPresentationID) { _, id in
                applyInitialSelectionIfNeeded(presentationID: id)
            }
            .onChange(of: overlayMode) { _, mode in
                // Minimized (pull-down, edge swipe, accessibility escape): the panel
                // stays closed, also after the card is expanded again.
                if mode == .mini, showChannelSidePanel {
                    showChannelSidePanel = false
                }
            }
            .onDisappear {
                // The player is gone: a burst that had not settled must not load anything.
                cancelPendingZap()
            }
        }
    }

    private func applyInitialSelectionIfNeeded(presentationID: UUID?) {
        // A newly presented channel replaces whatever a prev/next burst was about to load.
        cancelPendingZap()
        // PlayerView sees the new presentation in the same update as the selection
        // adopted below. Before the guard: the same channel presented again still
        // changes the revision, which is what lets PlayerView retry it.
        reselectRevision = presentationID
        let targetURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: initialStream.streamId)
        let targetResume = initialHistory?.lastTimeMs
        guard session.stream.streamId != initialStream.streamId
                || session.url != targetURL
                || session.resumeTimeMs != targetResume else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            showChannelSidePanel = false
            if session.stream.streamId != initialStream.streamId {
                lastChannelStream = session.stream
            }
            session = LivePlaybackSession(
                stream: initialStream,
                url: targetURL,
                resumeTimeMs: targetResume
            )
        }
    }

    /// Builds the categories `init` left out (cold cache, large catalog) off the main
    /// thread and swaps the full panel model in.
    private func completePanelSections() async {
        guard let token = panelBuildToken, completedPanel?.token != token else { return }
        let full = await LiveChannelPanelSectionCache.shared.resolveAll(sections, playlistId: playlist.id)
        guard !Task.isCancelled else { return }
        completedPanel = CompletedPanel(token: token, sections: full)
    }

    private func selectPanelItem(id: String) {
        guard let streamId = Int(id) else { return }
        // Lazy fallback: no whole-catalog copy just to find one channel of another category.
        guard let stream = queue.first(where: { $0.streamId == streamId })
            ?? sections.lazy.map(\.streams).joined().first(where: { $0.streamId == streamId }) else { return }
        if stream.streamId == session.stream.streamId,
           session.url == PlaybackURLBuilder(playlist: playlist).liveURL(streamId: stream.streamId) {
            // The channel that is already loaded was picked again. `switchTo` has nothing
            // to load, but the viewer may be looking at an ended or failed stream: pass
            // the pick on as a new presentation revision and let PlayerView, which knows
            // the playback state, decide whether to reload.
            cancelPendingZap()
            reselectRevision = UUID()
            return
        }
        // A pick from the list is deliberate, so it loads at once (no zap debounce).
        switchTo(stream: stream, resumeTimeMs: nil)
    }

    // MARK: Short-EPG fallback

    /// Re-keyed when the visible channel changes and when its guide entry appears or
    /// runs out, so the fallback is reconsidered at exactly those moments.
    private func shortEPGTaskKey(for stream: DBLiveStream) -> String {
        let hasNow = epgSnapshot?[EPGChannelKey.forXtream(stream)]?.now != nil
        return "\(playlist.id.uuidString)-\(stream.streamId)-\(hasNow ? "guide" : "none")"
    }

    /// Player now/next for a channel the XMLTV guide does not cover: asks the panel's
    /// `get_short_epg` once the viewer has settled on the channel. The request, the
    /// database write and the snapshot rebuild all run off the main thread inside
    /// `EPGStore.ensureShortEPG`; this task only waits for them.
    private func loadShortEPGIfMissing(for stream: DBLiveStream) async {
        guard playlist.kind == .xtream, playlist.epgEnabled else { return }
        guard epgSnapshot?[EPGChannelKey.forXtream(stream)]?.now == nil else { return }
        // Cancelled by the next zap (the task is keyed on the channel).
        try? await Task.sleep(nanoseconds: Self.shortEPGDelayNanoseconds)
        guard !Task.isCancelled else { return }
        guard LiveShortEPGAttempts.shared.claim(playlistId: playlist.id, streamId: stream.streamId) else { return }
        await EPGStore.shared.ensureShortEPG(playlist: playlist, stream: stream)
        // A zap during the request cancels it before anything is stored; the channel
        // must not stay blocked for an answer it never got. After a completed store
        // this is harmless: the guide check above returns before the next claim.
        if Task.isCancelled {
            LiveShortEPGAttempts.shared.release(playlistId: playlist.id, streamId: stream.streamId)
        }
    }

    /// Previous / next: the chrome moves to the target at once, the load is debounced so
    /// a burst of presses (buttons, headset, lock screen) opens only its last channel
    /// instead of one panel connection per press.
    private func jump(offset: Int) {
        // `currentIndex` follows the visible channel, so a burst keeps stepping from
        // where the previous press landed rather than from the channel still playing.
        guard let index = currentIndex else { return }
        let target = index + offset
        guard target >= 0, target < queue.count else { return }
        let targetStream = queue[target]
        pendingZapTask?.cancel()
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            pendingZapStream = targetStream
        }
        pendingZapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.zapDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            commitPendingZap()
        }
    }

    private func commitPendingZap() {
        guard let stream = pendingZapStream else {
            pendingZapTask = nil
            return
        }
        switchTo(stream: stream, resumeTimeMs: nil)
    }

    /// Drops a pending prev/next burst; the chrome falls back to the playing channel.
    private func cancelPendingZap() {
        pendingZapTask?.cancel()
        pendingZapTask = nil
        guard pendingZapStream != nil else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            pendingZapStream = nil
        }
    }

    private func switchTo(stream: DBLiveStream, resumeTimeMs: Int?) {
        let targetURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: stream.streamId)
        if session.stream.streamId == stream.streamId, session.url == targetURL {
            // Already playing (a burst can come back to where it started): nothing to load.
            cancelPendingZap()
            return
        }
        // Every committed switch supersedes a burst that is still waiting.
        pendingZapTask?.cancel()
        pendingZapTask = nil
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            lastChannelStream = session.stream
            pendingZapStream = nil
            session = LivePlaybackSession(
                stream: stream,
                url: targetURL,
                resumeTimeMs: resumeTimeMs
            )
        }
    }

    private func refreshFavorite() async {
        let streamId = visibleStream.streamId
        let value = (try? await AppDatabase.shared.read { db in
            try DBFavorite
                .filter(Column("streamId") == streamId
                    && Column("playlistId") == playlist.id
                    && Column("type") == "live")
                .fetchCount(db) > 0
        }) ?? false
        guard !Task.isCancelled, visibleStream.streamId == streamId else { return }
        isFavorite = value
    }

    private func toggleFavorite() {
        let streamId = visibleStream.streamId
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
            } catch {
                if visibleStream.streamId == streamId { isFavorite.toggle() }
            }
        }
    }
}

struct LivePlaybackSession: Equatable {
    var stream: DBLiveStream
    var url: URL?
    var resumeTimeMs: Int?
}

/// Remembers which channels the short-EPG fallback already asked the panel about, so
/// a channel without guide data is not queried again on every zap past it.
final class LiveShortEPGAttempts {
    static let shared = LiveShortEPGAttempts()

    /// A channel is asked again after this long: one answer covers only the next few
    /// programmes, and a panel that had nothing may have data later.
    static let retryInterval: TimeInterval = 30 * 60

    private var lastAttempt: [String: Date] = [:]

    /// True when a request for this channel may go out now. The attempt is recorded,
    /// whatever its outcome; only a cancelled request is taken back with `release`.
    func claim(playlistId: UUID, streamId: Int, now: Date = Date()) -> Bool {
        let key = "\(playlistId.uuidString)-\(streamId)"
        if let last = lastAttempt[key], now.timeIntervalSince(last) < Self.retryInterval {
            return false
        }
        lastAttempt[key] = now
        return true
    }

    /// Forgets an attempt whose request was cancelled before the panel answered.
    func release(playlistId: UUID, streamId: Int) {
        lastAttempt["\(playlistId.uuidString)-\(streamId)"] = nil
    }
}

/// Reference box behind `LiveStreamsView.playbackModelMemo`: filling it from a tap
/// handler must not invalidate the view the way a value-type @State write would.
private final class LivePlaybackModelMemo {
    struct Model {
        let queue: [DBLiveStream]
        let sections: [LiveChannelCategorySection]
    }

    var model: Model?
}

/// Per-category memo of the channel-panel display model for the Xtream live shell.
///
/// Mapping every stream to a `ChannelPanelItem` costs one `URL(string:)` per channel and
/// used to run on the main thread for the whole catalog at every player open. An entry is
/// reused for as long as its category's title and streams are unchanged; only the most
/// recently used playlist is kept, so the footprint stays bounded by one catalog.
final class LiveChannelPanelSectionCache {
    static let shared = LiveChannelPanelSectionCache()

    struct Resolution {
        let sections: [ChannelPanelSection]
        /// False when some categories were left out for `resolveAll` to build.
        let isComplete: Bool
    }

    private struct Entry {
        let title: String
        /// Source the section was built from. `Array ==` short-circuits on a shared
        /// buffer, so validating an unchanged category is O(1).
        let streams: [DBLiveStream]
        let section: ChannelPanelSection
    }

    /// Up to this many uncached channels are mapped inline (a few milliseconds); above
    /// it only the current category is, so a cold open of a huge catalog does not stall
    /// the tap that opened the player.
    private static let inlineBuildLimit = 1500

    private var playlistId: UUID?
    private var entries: [String: Entry] = [:]

    /// Synchronous resolution for `LivePlayerShell.init`. Returns every category when all
    /// of them are cached or cheap to build; otherwise the cached ones plus the category
    /// holding `currentStreamId`, in their original order, flagged incomplete.
    func resolve(
        _ sections: [LiveChannelCategorySection],
        playlistId: UUID,
        currentStreamId: Int
    ) -> Resolution {
        adopt(playlistId)
        var resolved = sections.map { cachedSection(for: $0) }
        let missing = resolved.indices.filter { resolved[$0] == nil }
        guard !missing.isEmpty else {
            return Resolution(sections: resolved.compactMap { $0 }, isComplete: true)
        }

        let missingChannelCount = missing.reduce(0) { $0 + sections[$1].streams.count }
        if missingChannelCount <= Self.inlineBuildLimit {
            for index in missing {
                resolved[index] = buildAndStore(sections[index])
            }
            return Resolution(sections: resolved.compactMap { $0 }, isComplete: true)
        }

        let currentIndex = sections.firstIndex { section in
            section.streams.contains(where: { $0.streamId == currentStreamId })
        }
        if let currentIndex {
            if resolved[currentIndex] == nil {
                resolved[currentIndex] = buildAndStore(sections[currentIndex])
            }
        } else if missing.count == sections.count, let first = missing.first {
            // Nothing cached and the channel is in no category (e.g. a history entry):
            // build one category anyway so the player still offers its channel list.
            resolved[first] = buildAndStore(sections[first])
        }
        return Resolution(
            sections: resolved.compactMap { $0 },
            isComplete: !resolved.contains(where: { $0 == nil })
        )
    }

    /// Full resolution; categories missing from the cache are built off the main thread.
    func resolveAll(
        _ sections: [LiveChannelCategorySection],
        playlistId: UUID
    ) async -> [ChannelPanelSection] {
        adopt(playlistId)
        var resolved = sections.map { cachedSection(for: $0) }
        let missing = resolved.indices.filter { resolved[$0] == nil }
        guard !missing.isEmpty else { return resolved.compactMap { $0 } }

        let pending = missing.map { sections[$0] }
        let built = await Task.detached(priority: .userInitiated) {
            pending.map { LiveChannelPanelSectionCache.makePanelSection($0) }
        }.value

        // Another playlist may have taken the cache over while this was building.
        let canStore = self.playlistId == playlistId
        for (offset, index) in missing.enumerated() {
            resolved[index] = built[offset]
            if canStore {
                let source = pending[offset]
                entries[source.id] = Entry(title: source.title, streams: source.streams, section: built[offset])
            }
        }
        return resolved.compactMap { $0 }
    }

    private func adopt(_ playlistId: UUID) {
        guard self.playlistId != playlistId else { return }
        self.playlistId = playlistId
        entries.removeAll()
    }

    private func cachedSection(for section: LiveChannelCategorySection) -> ChannelPanelSection? {
        guard let entry = entries[section.id],
              entry.title == section.title,
              entry.streams == section.streams else { return nil }
        return entry.section
    }

    private func buildAndStore(_ section: LiveChannelCategorySection) -> ChannelPanelSection {
        let built = Self.makePanelSection(section)
        entries[section.id] = Entry(title: section.title, streams: section.streams, section: built)
        return built
    }

    /// `nonisolated`: also runs inside the detached task in `resolveAll`.
    nonisolated private static func makePanelSection(_ section: LiveChannelCategorySection) -> ChannelPanelSection {
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
}
