import Foundation
import GRDB

enum MacQueueItem: Identifiable {
  case catalog(CatalogItem)
  case episode(DBEpisode, series: CatalogItem)

  var id: String {
    switch self {
    case .catalog(let item): item.streamKey
    case .episode(let row, _): row.episodeId ?? row.id
    }
  }
  var title: String {
    switch self {
    case .catalog(let item): item.title
    case .episode(let row, _): SeriesDetailData.episodeTitle(row)
    }
  }
  func resolve(source: Playlist, database: AppDatabase) async throws -> MediaSelection {
    switch self {
    case .catalog(let item): try await MediaSelection.resolve(item, in: source, database: database)
    case .episode(let row, let series):
      try MediaSelection.episode(row, series: series, source: source)
    }
  }
}
struct MacQueue {
  let source: Playlist
  let items: [MacQueueItem]

  static func load(for media: MediaSelection, catalog: MacCatalogQuery?, in database: AppDatabase)
    async throws -> MacQueue?
  {
    guard media.isLive || media.type == "series" || media.type == "vod" else { return nil }
    guard let source = try await database.read({ try Playlist.fetchOne($0, key: media.playlistId) })
    else { return nil }
    if media.type == "series", let key = media.seriesId, let seriesID = Int(key) {
      let (record, episodes) = try await database.read { db in
        let series = try DBSeries.filter(Column("seriesId") == seriesID && Column("playlistId") == source.id).fetchOne(db)
        let episodes = try SeriesPlaybackOrdering.orderedEpisodes(seriesId: seriesID, playlistId: source.id, db: db)
        return (series, episodes)
      }
      let series = CatalogItem(
        playlistId: source.id, kind: "series", streamKey: key,
        title: record?.name ?? media.secondaryTitle ?? media.title,
        category: "", artwork: record?.cover, rating: nil, favorite: false, sortIndex: 0)
      return MacQueue(source: source, items: episodes.map { .episode($0, series: series) })
    }
    let kind: MediaKind = source.kind == .m3u ? .m3u : media.isLive ? .live : .vod
    let hidden = HiddenCategoryStore.shared.hiddenIds(playlistId: source.id, type: kind.rawValue)
    let items = try await database.read { db -> [MacQueueItem] in
      var query =
        catalog
        ?? MacCatalogQuery(
          playlistID: source.id, kinds: [kind], hidden: [kind: hidden], limit: Int.max)
      guard query.playlistID == source.id, query.kinds.contains(kind) else { return [] }
      query.kinds = [kind]
      if media.isLive && kind == .m3u { query.liveChannelsOnly = true }
      if kind == .m3u, query.selectedGroup == nil {
        guard
          let channel = try DBM3UChannel.filter(
            Column("playlistId") == source.id && Column("id") == media.streamId
          ).fetchOne(db)
        else { return [] }
        query.selectedGroup = M3UContentStore.groupKey(for: channel)
      } else if kind == .vod, catalog == nil {
        guard let id = Int(media.streamId),
          let movie = try DBVODStream.filter(
            Column("playlistId") == source.id && Column("streamId") == id
          ).fetchOne(db)
        else { return [] }
        query.selectedGroup = movie.categoryId ?? ""
      }
      return try query.fetch(db).map(MacQueueItem.catalog)
    }
    guard !items.isEmpty else { return nil }
    return MacQueue(source: source, items: items)
  }
}
