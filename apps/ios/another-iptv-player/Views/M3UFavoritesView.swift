import SwiftUI

/// M3U favorileri grid görünümü. `M3UFavoriteStore` üstünden reaktif günceller.
///
/// 310K+ kanallık kataloglarda body başına tam liste taraması yapmamak için favori ve
/// arama sonuçları @State'te tutulur, `.task(id:)` ile (debounce'lu) yeniden hesaplanır.
struct M3UFavoritesView: View {
    let playlist: Playlist

    @ObservedObject private var store = M3UContentStore.shared
    @ObservedObject private var favorites = M3UFavoriteStore.shared
    @Environment(\.playerOverlayController) private var playerOverlay

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// The favourites that are in the playlist, in playlist order. nil until the first
    /// scan of the catalog has answered: "none" is only known after it.
    @State private var favoriteChannels: [DBM3UChannel]?
    @State private var filtered: [DBM3UChannel] = []
    @State private var resultRevision = 0
    /// Input of the scan whose result is on screen.
    @State private var appliedKey: RecomputeKey?

    /// Favori kümesi veya katalog değişince yeniden hesaplama tetiği.
    /// The store's revision stands for the catalog: a channel count misses a refresh
    /// that leaves the size unchanged.
    private struct RecomputeKey: Equatable {
        let favoriteIds: Set<String>
        let revision: Int
        let query: String
        let activePlaylistId: UUID?
        let isLoading: Bool
        let favoritesLoaded: Bool
    }

    private var recomputeKey: RecomputeKey {
        RecomputeKey(favoriteIds: favorites.favoriteIds, revision: store.revision, query: debouncedQuery, activePlaylistId: store.activePlaylistId, isLoading: store.isLoading, favoritesLoaded: favorites.isLoaded(for: playlist.id))
    }

    var body: some View {
        Group {
            if let error = favorites.error(for: playlist.id) {
                InlineErrorRow(message: error) {
                    favorites.track(playlistId: playlist.id)
                }
                .padding()
            } else if !favorites.isLoaded(for: playlist.id) {
                Color.clear
            } else if favorites.favoriteIds.isEmpty {
                noFavoritesState
            } else if let favoriteChannels {
                if favoriteChannels.isEmpty {
                    noFavoritesState
                } else if filtered.isEmpty {
                    CatalogEmptyView(.noSearchResults)
                } else {
                    M3UGroupGridContent(items: filtered, contentID: .favorites(playlist.id, resultRevision), menu: .favorites, onChannelSelected: { channel in
                        present(channel)
                    })
                    .equatable()
                }
            } else {
                // The scan has not answered yet. Nothing is drawn for those few frames:
                // the empty state here would flash before the grid replaces it.
                Color.clear
            }
        }
        .searchable(text: $searchText, prompt: L("favorites.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                debouncedQuery = ""
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = new
            }
        }
        .task(id: recomputeKey) { await recompute() }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .navigationTitle(L("favorites.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var noFavoritesState: some View {
        CatalogEmptyView(.message(
            title: L("favorites.empty.title"),
            systemImage: "star",
            description: L("favorites.empty.message")
        ))
    }

    private func recompute() async {
        let key = recomputeKey
        // The task also restarts when the screen comes back (a tab switch); the lists
        // on screen are still the answer then.
        guard key != appliedKey else { return }
        guard key.favoritesLoaded, key.activePlaylistId == playlist.id, !(key.isLoading && store.channels.isEmpty) else {
            favoriteChannels = nil
            appliedKey = nil
            return
        }
        let channels = store.channels
        let ids = key.favoriteIds
        let query = key.query.trimmingCharacters(in: .whitespaces)
        let result = await CatalogTextSearch.detached { () -> ([DBM3UChannel], [DBM3UChannel]) in
            // Sıralama: DB'deki kanal listesindeki orijinal sıra (sortIndex) korunur.
            let favs = ids.isEmpty ? [] : channels.filter { ids.contains($0.id) }
            // A blank query returns the favourites as they are; a real one ranks its hits.
            let hits = CatalogTextSearch.rankedFilter(favs, search: query) { $0.name }
            return (favs, hits)
        }
        // A cancelled scan returns empty lists, which must not be shown as "no favourites".
        guard !Task.isCancelled else { return }
        favoriteChannels = result.0
        filtered = result.1
        resultRevision += 1
        appliedKey = key
    }

    private func present(_ channel: DBM3UChannel) {
        // Favorilerden oynatırken queue = favori listesi (prev/next favoriler arasında geçer).
        guard let overlay = playerOverlay.injected else { return }
        M3UPlayback.present(channel, queue: filtered, playlist: playlist, overlay: overlay)
    }
}
