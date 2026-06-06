import SwiftUI

struct SeriesTabView: View {
    let playlist: Playlist
    @EnvironmentObject private var contentStore: PlaylistContentStore
    @State private var selectedSeries: DBSeries?
    @State private var navigatedCategory: DBCategory?

    var body: some View {
        CategoryListView(
            categories: contentStore.seriesCategories,
            itemsForCategory: { contentStore.seriesItemsByCategoryId[$0.id] ?? [] },
            cardWidth: 280,
            emptyTitle: L("series.empty"),
            emptyIcon: "play.tv",
            shelfEmptyMessage: L("series.empty"),
            isLoading: !contentStore.streamsLoaded,
            onCategoryTap: { navigatedCategory = $0 },
            header: {
                ContinueWatchingSeriesShelf(playlist: playlist) { entry in
                    selectedSeries = entry.series
                }
            }
        ) { (item: SeriesWithCategory) in
            PosterCard(
                title: item.series.name,
                subtitle: nil,
                imageURL: item.series.cover.flatMap(URL.init(string:))
            ) {
                selectedSeries = item.series
            }
        }
        .navigationTitle(L("dashboard.series"))
        .navigationDestination(item: $navigatedCategory) { category in
            CategoryGridView(
                title: category.name,
                items: contentStore.seriesItemsByCategoryId[category.id] ?? [],
                cardWidth: 280,
                emptyIcon: "play.tv",
                emptyMessage: L("series.empty")
            ) { (item: SeriesWithCategory) in
                PosterCard(
                    title: item.series.name,
                    subtitle: nil,
                    imageURL: item.series.cover.flatMap(URL.init(string:))
                ) {
                    selectedSeries = item.series
                }
            }
        }
        .fullScreenCover(item: $selectedSeries) { series in
            NavigationStack {
                SeriesDetailView(playlist: playlist, series: series)
            }
        }
    }
}
