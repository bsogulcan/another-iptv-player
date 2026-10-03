import Combine
import SwiftUI
import GRDB
import GRDBQuery

/// Everything the content of a Live browse screen depends on, apart from a grid's own
/// sort and filter. Each screen runs one task keyed on it and remembers the key that
/// task last applied, so coming back to the screen does no work.
private nonisolated struct LiveBrowseKey: Equatable {
    /// Debounced search text, trimmed.
    let query: String
    let streamsLoaded: Bool
    /// `PlaylistContentStore.liveRevision`. A scoped reload changes nothing else.
    let revision: Int
    /// `HiddenCategoryStore.version`; 0 on a screen that hidden categories do not affect.
    let hiddenVersion: Int
    let playlistId: UUID
    let activePlaylistId: UUID?

    /// False while the store still holds another playlist's lists.
    var isActive: Bool { playlistId == activePlaylistId }

    var withoutQuery: LiveBrowseKey {
        LiveBrowseKey(
            query: "",
            streamsLoaded: streamsLoaded,
            revision: revision,
            hiddenVersion: hiddenVersion,
            playlistId: playlistId,
            activePlaylistId: activePlaylistId
        )
    }
}

/// List building for the Live browse screens. Free of view state and `nonisolated`:
/// all of it runs inside detached tasks, which also means that a superseded run only
/// has to stop early; its caller throws the result away.
nonisolated enum LiveBrowseLists {
    /// A channel list together with its plain streams in the same order, which is the
    /// form the player takes its queue in.
    struct Arrangement: Sendable {
        let items: [LiveStreamWithCategory]
        let streams: [DBLiveStream]

        static let empty = Arrangement(items: [], streams: [])
    }

    struct Shelves: Sendable {
        let categories: [DBCategory]
        let itemsByCategory: [String: [LiveStreamWithCategory]]
    }

    /// Home shelves for a search, in catalog order: a category found by its name keeps
    /// all its channels, any other category keeps the channels that match and is left
    /// out without one.
    static func shelves(
        matching search: String,
        categories: [DBCategory],
        itemsByCategory: [String: [LiveStreamWithCategory]],
        hidden: Set<String>
    ) -> Shelves {
        let query = CatalogTextSearch.Query(search)
        var matched: [DBCategory] = []
        var matchedItems: [String: [LiveStreamWithCategory]] = [:]
        for category in categories where !hidden.contains(category.id) {
            if Task.isCancelled { break }
            let items = itemsByCategory[category.id] ?? []
            if query.matches(category.name) {
                matched.append(category)
                matchedItems[category.id] = items
                continue
            }
            let hits = items.filter { query.matches($0.stream.name) }
            if !hits.isEmpty {
                matched.append(category)
                matchedItems[category.id] = hits
            }
        }
        return Shelves(categories: matched, itemsByCategory: matchedItems)
    }

    /// "All Channels": every channel outside the hidden categories, ranked by relevance
    /// when `search` is not blank. With nothing hidden and no search the result shares
    /// the catalog's own buffer instead of copying it.
    static func allChannels(
        _ source: [LiveStreamWithCategory],
        hidden: Set<String>,
        search: String
    ) -> Arrangement {
        let visible = hidden.isEmpty
            ? source
            : source.filter { !hidden.contains($0.stream.categoryId ?? "") }
        let items = CatalogTextSearch.rankedFilter(visible, search: search) { $0.stream.name }
        if Task.isCancelled { return .empty }
        return Arrangement(items: items, streams: items.map { $0.stream })
    }

    /// A grid's own order on top of the caller's list: `filter`, then `sort`.
    static func arranged(
        _ items: [LiveStreamWithCategory],
        sort: LiveSortOption,
        filter: LiveStreamFilter
    ) -> Arrangement {
        let filtered = LiveStreamFilter.apply(items, filter)
        if Task.isCancelled { return .empty }
        let sorted = sort.apply(to: filtered)
        if Task.isCancelled { return .empty }
        return Arrangement(items: sorted, streams: sorted.map { $0.stream })
    }
}

/// What the shelf list of the Live home draws.
private struct LiveShelves {
    var categories: [DBCategory] = []
    var itemsByCategory: [String: [LiveStreamWithCategory]] = [:]
    /// The channels are not in yet. It travels with the items, so a shelf never gets
    /// "loaded" next to an item list that is only not there yet.
    var isLoading = false
    /// Inputs the shelves were built from; nil while the store holds another playlist.
    var key: LiveBrowseKey?
}

struct LiveStreamsView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay
    @Environment(\.epgGuideEnabled) private var epgGuideEnabled

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false
    /// Channel whose schedule a card's menu asked for.
    @State private var scheduleChannel: DBLiveStream?

    /// Shelves of the last search that finished. Without a query the shelves are read
    /// from the store in `body`: a copy held here would go stale whenever the store
    /// changes without one of this view's own inputs changing.
    @State private var searchResult: LiveShelves?
    /// Key the keyed task last ran to the end for.
    @State private var appliedKey: LiveBrowseKey?
    /// Message of the last failed catalog load. The dashboard's alert clears the store's
    /// copy when it is dismissed; this one keeps the retry on screen until a load gets
    /// through one of its phases.
    @State private var failedLoadMessage: String?

    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    /// Flattened queue + per-category sections for the shelves on screen. Built on the
    /// first channel tap and reused for as long as the shelves stay the same, so opening
    /// the player does not copy the whole catalog twice on the main thread every time.
    @StateObject private var playbackModelMemo = LivePlaybackModelMemo()

    private var browseKey: LiveBrowseKey {
        LiveBrowseKey(
            query: debouncedQuery.trimmingCharacters(in: .whitespaces),
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.liveRevision,
            hiddenVersion: hiddenStore.version,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    private var hiddenCategoryIds: Set<String> {
        hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
    }

    /// The shelves for `key`: the store's own lists, or the search result while a query
    /// is applied. A query whose first result is still on its way shows the unfiltered
    /// shelves, and one that follows another shows that one's result, until its own is in.
    private func shelves(for key: LiveBrowseKey, hidden: Set<String>) -> LiveShelves {
        guard key.isActive else { return LiveShelves(isLoading: true) }
        if !key.query.isEmpty, let searchResult { return searchResult }
        let categories = contentStore.liveCategories
        return LiveShelves(
            categories: hidden.isEmpty ? categories : categories.filter { !hidden.contains($0.id) },
            // The store's own buffers: the Equatable shelf rows compare them by identity.
            itemsByCategory: contentStore.liveStreamsByCategoryId,
            // A reload keeps the old lists up while it reads; only a catalog without
            // any channel yet is one that is still loading.
            isLoading: !contentStore.streamsLoaded && contentStore.liveStreams.isEmpty,
            key: key.withoutQuery
        )
    }

    private var livePlaybackModel: LivePlaybackModelMemo.Model {
        let shelves = shelves(for: browseKey, hidden: hiddenCategoryIds)
        return playbackModelMemo.model(for: shelves.key) {
            let sections = shelves.categories.compactMap { cat -> LiveChannelCategorySection? in
                let streams = shelves.itemsByCategory[cat.id]?.map(\.stream) ?? []
                guard !streams.isEmpty else { return nil }
                return LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams)
            }
            // Empty categories contribute nothing, so the queue is every channel of the
            // shelves on screen, in shelf order.
            return LivePlaybackModelMemo.Model(queue: sections.flatMap(\.streams), sections: sections)
        }
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

    /// A failed load that left nothing to show. A failed reload keeps the lists it had,
    /// and the dashboard's alert is all it needs.
    private var loadFailure: String? {
        guard playlist.id == contentStore.activePlaylistId,
              !contentStore.isLoading,
              !contentStore.streamsLoaded,
              contentStore.liveStreams.isEmpty else { return nil }
        return contentStore.loadError ?? failedLoadMessage
    }

    var body: some View {
        let key = browseKey
        let shelves = shelves(for: key, hidden: hiddenCategoryIds)
        Group {
            if let message = loadFailure {
                CatalogLoadErrorView(message: message) {
                    failedLoadMessage = nil
                    Task { await contentStore.loadPlaylist(playlist) }
                }
            } else if !shelves.categories.isEmpty {
                contentList(shelves)
            } else if contentStore.isLoading || shelves.isLoading {
                // Also while the categories are in and none of them is a live one: the
                // channels that follow can still bring the "uncategorized" shelf.
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(contentStore.loadingMessage ?? L("live.empty.preparing"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if key.query.isEmpty {
                CatalogEmptyView(.noItems(title: L("live.empty.no_category"), systemImage: "tv.slash"))
            } else {
                CatalogEmptyView(.noSearchResults)
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L("live.search_placeholder")
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
        .onChange(of: contentStore.loadError, initial: true) { _, error in
            if let error, !contentStore.streamsLoaded { failedLoadMessage = error }
        }
        .onChange(of: contentStore.liveRevision) { _, _ in
            // Every load phase that gets through bumps the revision and a failing one
            // does not, so this also catches a retry started from the dashboard's alert:
            // its categories bring the shelves back while its channels are still read.
            if contentStore.loadError == nil { failedLoadMessage = nil }
        }
        .task(id: key) { await apply(key) }
        .liveScheduleDestination($scheduleChannel, playlist: playlist)
        .toolbar {
            if epgGuideEnabled {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        EPGGuideView(source: .xtream(playlist))
                    } label: {
                        Label(L("epg.guide.title"), systemImage: "calendar.day.timeline.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AllLiveView(playlist: playlist)
                } label: {
                    Label(L("browse.all_live"), systemImage: "square.grid.2x2")
                }
                .disabled(contentStore.liveStreams.isEmpty)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Cleared here rather than after the jump, so that picking the
                    // category it already holds is still a change.
                    pendingScrollTarget = nil
                    showingCategoryPicker = true
                } label: {
                    Label(L("list.jump_to_category"), systemImage: "list.bullet.indent")
                }
                .disabled(contentStore.liveCategories.isEmpty)
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
        let model = livePlaybackModel
        playerOverlay.injected?.present(playlistId: playlist.id) {
            LivePlayerShell(
                playlist: playlist,
                queue: model.queue,
                sections: model.sections,
                initialStream: selection.stream,
                initialHistory: selection.history,
                subtitle: nil
            )
        }
    }

    private func presentHistoryItem(_ item: DBWatchHistory) {
        guard let url = historyURL(for: item) else { return }
        if item.type == "series" {
            playerOverlay.injected?.present(playlistId: playlist.id) {
                HistorySeriesPlayerShell(playlist: playlist, history: item, url: url)
            }
        } else if item.type == "live" {
            let model = livePlaybackModel
            let stream = liveStream(for: item, in: model.queue) ?? DBLiveStream(
                streamId: Int(item.streamId) ?? 0,
                name: item.title,
                streamIcon: item.imageURL,
                categoryId: nil,
                sortIndex: 0,
                playlistId: item.playlistId
            )
            playerOverlay.injected?.present(playlistId: playlist.id) {
                LivePlayerShell(
                    playlist: playlist,
                    queue: model.queue,
                    sections: model.sections,
                    initialStream: stream,
                    initialHistory: item,
                    subtitle: nil
                )
            }
        } else {
            playerOverlay.injected?.present(playlistId: playlist.id) {
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

    private func contentList(_ shelves: LiveShelves) -> some View {
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
                    ForEach(shelves.categories) { category in
                        LiveCategoryShelfRow(
                            playlist: playlist,
                            category: category,
                            items: shelves.itemsByCategory[category.id] ?? [],
                            onStreamSelected: { stream, history in
                                presentLiveSelection(LivePlayerSelection(stream: stream, history: history))
                            },
                            onScheduleRequested: { stream in
                                scheduleChannel = stream
                            },
                            isStreamsLoading: shelves.isLoading
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
                // A jump, not a glide: an animated scroll runs through every lazy shelf
                // on the way, and each of them starts loading its logos.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(target, anchor: .top)
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

    /// Brings the search result in line with `key`. Without a query there is nothing to
    /// compute, because `body` reads the shelves from the store; what is left of the
    /// previous key is dropped.
    private func apply(_ key: LiveBrowseKey) async {
        guard key != appliedKey else { return }
        // Built from other shelves. Dropped now rather than at the next tap, so the old
        // catalog's queue is not kept alive until then.
        playbackModelMemo.reset()
        guard key.isActive, !key.query.isEmpty else {
            searchResult = nil
            appliedKey = key
            return
        }
        let hidden = hiddenCategoryIds
        let categories = contentStore.liveCategories
        let itemsByCategory = contentStore.liveStreamsByCategoryId
        let isLoading = !contentStore.streamsLoaded && contentStore.liveStreams.isEmpty
        let search = key.query
        let result = await CatalogTextSearch.detached {
            LiveBrowseLists.shelves(
                matching: search,
                categories: categories,
                itemsByCategory: itemsByCategory,
                hidden: hidden
            )
        }
        guard !Task.isCancelled else { return }
        searchResult = LiveShelves(
            categories: result.categories,
            itemsByCategory: result.itemsByCategory,
            isLoading: isLoading,
            key: key
        )
        appliedKey = key
    }

    private func liveStream(for item: DBWatchHistory, in queue: [DBLiveStream]) -> DBLiveStream? {
        let streamId = Int(item.streamId) ?? 0
        if let match = queue.first(where: { $0.streamId == streamId }) {
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

struct LiveCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [LiveStreamWithCategory]
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil
    var onScheduleRequested: ((DBLiveStream) -> Void)? = nil
    var isStreamsLoading: Bool = false

    static func == (lhs: LiveCategoryShelfRow, rhs: LiveCategoryShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.category == rhs.category &&
        lhs.items == rhs.items &&
        lhs.isStreamsLoading == rhs.isStreamsLoading
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.epgGuideEnabled) private var epgGuideEnabled
    @StateObject private var headPrefetch = LiveShelfHeadPrefetch()

    private static let cardSpacing = BrowseMetrics.tileShelfSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(category.name) {
                LiveCategoryDetailView(playlist: playlist, category: category)
            }
            .accessibilityIdentifier("home.shelf.header.\(category.id)")
            .contextMenu {
                HideCategoryMenuButton(categoryId: category.id, type: "live", playlistId: playlist.id)
            }

            if items.isEmpty {
                if isStreamsLoading {
                    loadingPlaceholder
                } else {
                    Text(L("live.empty.no_channel_in_category"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, BrowseMetrics.pageMargin)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Self.cardSpacing) {
                        // The integer id: the Identifiable one is a string built from the
                        // stream and playlist ids, for every channel of the category.
                        ForEach(items, id: \.stream.streamId) { item in
                            LiveStreamCard(
                                playlistId: playlist.id,
                                stream: item.stream,
                                width: posterMetrics.liveShelfLabelWidth,
                                iconSize: posterMetrics.liveShelfIcon,
                                imageLoadProfile: .shelf
                            ) { stream, history in
                                onStreamSelected?(stream, history)
                            }
                            .liveCardMenu(
                                stream: item.stream,
                                playlistId: playlist.id,
                                guideEnabled: epgGuideEnabled,
                                play: { onStreamSelected?(item.stream, nil) },
                                schedule: onScheduleRequested
                            )
                        }
                    }
                    .padding(.horizontal, BrowseMetrics.pageMargin)
                }
                .onAppear {
                    headPrefetch.start(
                        urls: headIconURLs(limit: prefetchHeadCount),
                        side: posterMetrics.liveShelfIcon
                    )
                }
                .onDisappear { headPrefetch.stop() }
            }
        }
        .padding(.vertical, 6)
    }

    /// Stands in for the cards while the channels are not in yet. It is a card that is
    /// not drawn, so the row is exactly as tall as the loaded one, at every text size and
    /// with or without the guide line, and nothing below it moves when the channels arrive.
    private var loadingPlaceholder: some View {
        LiveStreamCard(
            playlistId: playlist.id,
            stream: DBLiveStream(streamId: 0, name: " ", playlistId: playlist.id),
            width: posterMetrics.liveShelfLabelWidth,
            iconSize: posterMetrics.liveShelfIcon,
            imageLoadProfile: .shelf
        )
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .padding(.horizontal, BrowseMetrics.pageMargin)
    }

    private var prefetchHeadCount: Int {
        ListImagePrefetch.headCount(
            itemWidth: posterMetrics.liveShelfLabelWidth,
            spacing: Self.cardSpacing,
            containerWidth: UIScreen.main.bounds.width
        )
    }

    private func headIconURLs(limit: Int) -> [URL] {
        items.prefix(limit)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
    }
}

struct LiveStreamCard: View {
    let playlistId: UUID
    let stream: DBLiveStream
    var width: CGFloat = 120
    var iconSize: CGFloat = 120
    var imageLoadProfile: ImageLoadProfile = .standard
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil

    @Environment(\.epgLineReserved) private var epgLineReserved

    var body: some View {
        Button(action: {
            onStreamSelected?(stream, nil)
        }) {
            VStack(alignment: .center, spacing: 10) {
                CachedImage(
                    url: stream.streamIcon.flatMap { URL(string: $0) },
                    width: iconSize,
                    height: iconSize,
                    cornerRadius: BrowseMetrics.tileCornerRadius,
                    iconName: "tv",
                    loadProfile: imageLoadProfile
                )
                .cardHover(cornerRadius: BrowseMetrics.tileCornerRadius)

                // Two lines whatever the name: every card of a row, and the
                // placeholder of a row that is still loading, has the same height.
                Text(stream.name)
                    .tileTitleStyle(width: width)

                if epgLineReserved {
                    EPGNowNextSlot(channelKey: EPGChannelKey.forXtream(stream), width: width)
                }
            }
        }
        .buttonStyle(.cardPress)
        .accessibilityIdentifier("card.live.\(stream.streamId)")
    }
}

extension View {
    /// The context menu of a channel card in the Live browse screens: Play, the
    /// favourite toggle and, while the guide is on, the channel's schedule.
    fileprivate func liveCardMenu(
        stream: DBLiveStream,
        playlistId: UUID,
        guideEnabled: Bool,
        play: @escaping () -> Void,
        schedule: ((DBLiveStream) -> Void)?
    ) -> some View {
        cardContextMenuShape(cornerRadius: BrowseMetrics.tileCornerRadius)
            .contextMenu {
                PlayMenuButton(action: play)
                FavoriteMenuButton(streamId: stream.streamId, type: "live", playlistId: playlistId)
                if guideEnabled, let schedule {
                    ScheduleMenuButton { schedule(stream) }
                }
            }
    }

    /// Pushes the schedule of the channel `channel` holds.
    fileprivate func liveScheduleDestination(_ channel: Binding<DBLiveStream?>, playlist: Playlist) -> some View {
        navigationDestination(item: channel) { stream in
            ChannelEPGDetailView(
                playlist: playlist,
                channelKey: EPGChannelKey.forXtream(stream) ?? "",
                displayName: stream.name,
                iconURL: stream.streamIcon.flatMap { URL(string: $0) },
                liveStream: stream
            )
        }
    }
}

/// The logo prefetch a shelf row started, kept so that leaving the screen stops exactly
/// that head. Rebuilding it on disappear would miss when the row was rotated or handed
/// other channels in between, and a wider guess would also cancel what other shelves
/// queued for the same logos on the shared prefetcher. Never publishes, like the memos
/// below, so the Equatable row is not invalidated by it.
private final class LiveShelfHeadPrefetch: ObservableObject {
    private var urls: [URL] = []
    private var side: CGFloat = 0

    func start(urls: [URL], side: CGFloat) {
        stop()
        guard !urls.isEmpty else { return }
        ListImagePrefetch.start(urls: urls, width: side, height: side, loadProfile: .shelf)
        self.urls = urls
        self.side = side
    }

    func stop() {
        guard !urls.isEmpty else { return }
        ListImagePrefetch.stop(urls: urls, width: side, height: side, loadProfile: .shelf)
        urls = []
    }
}

/// Outcome of a pushed list's keyed task.
private struct LiveListResult {
    /// Inputs it was computed for; a result for other inputs is stale but still the
    /// best thing to show until its successor is in.
    let key: LiveBrowseKey
    let items: [LiveStreamWithCategory]
    /// `items` as plain streams, when the task built them along the way.
    var streams: [DBLiveStream]? = nil
}

// MARK: - Category Detail View
struct LiveCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// Result of the last search that finished. Without a query the grid is handed the
    /// store's own array, so there is nothing to keep in sync here.
    @State private var searchResult: LiveListResult?
    @State private var appliedKey: LiveBrowseKey?
    @State private var scheduleChannel: DBLiveStream?

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay

    private var browseKey: LiveBrowseKey {
        LiveBrowseKey(
            query: debouncedQuery.trimmingCharacters(in: .whitespaces),
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.liveRevision,
            hiddenVersion: 0,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    var body: some View {
        let key = browseKey
        let source = key.isActive ? (contentStore.liveStreamsByCategoryId[category.id] ?? []) : []
        // A search keeps the list that is on screen until its own result is in.
        let items = key.query.isEmpty ? source : (searchResult?.items ?? source)
        let isSearchPending = !key.query.isEmpty && searchResult?.key != key
        LiveCategoryContent(
            playlist: playlist,
            items: items,
            isSourceLoading: !key.isActive || !contentStore.streamsLoaded || isSearchPending,
            isSearchResult: !key.query.isEmpty,
            onStreamSelected: { stream, queue in
                playerOverlay.injected?.present(playlistId: playlist.id) {
                    LivePlayerShell(
                        playlist: playlist,
                        queue: queue,
                        sections: [LiveChannelCategorySection(id: category.id, title: category.name, streams: queue)],
                        initialStream: stream,
                        initialHistory: nil,
                        subtitle: category.name
                    )
                }
            },
            onScheduleRequested: { stream in
                scheduleChannel = stream
            }
        )
        .equatable()
        .liveScheduleDestination($scheduleChannel, playlist: playlist)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("live.search_placeholder"))
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
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
            // The screen can come back (another tab, then this one again): the text in
            // the field must not stay ahead of the list for good.
            if debouncedQuery != searchText { debouncedQuery = searchText }
        }
        .task(id: key) { await apply(key) }
    }

    private func apply(_ key: LiveBrowseKey) async {
        guard key != appliedKey else { return }
        guard key.isActive, !key.query.isEmpty else {
            searchResult = nil
            appliedKey = key
            return
        }
        let base = contentStore.liveStreamsByCategoryId[category.id] ?? []
        let search = key.query
        let items = await CatalogTextSearch.detached {
            CatalogTextSearch.rankedFilter(base, search: search) { $0.stream.name }
        }
        // A cancelled scan returns nothing, which must not pass for "no match".
        guard !Task.isCancelled else { return }
        searchResult = LiveListResult(key: key, items: items)
        appliedKey = key
    }
}

/// Reference box for a grid's channel queue in the caller's order, filled on the first
/// tap. Like `LivePlaybackModelMemo`, an object that never publishes: filling it does
/// not invalidate the grid.
private final class LiveGridQueueMemo: ObservableObject {
    private var source: [LiveStreamWithCategory]?
    private var streams: [DBLiveStream] = []

    /// `Array ==` returns at once for a shared buffer, so asking again for the list the
    /// queue was built from costs nothing.
    func streams(of items: [LiveStreamWithCategory]) -> [DBLiveStream] {
        if let source, source == items { return streams }
        source = items
        streams = items.map(\.stream)
        return streams
    }

    func reset() {
        source = nil
        streams = []
    }
}

struct LiveCategoryContent: View, Equatable {
    let playlist: Playlist
    let items: [LiveStreamWithCategory]
    /// `items` as plain streams in the same order, when the caller has built them off
    /// the main thread. Without them the grid maps `items` on the first tap.
    var streams: [DBLiveStream]? = nil
    /// The caller's list is not final yet (the catalog is still loading, or a filter of
    /// the caller is still running): an empty list then means "not known yet".
    var isSourceLoading: Bool = false
    /// `items` is what a search left over: an empty list then means "no results".
    var isSearchResult: Bool = false
    /// Called with the tapped channel and with the channels of the grid in the order
    /// they are shown, which is the queue the player steps through.
    var onStreamSelected: ((DBLiveStream, [DBLiveStream]) -> Void)? = nil
    /// A card's menu asked for the channel's schedule.
    var onScheduleRequested: ((DBLiveStream) -> Void)? = nil

    /// Cheap signature compare (ignores the selection closure) so a parent @Published
    /// re-render doesn't force SwiftUI to re-process a huge channel list. Internal
    /// @State updates still invalidate normally.
    static func == (lhs: LiveCategoryContent, rhs: LiveCategoryContent) -> Bool {
        lhs.playlist.id == rhs.playlist.id
            && lhs.isSourceLoading == rhs.isSourceLoading
            && lhs.isSearchResult == rhs.isSearchResult
            && lhs.items.count == rhs.items.count
            && lhs.items.first?.stream.streamId == rhs.items.first?.stream.streamId
            && lhs.items.last?.stream.streamId == rhs.items.last?.stream.streamId
            && lhs.streams?.count == rhs.streams?.count
    }

    /// Everything the grid's own order depends on.
    private nonisolated struct ContentKey: Equatable {
        let itemsToken: Int
        let sort: LiveSortOption
        let filter: Int

        /// The grid shows the caller's list as it is.
        var keepsSourceOrder: Bool { sort == .defaultOrder && filter == 0 }
    }

    /// The caller's list after the grid's sort and filter.
    private struct Arranged {
        let key: ContentKey
        let items: [LiveStreamWithCategory]
        let streams: [DBLiveStream]
    }

    private enum Displayed {
        /// The caller's list as it is.
        case source
        case arranged(Arranged)
        /// The caller's list the grid last applied. The caller has handed over another
        /// one, which replaces it in the update that also resets the page count and the
        /// scroll position, so the new list is never drawn at the old list's offset.
        case previous([LiveStreamWithCategory])
        /// First display with a stored sort: the list has to be sorted before any of
        /// it can be shown.
        case pending
    }

    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.epgGuideEnabled) private var epgGuideEnabled

    @AppStorage(LiveSortOption.storageKey) private var sortOption: LiveSortOption = .defaultOrder
    /// Screen-local toggle filters (catch-up / EPG).
    @State private var filter: LiveStreamFilter = []
    /// Sort/filter output for `appliedKey`, computed off the main thread; nil while
    /// that key keeps the caller's order.
    @State private var arranged: Arranged?
    /// Inputs the grid shows. It changes together with the list, the page count and the
    /// scroll position, in one update, and only when an input really changed: coming
    /// back to the screen leaves all of them alone.
    @State private var appliedKey: ContentKey?
    /// The caller's list as of `appliedKey`. Shares its buffer, so keeping it costs nothing.
    @State private var appliedSource: [LiveStreamWithCategory] = []
    /// Paginated render count so a huge catalog doesn't build one giant ForEach.
    @State private var visibleCount = Self.pageSize
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @StateObject private var queueMemo = LiveGridQueueMemo()

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

    private var contentKey: ContentKey {
        ContentKey(itemsToken: itemsToken, sort: sortOption, filter: filter.rawValue)
    }

    private var isFilterActive: Bool {
        sortOption != .defaultOrder || !filter.isEmpty
    }

    /// What is on screen for `key`. The applied key decides, not `key` itself: after a
    /// sort or filter change, or a new list from the caller, the previous list stays up
    /// until the new one replaces it.
    /// Only the very first display has nothing applied yet; the caller's order is then
    /// shown directly, so a pushed grid is there in its first frame.
    private func displayed(for key: ContentKey) -> Displayed {
        guard let appliedKey else { return key.keepsSourceOrder ? .source : .pending }
        if !appliedKey.keepsSourceOrder, let arranged { return .arranged(arranged) }
        if appliedKey.itemsToken != key.itemsToken { return .previous(appliedSource) }
        return .source
    }

    private func shownItems(_ displayed: Displayed) -> [LiveStreamWithCategory] {
        switch displayed {
        case .source: return items
        case .arranged(let arranged): return arranged.items
        case .previous(let list): return list
        case .pending: return []
        }
    }

    /// Whether an empty list is the answer for `key` rather than a list still on its way.
    private func isSettled(_ displayed: Displayed, for key: ContentKey) -> Bool {
        switch displayed {
        // Sorting or filtering an empty list changes nothing.
        case .source: return true
        case .arranged(let arranged): return arranged.key == key
        case .previous, .pending: return false
        }
    }

    /// Makes the grid show `key`: the list in the new order, the first page of it, from
    /// the top.
    private func apply(_ key: ContentKey) async {
        guard key != appliedKey else { return }
        let source = items
        var result: Arranged?
        if !key.keepsSourceOrder {
            let sort = key.sort
            let filter = LiveStreamFilter(rawValue: key.filter)
            let arrangement = await CatalogTextSearch.detached {
                LiveBrowseLists.arranged(source, sort: sort, filter: filter)
            }
            // Superseded by a newer choice, whose own run will apply it. Without this
            // a slow sort could land after a fast one and leave the grid in an order
            // the menu does not show.
            guard !Task.isCancelled else { return }
            result = Arranged(key: key, items: arrangement.items, streams: arrangement.streams)
        }
        let isFirstDisplay = appliedKey == nil
        arranged = result
        appliedSource = source
        visibleCount = Self.pageSize
        if !isFirstDisplay { scrollPosition.scrollTo(edge: .top) }
        appliedKey = key
        queueMemo.reset()
        prefetch(result?.items ?? source)
    }

    private func loadMore(total: Int) {
        guard visibleCount < total else { return }
        visibleCount = min(visibleCount + Self.pageSize, total)
    }

    /// The channels of the grid in the order they are shown.
    private func playbackQueue() -> [DBLiveStream] {
        switch displayed(for: contentKey) {
        case .arranged(let arranged): return arranged.streams
        case .previous(let list): return queueMemo.streams(of: list)
        case .source, .pending: return streams ?? queueMemo.streams(of: items)
        }
    }

    var body: some View {
        let key = contentKey
        let displayed = displayed(for: key)
        let shown = shownItems(displayed)
        Group {
            if !shown.isEmpty {
                grid(shown)
            } else if isSourceLoading || !isSettled(displayed, for: key) {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isSearchResult || !filter.isEmpty {
                CatalogEmptyView(.noSearchResults)
            } else {
                CatalogEmptyView(.noItems(title: L("list.no_channel"), systemImage: "tv.slash"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortFilterMenu
            }
        }
        .task(id: key) { await apply(key) }
    }

    private func grid(_ shown: [LiveStreamWithCategory]) -> some View {
        let columns = [
            GridItem(
                .adaptive(minimum: posterMetrics.liveGridIconSize),
                spacing: posterMetrics.gridSpacing,
                alignment: .top
            )
        ]
        let total = shown.count
        return ScrollView {
            LazyVGrid(columns: columns, spacing: posterMetrics.gridRowSpacing) {
                ForEach(Indexed(shown.prefix(visibleCount)), id: \.element.stream.streamId) { index, item in
                    LiveStreamCard(
                        playlistId: playlist.id,
                        stream: item.stream,
                        width: posterMetrics.liveGridIconSize,
                        iconSize: posterMetrics.liveGridIconSize,
                        imageLoadProfile: .grid,
                        onStreamSelected: { stream, _ in
                            onStreamSelected?(stream, playbackQueue())
                        }
                    )
                    .liveCardMenu(
                        stream: item.stream,
                        playlistId: playlist.id,
                        guideEnabled: epgGuideEnabled,
                        play: { onStreamSelected?(item.stream, playbackQueue()) },
                        schedule: onScheduleRequested
                    )
                    // The next page is a counter bump, triggered from inside the lazy
                    // grid well before its end comes into view.
                    .onAppear { if index >= visibleCount - 15 { loadMore(total: total) } }
                }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
    }

    private func filterBinding(_ flag: LiveStreamFilter) -> Binding<Bool> {
        Binding(
            get: { filter.contains(flag) },
            set: { isOn in
                if isOn { filter.insert(flag) } else { filter.remove(flag) }
            }
        )
    }

    private var sortFilterMenu: some View {
        Menu {
            Picker(L("sort.title"), selection: $sortOption) {
                ForEach(LiveSortOption.allCases) { option in
                    Label(L(option.titleKey), systemImage: option.systemImage).tag(option)
                }
            }

            Section(L("filter.title")) {
                // Several can be on at once, so the menu stays open while they are
                // switched; the sort above and "clear" below still close it.
                Group {
                    Toggle(L("filter.catchup"), isOn: filterBinding(.catchup))
                    Toggle(L("filter.has_epg"), isOn: filterBinding(.hasEPG))
                }
                .menuActionDismissBehavior(.disabled)

                if !filter.isEmpty {
                    Button {
                        filter = []
                    } label: {
                        Label(L("filter.clear"), systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Label(
                L("sort.title"),
                systemImage: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
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
    @Environment(\.playerOverlayController) private var playerOverlay
    @AppStorage(LiveSortOption.storageKey) private var sortOption: LiveSortOption = .defaultOrder
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// Outcome of the last run of the keyed task: the list for a search or with hidden
    /// categories left out, and the plain streams of whatever list is shown.
    @State private var result: LiveListResult?
    @State private var appliedKey: LiveBrowseKey?
    @State private var scheduleChannel: DBLiveStream?

    /// Up to this many channels the player builds its channel panel on the tap, in well
    /// under a frame; there is nothing to prepare for it.
    private static let panelPrewarmMinimum = 1500

    private var browseKey: LiveBrowseKey {
        LiveBrowseKey(
            query: debouncedQuery.trimmingCharacters(in: .whitespaces),
            streamsLoaded: contentStore.streamsLoaded,
            revision: contentStore.liveRevision,
            hiddenVersion: hiddenStore.version,
            playlistId: playlist.id,
            activePlaylistId: contentStore.activePlaylistId
        )
    }

    /// The whole list as the one section the player's channel panel shows.
    private static func panelSection(_ streams: [DBLiveStream]) -> LiveChannelCategorySection {
        LiveChannelCategorySection(id: "all", title: L("browse.all_live"), streams: streams)
    }

    var body: some View {
        let key = browseKey
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
        // With nothing hidden and no search the list is the catalog itself, and the grid
        // gets the store's array without waiting for the task.
        let isCatalog = hidden.isEmpty && key.query.isEmpty
        let isCurrent = result?.key == key
        LiveCategoryContent(
            playlist: playlist,
            items: items(for: key, isCatalog: isCatalog, nothingHidden: hidden.isEmpty),
            streams: isCurrent ? result?.streams : nil,
            isSourceLoading: !key.isActive || !contentStore.streamsLoaded || (!isCatalog && !isCurrent),
            isSearchResult: !key.query.isEmpty,
            onStreamSelected: { stream, queue in
                playerOverlay.injected?.present(playlistId: playlist.id) {
                    LivePlayerShell(
                        playlist: playlist,
                        queue: queue,
                        sections: [Self.panelSection(queue)],
                        initialStream: stream,
                        initialHistory: nil,
                        subtitle: L("browse.all_live")
                    )
                }
            },
            onScheduleRequested: { stream in
                scheduleChannel = stream
            }
        )
        .equatable()
        .liveScheduleDestination($scheduleChannel, playlist: playlist)
        .navigationTitle(L("browse.all_live"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("live.search_placeholder"))
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
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
            // The screen can come back (another tab, then this one again): the text in
            // the field must not stay ahead of the list for good.
            if debouncedQuery != searchText { debouncedQuery = searchText }
        }
        .task(id: key) { await apply(key) }
    }

    private func items(for key: LiveBrowseKey, isCatalog: Bool, nothingHidden: Bool) -> [LiveStreamWithCategory] {
        guard key.isActive else { return [] }
        if isCatalog { return contentStore.liveStreams }
        // A result for other inputs stays up until its successor is in.
        if let result { return result.items }
        // First search with nothing hidden: the catalog stays up until the result is in.
        return nothingHidden ? contentStore.liveStreams : []
    }

    private func apply(_ key: LiveBrowseKey) async {
        guard key != appliedKey else { return }
        guard key.isActive else {
            result = nil
            appliedKey = key
            return
        }
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
        let source = contentStore.liveStreams
        let search = key.query
        // All work off the main thread; the catalog can be very large.
        let list = await CatalogTextSearch.detached {
            LiveBrowseLists.allChannels(source, hidden: hidden, search: search)
        }
        guard !Task.isCancelled else { return }
        result = LiveListResult(key: key, items: list.items, streams: list.streams)
        appliedKey = key
        await prewarmChannelPanel(for: list.streams)
    }

    /// The player lists this screen's queue as a single section, and builds that
    /// section's panel model on the tap that opens it when it is not cached: one icon
    /// URL per channel of the whole list. Done here instead, off the main thread, while
    /// the grid is already on screen. The cache recognises the array by its buffer, so
    /// this helps as long as the grid hands over these very streams, which it does in
    /// the default order; with a stored sort the first tap builds the model as before.
    private func prewarmChannelPanel(for streams: [DBLiveStream]) async {
        guard sortOption == .defaultOrder, streams.count > Self.panelPrewarmMinimum else { return }
        _ = await LiveChannelPanelSectionCache.shared.resolveAll(
            [Self.panelSection(streams)], playlistId: playlist.id
        )
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

/// Reference box behind `LiveStreamsView.playbackModelMemo`. It is an object that never
/// publishes, held as a `@StateObject`: filling it from a tap handler does not
/// invalidate the view, and the view's value stays comparable across parent updates,
/// which a fresh instance in a plain `@State` initial value never is.
private final class LivePlaybackModelMemo: ObservableObject {
    struct Model {
        let queue: [DBLiveStream]
        let sections: [LiveChannelCategorySection]
    }

    private var model: Model?
    /// Inputs of the shelves `model` was built from.
    private var key: LiveBrowseKey?

    /// The model for the shelves identified by `key`; built when the box is empty or
    /// holds the model of other shelves.
    func model(for key: LiveBrowseKey?, build: () -> Model) -> Model {
        if let model, self.key == key { return model }
        let built = build()
        model = built
        self.key = key
        return built
    }

    func reset() {
        model = nil
        key = nil
    }
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
