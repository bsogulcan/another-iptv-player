import SwiftUI
import GRDBQuery
import GRDB

struct ContentView: View {
    @Query<PlaylistRequest> private var playlists: [Playlist]?

    init() {
        _playlists = Query(PlaylistRequest(), in: \.appDatabase)
    }

    /// The one sheet of the playlist list: a form for a new playlist of either
    /// kind, or for an existing one.
    private enum PlaylistSheet: Identifiable {
        case addXtream
        case addM3U
        case edit(Playlist)

        var id: String {
            switch self {
            case .addXtream: return "add-xtream"
            case .addM3U: return "add-m3u"
            case .edit(let playlist): return "edit-\(playlist.id.uuidString)"
            }
        }
    }

    @State private var activeSheet: PlaylistSheet?
    /// The row whose delete confirmation is up.
    @State private var pendingDeleteID: UUID?
    /// Playlists whose deletion was confirmed. Their rows are hidden from that
    /// moment: the delete cascades over the whole catalog and the query only
    /// reports it once that is done.
    @State private var deletingIDs: Set<UUID> = []
    @State private var deleteError: String?
    @State private var selectedPlaylist: Playlist?
    @State private var hasAttemptedAutoLoad = false
    @State private var showStorageWarning = false
    /// The playlist whose dashboard was left and whose catalog is still in memory,
    /// to be released when the way out has finished.
    @State private var playlistAwaitingRelease: Playlist?
    /// Counts the exits, so that only the latest one releases.
    @State private var exitCount = 0
    @Environment(\.appDatabase) private var appDatabase

    private let lastPlaylistKey = "lastPlaylistId"

    var body: some View {
        storageAwareBody
            .onAppear {
                if AppDatabase.isEphemeral || AppDatabase.didResetCorruptStore {
                    showStorageWarning = true
                }
            }
            .alert(
                AppDatabase.isEphemeral ? L("db.error.ephemeral_title") : L("db.error.reset_title"),
                isPresented: $showStorageWarning
            ) {
                Button(L("common.ok"), role: .cancel) {}
            } message: {
                Text(AppDatabase.isEphemeral ? L("db.error.ephemeral_message") : L("db.error.reset_message"))
            }
    }

    private var storageAwareBody: some View {
        ZStack {
            if let playlist = selectedPlaylist {
                Group {
                    if playlist.kind == .m3u {
                        M3UDashboardView(playlist: playlist) {
                            leaveDashboard(of: playlist)
                        }
                    } else {
                        DashboardView(playlist: playlist) {
                            leaveDashboard(of: playlist)
                        }
                    }
                }
                // Without an explicit order the layering of the two screens during
                // the removal is up to SwiftUI. The dashboard slides over the list
                // on the way in and off it on the way out.
                .zIndex(1)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
                .onAppear {
                    // Reaching a playlist's dashboard counts as a successful session.
                    // The dashboard itself asks for the review, once it is quiet.
                    RatingManager.shared.registerSuccessfulSession()
                }
            } else if hasAttemptedAutoLoad, let playlists = playlists {
                // The playlists are known in the very first body, before the
                // remembered one has been looked up. Waiting for that lookup keeps
                // a launch into a dashboard from building this list first.
                let visiblePlaylists = playlists.filter { !deletingIDs.contains($0.id) }
                NavigationStack {
                    Group {
                        if visiblePlaylists.isEmpty {
                            emptyState
                        } else {
                            playlistList(visiblePlaylists)
                        }
                    }
                    .navigationTitle(L("playlists.title"))
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                addPlaylistActions
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(L("playlists.empty.add_button"))
                            .accessibilityIdentifier("plus")
                        }
                    }
                    .sheet(item: $activeSheet) { sheet in
                        switch sheet {
                        case .addXtream:
                            AddPlaylistView()
                        case .addM3U:
                            AddM3UPlaylistView()
                        case .edit(let playlist):
                            if playlist.kind == .m3u {
                                AddM3UPlaylistView(editingPlaylist: playlist)
                            } else {
                                AddPlaylistView(editingPlaylist: playlist)
                            }
                        }
                    }
                    .alert(L("common.error"), isPresented: Binding(
                        get: { deleteError != nil },
                        set: { if !$0 { deleteError = nil } }
                    )) {
                        Button(L("common.ok"), role: .cancel) {}
                    } message: {
                        Text(deleteError ?? L("common.unknown_error"))
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
                refreshSelectedPlaylist(from: newList)
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

    /// Hands the dashboard the row as it is stored now. It used to keep the value
    /// it was opened with, so a setting saved inside it (adult filter, guide
    /// switch, guide URL) never reached the screens that act on it. Outside any
    /// animation and for the same playlist: the screen switch does not run again
    /// and work keyed on the playlist id does not restart.
    private func refreshSelectedPlaylist(from list: [Playlist]) {
        guard let current = selectedPlaylist,
              let stored = list.first(where: { $0.id == current.id }),
              stored != current else { return }
        selectedPlaylist = stored
    }

    private func selectPlaylist(_ playlist: Playlist) {
        // Picked while the previous dashboard is still on its way out: its release
        // is pending. Another playlist must not start on top of that catalog and
        // guide, so release now. The same playlist again keeps what is loaded.
        if let left = playlistAwaitingRelease {
            playlistAwaitingRelease = nil
            if left.id != playlist.id { releaseCatalog(of: left) }
        }
        UserDefaults.standard.set(playlist.id.uuidString, forKey: lastPlaylistKey)
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedPlaylist = playlist
        }
    }

    private func leaveDashboard(of playlist: Playlist) {
        UserDefaults.standard.removeObject(forKey: lastPlaylistKey)
        playlistAwaitingRelease = playlist
        exitCount += 1
        let exit = exitCount
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedPlaylist = nil
        } completion: {
            // Released here and not in the turn that starts the slide: freeing a
            // catalog of a few hundred thousand rows is main-thread work and would
            // hold the first frame back. An exit that was followed by another one
            // leaves the release to that one.
            guard exit == exitCount, let left = playlistAwaitingRelease else { return }
            playlistAwaitingRelease = nil
            releaseCatalog(of: left)
        }
    }

    /// Drops the in-memory catalog and the guide of a playlist that is no longer
    /// on screen; a later visit loads them from the database again.
    private func releaseCatalog(of playlist: Playlist) {
        if playlist.kind == .m3u {
            M3UContentStore.shared.unload()
        } else {
            PlaylistContentStore.shared.unload()
        }
        EPGStore.shared.setActivePlaylist(nil)
    }

    // MARK: - Adding

    /// The two kinds of playlist, for the + menu and the empty state. Each opens
    /// its form directly.
    @ViewBuilder
    private var addPlaylistActions: some View {
        Button {
            activeSheet = .addXtream
        } label: {
            Label(L("playlist_type.xtream.title"), systemImage: "server.rack")
            Text(L("playlist_type.xtream.subtitle"))
        }
        Button {
            activeSheet = .addM3U
        } label: {
            Label(L("playlist_type.m3u.title"), systemImage: "list.bullet.rectangle.portrait")
            Text(L("playlist_type.m3u.subtitle"))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("playlists.empty.title"), systemImage: "tv.badge.wifi")
        } description: {
            Text(L("playlists.empty.message"))
        } actions: {
            Menu {
                addPlaylistActions
            } label: {
                Text(L("playlists.empty.add_button"))
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - List

    private func playlistList(_ playlists: [Playlist]) -> some View {
        List {
            ForEach(playlists) { playlist in
                Button {
                    selectPlaylist(playlist)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(playlist.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(playlist.kind == .m3u ? "M3U" : "Xtream")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                                // A long name wraps; the badge keeps its size.
                                .fixedSize()
                        }
                        // The host only. The stored link of an M3U playlist carries
                        // the account in its query.
                        Text(playlist.displaySource)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .foregroundColor(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // No destructive role: with it the row leaves before the
                    // question has been answered.
                    Button {
                        pendingDeleteID = playlist.id
                    } label: {
                        Label(L("common.delete"), systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        activeSheet = .edit(playlist)
                    } label: {
                        Label(L("common.edit"), systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        activeSheet = .edit(playlist)
                    } label: {
                        Label(L("common.edit"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        pendingDeleteID = playlist.id
                    } label: {
                        Label(L("common.delete"), systemImage: "trash")
                    }
                }
                .confirmationDialog(
                    L("onboarding.delete.title_named", playlist.name),
                    isPresented: Binding(
                        get: { pendingDeleteID == playlist.id },
                        set: { if !$0, pendingDeleteID == playlist.id { pendingDeleteID = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button(L("common.delete"), role: .destructive) {
                        delete(playlist)
                    }
                    Button(L("common.cancel"), role: .cancel) {}
                } message: {
                    Text(L("playlists.delete.message"))
                }
            }
        }
    }

    private func delete(_ playlist: Playlist) {
        let id = playlist.id
        withAnimation {
            _ = deletingIDs.insert(id)
        }
        Task {
            do {
                _ = try await appDatabase.write { db in
                    try Playlist.deleteAll(db, ids: [id])
                }
                HiddenCategoryStore.shared.removeAll(playlistId: id)
                DownloadManager.shared.cleanupPlaylist(playlistId: id)
                ImportedSubtitleStore.removeAll(playlistId: id)
                // The per-content subtitle offsets are keyed by the same content
                // keys; without this they outlive the playlist until the store's
                // entry cap evicts them.
                SubtitleDelayStore.removeAll(playlistId: id)
                EPGStore.forgetLineReservation(playlistId: id)
                // The id stays in `deletingIDs`: the query drops the row a moment
                // after the write returns, and the row must not show up in between.
            } catch {
                // Still there after all: bring the row back and say why.
                withAnimation {
                    _ = deletingIDs.remove(id)
                }
                deleteError = NetworkErrorText.describe(error)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, .empty())
}
