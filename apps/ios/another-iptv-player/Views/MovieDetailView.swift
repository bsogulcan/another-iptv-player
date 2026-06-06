import SwiftUI
import Foundation
import Combine
import GRDB
import GRDBQuery

struct MovieDetailView: View {
    let playlist: Playlist
    var movie: DBVODStream
    /// Oynatıcıda önceki/sonraki film için kuyruk. Boşsa tek film olarak açılır.
    var queue: [DBVODStream] = []

    @Environment(\.posterMetrics) private var posterMetrics
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var enlargedImage: IdentifiableURL?
    @State private var showNavTitle: Bool = false
    @State private var pendingMovieDetail: DBVODStream?
    @EnvironmentObject private var playerOverlay: PlayerOverlayController
    @Query<VODByIDRequest> private var movieRecord: DBVODStream?
    @Query<IsFavoriteRequest> private var isFavorite: Bool
    @Query<WatchHistoryRequest> private var watchHistory: DBWatchHistory?

    init(playlist: Playlist, movie: DBVODStream, queue: [DBVODStream] = []) {
        self.playlist = playlist
        self.movie = movie
        self.queue = queue
        _movieRecord = Query(VODByIDRequest(streamId: movie.streamId, playlistId: playlist.id), in: \.appDatabase)
        _isFavorite = Query(IsFavoriteRequest(streamId: movie.streamId, playlistId: playlist.id, type: "vod"), in: \.appDatabase)
        _watchHistory = Query(WatchHistoryRequest(streamId: String(movie.streamId), playlistId: playlist.id, type: "vod"), in: \.appDatabase)
    }

    private var currentMovie: DBVODStream {
        movieRecord ?? movie
    }

    private var resumeMs: Int? {
        guard let h = watchHistory, h.lastTimeMs > 5000 else { return nil }
        return h.lastTimeMs
    }

    private var resumeProgress: Double? {
        guard let h = watchHistory, h.durationMs > 0 else { return nil }
        let p = Double(h.lastTimeMs) / Double(h.durationMs)
        return (p > 0.02 && p < 0.98) ? p : nil
    }

    private var trailerURL: URL? {
        guard let raw = currentMovie.youtubeTrailer?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        if raw.lowercased().hasPrefix("http") { return URL(string: raw) }
        return URL(string: "https://www.youtube.com/watch?v=\(raw)")
    }

    private var heroConfig: DetailHeroConfig {
        DetailHeroConfig(
            title: currentMovie.name,
            backdropURL: currentMovie.backdropPath.flatMap { URL(string: $0) },
            posterURL: currentMovie.streamIcon.flatMap { URL(string: $0) },
            year: DetailFormatting.year(from: currentMovie.releaseDate),
            runtime: currentMovie.duration?.trimmingCharacters(in: .whitespaces),
            rating10: currentMovie.rating5Based.map { $0 * 2 },
            ratingText: currentMovie.rating,
            posterIconName: "film",
            backdropIconName: "film"
        )
    }

    var body: some View {
        Group {
            if isLoading && !currentMovie.metadataLoaded {
                ProgressView(L("detail.loading_movie"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                contentScroll
            }
        }
        .navigationTitle(showNavTitle ? currentMovie.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .primary)
                }
            }
        }
        .fullScreenCover(item: $enlargedImage) { wrapper in
            FullscreenImageViewer(url: wrapper.url)
        }
        .navigationDestination(item: $pendingMovieDetail) { nextMovie in
            MovieDetailView(playlist: playlist, movie: nextMovie, queue: queue)
        }
        .task {
            if !currentMovie.metadataLoaded {
                await fetchMovieInfo()
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Text(L("common.error"))
                .font(.headline)
            Text(error)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(L("common.try_again")) {
                Task { await fetchMovieInfo() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHero(config: heroConfig, heroHeight: 380) { url in
                    enlargedImage = IdentifiableURL(url: url)
                }

                GenreChipRow(genres: DetailFormatting.genreList(currentMovie.genre))

                DetailActionBar(
                    primaryTitle: resumeMs != nil ? L("detail.resume") : L("detail.watch_now"),
                    primarySubtitle: resumeMs.map { DetailFormatting.formatMs($0) },
                    primaryIcon: resumeMs != nil ? "play.circle.fill" : "play.fill",
                    progress: resumeProgress,
                    onPrimary: { presentMoviePlayer(resume: true) },
                    restartTitle: resumeMs != nil ? L("detail.restart") : nil,
                    onRestart: resumeMs != nil ? { presentMoviePlayer(resume: false) } : nil,
                    trailerURL: trailerURL
                )

                if let remoteURL = PlaybackURLBuilder(playlist: playlist).movieURL(
                    streamId: currentMovie.streamId,
                    containerExtension: currentMovie.containerExtension
                ) {
                    DownloadButton(
                        id: DownloadManager.idFor(vod: playlist.id, streamId: currentMovie.streamId),
                        playlistId: playlist.id,
                        streamId: String(currentMovie.streamId),
                        type: "vod",
                        title: currentMovie.name,
                        secondaryTitle: currentMovie.genre,
                        imageURL: currentMovie.streamIcon,
                        remoteURL: remoteURL,
                        containerExtension: currentMovie.containerExtension
                    )
                    .padding(.horizontal, 16)
                    // Fragman satırıyla aynı sıkı aralık; VStack spacing 20'yi -10 ile nötrleyip
                    // DetailActionBar içindeki 10pt ritme hizalar.
                    .padding(.top, -10)
                }

                if let plot = currentMovie.plot?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
                    DetailPlotBlock(plot: plot)
                        .padding(.top, 4)
                }

                if let director = currentMovie.director?.trimmingCharacters(in: .whitespacesAndNewlines), !director.isEmpty {
                    DetailInfoTextBlock(label: L("movie.director"), value: director)
                }

                if let cast = currentMovie.cast?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty {
                    DetailInfoTextBlock(label: L("movie.cast"), value: cast, lineLimit: 3)
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y > 240
        } action: { _, newValue in
            if showNavTitle != newValue {
                withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = newValue }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func presentMoviePlayer(resume: Bool) {
        Task {
            let localURL = await DownloadManager.shared.localURL(
                forId: DownloadManager.idFor(vod: playlist.id, streamId: currentMovie.streamId)
            )
            await MainActor.run {
                presentMoviePlayer(resume: resume, localOverrideURL: localURL)
            }
        }
    }

    private func presentMoviePlayer(resume: Bool, localOverrideURL: URL?) {
        let r = resume ? watchHistory?.lastTimeMs : nil
        let originStreamId = currentMovie.streamId
        let navigateToDetail: (String, String) -> Void = { type, id in
            guard type == "vod" else {
                playerOverlay.dismiss()
                return
            }
            if let vId = Int(id), vId == originStreamId {
                playerOverlay.dismiss()
                return
            }
            Task {
                if let vId = Int(id),
                   let movie = try? await AppDatabase.shared.read({ db in
                    try DBVODStream.filter(Column("streamId") == vId && Column("playlistId") == playlist.id).fetchOne(db)
                }) {
                    await MainActor.run {
                        playerOverlay.dismiss()
                        pendingMovieDetail = movie
                    }
                } else {
                    await MainActor.run { playerOverlay.dismiss() }
                }
            }
        }
        // İndirilmiş dosya varsa queue'yu atla, tek film olarak local dosyadan oyna.
        if localOverrideURL == nil, !queue.isEmpty {
            playerOverlay.present(playlistId: playlist.id) {
                VODPlayerShell(
                    playlist: playlist,
                    queue: queue,
                    initialMovie: currentMovie,
                    initialResumeMs: r,
                    onNavigateToDetail: navigateToDetail
                )
            }
            return
        }
        let url: URL = {
            if let localOverrideURL { return localOverrideURL }
            return PlaybackURLBuilder(playlist: playlist).movieURL(
                streamId: currentMovie.streamId,
                containerExtension: currentMovie.containerExtension
            ) ?? URL(fileURLWithPath: "/dev/null")
        }()
        guard url.path != "/dev/null" else { return }
        let parts = [currentMovie.genre, currentMovie.releaseDate].compactMap { $0 }.filter { !$0.isEmpty }
        playerOverlay.present(skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
            PlayerView(
                url: url,
                title: currentMovie.name,
                subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                artworkURL: currentMovie.streamIcon.flatMap { URL(string: $0) },
                isLiveStream: false,
                playlistId: playlist.id,
                streamId: String(currentMovie.streamId),
                type: "vod",
                resumeTimeMs: r,
                containerExtension: currentMovie.containerExtension,
                onNavigateToDetail: navigateToDetail
            )
        }
    }

    private func fetchMovieInfo() async {
        isLoading = true
        errorMessage = nil
        let client = XtreamAPIClient(playlist: playlist)
        do {
            let response = try await client.getVODInfo(vodId: movie.streamId)
            
            try await AppDatabase.shared.write { db in
                var updatedMovie = currentMovie
                updatedMovie.metadataLoaded = true
                if let i = response.info {
                    updatedMovie.cast = i.cast
                    updatedMovie.director = i.director
                    updatedMovie.genre = i.genre
                    updatedMovie.plot = i.plot
                    updatedMovie.releaseDate = i.releaseDate
                    updatedMovie.rating = i.rating
                    updatedMovie.backdropPath = i.backdropPath?.first
                    updatedMovie.youtubeTrailer = i.youtubeTrailer
                    updatedMovie.duration = i.duration
                    updatedMovie.tmdbId = i.tmdbId
                    updatedMovie.kinopoiskURL = i.kinopoiskURL
                    
                    if let rString = i.rating, let rDouble = Double(rString) {
                         updatedMovie.rating5Based = rDouble / 2.0
                    }
                }
                try updatedMovie.update(db)
            }
            
            await MainActor.run { self.isLoading = false }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func toggleFavorite() {
        Task {
            do {
                try await AppDatabase.shared.write { db in
                    if isFavorite {
                        try DBFavorite
                            .filter(Column("streamId") == movie.streamId && Column("playlistId") == playlist.id && Column("type") == "vod")
                            .deleteAll(db)
                    } else {
                        let fav = DBFavorite(streamId: movie.streamId, playlistId: playlist.id, type: "vod")
                        try fav.insert(db)
                    }
                }
            } catch {
                print("Failed to toggle favorite: \(error)")
            }
        }
    }

}
