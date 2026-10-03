import SwiftUI
import GRDB

/// Grup (group-title) başlıklı yatay raflar. Xtream Canlı TV görünümü ile aynı desen.
struct M3UChannelsView: View {
    static let hiddenCategoryType = "m3u"

    let playlist: Playlist
    @ObservedObject private var store = M3UContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay
    @Environment(\.epgGuideEnabled) private var epgGuideEnabled

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    /// The search whose hits are on screen; nil while the store's own lists are shown.
    /// It is set together with its result and never before it, so the list on screen
    /// stays what it was (the full catalog, or the previous hits) until the new hits
    /// exist, and it survives leaving the screen and coming back.
    @State private var appliedSearch: M3UGroupSearch.Result?

    /// Kategori atlama: picker sheet açık mı, ve en son talep edilen grup (scrollTo için).
    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    /// A history card that was tapped although its channel cannot be played any more.
    @State private var unavailableHistoryItem: DBWatchHistory?
    /// Channel whose schedule a card's menu asked for.
    @State private var scheduleChannel: DBM3UChannel?

    /// Everything a search result depends on. The revision stands for the channel
    /// lists: comparing the lists themselves walks the whole catalog after a refresh
    /// that changed nothing.
    private struct FilterKey: Equatable {
        let query: String
        let revision: Int
        let activePlaylistId: UUID?
    }

    private var isStoreCurrent: Bool { playlist.id == store.activePlaylistId }

    /// Groups in list order, before the hidden ones are taken out. Without a search these
    /// are the store's own arrays: nothing is mirrored into view state, so there is no
    /// moment in which the store has channels and the screen does not.
    private var groups: [String] {
        guard isStoreCurrent else { return [] }
        return appliedSearch?.groups ?? store.groupNames
    }

    private var channelsByGroup: [String: [DBM3UChannel]] {
        guard isStoreCurrent else { return [:] }
        return appliedSearch?.channelsByGroup ?? store.channelsByGroup
    }

    /// Shelf listesinde gösterilecek gruplar (gizlenenler çıkarılır). Picker tüm grupları görür.
    private var visibleShelfGroups: [String] {
        let all = groups
        let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: Self.hiddenCategoryType)
        guard !hidden.isEmpty else { return all }
        return all.filter { !hidden.contains($0) }
    }

    private var pickerEntries: [CategoryPickerSheet.Entry] {
        let byGroup = channelsByGroup
        return groups.map { group in
            CategoryPickerSheet.Entry(
                id: group,
                name: M3UContentStore.displayName(forGroup: group),
                count: byGroup[group]?.count ?? 0
            )
        }
    }

    var body: some View {
        // Once per pass: the hidden set is read from UserDefaults.
        let shelfGroups = visibleShelfGroups
        Group {
            if !isStoreCurrent || (store.isLoading && store.channels.isEmpty && !isRefreshing) {
                // Also the frame before the dashboard has asked the store for this
                // playlist: nothing is known yet, which is not the same as "no channels".
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.2)
                    Text(L("m3u.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.channels.isEmpty {
                if let loadError = store.loadError {
                    CatalogLoadErrorView(message: loadError) {
                        Task { await store.loadPlaylist(playlist) }
                    }
                } else {
                    emptyPlaylistState
                }
            } else if shelfGroups.isEmpty {
                if appliedSearch != nil {
                    CatalogEmptyView(.noSearchResults)
                } else {
                    allHiddenState
                }
            } else {
                shelvesList(shelfGroups)
            }
        }
        .m3uScheduleDestination($scheduleChannel, playlist: playlist) { channel in
            present(channel)
        }
        .toolbar {
            if epgGuideEnabled {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        EPGGuideView(source: .m3u(playlist))
                    } label: {
                        Label(L("epg.guide.title"), systemImage: "calendar.day.timeline.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    M3UFavoritesView(playlist: playlist)
                } label: {
                    Label(L("favorites.title"), systemImage: "star.fill")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    openCategoryPicker()
                } label: {
                    Label(L("list.jump_to_category"), systemImage: "list.bullet.indent")
                }
                .disabled(groups.isEmpty)
            }
        }
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerSheet(
                title: L("category_picker.title"),
                entries: pickerEntries,
                playlistId: playlist.id,
                type: Self.hiddenCategoryType
            ) { id in
                showingCategoryPicker = false
                pendingScrollTarget = id
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L("m3u.search_placeholder")
        )
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            // Boş aramaya geçişte debounce bekletme yok — tam listeyi anında göster.
            if new.trimmingCharacters(in: .whitespaces).isEmpty {
                clearSearch()
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = new
            }
        }
        .onChange(of: isSearchActive) { _, active in
            if !active {
                debounceTask?.cancel()
                searchText = ""
                clearSearch()
            }
        }
        .task(id: FilterKey(query: debouncedQuery, revision: store.revision, activePlaylistId: store.activePlaylistId)) {
            await recomputeFilter()
        }
        .alert(L("loading.error.title"), isPresented: Binding(
            get: { store.refreshError != nil && isStoreCurrent },
            set: { if !$0 { store.refreshError = nil } }
        )) {
            Button(L("common.ok"), role: .cancel) {
                store.refreshError = nil
            }
            Button(L("common.try_again")) {
                // Runs the refresh that failed again; loading the stored list a second
                // time would bring back exactly what is already on screen.
                Task { await Self.refreshCatalog(for: playlist) }
            }
        } message: {
            Text(store.refreshError ?? "")
        }
        .modifier(M3UUnavailableHistoryAlert(item: $unavailableHistoryItem))
    }

    /// Back to the full list at once. The store's lists are read directly, so there is
    /// nothing to copy and nothing to wait for.
    private func clearSearch() {
        debouncedQuery = ""
        if appliedSearch != nil { appliedSearch = nil }
    }

    /// The trigger is re-armed here, where the picker opens, so picking the same group
    /// twice is still a change (nil, then the id) and needs no timer to reset it.
    private func openCategoryPicker() {
        pendingScrollTarget = nil
        showingCategoryPicker = true
    }

    private func shelvesList(_ shelfGroups: [String]) -> some View {
        let itemsByGroup = channelsByGroup
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // İzlemeye devam: arama yokken üstte.
                    if appliedSearch == nil {
                        ContinueWatchingRow(
                            playlist: playlist,
                            destination: {
                                M3UWatchHistoryScreen(playlist: playlist)
                            },
                            onPlay: { item in
                                presentHistoryItem(item)
                            }
                        )
                    }

                    ForEach(shelfGroups, id: \.self) { group in
                        M3UGroupShelfRow(
                            playlist: playlist,
                            group: group,
                            items: itemsByGroup[group] ?? [],
                            onChannelSelected: { channel in
                                present(channel)
                            },
                            onScheduleRequested: { channel in
                                scheduleChannel = channel
                            }
                        )
                        .equatable()
                        .id(group)
                    }
                }
            }
            .refreshable { await refreshFromPull() }
            .onChange(of: pendingScrollTarget) { _, target in
                guard let target else { return }
                // A jump, not a scroll: an animated scroll builds every lazy row it
                // passes on the way, each with its own image prefetch.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// A playlist without channels. Scrollable, so it can still be pulled to refresh:
    /// a list that came back empty once is otherwise stuck that way.
    private var emptyPlaylistState: some View {
        GeometryReader { proxy in
            ScrollView {
                CatalogEmptyView(.noItems(title: L("m3u.empty.no_channel"), systemImage: "tv.slash"))
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .refreshable { await refreshFromPull() }
        }
    }

    /// Every group is hidden. That is not a search without hits, and the way out is
    /// the category list, where groups are shown again.
    private var allHiddenState: some View {
        ContentUnavailableView {
            Label(L("m3u.empty.all_hidden.title"), systemImage: "eye.slash")
        } description: {
            Text(L("m3u.empty.all_hidden.message"))
        } actions: {
            Button(L("category_picker.title")) {
                openCategoryPicker()
            }
        }
    }

    @State private var isRefreshing = false

    private func refreshFromPull() async {
        isRefreshing = true
        defer { isRefreshing = false }
        // Bağımsız Task: refreshable iptali isteklere yayılmasın (bkz. LiveStreamsView).
        let work = Task { await Self.refreshCatalog(for: playlist) }
        await work.value
    }

    /// Pull-to-refresh: URL tabanlı playlist'te tam yeniden indirme + import (ayarlardaki
    /// yenilemeyle aynı yol); yerel dosyalı playlist'te yalnızca DB'den yeniden yükleme
    /// (dosya yeniden seçilmeden içerik değişemez).
    ///
    /// A failure goes to the store's `refreshError`, not to `loadError`: the stored list
    /// is still on screen and still valid, and "try again" has to mean this download.
    static func refreshCatalog(for openedWith: Playlist) async {
        let store = M3UContentStore.shared
        store.refreshError = nil
        // The row as it is stored now, not the value the screen was opened with: the
        // import writes name and source back, and Settings may have changed the source
        // since (a list reloaded from a file has no URL any more).
        let playlistId = openedWith.id
        let stored = try? await AppDatabase.shared.read { db in
            try Playlist.fetchOne(db, key: playlistId)
        }
        let playlist = stored ?? openedWith
        let url = playlist.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            await store.reloadIfActive(playlist: playlist)
            return
        }
        do {
            let content = try await M3UService().fetchRemote(urlString: url)
            let parsed = try await M3UParser.parseAsync(content)
            try await M3UImporter.replace(
                playlist: playlist,
                channels: parsed.channels,
                epgURL: parsed.epgURL
            )
            await store.reloadIfActive(playlist: playlist)
        } catch {
            // Only while the playlist is still open: the error of a list the viewer
            // has left would come up over another one.
            guard store.activePlaylistId == playlist.id else { return }
            Log.error("M3U", "refresh failed: \(error)")
            store.refreshError = NetworkErrorText.describe(error)
        }
    }

    // MARK: - Filter

    private func recomputeFilter() async {
        let query = debouncedQuery.trimmingCharacters(in: .whitespaces)
        guard isStoreCurrent, !query.isEmpty else {
            if appliedSearch != nil { appliedSearch = nil }
            return
        }
        let revision = store.revision
        // Coming back to the screen (a pop, a tab switch) restarts this task with
        // nothing new to compute: the hits on screen are still the answer.
        if let applied = appliedSearch, applied.query == query, applied.revision == revision { return }

        let groups = store.groupNames
        let byGroup = store.channelsByGroup
        let result = await CatalogTextSearch.detached {
            M3UGroupSearch.run(query: query, revision: revision, groups: groups, channelsByGroup: byGroup)
        }

        // A scan that was cancelled stopped early; its result is not a result. The
        // query is compared as well: the field may have been emptied while this ran.
        guard !Task.isCancelled,
              debouncedQuery.trimmingCharacters(in: .whitespaces) == query else { return }
        appliedSearch = result
    }

    // MARK: - Playback

    private func present(_ channel: DBM3UChannel) {
        // Previous / next walk the channel's group as it is on screen (the hits, while a
        // search is applied). The lookup uses the store's canonical group key: a
        // localized label misses and leaves the player with a queue of one.
        let queue = channelsByGroup[M3UContentStore.groupKey(for: channel)] ?? [channel]
        guard let overlay = playerOverlay.injected else { return }
        M3UPlayback.present(channel, queue: queue, playlist: playlist, overlay: overlay)
    }

    /// Plays the item of a Continue Watching card. When its channel is not in the
    /// playlist any more, the card gets an alert instead of a tap that does nothing.
    private func presentHistoryItem(_ item: DBWatchHistory) {
        guard let overlay = playerOverlay.injected else { return }
        if !M3UPlayback.present(history: item, playlist: playlist, overlay: overlay) {
            unavailableHistoryItem = item
        }
    }
}

// MARK: - Search over groups

/// The Channels screen's search: which groups stay on screen for a query, and with
/// which channels. Runs in a detached task, so nothing in here may touch the main actor.
nonisolated enum M3UGroupSearch {
    nonisolated struct Result: Sendable {
        /// The trimmed query and the store revision the hits were computed from.
        let query: String
        let revision: Int
        /// Groups with at least one hit, in playlist order.
        let groups: [String]
        let channelsByGroup: [String: [DBM3UChannel]]
    }

    /// A group whose own name matches stays whole, and keeps the store's array (the
    /// shelf row then compares it by buffer identity). Any other group stays with the
    /// channels whose names match, or drops out when there are none.
    static func run(
        query: String,
        revision: Int,
        groups: [String],
        channelsByGroup: [String: [DBM3UChannel]]
    ) -> Result {
        // Folded once here; the per-name wrapper would fold the query for every channel.
        let prepared = CatalogTextSearch.Query(query)
        var hitGroups: [String] = []
        var hitsByGroup: [String: [DBM3UChannel]] = [:]
        for group in groups {
            // Nobody waits for a superseded search; the caller drops what comes back.
            if Task.isCancelled { break }
            let channels = channelsByGroup[group] ?? []
            // The name the viewer reads: the ungrouped bucket is stored under a fixed
            // key and shown under a localized title.
            if prepared.matches(M3UContentStore.displayName(forGroup: group)) {
                hitGroups.append(group)
                hitsByGroup[group] = channels
                continue
            }
            var hits: [DBM3UChannel] = []
            for (index, channel) in channels.enumerated() {
                if index.isMultiple(of: 2048), Task.isCancelled { break }
                if prepared.matches(channel.name) { hits.append(channel) }
            }
            if !hits.isEmpty {
                hitGroups.append(group)
                hitsByGroup[group] = hits
            }
        }
        return Result(query: query, revision: revision, groups: hitGroups, channelsByGroup: hitsByGroup)
    }
}

// MARK: - History

/// The full watch history of an M3U playlist. It wraps the shared list so that a card
/// whose channel is gone gets its alert on the screen the viewer is looking at: an alert
/// owned by the Channels screen underneath is not presented from there.
private struct M3UWatchHistoryScreen: View {
    let playlist: Playlist

    @Environment(\.playerOverlayController) private var playerOverlay
    @State private var unavailableItem: DBWatchHistory?

    var body: some View {
        WatchHistoryListView(playlist: playlist, typeFilter: nil) { item in
            guard let overlay = playerOverlay.injected else { return }
            if !M3UPlayback.present(history: item, playlist: playlist, overlay: overlay) {
                unavailableItem = item
            }
        }
        .modifier(M3UUnavailableHistoryAlert(item: $unavailableItem))
    }
}

/// Alert for a history card whose channel cannot be played any more: it left the
/// playlist in a re-import, its address changed (the channel id is derived from the
/// URL), or the adult filter hides it now.
///
/// Removing the row is offered, never done on its own: the row also holds the resume
/// position, and a channel that is merely filtered or briefly missing comes back.
struct M3UUnavailableHistoryAlert: ViewModifier {
    @Binding var item: DBWatchHistory?

    func body(content: Content) -> some View {
        content.alert(
            L("m3u.history.unavailable.title"),
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            presenting: item
        ) { item in
            Button(L("history.item.remove"), role: .destructive) {
                remove(item)
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(L("m3u.history.unavailable.message"))
        }
    }

    /// The card disappears through the history query that drew it.
    private func remove(_ item: DBWatchHistory) {
        Task { await DBWatchHistory.remove(id: item.id, from: .shared) }
    }
}

// MARK: - Logo look-ahead

/// Look-ahead logo prefetch along a run of channel cards (a shelf, a grid).
///
/// Every `stride`-th card is a trigger. When it appears it asks for the two strides of
/// logos after it; when it leaves it lets go of the first of the two, which by then is
/// on screen (scrolling on) or behind the viewer (scrolling back). The second stride is
/// the next trigger's to stop. So a prefetch lives only while its trigger is near the
/// screen, and a fling leaves one stride queued instead of the whole list.
///
/// The stopped ranges never overlap. The prefetcher keeps one task per image, whoever
/// asked for it, so stopping a range that another trigger still wants would cancel it
/// for both.
struct M3ULogoLookAhead {
    let stride: Int
    /// What the cards give `CachedImage`; a prefetch built differently never hits.
    let side: CGFloat
    let loadProfile: ImageLoadProfile

    func cardAppeared(at index: Int, in items: [DBM3UChannel]) {
        guard let range = Self.startRange(forCardAt: index, stride: stride, count: items.count) else { return }
        let urls = Self.logoURLs(in: items[range])
        guard !urls.isEmpty else { return }
        ListImagePrefetch.start(urls: urls, width: side, height: side, loadProfile: loadProfile)
    }

    func cardDisappeared(at index: Int, in items: [DBM3UChannel]) {
        guard let range = Self.stopRange(forCardAt: index, stride: stride, count: items.count) else { return }
        let urls = Self.logoURLs(in: items[range])
        guard !urls.isEmpty else { return }
        ListImagePrefetch.stop(urls: urls, width: side, height: side, loadProfile: loadProfile)
    }

    /// Items a trigger card asks for when it appears; nil for a card that is no trigger
    /// or has nothing after it.
    nonisolated static func startRange(forCardAt index: Int, stride: Int, count: Int) -> Range<Int>? {
        range(after: index, strides: 2, stride: stride, count: count)
    }

    /// Items a trigger card lets go of when it leaves: the stride right after it.
    nonisolated static func stopRange(forCardAt index: Int, stride: Int, count: Int) -> Range<Int>? {
        range(after: index, strides: 1, stride: stride, count: count)
    }

    nonisolated private static func range(after index: Int, strides: Int, stride: Int, count: Int) -> Range<Int>? {
        guard stride > 0, index >= 0, index % stride == 0 else { return nil }
        let start = index + 1
        let end = min(count, start + strides * stride)
        return start < end ? start..<end : nil
    }

    nonisolated static func logoURLs(in channels: ArraySlice<DBM3UChannel>) -> [URL] {
        channels.compactMap { $0.tvgLogo.flatMap { URL(string: $0) } }
    }
}

// MARK: - Group shelf (horizontal preview)

private enum M3UShelf {
    /// Look-ahead trigger distance while a shelf is scrolled sideways: every fifth card
    /// asks for the ten logos after it.
    static let lookAheadStride = 5
    static let cardSpacing = BrowseMetrics.tileShelfSpacing
}

struct M3UGroupShelfRow: View, Equatable {
    let playlist: Playlist
    let group: String
    let items: [DBM3UChannel]
    var onChannelSelected: ((DBM3UChannel) -> Void)? = nil
    var onScheduleRequested: ((DBM3UChannel) -> Void)? = nil

    static func == (lhs: M3UGroupShelfRow, rhs: M3UGroupShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.group == rhs.group &&
        lhs.items == rhs.items
    }

    @Environment(\.posterMetrics) private var posterMetrics

    /// How many leading logos are warmed up when the row comes on screen. Starts at the
    /// minimum and follows the row's width once it is laid out.
    @State private var headCount = ListImagePrefetch.minHeadCount

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(M3UContentStore.displayName(forGroup: group)) {
                M3UGroupDetailView(playlist: playlist, group: group)
            } accessory: {
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contextMenu {
                HideCategoryMenuButton(
                    categoryId: group,
                    type: M3UChannelsView.hiddenCategoryType,
                    playlistId: playlist.id
                )
            }

            if items.isEmpty {
                Text(L("live.empty.no_channel_in_category"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, BrowseMetrics.pageMargin)
            } else {
                let items = items
                let lookAhead = lookAhead
                let cardWidth = posterMetrics.liveShelfLabelWidth
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: M3UShelf.cardSpacing) {
                        // Index and channel side by side without materializing the group:
                        // a lazy map over the indices costs nothing to build, while an
                        // enumerated copy is one allocation of the whole group per body.
                        ForEach(
                            items.indices.lazy.map { (index: $0, channel: items[$0]) },
                            id: \.channel.id
                        ) { entry in
                            M3UChannelCard(
                                channel: entry.channel,
                                width: cardWidth,
                                iconSize: posterMetrics.liveShelfIcon,
                                imageLoadProfile: .shelf,
                                onChannelSelected: onChannelSelected,
                                onScheduleRequested: onScheduleRequested
                            )
                            .onAppear { lookAhead.cardAppeared(at: entry.index, in: items) }
                            .onDisappear { lookAhead.cardDisappeared(at: entry.index, in: items) }
                        }
                    }
                    .padding(.horizontal, BrowseMetrics.pageMargin)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    headCount = ListImagePrefetch.headCount(
                        itemWidth: cardWidth,
                        spacing: M3UShelf.cardSpacing,
                        containerWidth: width
                    )
                }
                // On appear, and again when the laid-out width asks for more: what is
                // already queued is not queued twice.
                .task(id: headCount) { prefetchHead(count: headCount, start: true) }
                .onDisappear {
                    // The widest head there can be: also covers a count that shrank
                    // (rotation) while the row was on screen.
                    prefetchHead(count: ListImagePrefetch.maxHeadCount, start: false)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var lookAhead: M3ULogoLookAhead {
        M3ULogoLookAhead(
            stride: M3UShelf.lookAheadStride,
            side: posterMetrics.liveShelfIcon,
            loadProfile: .shelf
        )
    }

    /// Starts or stops the prefetch of the row's leading logos: what one swipe reaches
    /// before the per-card look-ahead takes over.
    private func prefetchHead(count: Int, start: Bool) {
        let urls = M3ULogoLookAhead.logoURLs(in: items.prefix(count))
        guard !urls.isEmpty else { return }
        let side = posterMetrics.liveShelfIcon
        if start {
            ListImagePrefetch.start(urls: urls, width: side, height: side, loadProfile: .shelf)
        } else {
            ListImagePrefetch.stop(urls: urls, width: side, height: side, loadProfile: .shelf)
        }
    }
}

// MARK: - Channel card

struct M3UChannelCard: View {
    /// What the card's context menu offers.
    enum MenuKind: Equatable {
        /// Play, the favourite toggle and, while the guide is on, the schedule.
        case browse
        /// A cell of the favourites screen: removing it.
        case favorites
    }

    let channel: DBM3UChannel
    var width: CGFloat = 120
    var iconSize: CGFloat = 120
    var imageLoadProfile: ImageLoadProfile = .standard
    var menu: MenuKind = .browse
    var onChannelSelected: ((DBM3UChannel) -> Void)? = nil
    var onScheduleRequested: ((DBM3UChannel) -> Void)? = nil

    @Environment(\.epgLineReserved) private var epgLineReserved
    @Environment(\.epgGuideEnabled) private var epgGuideEnabled

    var body: some View {
        Button {
            onChannelSelected?(channel)
        } label: {
            VStack(alignment: .center, spacing: 10) {
                CachedImage(
                    url: channel.tvgLogo.flatMap { URL(string: $0) },
                    width: iconSize,
                    height: iconSize,
                    cornerRadius: BrowseMetrics.tileCornerRadius,
                    iconName: "tv",
                    loadProfile: imageLoadProfile
                )
                .cardHover(cornerRadius: BrowseMetrics.tileCornerRadius)

                Text(channel.name)
                    .tileTitleStyle(width: width)

                if epgLineReserved {
                    EPGNowNextSlot(channelKey: EPGChannelKey.forM3U(channel), width: width)
                }
            }
        }
        .buttonStyle(.cardPress)
        .accessibilityIdentifier("card.m3u.\(channel.id)")
        .accessibilityActions {
            M3UFavoriteMenuButton(channel: channel)
            if epgGuideEnabled, let onScheduleRequested {
                ScheduleMenuButton { onScheduleRequested(channel) }
            }
        }
        .cardContextMenuShape(cornerRadius: BrowseMetrics.tileCornerRadius)
        .contextMenu {
            switch menu {
            case .browse:
                PlayMenuButton { onChannelSelected?(channel) }
                M3UFavoriteMenuButton(channel: channel)
                if epgGuideEnabled, let onScheduleRequested {
                    ScheduleMenuButton { onScheduleRequested(channel) }
                }
                // The only place an M3U film can be downloaded from. Live streams
                // are not single files and offer nothing here.
                if let url = M3UParser.sanitizedURL(from: channel.url) {
                    let cls = M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle)
                    if !cls.isLive {
                        M3UDownloadMenuItems(
                            id: DownloadManager.idFor(m3uChannel: channel.playlistId, channelId: channel.id),
                            playlistId: channel.playlistId,
                            streamId: channel.id,
                            title: channel.name,
                            secondaryTitle: channel.groupTitle,
                            imageURL: channel.tvgLogo,
                            remoteURL: url,
                            containerExtension: cls.containerExtension
                        )
                    }
                }
            case .favorites:
                M3UFavoriteMenuButton(channel: channel)
            }
        }
    }
}

/// "Add to Favorites" / "Remove from Favorites" for an M3U channel.
///
/// The state is read when the menu is built, not observed: a card that observed the
/// store would re-render with every toggle, together with every card a lazy stack keeps.
private struct M3UFavoriteMenuButton: View {
    let channel: DBM3UChannel

    var body: some View {
        let isFavorite = M3UFavoriteStore.shared.isFavorite(channelId: channel.id)
        Button {
            let channel = channel
            Task {
                // The store toggles; this keeps the tap to what the label promised.
                let store = M3UFavoriteStore.shared
                guard store.isFavorite(channelId: channel.id) == isFavorite else { return }
                await store.toggle(channel: channel)
            }
        } label: {
            Label(
                isFavorite ? L("favorites.remove") : L("favorites.add"),
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }
    }
}

extension View {
    /// Pushes the schedule of the channel `channel` holds; `play` starts the channel
    /// from its programme sheet.
    func m3uScheduleDestination(
        _ channel: Binding<DBM3UChannel?>,
        playlist: Playlist,
        play: @escaping (DBM3UChannel) -> Void
    ) -> some View {
        navigationDestination(item: channel) { channel in
            ChannelEPGDetailView(
                playlist: playlist,
                channelKey: EPGChannelKey.forM3U(channel) ?? "",
                displayName: channel.name,
                iconURL: channel.tvgLogo.flatMap { URL(string: $0) },
                liveStream: nil,
                onPlayChannel: { play(channel) }
            )
        }
    }
}

// MARK: - Group detail (grid)

struct M3UGroupDetailView: View {
    let playlist: Playlist
    let group: String

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// Hits of the search that is on screen; nil while the group itself is shown.
    @State private var appliedSearch: AppliedSearch?
    @State private var scheduleChannel: DBM3UChannel?

    @ObservedObject private var store = M3UContentStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay

    private struct AppliedSearch {
        let query: String
        let revision: Int
        let items: [DBM3UChannel]
    }

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
    }

    /// The group straight from the store: there in the first frame of the push, with
    /// no copy held by the view.
    private var groupItems: [DBM3UChannel] {
        guard playlist.id == store.activePlaylistId else { return [] }
        return store.channelsByGroup[group] ?? []
    }

    private var items: [DBM3UChannel] {
        appliedSearch?.items ?? groupItems
    }

    var body: some View {
        M3UGroupGridContent(
            items: items,
            contentID: .catalog(playlist.id, appliedSearch?.revision ?? store.revision, appliedSearch?.query ?? ""),
            isSearchResult: appliedSearch != nil,
            onChannelSelected: { channel in
                present(channel)
            },
            onScheduleRequested: { channel in
                scheduleChannel = channel
            }
        )
        .equatable()
        .m3uScheduleDestination($scheduleChannel, playlist: playlist) { channel in
            present(channel)
        }
        .navigationTitle(M3UContentStore.displayName(forGroup: group))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("live.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            // An emptied field shows the whole group at once.
            if new.trimmingCharacters(in: .whitespaces).isEmpty {
                debouncedQuery = ""
                if appliedSearch != nil { appliedSearch = nil }
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = new
            }
        }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .task(id: SearchKey(query: debouncedQuery, revision: store.revision)) { await recomputeSearch() }
    }

    private func recomputeSearch() async {
        let query = debouncedQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            if appliedSearch != nil { appliedSearch = nil }
            return
        }
        let revision = store.revision
        // The task also restarts when the screen comes back; the hits are still right.
        if let applied = appliedSearch, applied.query == query, applied.revision == revision { return }

        let base = groupItems
        let hits = await CatalogTextSearch.detached {
            CatalogTextSearch.rankedFilter(base, search: query) { $0.name }
        }
        // A cancelled scan returns an empty list, which must not be shown as "no results".
        guard !Task.isCancelled,
              debouncedQuery.trimmingCharacters(in: .whitespaces) == query else { return }
        appliedSearch = AppliedSearch(query: query, revision: revision, items: hits)
    }

    private func present(_ channel: DBM3UChannel) {
        // Bu detay ekranında queue = bu grubun tüm kanalları (arama varsa filtrelenmiş).
        guard let overlay = playerOverlay.injected else { return }
        M3UPlayback.present(channel, queue: items, playlist: playlist, overlay: overlay)
    }
}

struct M3UGroupGridContent: View, Equatable {
    enum ContentID: Equatable {
        case catalog(UUID, Int, String)
        case favorites(UUID, Int)
    }

    let items: [DBM3UChannel]
    /// Identifies the applied result without comparing every row on the main actor.
    let contentID: ContentID
    /// `items` is what a search left over, so an empty list means "no results" and not
    /// "no channels".
    var isSearchResult: Bool = false
    var menu: M3UChannelCard.MenuKind = .browse
    var onChannelSelected: ((DBM3UChannel) -> Void)? = nil
    var onScheduleRequested: ((DBM3UChannel) -> Void)? = nil

    /// Cheap signature compare (ignores the selection closure) so a parent re-render,
    /// one per keystroke and one per store publish, doesn't make SwiftUI re-process a
    /// group of tens of thousands of channels. Internal @State updates still invalidate
    /// normally. The closure may be the one of an earlier pass: callers read their
    /// current list through @State when it runs.
    static func == (lhs: M3UGroupGridContent, rhs: M3UGroupGridContent) -> Bool {
        lhs.contentID == rhs.contentID
            && lhs.isSearchResult == rhs.isSearchResult
            && lhs.menu == rhs.menu
            && lhs.items.count == rhs.items.count
            && lhs.items.first?.id == rhs.items.first?.id
            && lhs.items.last?.id == rhs.items.last?.id
    }

    @Environment(\.posterMetrics) private var posterMetrics

    /// Paginated render count so a huge group doesn't build one giant ForEach.
    @State private var visibleCount = Self.pageSize

    private static let pageSize = 90
    /// The next page is asked for this many cards before the end of the loaded ones.
    private static let pageLead = 15
    /// Every eighth card asks for the sixteen logos after it (see `M3ULogoLookAhead`).
    private static let lookAheadStride = 8

    private func loadMore() {
        guard visibleCount < items.count else { return }
        visibleCount += Self.pageSize
    }

    var body: some View {
        Group {
            if items.isEmpty {
                if isSearchResult {
                    CatalogEmptyView(.noSearchResults)
                } else {
                    CatalogEmptyView(.noItems(title: L("list.no_channel"), systemImage: "tv.slash"))
                }
            } else {
                let items = items
                let side = posterMetrics.liveGridIconSize
                let lookAhead = M3ULogoLookAhead(stride: Self.lookAheadStride, side: side, loadProfile: .grid)
                let columns = [
                    GridItem(.adaptive(minimum: side), spacing: posterMetrics.gridSpacing, alignment: .top)
                ]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(Indexed(items.prefix(visibleCount)), id: \.element.id) { index, channel in
                            M3UChannelCard(
                                channel: channel,
                                width: side,
                                iconSize: side,
                                imageLoadProfile: .grid,
                                menu: menu,
                                onChannelSelected: onChannelSelected,
                                onScheduleRequested: onScheduleRequested
                            )
                            .onAppear {
                                if index >= visibleCount - Self.pageLead { loadMore() }
                                lookAhead.cardAppeared(at: index, in: items)
                            }
                            .onDisappear { lookAhead.cardDisappeared(at: index, in: items) }
                        }
                    }
                    .padding()

                    if visibleCount < items.count {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
            }
        }
        // A list with another first channel is another list (a new search): back to one
        // page. A list that only grew or lost entries further down keeps its pages, so
        // removing a favourite deep in the grid does not shrink it under the viewer.
        // Unlike a task keyed on the list, this does not run again when the screen
        // comes back, which would drop the pages for no reason.
        .onChange(of: items.first?.id) {
            visibleCount = Self.pageSize
        }
    }
}

// MARK: - Player shell

/// M3U oynatma — canlı kanalda önceki/sonraki kanal, VOD'da tek oynatım (prev/next gizli).
/// Queue genellikle mevcut grubun kanal listesidir; boş bırakılırsa navigation pasif.
/// `resumeTimeMs` sadece ilk kanal açılırken kullanılır (Continue Watching girişleri için).
struct M3UPlayerShell: View {
    let playlist: Playlist
    let initialResumeMs: Int?
    private let initialChannel: DBM3UChannel
    private let initialQueue: [DBM3UChannel]
    /// Panelden başka bir kategoriye geçiş yapıldığında queue yeniden üretildiği için `@State`.
    @State private var queue: [DBM3UChannel]
    /// Playlist'in tüm canlı kanallarından (store yüklüyse) veya queue'dan (fallback) türetilen panel modeli.
    /// `.task(id:)` içinde, off-main hesaplanıp cache'lenir — body her render olduğunda yeniden üretilmez.
    @State private var livePanelSections: [ChannelPanelSection] = []
    @State private var currentIndex: Int
    @State private var resumeTimeMs: Int?
    @State private var showChannelSidePanel: Bool = false
    /// Queue index a prev/next burst has landed on but that is not loaded yet. The
    /// chrome follows it at once; playback waits for the burst to end, so only its last
    /// item opens a connection (same scheme as `LivePlayerShell`).
    @State private var pendingZapIndex: Int?
    @State private var pendingZapTask: Task<Void, Never>?
    /// The presentation revision PlayerView sees: the overlay's, adopted together with
    /// the selection of a new presentation, or a fresh one when the item that is already
    /// playing is picked again (see `LivePlayerShell.reselectRevision`).
    @State private var reselectRevision: UUID?
    @Environment(\.playerOverlayPresentationID) private var overlayPresentationID
    @Environment(\.playerOverlayMode) private var overlayMode
    @ObservedObject private var favorites = M3UFavoriteStore.shared
    @ObservedObject private var m3uStore = M3UContentStore.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared

    init(
        playlist: Playlist,
        channel: DBM3UChannel,
        queue: [DBM3UChannel] = [],
        resumeTimeMs: Int? = nil
    ) {
        self.playlist = playlist
        self.initialResumeMs = resumeTimeMs
        self.initialChannel = channel
        let resolvedQueue: [DBM3UChannel]
        let resolvedIndex: Int
        if let idx = queue.firstIndex(where: { $0.id == channel.id }) {
            resolvedQueue = queue
            resolvedIndex = idx
        } else {
            resolvedQueue = [channel]
            resolvedIndex = 0
        }
        self.initialQueue = resolvedQueue
        _queue = State(initialValue: resolvedQueue)
        _currentIndex = State(initialValue: resolvedIndex)
        _resumeTimeMs = State(initialValue: resumeTimeMs)
    }

    /// Trailing debounce for prev/next presses.
    private static let zapDebounceNanoseconds: UInt64 = 250_000_000

    private var channel: DBM3UChannel { queue[currentIndex] }

    /// Index the chrome presents: the pending zap target while a burst is being
    /// coalesced, otherwise the one that is playing.
    private var visibleIndex: Int {
        if let pending = pendingZapIndex, queue.indices.contains(pending) { return pending }
        return currentIndex
    }

    var body: some View {
        if let url = M3UParser.sanitizedURL(from: channel.url) {
            let classification = M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle)
            // `url`, `streamId` and the stream's own settings are PlayerView's playback
            // identity and stay on the playing item until a zap burst settles; what the
            // viewer reads (title, artwork, EPG, highlighted row, favourite) follows
            // `visible` at once.
            let activeChannel = channel
            let visibleIdx = visibleIndex
            let visible = queue[visibleIdx]
            // Queue tek elemansa prev/next anlamsız; aksi hâlde live (showLiveChannelSkip) ve
            // VOD (showVODQueueSkip) için callback'leri ikisi de açık bırakılır. PlayerView
            // `type` + `isLive` kombinasyonundan hangi UI'ı göstereceğine karar veriyor.
            let hasQueueNav = queue.count > 1
            let panelSections = classification.isLive ? livePanelSections : []
            ZStack(alignment: .bottom) {
                PlayerView(
                    url: url,
                    title: visible.name,
                    subtitle: visible.groupTitle,
                    artworkURL: visible.tvgLogo.flatMap { URL(string: $0) },
                    isLiveStream: classification.isLive,
                    playlistId: playlist.id,
                    streamId: activeChannel.id,
                    type: classification.playbackType,
                    resumeTimeMs: resumeTimeMs,
                    containerExtension: classification.containerExtension,
                    userAgent: activeChannel.userAgent,
                    epgChannelKey: classification.isLive ? EPGChannelKey.forM3U(visible) : nil,
                    canGoToPreviousChannel: hasQueueNav && visibleIdx > 0,
                    canGoToNextChannel: hasQueueNav && visibleIdx < queue.count - 1,
                    onPreviousChannel: hasQueueNav ? { jump(offset: -1) } : nil,
                    onNextChannel: hasQueueNav ? { jump(offset: 1) } : nil,
                    channelPanelSections: panelSections,
                    currentChannelPanelItemId: visible.id,
                    onSelectChannelPanelItem: { id in selectPanelItem(id: id) },
                    isLiveChannelSidePanelVisible: showChannelSidePanel,
                    onToggleLiveChannelSidePanel: panelSections.isEmpty ? nil : {
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
                    isFavorite: favorites.isFavorite(channelId: visible.id),
                    onToggleFavorite: {
                        Task { await favorites.toggle(channel: visible) }
                    }
                )
                .environment(\.playerOverlayPresentationID, reselectRevision ?? overlayPresentationID)

                // Its own container: the mode-driven removal below animates the panel
                // without putting an implicit animation on the player next to it.
                ZStack(alignment: .bottom) {
                    // Never over the mini card: there the strip covered the card and the
                    // tab bar, and nothing in reach could close it.
                    if showChannelSidePanel, overlayMode == .fullscreen, !panelSections.isEmpty {
                        LiveChannelSidePanel(
                            sections: panelSections,
                            currentItemId: visible.id,
                            onSelectChannel: { id in selectPanelItem(id: id) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: overlayMode)
                .zIndex(1)
            }
            .task(id: panelSectionsCacheKey) { await recomputeLivePanelSections() }
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
        // A newly presented item replaces whatever a prev/next burst was about to load.
        cancelPendingZap()
        // PlayerView sees the new presentation in the same update as the selection
        // adopted below. Before the guard: the same item presented again still changes
        // the revision, which is what lets PlayerView retry it.
        reselectRevision = presentationID
        guard channel.id != initialChannel.id
                || queue.map(\.id) != initialQueue.map(\.id)
                || resumeTimeMs != initialResumeMs else { return }
        guard let targetIndex = initialQueue.firstIndex(where: { $0.id == initialChannel.id }) else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            showChannelSidePanel = false
            queue = initialQueue
            currentIndex = targetIndex
            resumeTimeMs = initialResumeMs
        }
    }

    /// Store'daki playlist id, grup sayısı ve gizli kategori sürümü değiştiğinde `.task(id:)`
    /// yeniden tetiklensin diye birleşik anahtar.
    private var panelSectionsCacheKey: String {
        "\(m3uStore.activePlaylistId?.uuidString ?? "none")-\(m3uStore.groupNames.count)-\(playlist.id.uuidString)-\(hiddenStore.version)"
    }

    private func recomputeLivePanelSections() async {
        let useStore = m3uStore.activePlaylistId == playlist.id && !m3uStore.groupNames.isEmpty
        let snapshotNames = useStore ? m3uStore.groupNames : []
        let snapshotByGroup = useStore ? m3uStore.channelsByGroup : [:]
        let snapshotQueue = useStore ? [] : queue
        // Store anahtarlarıyla ve hidden-category id'leriyle tutarlı kalması için
        // kanonik etiket; başlıklar render sırasında displayName ile localize edilir.
        let ungroupedLabel = M3UContentStore.ungroupedLabel
        let hiddenIds = hiddenStore.hiddenIds(playlistId: playlist.id, type: M3UChannelsView.hiddenCategoryType)

        let result = await Task.detached(priority: .userInitiated) { () -> [ChannelPanelSection] in
            let raw: [ChannelPanelSection]
            if !snapshotNames.isEmpty {
                raw = Self.buildLivePanelSectionsFromStore(names: snapshotNames, byGroup: snapshotByGroup)
            } else {
                raw = Self.buildLivePanelSections(queue: snapshotQueue, ungroupedLabel: ungroupedLabel)
            }
            return raw.filter { !hiddenIds.contains($0.id) }
        }.value

        guard !Task.isCancelled else { return }
        livePanelSections = result
    }

    /// Previous / next: the chrome moves to the target at once, the load is debounced so
    /// a burst of presses (buttons, headset, lock screen) opens only its last item
    /// instead of one connection per press.
    private func jump(offset: Int) {
        // Steps from the visible item, so a burst keeps walking from where the previous
        // press landed rather than from the item still playing.
        let target = visibleIndex + offset
        guard target >= 0, target < queue.count else { return }
        pendingZapTask?.cancel()
        pendingZapIndex = target
        pendingZapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.zapDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            commitPendingZap()
        }
    }

    private func commitPendingZap() {
        pendingZapTask = nil
        guard let target = pendingZapIndex else { return }
        pendingZapIndex = nil
        // A burst can come back to where it started: nothing to load then.
        guard queue.indices.contains(target), target != currentIndex else { return }
        currentIndex = target
        resumeTimeMs = nil
    }

    /// Drops a pending prev/next burst; the chrome falls back to the playing item.
    private func cancelPendingZap() {
        pendingZapTask?.cancel()
        pendingZapTask = nil
        if pendingZapIndex != nil { pendingZapIndex = nil }
    }

    private func selectPanelItem(id: String) {
        // A pick from the list is deliberate: it supersedes a burst that is still
        // waiting and loads at once (no zap debounce).
        cancelPendingZap()
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            if idx == currentIndex {
                // The channel that is already loaded was picked again. There is nothing
                // to switch, but the viewer may be looking at an ended or failed stream:
                // pass the pick on as a new presentation revision and let PlayerView,
                // which knows the playback state, decide whether to reload.
                reselectRevision = UUID()
                return
            }
            currentIndex = idx
            resumeTimeMs = nil
            return
        }
        // Farklı kategoriden seçim yapıldı — queue'yu o kategorinin kanallarından yeniden üret.
        guard let section = livePanelSections.first(where: { section in
            section.items.contains(where: { $0.id == id })
        }) else { return }
        // A store-built section is keyed by its group, so the new queue comes from that
        // one group; indexing the whole catalog on the main thread for a single pick
        // stalled the tap on large playlists.
        let wanted = Set(section.items.map(\.id))
        let newQueue = (m3uStore.channelsByGroup[section.id] ?? []).filter { wanted.contains($0.id) }
        guard let newIdx = newQueue.firstIndex(where: { $0.id == id }) else { return }
        queue = newQueue
        currentIndex = newIdx
        resumeTimeMs = nil
    }

    nonisolated private static func buildLivePanelSections(queue: [DBM3UChannel], ungroupedLabel: String) -> [ChannelPanelSection] {
        var groupOrder: [String] = []
        var groups: [String: [DBM3UChannel]] = [:]
        for channel in queue {
            guard let url = M3UParser.sanitizedURL(from: channel.url) else { continue }
            let classification = M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle)
            guard classification.isLive else { continue }
            let raw = channel.groupTitle?.trimmingCharacters(in: .whitespaces)
            let key = (raw?.isEmpty == false ? raw! : ungroupedLabel)
            if groups[key] == nil {
                groupOrder.append(key)
                groups[key] = []
            }
            groups[key]?.append(channel)
        }
        return groupOrder.map { key in
            ChannelPanelSection(
                id: key,
                title: M3UContentStore.displayName(forGroup: key),
                items: (groups[key] ?? []).map { ch in
                    ChannelPanelItem(
                        id: ch.id,
                        name: ch.name,
                        iconURL: ch.tvgLogo.flatMap { URL(string: $0) }
                    )
                }
            )
        }
    }

    /// Store zaten playlist'i gruplamış; her kategori için sadece canlı kanalları filtrelemek yeterli.
    nonisolated private static func buildLivePanelSectionsFromStore(
        names: [String],
        byGroup: [String: [DBM3UChannel]]
    ) -> [ChannelPanelSection] {
        var result: [ChannelPanelSection] = []
        result.reserveCapacity(names.count)
        for name in names {
            let groupChannels = byGroup[name] ?? []
            var items: [ChannelPanelItem] = []
            items.reserveCapacity(groupChannels.count)
            for ch in groupChannels {
                guard let url = M3UParser.sanitizedURL(from: ch.url) else { continue }
                let classification = M3UStreamClassifier.classify(url: url, groupTitle: ch.groupTitle)
                guard classification.isLive else { continue }
                items.append(
                    ChannelPanelItem(
                        id: ch.id,
                        name: ch.name,
                        iconURL: ch.tvgLogo.flatMap { URL(string: $0) }
                    )
                )
            }
            if !items.isEmpty {
                result.append(ChannelPanelSection(id: name, title: M3UContentStore.displayName(forGroup: name), items: items))
            }
        }
        return result
    }
}

/// M3U kanallarının canlı yayın mı yoksa VOD (film/dizi) mu olduğunu tespit eder.
/// Seek bar, resume, control-center davranışları buna bağlı.
enum M3UStreamClassifier {
    struct Classification {
        /// `PlayerView.isLiveStream`'e verilir — false ise seek bar görünür, resume çalışır.
        let isLive: Bool
        /// `PlayerView.type` — watch history için ("live" | "vod").
        let playbackType: String
        /// URL'de belirgin bir dosya uzantısı varsa (mp4/mkv/...) player'a bilgi olarak iletilir.
        let containerExtension: String?
    }

    /// VOD göstergeleri: dosya uzantıları ve Xtream tarzı yollar.
    nonisolated private static let vodExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "webm", "flv", "m4v", "wmv", "3gp"]
    nonisolated private static let vodPathHints: [String] = ["/movie/", "/movies/", "/series/", "/vod/", "/films/", "/film/"]

    nonisolated static func classify(url: URL, groupTitle: String?) -> Classification {
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()

        if vodPathHints.contains(where: path.contains) {
            return Classification(isLive: false, playbackType: "vod", containerExtension: ext.isEmpty ? nil : ext)
        }
        if vodExtensions.contains(ext) {
            return Classification(isLive: false, playbackType: "vod", containerExtension: ext)
        }
        // Bilinen live indikatörleri veya uzantısız Xtream-style: canlı varsay.
        return Classification(isLive: true, playbackType: "live", containerExtension: ext.isEmpty ? nil : ext)
    }
}

// MARK: - Playback entry point

/// Starts an M3U channel in the player overlay. Every browse surface goes through here:
/// a shelf, a group grid, favourites, a history card.
///
/// A live channel opens at once. A film-like item first asks the database two things
/// the card does not know: where the viewer stopped, and whether a finished download
/// can stand in for the stream. Without the first, a half-watched film restarted at
/// 0:00 and the new playback overwrote the saved position; without the second, a
/// downloaded film was streamed again and failed offline.
enum M3UPlayback {
    /// The film whose lookups are still running. A newer tap replaces it, so two quick
    /// taps present once and an older pick cannot land on top of a newer one.
    private static var pendingPresentation: Task<Void, Never>?

    /// - Parameters:
    ///   - queue: what previous / next walk through, normally the channel's group.
    ///   - history: the row of the history card that was tapped; without it the saved
    ///     position is looked up.
    /// - Returns: false when the channel's address cannot be played at all.
    @discardableResult
    static func present(
        _ channel: DBM3UChannel,
        queue: [DBM3UChannel],
        playlist: Playlist,
        overlay: PlayerOverlayController,
        history: DBWatchHistory? = nil
    ) -> Bool {
        guard let url = M3UParser.sanitizedURL(from: channel.url) else { return false }
        pendingPresentation?.cancel()
        pendingPresentation = nil

        let classification = M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle)
        guard !classification.isLive else {
            overlay.present {
                M3UPlayerShell(
                    playlist: playlist,
                    channel: channel,
                    queue: queue
                )
            }
            return true
        }

        pendingPresentation = Task {
            let saved: DBWatchHistory?
            if let history, history.type == classification.playbackType {
                saved = history
            } else {
                saved = await savedPosition(channelId: channel.id, playlistId: playlist.id)
            }
            let fileURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(m3uChannel: playlist.id, channelId: channel.id)
            )
            guard !Task.isCancelled else { return }
            // M3U VOD is always typed "vod": a finished item starts over instead of
            // reopening in its last seconds.
            let resumeTimeMs = saved?.resumePositionMs(as: .film)
            if let fileURL {
                overlay.present(skipDownloadCheck: true) {
                    M3UDownloadedFilmPlayer(
                        playlistId: playlist.id,
                        channel: channel,
                        fileURL: fileURL,
                        resumeTimeMs: resumeTimeMs,
                        containerExtension: classification.containerExtension
                    )
                }
            } else {
                overlay.present {
                    M3UPlayerShell(
                        playlist: playlist,
                        channel: channel,
                        queue: queue,
                        resumeTimeMs: resumeTimeMs
                    )
                }
            }
        }
        return true
    }

    /// Plays the channel a history card stands for.
    ///
    /// - Returns: false when the card is dead: its channel is not in the visible list
    ///   any more (removed by a re-import, re-addressed, or hidden by the adult filter),
    ///   or its address cannot be played. The caller then offers to remove the row.
    static func present(
        history item: DBWatchHistory,
        playlist: Playlist,
        overlay: PlayerOverlayController
    ) -> Bool {
        let store = M3UContentStore.shared
        // A store that is still loading cannot tell a missing channel from one it has
        // not read yet; offering to delete the row on that ground would be wrong.
        guard store.activePlaylistId == playlist.id,
              !(store.isLoading && store.channels.isEmpty) else { return true }
        guard let channel = store.channel(id: item.streamId) else { return false }
        return present(
            channel,
            queue: store.queue(for: channel),
            playlist: playlist,
            overlay: overlay,
            history: item
        )
    }

    /// The history row the player keeps for a film-like channel (type "vod").
    private static func savedPosition(channelId: String, playlistId: UUID) async -> DBWatchHistory? {
        try? await AppDatabase.shared.read { db in
            try DBWatchHistory
                .filter(
                    Column("streamId") == channelId
                        && Column("playlistId") == playlistId
                        && Column("type") == "vod"
                )
                .fetchOne(db)
        }
    }
}

/// A finished download of a film-like M3U item, played from its file. Stream id and
/// type are the ones `M3UPlayerShell` uses, so the saved position is shared with the
/// streamed playback. No previous / next: the queue is a list of streams, as for a
/// downloaded Xtream film.
private struct M3UDownloadedFilmPlayer: View {
    let playlistId: UUID
    let channel: DBM3UChannel
    let fileURL: URL
    let resumeTimeMs: Int?
    let containerExtension: String?

    @ObservedObject private var favorites = M3UFavoriteStore.shared

    var body: some View {
        PlayerView(
            url: fileURL,
            title: channel.name,
            subtitle: channel.groupTitle,
            artworkURL: channel.tvgLogo.flatMap { URL(string: $0) },
            isLiveStream: false,
            playlistId: playlistId,
            streamId: channel.id,
            type: "vod",
            resumeTimeMs: resumeTimeMs,
            containerExtension: containerExtension,
            isFavorite: favorites.isFavorite(channelId: channel.id),
            onToggleFavorite: {
                Task { await favorites.toggle(channel: channel) }
            }
        )
    }
}
