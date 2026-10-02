import SwiftUI
import GRDB
import GRDBQuery

struct FavoritesView: View {
    let playlist: Playlist

    @State private var selectedType: String
    @State private var searchText = ""
    @Environment(\.posterMetrics) private var posterMetrics
    @Environment(\.playerOverlayController) private var playerOverlay
    @Namespace private var zoomNamespace

    // `nil` until the database has answered, so a type with favourites does not
    // open on its "no favourites yet" text; see `LoadedRequest`.
    @Query<LoadedRequest<FavoriteLiveRequest>> private var loadedLive: [LiveStreamWithCategory]?
    @Query<LoadedRequest<FavoriteVODRequest>> private var loadedVODs: [VODWithCategory]?
    @Query<LoadedRequest<FavoriteSeriesRequest>> private var loadedSeries: [SeriesWithCategory]?
    @Query<WatchProgressMapRequest> private var vodProgressMap: [String: Double]
    @Query<WatchProgressMapRequest> private var seriesProgressMap: [String: Double]

    init(playlist: Playlist, initialType: String = "vod") {
        self.playlist = playlist
        self._selectedType = State(initialValue: initialType)
        _loadedLive = Query(LoadedRequest(FavoriteLiveRequest(playlistId: playlist.id)), in: \.appDatabase)
        _loadedVODs = Query(LoadedRequest(FavoriteVODRequest(playlistId: playlist.id)), in: \.appDatabase)
        _loadedSeries = Query(LoadedRequest(FavoriteSeriesRequest(playlistId: playlist.id)), in: \.appDatabase)
        _vodProgressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "vod"), in: \.appDatabase)
        _seriesProgressMap = Query(WatchProgressMapRequest(playlistId: playlist.id, type: "series"), in: \.appDatabase)
    }

    private var favoriteLive: [LiveStreamWithCategory] { loadedLive ?? [] }
    private var favoriteVODs: [VODWithCategory] { loadedVODs ?? [] }
    private var favoriteSeries: [SeriesWithCategory] { loadedSeries ?? [] }

    private var gridColumns: [GridItem] {
        let minimum = selectedType == "live" ? posterMetrics.liveGridIconSize : posterMetrics.categoryGridPosterWidth
        return [GridItem(.adaptive(minimum: minimum), spacing: posterMetrics.gridSpacing, alignment: .top)]
    }

    var body: some View {
        // A real container, not a `Group`: a modifier on a `Group` is applied to each
        // branch, which would rebuild the picker (and cut its selection animation)
        // on every type change.
        ZStack {
            if selectedType == "live" {
                liveGrid
            } else if selectedType == "vod" {
                vodGrid
            } else {
                seriesGrid
            }
        }
        .topAccessoryBar {
            Picker(L("favorites.type"), selection: $selectedType) {
                Text(L("dashboard.live")).tag("live")
                Text(L("dashboard.movies")).tag("vod")
                Text(L("dashboard.series")).tag("series")
            }
            .pickerStyle(.segmented)
            // 16 pt: the horizontal inset of the grids below.
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle(L("favorites.title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: L("favorites.search_placeholder"))
    }

    // MARK: - Search filtering (favori listeleri küçük olduğundan render başına filtre yeterli)

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespaces) }

    private func displayed<Item>(_ items: [Item], name: (Item) -> String) -> [Item] {
        guard !trimmedQuery.isEmpty else { return items }
        let query = CatalogTextSearch.Query(trimmedQuery)
        return items.filter { query.matches(name($0)) }
    }

    private func presentFavoriteLive(stream: DBLiveStream, history: DBWatchHistory?, queue: [DBLiveStream]) {
        // Diğer tüm canlı giriş noktaları gibi LivePlayerShell: favoriler arası
        // önceki/sonraki kanal ve yan panel çalışsın (çıplak PlayerView bunları kaybediyordu).
        let sections = [LiveChannelCategorySection(
            id: "favorites",
            title: L("favorites.title"),
            streams: queue
        )]
        playerOverlay.injected?.present(playlistId: playlist.id) {
            LivePlayerShell(
                playlist: playlist,
                queue: queue,
                sections: sections,
                initialStream: stream,
                initialHistory: history,
                subtitle: nil
            )
        }
    }

    @ViewBuilder
    private var liveGrid: some View {
        let shown = displayed(favoriteLive) { $0.stream.name }
        if loadedLive == nil {
            Color.clear
        } else if shown.isEmpty {
            emptyState(icon: "tv", title: L("favorites.empty.live"), hasFavorites: !favoriteLive.isEmpty)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: posterMetrics.gridRowSpacing) {
                    ForEach(shown) { item in
                        Button {
                            presentFavoriteLive(stream: item.stream, history: nil, queue: shown.map(\.stream))
                        } label: {
                            FavoriteChannelCell(stream: item.stream, side: posterMetrics.liveGridIconSize)
                        }
                        .buttonStyle(.cardPress)
                        .accessibilityIdentifier("card.live.\(item.stream.streamId)")
                        .favoriteCellMenu(cornerRadius: BrowseMetrics.tileCornerRadius) {
                            FavoriteMenuButton(streamId: item.stream.streamId, type: "live", playlistId: playlist.id)
                        }
                    }
                }
                .padding()
                // Keyed on the unfiltered list: a removed favourite lets the other
                // cells reflow, typing in the search field stays instant.
                .animation(.snappy, value: favoriteLive.map(\.stream.streamId))
            }
        }
    }

    @ViewBuilder
    private var vodGrid: some View {
        let shown = displayed(favoriteVODs) { $0.stream.name }
        if loadedVODs == nil {
            Color.clear
        } else if shown.isEmpty {
            emptyState(icon: "film", title: L("favorites.empty.movie"), hasFavorites: !favoriteVODs.isEmpty)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: posterMetrics.gridRowSpacing) {
                    ForEach(shown) { item in
                        let zoomId = "vod.\(item.stream.streamId)"
                        NavigationLink {
                            MovieDetailView(playlist: playlist, movie: item.stream)
                                .posterZoomDestination(id: zoomId, in: zoomNamespace)
                        } label: {
                            FavoritePosterCell(
                                title: item.stream.name,
                                imageURL: item.stream.streamIcon,
                                iconName: "film",
                                rating: item.stream.rating,
                                categoryName: item.categoryName,
                                watchProgress: vodProgressMap[String(item.stream.streamId)],
                                width: posterMetrics.categoryGridPosterWidth,
                                height: posterMetrics.categoryGridPosterHeight,
                                zoomId: zoomId,
                                zoomNamespace: zoomNamespace
                            )
                        }
                        .buttonStyle(.cardPress)
                        .accessibilityIdentifier("card.vod.\(item.stream.streamId)")
                        .favoriteCellMenu(cornerRadius: BrowseMetrics.posterCornerRadius) {
                            FavoriteMenuButton(streamId: item.stream.streamId, type: "vod", playlistId: playlist.id)
                        }
                    }
                }
                .padding()
                .animation(.snappy, value: favoriteVODs.map(\.stream.streamId))
            }
        }
    }

    @ViewBuilder
    private var seriesGrid: some View {
        let shown = displayed(favoriteSeries) { $0.series.name }
        if loadedSeries == nil {
            Color.clear
        } else if shown.isEmpty {
            emptyState(icon: "play.tv", title: L("favorites.empty.series"), hasFavorites: !favoriteSeries.isEmpty)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: posterMetrics.gridRowSpacing) {
                    ForEach(shown) { item in
                        let zoomId = "series.\(item.series.seriesId)"
                        NavigationLink {
                            SeriesDetailView(playlist: playlist, series: item.series)
                                .posterZoomDestination(id: zoomId, in: zoomNamespace)
                        } label: {
                            FavoritePosterCell(
                                title: item.series.name,
                                imageURL: item.series.cover,
                                iconName: "play.tv",
                                rating: item.series.rating,
                                categoryName: item.categoryName,
                                watchProgress: seriesProgressMap[String(item.series.seriesId)],
                                width: posterMetrics.categoryGridPosterWidth,
                                height: posterMetrics.categoryGridPosterHeight,
                                zoomId: zoomId,
                                zoomNamespace: zoomNamespace
                            )
                        }
                        .buttonStyle(.cardPress)
                        .accessibilityIdentifier("card.series.\(item.series.seriesId)")
                        .favoriteCellMenu(cornerRadius: BrowseMetrics.posterCornerRadius) {
                            FavoriteMenuButton(streamId: item.series.seriesId, type: "series", playlistId: playlist.id)
                        }
                    }
                }
                .padding()
                .animation(.snappy, value: favoriteSeries.map(\.series.seriesId))
            }
        }
    }

    /// `hasFavorites`: the type has favourites and the search matched none of them.
    @ViewBuilder
    private func emptyState(icon: String, title: String, hasFavorites: Bool) -> some View {
        if hasFavorites {
            CatalogEmptyView(.noSearchResults)
        } else {
            CatalogEmptyView(.noItems(title: title, systemImage: icon))
        }
    }
}

private extension View {
    /// Pins `bar` under the navigation bar as part of the bar area, so the content
    /// scrolls beneath it instead of being cut off at its lower edge.
    @ViewBuilder
    func topAccessoryBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            // The system scroll-edge effect of the navigation bar extends over the bar.
            safeAreaBar(edge: .top) { bar() }
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                // The empty edge set keeps the material on the bar's own strip; by
                // default it would run up behind the large title and the search field.
                bar().background(.bar, ignoresSafeAreaEdges: [])
            }
        }
    }

    /// Long-press menu of a favourites cell, with the lifted preview rounded like a card.
    func favoriteCellMenu<Items: View>(cornerRadius: CGFloat, @ViewBuilder _ items: () -> Items) -> some View {
        cardContextMenuShape(cornerRadius: cornerRadius)
            .contextMenu(menuItems: items)
    }
}

/// A channel of the favourites grid: the logo, the name centred under it and the
/// guide's now / next line when the playlist has a guide.
private struct FavoriteChannelCell: View {
    let stream: DBLiveStream
    let side: CGFloat

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CachedImage(
                url: stream.streamIcon.flatMap { URL(string: $0) },
                width: side,
                height: side,
                cornerRadius: BrowseMetrics.tileCornerRadius,
                iconName: "tv",
                loadProfile: .grid
            )
            Text(stream.name)
                .tileTitleStyle(width: side)
            EPGNowNextSlot(channelKey: EPGChannelKey.forXtream(stream), width: side)
        }
    }
}

/// A movie or series of the favourites grid. The poster is the source of the zoom
/// into the detail screen.
private struct FavoritePosterCell: View {
    let title: String
    let imageURL: String?
    let iconName: String
    let rating: String?
    let categoryName: String?
    let watchProgress: Double?
    let width: CGFloat
    let height: CGFloat
    let zoomId: String
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedImage(
                url: imageURL.flatMap { URL(string: $0) },
                width: width,
                height: height,
                cornerRadius: BrowseMetrics.posterCornerRadius,
                contentMode: .fill,
                iconName: iconName,
                loadProfile: .grid
            )
            .overlay(alignment: .topTrailing) {
                PosterRatingBadge(rating: rating)
                    .padding(6)
            }
            .overlay(alignment: .bottom) {
                if let watchProgress, watchProgress > 0 {
                    CardProgressBar(fraction: watchProgress)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
            .posterZoomSource(id: zoomId, in: zoomNamespace)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .posterTitleStyle(width: width)
                if let categoryName {
                    Text(categoryName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: width, alignment: .leading)
                }
            }
        }
    }
}
