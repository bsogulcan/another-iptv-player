import SwiftUI
import Combine

/// One channel row in the guide.
///
/// `nonisolated` because the rows are built in a detached task: a playlist has
/// tens of thousands of channels, and every one needs its guide key resolved.
nonisolated struct EPGGuideRow: Identifiable, Equatable, Hashable, Sendable {
    let id: String            // unique per channel; the channel id on M3U playlists
    let channelKey: String    // resolved stored key for programme lookup
    let displayName: String
    let iconURL: URL?
    let liveStream: DBLiveStream?   // Xtream only (catch-up + live play)
    /// Category the channel belongs to, used to group rows under collapsible
    /// headers. `categoryId` is the stable grouping key; `categoryTitle` is shown.
    let categoryId: String
    let categoryTitle: String
}

/// One category of the guide with its channels, both in display order.
nonisolated struct EPGGuideSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    var rows: [EPGGuideRow]
}

/// What the guide derives from the channel list in one pass over it.
nonisolated struct EPGGuideRowSet: Sendable {
    /// Categories in first-appearance order, each with its channels.
    var sections: [EPGGuideSection] = []
    /// Stored guide keys of the listed channels: the programme layouts are built
    /// for these only.
    var channelKeys: Set<String> = []
    /// At least one channel was left out because its category is hidden.
    var hasHiddenChannels = false

    var isEmpty: Bool { sections.isEmpty }

    private var sectionIndexById: [String: Int] = [:]

    fileprivate mutating func append(_ row: EPGGuideRow) {
        channelKeys.insert(row.channelKey)
        if let index = sectionIndexById[row.categoryId] {
            sections[index].rows.append(row)
        } else {
            sectionIndexById[row.categoryId] = sections.count
            sections.append(EPGGuideSection(id: row.categoryId, title: row.categoryTitle, rows: [row]))
        }
    }
}

/// A collapsible category header row in the guide.
struct EPGGuideSectionHeader: Identifiable, Equatable {
    let id: String
    let title: String
    let channelCount: Int
    let collapsed: Bool
}

/// One rendered row of the guide: either a category header or a channel.
enum EPGGuideItem: Identifiable, Equatable {
    case header(EPGGuideSectionHeader)
    case channel(EPGGuideRow)

    var id: String {
        switch self {
        case .header(let header): return "hdr:" + header.id
        case .channel(let row): return row.id
        }
    }
}

/// A positioned programme cell (or a "no data" filler when `programme == nil`).
struct EPGCellLayout: Identifiable, Equatable, Sendable {
    let id: String
    let programme: EPGProgramme?
    let x: CGFloat
    let width: CGFloat
}

struct EPGRowLayout: Equatable, Sendable {
    let cells: [EPGCellLayout]
    let version: Int
}

@MainActor
final class EPGGuideViewModel: ObservableObject {
    enum Source: Equatable {
        case xtream(Playlist)
        case m3u(Playlist)

        var playlist: Playlist {
            switch self {
            case .xtream(let p), .m3u(let p): return p
            }
        }
    }

    enum GuideState: Equatable {
        case loading, notConfigured, empty, ready
        /// Every channel with a guide sits in a category the user hid.
        case allHidden
        /// The channel list itself could not be read.
        case catalogFailed
    }

    let source: Source
    /// The flat sequence the grid renders: category headers interleaved with the
    /// channels of each (expanded) category. Recomputed only when the row set,
    /// the search result, or a collapse toggle changes — never per scroll frame.
    @Published private(set) var items: [EPGGuideItem] = []
    /// Category ids the user has collapsed. Persisted per playlist so the guide
    /// reopens in the same shape.
    @Published private(set) var collapsedCategories: Set<String>
    @Published private(set) var layouts: [String: EPGRowLayout] = [:]
    @Published var selectedDay: Date
    /// Day chips: yesterday … +7 days around the current day. Stored, because the
    /// view reads them on every pass and the calendar arithmetic is not free.
    @Published private(set) var availableDays: [Date]
    @Published private(set) var state: GuideState = .loading
    /// The programmes of the selected day could not be read. The grid stays, with
    /// the channels and empty rows.
    @Published private(set) var programmeError: String?
    @Published var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            updateSearch()
        }
    }

    /// Categories in display order with their channels, hidden categories left
    /// out. Built once per load; `items` is derived from this plus the search
    /// result and collapse state.
    private var sections: [EPGGuideSection] = []
    private var channelKeys: Set<String> = []
    /// `sections` narrowed to the channels matching `searchQuery`. Nil while no
    /// search is active, and for the first keystroke until its result is in.
    private var matchedSections: [EPGGuideSection]?
    /// Same notion of "blank" as the matcher: nothing but whitespace. Text without
    /// a letter or digit is a search, and it matches nothing.
    private var isSearching: Bool { searchQuery.contains { !$0.isWhitespace } }

    /// Grouping key/title for channels that belong to no category.
    nonisolated private static let uncategorizedId = "__epg_uncategorized__"

    private var layoutVersion = 0
    private let calendar = Calendar.current
    private let now: () -> Date
    private var today: Date
    /// The selected day is the current one, so it moves on with the calendar. A
    /// day the user picked on purpose stays put.
    private(set) var followsToday = true
    private var loadGeneration = 0
    /// A load or a day switch is running. `cancelLoading()` turns it into
    /// `needsReload`, so work that was cut short runs again when the screen is back.
    private var isWorking = false
    private var needsReload = false
    /// The rows of the load in flight are not in yet. A day switch at that point
    /// must not settle for new layouts: it would drop the pending rows with them.
    private var rowBuildPending = false
    private var rowTask: Task<EPGGuideRowSet, Never>?
    private var programmeTask: Task<[String: [EPGProgramme]], Error>?
    private var layoutTask: Task<[String: EPGRowLayout], Never>?
    private var searchTask: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()

    /// Shared fallback for channels without listings. Keeping one value avoids a
    /// dictionary entry and cell array for every no-data channel.
    private(set) var emptyLayout = EPGRowLayout(cells: [], version: 0)

    /// `now` exists for tests, which move the clock across midnight.
    init(source: Source, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = now
        let today = Calendar.current.startOfDay(for: now())
        self.today = today
        self.selectedDay = today
        self.availableDays = Self.days(around: today, calendar: Calendar.current)
        self.collapsedCategories = Self.loadCollapsed(playlistId: source.playlist.id)
        observeCatalog()
        observeDayChange()
    }

    var playlist: Playlist { source.playlist }
    var dayStart: Date { calendar.startOfDay(for: selectedDay) }

    /// True when there is more than one category to show — headers are only worth
    /// drawing then; a single-category playlist renders as a flat list.
    var hasCategories: Bool { sections.count > 1 }

    /// A search ran and matched no channel.
    var hasNoSearchResults: Bool { matchedSections?.isEmpty == true }

    /// The screen has nothing current to show: it was never loaded, or its last
    /// load was cut short when it went off screen.
    var needsLoad: Bool { state == .loading || needsReload }

    private static func days(around today: Date, calendar: Calendar) -> [Date] {
        (-1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// Rebuilds `items` from the sections, honouring the search result and collapse
    /// state. While searching, collapse is ignored so matches are always visible.
    private func recomputeItems() {
        let searching = matchedSections != nil
        let showHeaders = sections.count > 1
        var result: [EPGGuideItem] = []
        for section in matchedSections ?? sections {
            guard !section.rows.isEmpty else { continue }
            let collapsed = !searching && collapsedCategories.contains(section.id)
            if showHeaders {
                result.append(.header(EPGGuideSectionHeader(
                    id: section.id, title: section.title,
                    channelCount: section.rows.count, collapsed: collapsed)))
            }
            if !collapsed {
                result.append(contentsOf: section.rows.map { EPGGuideItem.channel($0) })
            }
        }
        items = result
    }

    func toggleCategory(_ id: String) {
        if collapsedCategories.contains(id) {
            collapsedCategories.remove(id)
        } else {
            collapsedCategories.insert(id)
        }
        persistCollapsed()
        recomputeItems()
    }

    func setAllCollapsed(_ collapsed: Bool) {
        collapsedCategories = collapsed ? Set(sections.map(\.id)) : []
        persistCollapsed()
        recomputeItems()
    }

    // MARK: - Search

    /// Filters off the main actor: the matcher folds every channel name, which on
    /// a large playlist is too much for a keystroke. The list on screen stays as
    /// it is until the result arrives, and a newer keystroke cancels the scan.
    private func updateSearch() {
        searchTask?.cancel()
        searchTask = nil
        guard isSearching else {
            if matchedSections != nil {
                matchedSections = nil
                recomputeItems()
            }
            return
        }
        let all = sections
        let search = searchQuery
        searchTask = Task { [weak self] in
            let matched = await CatalogTextSearch.detached {
                Self.filter(all, search: search)
            }
            // A cancelled scan returns a partial result.
            guard !Task.isCancelled, let self else { return }
            self.matchedSections = matched
            self.recomputeItems()
        }
    }

    /// The channels of `sections` whose name matches `search`, by the app's shared
    /// matcher. Sections left without a match are dropped.
    nonisolated static func filter(_ sections: [EPGGuideSection], search: String) -> [EPGGuideSection] {
        let query = CatalogTextSearch.Query(search)
        var result: [EPGGuideSection] = []
        for section in sections {
            var rows: [EPGGuideRow] = []
            for (offset, row) in section.rows.enumerated() {
                if offset % cancellationStride == 0, Task.isCancelled { return result }
                if query.matches(row.displayName) { rows.append(row) }
            }
            if !rows.isEmpty {
                result.append(EPGGuideSection(id: section.id, title: section.title, rows: rows))
            }
        }
        return result
    }

    /// Channels handled between two looks at the task's cancellation flag.
    nonisolated private static let cancellationStride = 2048

    /// Grouping key + display title for a channel's category, folding empty ids and
    /// names into a shared "Uncategorized" bucket.
    nonisolated private static func category(id: String?, name: String?) -> (id: String, title: String) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedId = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty && trimmedId.isEmpty {
            return (uncategorizedId, L("content.uncategorized"))
        }
        let key = trimmedId.isEmpty ? trimmedName : trimmedId
        let title = trimmedName.isEmpty ? trimmedId : trimmedName
        return (key, title)
    }

    // MARK: - Collapse persistence

    private static func collapseKey(_ playlistId: UUID) -> String {
        "epg.collapsedCategories.\(playlistId.uuidString)"
    }

    private static func loadCollapsed(playlistId: UUID) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: collapseKey(playlistId)) ?? [])
    }

    private func persistCollapsed() {
        UserDefaults.standard.set(Array(collapsedCategories), forKey: Self.collapseKey(playlist.id))
    }

    // MARK: - Loading

    func load() async {
        let interval = BrowsePerformance.begin("GuideLoad")
        defer { BrowsePerformance.end("GuideLoad", interval) }
        loadGeneration += 1
        let generation = loadGeneration
        isWorking = true
        needsReload = false
        rowBuildPending = true

        let built = await buildRows()
        guard generation == loadGeneration, !Task.isCancelled else { return }
        rowBuildPending = false
        sections = built.sections
        channelKeys = built.channelKeys
        // A search result holds rows of the previous build. It stays on screen for
        // the moment the new scan takes, rather than flashing the full list.
        if isSearching { updateSearch() }
        recomputeItems()

        if built.isEmpty {
            isWorking = false
            if catalogIsLoading {
                // The channels are still being read; their arrival loads again.
                state = .loading
            } else if catalogFailed {
                state = .catalogFailed
            } else if playlist.kind == .m3u, playlist.effectiveEPGURL == nil {
                // Distinguish "no EPG source configured" from "no channels".
                state = .notConfigured
            } else if built.hasHiddenChannels {
                state = .allHidden
            } else {
                state = .empty
            }
            return
        }
        await rebuildLayouts(generation: generation)
    }

    /// Loads again after a guide refresh that this screen did not start. The
    /// channel keys depend on the store's alias map, which the store rebuilds
    /// only after it has announced the refresh; rebuilding it here first keeps
    /// the rows from being resolved against the old one.
    func reloadAfterGuideRefresh() async {
        await EPGStore.shared.rebuildResolution(playlist: playlist)
        await load()
    }

    func selectDay(_ day: Date) async {
        selectedDay = calendar.startOfDay(for: day)
        followsToday = selectedDay == calendar.startOfDay(for: now())
        if rowBuildPending {
            await load()
            return
        }
        // Without channels there is nothing to lay out, and no grid to show it in.
        guard !sections.isEmpty else { return }
        loadGeneration += 1
        isWorking = true
        await rebuildLayouts(generation: loadGeneration)
    }

    /// Follows the calendar into a new day when the user was looking at today: a
    /// guide left open over midnight would otherwise keep yesterday's grid under a
    /// chip that now reads "Yesterday".
    func rollToTodayIfNeeded() async {
        let today = calendar.startOfDay(for: now())
        guard today != self.today else { return }
        self.today = today
        availableDays = Self.days(around: today, calendar: calendar)
        if followsToday {
            await selectDay(today)
        } else if selectedDay == today {
            // The day the user had picked has become the current one.
            followsToday = true
        }
    }

    func cancelLoading() {
        loadGeneration += 1
        rowTask?.cancel()
        programmeTask?.cancel()
        layoutTask?.cancel()
        rowTask = nil
        programmeTask = nil
        layoutTask = nil
        if isWorking {
            isWorking = false
            needsReload = true
        }
    }

    /// The catalog the rows come from has not finished loading (and has not failed).
    private var catalogIsLoading: Bool {
        switch source {
        case .xtream(let playlist):
            let store = PlaylistContentStore.shared
            return store.activePlaylistId == playlist.id && !store.streamsLoaded && store.loadError == nil
        case .m3u(let playlist):
            let store = M3UContentStore.shared
            return store.activePlaylistId == playlist.id && store.isLoading
        }
    }

    private var catalogFailed: Bool {
        switch source {
        case .xtream(let playlist):
            let store = PlaylistContentStore.shared
            return store.activePlaylistId == playlist.id && store.loadError != nil
        case .m3u(let playlist):
            let store = M3UContentStore.shared
            return store.activePlaylistId == playlist.id && store.loadError != nil
        }
    }

    var catalogError: String? {
        switch source {
        case .xtream: return PlaylistContentStore.shared.loadError
        case .m3u: return M3UContentStore.shared.loadError
        }
    }

    func retryCatalog() async {
        switch source {
        case .xtream(let playlist): await PlaylistContentStore.shared.loadPlaylist(playlist)
        case .m3u(let playlist): await M3UContentStore.shared.loadPlaylist(playlist)
        }
        await load()
    }

    /// Reads the selected day's programmes again after a failure.
    func retryProgrammes() async {
        await selectDay(selectedDay)
    }

    /// The guide can be opened while the channel list is still being read from the
    /// database. Its arrival (or its failure) loads the guide again, so the screen
    /// does not stay on a spinner or on "no guide data".
    private func observeCatalog() {
        let changes: AnyPublisher<Void, Never>
        switch source {
        case .xtream:
            let store = PlaylistContentStore.shared
            changes = store.$liveRevision.dropFirst().map { _ in () }
                .merge(with: store.$loadError.dropFirst().filter { $0 != nil }.map { _ in () })
                .eraseToAnyPublisher()
        case .m3u:
            let store = M3UContentStore.shared
            changes = store.$revision.dropFirst().map { _ in () }
                .merge(with: store.$loadError.dropFirst().filter { $0 != nil }.map { _ in () })
                .eraseToAnyPublisher()
        }
        changes
            .sink { [weak self] _ in
                // `@Published` emits before the value is stored, and the stores bump
                // their revision last: one hop later the whole change is readable.
                Task { await self?.catalogChanged() }
            }
            .store(in: &observers)
    }

    private func catalogChanged() async {
        // Nothing to bring up to date before the first load, which reads the
        // catalog as it is when it runs.
        guard loadGeneration > 0 else { return }
        await load()
    }

    private func observeDayChange() {
        // The notification is posted on an arbitrary thread.
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.rollToTodayIfNeeded() }
            }
            .store(in: &observers)
    }

    /// Copies everything the row builders read in one main-actor step, the alias
    /// map together with the channel list it belongs to, and builds off the main
    /// actor.
    private func buildRows() async -> EPGGuideRowSet {
        let interval = BrowsePerformance.begin("GuideBuildRows")
        defer { BrowsePerformance.end("GuideBuildRows", interval) }
        rowTask?.cancel()
        let aliases = EPGStore.shared.resolutionSnapshot
        let hiddenStore = HiddenCategoryStore.shared
        let task: Task<EPGGuideRowSet, Never>
        switch source {
        case .xtream(let playlist):
            let store = PlaylistContentStore.shared
            let entries = store.liveStreams
            let byCategory = store.liveStreamsByCategoryId
            let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: "live")
            task = Task.detached(priority: .userInitiated) {
                Self.makeRows(xtream: entries, aliases: aliases,
                              hiddenCategoryIds: hidden, streamsByCategory: byCategory)
            }
        case .m3u(let playlist):
            let channels = M3UContentStore.shared.channels
            let hidden = hiddenStore.hiddenIds(playlistId: playlist.id, type: M3UChannelsView.hiddenCategoryType)
            task = Task.detached(priority: .userInitiated) {
                Self.makeRows(m3u: channels, aliases: aliases, hiddenGroups: hidden)
            }
        }
        rowTask = task
        return await task.value
    }

    /// Guide rows of an Xtream playlist, grouped by category.
    ///
    /// Channels of hidden categories are left out. "Hidden" goes by the bucket the
    /// catalog files a channel under, not by the channel's own category id: orphans
    /// sit in the synthetic "uncategorized" bucket, which can be hidden like any
    /// other. `streamsByCategory` is only read for the hidden ids.
    nonisolated static func makeRows(
        xtream entries: [LiveStreamWithCategory],
        aliases: [String: String],
        hiddenCategoryIds: Set<String>,
        streamsByCategory: [String: [LiveStreamWithCategory]]
    ) -> EPGGuideRowSet {
        var hiddenStreamIds = Set<Int>()
        for id in hiddenCategoryIds {
            for entry in streamsByCategory[id] ?? [] {
                hiddenStreamIds.insert(entry.stream.streamId)
            }
        }

        var result = EPGGuideRowSet()
        for (offset, entry) in entries.enumerated() {
            if offset % cancellationStride == 0, Task.isCancelled { return EPGGuideRowSet() }
            let stream = entry.stream
            if hiddenStreamIds.contains(stream.streamId) {
                result.hasHiddenChannels = true
                continue
            }
            let idKey = EPGConstants.normalizeChannelKey(stream.epgChannelId)
            let nameKey = EPGConstants.normalizeChannelKey(stream.name)
            let key = EPGStore.storedKey(idKey: idKey, nameKey: nameKey, in: aliases)
                ?? idKey ?? nameKey ?? "#stream:\(stream.streamId)"
            let category = category(id: stream.categoryId, name: entry.categoryName)
            result.append(EPGGuideRow(
                id: stream.id, channelKey: key, displayName: stream.name,
                iconURL: stream.streamIcon.flatMap { URL(string: $0) }, liveStream: stream,
                categoryId: category.id, categoryTitle: category.title))
        }
        return result
    }

    /// Guide rows of an M3U playlist: its live channels, grouped by `group-title`.
    /// Channels of hidden groups are left out; the hidden ids are the keys the
    /// content store groups by.
    nonisolated static func makeRows(
        m3u channels: [DBM3UChannel],
        aliases: [String: String],
        hiddenGroups: Set<String>
    ) -> EPGGuideRowSet {
        var result = EPGGuideRowSet()
        for (offset, channel) in channels.enumerated() {
            if offset % cancellationStride == 0, Task.isCancelled { return EPGGuideRowSet() }
            if !hiddenGroups.isEmpty, hiddenGroups.contains(M3UContentStore.groupKey(for: channel)) {
                // Only a hidden live channel counts: the guide lists nothing else.
                if !result.hasHiddenChannels, M3UContentStore.isLive(channel) { result.hasHiddenChannels = true }
                continue
            }
            // The costly check (it parses the URL) comes after the cheap one.
            guard M3UContentStore.isLive(channel) else { continue }
            let idKey = EPGConstants.normalizeChannelKey(channel.tvgId)
            let nameKey = EPGConstants.normalizeChannelKey(channel.tvgName ?? channel.name)
            let key = EPGStore.storedKey(idKey: idKey, nameKey: nameKey, in: aliases)
                ?? idKey ?? nameKey ?? channel.id
            let category = category(id: channel.groupTitle, name: channel.groupTitle)
            result.append(EPGGuideRow(
                id: channel.id, channelKey: key, displayName: channel.name,
                iconURL: channel.tvgLogo.flatMap { URL(string: $0) }, liveStream: nil,
                categoryId: category.id, categoryTitle: category.title))
        }
        return result
    }

    private func rebuildLayouts(generation: Int) async {
        let start = dayStart
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let wantedKeys = channelKeys
        let byKey: [String: [EPGProgramme]]
        do {
            // Fetch the whole playlist's day window and group locally — cheaper than a
            // multi-thousand-placeholder IN clause for large playlists.
            programmeTask?.cancel()
            let query = Task {
                try await EPGStore.shared.programmes(playlistId: playlist.id, from: start, to: end)
            }
            programmeTask = query
            byKey = try await query.value
        } catch {
            guard generation == loadGeneration, !Task.isCancelled, !(error is CancellationError) else { return }
            isWorking = false
            programmeError = NetworkErrorText.describe(error)
            // Empty rows rather than the previous day's programmes under this day's
            // chip. A new version, so the rows draw again.
            layoutVersion += 1
            let dayWidth = EPGGuideMetrics.guide(regularWidth: false).dayWidth
            emptyLayout = EPGRowLayout(
                cells: [EPGCellLayout(id: "empty", programme: nil, x: 0, width: dayWidth)],
                version: layoutVersion
            )
            layouts = [:]
            state = sections.isEmpty ? .empty : .ready
            return
        }

        guard generation == loadGeneration, !Task.isCancelled else { return }

        layoutVersion += 1
        let version = layoutVersion
        // Only the hour width matters here, and it does not follow the width class.
        let metrics = EPGGuideMetrics.guide(regularWidth: false)
        let hourWidth = metrics.hourWidth
        emptyLayout = EPGRowLayout(
            cells: [EPGCellLayout(id: "empty", programme: nil, x: 0, width: metrics.dayWidth)],
            version: version
        )
        // Precompute frames off the main actor — for large playlists this is
        // thousands of channels × dozens of cells.
        layoutTask?.cancel()
        let task = Task.detached(priority: .userInitiated) { () -> [String: EPGRowLayout] in
            EPGGuideViewModel.makeLayouts(
                byKey: byKey,
                wantedKeys: wantedKeys,
                dayStart: start,
                dayEnd: end,
                hourWidth: hourWidth,
                version: version
            )
        }
        layoutTask = task
        let newLayouts = await task.value
        guard generation == loadGeneration, !Task.isCancelled, !task.isCancelled else { return }
        layouts = newLayouts
        programmeError = nil
        isWorking = false
        state = .ready
    }

    func layout(for channelKey: String) -> EPGRowLayout {
        layouts[channelKey] ?? emptyLayout
    }

    nonisolated static func makeLayouts(
        byKey: [String: [EPGProgramme]],
        wantedKeys: Set<String>,
        dayStart: Date,
        dayEnd: Date,
        hourWidth: CGFloat,
        version: Int
    ) -> [String: EPGRowLayout] {
        var result: [String: EPGRowLayout] = [:]
        result.reserveCapacity(min(byKey.count, wantedKeys.count))
        for (key, unsortedProgrammes) in byKey where wantedKeys.contains(key) {
            guard !Task.isCancelled else { return [:] }
            let programmes = unsortedProgrammes.sorted { $0.start < $1.start }
            result[key] = EPGRowLayout(
                cells: cells(
                    for: programmes,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    hourWidth: hourWidth
                ),
                version: version
            )
        }
        return result
    }

    /// Builds positioned cells for a row, clamped to the day bounds. A leading
    /// filler is added when the first programme starts after the day start.
    /// `nonisolated static` so layout precompute can run off the main actor.
    nonisolated static func cells(for programmes: [EPGProgramme], dayStart: Date, dayEnd: Date, hourWidth: CGFloat) -> [EPGCellLayout] {
        // Use the real elapsed hours between dayStart/dayEnd rather than a fixed 24
        // so DST transition days (23h/25h) don't misplace the trailing filler cell.
        let dayWidth = CGFloat(dayEnd.timeIntervalSince(dayStart) / 3600) * hourWidth
        func x(_ date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourWidth
        }
        var result: [EPGCellLayout] = []
        var cursor = dayStart
        for programme in programmes {
            let cellStart = max(programme.start, dayStart)
            let cellEnd = min(programme.stop, dayEnd)
            guard cellEnd > cellStart else { continue }
            // Gap filler.
            if cellStart > cursor {
                let gx = x(cursor)
                result.append(EPGCellLayout(id: "gap-\(gx)", programme: nil, x: gx, width: x(cellStart) - gx))
            }
            let sx = x(cellStart)
            result.append(EPGCellLayout(id: programme.id, programme: programme, x: sx, width: max(2, x(cellEnd) - sx)))
            cursor = cellEnd
        }
        // Trailing filler to the end of the day.
        if cursor < dayEnd {
            let gx = x(cursor)
            result.append(EPGCellLayout(id: "gap-tail", programme: nil, x: gx, width: dayWidth - gx))
        }
        if result.isEmpty {
            result.append(EPGCellLayout(id: "empty", programme: nil, x: 0, width: dayWidth))
        }
        return result
    }
}
