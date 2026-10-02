import SwiftUI

struct DashboardView: View {
    let playlist: Playlist
    let onDismiss: () -> Void
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var epgStore = EPGStore.shared
    @StateObject private var playerOverlay = PlayerOverlayController()

    /// Last content tab is restored on launch; Settings/Search stay ephemeral.
    @AppStorage(DashboardTab.storageKey) private var savedTab: Int = DashboardTab.live.rawValue
    @State private var selectedTab: DashboardTab

    @State private var globalSearchText: String = ""

    init(playlist: Playlist, onDismiss: @escaping () -> Void) {
        self.playlist = playlist
        self.onDismiss = onDismiss
        // Restore synchronously so the first frame already renders the correct tab.
        // An async restore in .task set selectedTab after the first render, causing a
        // Live→saved-tab flash and a title/tab desync ("title tam oturmuyor").
        // A language change rebuilds the whole tree from Settings, and that is where the
        // user comes back to. Only read here: this initialiser runs on every parent update,
        // and the saved tab is left alone so the next launch opens a content tab as usual.
        _selectedTab = State(initialValue: LocalizationManager.shared.isRebuildingAfterLanguageChange
            ? .settings
            : DashboardTab.restoreInitialTab())
    }

    /// Settings/Search selections are not persisted, so we never restore into them.
    private var tabBinding: Binding<DashboardTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                selectedTab = newTab
                if newTab.isPersisted { savedTab = newTab.rawValue }
            }
        )
    }

    @State private var showDownloadsSheet = false
    /// A load failure that nothing on screen reports. Decided when the failure happens,
    /// so moving to another tab later does not raise an alert for an error the user has
    /// already seen in place.
    @State private var loadErrorAlert: String?

    /// True while a fullscreen (not mini) player covers the dashboard.
    private var isPlayerCoveringContent: Bool {
        playerOverlay.presentation != nil && playerOverlay.mode == .fullscreen
    }

    /// A content tab with nothing to show reports a load failure in place, with its own
    /// retry. Settings and Search have no such state, and neither has a tab whose shelves
    /// are on screen.
    private var selectedTabShowsLoadErrorInline: Bool {
        switch selectedTab {
        case .live: return contentStore.liveCategories.isEmpty
        case .movies: return contentStore.vodCategories.isEmpty
        case .series: return contentStore.seriesCategories.isEmpty
        case .settings, .search: return false
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: tabBinding) {
                Tab(L("dashboard.live"), systemImage: "tv", value: DashboardTab.live) {
                    NavigationStack {
                        LiveStreamsView(playlist: playlist)
                            .dashboardNavigation(playlist: playlist, tabTitle: L("dashboard.live"), type: "live", onDismiss: onDismiss)
                    }
                }

                Tab(L("dashboard.movies"), systemImage: "film", value: DashboardTab.movies) {
                    NavigationStack {
                        VODView(playlist: playlist)
                            .dashboardNavigation(playlist: playlist, tabTitle: L("dashboard.movies"), type: "vod", onDismiss: onDismiss)
                    }
                }

                Tab(L("dashboard.series"), systemImage: "play.tv", value: DashboardTab.series) {
                    NavigationStack {
                        SeriesView(playlist: playlist)
                            .dashboardNavigation(playlist: playlist, tabTitle: L("dashboard.series"), type: "series", onDismiss: onDismiss)
                    }
                }

                Tab(L("dashboard.settings"), systemImage: "gear", value: DashboardTab.settings) {
                    NavigationStack {
                        PlaylistSettingsView(playlist: playlist, onDismiss: onDismiss)
                            .dashboardNavigation(playlist: playlist, tabTitle: L("dashboard.settings"), onDismiss: onDismiss)
                    }
                }

                // Same key as the screen's own title, so the tab and the page it opens
                // cannot be worded differently.
                Tab(L("search.title"), systemImage: "magnifyingglass", value: DashboardTab.search, role: .search) {
                    NavigationStack {
                        SearchView(playlist: playlist, searchText: $globalSearchText)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .posterMetricsFollowingWindow()
            // The fullscreen player is an in-window overlay, not a system presentation, so
            // VoiceOver would otherwise still reach (and activate) the catalog and tab bar
            // behind it. The mini card leaves the catalog reachable.
            .accessibilityHidden(isPlayerCoveringContent)

            PlayerOverlayHost(controller: playerOverlay)
                .zIndex(10_000)
        }
        .environmentObject(playerOverlay)
        .environment(\.playerOverlayController, playerOverlay)
        .onChange(of: playerOverlay.presentation?.id) { _, id in
            // The overlay sits below UIKit-presented sheets; playback started from the
            // Downloads sheet would otherwise run, audibly, behind it.
            if id != nil, showDownloadsSheet { showDownloadsSheet = false }
        }
        .onChange(of: playerOverlay.detailRequest) { _, request in
            // The page is pushed by the root of the tab that owns its type, so that tab
            // has to be the visible one. Through the binding, so the saved tab follows.
            switch request {
            case .movie: if selectedTab != .movies { tabBinding.wrappedValue = .movies }
            case .series: if selectedTab != .series { tabBinding.wrappedValue = .series }
            case nil: break
            }
        }
        .environment(\.epgSnapshot, epgStore.snapshot)
        .environment(\.epgLineReserved, epgStore.isLineReserved(for: playlist))
        .environment(\.epgGuideEnabled, epgStore.isGuideEnabled)
        .onAppear { LocalizationManager.shared.finishLanguageChangeRebuild() }
        .task(id: playlist.id) {
            // Card menus and the detail stars read favourites from this store.
            XtreamFavoriteStore.shared.track(playlistId: playlist.id)
            await contentStore.loadPlaylist(playlist)
            // Bind the EPG store to this playlist and refresh the guide if stale.
            // Runs after the catalog load so the wanted-channel set is populated.
            epgStore.setActivePlaylist(playlist)
            await epgStore.refreshIfStale(playlist: playlist)
        }
        .task(id: playlist.id) {
            guard await DashboardReviewPrompt.waitForDelay() else { return }
            DashboardReviewPrompt.requestIfQuiet(
                playerPresented: playerOverlay.presentation != nil || playerOverlay.pendingPresentation != nil,
                dashboardPresenting: showDownloadsSheet || loadErrorAlert != nil || contentStore.refreshError != nil,
                catalogLoaded: contentStore.activePlaylistId == playlist.id
                    && !contentStore.isLoading && contentStore.loadError == nil
            )
        }
        .onChange(of: contentStore.loadError) { _, error in
            guard let error, contentStore.activePlaylistId == playlist.id,
                  !selectedTabShowsLoadErrorInline else {
                loadErrorAlert = nil
                return
            }
            loadErrorAlert = error
        }
        // Closing this alert leaves the store's error in place: the content tabs show it
        // with their own retry for as long as they have nothing else to show.
        .alert(L("loading.error.title"), isPresented: Binding(
            get: { loadErrorAlert != nil },
            set: { if !$0 { loadErrorAlert = nil } }
        ), presenting: loadErrorAlert) { _ in
            Button(L("common.ok")) {}
            Button(L("common.try_again")) {
                Task { await contentStore.loadPlaylist(playlist) }
            }
        } message: { message in
            Text(message)
        }
        // A failed refresh leaves the stored catalog on screen, so it has no inline surface.
        .alert(L("loading.error.title"), isPresented: Binding(
            get: { contentStore.refreshError != nil && contentStore.activePlaylistId == playlist.id },
            set: { if !$0 { contentStore.refreshError = nil } }
        ), presenting: contentStore.refreshError) { _ in
            Button(L("common.ok")) {
                contentStore.refreshError = nil
            }
            Button(L("common.try_again")) {
                // Reloading the stored catalog would change nothing; ask the panel again.
                contentStore.refreshError = nil
                Task { await contentStore.refreshFromNetwork(playlist: playlist) }
            }
        } message: { message in
            Text(message)
        }
        .alert(L("download.player_warning.title"), isPresented: Binding(
            get: { playerOverlay.pendingPresentation != nil },
            set: { if !$0 { playerOverlay.cancelPending() } }
        )) {
            Button(L("common.cancel"), role: .cancel) {
                playerOverlay.cancelPending()
            }
            Button(L("download.player_warning.go_to_downloads")) {
                playerOverlay.cancelPending()
                showDownloadsSheet = true
            }
            Button(L("download.player_warning.continue")) {
                playerOverlay.confirmPending()
            }
        } message: {
            Text(L("download.player_warning.message"))
        }
        .sheet(isPresented: $showDownloadsSheet) {
            NavigationStack {
                DownloadsView(playlist: playlist)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.close")) { showDownloadsSheet = false }
                        }
                    }
            }
            // A sheet is outside the tree the injections above cover.
            .environmentObject(playerOverlay)
            .environment(\.playerOverlayController, playerOverlay)
        }
    }
}

// MARK: - Review prompt

/// Asks for an App Store review a while after a dashboard opens, and only when nothing
/// else has the user's attention. Shared by the Xtream and the M3U dashboard.
enum DashboardReviewPrompt {
    /// Waits long enough not to interrupt the arrival on the dashboard. False when the
    /// dashboard went away in the meantime (SwiftUI cancels its task).
    static func waitForDelay() async -> Bool {
        do {
            try await Task.sleep(for: .seconds(8))
            return true
        } catch {
            return false
        }
    }

    static func requestIfQuiet(playerPresented: Bool, dashboardPresenting: Bool, catalogLoaded: Bool) {
        guard !playerPresented, !dashboardPresenting, catalogLoaded, !isWindowBusy else { return }
        RatingManager.shared.requestReviewIfAppropriate()
    }

    /// A sheet, alert or dialog is up anywhere in the key window, or a text field is
    /// being edited.
    private static var isWindowBusy: Bool {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) else { return true }
        if window.rootViewController?.presentedViewController != nil { return true }
        return containsEditingText(window)
    }

    private static func containsEditingText(_ view: UIView) -> Bool {
        if view.isFirstResponder, view is UITextInput { return true }
        return view.subviews.contains { containsEditingText($0) }
    }
}

// MARK: - Dashboard Tab
private enum DashboardTab: Int, CaseIterable {
    case live = 0
    case movies = 1
    case series = 2
    case settings = 3
    case search = 4

    static let storageKey = "dashboard_selected_tab"
    private static let migrationKey = "dashboard_removed_home_tab_migration_v1"

    /// Only content tabs are persisted; Settings/Search are ephemeral by design.
    var isPersisted: Bool { rawValue <= DashboardTab.series.rawValue }

    /// Reads the persisted tab, applies the one-time "Home tab removed" index shift,
    /// and clamps anything invalid or ephemeral back to a content tab so the restored
    /// selection is always a valid, persistable tab.
    static func restoreInitialTab() -> DashboardTab {
        let defaults = UserDefaults.standard
        var raw = defaults.integer(forKey: storageKey)
        if !defaults.bool(forKey: migrationKey) {
            if raw != 0 { raw -= 1 }
            defaults.set(raw, forKey: storageKey)
            defaults.set(true, forKey: migrationKey)
        }
        let tab = DashboardTab(rawValue: raw) ?? .live
        return tab.isPersisted ? tab : .live
    }
}

// MARK: - Dashboard Navigation Modifier
private struct DashboardNavigationModifier: ViewModifier {
    let playlist: Playlist
    let tabTitle: String
    let type: String?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(tabTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let type = type {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: FavoritesView(playlist: playlist, initialType: type)) {
                            Image(systemName: "star.fill")
                        }
                        // The symbol's built-in description follows the device language,
                        // not the one chosen in the app.
                        .accessibilityLabel(L("favorites.title"))
                        // UI tests address the button by its symbol name, whatever the
                        // language of the label.
                        .accessibilityIdentifier("star.fill")
                    }
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func dashboardNavigation(playlist: Playlist, tabTitle: String, type: String? = nil, onDismiss: @escaping () -> Void) -> some View {
        modifier(DashboardNavigationModifier(playlist: playlist, tabTitle: tabTitle, type: type, onDismiss: onDismiss))
    }
}

// MARK: - Poster metrics

extension PosterMetrics {
    /// Metrics for a window of `size`, with the scale snapped to eighths. Every poster,
    /// tile and image request is keyed on these sizes, so a window that is being dragged
    /// to a new size re-lays the catalog out at four steps at most instead of on every
    /// point. Uses the same reference width as `PosterMetrics.init(windowSize:)`.
    static func snapped(toWindow size: CGSize) -> PosterMetrics {
        let referenceShortSide: CGFloat = 834
        let scale = min(1, max(0.5, min(size.width, size.height) / referenceShortSide))
        let side = (scale * 8).rounded() / 8 * referenceShortSide
        return PosterMetrics(windowSize: CGSize(width: side, height: side))
    }

    /// The app window's size when there is one already, else the screen's: what the first
    /// frame is laid out with before the window has been measured.
    fileprivate static var initialWindowSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let size = (windows.first(where: \.isKeyWindow) ?? windows.first)?.bounds.size ?? .zero
        return size.width > 0 && size.height > 0 ? size : UIScreen.main.bounds.size
    }
}

/// Poster sizing follows the window, so Split View, Slide Over and a resized window get
/// sizes for their own width instead of the full screen's.
/// It is the window that is measured, not the layout of the view this is attached to: the
/// reader ignores every safe area, the keyboard's included. Keyboard, status-bar and player
/// transitions shrink the safe area for a moment, and a size taken from it resized every
/// poster on screen. `PosterMetrics` uses the shorter side, so rotation (the player forcing
/// landscape included) changes nothing either.
private struct WindowPosterMetricsModifier: ViewModifier {
    @State private var metrics = PosterMetrics.snapped(toWindow: PosterMetrics.initialWindowSize)

    func body(content: Content) -> some View {
        content
            .environment(\.posterMetrics, metrics)
            .background {
                Color.clear
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                        guard size.width > 0, size.height > 0 else { return }
                        let next = PosterMetrics.snapped(toWindow: size)
                        if next != metrics { metrics = next }
                    }
                    .ignoresSafeArea()
            }
    }
}

extension View {
    /// Injects `posterMetrics` for the window this view is shown in and keeps it current.
    func posterMetricsFollowingWindow() -> some View {
        modifier(WindowPosterMetricsModifier())
    }
}
