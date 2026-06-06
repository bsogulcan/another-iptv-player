import SwiftUI
import GRDB

struct MoviesTabView: View {
    let playlist: Playlist
    @EnvironmentObject private var contentStore: PlaylistContentStore
    @State private var selectedMovie: DBVODStream?
    @State private var navigatedCategory: DBCategory?

    var body: some View {
        CategoryListView(
            categories: contentStore.vodCategories,
            itemsForCategory: { contentStore.vodStreamsByCategoryId[$0.id] ?? [] },
            cardWidth: 280,
            emptyTitle: L("movies.empty"),
            emptyIcon: "film",
            shelfEmptyMessage: L("movies.empty"),
            isLoading: !contentStore.streamsLoaded,
            onCategoryTap: { navigatedCategory = $0 },
            header: {
                ContinueWatchingShelf(playlist: playlist, typeFilter: "vod") { item in
                    Task { await openMovieDetail(item) }
                }
            }
        ) { (item: VODWithCategory) in
            PosterCard(
                title: item.stream.name,
                subtitle: nil,
                imageURL: item.stream.streamIcon.flatMap(URL.init(string:))
            ) {
                selectedMovie = item.stream
            }
        }
        .navigationTitle(L("dashboard.movies"))
        .navigationDestination(item: $navigatedCategory) { category in
            CategoryGridView(
                title: category.name,
                items: contentStore.vodStreamsByCategoryId[category.id] ?? [],
                cardWidth: 280,
                emptyIcon: "film",
                emptyMessage: L("movies.empty")
            ) { (item: VODWithCategory) in
                PosterCard(
                    title: item.stream.name,
                    subtitle: nil,
                    imageURL: item.stream.streamIcon.flatMap(URL.init(string:))
                ) {
                    selectedMovie = item.stream
                }
            }
        }
        .fullScreenCover(item: $selectedMovie) { movie in
            // Own NavigationStack so the dashboard tab bar is not visible behind
            // the detail — feels like a separate "page" the way tvOS apps usually
            // present hero content.
            NavigationStack {
                MovieDetailView(playlist: playlist, movie: movie)
            }
        }
    }

    /// Open the detail view for a Continue Watching entry. If the underlying
    /// stream was removed from the library, drop the stale history row so it
    /// stops showing in the shelf.
    @MainActor
    private func openMovieDetail(_ item: DBWatchHistory) async {
        guard let streamIdInt = Int(item.streamId) else { return }
        do {
            let stream = try await AppDatabase.shared.read { db in
                try DBVODStream
                    .filter(Column("streamId") == streamIdInt && Column("playlistId") == playlist.id)
                    .fetchOne(db)
            }
            guard let stream else {
                try? await AppDatabase.shared.write { db in try db.execute(
                    sql: "DELETE FROM watchHistory WHERE id = ?",
                    arguments: [item.id]
                ) }
                return
            }
            selectedMovie = stream
        } catch {
            print("[MoviesTab] openMovieDetail failed: \(error)")
        }
    }
}
