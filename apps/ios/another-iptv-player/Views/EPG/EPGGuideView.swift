import SwiftUI

/// Full-page timeline TV guide: channels × time. All programme rows live inside
/// one horizontal ScrollView, so they can never drift to different time offsets.
/// The channel column is drawn above that scroller and remains pinned.
struct EPGGuideView: View {
    @ScaledMetric(relativeTo: .caption) private var gridTextScale: CGFloat = 1
    @StateObject private var model: EPGGuideViewModel
    @Environment(\.playerOverlayController) private var playerOverlay
    @ObservedObject private var epgStore = EPGStore.shared
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Also read so the body runs again when the app comes back: the now-line is
    /// derived from the clock.
    @Environment(\.scenePhase) private var scenePhase

    /// The only horizontal scrollers are the time axis and the complete programme
    /// body. The active one drives the other while preserving native momentum.
    @State private var positions: [String: ScrollPosition] = [:]
    @State private var reportedOffsets: [String: CGFloat] = [:]
    @State private var bodyOffsetX: CGFloat = 0
    /// Visible width of the scrolling body, used to size pinned category headers so
    /// they span the viewport rather than the full 24-hour content width.
    @State private var viewportWidth: CGFloat = 0
    @State private var lastSyncX: CGFloat = -1
    /// Which scroller the user is actively driving. Only that one may push the other,
    /// so a follower's geometry updates can never feed back and start a ping-pong loop
    /// that pins the main thread (the guide's hang).
    @State private var activeScroller: String?
    /// Initial/programmatic positioning causes stale zero-offset geometry events.
    /// Ignore those briefly so they cannot undo the jump to the selected time.
    @State private var programmaticTargetX: CGFloat?
    @State private var targetReleaseTask: Task<Void, Never>?
    @State private var selected: SelectedProgramme?
    @State private var selectionTask: Task<Void, Never>?
    @State private var detailChannel: EPGGuideRow?
    @State private var searchPresented = false
    /// The day the grid was last moved to its default time for. Coming back from a
    /// pushed channel schedule starts the grid's task again; the time the user had
    /// scrolled to must survive that.
    @State private var focusedDay: Date?
    /// A refresh started from this screen loads the guide itself when it is done.
    @State private var isRefreshingHere = false

    private static let axisID = "axis"
    private static let bodyID = "body"

    private var metrics: EPGGuideMetrics {
        EPGGuideMetrics.guide(regularWidth: horizontalSizeClass == .regular, textScale: gridTextScale)
    }

    init(source: EPGGuideViewModel.Source) {
        _model = StateObject(wrappedValue: EPGGuideViewModel(source: source))
    }

    struct SelectedProgramme: Identifiable {
        let id: String
        let programme: EPGProgramme
        let row: EPGGuideRow
    }

    var body: some View {
        content
            .navigationTitle(L("epg.guide.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar { toolbarContent }
            .searchable(text: $model.searchQuery, isPresented: $searchPresented, prompt: L("live.search_placeholder"))
            .onChange(of: searchPresented) { _, presented in
                // Leaving search brings back the full list and its collapsed categories.
                if !presented, !model.searchQuery.isEmpty { model.searchQuery = "" }
            }
            .task {
                guard model.needsLoad else { return }
                await model.load()
            }
            .onDisappear {
                selectionTask?.cancel()
                targetReleaseTask?.cancel()
                // The release task is what clears the target. With it cancelled the
                // target would stay set, and the axis and the body would no longer
                // follow each other when the screen comes back.
                programmaticTargetX = nil
                model.cancelLoading()
            }
            .onChange(of: model.state) { _, state in
                // The grid is rebuilt with fresh scrollers when it comes back.
                if state != .ready { focusedDay = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.rollToTodayIfNeeded() } }
            }
            .onChange(of: epgStore.lastSuccess[model.playlist.id]) { _, _ in
                guard !isRefreshingHere else { return }
                Task { await model.reloadAfterGuideRefresh() }
            }
            .navigationDestination(item: $detailChannel) { row in
                ChannelEPGDetailView(playlist: model.playlist, channelKey: row.channelKey,
                                     displayName: row.displayName, iconURL: row.iconURL, liveStream: row.liveStream,
                                     onPlayChannel: m3uPlayAction(for: row))
            }
            .sheet(item: $selected) { sel in
                EPGProgrammeDetailSheet(playlist: model.playlist, programme: sel.programme,
                                        channelName: sel.row.displayName, channelIcon: sel.row.iconURL,
                                        liveStream: sel.row.liveStream,
                                        onPlayChannel: m3uPlayAction(for: sel.row))
                    .presentationDetents([.medium, .large])
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notConfigured:
            CatalogEmptyView(.message(
                title: L("epg.not_configured.title"),
                systemImage: "calendar.badge.exclamationmark",
                description: model.playlist.kind == .m3u
                    ? L("epg.not_configured.m3u_message") : L("epg.not_configured.xtream_message")
            ))
        case .empty:
            VStack(spacing: 0) {
                CatalogEmptyView(.message(title: L("epg.empty.title"), systemImage: "calendar",
                                          description: L("epg.empty.message")))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("epg.refresh")) { Task { await refreshGuide() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .allHidden:
            CatalogEmptyView(.message(title: L("guide.all_hidden.title"), systemImage: "eye.slash",
                                      description: L("guide.all_hidden.message")))
        case .catalogFailed:
            CatalogLoadErrorView(message: model.catalogError ?? L("kit.error.generic")) {
                Task { await model.retryCatalog() }
            }
        case .ready:
            VStack(spacing: 0) {
                EPGDayPicker(days: model.availableDays, selectedDay: model.selectedDay) { day in
                    Task { await model.selectDay(day) }
                }
                .equatable()
                if let message = model.programmeError {
                    InlineErrorRow(message: message) {
                        Task { await model.retryProgrammes() }
                    }
                    .padding(.horizontal, BrowseMetrics.pageMargin)
                    .padding(.bottom, 8)
                }
                grid
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .overlay {
                        if model.hasNoSearchResults {
                            CatalogEmptyView(.noSearchResults)
                                .background(Color(.systemBackground))
                        }
                    }
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        let metrics = self.metrics
        // One reading of the clock per pass, so every row draws the line at the
        // same x as the axis.
        let nowX = nowLineX
        return VStack(spacing: 0) {
            // Header: fixed corner + time axis. The axis shares `timePosition`, so it
            // tracks the rows' horizontal scroll.
            HStack(spacing: 0) {
                Color(.secondarySystemBackground)
                    .frame(width: metrics.channelColumnWidth, height: metrics.axisHeight)
                ScrollView(.horizontal) {
                    EPGTimeAxisView(dayStart: model.dayStart, metrics: metrics)
                        .frame(width: metrics.dayWidth, height: metrics.axisHeight)
                }
                .scrollPosition(hBinding(Self.axisID))
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, phase in
                    updateActiveScroller(Self.axisID, phase: phase)
                }
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
                    propagate(from: Self.axisID, x: x)
                }
                // Draw the axis now-line off the shared `bodyOffsetX` (the same value
                // that pins the channel column and positions the row now-lines) rather
                // than inside the axis scroller. The axis and body are two separate
                // scrollers that can transiently drift while syncing; anchoring both
                // now-lines to one offset keeps them on the exact same screen column.
                .overlay(alignment: .leading) {
                    if let nowX {
                        Rectangle().fill(Color.red)
                            .frame(width: 1.5, height: metrics.axisHeight)
                            .offset(x: nowX - bodyOffsetX)
                            .allowsHitTesting(false)
                    }
                }
                .clipped()
            }
            .frame(height: metrics.axisHeight)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Divider() }

            // A single two-axis ScrollView keeps every row on the same time offset.
            // LazyVStack is now a direct child of the vertical scroller, preserving
            // virtualization for playlists with thousands of channels.
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 1) {
                    ForEach(model.items) { item in
                        switch item {
                        case .header(let header):
                            headerRow(header)
                        case .channel(let row):
                            channelRow(row, metrics: metrics, nowX: nowX)
                        }
                    }
                }
            }
            .accessibilityIdentifier("epg.guide.grid")
            .scrollPosition(hBinding(Self.bodyID))
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                updateActiveScroller(Self.bodyID, phase: phase)
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { max(0, $0.contentOffset.x) }) { _, x in
                if bodyOffsetX != x { bodyOffsetX = x }
                propagate(from: Self.bodyID, x: x)
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.width }) { _, w in
                if viewportWidth != w { viewportWidth = w }
            }
        }
        // `grid` only exists after the async model load reaches `.ready`. Position
        // after its first layout pass, then verify once and retry if either binding
        // was not ready when the first command arrived.
        // The task also starts again each time the screen re-appears; the jump runs
        // once per selected day.
        .task(id: model.selectedDay) {
            let day = model.selectedDay
            guard focusedDay != day else { return }
            await focusSelectedTimeAfterLayout()
            if !Task.isCancelled { focusedDay = day }
        }
    }

    @ViewBuilder
    private func channelRow(_ row: EPGGuideRow, metrics: EPGGuideMetrics, nowX: CGFloat?) -> some View {
        HStack(spacing: 0) {
            EPGChannelColumnCell(row: row, metrics: metrics,
                                 onPlay: { playChannel(row) },
                                 onSchedule: { detailChannel = row })
                .equatable()
                .frame(width: metrics.channelColumnWidth, height: metrics.rowHeight)
                .offset(x: bodyOffsetX)
                .zIndex(1)

            ZStack(alignment: .topLeading) {
                EPGChannelRowView(channelKey: row.channelKey,
                                  layout: model.layout(for: row.channelKey),
                                  metrics: metrics) { programme in
                    showProgramme(programme, in: row)
                }
                .equatable()

                if let nowX {
                    Rectangle().fill(Color.red.opacity(0.85))
                        .frame(width: 1.5, height: metrics.rowHeight)
                        .offset(x: nowX)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: metrics.dayWidth, height: metrics.rowHeight, alignment: .topLeading)
        }
        .frame(
            width: metrics.channelColumnWidth + metrics.dayWidth,
            height: metrics.rowHeight,
            alignment: .leading
        )
    }

    /// A category header pinned to the left edge: it rides `bodyOffsetX` so it stays
    /// in view while the programme body scrolls horizontally.
    @ViewBuilder
    private func headerRow(_ header: EPGGuideSectionHeader) -> some View {
        EPGCategoryHeader(
            title: header.title,
            channelCount: header.channelCount,
            collapsed: header.collapsed,
            width: max(viewportWidth, metrics.channelColumnWidth),
            height: metrics.headerHeight,
            onToggle: { model.toggleCategory(header.id) }
        )
        .offset(x: bodyOffsetX)
        .zIndex(2)
        .frame(
            width: metrics.channelColumnWidth + metrics.dayWidth,
            height: metrics.headerHeight,
            alignment: .leading
        )
    }

    // MARK: - Toolbar

    // Keep the inline title readable when accessibility text enlarges controls.
    // The guide hides the tab bar, leaving room for these same actions below.
    private var actionPlacement: ToolbarItemPlacement {
        (dynamicTypeSize.isAccessibilitySize || (horizontalSizeClass != .regular && layoutDirection == .rightToLeft))
            ? .bottomBar : .topBarTrailing
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.hasCategories {
            ToolbarItem(placement: actionPlacement) {
                Menu {
                    Button(L("epg.categories.expand_all")) { model.setAllCollapsed(false) }
                    Button(L("epg.categories.collapse_all")) { model.setAllCollapsed(true) }
                } label: {
                    Label(L("epg.categories.menu_a11y"), systemImage: "rectangle.expand.vertical")
                }
            }
        }
        ToolbarItem(placement: actionPlacement) {
            // The drawer of an inline-title screen is collapsed on open and this
            // grid has no vertical scroller at its top to pull it out with.
            Button {
                searchPresented = true
            } label: { Label(L("common.search"), systemImage: "magnifyingglass") }
            .disabled(model.state != .ready)
        }
        ToolbarItem(placement: actionPlacement) {
            // A plain clock: the arrowed one marks catch-up in the schedule rows
            // and in the programme sheet.
            Button {
                scrollToNow(forceToday: true)
            } label: { Label(L("epg.jump_to_now"), systemImage: "clock") }
            .disabled(model.state != .ready)
        }
        ToolbarItem(placement: actionPlacement) {
            let refreshing = epgStore.refreshState[model.playlist.id]?.isRefreshing ?? false
            Button {
                Task { await refreshGuide() }
            } label: {
                if refreshing { ProgressView() } else { Label(L("epg.refresh"), systemImage: "arrow.clockwise") }
            }
            .accessibilityLabel(L("epg.refresh"))
            .disabled(refreshing)
        }
    }

    // MARK: - Helpers

    private var isToday: Bool { Calendar.current.isDateInToday(model.selectedDay) }

    private var nowLineX: CGFloat? {
        guard isToday else { return nil }
        return metrics.x(for: Date(), dayStart: model.dayStart)
    }

    private func hBinding(_ id: String) -> Binding<ScrollPosition> {
        Binding(
            get: { positions[id] ?? ScrollPosition(edge: .leading) },
            set: { positions[id] = $0 }
        )
    }

    /// Latches which scroller the user is physically driving. Only user-initiated
    /// phases claim the latch — the `.animating` phase emitted when we sync the
    /// follower programmatically must be ignored, otherwise the follower would seize
    /// the latch and block the real driver, leaving it behind (the now-line drift).
    private func updateActiveScroller(_ id: String, phase: ScrollPhase) {
        switch phase {
        case .tracking, .interacting, .decelerating:
            activeScroller = id
        case .idle:
            if activeScroller == id { activeScroller = nil }
        case .animating:
            break   // programmatic follower sync — never claims the latch
        @unknown default:
            break
        }
    }

    /// Pushes the active scroller's offset to the one follower. Programme rows are
    /// part of a single body scroller, so row-specific horizontal state is impossible.
    private func propagate(from sourceID: String, x: CGFloat) {
        reportedOffsets[sourceID] = x
        guard programmaticTargetX == nil else { return }
        // Only the scroller the user is actively driving may move the other. This
        // makes the sync one-directional at any instant, so the follower's resulting
        // geometry events can never bounce back and spin the main thread.
        guard activeScroller == nil || activeScroller == sourceID else { return }
        guard abs(x - lastSyncX) > 0.5 else { return }
        lastSyncX = x
        let followerID = sourceID == Self.axisID ? Self.bodyID : Self.axisID
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            var position = positions[followerID] ?? ScrollPosition(edge: .leading)
            position.scrollTo(x: x)
            positions[followerID] = position
        }
    }

    private func scrollToNow(forceToday: Bool = false) {
        if forceToday, !isToday {
            // Switching the day re-runs the grid task keyed by selectedDay.
            Task { await model.selectDay(Date()) }
            return
        }
        applyProgrammaticOffset(defaultTimeOffset)
    }

    private var defaultTimeOffset: CGFloat {
        if isToday {
            return max(0, metrics.x(for: Date(), dayStart: model.dayStart) - metrics.hourWidth / 2)
        }
        return 8 * metrics.hourWidth // 08:00
    }

    private func focusSelectedTimeAfterLayout() async {
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        let targetX = defaultTimeOffset
        applyProgrammaticOffset(targetX)

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let axisReachedTarget = abs((reportedOffsets[Self.axisID] ?? -1) - targetX) < 1
        let bodyReachedTarget = abs((reportedOffsets[Self.bodyID] ?? -1) - targetX) < 1
        if !axisReachedTarget || !bodyReachedTarget {
            applyProgrammaticOffset(targetX)
        }
    }

    private func applyProgrammaticOffset(_ targetX: CGFloat) {
        targetReleaseTask?.cancel()
        programmaticTargetX = targetX
        lastSyncX = targetX
        bodyOffsetX = targetX

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for id in [Self.axisID, Self.bodyID] {
                var position = positions[id] ?? ScrollPosition(edge: .leading)
                position.scrollTo(x: targetX)
                positions[id] = position
            }
        }

        // Scroll geometry may report the pre-jump zero offset for a few frames.
        // Release normal user-driven synchronization after both views have settled.
        targetReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            programmaticTargetX = nil
        }
    }

    /// Downloads the guide again and loads the result. The store announces a
    /// finished refresh to every open guide; this one loads on its own once the
    /// whole refresh is through, so the announcement is not acted on a second time.
    private func refreshGuide() async {
        isRefreshingHere = true
        await epgStore.forceRefresh(playlist: model.playlist)
        isRefreshingHere = false
        await model.load()
    }

    private func playChannel(_ row: EPGGuideRow) {
        if let stream = row.liveStream {
            // Hand the player the live catalog as the Live tab lists it, so prev/next
            // channel and the channel side panel work, not just the tapped channel.
            let live = EPGGuidePlayback.xtreamLiveQueue(playlistId: model.playlist.id, including: stream)
            playerOverlay.injected?.present(playlistId: model.playlist.id) {
                LivePlayerShell(playlist: model.playlist, queue: live.queue, sections: live.sections,
                                initialStream: stream, initialHistory: nil, subtitle: row.displayName)
            }
        } else if let play = m3uPlayAction(for: row) {
            play()
        } else {
            // No playable channel behind the row; its schedule is still worth showing.
            detailChannel = row
        }
    }

    /// Starts an M3U row's channel with its group as the queue, the way the
    /// channel shelves do. Nil when the row does not resolve to a channel of the
    /// loaded playlist (an Xtream row, a channel the adult filter has taken out
    /// since the rows were built) or the channel has no usable URL.
    private func m3uPlayAction(for row: EPGGuideRow) -> (() -> Void)? {
        guard case .m3u(let playlist) = model.source,
              let channel = M3UContentStore.shared.channel(id: row.id),
              M3UParser.sanitizedURL(from: channel.url) != nil else { return nil }
        return {
            let queue = M3UContentStore.shared.queue(for: channel)
            playerOverlay.injected?.present {
                M3UPlayerShell(playlist: playlist, channel: channel, queue: queue)
            }
        }
    }

    private func showProgramme(_ programme: EPGProgramme, in row: EPGGuideRow) {
        selectionTask?.cancel()
        selectionTask = Task {
            let detailed = try? await epgStore.programmeDetails(
                playlistId: model.playlist.id,
                channelKey: programme.channelKey,
                start: programme.start
            )
            guard !Task.isCancelled else { return }
            let value = detailed ?? programme
            selected = SelectedProgramme(id: value.id, programme: value, row: row)
        }
    }
}
