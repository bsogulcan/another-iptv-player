import GRDB
import GRDBQuery
import NukeUI
import SwiftUI

struct MacMediaDetail: View {
  @Environment(\.appDatabase) private var database
  @Environment(\.detailArtwork) private var artworkSelection
  @EnvironmentObject private var playback: DesktopPlayback
  let item: CatalogItem
  let source: Playlist
  let catalog: MacCatalogQuery?
  @State private var posterRevision = 0
  @State private var channel: DBM3UChannel?
  @State private var movie: DBVODStream?
  @State private var series: DBSeries?
  @ObservedObject private var hidden = HiddenCategoryStore.shared
  @State private var related: [CatalogItem] = []
  @State private var seasons: [DBSeason] = []
  @State private var selectedSeason: String?
  @State private var hasSeriesEpisodes = false
  @StateObject private var episodeObserver = SeasonEpisodesObserver()
  private var episodes: SeasonEpisodes { episodeObserver.season ?? SeasonEpisodes() }
  @State private var favorite = false
  @State private var refresh = 0
  @State private var error: String?
  @State private var metadataError: String?
  @State private var busy = false
  @State private var playTask: Task<Void, Never>?

  @Query<WatchHistoryRequest> private var filmHistory: DBWatchHistory?
  @Query<LatestSeriesWatchHistoryRequest> private var seriesHistory: DBWatchHistory?

  init(item: CatalogItem, source: Playlist, catalog: MacCatalogQuery? = nil) {
    self.catalog = catalog
    self.item = item
    self.source = source
    _favorite = State(initialValue: item.favorite)
    _filmHistory = Query(WatchHistoryRequest(streamId: item.streamKey, playlistId: source.id,
                                           type: "vod", immediate: true), in: \.appDatabase)
    _seriesHistory = Query(
      LatestSeriesWatchHistoryRequest(
        seriesId: item.streamKey, playlistId: source.id, immediate: true),
      in: \.appDatabase)
  }

  private var resumeEpisode: DBWatchHistory? {
    guard item.media == .series, let seriesHistory, seriesHistory.lastTimeMs > 5_000 else {
      return nil
    }
    return seriesHistory
  }

  private var displayMedia: MediaKind {
    guard let channel, let url = M3UParser.sanitizedURL(from: channel.url) else { return item.displayMedia }
    return M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle).isLive ? .live : .vod
  }

  private var filmResume: Int? {
    displayMedia == .vod ? filmHistory?.resumePositionMs(as: .film) : nil
  }

  private var progress: Double? {
    guard displayMedia != .live else { return nil }
    let history = item.media == .series ? seriesHistory : filmHistory
    guard let history, history.durationMs > 0 else { return nil }
    let fraction = Double(history.lastTimeMs) / Double(history.durationMs)
    return fraction > 0.02 && fraction < 0.98 ? fraction : nil
  }

  private var shownTitle: String { movie?.name ?? series?.name ?? channel?.name ?? item.title }

  private var posterURL: URL? {
    if let movie { return MacDetailArtwork.url(movie.streamIcon) }
    if let series { return MacDetailArtwork.url(series.cover) }
    if let channel { return MacDetailArtwork.url(channel.tvgLogo) }
    return MacDetailArtwork.url(item.artwork)
  }

  @ViewBuilder private var detailPoster: some View {
    let poster = CatalogArtwork(item: item, poster: displayMedia == .series || displayMedia == .vod, artworkURL: posterURL).frame(width: 152)
    if let posterURL {
      Button {
        artworkSelection.wrappedValue = MacDetailArtwork(url: posterURL, title: shownTitle, didClose: { posterRevision += 1 })
      } label: { poster.id(posterRevision) }
        .buttonStyle(.plain).accessibilityLabel(ML("enlarge_artwork"))
        .accessibilityIdentifier("detail.poster").help(ML("enlarge_artwork"))
    } else {
      poster
    }
  }

  private var detailRating: String? {
    if let five = movie?.rating5Based ?? series?.rating5Based, five > 0 { return String(five * 2) }
    if let movie { return movie.rating }
    if let series { return series.rating }
    return item.rating
  }

  @ViewBuilder private var primaryActions: some View {
    if item.media != .series || hasSeriesEpisodes || resumeEpisode != nil {
      Button(
        resumeEpisode != nil || filmResume != nil ? L("detail.resume") : L("movie.play"),
        systemImage: "play.fill"
      ) { play(nil) }.buttonStyle(
        .borderedProminent)
    }
    if filmResume != nil {
      Button(L("detail.restart"), systemImage: "arrow.counterclockwise") { play(nil, restart: true) }
    }
  }

  @ViewBuilder private var libraryActions: some View {
    Button(
      ML(favorite ? "unfavorite" : "favorite"),
      systemImage: favorite ? "heart.fill" : "heart"
    ) { toggleFavorite() }
    if displayMedia == .vod { downloadButton(nil) }
  }

  private var relatedQuery: MacCatalogQuery? {
    guard let group = movie?.categoryId ?? series?.categoryId, !group.isEmpty else { return nil }
    let kind = item.media
    return MacCatalogQuery(playlistID: source.id, kinds: [kind], selectedGroup: group,
      hidden: [kind: hidden.hiddenIds(playlistId: source.id, type: kind.rawValue)],
      limit: 20, excludedStreamKey: item.streamKey)
  }

  private func relatedShelf(_ query: MacCatalogQuery) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L("detail.more_like_this")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          ForEach(related) { other in
            NavigationLink(value: CatalogDestination.item(other, query)) {
              VStack(alignment: .leading, spacing: 5) {
                CatalogArtwork(item: other, poster: true)
                  .overlay(alignment: .topTrailing) {
                    PosterRatingBadge(rating: other.rating).padding(5)
                  }
                Text(verbatim: other.title).font(.headline).lineLimit(2)
              }.frame(width: 116).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(other.title)
              .accessibilityValue(BrowseAccessibility.ratingLabel(ContentRating.displayText(other.rating)) ?? "")
          }
        }.padding(.bottom, 8)
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let backdrop = MacDetailArtwork.url(movie?.backdropPath ?? series?.backdropPath) {
          LazyImage(url: backdrop) { state in
            if state.error == nil {
              Rectangle().fill(.quaternary).frame(height: 190)
                .overlay { state.image?.resizable().scaledToFill() }
                .clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
            }
          }
        }
        HStack(alignment: .bottom, spacing: 24) {
          detailPoster
          VStack(alignment: .leading, spacing: 10) {
            Text(displayMedia.title).font(.subheadline)
              .foregroundStyle(.secondary)
            Text(verbatim: shownTitle).font(.system(.largeTitle, design: .serif).weight(.semibold))
              .textSelection(.enabled).accessibilityAddTraits(.isHeader)
            let metadata = [
              DetailFormatting.year(from: movie?.releaseDate ?? series?.releaseDate),
              movie?.duration ?? DetailFormatting.seriesRuntime(series?.episodeRunTime), channel.map { $0.groupTitle ?? "" } ?? item.category,
            ]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
            if !metadata.isEmpty { Text(verbatim: metadata).foregroundStyle(.secondary) }
            RatingLabel(rating: detailRating, style: .standard)
            let genres = DetailFormatting.genreList(movie?.genre ?? series?.genre)
            if !genres.isEmpty {
              Text(verbatim: genres.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
              HStack { primaryActions; libraryActions }
              VStack(alignment: .leading, spacing: 8) {
                HStack { primaryActions }
                HStack { libraryActions }
              }
            }.controlSize(.large)
            if let progress {
              ProgressView(value: progress)
                .accessibilityLabel(L("player.a11y.playback_position"))
                .accessibilityValue(DetailFormatting.percent(progress))
            }
            if let filmResume {
              Text(DetailFormatting.formatMs(filmResume)).font(.subheadline).monospacedDigit()
                .foregroundStyle(.secondary)
            }
            if let resumeEpisode {
              Text(
                [resumeEpisode.title, DetailFormatting.formatMs(resumeEpisode.lastTimeMs)]
                  .filter { !$0.isEmpty }.joined(separator: " · ")
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
          }
        }
        if busy {
          ProgressView(L("common.loading")).controlSize(.small)
        } else if let metadataError {
          HStack {
            Label(metadataError, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button(L("common.try_again")) { refresh += 1 }
          }
        }
        if let plot = (movie?.plot ?? series?.plot)?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
          Divider()
          Text(L("movie.plot")).font(.title2.bold())
          Text(verbatim: plot).textSelection(.enabled).lineSpacing(3)
        }
        if let director = (movie?.director ?? series?.director)?.trimmingCharacters(in: .whitespacesAndNewlines), !director.isEmpty {
          LabeledContent(L("movie.director"), value: director).textSelection(.enabled)
        }
        if let cast = (movie?.cast ?? series?.cast)?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty {
          LabeledContent(L("movie.cast"), value: cast).textSelection(.enabled)
        }
        if let trailer = movie?.youtubeTrailer ?? series?.youtubeTrailer, !trailer.isEmpty,
          let url = trailerURL(trailer)
        {
          Link(L("movie.trailer"), destination: url)
        }
        if item.media == .series, let season = seasons.first(where: { $0.id == selectedSeason }) {
          Divider()
          HStack(alignment: .firstTextBaseline) {
            if seasons.count == 1 {
              Text(season.name ?? L("series.season_format", season.seasonNumber))
                .font(.title2.bold()).accessibilityAddTraits(.isHeader)
            } else {
              Picker(L("series.seasons"), selection: Binding(get: { season.id }, set: { selectedSeason = $0 })) {
                ForEach(seasons) { row in
                  Text(row.name ?? L("series.season_format", row.seasonNumber)).tag(row.id)
                }
              }.fixedSize().accessibilityIdentifier("series.seasonPicker")
            }
            Spacer()
            if let count = season.episodeCount {
              Text(L("detail.episode_count_plural", count)).font(.subheadline).foregroundStyle(.secondary)
            }
          }
          if let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
            Text(verbatim: overview).foregroundStyle(.secondary).textSelection(.enabled)
          }
          if episodeObserver.season == nil {
            ProgressView(L("common.loading")).controlSize(.small)
          } else if episodes.episodes.isEmpty {
            Text(L("series.no_episodes_in_season")).font(.subheadline).foregroundStyle(.secondary)
          }
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(episodes.episodes) { episode in
              VStack(spacing: 0) {
                HStack(spacing: 12) {
                  Button {
                    play(episode)
                  } label: {
                    episodeLabel(episode)
                  }.buttonStyle(.plain)
                  downloadButton(episode)
                }.padding(.vertical, 8)
                Divider()
              }
            }
          }
        } else if item.media == .series, seasons.isEmpty, series?.seasonsLoaded == true, !busy, metadataError == nil {
          Text(L("series.no_seasons_info")).font(.subheadline).foregroundStyle(.secondary)
        }
        if let relatedQuery, !related.isEmpty { relatedShelf(relatedQuery) }

      }.padding(26).frame(maxWidth: 920, alignment: .leading).frame(
        maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(shownTitle)
    .macError($error)
    .task(id: refresh) { await loadDetails() }
    .onReceive(NetworkStatus.shared.$reconnectCount.dropFirst()) { _ in
      if metadataError != nil && !busy { refresh += 1 }
    }
    .task(id: item.id) {
      do {
        for try await stored in ValueObservation.tracking({ try item.isFavorite(in: $0) }).values(
          in: database.reader)
        {
          favorite = stored
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .task(id: item.id) {
      guard item.media == .m3u else { return }
      let pid = source.id, key = item.streamKey
      do {
        let observation = ValueObservation.tracking { db in
          try DBM3UChannel.filter(Column("playlistId") == pid && Column("id") == key).fetchOne(db)
        }
        for try await row in observation.removeDuplicates().values(in: database.reader) {
          try Task.checkCancellation()
          channel = row
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .task(id: item.id) {
      guard item.media == .vod, let number = Int(item.streamKey) else { return }
      let pid = source.id
      do {
        let observation = ValueObservation.tracking { db in
          try DBVODStream.filter(Column("playlistId") == pid && Column("streamId") == number).fetchOne(db)
        }
        for try await row in observation.values(in: database.reader) {
          try Task.checkCancellation()
          movie = row
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .task(id: item.id) {
      if item.media == .series {
        do { try await observeSeries() }
        catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
      }
    }
    .task(id: relatedQuery) {
      related = []
      guard let query = relatedQuery else { return }
      do {
        for try await results in ValueObservation.tracking({ try query.fetch($0) }).values(in: database.reader) {
          try Task.checkCancellation()
          related = results
        }
      } catch { if !Task.isCancelled { Log.error("Related", NetworkErrorText.describe(error)) } }
    }
    .task(id: selectedSeason) {
      episodeObserver.load(seasonId: selectedSeason, playlistId: source.id, db: database)
    }
    .onDisappear { playTask?.cancel() }
  }
  private func episodeLabel(_ episode: DBEpisode) -> some View {
    let history = episodes.history[episode.episodeId ?? episode.id]
    let fraction = history.flatMap { $0.durationMs > 0 ? Double($0.lastTimeMs) / Double($0.durationMs) : nil }
    return HStack(spacing: 12) {
      ZStack {
        Rectangle().fill(.quaternary)
        LazyImage(url: episode.cover.flatMap(URL.init(string:))) { state in
          if let image = state.image {
            image.resizable().scaledToFill()
          } else {
            Image(systemName: "play.rectangle").foregroundStyle(.secondary)
          }
        }
      }.frame(width: 96, height: 54)
        .overlay(alignment: .bottom) {
          if let fraction, fraction > 0, fraction < 0.95 {
            ProgressView(value: fraction).tint(.accentColor).padding(.horizontal, 4)
              .padding(.vertical, 2).background(.regularMaterial)
          }
        }
        .overlay(alignment: .topTrailing) {
          if let fraction, fraction >= 0.95 {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor)
              .padding(3)
          }
        }
        .clipShape(.rect(cornerRadius: 5)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(SeriesDetailData.episodeTitle(episode)).font(.headline)
        HStack(spacing: 10) {
          if let duration = episode.duration?.trimmingCharacters(in: .whitespacesAndNewlines), !duration.isEmpty {
            Label(duration, systemImage: "clock")
          }
          RatingLabel(rating: episode.rating)
          if let history, history.durationMs > 0 {
            if let fraction, fraction >= 0.95 {
              Label(L("detail.watched"), systemImage: "checkmark.circle")
            } else {
              let time = DetailFormatting.formatMs(history.durationMs - history.lastTimeMs)
              Text(L("detail.remaining_format", time))
            }
          }
        }.font(.caption).foregroundStyle(.secondary)
        if let plot = episode.info?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty {
          Text(verbatim: plot).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
  }

  private func loadDetails() async {
    busy = true
    metadataError = nil
    let generation = refresh
    defer { if refresh == generation { busy = false } }
    let pid = source.id
    let number = Int(item.streamKey) ?? 0
    do {
      let client = XtreamAPIClient(playlist: source)
      switch item.media {
      case .vod:
        let cached = try await database.read { db in
          try DBVODStream.filter(Column("playlistId") == pid && Column("streamId") == number)
            .fetchOne(db)
        }
        if let cached, !cached.metadataLoaded {
          let info = try await client.getVODInfo(vodId: number)
          try Task.checkCancellation()
          _ = try await database.write { db in
            try DetailMetadata.storeMovie(info, streamId: number, playlistId: pid, db: db)
          }
        }
      case .series:
        let cached = try await database.read { db in
          try DBSeries.filter(Column("playlistId") == pid && Column("seriesId") == number).fetchOne(db)
        }
        if let cached, !cached.seasonsLoaded {
          let info = try await client.getSeriesInfo(seriesId: number)
          try Task.checkCancellation()
          _ = try await database.write { db in
            try SeriesDetailData.store(info, seriesId: number, playlistId: pid, db: db)
          }
        }
      default: break
      }
    } catch {
      guard !Task.isCancelled, generation == refresh else { return }
      metadataError = Self.metadataFailureMessage(error)
    }
  }

  static func metadataFailureMessage(_ error: Error) -> String? {
    let cause: Error
    if case XtreamError.networkError(let underlying) = error { cause = underlying }
    else { cause = error }
    guard !(cause is CancellationError), (cause as? URLError)?.code != .cancelled else { return nil }
    return NetworkErrorText.describe(error)
  }

  private func observeSeries() async throws {
    let pid = source.id
    guard let number = Int(item.streamKey) else { return }
    let observation = ValueObservation.tracking { db in
      let filter = Column("playlistId") == pid && Column("seriesId") == number
      return (try DBSeries.filter(filter).fetchOne(db),
              try DBSeason.filter(filter).order(Column("seasonNumber")).fetchAll(db),
              try SeriesDetailData.seasonAnchor(seriesId: number, playlistId: pid, db: db))
    }
    var previouslyWatched: String?
    for try await (record, list, anchor) in observation.values(in: database.reader) {
      try Task.checkCancellation()
      series = record
      hasSeriesEpisodes = anchor.hasEpisodes
      if !list.contains(where: { $0.id == selectedSeason }) {
        selectedSeason = list.contains(where: { $0.id == anchor.initialSeasonId }) ? anchor.initialSeasonId : list.first?.id
      } else if let previouslyWatched, selectedSeason == previouslyWatched,
                let watched = anchor.watchedSeasonId, watched != previouslyWatched {
        selectedSeason = watched
      }
      if let watched = anchor.watchedSeasonId { previouslyWatched = watched }
      seasons = list
    }
  }

  private func media(for episode: DBEpisode?) async throws -> MediaSelection {
    if let episode { return try .episode(episode, series: item, source: source, currentSeries: series) }
    if let history = resumeEpisode {
      let episode = try await database.read {
        try SeriesDetailData.episode(streamId: history.streamId, playlistId: source.id, db: $0)
      }
      var selection: MediaSelection
      if let episode {
        selection = try .episode(episode, series: item, source: source, currentSeries: series)
      } else {
        selection = try await .history(history, source: source, database: database)
        if let series {
          selection.secondaryTitle = series.name
          selection.artwork = selection.artwork ?? series.cover
        }
      }
      selection.startPosition = .latestEpisode
      return selection
    }
    if item.media == .series {
      let first = try await database.read {
        try SeriesDetailData.firstEpisode(
          seriesId: Int(item.streamKey) ?? 0, playlistId: source.id, db: $0)
      }
      guard let first else { throw CocoaError(.fileNoSuchFile) }
      return try .episode(first, series: item, source: source, currentSeries: series)
    }
    return try await MediaSelection.resolve(item, in: source, database: database)
  }
  private func play(_ episode: DBEpisode?, restart: Bool = false) {
    playTask?.cancel()
    playTask = Task {
      do {
        var target = try await media(for: episode)
        if restart { target.startPosition = .beginning }
        try Task.checkCancellation()
        playback.start(target, catalog: catalog)
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
  }
  private func toggleFavorite() {
    let desired = !favorite
    Task {
      do {
        try await item.setFavorite(desired, in: database)
      } catch { self.error = NetworkErrorText.describe(error) }
    }
  }
  private func downloadButton(_ episode: DBEpisode?) -> some View {
    let id: String
    if let episode {
      id = DownloadManager.idFor(episode: source.id, episodeId: episode.episodeId ?? episode.id)
    } else if item.media == .m3u {
      id = DownloadManager.idFor(m3uChannel: source.id, channelId: item.streamKey)
    } else {
      id = DownloadManager.idFor(vod: source.id, streamId: Int(item.streamKey) ?? 0)
    }
    return MacDownloadAction(id: id, play: { play(episode) }) {
      Task {
        do {
          let target = try await media(for: episode)
          await target.enqueueDownload(
            seasonNumber: seasons.first { $0.id == episode?.seasonId }?.seasonNumber,
            episodeNumber: episode?.episodeNum)
        } catch { self.error = NetworkErrorText.describe(error) }
      }
    }
  }
  private func trailerURL(_ value: String) -> URL? {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    if let url = URL(string: raw), let scheme = url.scheme?.lowercased() {
      return ["https", "http"].contains(scheme) ? url : nil
    }
    var components = URLComponents(string: "https://www.youtube.com/watch")
    components?.queryItems = [URLQueryItem(name: "v", value: raw)]
    return components?.url
  }
}

struct MacDownloadAction: View {
  let id: String
  let play: () -> Void
  let enqueue: () -> Void
  @ObservedObject private var manager = DownloadManager.shared
  @Query<DownloadedItemByIDRequest> private var item: DBDownloadedItem?
  @State private var confirmingDelete = false

  init(id: String, play: @escaping () -> Void, enqueue: @escaping () -> Void) {
    self.id = id
    self.play = play
    self.enqueue = enqueue
    _item = Query(DownloadedItemByIDRequest(id: id), in: \.appDatabase)
  }

  var body: some View {
    Group {
      switch item?.downloadStatus {
      case .completed:
        Menu {
          Button(L("movie.play"), systemImage: "play.fill", action: play)
          Button(L("download.delete"), systemImage: "trash", role: .destructive) {
            confirmingDelete = true
          }
        } label: {
          Label(L("download.completed"), systemImage: "checkmark.circle")
        }.help(L("download.completed")).accessibilityLabel(L("download.completed"))
      case .queued, .downloading:
        Button {
          manager.cancel(id: id)
        } label: {
          if item?.downloadStatus == .downloading {
            let progress = manager.progress[id]?.fraction ?? 0
            Label(L("download.downloading_format", Int(progress * 100)), systemImage: "stop.circle")
          } else {
            Label(L("download.status.queued"), systemImage: "clock")
          }
        }
        .help(L("download.cancel"))
        .accessibilityLabel(L("download.cancel"))
      case .failed:
        Button(action: enqueue) {
          Label(L("download.retry"), systemImage: "arrow.clockwise")
        }.help(item?.errorMessage ?? L("download.retry"))
      case nil:
        Button(action: enqueue) {
          Label(L("download.action"), systemImage: "arrow.down.circle")
        }.help(L("download.action"))
      }
    }
    .labelStyle(.titleAndIcon)
    .confirmationDialog(L("download.delete"), isPresented: $confirmingDelete) {
      Button(L("download.delete"), role: .destructive) {
        Task { await manager.delete(id: id) }
      }
      Button(L("common.cancel"), role: .cancel) {}
    } message: {
      Text(verbatim: item?.title ?? "")
    }
  }
}
