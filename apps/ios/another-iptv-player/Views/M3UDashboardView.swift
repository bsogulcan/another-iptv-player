import SwiftUI

/// M3U türündeki playlist için TabView. Canlı/Film/Dizi ayrımı yok — tek "Kanallar" listesi.
struct M3UDashboardView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    @ObservedObject private var store = M3UContentStore.shared
    @ObservedObject private var favorites = M3UFavoriteStore.shared
    @StateObject private var playerOverlay = PlayerOverlayController()

    /// Son seçilen tab kaydedilmez — dashboard her açılışta "Kanallar"dan başlar.
    @State private var selectedTab: Int = 0
    @State private var windowSize = UIScreen.main.bounds.size

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
            .environment(\.posterMetrics, PosterMetrics(windowSize: windowSize))

            ZStack {
                if let item = playerOverlay.presentation {
                    item.root
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.playerOverlayDismiss) {
                            playerOverlay.dismiss(animated: true)
                        }
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.22), value: playerOverlay.presentation?.id)
            .zIndex(10_000)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowSize = geo.size }
                    .onChange(of: geo.size) { _, size in windowSize = size }
            }
        )
        .environmentObject(playerOverlay)
        .task(id: playlist.id) {
            favorites.track(playlistId: playlist.id)
            await store.loadPlaylist(playlist)
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
