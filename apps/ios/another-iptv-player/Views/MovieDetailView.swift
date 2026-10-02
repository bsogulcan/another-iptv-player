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
    /// Message of the last metadata request that failed; nil while one runs.
    @State private var errorMessage: String?
    /// Counts metadata requests, so that one that was overtaken leaves the state alone.
    @State private var fetchGeneration = 0
    @State private var fetchPhase: FetchPhase = .pending
    @State private var enlargedImage: IdentifiableURL?
    @State private var showNavTitle: Bool = false
    @State private var pendingMovieDetail: DBVODStream?
    /// What the star shows between a tap and the database catching up with it.
    @State private var favoriteOverride: Bool?
    @State private var favoriteTapCount = 0
    @Environment(\.playerOverlayController) private var playerOverlay
    @Query<VODByIDRequest> private var movieRecord: DBVODStream?
    @Query<IsFavoriteRequest> private var isFavorite: Bool
    @Query<WatchHistoryRequest> private var watchHistory: DBWatchHistory?

    init(playlist: Playlist, movie: DBVODStream, queue: [DBVODStream] = []) {
        self.playlist = playlist
        self.movie = movie
        self.queue = queue
        // Three single-row lookups that decide the first frame: the stored metadata, the
        // star, and whether the button says Resume and carries a progress bar. Read
        // during subscription, they are in the first body instead of changing the
        // layout while the screen slides in.
        _movieRecord = Query(VODByIDRequest(streamId: movie.streamId, playlistId: playlist.id, immediate: true), in: \.appDatabase)
        _isFavorite = Query(IsFavoriteRequest(streamId: movie.streamId, playlistId: playlist.id, type: "vod", immediate: true), in: \.appDatabase)
        _watchHistory = Query(WatchHistoryRequest(streamId: String(movie.streamId), playlistId: playlist.id, type: "vod", immediate: true), in: \.appDatabase)
    }

    private var currentMovie: DBVODStream {
        movieRecord ?? movie
    }

    private var shownFavorite: Bool {
        favoriteOverride ?? isFavorite
    }

    /// Plot, genre, cast, backdrop and trailer come from a request of their own. The
    /// rest of the page, playback and download included, needs nothing from it, so its
    /// three states are drawn inside the page and never instead of it.
    enum MetadataState: Equatable {
        /// Everything there is to show is in the row: the metadata, or whatever the row
        /// holds when no request is coming for it.
        case loaded
        case loading
        case failed(String)
    }

    /// Where the metadata request of this screen stands. The row alone cannot say
    /// whether something is loading: a catalog refresh can rewrite it as "not loaded"
    /// while the screen is open, with no request running.
    enum FetchPhase: Equatable {
        /// The screen's task has not decided yet whether to ask.
        case pending
        case running
        /// The answer is written; the row's observation has not delivered it yet.
        case landing
        case idle
    }

    nonisolated static func metadataState(isLoaded: Bool, errorMessage: String?, phase: FetchPhase) -> MetadataState {
        if isLoaded { return .loaded }
        if let errorMessage { return .failed(errorMessage) }
        // Pending counts as loading, so the placeholder is in the first frame instead
        // of appearing one frame late; landing does too, or the placeholder would go
        // a moment before the plot it stands for arrives.
        return phase == .idle ? .loaded : .loading
    }

    private var metadataState: MetadataState {
        Self.metadataState(isLoaded: currentMovie.metadataLoaded, errorMessage: errorMessage, phase: fetchPhase)
    }

    private var resumeMs: Int? {
        // Bitmiş (≥%98) filmde "Devam et" son saniyelere ışınlıyordu; nil dönünce
        // birincil aksiyon baştan izlemeye düşer (resumeProgress ile tutarlı).
        // The rule itself lives in WatchResume so every entry point shares it.
        watchHistory?.resumePositionMs(as: .film)
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
        contentScroll
            // Always the name: it is what the back button of a screen pushed from here
            // and VoiceOver read. The bar shows the item below instead, which can fade.
            .navigationTitle(currentMovie.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26, *) {
                    // An item without a shared background, or the bar would carry an
                    // empty capsule while the title is faded out.
                    ToolbarItem(placement: .principal) { navigationTitleLabel }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { navigationTitleLabel }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleFavorite) {
                        Image(systemName: shownFavorite ? "star.fill" : "star")
                            .foregroundColor(shownFavorite ? .yellow : .primary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(shownFavorite ? L("favorites.remove") : L("favorites.add"))
                    .accessibilityIdentifier("detail.favorite")
                }
            }
            // Keyed on the tap, not on the star's value, which also changes when the
            // favourite is toggled somewhere else.
            .sensoryFeedback(.impact(weight: .light), trigger: favoriteTapCount)
            .onChange(of: isFavorite) { _, stored in
                if stored == favoriteOverride { favoriteOverride = nil }
            }
            .fullScreenCover(item: $enlargedImage) { wrapper in
                // The viewer opens on the poster that is already on screen and sharpens
                // it, instead of starting with a spinner on black.
                FullscreenImageViewer(
                    url: wrapper.url,
                    placeholderRequest: DetailHero.posterRequest(url: wrapper.url, metrics: posterMetrics)
                )
            }
            .onReceive(NetworkStatus.shared.$reconnectCount.dropFirst()) { _ in
                // One more try once the connection is back, only while the page shows the failure.
                if case .failed = metadataState {
                    Task { await fetchMovieInfo() }
                }
            }
            .navigationDestination(item: $pendingMovieDetail) { nextMovie in
                MovieDetailView(playlist: playlist, movie: nextMovie, queue: queue)
            }
            .task {
                // Decided from the stored row. The copy handed in by a shelf, a grid or a
                // play queue was taken when that list was built and still says "not
                // loaded" after an earlier visit, which would repeat the request on
                // every open.
                let streamId = movie.streamId
                let playlistId = playlist.id
                let stored = try? await AppDatabase.shared.read { db in
                    try DBVODStream
                        .filter(Column("streamId") == streamId && Column("playlistId") == playlistId)
                        .fetchOne(db)
                }
                guard !Task.isCancelled else { return }
                if !(stored?.metadataLoaded ?? movie.metadataLoaded) {
                    await fetchMovieInfo()
                }
            }
    }

    /// The title in the bar, shown once the hero's own title has scrolled away. A view,
    /// because the bar cannot cross-fade a change of its title string.
    private var navigationTitleLabel: some View {
        Text(currentMovie.name)
            .font(.headline)
            .lineLimit(1)
            .opacity(showNavTitle ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showNavTitle)
            .accessibilityHidden(true)
    }

    /// Stands in for the plot while the metadata loads, so the page does not grow by a
    /// whole block when it arrives.
    private var plotPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("movie.plot"))
                .font(.headline)
            Text(Self.plotPlaceholderText)
                .font(.subheadline)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("detail.loading_movie"))
    }

    /// Never shown as text: it only gives the redacted block four lines to draw.
    private static let plotPlaceholderText = String(repeating: "placeholder ", count: 30)

    private func metadataErrorRow(_ message: String) -> some View {
        InlineErrorRow(message: message) {
            Task { await fetchMovieInfo() }
        }
        .padding(.horizontal, 16)
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHero(config: heroConfig, heroHeight: 380) { url in
                    enlargedImage = IdentifiableURL(url: url)
                }

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

                if case .failed(let message) = metadataState {
                    metadataErrorRow(message)
                }

                // Below the actions: the genres arrive with the metadata, and above the
                // primary button they would push it down just as the thumb reaches it.
                GenreChipRow(genres: DetailFormatting.genreList(currentMovie.genre))

                if metadataState == .loading {
                    plotPlaceholder
                } else if let plot = currentMovie.plot?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
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
            // What the metadata adds fades in, and what sits below it slides, instead
            // of the page jumping when the answer arrives.
            .animation(.smooth(duration: 0.3), value: metadataState)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y > 240
        } action: { _, newValue in
            if showNavTitle != newValue { showNavTitle = newValue }
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
        // resumeMs sınırlı (bitmiş film → nil); ham lastTimeMs kullanmak bitmiş filmde
        // "İzle"ye basınca bile sona sıçratıyordu.
        let r = resume ? resumeMs : nil
        let originStreamId = currentMovie.streamId
        let navigateToDetail: (String, String) -> Void = { type, id in
            guard type == "vod" else {
                playerOverlay.injected?.dismiss()
                return
            }
            if let vId = Int(id), vId == originStreamId {
                playerOverlay.injected?.dismiss()
                return
            }
            Task {
                if let vId = Int(id),
                   let movie = try? await AppDatabase.shared.read({ db in
                    try DBVODStream.filter(Column("streamId") == vId && Column("playlistId") == playlist.id).fetchOne(db)
                }) {
                    await MainActor.run {
                        playerOverlay.injected?.dismiss()
                        pendingMovieDetail = movie
                    }
                } else {
                    await MainActor.run { playerOverlay.injected?.dismiss() }
                }
            }
        }
        // İndirilmiş dosya varsa queue'yu atla, tek film olarak local dosyadan oyna.
        if localOverrideURL == nil, !queue.isEmpty {
            playerOverlay.injected?.present(playlistId: playlist.id) {
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
        playerOverlay.injected?.present(skipDownloadCheck: localOverrideURL != nil, playlistId: playlist.id) {
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
        // The screen's task runs again each time the screen comes back, and Try Again
        // starts a request of its own, so two can overlap; the later one owns the state.
        fetchGeneration += 1
        let generation = fetchGeneration
        errorMessage = nil
        let client = XtreamAPIClient(playlist: playlist)
        do {
            let response = try await client.getVODInfo(vodId: movie.streamId)

            // @Query destekli currentMovie'yi MAIN actor'da kopyala: write closure'ı
            // GRDB'nin arka plan writer kuyruğunda koşar ve SwiftUI property-wrapper
            // state'ini oradan okumak veri yarışıdır.
            let base = await MainActor.run { currentMovie }
            // The page follows the stored row through its query. The catalog held in
            // memory is left alone: patching it copied the whole film list on the main
            // actor and re-rendered every screen that observes the store.
            try await AppDatabase.shared.write { db in
                var updatedMovie = base
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
        } catch {
            guard generation == fetchGeneration else { return }
            // Leaving the screen cuts the request off. That is not a failure to show:
            // the task asks again when the screen comes back.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            errorMessage = NetworkErrorText.describe(error)
        }
    }

    private func toggleFavorite() {
        let target = !shownFavorite
        let streamId = movie.streamId
        let playlistId = playlist.id
        favoriteTapCount += 1
        let tap = favoriteTapCount
        // Shown at once; the write and its observation follow. A busy writer (a catalog
        // refresh) would otherwise leave the star unchanged for as long as it runs.
        withAnimation(.snappy(duration: 0.25)) { favoriteOverride = target }
        Task {
            do {
                // The target state is written, not a toggle of whatever is stored: a
                // second tap that overtakes the first write must not insert the same
                // primary key twice.
                try await AppDatabase.shared.write { db in
                    if target {
                        try DBFavorite(streamId: streamId, playlistId: playlistId, type: "vod")
                            .insert(db, onConflict: .ignore)
                    } else {
                        try DBFavorite
                            .filter(Column("streamId") == streamId && Column("playlistId") == playlistId && Column("type") == "vod")
                            .deleteAll(db)
                    }
                }
                // The observation normally lands after this point and drops the
                // override itself. When the stored value already equals the target
                // nothing will be delivered, so it is dropped here.
                if tap == favoriteTapCount, isFavorite == target { favoriteOverride = nil }
            } catch {
                Log.error("MovieDetail", "Favourite write failed: \(error)")
                if tap == favoriteTapCount {
                    withAnimation(.snappy(duration: 0.25)) { favoriteOverride = nil }
                }
            }
        }
    }

}
