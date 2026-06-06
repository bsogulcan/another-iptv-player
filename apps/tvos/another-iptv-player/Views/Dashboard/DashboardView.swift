import SwiftUI

struct DashboardView: View {
    let playlist: Playlist
    let onSwitchPlaylist: () -> Void

    @StateObject private var contentStore = PlaylistContentStore.shared

    @AppStorage("dashboard_selected_tab") private var savedTab: Int = 0
    @State private var selectedTab: Int = 0

    private var tabBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                selectedTab = newTab
                if newTab < 3 { savedTab = newTab }
            }
        )
    }

    private var isInitialLoading: Bool {
        contentStore.isLoading && contentStore.activePlaylistId == playlist.id
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()

            if isInitialLoading {
                loadingOverlay
            } else {
                TabView(selection: tabBinding) {
                    Tab(L("dashboard.live"), systemImage: "tv", value: 0) {
                        NavigationStack {
                            LiveTVTabView(playlist: playlist)
                                .environmentObject(contentStore)
                        }
                    }
                    Tab(L("dashboard.movies"), systemImage: "film", value: 1) {
                        NavigationStack {
                            MoviesTabView(playlist: playlist)
                                .environmentObject(contentStore)
                        }
                    }
                    Tab(L("dashboard.series"), systemImage: "play.tv", value: 2) {
                        NavigationStack {
                            SeriesTabView(playlist: playlist)
                                .environmentObject(contentStore)
                        }
                    }
                    Tab(L("dashboard.settings"), systemImage: "gear", value: 3) {
                        NavigationStack {
                            SettingsTabView(playlist: playlist, onSwitchPlaylist: onSwitchPlaylist)
                                .environmentObject(contentStore)
                        }
                    }
                    Tab(L("dashboard.search"), systemImage: "magnifyingglass", value: 4, role: .search) {
                        NavigationStack {
                            SearchTabView(playlist: playlist)
                                .environmentObject(contentStore)
                        }
                    }
                }
            }
        }
        .task {
            selectedTab = savedTab
        }
        .task(id: playlist.id) {
            await contentStore.loadPlaylist(playlist)
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
    }

    private var loadingOverlay: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            if let msg = contentStore.loadingMessage {
                Text(msg)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
