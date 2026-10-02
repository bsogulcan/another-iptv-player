import SwiftUI

/// M3U türündeki playlist için TabView. Canlı/Film/Dizi ayrımı yok — tek "Kanallar" listesi.
struct M3UDashboardView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    @ObservedObject private var store = M3UContentStore.shared
    @ObservedObject private var epgStore = EPGStore.shared
    @StateObject private var playerOverlay = PlayerOverlayController()

    /// Son seçilen tab kaydedilmez — dashboard her açılışta "Kanallar"dan başlar.
    /// The one exception is the rebuild after a language change: that was made in Settings,
    /// so Settings is where the user comes back to. Only read here; the flag is cleared
    /// once the dashboard is on screen.
    @State private var selectedTab: Int = LocalizationManager.shared.isRebuildingAfterLanguageChange ? 1 : 0
    /// The load failure the alert is showing. Closing the alert clears this, not the
    /// store's error, which a screen may be showing in place with its own retry.
    @State private var loadErrorAlert: String?

    /// True while a fullscreen (not mini) player covers the dashboard.
    private var isPlayerCoveringContent: Bool {
        playerOverlay.presentation != nil && playerOverlay.mode == .fullscreen
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab(L("dashboard.channels"), systemImage: "tv", value: 0) {
                    NavigationStack {
                        M3UChannelsView(playlist: playlist)
                            .navigationTitle(L("dashboard.channels"))
                            .navigationBarTitleDisplayMode(.large)
                            .toolbar(.visible, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                }

                Tab(L("dashboard.settings"), systemImage: "gear", value: 1) {
                    NavigationStack {
                        M3UPlaylistSettingsView(playlist: playlist, onDismiss: onDismiss)
                            .navigationTitle(L("dashboard.settings"))
                            .navigationBarTitleDisplayMode(.large)
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
        .environment(\.epgSnapshot, epgStore.snapshot)
        .environment(\.epgLineReserved, epgStore.isLineReserved(for: playlist))
        .environment(\.epgGuideEnabled, epgStore.isGuideEnabled)
        .onAppear { LocalizationManager.shared.finishLanguageChangeRebuild() }
        .task(id: playlist.id) {
            M3UFavoriteStore.shared.track(playlistId: playlist.id)
            await store.loadPlaylist(playlist)
            epgStore.setActivePlaylist(playlist)
            await epgStore.refreshIfStale(playlist: playlist)
        }
        .task(id: playlist.id) {
            guard await DashboardReviewPrompt.waitForDelay() else { return }
            DashboardReviewPrompt.requestIfQuiet(
                playerPresented: playerOverlay.presentation != nil || playerOverlay.pendingPresentation != nil,
                dashboardPresenting: loadErrorAlert != nil,
                catalogLoaded: store.activePlaylistId == playlist.id
                    && !store.isLoading && store.loadError == nil
            )
        }
        .onChange(of: store.loadError) { _, error in
            loadErrorAlert = store.activePlaylistId == playlist.id ? error : nil
        }
        .alert(L("loading.error.title"), isPresented: Binding(
            get: { loadErrorAlert != nil },
            set: { if !$0 { loadErrorAlert = nil } }
        ), presenting: loadErrorAlert) { _ in
            Button(L("common.ok")) {}
            Button(L("common.try_again")) {
                Task { await store.loadPlaylist(playlist) }
            }
        } message: { message in
            Text(message)
        }
        // A failed refresh is reported by the Channels screen, which owns the refresh and
        // its Try Again; a second alert here would compete with it for the same error.
    }
}
