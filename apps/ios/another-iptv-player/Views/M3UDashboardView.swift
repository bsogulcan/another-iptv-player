import SwiftUI

/// M3U türündeki playlist için TabView. Canlı/Film/Dizi ayrımı yok — tek "Kanallar" listesi.
struct M3UDashboardView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    @ObservedObject private var store = M3UContentStore.shared
    @ObservedObject private var favorites = M3UFavoriteStore.shared
    @ObservedObject private var epgStore = EPGStore.shared
    @StateObject private var playerOverlay = PlayerOverlayController()

    /// Son seçilen tab kaydedilmez — dashboard her açılışta "Kanallar"dan başlar.
    @State private var selectedTab: Int = 0
    // Keep poster sizing tied to the display, not to this view's transient layout.
    // Keyboard/status-bar/player transitions can temporarily shrink GeometryReader.
    private let posterMetrics = PosterMetrics(windowSize: UIScreen.main.bounds.size)

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
            // Animate only insertion/removal, never in-place source revisions.
            .animation(.easeOut(duration: 0.14), value: playerOverlay.presentation != nil)
            .zIndex(10_000)
        }
        .environmentObject(playerOverlay)
        .environment(\.epgSnapshot, epgStore.snapshot)
        .task(id: playlist.id) {
            favorites.track(playlistId: playlist.id)
            await store.loadPlaylist(playlist)
            epgStore.setActivePlaylist(playlist)
            await epgStore.refreshIfStale(playlist: playlist)
        }
        .alert(L("loading.error.title"), isPresented: Binding(
            get: {
                store.loadError != nil
                    && store.activePlaylistId == playlist.id
                    && !store.isLoading
            },
            set: { if !$0 { store.loadError = nil } }
        )) {
            Button(L("common.ok")) {
                store.loadError = nil
            }
            Button(L("common.try_again")) {
                store.loadError = nil
                Task { await store.loadPlaylist(playlist) }
            }
        } message: {
            Text(store.loadError ?? "")
        }
    }
}
