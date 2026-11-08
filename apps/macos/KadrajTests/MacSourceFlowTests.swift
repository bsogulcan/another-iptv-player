import Foundation
import GRDB
import Testing

@testable import another_iptv_player

@Suite("Mac source and catalogue flows")
@MainActor
struct MacSourceFlowTests {
  private let list = """
    #EXTM3U x-tvg-url="https://example.invalid/guide.xml"
    #EXTINF:-1 tvg-id="show" group-title="Cinema",Afternoon Film
    #EXTVLCOPT:http-user-agent=FixturePlayer
    https://media.invalid/movie/afternoon.mp4
    #EXTINF:-1 group-title="News",Radio News
    https://media.invalid/live/news.ts
    """

  @Test(arguments: [MediaKind.vod, .series])
  func recentShelfRequiresListedCategoryAndIntegerTimestampBeforeLimiting(_ kind: MediaKind) throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Recent titles", serverURL: "https://fixture.invalid")
    try database.writeSync { db in
      try source.insert(db)
      for group in ["visible", "hidden"] {
        try DBCategory(id: group, name: group, type: kind.rawValue, playlistId: source.id).insert(db)
      }
      for i in 0..<130 {
        let group = i < 90 ? "hidden" : i == 90 ? "no-such-category" : "visible"
        let date = i < 92 ? "10000" : i == 92 ? "99999bad" : i == 93 ? nil : String(200 - i / 2)
        if kind == .vod {
          try DBVODStream(streamId: i, name: "Title \(i)", categoryId: group, added: date,
                          sortIndex: i, playlistId: source.id).insert(db)
        } else {
          try DBSeries(seriesId: i, name: "Title \(i)", lastModified: date, categoryId: group,
                       sortIndex: i, playlistId: source.id).insert(db)
        }
      }
      let query = MacCatalogQuery(playlistID: source.id, kinds: [kind], order: .recent,
        hidden: [kind: ["hidden"]], limit: MacCatalogQuery.recentShelfLimit, recentlyAddedOnly: true)
      #expect(try query.fetch(db).map(\.streamKey) == ([91] + Array(94...112)).map(String.init))
    }
  }

  @Test(arguments: [MediaKind.live, .vod, .series])
  func uncategorizedIncludesMissingAndRemovedCategoriesOfTheSelectedKind(_ kind: MediaKind) throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Mixed groups", serverURL: "https://fixture.invalid")
    let orphan = PlaylistContentStore.uncategorizedCategoryId
    try database.writeSync { db in
      try source.insert(db)
      for (type, id) in [(kind, "known"), (kind == .live ? MediaKind.vod : .live, "other-type")] {
        try DBCategory(id: id, name: id, type: type.rawValue, playlistId: source.id).insert(db)
      }
      let groupIds: [String?] = ["known", nil, "", "removed", "other-type"]
      for (i, category) in groupIds.enumerated() {
        switch kind {
        case .vod:
          try DBVODStream(streamId: i, name: "Title \(i)", categoryId: category, sortIndex: i, playlistId: source.id).insert(db)
        case .series:
          try DBSeries(seriesId: i, name: "Title \(i)", categoryId: category, sortIndex: i, playlistId: source.id).insert(db)
        case .live:
          try DBLiveStream(streamId: i, name: "Title \(i)", categoryId: category, sortIndex: i, playlistId: source.id).insert(db)
        case .m3u: break
        }
      }
      let groups = try MacCatalogQuery.groups(in: db, playlist: source.id, kind: kind)
      #expect(groups.map(\.id) == ["known", orphan])
      var query = MacCatalogQuery(playlistID: source.id, kinds: [kind], selectedGroup: orphan)
      #expect(try query.fetch(db).map(\.streamKey) == ["1", "2", "3", "4"])
      query.selectedGroup = nil
      query.hidden = [kind: [orphan]]
      #expect(try query.fetch(db).map(\.streamKey) == ["0"])
      query.hidden = [kind: ["removed"]]
      #expect(try query.fetch(db).map(\.streamKey) == ["0", "1", "2", "4"])
    }
  }

  @Test func catalogueFiltersIntersectWithCategoryAndApplyBeforePaging() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Filter fixture", serverURL: "https://fixture.invalid")
    try database.writeSync { db in
      try source.insert(db)
      for i in 1...105 {
        try DBVODStream(
          streamId: i, name: "Film \(i)", categoryId: "visible", rating: "6",
          containerExtension: "mp4", sortIndex: i, playlistId: source.id
        ).insert(db)
      }
      for (id, category) in [(200, "visible"), (201, "visible"), (202, "hidden")] {
        try DBVODStream(
          streamId: id, name: "Harbor \(id)", categoryId: category, rating: "7,2",
          containerExtension: " MKV ", sortIndex: id, playlistId: source.id
        ).insert(db)
      }
      try DBWatchHistory(
        id: "watched", playlistId: source.id, streamId: "200", type: "vod", lastTimeMs: 9500,
        durationMs: 10000, lastWatchedAt: .now, title: "Harbor 200"
      ).insert(db)
      try DBWatchHistory(
        id: "part", playlistId: source.id, streamId: "201", type: "vod", lastTimeMs: 9499,
        durationMs: 10000, lastWatchedAt: .now, title: "Harbor 201"
      ).insert(db)
      for (id, genre, rating) in [
        (1, "Crime / Drama", "7,0"), (2, "Crime fiction", "9"), (3, "Crime|Thriller", "6.9"),
      ] {
        try DBSeries(
          seriesId: id, name: "Series \(id)", genre: genre, rating: rating, playlistId: source.id
        ).insert(db)
      }
      for (id, epg, archive) in [(1, "one", 1), (2, "", 1), (3, "three", 0)] {
        try DBLiveStream(
          streamId: id, name: "Channel \(id)", epgChannelId: epg, playlistId: source.id,
          tvArchive: archive
        ).insert(db)
      }
    }
    try await database.read { db in
      let films = MacCatalogQuery(
        playlistID: source.id, kinds: [.vod], selectedGroup: "visible", hidden: [.vod: ["hidden"]],
        limit: 1,
        filters: CatalogFilters(unwatched: true, highRated: true, values: ["mkv"]))
      let matchingFilms = try films.fetch(db).map(\.streamKey)
      #expect(matchingFilms == ["201"])
      let extensions = try films.facetValues(db)
      #expect(extensions == ["mkv", "mp4"])
      let series = MacCatalogQuery(
        playlistID: source.id, kinds: [.series],
        filters: CatalogFilters(highRated: true, values: ["Crime"]))
      let matchingSeries = try series.fetch(db).map(\.streamKey)
      #expect(matchingSeries == ["1"])
      let genres = try Set(series.facetValues(db))
      #expect(genres == ["Crime", "Drama", "Crime fiction", "Thriller"])
      let live = MacCatalogQuery(
        playlistID: source.id, kinds: [.live], filters: CatalogFilters(catchup: true, hasEPG: true))
      let matchingChannels = try live.fetch(db).map(\.streamKey)
      #expect(matchingChannels == ["1"])
    }
  }

  @Test func localFileSurvivesRelaunchAndRenameKeepsFavorites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("fixture.m3u")
    try list.write(to: file, atomically: true, encoding: .utf8)
    let path = directory.appendingPathComponent("catalog.sqlite").path
    var draft = SourceDraft(kind: .m3u)
    draft.name = "Fixture"
    let selected = try draft.selectFile(.success(file))
    let cancelled = try draft.selectFile(.failure(CocoaError(.userCancelled)))
    #expect(selected)
    #expect(!cancelled)
    #expect(draft.file == file)
    let source: Playlist
    do {
      let database = try AppDatabase(DatabaseQueue(path: path))
      source = try await draft.save(in: database, status: { _ in }, committing: {})
      let items = try await database.read {
        try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0)
      }
      #expect(items.map(\.title) == ["Afternoon Film", "Radio News"])
      try await items[0].setFavorite(!items[0].favorite, in: database)
      let media = try await MediaSelection.resolve(items[0], in: source, database: database)
      #expect(!media.isLive)
      #expect(media.userAgent == "FixturePlayer")
      let live = try await MediaSelection.resolve(items[1], in: source, database: database)
      #expect(live.isLive)
    }
    try FileManager.default.removeItem(at: file)
    let reopened = try AppDatabase(DatabaseQueue(path: path))
    var edit = SourceDraft(kind: .m3u, editing: source)
    edit.name = "Living room"
    let renamed = try await edit.save(in: reopened, status: { _ in }, committing: {})
    #expect(renamed.id == source.id)
    let stored = try await reopened.read { db in try Playlist.fetchOne(db, key: source.id) }
    #expect(stored?.name == "Living room")
    #expect(stored?.m3uEpgURL == "https://example.invalid/guide.xml")
    let favorites = try await reopened.read {
      try MacCatalogQuery(playlistID: source.id, kinds: [.m3u], favoritesOnly: true).fetch($0)
    }
    #expect(favorites.map(\.title) == ["Afternoon Film"])
    let visible = try await reopened.read {
      try MacCatalogQuery(playlistID: source.id, kinds: [.m3u], hidden: [.m3u: ["Cinema"]]).fetch(
        $0)
    }
    #expect(visible.map(\.title) == ["Radio News"])
  }

  @Test func discardPromptTracksOnlyUnsavedSourceInput() throws {
    let local = Playlist(name: "Living room", serverURL: "", type: .m3u)
    var fileDraft = SourceDraft(kind: .m3u, editing: local)
    fileDraft.name = " Living room "
    #expect(!fileDraft.hasUnsavedInput)
    _ = try fileDraft.selectFile(.success(URL(fileURLWithPath: "/tmp/replacement.m3u")))
    #expect(fileDraft.hasUnsavedInput)
    fileDraft.file = nil
    #expect(!fileDraft.hasUnsavedInput)
    fileDraft.address = "https://example.invalid/list.m3u"
    #expect(fileDraft.hasUnsavedInput)

    let panel = Playlist(name: "Panel", serverURL: "https://example.invalid", username: "user", password: "pw")
    var panelDraft = SourceDraft(kind: .xtream, editing: panel)
    panelDraft.username = " user "
    #expect(!panelDraft.hasUnsavedInput)
    panelDraft.filterAdult.toggle()
    #expect(panelDraft.hasUnsavedInput)
    panelDraft.filterAdult.toggle()
    panelDraft.password += " "
    #expect(panelDraft.hasUnsavedInput)
    panelDraft.password = panel.password
    #expect(!panelDraft.hasUnsavedInput)
  }

  @Test func xtreamAccountLinkPopulatesNativeSourceDraft() {
    var draft = SourceDraft(kind: .xtream)
    draft.address = "https://fixture.invalid/panel/get.php?username=demo&password=a%2Bb"
    draft.applyAccountLink()
    #expect(draft.name == "fixture.invalid")
    #expect(draft.address == "https://fixture.invalid/panel")
    #expect(draft.username == "demo")
    #expect(draft.password == "a+b")
    #expect(draft.canSave)
    draft.name = "Living room"
    draft.address = "https://second.invalid/player_api.php?username=other&password=secret"
    draft.applyAccountLink()
    #expect(draft.name == "Living room")
    #expect(draft.address == "https://second.invalid")
    #expect(draft.username == "other")
  }

  @Test func remoteM3UAndGetLinkFallback() async throws {
    let db = AppDatabase.empty()
    let host = EPGTestSupport.uniqueHost()
    XtreamStubURLProtocol.setAnswer(.init(status: 200, body: Data(list.utf8)), forHost: host)
    defer { XtreamStubURLProtocol.setAnswer(nil, forHost: host) }
    var draft = SourceDraft(kind: .m3u)
    draft.name = "Remote"
    draft.address = "https://\(host)/get.php?username=test&password=fixture"
    let source = try await draft.save(
      in: db, session: XtreamStubURLProtocol.makeSession(), status: { _ in }, committing: {})
    #expect(source.kind == .m3u)
    let requests = XtreamStubURLProtocol.requests(forHost: host).compactMap {
      $0.url?.lastPathComponent
    }
    #expect(requests == ["player_api.php", "get.php"])
    #expect(try await db.read { try DBM3UChannel.fetchCount($0) } == 2)
  }

  @Test func replacingRemoteListWithLocalFileRetainsMatchingFavorite() async throws {
    let db = AppDatabase.empty()
    let host = EPGTestSupport.uniqueHost()
    XtreamStubURLProtocol.setAnswer(.init(status: 200, body: Data(list.utf8)), forHost: host)
    defer { XtreamStubURLProtocol.setAnswer(nil, forHost: host) }
    var draft = SourceDraft(kind: .m3u)
    draft.name = "Home"
    draft.address = "https://\(host)/list.m3u"
    let source = try await draft.save(in: db, session: XtreamStubURLProtocol.makeSession(), status: { _ in }, committing: {})
    let items = try await db.read { try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0) }
    let film = try #require(items.first { $0.title == "Afternoon Film" })
    try await film.setFavorite(true, in: db)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m3u")
    defer { try? FileManager.default.removeItem(at: file) }
    try "#EXTM3U\n#EXTINF:-1,Missing address".write(to: file, atomically: true, encoding: .utf8)
    var edit = SourceDraft(kind: .m3u, editing: source)
    _ = try edit.selectFile(.success(file))
    await #expect(throws: M3UParserError.self) {
      _ = try await edit.save(in: db, status: { _ in }, committing: { Issue.record("Invalid list reached commit") })
    }
    let retained = try await db.read { try Playlist.fetchOne($0, key: source.id) }
    #expect(retained?.serverURL == source.serverURL)
    let unchanged = try await db.read { try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0) }
    #expect(unchanged.map(\.id) == items.map(\.id))
    #expect(unchanged.filter(\.favorite).map(\.id) == [film.id])
    try list.replacingOccurrences(of: "Radio News", with: "Local News").write(to: file, atomically: true, encoding: .utf8)
    let replaced = try await edit.save(in: db, status: { _ in }, committing: {})
    #expect(replaced.id == source.id)
    #expect(replaced.serverURL.isEmpty)
    let updated = try await db.read { try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0) }
    #expect(Set(updated.map(\.title)) == ["Afternoon Film", "Local News"])
    #expect(updated.filter(\.favorite).map(\.id) == [film.id])
  }

  @Test func livePanelGroupsFollowProviderOrderAndCollectOrphans() async throws {
    let db = AppDatabase.empty()
    let source = Playlist(name: "Cable", serverURL: "https://fixture.invalid")
    try db.writeSync { db in
      try source.insert(db)
      for (index, id) in ["sports", "news", "unused", "hidden"].enumerated() {
        try DBCategory(id: id, name: id.capitalized, type: "live", sortIndex: index, playlistId: source.id).insert(db)
      }
      for (index, id) in ["news", "sports", "missing", "hidden"].enumerated() {
        try DBLiveStream(streamId: index + 1, name: id.capitalized, categoryId: id,
                         playlistId: source.id).insert(db)
      }
    }
    let query = MacCatalogQuery(playlistID: source.id, kinds: [.live], hidden: [.live: ["hidden"]],
                                liveChannelsOnly: true)
    let groups = try await db.read { try query.liveChannelGroups($0).map(\.id) }
    #expect(groups == ["sports", "news", PlaylistContentStore.uncategorizedCategoryId])
    var orphan = query
    orphan.selectedGroup = PlaylistContentStore.uncategorizedCategoryId
    let orphanQuery = orphan
    let names = try await db.read { try orphanQuery.fetch($0).map(\.title) }
    #expect(names == ["Missing"])
  }

  @Test(arguments: [false, true])
  func staleNetworkRefreshCannotApplyAfterProviderEditOrDeletion(scoped: Bool) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MacPanelProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    for deleteSource in [false, true] {
      let db = AppDatabase.empty()
      let source = Playlist(name: "Old panel", serverURL: "https://panel.invalid", username: "old")
      try db.writeSync { db in
        try source.insert(db)
        try DBLiveStream(streamId: 9, name: "Existing channel", playlistId: source.id).insert(db)
      }
      let store = PlaylistContentStore(database: db, makeClient: {
        XtreamAPIClient(playlist: $0, urlSession: session)
      })
      var didChangeSource = false
      do {
        let onProgress: (String) -> Void = { phase in
          guard phase == L("phase.save_db") else { return }
          do {
            try db.writeSync { db in
              if deleteSource {
                _ = try source.delete(db)
              } else {
                var changed = source
                changed.username = "new"
                try changed.update(db)
              }
            }
            didChangeSource = true
          } catch { Issue.record("Could not update source fixture: \(error)") }
        }
        if scoped {
          try await store.syncFromNetworkReplacingLocal(playlist: source, only: .live, progress: onProgress)
        } else {
          try await store.syncFromNetworkReplacingLocal(playlist: source, progress: onProgress)
        }
        Issue.record("Old credentials must not change the stored catalogue")
      } catch is CancellationError {}
      #expect(didChangeSource)
      let rows = try await db.read {
        try MacCatalogQuery(playlistID: source.id, kinds: [.live]).fetch($0).map(\.title)
      }
      #expect(rows == (deleteSource ? [] : ["Existing channel"]))
    }
  }

  enum ImportRace: CaseIterable { case deletion, changedProvider, editedSettings, failedWrite }

  @Test(arguments: [PlaylistKind.xtream, .m3u], ImportRace.allCases)
  func fullImportRespectsConcurrentChanges(kind: PlaylistKind, race: ImportRace) async throws {
    let db = AppDatabase.empty()
    let source = Playlist(name: "Original", serverURL: kind == .m3u ? "" : "https://panel.invalid",
                          username: "user", password: "fixture", type: kind, timeshiftStyle: "php")
    try db.writeSync { db in
      try source.insert(db)
      if kind == .xtream {
        try DBLiveStream(streamId: 42, name: "Previously saved", playlistId: source.id).insert(db)
      } else {
        try DBM3UChannel(id: "42", playlistId: source.id, name: "Previously saved",
          url: "https://media.invalid/42.ts", sortIndex: 0).insert(db)
      }
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m3u")
    try list.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MacPanelProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    var draft = SourceDraft(kind: kind, editing: source)
    if kind == .m3u { draft.file = file }
    if race == .failedWrite { draft.name = "Rename during edit" }
    var commitReached = false
    var saved: Playlist?
    do {
      saved = try await draft.save(in: db, session: session, forceRefresh: true, status: { _ in }) {
        do {
          try db.writeSync { sql in
            var current = source
            switch race {
            case .deletion:
              _ = try current.delete(sql)
            case .changedProvider:
              current.serverURL = "https://replacement.invalid"
              try current.update(sql)
            case .editedSettings:
              current.name = "Latest name"
              current.filterAdultContent = true
              current.epgEnabled = false
              current.epgURLOverride = "https://guide.invalid/current.xml"
              current.serverTimezone = "Europe/Istanbul"
              current.timeshiftStyle = "path-no-m3u8"
              try current.update(sql)
            case .failedWrite:
              let table = kind == .xtream ? "liveStream" : "m3uChannel"
              try sql.execute(sql: "CREATE TRIGGER fail_import BEFORE INSERT ON \(table) BEGIN SELECT RAISE(ABORT,'test write failure'); END")
            }
          }
          commitReached = true
        } catch { Issue.record("Failed to set up concurrent change: \(error)") }
      }
      #expect(race == .editedSettings)
    } catch {
      if race == .failedWrite { #expect(error is DatabaseError) }
      else { #expect(error is PlaylistImportConflict) }
    }
    #expect(commitReached)
    let current = try await db.read { try Playlist.fetchOne($0, key: source.id) }
    let names = try await db.read {
      try MacCatalogQuery(playlistID: source.id, kinds: [kind == .m3u ? .m3u : .live]).fetch($0).map(\.title)
    }
    switch race {
    case .deletion:
      #expect(current == nil && names.isEmpty)
    case .changedProvider:
      #expect(current?.serverURL == "https://replacement.invalid")
      #expect(names == ["Previously saved"])
    case .failedWrite:
      #expect(current?.name == "Original")
      #expect(names == ["Previously saved"])
    case .editedSettings:
      #expect(saved == current)
      #expect(current?.name == "Latest name" && current?.filterAdultContent == true)
      #expect(current?.epgEnabled == false && current?.epgURLOverride == "https://guide.invalid/current.xml")
      #expect(current?.serverTimezone == "Europe/Istanbul" && current?.timeshiftStyle == "path-no-m3u8")
      #expect(!names.isEmpty && !names.contains("Previously saved"))
    }
  }

  @Test(arguments: [PlaylistKind.xtream, .m3u])
  func deliberateProviderChangeKeepsGuideSettingsAndDropsOldTimeshift(kind: PlaylistKind) async throws {
    let db = AppDatabase.empty()
    let original = Playlist(name: "Old provider", serverURL: "https://retired.invalid",
      username: "old", password: "old", type: kind, epgURLOverride: "https://guide.invalid/override",
      epgEnabled: false, serverTimezone: "Europe/Istanbul", timeshiftStyle: "php")
    try db.writeSync { try original.insert($0) }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m3u")
    try list.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MacPanelProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    var draft = SourceDraft(kind: kind, editing: original)
    draft.name = "New provider"
    draft.filterAdult = true
    if kind == .xtream {
      draft.address = "https://panel.invalid"
      draft.username = "new"
      draft.password = "new-password"
    } else {
      draft.file = file
    }
    let saved = try await draft.save(in: db, session: session, status: { _ in }, committing: {})
    let row = try await db.read { try Playlist.fetchOne($0, key: original.id) }
    #expect(saved == row && saved.id == original.id)
    #expect(saved.name == "New provider" && saved.filterAdultContent)
    #expect(saved.epgURLOverride == original.epgURLOverride && !saved.epgEnabled)
    #expect(saved.timeshiftStyle == nil)
    #expect(saved.serverURL == (kind == .xtream ? "https://panel.invalid" : ""))
    if kind == .xtream { #expect(saved.username == "new") }
    else { #expect(saved.m3uEpgURL == "https://example.invalid/guide.xml") }
  }

  @Test func xtreamCredentialAndLinkImportsReachAllThreeCatalogs() async throws {
    for detection in [false, true] {
      let database = AppDatabase.empty()
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MacPanelProtocol.self]
      let session = URLSession(configuration: configuration)
      defer { session.invalidateAndCancel() }
      var draft = SourceDraft(kind: detection ? .m3u : .xtream)
      draft.name = "Panel"
      draft.address =
        detection ? "https://panel.invalid/get.php?username=user&password=fixture" : "panel.invalid"
      draft.username = "user"
      draft.password = "fixture"
      let saved = try await draft.save(
        in: database, session: session, status: { _ in }, committing: {})
      #expect(saved.kind == .xtream)
      #expect(saved.username == "user")
      let result = try await database.read {
        try MacCatalogQuery(playlistID: saved.id, kinds: [.live, .vod, .series]).fetch($0)
      }
      #expect(Set(result.map(\.media)) == [.live, .vod, .series])
      #expect(Set(result.map(\.id)).count == result.count)
      let vod = try #require(result.first { $0.media == .vod })
      let media = try await MediaSelection.resolve(vod, in: saved, database: database)
      #expect(media.url.path.hasPrefix("/movie/user/fixture/"))
    }
  }
}

private nonisolated final class MacPanelProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "panel.invalid"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { return }
    let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
      $0.name == "action"
    }?.value
    let name = action == "get_series" ? "get_series_list" : action ?? "auth_success"
    let fixture = Bundle(for: Self.self).bundleURL.appendingPathComponent(
      "Contents/Resources/fixtures/xtream/\(name).json")
    do {
      let body: Data
      switch name {
      case "get_vod_categories":
        body = Data(#"[{"category_id":"12","category_name":"Cinema"}]"#.utf8)
      case "get_series_categories":
        body = Data(#"[{"category_id":"21","category_name":"Series"}]"#.utf8)
      default: body = try Data(contentsOf: fixture)
      }
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
