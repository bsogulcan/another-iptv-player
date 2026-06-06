import SwiftUI
import GRDBQuery

struct FavoritesView: View {
    let playlist: Playlist

    @State private var selectedType: String
    @Environment(\.posterMetrics) private var posterMetrics
    @ObservedObject private var playerOverlay: PlayerOverlayController = .shared
    
    @Query<FavoriteLiveRequest> private var favoriteLive: [LiveStreamWithCategory]
    @Query<FavoriteVODRequest> private var favoriteVODs: [VODWithCategory]
    @Query<FavoriteSeriesRequest> private var favoriteSeries: [SeriesWithCategory]
    
    init(playlist: Playlist, initialType: String = "vod") {
        self.playlist = playlist
        self._selectedType = State(initialValue: initialType)
        _favoriteLive = Query(FavoriteLiveRequest(playlistId: playlist.id), in: \.appDatabase)
        _favoriteVODs = Query(FavoriteVODRequest(playlistId: playlist.id), in: \.appDatabase)
        _favoriteSeries = Query(FavoriteSeriesRequest(playlistId: playlist.id), in: \.appDatabase)
    }
    
    private var gridColumns: [GridItem] {
        if selectedType == "live" {
            return [GridItem(.adaptive(minimum: posterMetrics.liveGridIconSize), spacing: posterMetrics.gridSpacing)]
        }
        return [GridItem(.adaptive(minimum: posterMetrics.categoryGridPosterWidth), spacing: posterMetrics.gridSpacing)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker(L("favorites.type"), selection: $selectedType) {
                Text(L("dashboard.live")).tag("live")
                Text(L("dashboard.movies")).tag("vod")
                Text(L("dashboard.series")).tag("series")
            }
            .pickerStyle(.segmented)
            .padding()
            .background(.ultraThinMaterial)
            
            Group {
                if selectedType == "live" {
                    liveGrid
                } else if selectedType == "vod" {
                    vodGrid
                } else {
                    seriesGrid
                }
            }
        }
        .navigationTitle(L("favorites.title"))
        
    }

    private func presentFavoriteLive(stream: DBLiveStream, history: DBWatchHistory?) {
        guard let url = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: stream.streamId) else { return }
        playerOverlay.present(playlistId: playlist.id) {
            PlayerView(
                url: url,
                title: stream.name,
                subtitle: nil,
                artworkURL: stream.streamIcon.flatMap { URL(string: $0) },
                isLiveStream: true,
                playlistId: playlist.id,
                streamId: String(stream.streamId),
                type: "live",
                resumeTimeMs: history?.lastTimeMs
            )
        }
    }
    
    @ViewBuilder
    private var liveGrid: some View {
        if favoriteLive.isEmpty {
            emptyState(icon: "tv", message: L("favorites.empty.live"))
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: posterMetrics.gridRowSpacing) {
                    ForEach(favoriteLive) { item in
                        LiveStreamCard(
                            playlistId: playlist.id,
                            stream: item.stream,
                            width: posterMetrics.liveGridIconSize,
                            iconSize: posterMetrics.liveGridIconSize,
                            imageLoadProfile: .grid,
                            onStreamSelected: { stream, history in
                                presentFavoriteLive(stream: stream, history: history)
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private var vodGrid: some View {
        if favoriteVODs.isEmpty {
            emptyState(icon: "film", message: L("favorites.empty.movie"))
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: posterMetrics.gridRowSpacing) {
                    ForEach(favoriteVODs) { item in
                        NavigationLink(destination: MovieDetailView(playlist: playlist, movie: item.stream)) {
                            VODStreamCard(
                                playlistId: playlist.id,
                                stream: item.stream,
                                categoryName: item.categoryName,
                                posterWidth: posterMetrics.categoryGridPosterWidth,
                                posterHeight: posterMetrics.categoryGridPosterHeight,
                                imageLoadProfile: ImageLoadProfile.grid
                            )
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private var seriesGrid: some View {
        if favoriteSeries.isEmpty {
            emptyState(icon: "play.tv", message: L("favorites.empty.series"))
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: posterMetrics.gridRowSpacing) {
                    ForEach(favoriteSeries) { item in
                        NavigationLink(destination: SeriesDetailView(playlist: playlist, series: item.series)) {
                            SeriesCard(
                                playlistId: playlist.id,
                                stream: item.series,
                                categoryName: item.categoryName,
                                posterWidth: posterMetrics.categoryGridPosterWidth,
                                posterHeight: posterMetrics.categoryGridPosterHeight,
                                imageLoadProfile: ImageLoadProfile.grid
                            )
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }
}
