import SwiftUI
import GRDBQuery
import GRDB

struct ContentView: View {
    @Query<PlaylistRequest> private var playlists: [Playlist]?

    init() {
        _playlists = Query(PlaylistRequest(), in: \.appDatabase)
    }

    @State private var selectedPlaylist: Playlist?
    @State private var playlistFullScreen: PlaylistFullScreen?
    @State private var showPlaylistSwitcher = false
    @State private var playlistToDelete: Playlist?
    @State private var showingDeleteAlert = false
    @State private var hasAttemptedAutoLoad = false
    @Environment(\.appDatabase) private var appDatabase

    private let lastPlaylistKey = "lastPlaylistId"

    var body: some View {
        ZStack {
            baseLayer

            if showPlaylistSwitcher {
                PlaylistSwitcherView(
                    playlists: playlists ?? [],
                    currentPlaylistId: selectedPlaylist?.id,
                    onSelect: { pick($0) },
                    onAddRequest: { playlistFullScreen = .add },
                    onEditRequest: { playlistFullScreen = .edit($0) },
                    onDeleteRequest: { requestDelete($0) },
                    onClose: closeSwitcher
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(1)
                .onExitCommand(perform: closeSwitcher)
            }

            if let route = playlistFullScreen {
                Group {
                    switch route {
                    case .add:
                        PlaylistAddNavigationView(onClose: dismissModal)
                    case .edit(let playlist):
                        PlaylistEditContainerView(playlist: playlist, onClose: dismissModal)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(2)
                .onExitCommand(perform: dismissModal)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: playlistFullScreen)
        .animation(.easeInOut(duration: 0.28), value: showPlaylistSwitcher)
        .animation(.easeInOut(duration: 0.35), value: selectedPlaylist?.id)
        .onAppear {
            if let playlists = playlists {
                attemptAutoLoad(playlists)
            }
        }
        .onChange(of: playlists) { _, newList in
            if let newList = newList {
                attemptAutoLoad(newList)
                reconcileSelection(with: newList)
            }
        }
        .alert(L("playlists.delete.title"), isPresented: $showingDeleteAlert) {
            Button(L("common.delete"), role: .destructive) {
                if let playlist = playlistToDelete {
                    performDelete(playlist: playlist)
                }
            }
            Button(L("common.cancel"), role: .cancel) {
                playlistToDelete = nil
            }
        } message: {
            Text(L("playlists.delete.message"))
        }
    }

    @ViewBuilder
    private var baseLayer: some View {
        if let playlist = selectedPlaylist {
            DashboardView(playlist: playlist, onSwitchPlaylist: openSwitcher)
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
        } else if (playlists?.isEmpty ?? true) {
            welcomeView
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv.badge.wifi")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            Text(L("playlists.empty.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(L("playlists.empty.message"))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                playlistFullScreen = .add
            } label: {
                Text(L("playlists.empty.add_button"))
            }
        }
    }

    private func openSwitcher() {
        showPlaylistSwitcher = true
    }

    private func closeSwitcher() {
        showPlaylistSwitcher = false
    }

    private func dismissModal() {
        playlistFullScreen = nil
    }

    private func attemptAutoLoad(_ list: [Playlist]) {
        guard !hasAttemptedAutoLoad else { return }
        hasAttemptedAutoLoad = true
        guard !list.isEmpty else { return }

        if let lastIdString = UserDefaults.standard.string(forKey: lastPlaylistKey),
           let lastId = UUID(uuidString: lastIdString),
           let playlist = list.first(where: { $0.id == lastId }) {
            selectedPlaylist = playlist
        } else {
            selectedPlaylist = list.first
            persistSelection(list.first)
        }
    }

    /// Keeps `selectedPlaylist` consistent when the database list changes
    /// (e.g. the selected playlist was deleted, or the first one was added).
    private func reconcileSelection(with list: [Playlist]) {
        if let current = selectedPlaylist,
           !list.contains(where: { $0.id == current.id }) {
            selectedPlaylist = list.first
            persistSelection(list.first)
        } else if selectedPlaylist == nil, let first = list.first, hasAttemptedAutoLoad {
            selectedPlaylist = first
            persistSelection(first)
        }
    }

    private func pick(_ playlist: Playlist) {
        withAnimation(.easeInOut(duration: 0.35)) {
            selectedPlaylist = playlist
            showPlaylistSwitcher = false
        }
        persistSelection(playlist)
    }

    private func persistSelection(_ playlist: Playlist?) {
        if let playlist = playlist {
            UserDefaults.standard.set(playlist.id.uuidString, forKey: lastPlaylistKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastPlaylistKey)
        }
    }

    private func requestDelete(_ playlist: Playlist) {
        playlistToDelete = playlist
        showingDeleteAlert = true
    }

    private func performDelete(playlist: Playlist) {
        Task {
            do {
                _ = try await appDatabase.write { db in
                    try Playlist.deleteOne(db, id: playlist.id)
                }
            } catch {
                print("Failed to delete playlist: \(error)")
            }
            playlistToDelete = nil
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, .empty())
}
