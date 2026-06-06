import SwiftUI
import NukeUI
import GRDB

struct SeriesDetailView: View {
    let playlist: Playlist
    let series: DBSeries

    @Environment(\.dismiss) private var dismiss
    @State private var currentSeries: DBSeries
    @State private var seasons: [DBSeason] = []
    @State private var episodesBySeasonId: [String: [DBEpisode]] = [:]
    @State private var selectedSeasonId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingEpisode: PlayableEpisode?
    @State private var resumeHistory: DBWatchHistory?

    private let backdropHeight: CGFloat = 720
    private let posterWidth: CGFloat = 280
    private let posterHeight: CGFloat = 420
    private let horizontalInset: CGFloat = 80

    init(playlist: Playlist, series: DBSeries) {
        self.playlist = playlist
        self.series = series
        _currentSeries = State(initialValue: series)
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
            await loadFromDatabase()
            if !currentSeries.seasonsLoaded {
                await fetchSeriesInfo()
            }
            await loadResumeHistory()
        }
        .fullScreenCover(item: $playingEpisode) { item in
            PlayerView(items: item.queue, startIndex: item.startIndex)
        }
        .onExitCommand { dismiss() }
    }

    // MARK: - Hero

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
                Text(currentSeries.name)
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
                    if resumeHistory != nil {
                        resumeButton
                    }
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
        if let url = currentSeries.cover.flatMap(URL.init(string:)) {
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
                Image(systemName: "play.tv")
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
            playFirstEpisode()
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
        .disabled(firstPlayableEpisode == nil)
    }

    private var resumeButton: some View {
        Button {
            resumeLastWatchedEpisode()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "play.circle.fill")
                Text(L("detail.resume"))
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 36)
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
            seasonsAndEpisodesSection
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
        let dir = trimmed(currentSeries.director)
        let cast = trimmed(currentSeries.cast)
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

    // MARK: - Seasons & Episodes

    @ViewBuilder
    private var seasonsAndEpisodesSection: some View {
        if seasons.isEmpty {
            Text(currentSeries.seasonsLoaded ? L("series.no_seasons_info") : L("series.loading_seasons"))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 32) {
                seasonBar
                episodesRow
            }
        }
    }

    private var seasonBar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("series.seasons"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(seasons) { season in
                        SeasonPill(
                            title: seasonTitle(season),
                            isSelected: season.id == selectedSeasonId
                        ) {
                            selectedSeasonId = season.id
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let sid = selectedSeasonId,
           let season = seasons.first(where: { $0.id == sid }) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(seasonTitle(season))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    if let count = season.episodeCount {
                        Text(L("detail.episode_count_plural", count))
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                if let overview = trimmed(season.overview) {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                        .frame(maxWidth: 1400, alignment: .leading)
                }

                let episodes = episodesBySeasonId[sid] ?? []
                if episodes.isEmpty {
                    Text(L("series.no_episodes_in_season"))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.vertical, 24)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(episodes) { ep in
                                EpisodeCard(
                                    episode: ep,
                                    seriesName: currentSeries.name,
                                    seriesCover: currentSeries.cover
                                ) {
                                    play(episode: ep)
                                }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
        }
    }

    // MARK: - Derived data

    private var firstPlayableEpisode: DBEpisode? {
        if let sid = selectedSeasonId, let ep = episodesBySeasonId[sid]?.first {
            return ep
        }
        for season in seasons {
            if let ep = episodesBySeasonId[season.id]?.first {
                return ep
            }
        }
        return nil
    }

    private var backdropURL: URL? {
        if let s = trimmed(currentSeries.backdropPath), let u = URL(string: s) { return u }
        return currentSeries.cover.flatMap(URL.init(string:))
    }

    private var year: String? {
        trimmed(currentSeries.releaseDate)?.split(separator: "-").first.map(String.init)
    }

    private var runtime: String? { trimmed(currentSeries.episodeRunTime) }
    private var ratingText: String? { trimmed(currentSeries.rating) }

    private var genres: [String] {
        guard let g = trimmed(currentSeries.genre) else { return [] }
        return g.split(whereSeparator: { ",/|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var cleanPlot: String? { trimmed(currentSeries.plot) }

    private func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private func seasonTitle(_ season: DBSeason) -> String {
        if let name = trimmed(season.name) { return name }
        return L("series.season_format", season.seasonNumber)
    }

    // MARK: - Playback

    private func playFirstEpisode() {
        guard let ep = firstPlayableEpisode else { return }
        play(episode: ep)
    }

    private func resumeLastWatchedEpisode() {
        guard let history = resumeHistory else { return }
        // The history row's `streamId` is the xtream episodeId or our fallback
        // DBEpisode.id. Walk loaded episodes to find the matching row.
        let target = episodesBySeasonId.values
            .flatMap { $0 }
            .first { ($0.episodeId ?? $0.id) == history.streamId }
        if let target {
            // Make sure the season containing the resumed episode is expanded in
            // the UI so the user can continue browsing from there.
            if let sid = seasons.first(where: { season in
                episodesBySeasonId[season.id]?.contains(where: { $0.id == target.id }) == true
            })?.id {
                selectedSeasonId = sid
            }
            play(episode: target)
        } else {
            // History references an episode we no longer have cached — fall
            // back to the first playable episode rather than doing nothing.
            playFirstEpisode()
        }
    }

    @MainActor
    private func loadResumeHistory() async {
        let seriesIdString = String(currentSeries.seriesId)
        do {
            let row = try await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(Column("playlistId") == playlist.id
                            && Column("type") == "series"
                            && Column("seriesId") == seriesIdString)
                    .order(Column("lastWatchedAt").desc)
                    .fetchOne(db)
            }
            // Only offer "resume" if there's meaningful progress — otherwise
            // the regular "Watch Now" button already starts from zero.
            if let row, row.durationMs > 0, row.lastTimeMs > 5000 {
                resumeHistory = row
            } else {
                resumeHistory = nil
            }
        } catch {
            resumeHistory = nil
        }
    }

    private func play(episode ep: DBEpisode) {
        // Build a queue of all episodes in the same season so the in-player
        // prev/next controls can walk through them without leaving the player.
        let seasonId = seasons.first(where: { season in
            episodesBySeasonId[season.id]?.contains(where: { $0.id == ep.id }) == true
        })?.id

        let sourceEpisodes: [DBEpisode] = seasonId.flatMap { episodesBySeasonId[$0] } ?? [ep]

        Task { await launchQueue(sourceEpisodes: sourceEpisodes, tapped: ep) }
    }

    @MainActor
    private func launchQueue(sourceEpisodes: [DBEpisode], tapped: DBEpisode) async {
        // Fetch existing resume positions for every episode in this season in
        // one read so prev/next inside the player keeps resuming correctly.
        let streamIds = sourceEpisodes.map { $0.episodeId ?? $0.id }
        var resumeMap: [String: Int] = [:]
        do {
            let rows = try await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(Column("playlistId") == playlist.id
                            && Column("type") == "series"
                            && streamIds.contains(Column("streamId")))
                    .fetchAll(db)
            }
            for row in rows where row.durationMs > 0 {
                resumeMap[row.streamId] = row.lastTimeMs
            }
        } catch {
            // Ignore — resume is optional.
        }

        let queue: [PlayableItem] = sourceEpisodes.compactMap { episode in
            guard let url = XtreamURLBuilder.episode(playlist: playlist, episode: episode) else { return nil }
            let sid = episode.episodeId ?? episode.id
            let tags = WatchHistoryTags(
                playlistId: playlist.id,
                streamId: sid,
                type: "series",
                seriesId: String(currentSeries.seriesId),
                title: episodeDisplayTitle(episode),
                secondaryTitle: currentSeries.name,
                imageURL: episode.cover ?? currentSeries.cover,
                containerExtension: episode.containerExtension
            )
            return PlayableItem(
                url: url,
                title: episodeDisplayTitle(episode),
                historyTags: tags,
                resumeTimeMs: resumeMap[sid]
            )
        }
        guard !queue.isEmpty else { return }

        let tappedId = tapped.episodeId ?? tapped.id
        let startIndex = queue.firstIndex(where: { $0.historyTags?.streamId == tappedId }) ?? 0

        playingEpisode = PlayableEpisode(queue: queue, startIndex: startIndex)
    }

    private func episodeDisplayTitle(_ ep: DBEpisode) -> String {
        let raw = ep.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = raw.isEmpty ? L("detail.episode_fallback") : raw
        if let num = ep.episodeNum {
            return "\(num). \(base)"
        }
        return base
    }

    // MARK: - Data loading

    @MainActor
    private func loadFromDatabase() async {
        let seriesId = currentSeries.seriesId
        let playlistId = playlist.id
        do {
            let (fetchedSeries, fetchedSeasons, episodesDict) = try await AppDatabase.shared.read { db -> (DBSeries?, [DBSeason], [String: [DBEpisode]]) in
                let series = try DBSeries
                    .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
                    .fetchOne(db)
                let seasons = try DBSeason
                    .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
                    .order(Column("seasonNumber"))
                    .fetchAll(db)
                var byId: [String: [DBEpisode]] = [:]
                for season in seasons {
                    let eps = try DBEpisode
                        .filter(Column("seasonId") == season.id)
                        .order(Column("episodeNum"))
                        .fetchAll(db)
                    byId[season.id] = eps
                }
                return (series, seasons, byId)
            }
            if let fetchedSeries { currentSeries = fetchedSeries }
            seasons = fetchedSeasons
            episodesBySeasonId = episodesDict
            if selectedSeasonId == nil || !fetchedSeasons.contains(where: { $0.id == selectedSeasonId }) {
                selectedSeasonId = fetchedSeasons.first(where: { !(episodesDict[$0.id]?.isEmpty ?? true) })?.id
                    ?? fetchedSeasons.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func fetchSeriesInfo() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let seriesId = currentSeries.seriesId
        let playlistId = playlist.id
        let baseSeries = currentSeries

        print("[SeriesDetail] fetchSeriesInfo START seriesId=\(seriesId) name=\(baseSeries.name)")

        do {
            let info = try await XtreamAPIClient(playlist: playlist).getSeriesInfo(seriesId: seriesId)

            let apiSeasonsCount = info.seasons?.count ?? -1
            let episodeKeys = info.episodes?.keys.sorted() ?? []
            let episodeCounts = info.episodes?.mapValues { $0.count } ?? [:]
            print("[SeriesDetail] API decoded: seasons.count=\(apiSeasonsCount) episodes.keys=\(episodeKeys) episodesPerSeason=\(episodeCounts) info=\(info.info != nil ? "present" : "nil")")

            var savedSeasonCount = 0
            var savedEpisodeCount = 0

            try await AppDatabase.shared.write { db in
                let apiSeasons = info.seasons ?? []
                let episodesDict = info.episodes ?? [:]

                var processedSeasons: [XtreamSeason] = apiSeasons
                let coveredNumbers = Set(apiSeasons.compactMap { $0.seasonNumber })
                let uncoveredKeys = episodesDict.keys
                    .compactMap { Int($0) }
                    .filter { !coveredNumbers.contains($0) }
                    .sorted()
                if !uncoveredKeys.isEmpty {
                    print("[SeriesDetail] Synthesizing virtual seasons for uncovered episode keys: \(uncoveredKeys)")
                }
                for seasonNum in uncoveredKeys {
                    if let virtualSeason = try? JSONDecoder().decode(
                        XtreamSeason.self,
                        from: """
                        {"season_number": \(seasonNum), "name": "Season \(seasonNum)"}
                        """.data(using: .utf8)!
                    ) {
                        processedSeasons.append(virtualSeason)
                    }
                }

                print("[SeriesDetail] processedSeasons.count=\(processedSeasons.count) (api=\(apiSeasons.count) + virtual=\(uncoveredKeys.count))")

                for apiSeason in processedSeasons {
                    let seasonNum = apiSeason.seasonNumber ?? 0
                    let seasonId = "\(seriesId)_\(seasonNum)"

                    let dbSeason = DBSeason(
                        id: seasonId,
                        seasonNumber: seasonNum,
                        name: apiSeason.name ?? "Season \(seasonNum)",
                        overview: apiSeason.overview,
                        cover: apiSeason.cover,
                        airDate: apiSeason.airDate,
                        episodeCount: apiSeason.episodeCount,
                        voteAverage: apiSeason.voteAverage,
                        seriesId: seriesId,
                        playlistId: playlistId
                    )
                    try dbSeason.save(db)
                    savedSeasonCount += 1

                    if let eps = episodesDict[String(seasonNum)] {
                        for ep in eps {
                            let dbEp = DBEpisode(
                                id: ep.id ?? UUID().uuidString,
                                episodeId: ep.id,
                                episodeNum: ep.episodeNum,
                                title: ep.title,
                                containerExtension: ep.containerExtension,
                                info: ep.info?.plot,
                                cover: ep.info?.movieImage ?? ep.info?.cover,
                                duration: ep.info?.duration,
                                rating: ep.info?.rating,
                                seasonId: seasonId
                            )
                            try dbEp.save(db)
                            savedEpisodeCount += 1
                        }
                    }
                }

                var updated = baseSeries
                updated.seasonsLoaded = true
                if let i = info.info {
                    updated.cast = i.cast
                    updated.director = i.director
                    updated.genre = i.genre
                    updated.plot = i.plot
                    updated.releaseDate = i.releaseDate
                    updated.rating = i.rating
                    updated.lastModified = i.lastModified
                    updated.rating5Based = i.rating5Based
                    updated.backdropPath = i.backdropPath?.first
                    updated.youtubeTrailer = i.youtubeTrailer
                    updated.episodeRunTime = i.episodeRunTime
                }
                try updated.update(db)
            }

            print("[SeriesDetail] DB write DONE seasons=\(savedSeasonCount) episodes=\(savedEpisodeCount)")

            await loadFromDatabase()

            print("[SeriesDetail] After loadFromDatabase: seasons.count=\(seasons.count) selectedSeasonId=\(selectedSeasonId ?? "nil") episodesDict.keys=\(episodesBySeasonId.keys.sorted())")
        } catch {
            print("[SeriesDetail] fetchSeriesInfo ERROR: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Episode Card

private struct EpisodeCard: View {
    let episode: DBEpisode
    let seriesName: String
    let seriesCover: String?
    let action: () -> Void

    private let cardWidth: CGFloat = 420
    private let thumbHeight: CGFloat = 236

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                thumbnail
                    .frame(width: cardWidth, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let info = trimmed(episode.info) {
                        Text(info)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let duration = trimmed(episode.duration) {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: cardWidth, alignment: .leading)
            }
        }
        .buttonStyle(.card)
    }

    private var title: String {
        let raw = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = raw.isEmpty ? L("detail.episode_fallback") : raw
        if let num = episode.episodeNum {
            return "\(num). \(base)"
        }
        return base
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = episode.cover.flatMap(URL.init(string:))
            ?? seriesCover.flatMap(URL.init(string:))
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tertiary)
            }
    }

    private func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - Season Pill

private struct SeasonPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(strokeColor, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var foreground: Color {
        if isFocused { return .black }
        return isSelected ? .white : .white.opacity(0.85)
    }

    private var background: Color {
        if isFocused { return .white }
        return isSelected ? .white.opacity(0.22) : .white.opacity(0.08)
    }

    private var strokeColor: Color {
        if isFocused { return .white }
        return isSelected ? .white.opacity(0.6) : .white.opacity(0.15)
    }
}

// MARK: - Playable Model

struct PlayableEpisode: Identifiable {
    let id = UUID()
    let queue: [PlayableItem]
    let startIndex: Int

    var url: URL { queue[startIndex].url }
    var title: String { queue[startIndex].title }
}
