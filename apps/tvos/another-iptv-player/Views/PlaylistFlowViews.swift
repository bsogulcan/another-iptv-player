import SwiftUI

// MARK: - Yeni playlist: native NavigationStack + NavigationLink

struct PlaylistAddNavigationView: View {
    let onClose: () -> Void

    @State private var navPath: [PlaylistKind] = []

    var body: some View {
        ModalMaterialBackground {
            NavigationStack(path: $navPath) {
                List {
                    Section(header: Text(L("playlist_type.section"))) {
                        NavigationLink(value: PlaylistKind.xtream) {
                            playlistKindRow(
                                icon: "server.rack",
                                title: L("playlist_type.xtream.title"),
                                subtitle: L("playlist_type.xtream.subtitle")
                            )
                        }
                        NavigationLink(value: PlaylistKind.m3u) {
                            playlistKindRow(
                                icon: "list.bullet.rectangle.portrait",
                                title: L("playlist_type.m3u.title"),
                                subtitle: L("playlist_type.m3u.subtitle")
                            )
                        }
                    }
                }
                .navigationTitle(L("playlist_type.title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("common.cancel")) { onClose() }
                    }
                }
                .navigationDestination(for: PlaylistKind.self) { kind in
                    switch kind {
                    case .xtream:
                        AddPlaylistView(
                            editingPlaylist: nil,
                            onFinished: onClose,
                            onCancel: popNav
                        )
                    case .m3u:
                        AddM3UPlaylistView(
                            editingPlaylist: nil,
                            onFinished: onClose,
                            onCancel: popNav
                        )
                    }
                }
            }
        }
    }

    private func popNav() {
        if !navPath.isEmpty {
            navPath.removeLast()
        } else {
            onClose()
        }
    }

    private func playlistKindRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Düzenleme: tek form, kendi Navigation başlığı

struct PlaylistEditContainerView: View {
    let playlist: Playlist
    let onClose: () -> Void

    var body: some View {
        ModalMaterialBackground {
            NavigationStack {
                Group {
                    if playlist.kind == .m3u {
                        AddM3UPlaylistView(
                            editingPlaylist: playlist,
                            onFinished: onClose,
                            onCancel: onClose
                        )
                    } else {
                        AddPlaylistView(
                            editingPlaylist: playlist,
                            onFinished: onClose,
                            onCancel: onClose
                        )
                    }
                }
            }
        }
    }
}

/// Heavy frosted-glass wrapper used by inline modal overlays on tvOS —
/// `presentationBackground` on a `fullScreenCover` can't reach the underlying
/// ContentView (tvOS paints the cover's backing opaque), so we render the
/// modal inline in ContentView's ZStack and blur what's actually behind it.
/// Using `ultraThickMaterial` (Apple's own choice for Settings / pairing
/// sheets) so the previous screen's shapes blur into an unreadable wash.
struct ModalMaterialBackground<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
            content()
        }
    }
}
