import Foundation
import GRDB

enum MediaKind: String, CaseIterable, Hashable, Sendable {
  case live, vod, series, m3u
  var title: String {
    switch self {
    case .live: L("dashboard.live")
    case .vod: L("dashboard.movies")
    case .series: L("dashboard.series")
    case .m3u: L("dashboard.channels")
    }
  }
  var symbol: String {
    switch self {
    case .live, .m3u: "antenna.radiowaves.left.and.right"
    case .vod: "film"
    case .series: "tv"
    }
  }
  nonisolated var table: String {
    switch self {
    case .live: "liveStream"
    case .vod: "vodStream"
    case .series: "series"
    case .m3u: "m3uChannel"
    }
  }
  nonisolated var identifier: String {
    switch self {
    case .live, .vod: "streamId"
    case .series: "seriesId"
    case .m3u: "id"
    }
  }
}

nonisolated struct CatalogItem: Hashable, Identifiable, Decodable, FetchableRecord, Sendable {
  let playlistId: UUID
  let kind: String
  let streamKey: String
  let title: String
  let category: String
  let artwork: String?
  let rating: String?
  let favorite: Bool
  let sortIndex: Int
  var m3uURL: String?
  var groupKey: String?
  var epgID: String?
  var epgName: String?
  var isM3UMovie: Bool {
    guard let m3uURL, let url = M3UParser.sanitizedURL(from: m3uURL) else { return false }
    return !M3UStreamClassifier.classify(url: url, groupTitle: category).isLive
  }
  var displayMedia: MediaKind { isM3UMovie ? .vod : media }
  var usesPoster: Bool { [.vod, .series].contains(displayMedia) }
  var id: String { "\(playlistId)/\(kind)/\(streamKey)" }
  var media: MediaKind { MediaKind(rawValue: kind)! }
}

nonisolated struct CatalogGroup: Identifiable, Hashable, FetchableRecord, Decodable, Sendable {
  let id: String
  let name: String
}

enum CatalogOrder: String, CaseIterable, Identifiable, Sendable {
  case provider = "sort.default"
  case az = "sort.name_asc"
  case za = "sort.name_desc"
  case rating = "sort.rating_desc"
  case recent = "sort.recently_added"
  var id: Self { self }
}

nonisolated struct CatalogFilters: Hashable, Sendable {
  var catchup = false
  var hasEPG = false
  var unwatched = false
  var highRated = false
  var values = Set<String>()
}

nonisolated struct MacCatalogQuery: Hashable, Sendable {
  let playlistID: UUID
  var kinds: [MediaKind]
  var search = ""
  var selectedGroup: String?
  var favoritesOnly = false
  var order = CatalogOrder.provider
  var hidden: [MediaKind: Set<String>] = [:]
  var limit = 100
  var filters = CatalogFilters()
  var liveChannelsOnly = false
  var streamKey: String?
  var excludedStreamKey: String?
  var recentlyAddedOnly = false
  static let recentShelfLimit = 20

  private func selection(_ db: Database, applyingFilters: Bool) throws -> (
    String, StatementArguments
  ) {
    let filterM3U =
      kinds.contains(.m3u)
      && (try? Playlist.fetchOne(db, key: playlistID))?.filterAdultContent == true
    var args = StatementArguments()
    let parts = kinds.map { kind -> String in
      let m3u = kind == .m3u
      let xtreamGroup = kind == .live
        ? "coalesce(c.id,'\(PlaylistContentStore.uncategorizedCategoryId)')" : "coalesce(s.categoryId,'')"
      let category =
        m3u ? "coalesce(nullif(trim(s.groupTitle),''), 'Diğer')" : (liveChannelsOnly ? xtreamGroup : "coalesce(s.categoryId,'')")
      let name = m3u ? category : "coalesce(c.name,'')"
      let image = m3u ? "s.tvgLogo" : (kind == .series ? "s.cover" : "s.streamIcon")
      let rating = kind == .vod || kind == .series ? "s.rating" : "NULL"
      let added: String
      switch kind {
      case .vod: added = "s.added"
      case .series: added = "s.lastModified"
      default: added = "0"
      }
      let favorites =
        m3u
        ? "EXISTS(SELECT 1 FROM m3uFavorite f WHERE f.playlistId=s.playlistId AND f.channelId=s.id)"
        : "EXISTS(SELECT 1 FROM favorite f WHERE f.playlistId=s.playlistId AND f.type='\(kind.rawValue)' AND f.streamId=s.\(kind.identifier))"
      let join =
        m3u
        ? ""
        : "LEFT JOIN category c ON c.playlistId=s.playlistId AND c.id=s.categoryId AND c.type='\(kind.rawValue)'"
      var conditions = ["s.playlistId = ?"]
      args += [playlistID]
      if recentlyAddedOnly {
        conditions += ["nullif(c.id, '') IS NOT NULL", "mac_provider_timestamp(\(added)) IS NOT NULL"]
      }
      if m3u && liveChannelsOnly { conditions.append("mac_live_url(s.url,s.groupTitle)") }
      if m3u && filterM3U {
        conditions += ["NOT mac_adult_name(s.name)", "NOT mac_adult_name(s.groupTitle)"]
      }
      if let selectedGroup {
        if !m3u && selectedGroup == PlaylistContentStore.uncategorizedCategoryId {
          conditions.append("(nullif(c.id, '') IS NULL OR c.id = ?)")
          args += [selectedGroup]
        } else {
          let column = (kind == .vod || kind == .series) && !selectedGroup.isEmpty ? "s.categoryId" : category
          conditions.append("\(column) = ?")
          args += [selectedGroup]
        }
      }
      if let suppressed = hidden[kind], !suppressed.isEmpty {
        let parameters = Array(repeating: "?", count: suppressed.count).joined(separator: ",")
        conditions.append("\(category) NOT IN (\(parameters))")
        args += StatementArguments(suppressed.sorted())
        if !m3u && suppressed.contains(PlaylistContentStore.uncategorizedCategoryId) {
          conditions.append("nullif(c.id, '') IS NOT NULL")
        }
      }
      let facet: String
      switch kind {
      case .vod: facet = "s.containerExtension"
      case .series: facet = "s.genre"
      default: facet = "NULL"
      }
      if applyingFilters {
        if kind == .live {
          if filters.catchup { conditions.append("s.tvArchive > 0") }
          if filters.hasEPG { conditions.append("coalesce(s.epgChannelId, '') != ''") }
        }
        if kind == .vod || kind == .series {
          if filters.highRated { conditions.append("mac_rating(s.rating) >= 7") }
          if !filters.values.isEmpty {
            let values = filters.values.sorted()
            if kind == .vod {
              conditions.append(
                "mac_file_type(\(facet)) IN (\(Array(repeating: "?", count: values.count).joined(separator: ",")))"
              )
            } else {
              conditions.append(
                "(" + values.map { _ in "mac_has_genre(s.genre, ?)" }.joined(separator: " OR ")
                  + ")")
            }
            args += StatementArguments(values)
          }
        }
        if kind == .vod && filters.unwatched {
          conditions.append(
            "NOT EXISTS (SELECT 1 FROM watchHistory h WHERE h.playlistId=s.playlistId AND h.type='vod' AND h.streamId=CAST(s.streamId AS TEXT) AND h.durationMs>0 AND h.lastTimeMs>=0.95*h.durationMs)"
          )
        }
      }
      if !search.isEmpty {
        conditions.append("localized_contains(s.name, ?)")
        args += [search]
      }
      if let streamKey {
        conditions.append("s.\(kind.identifier) = ?")
        args += [streamKey]
      }
      if let excludedStreamKey {
        conditions.append("s.\(kind.identifier) != ?")
        args += [excludedStreamKey]
      }
      if favoritesOnly { conditions.append(favorites) }
      return """
        SELECT s.playlistId, '\(kind.rawValue)' AS kind, CAST(s.\(kind.identifier) AS TEXT) AS streamKey,
               \(kind == .live ? "s.epgChannelId" : m3u ? "s.tvgId" : "NULL") AS epgID,
               \(m3u ? "s.tvgName" : "NULL") AS epgName,
               \(m3u ? category : xtreamGroup) AS groupKey,
               \(m3u ? category : "coalesce(nullif(c.id,''),'\(PlaylistContentStore.uncategorizedCategoryId)')") AS pickerGroup,
               \(m3u ? "s.sortIndex" : "coalesce(c.sortIndex,2147483647)") AS groupOrder,
               s.name AS title, \(m3u ? "s.url" : "NULL") AS m3uURL, \(name) AS category, \(image) AS artwork, \(rating) AS rating,
               \(facet) AS facet, \(favorites) AS favorite, s.sortIndex, CAST(\(added) AS INTEGER) AS addedAt
        FROM \(kind.table) s \(join) WHERE \(conditions.joined(separator: " AND "))
        """
    }
    return (parts.joined(separator: " UNION ALL "), args)
  }

  func categoryCounts(_ db: Database) throws -> [String: Int] {
    let (base, args) = try selection(db, applyingFilters: false)
    let rows = try Row.fetchAll(db, sql: "SELECT pickerGroup, count(*) AS total FROM (\(base)) GROUP BY pickerGroup",
                                arguments: args)
    return Dictionary(uniqueKeysWithValues: rows.map { ($0["pickerGroup"], $0["total"]) })
  }

  func liveChannelGroups(_ db: Database) throws -> [CatalogGroup] {
    let (base, args) = try selection(db, applyingFilters: true)
    return try CatalogGroup.fetchAll(db, sql: """
      SELECT groupKey AS id, category AS name FROM (\(base))
      GROUP BY groupKey ORDER BY min(groupOrder), category COLLATE mac_title, groupKey
      """, arguments: args)
  }

  func facetValues(_ db: Database) throws -> [String] {
    guard kinds == [.series] || kinds == [.vod] else { return [] }
    let (base, args) = try selection(db, applyingFilters: false)
    let raw = try String.fetchAll(
      db, sql: "SELECT DISTINCT facet FROM (\(base)) WHERE facet IS NOT NULL", arguments: args)
    if kinds == [.vod] { return Set(raw.compactMap(VODFileType.normalized)).sorted() }
    return Set(raw.flatMap(SeriesGenre.split)).sorted {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
  }

  struct SearchSection: Identifiable, Equatable, Sendable {
    let kind: MediaKind
    let count: Int
    let preview: [CatalogItem]
    var id: MediaKind { kind }
  }

  func searchSections(_ db: Database) throws -> [SearchSection] {
    try kinds.compactMap { kind in
      var section = self
      section.kinds = [kind]
      section.limit = 4
      let preview = try section.fetch(db)
      guard !preview.isEmpty else { return nil }
      var count = preview.count
      if count == section.limit {
        let (base, args) = try section.selection(db, applyingFilters: true)
        count = try Int.fetchOne(db, sql: "SELECT count(*) FROM (\(base))", arguments: args) ?? count
      }
      return SearchSection(kind: kind, count: count, preview: preview)
    }
  }

  func fetch(_ db: Database) throws -> [CatalogItem] {
    guard !kinds.isEmpty, !recentlyAddedOnly || kinds == [.vod] || kinds == [.series] else { return [] }
    var (base, args) = try selection(db, applyingFilters: true)
    var sorts: [String] = []
    if !search.isEmpty {
      sorts += ["localized_equals(title, ?) DESC", "localized_starts_with(title, ?) DESC"]
      args += [search, search]
    }
    switch order {
    case .az: sorts.append("title COLLATE mac_title ASC")
    case .za: sorts.append("title COLLATE mac_title DESC")
    case .rating: sorts.append("mac_rating(rating) DESC")
    case .recent: sorts.append("addedAt DESC")
    case .provider: break
    }
    sorts += ["sortIndex", "kind", "streamKey"]
    args += [limit]
    return try CatalogItem.fetchAll(
      db,
      sql:
        "SELECT * FROM (\(base)) ORDER BY \(sorts.joined(separator: ", ")) LIMIT ?",
      arguments: args)
  }

  static func groups(in db: Database, playlist: UUID, kind: MediaKind) throws -> [CatalogGroup] {
    if kind == .m3u {
      return try CatalogGroup.fetchAll(
        db,
        sql: """
          SELECT coalesce(nullif(trim(groupTitle),''),?) AS id, coalesce(nullif(trim(groupTitle),''),?) AS name
          FROM m3uChannel WHERE playlistId=? AND (NOT (SELECT filterAdultContent FROM playlist WHERE id=m3uChannel.playlistId) OR (NOT mac_adult_name(name) AND NOT mac_adult_name(groupTitle))) GROUP BY 1 ORDER BY min(sortIndex)
          """,
        arguments: [M3UContentStore.ungroupedLabel, M3UContentStore.ungroupedLabel, playlist])
    }
    var groups = try CatalogGroup.fetchAll(
      db, sql: "SELECT id,name FROM category WHERE playlistId=? AND type=? AND id != '' ORDER BY sortIndex",
      arguments: [playlist, kind.rawValue])
    let orphan = PlaylistContentStore.uncategorizedCategoryId
    if !groups.contains(where: { $0.id == orphan }),
       try Bool.fetchOne(db, sql: """
         SELECT EXISTS(
           SELECT 1 FROM \(kind.table) s WHERE s.playlistId = ? AND (
             coalesce(s.categoryId, '') = '' OR NOT EXISTS (
               SELECT 1 FROM category c WHERE c.playlistId = s.playlistId AND c.type = ? AND c.id = s.categoryId
             )
           )
         )
         """, arguments: [playlist, kind.rawValue]) == true {
      groups.append(CatalogGroup(id: orphan, name: L("content.uncategorized")))
    }
    return groups
  }
}

extension CatalogItem {
  func isFavorite(in db: Database) throws -> Bool {
    if media == .m3u {
      return try DBM3UFavorite.filter(
        Column("channelId") == streamKey && Column("playlistId") == playlistId
      ).fetchCount(db) > 0
    }
    guard let number = Int(streamKey) else { return false }
    return try DBFavorite.filter(
      Column("streamId") == number && Column("playlistId") == playlistId && Column("type") == kind
    ).fetchCount(db) > 0
  }

  func setFavorite(_ desired: Bool, in database: AppDatabase) async throws {
    if media == .m3u {
      try await database.write { db in
        let row = DBM3UFavorite(channelId: streamKey, playlistId: playlistId)
        if desired { try row.insert(db, onConflict: .ignore) } else { _ = try row.delete(db) }
      }
    } else if let number = Int(streamKey) {
      try await FavoriteWriter.set(
        desired, streamId: number, type: kind, playlistId: playlistId, in: database)
    }
  }
}
