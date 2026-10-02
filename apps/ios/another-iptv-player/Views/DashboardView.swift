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
        _selectedTab = State(initialValue: DashboardTab.restoreInitialTab())
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

    // Keep poster sizing tied to the display, not to this view's transient layout.
    // Keyboard/status-bar/player transitions can temporarily shrink GeometryReader.
    private let posterMetrics = PosterMetrics(windowSize: UIScreen.main.bounds.size)
    @State private var showDownloadsSheet = false

    /// True while a fullscreen (not mini) player covers the dashboard.
    private var isPlayerCoveringContent: Bool {
        playerOverlay.presentation != nil && playerOverlay.mode == .fullscreen
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

                Tab(L("dashboard.search"), systemImage: "magnifyingglass", value: DashboardTab.search, role: .search) {
                    NavigationStack {
                        SearchView(playlist: playlist, searchText: $globalSearchText)
                            .navigationTitle(L("dashboard.search"))
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .environment(\.posterMetrics, posterMetrics)
            // The fullscreen player is an in-window overlay, not a system presentation, so
            // VoiceOver would otherwise still reach (and activate) the catalog and tab bar
            // behind it. The mini card leaves the catalog reachable.
            .accessibilityHidden(isPlayerCoveringContent)

            ZStack {
                if let item = playerOverlay.presentation {
                    item.root
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Bound to this presentation: a dismiss the player issues at the
                        // end of its exit animation cannot close an item presented since.
                        .environment(\.playerOverlayDismiss) {
                            playerOverlay.dismiss(presentationID: item.id)
                        }
                        .environment(\.playerOverlayMode, playerOverlay.mode)
                        .environment(\.playerOverlayPresentationID, item.id)
                        .environment(\.playerOverlayMinimize) { playerOverlay.minimize() }
                        .environment(\.playerOverlayExpand) { playerOverlay.expand() }
                        // VoiceOver's two-finger scrub leaves the player the way a system
                        // presentation would. Kept unconditional: wrapping item.root in an
                        // if/else would remount PlayerView and tear playback down.
                        .accessibilityAction(.escape) { playerOverlay.minimize() }
                        // Keep UIKit-backed video surfaces at a fixed geometry while they attach.
                        // Moving the whole AVPlayer/KSPlayer subtree produced a launch flash.
                        .transition(.opacity)
                }
            }
            // The player must not be laid out in the keyboard-reduced area: a keyboard that is
            // still animating out would otherwise resize it and push the chrome up.
            // Fullscreen only: the docked mini card has to stay above the keyboard. The
            // modifier itself stays unconditional so PlayerView is never remounted.
            .ignoresSafeArea(.keyboard, edges: playerOverlay.mode == .mini ? [] : .all)
            // Animate only insertion/removal. A source switch changes presentation.id while
            // preserving PlayerView identity and must not animate the entire player subtree.
            .animation(.easeOut(duration: 0.14), value: playerOverlay.presentation != nil)
            .zIndex(10_000)
        }
        .environmentObject(playerOverlay)
        .onChange(of: playerOverlay.presentation?.id) { _, id in
            // The overlay sits below UIKit-presented sheets; playback started from the
            // Downloads sheet would otherwise run, audibly, behind it.
            if id != nil, showDownloadsSheet { showDownloadsSheet = false }
        }
        .environment(\.epgSnapshot, epgStore.snapshot)
        .task(id: playlist.id) {
            await contentStore.loadPlaylist(playlist)
            // Bind the EPG store to this playlist and refresh the guide if stale.
            // Runs after the catalog load so the wanted-channel set is populated.
            epgStore.setActivePlaylist(playlist)
            await epgStore.refreshIfStale(playlist: playlist)
        }
        .alert(L("loading.error.title"), isPresented: Binding(
            get: {
                contentStore.loadError != nil
                    && contentStore.activePlaylistId == playlist.id
                    && !contentStore.isLoading
            },
            set: { if !$0 { contentStore.loadError = nil } }
        )) {
            Button(L("common.ok")) {
                contentStore.loadError = nil
            }
            Button(L("common.try_again")) {
                contentStore.loadError = nil
                Task { await contentStore.loadPlaylist(playlist) }
            }
        } message: {
            Text(contentStore.loadError ?? "")
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
            .environmentObject(playerOverlay)
        }
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
    @Environment(\.posterMetrics) private var posterMetrics

    func body(content: Content) -> some View {
        content
            .navigationTitle(tabTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let type = type {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: FavoritesView(playlist: playlist, initialType: type)) {
                            Image(systemName: "star.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
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
