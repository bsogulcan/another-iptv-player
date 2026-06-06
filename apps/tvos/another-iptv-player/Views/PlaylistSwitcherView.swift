import SwiftUI

/// Blurred modal that lets the user switch playlists, add a new one, or
/// edit/delete an existing one. Presented over `DashboardView` so the
/// material backdrop can frost the dashboard behind it.
struct PlaylistSwitcherView: View {
    let playlists: [Playlist]
    let currentPlaylistId: UUID?
    let onSelect: (Playlist) -> Void
    let onAddRequest: () -> Void
    let onEditRequest: (Playlist) -> Void
    let onDeleteRequest: (Playlist) -> Void
    let onClose: () -> Void

    var body: some View {
        ModalMaterialBackground {
            NavigationStack {
                List {
                    ForEach(playlists) { playlist in
                        Button {
                            onSelect(playlist)
                        } label: {
                            row(for: playlist)
                        }
                        .contextMenu {
                            Button {
                                onEditRequest(playlist)
                            } label: {
                                Label(L("common.edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDeleteRequest(playlist)
                            } label: {
                                Label(L("common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .navigationTitle(L("playlists.title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("common.cancel")) { onClose() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onAddRequest()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
    }

    private func row(for playlist: Playlist) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(playlist.name).font(.headline)
                    Text(playlist.kind == .m3u ? "M3U" : "Xtream")
                        .font(.caption2.weight(.semibold))
                }
                Text(playlist.serverURL.isEmpty ? L("playlists.local_file") : playlist.serverURL)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if playlist.id == currentPlaylistId {
                Image(systemName: "checkmark")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
