import Combine
import Foundation
import GRDB

nonisolated struct SeasonEpisodes: Equatable, Sendable {
  var episodes: [DBEpisode] = []
  /// Keyed by the id playback uses for an episode (`episodeId ?? id`).
  var history: [String: DBWatchHistory] = [:]
}

/// Where the season selection of a series page stands.
nonisolated struct SeriesSeasonAnchor: Equatable, Sendable {
  /// Season of the most recently watched episode, when that episode is still stored.
  var watchedSeasonId: String?
  /// The season a page without a selection opens on.
  var initialSeasonId: String?
  var hasEpisodes = false
}

/// The database side of the series page and the rules its buttons share. The `db`
/// functions run inside GRDB's read and write closures, off the main actor.
enum SeriesDetailData {

  // MARK: Seasons request

  /// The stored `seasonsLoaded` flag; nil when the series has no row (any more).
  nonisolated static func seasonsLoaded(seriesId: Int, playlistId: UUID, db: Database) throws
    -> Bool?
  {
    try storedSeries(seriesId: seriesId, playlistId: playlistId, db: db)?.seasonsLoaded
  }

  /// Stores the answer of `get_series_info` and returns the number of seasons written,
  /// or nil, with nothing written, when the series row no longer exists.
  ///
  /// The row is fetched inside the transaction and only the fields of the answer are
  /// changed on it. Writing back the copy a screen was opened with would undo whatever
  /// a catalog refresh stored in between, and wipe the details of an earlier answer when
  /// this one comes without an info block.
  nonisolated static func store(
    _ info: XtreamSeriesInfoResponse, seriesId: Int, playlistId: UUID, db: Database
  ) throws -> Int? {
    guard var row = try storedSeries(seriesId: seriesId, playlistId: playlistId, db: db) else {
      return nil
    }

    let episodesBySeason = info.episodesBySeasonNumber
    let resolvedSeasons = info.resolvedSeasons
    for (seasonNum, apiSeason) in resolvedSeasons {
      let seasonId = DBSeason.scopedId(
        playlistId: playlistId, seriesId: seriesId, seasonNumber: seasonNum)
      let eps = episodesBySeason[seasonNum] ?? []

      let dbSeason = DBSeason(
        id: seasonId,
        seasonNumber: seasonNum,
        name: apiSeason?.name,
        overview: apiSeason?.overview,
        cover: apiSeason?.cover,
        airDate: apiSeason?.airDate,
        episodeCount: eps.isEmpty ? apiSeason?.episodeCount : eps.count,
        voteAverage: apiSeason?.voteAverage,
        seriesId: seriesId,
        playlistId: playlistId
      )
      try dbSeason.save(db)

      for ep in eps {
        let dbEp = DBEpisode(
          id: DBEpisode.scopedId(playlistId: playlistId, panelEpisodeId: ep.id),
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
      }
    }

    row = DetailMetadata.series(row, response: info)
    row.seasonsLoaded = true
    try row.update(db)
    return resolvedSeasons.count
  }

  nonisolated private static func storedSeries(seriesId: Int, playlistId: UUID, db: Database) throws
    -> DBSeries?
  {
    try DBSeries
      .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
      .fetchOne(db)
  }

  // MARK: Episodes

  /// The episode a history row of this playlist belongs to.
  ///
  /// Matched on the row id, which carries the playlist: the panel's own episode id
  /// repeats across playlists. The second term covers episodes the panel sent without
  /// an id; their history is filed under the row id itself.
  nonisolated static func episode(streamId: String, playlistId: UUID, db: Database) throws
    -> DBEpisode?
  {
    let scopedID = DBEpisode.scopedId(playlistId: playlistId, panelEpisodeId: streamId)
    return try DBEpisode.fetchOne(db, sql: """
      SELECT episode.* FROM episode JOIN season ON season.id = episode.seasonId
      WHERE season.playlistId = ? AND episode.id IN (?, ?)
      ORDER BY CASE WHEN episode.id = ? THEN 0 ELSE 1 END
      LIMIT 1
      """, arguments: [playlistId, scopedID, streamId, scopedID])
  }

  /// The episode "Watch" starts with: the first one in play order. Seasons a panel
  /// declares without episodes are passed over.
  ///
  /// The order is that of `SeriesPlaybackOrdering.orderedEpisodes`, which the player
  /// steps through (seasons by number, episodes by number within a season). Only the first matching episode is loaded.
  nonisolated static func firstEpisode(seriesId: Int, playlistId: UUID, db: Database) throws
    -> DBEpisode?
  {
    try SeriesPlaybackOrdering.orderedEpisodes(seriesId: seriesId, playlistId: playlistId, firstOnly: true, db: db).first
  }

  /// The series' season ids, lowest season number first.
  nonisolated private static func seasonIds(seriesId: Int, playlistId: UUID, db: Database) throws
    -> [String]
  {
    try String.fetchAll(
      db,
      DBSeason
        .select(Column("id"))
        .filter(Column("seriesId") == seriesId && Column("playlistId") == playlistId)
        .order(Column("seasonNumber").asc)
    )
  }

  /// The episodes of one season in list order, with the history rows of exactly those episodes.
  nonisolated static func seasonEpisodes(seasonId: String, playlistId: UUID, db: Database) throws
    -> SeasonEpisodes
  {
    guard let season = try DBSeason.filter(Column("id") == seasonId && Column("playlistId") == playlistId).fetchOne(db)
    else { return SeasonEpisodes() }
    let episodes = try SeriesPlaybackOrdering.orderedEpisodes(seriesId: season.seriesId, playlistId: playlistId,
      seasonId: seasonId, db: db)
    guard !episodes.isEmpty else { return SeasonEpisodes() }

    // By episode id rather than by the history's series id, which older rows lack.
    let streamIds = episodes.map { $0.episodeId ?? $0.id }
    let rows =
      try DBWatchHistory
      .filter(
        Column("playlistId") == playlistId
          && Column("type") == "series"
          && streamIds.contains(Column("streamId"))
      )
      .fetchAll(db)
    var history: [String: DBWatchHistory] = [:]
    for row in rows { history[row.streamId] = row }
    return SeasonEpisodes(episodes: episodes, history: history)
  }

  // MARK: Season selection

  /// One rule for the season a page opens on: the season of the most recently watched
  /// episode, else the season "Watch" would start in, else the first season. The history
  /// row is read here, in the same snapshot as its episode and the seasons.
  nonisolated static func seasonAnchor(seriesId: Int, playlistId: UUID, db: Database) throws
    -> SeriesSeasonAnchor
  {
    let seasonIds = try seasonIds(seriesId: seriesId, playlistId: playlistId, db: db)
    guard let firstSeasonId = seasonIds.first else { return SeriesSeasonAnchor() }

    let latest =
      try DBWatchHistory
      .filter(Column("seriesId") == String(seriesId) && Column("playlistId") == playlistId)
      .order(Column("lastWatchedAt").desc)
      .fetchOne(db)
    if let latest,
      let watched = try episode(streamId: latest.streamId, playlistId: playlistId, db: db),
      seasonIds.contains(watched.seasonId)
    {
      return SeriesSeasonAnchor(
        watchedSeasonId: watched.seasonId, initialSeasonId: watched.seasonId, hasEpisodes: true)
    }

    let first = try firstEpisode(seriesId: seriesId, playlistId: playlistId, db: db)
    return SeriesSeasonAnchor(
      watchedSeasonId: nil, initialSeasonId: first?.seasonId ?? firstSeasonId, hasEpisodes: first != nil)
  }

  // MARK: Favourite

  /// Sets the favourite to `isFavorite` whatever is stored: two quick taps are two
  /// writes of a known value each, not two toggles reading the same old state.
  nonisolated static func setFavorite(
    _ isFavorite: Bool, seriesId: Int, playlistId: UUID, db: Database
  ) throws {
    if isFavorite {
      try DBFavorite(streamId: seriesId, playlistId: playlistId, type: "series")
        .insert(db, onConflict: .ignore)
    } else {
      try DBFavorite
        .filter(
          Column("streamId") == seriesId && Column("playlistId") == playlistId
            && Column("type") == "series"
        )
        .deleteAll(db)
    }
  }

  // MARK: Playback

  /// "3. Title", the form the player shell and the downloads use for an episode.
  static func episodeTitle(_ episode: DBEpisode) -> String {
    let num = episode.episodeNum.map { "\($0). " } ?? ""
    let raw = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let title = raw.isEmpty ? L("detail.episode_fallback") : raw
    return "\(num)\(title)"
  }

  /// The history row `HistorySeriesPlayerShell` is started with for an episode of the page.
  ///
  /// The shell reads the stream, the texts, the artwork and the position from it. They
  /// are taken from the episode row, which is current, on top of `history` when the
  /// episode has one. `resumesFinished` keeps the stored position even when the episode
  /// counts as watched; otherwise such an episode starts over.
  static func playbackSeed(
    episode: DBEpisode,
    history: DBWatchHistory?,
    resumesFinished: Bool,
    series: DBSeries,
    playlistId: UUID,
    now: Date = Date()
  ) -> DBWatchHistory {
    let streamId = episode.episodeId ?? episode.id
    var seed =
      history
      ?? DBWatchHistory(
        id: "\(playlistId)_series_\(streamId)",
        playlistId: playlistId,
        streamId: streamId,
        type: "series",
        lastTimeMs: 0,
        durationMs: 0,
        lastWatchedAt: now,
        seriesId: nil,
        title: "",
        secondaryTitle: nil,
        imageURL: nil,
        containerExtension: nil
      )
    // Without the series id the shell has no neighbours to step to.
    seed.seriesId = String(series.seriesId)
    seed.title = episodeTitle(episode)
    seed.secondaryTitle = series.name
    seed.imageURL =
      episode.cover.flatMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
      } ?? series.cover
    seed.containerExtension = episode.containerExtension
    if !resumesFinished, seed.resumePositionMs(as: .episode) == nil {
      seed.lastTimeMs = 0
    }
    return seed
  }
}

final class SeasonEpisodesObserver: ObservableObject {
  /// nil only until the first season has been read, so that the panel shows its loading
  /// state instead of "no episodes" in the meantime. A season switch keeps the previous
  /// season's rows until the new ones exist: emptying the list in between collapses the
  /// page under the reader and the scroll view clamps its offset.
  @Published private(set) var season: SeasonEpisodes?
  private var seasonId: String?
  private var cancellable: AnyCancellable?

  func load(seasonId: String?, playlistId: UUID, db: AppDatabase) {
    guard seasonId != self.seasonId else { return }
    self.seasonId = seasonId
    cancellable?.cancel()
    guard let seasonId else {
      cancellable = nil
      season = nil
      return
    }
    cancellable =
      ValueObservation
      .tracking { db in
        try SeriesDetailData.seasonEpisodes(seasonId: seasonId, playlistId: playlistId, db: db)
      }
      // Daily series can contain hundreds of episodes in one season. Keep the
      // previous rows visible while the next read runs on the database queue.
      .publisher(in: db.reader)
      // The player saves a history row every few seconds and the observation
      // re-fetches on each of them; the panel only hears about its own episodes.
      .removeDuplicates()
      .sink(
        receiveCompletion: { [weak self] completion in
          guard self?.seasonId == seasonId else { return }
          if case .failure(let error) = completion {
            Log.error("SeriesDetail", "Season observation failed: \(error)")
            self?.seasonId = nil
          }
        },
        receiveValue: { [weak self] season in
          guard self?.seasonId == seasonId else { return }
          self?.season = season
        })
  }

  deinit {
    cancellable?.cancel()
  }
}
