import SwiftUI
import NukeUI
import GRDB

struct MovieDetailView: View {
    let playlist: Playlist
    let movie: DBVODStream

    @Environment(\.dismiss) private var dismiss
    @State private var currentMovie: DBVODStream
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingMovie: PlayableMovie?
    @State private var resumeHistory: DBWatchHistory?

    /// Fixed backdrop height. Hero content (poster + title + play) overlays
    /// the bottom of this strip, so the play button position is independent
    /// of the backdrop's intrinsic aspect ratio.
    private let backdropHeight: CGFloat = 720
    private let posterWidth: CGFloat = 280
    private let posterHeight: CGFloat = 420
    private let horizontalInset: CGFloat = 80

    init(playlist: Playlist, movie: DBVODStream) {
        self.playlist = playlist
        self.movie = movie
        _currentMovie = State(initialValue: movie)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                bodySection
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task {
            if !currentMovie.metadataLoaded {
                await fetchMovieInfo()
            }
            await loadResumeHistory()
        }
        .fullScreenCover(item: $playingMovie) { m in
            PlayerView(url: m.url, title: m.title,
                       historyTags: m.tags, resumeTimeMs: m.resumeTimeMs)
        }
        .onExitCommand { dismiss() }
    }

    // MARK: - Hero

    /// Backdrop + gradient fill a fixed strip at the top. Overlay sits at the
    /// bottom of that strip and can grow downward if needed, guaranteeing the
    /// play button stays on screen regardless of image aspect ratio.
    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            backdropLayer
                .frame(height: backdropHeight)
                .clipped()
                .overlay(heroGradient)

            heroOverlay
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, minHeight: backdropHeight, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var backdropLayer: some View {
        if let url = backdropURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    backdropPlaceholder
                }
            }
        } else {
            backdropPlaceholder
        }
    }

    private var backdropPlaceholder: some View {
        Rectangle().fill(Color(white: 0.08))
    }

    private var heroGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0.0),
                .init(color: .black.opacity(0.15), location: 0.25),
                .init(color: .black.opacity(0.45), location: 0.65),
                .init(color: .black.opacity(0.9), location: 0.92),
                .init(color: .black, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var heroOverlay: some View {
        HStack(alignment: .bottom, spacing: 48) {
            posterImage
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 28, y: 12)

            VStack(alignment: .leading, spacing: 18) {
                Text(currentMovie.name)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                metaRow

                if let err = errorMessage {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                HStack(spacing: 20) {
                    if resumeHistory != nil { resumeButton }
                    playButton
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: 1200, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = currentMovie.streamIcon.flatMap(URL.init(string:)) {
            LazyImage(url: url) { state in
                if let img = state.image {
                    img.resizable().scaledToFill()
                } else {
                    posterPlaceholder
                }
            }
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 72))
                    .foregroundStyle(.tertiary)
            }
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            if let r = ratingText { metaChip("★ " + r) }
            if let y = year { metaChip(y) }
            if let d = runtime { metaChip(d) }
            ForEach(genres.prefix(3), id: \.self) { metaChip($0) }
            if isLoading { ProgressView().tint(.white).padding(.leading, 8) }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.white.opacity(0.15), in: Capsule())
    }

    private var playButton: some View {
        Button {
            guard let url = XtreamURLBuilder.movie(playlist: playlist, stream: currentMovie) else { return }
            startPlayback(url: url, resumeMs: nil)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "play.fill")
                Text(L("detail.watch_now"))
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 48)
            .padding(.vertical, 18)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
    }

    private var resumeButton: some View {
        Button {
            guard let url = XtreamURLBuilder.movie(playlist: playlist, stream: currentMovie) else { return }
            startPlayback(url: url, resumeMs: resumeHistory?.lastTimeMs)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "play.circle.fill")
                Text(L("detail.resume"))
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 48)
            .padding(.vertical, 18)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.25))
        .foregroundStyle(.white)
    }

    // MARK: - Body

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 48) {
            if let plot = cleanPlot {
                plotSection(plot)
            }
            creditsSection
            Spacer(minLength: 40)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 48)
        .padding(.bottom, 80)
    }

    private func plotSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("movie.plot"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(text)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(6)
                .frame(maxWidth: 1400, alignment: .leading)
        }
    }

    @ViewBuilder
    private var creditsSection: some View {
        let dir = trimmed(currentMovie.director)
        let cast = trimmed(currentMovie.cast)
        VStack(alignment: .leading, spacing: 20) {
            if let dir { creditRow(L("movie.director"), dir) }
            if let cast { creditRow(L("movie.cast"), cast) }
        }
    }

    private func creditRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 200, alignment: .leading)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
        }
    }

    // MARK: - Derived data

    private var backdropURL: URL? {
        if let s = trimmed(currentMovie.backdropPath), let u = URL(string: s) { return u }
        return currentMovie.streamIcon.flatMap(URL.init(string:))
    }

    private var year: String? {
        trimmed(currentMovie.releaseDate)?.split(separator: "-").first.map(String.init)
    }

    private var runtime: String? { trimmed(currentMovie.duration) }
    private var ratingText: String? { trimmed(currentMovie.rating) }

    private var genres: [String] {
        guard let g = trimmed(currentMovie.genre) else { return [] }
        return g.split(whereSeparator: { ",/|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var cleanPlot: String? { trimmed(currentMovie.plot) }

    private func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Package history tags with an optional resume position and present the
    /// player. `resumeMs == nil` starts the movie from zero regardless of any
    /// saved progress.
    @MainActor
    private func startPlayback(url: URL, resumeMs: Int?) {
        let tags = WatchHistoryTags(
            playlistId: playlist.id,
            streamId: String(currentMovie.streamId),
            type: "vod",
            seriesId: nil,
            title: currentMovie.name,
            secondaryTitle: nil,
            imageURL: currentMovie.streamIcon,
            containerExtension: currentMovie.containerExtension
        )
        playingMovie = PlayableMovie(
            url: url,
            title: currentMovie.name,
            tags: tags,
            resumeTimeMs: resumeMs
        )
    }

    /// Look up any saved resume position for this VOD and expose it to the UI
    /// so the Resume button only appears when meaningful progress exists.
    @MainActor
    private func loadResumeHistory() async {
        let historyId = "\(playlist.id)_vod_\(currentMovie.streamId)"
        do {
            let existing = try await AppDatabase.shared.read { db in
                try DBWatchHistory.fetchOne(db, key: historyId)
            }
            if let existing, existing.durationMs > 0, existing.lastTimeMs > 5000 {
                resumeHistory = existing
            } else {
                resumeHistory = nil
            }
        } catch {
            resumeHistory = nil
        }
    }

    @MainActor
    private func fetchMovieInfo() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await XtreamAPIClient(playlist: playlist).getVODInfo(vodId: movie.streamId)
            var updated = currentMovie
            updated.metadataLoaded = true
            if let i = response.info {
                updated.cast = i.cast
                updated.director = i.director
                updated.genre = i.genre
                updated.plot = i.plot
                updated.releaseDate = i.releaseDate
                updated.rating = i.rating
                updated.backdropPath = i.backdropPath?.first
                updated.youtubeTrailer = i.youtubeTrailer
                updated.duration = i.duration
                updated.tmdbId = i.tmdbId
                updated.kinopoiskURL = i.kinopoiskURL
                if let r = i.rating, let d = Double(r) { updated.rating5Based = d / 2.0 }
            }
            try await AppDatabase.shared.write { db in try updated.update(db) }
            currentMovie = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlayableMovie: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    var tags: WatchHistoryTags? = nil
    var resumeTimeMs: Int? = nil
}
