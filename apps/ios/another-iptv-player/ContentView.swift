import SwiftUI
import GRDBQuery
import GRDB

struct ContentView: View {
    @Query<PlaylistRequest> private var playlists: [Playlist]?
    
    init() {
        _playlists = Query(PlaylistRequest(), in: \.appDatabase)
    }
    @State private var showingTypePicker = false
    @State private var showingAddXtreamPlaylist = false
    @State private var showingAddM3UPlaylist = false
    @State private var playlistToEdit: Playlist?
    @State private var offsetsToDelete: IndexSet?
    @State private var showingDeleteAlert = false
    @State private var selectedPlaylist: Playlist?
    @State private var hasAttemptedAutoLoad = false
    @Environment(\.appDatabase) private var appDatabase
    
    private let lastPlaylistKey = "lastPlaylistId"
    
    var body: some View {
        ZStack {
            if let playlist = selectedPlaylist {
                Group {
                    if playlist.kind == .m3u {
                        M3UDashboardView(playlist: playlist) {
                            UserDefaults.standard.removeObject(forKey: lastPlaylistKey)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedPlaylist = nil
                            }
                        }
                    } else {
                        DashboardView(playlist: playlist) {
                            UserDefaults.standard.removeObject(forKey: lastPlaylistKey)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedPlaylist = nil
                            }
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
                .onAppear {
                    // Bir playlist dashboard'una ulaşmak = başarılı oturum.
                    RatingManager.shared.registerSuccessfulSession()
                    Task {
                        // Kullanıcıyı karşılama anında bölmemek için kısa gecikme.
                        try? await Task.sleep(for: .seconds(8))
                        RatingManager.shared.requestReviewIfAppropriate()
                    }
                }
            } else if let playlists = playlists {
                NavigationStack {
                    Group {
                        if playlists.isEmpty {
                            emptyState
                        } else {
                            playlistList
                        }
                    }
                    .navigationTitle(L("playlists.title"))
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingTypePicker = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showingTypePicker) {
                        PlaylistTypeSelectionView(
                            onSelectXtream: { showingAddXtreamPlaylist = true },
                            onSelectM3U: { showingAddM3UPlaylist = true }
                        )
                    }
                    .sheet(isPresented: $showingAddXtreamPlaylist) {
                        AddPlaylistView()
                    }
                    .sheet(isPresented: $showingAddM3UPlaylist) {
                        AddM3UPlaylistView()
                    }
                    .sheet(item: $playlistToEdit) { playlist in
                        if playlist.kind == .m3u {
                            AddM3UPlaylistView(editingPlaylist: playlist)
                        } else {
                            AddPlaylistView(editingPlaylist: playlist)
                        }
                    }
                    .alert(L("playlists.delete.title"), isPresented: $showingDeleteAlert) {
                        Button(L("common.delete"), role: .destructive) {
                            if let offsets = offsetsToDelete {
                                performDelete(offsets: offsets)
                            }
                        }
                        Button(L("common.cancel"), role: .cancel) {
                            offsetsToDelete = nil
                        }
                    } message: {
                        Text(L("playlists.delete.message"))
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
            } else {
                // Initial check in progress, show system background to prevent flicker
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if let playlists = playlists {
                attemptAutoLoad(playlists)
            }
        }
        .onChange(of: playlists) { _, newList in
            if let newList = newList {
                attemptAutoLoad(newList)
            }
        }
    }
    
    private func attemptAutoLoad(_ list: [Playlist]) {
        guard !hasAttemptedAutoLoad else { return }
        
        // If the query has returned (even if empty), we finalize the check
        hasAttemptedAutoLoad = true
        
        if let lastIdString = UserDefaults.standard.string(forKey: lastPlaylistKey),
           let lastId = UUID(uuidString: lastIdString),
           let playlist = list.first(where: { $0.id == lastId }) {
            selectedPlaylist = playlist
        }
    }
    
    private func selectPlaylist(_ playlist: Playlist) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedPlaylist = playlist
            UserDefaults.standard.set(playlist.id.uuidString, forKey: lastPlaylistKey)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv.badge.wifi")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
            
            Text(L("playlists.empty.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(L("playlists.empty.message"))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button {
                showingTypePicker = true
            } label: {
                Text(L("playlists.empty.add_button"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 10)
        }
    }
    

    
    private var playlistList: some View {
        List {
            if let playlists = playlists {
                ForEach(playlists) { playlist in
                    Button {
                        selectPlaylist(playlist)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(playlist.name)
                                            .font(.headline)
                                        Text(playlist.kind == .m3u ? "M3U" : "Xtream")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(4)
                                    }
                                    Text(playlist.serverURL.isEmpty ? L("playlists.local_file") : playlist.serverURL)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundColor(.primary)
                    .swipeActions(edge: .leading) {
                        Button {
                            playlistToEdit = playlist
                        } label: {
                            Label(L("common.edit"), systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete(perform: deletePlaylists)
            }
        }
    }
    
    private func deletePlaylists(offsets: IndexSet) {
        offsetsToDelete = offsets
        showingDeleteAlert = true
    }
    
    private func performDelete(offsets: IndexSet) {
        Task {
            do {
                guard let playlists = playlists else { return }
                let idsToDelete = offsets.map { playlists[$0].id }
                _ = try await appDatabase.write { db in
                    try Playlist.deleteAll(db, ids: idsToDelete)
                }
                for id in idsToDelete {
                    HiddenCategoryStore.shared.removeAll(playlistId: id)
                    DownloadManager.shared.cleanupPlaylist(playlistId: id)
                }
            } catch {
                print("Failed to delete playlist: \(error)")
            }
            offsetsToDelete = nil
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, .empty())
}
