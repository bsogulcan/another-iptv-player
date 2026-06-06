import SwiftUI

/// M3U favorileri grid görünümü. `M3UFavoriteStore` üstünden reaktif günceller.
struct M3UFavoritesView: View {
    let playlist: Playlist

    @ObservedObject private var store = M3UContentStore.shared
    @ObservedObject private var favorites = M3UFavoriteStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    @State private var searchText = ""

    private var favoriteChannels: [DBM3UChannel] {
        // Sıralama: DB'deki kanal listesindeki orijinal sıra (sortIndex) korunur.
        store.channels.filter { favorites.isFavorite(channelId: $0.id) }
    }

    private var filtered: [DBM3UChannel] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return favoriteChannels }
        return favoriteChannels.filter { CatalogTextSearch.matches(search: q, text: $0.name) }
    }

    var body: some View {
        Group {
            if favoriteChannels.isEmpty {
                ContentUnavailableView(
                    L("favorites.empty.title"),
                    systemImage: "star",
                    description: Text(L("favorites.empty.message"))
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    L("favorites.empty.no_result.title"),
                    systemImage: "magnifyingglass",
                    description: Text(L("category_picker.not_found.message"))
                )
            } else {
                M3UGroupGridContent(items: filtered) { channel in
                    present(channel)
                }
            }
        }
        .searchable(text: $searchText, prompt: L("favorites.search_placeholder"))
        .navigationTitle(L("favorites.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func present(_ channel: DBM3UChannel) {
        guard M3UParser.sanitizedURL(from: channel.url) != nil else { return }
        // Favorilerden oynatırken queue = favori listesi (prev/next favoriler arasında geçer).
        playerOverlay.present {
            M3UPlayerShell(
                playlist: playlist,
                channel: channel,
                queue: filtered
            )
        }
    }
}
