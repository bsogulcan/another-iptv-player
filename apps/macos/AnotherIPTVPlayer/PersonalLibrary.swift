import AppKit
import GRDB
import SwiftUI

extension MediaSelection {
  static func history(_ row: DBWatchHistory, source: Playlist, database: AppDatabase) async throws
    -> Self
  {
    let builder = PlaybackURLBuilder(playlist: source)
    if source.kind == .m3u || row.type == "live" || row.type == "vod" {
      if source.kind != .m3u, Int(row.streamId) == nil { throw URLError(.badURL) }
      let item = CatalogItem(
        playlistId: source.id, kind: source.kind == .m3u ? "m3u" : row.type, streamKey: row.streamId,
        title: row.title,
        category: row.secondaryTitle ?? "", artwork: row.imageURL, rating: nil, favorite: false,
        sortIndex: 0)
      do {
        let selection = try await resolve(item, in: source, database: database, fallbackExtension: row.containerExtension)
        guard source.kind != .m3u || selection.type == row.type else { throw URLError(.badURL) }
        return selection
      } catch let error as URLError where error.code == .badURL && source.kind == .m3u && row.type == "vod" {
        // A provider can remove the channel while its downloaded film and
        // watch position still belong to the playlist.
        return try await downloadedM3UMovie(item, database: database)
      }
    }
    guard row.type == "series" else { throw URLError(.badURL) }
    let (episode, series): (DBEpisode?, DBSeries?)
    if let seriesID = row.seriesId.flatMap(Int.init) {
      (episode, series) = try await database.read { db in
        let episode = try DBEpisode.fetchOne(db, sql: """
          SELECT e.* FROM episode e JOIN season s ON s.id = e.seasonId
          WHERE s.playlistId = ? AND s.seriesId = ? AND COALESCE(e.episodeId, e.id) = ?
          ORDER BY (e.episodeId IS NULL), s.seasonNumber, s.id, e.episodeNum, e.id LIMIT 1
          """, arguments: [source.id, seriesID, row.streamId])
        let series = try DBSeries.filter(Column("playlistId") == source.id && Column("seriesId") == seriesID).fetchOne(db)
        return (episode, series)
      }
    } else { (episode, series) = (nil, nil) }
    let ext = episode?.containerExtension ?? row.containerExtension
    guard let url = builder.seriesURL(streamId: row.streamId, containerExtension: ext) else { throw URLError(.badURL) }
    let downloadID = DownloadManager.idFor(episode: source.id, episodeId: row.streamId)
    return Self(
      url: url, playlistId: source.id, streamId: row.streamId, type: row.type,
      title: episode.map(SeriesDetailData.episodeTitle) ?? row.title,
      secondaryTitle: series?.name ?? row.secondaryTitle, artwork: episodeArtwork(episode?.cover, series?.cover, row.imageURL), ext: ext,
      seriesId: row.seriesId, downloadID: downloadID)
  }
}

struct MacHistoryShelf<More: View>: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var playback: DesktopPlayback
  @State private var error: String?
  @State private var unavailable: DBWatchHistory?
  let source: Playlist
  let rows: [DBWatchHistory]
  let title: String
  @ViewBuilder let more: More

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
        Spacer()
        more
      }
      ScrollView(.horizontal) {
        LazyHStack(spacing: 12) {
          ForEach(rows) { row in
            Button { play(row) } label: {
              HStack(spacing: 10) {
                CachedImage(url: row.imageURL.flatMap(URL.init(string:)), width: 52, height: 46,
                            iconName: row.type == "live" ? "tv" : "play.rectangle", loadProfile: .grid)
                VStack(alignment: .leading, spacing: 5) {
                  Text(verbatim: row.title).font(.headline).lineLimit(1)
                  if let subtitle = row.secondaryTitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                  }
                  if row.type != "live", row.durationMs > 0 {
                    ProgressView(value: min(1, max(0, Double(row.lastTimeMs) / Double(row.durationMs))))
                      .progressViewStyle(.linear)
                  }
                }
              }.padding(10).frame(width: 215, alignment: .leading)
                .background(.quaternary, in: .rect(cornerRadius: 9))
            }.buttonStyle(.plain).accessibilityLabel(row.title)
              .contextMenu {
                Button(L("movie.play"), systemImage: "play.fill") { play(row) }
                Button(L("history.item.remove"), systemImage: "trash", role: .destructive) {
                  Task {
                    do { _ = try await database.write { try row.delete($0) } }
                    catch { self.error = NetworkErrorText.describe(error) }
                  }
                }
              }
          }
        }.padding(.vertical, 2)
      }
      .frame(height: 86, alignment: .top)
    }.modifier(UnavailableHistoryAlert(item: $unavailable, error: $error))
    .macError($error)
  }

  private func play(_ row: DBWatchHistory) {
    Task {
      do { playback.start(try await MediaSelection.history(row, source: source, database: database)) }
      catch let error as URLError where source.kind == .m3u && error.code == .badURL { unavailable = row }
      catch { self.error = NetworkErrorText.describe(error) }
    }
  }

}

struct MacHistory: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var playback: DesktopPlayback
  let source: Playlist
  let query: String
  private struct Request: Hashable {
    let playlist: UUID
    let scope: String
    let search: String
    let limit: Int
  }
  nonisolated private struct Page: Equatable {
    let rows: [DBWatchHistory]
    let hasHistory: Bool
    let more: Bool
  }
  @State private var result: Page?
  @State private var scope = ""
  @State private var limit = 100
  @State private var error: String?
  @State private var unavailable: DBWatchHistory?
  @State private var pendingClear: Request?
  init(source: Playlist, query: String, initialScope: String = "") {
    self.source = source
    self.query = query
    _scope = State(initialValue: initialScope)
  }

  private var request: Request {
    Request(playlist: source.id, scope: scope, search: query.trimmingCharacters(in: .whitespacesAndNewlines), limit: limit)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        Text(L(scope.isEmpty ? "history.title" : "history.title." + scope)).font(.largeTitle.bold())
        Picker(L("settings.playlist.type"), selection: $scope) {
          Text(L("search.all")).tag("")
          Text(L("dashboard.live")).tag("live")
          Text(L("dashboard.movies")).tag("vod")
          if source.kind == .xtream { Text(L("dashboard.series")).tag("series") }
        }.pickerStyle(.segmented).labelsHidden().fixedSize()
      }.padding(.horizontal, 26).padding(.vertical, 14)
      if let result, result.rows.isEmpty {
        ContentUnavailableView(
          L(result.hasHistory ? "favorites.empty.no_result.title" : "history.empty.title"),
          systemImage: result.hasHistory ? "magnifyingglass" : "clock",
          description: result.hasHistory ? nil : Text(L("history.empty.message")))
      } else if let result {
        List {
          ForEach(result.rows) { row in
            HStack {
              Button {
                play(row)
              } label: {
                HStack(spacing: 12) {
                  CachedImage(url: row.imageURL.flatMap(URL.init(string:)), width: 60, height: 44,
                              iconName: row.type == "live" ? "antenna.radiowaves.left.and.right" :
                                row.type == "series" ? "play.tv" : "film", loadProfile: .grid)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: row.title).font(.headline)
                    if let caption = row.secondaryTitle {
                      Text(verbatim: caption).font(.caption).foregroundStyle(.secondary)
                    }
                    if row.durationMs > 0 {
                      ProgressView(
                        value: min(1, max(0, Double(row.lastTimeMs) / Double(row.durationMs)))
                      ).frame(width: 110)
                    }
                  }
                  Spacer()
                  Text(row.lastWatchedAt, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
                }.contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityLabel(row.title)
                .accessibilityValue([row.secondaryTitle, row.lastWatchedAt.formatted(
                  .dateTime.month().day().hour().minute().locale(AppLocale.current))
                ].compactMap { $0 }.joined(separator: ", "))
            }.padding(.vertical, 5)
              .contextMenu {
                Button(L("movie.play")) { play(row) }
                Button(L("history.item.remove"), role: .destructive) {
                  Task {
                    do { _ = try await database.write { try row.delete($0) } } catch {
                      self.error = NetworkErrorText.describe(error)
                    }
                  }
                }
              }
            .onAppear {
              if result.more, result.rows.count == limit, row.id == result.rows.last?.id { limit += 100 }
            }
          }
          if result.more { Button(ML("load_more")) { limit += 100 } }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onChange(of: scope) { _, _ in
      limit = 100
      result = nil
    }
    .onChange(of: query) { _, _ in limit = 100 }
    .task(id: request) {
      let current = request
      do {
        if !current.search.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
        let observation = ValueObservation.tracking { db in
          var all = DBWatchHistory.filter(Column("playlistId") == current.playlist)
          if !current.scope.isEmpty { all = all.filter(Column("type") == current.scope) }
          let filtered = current.search.isEmpty ? all :
            all.filter(sql: "localized_contains(title, ?)", arguments: [current.search])
          let rows = try filtered.order(Column("lastWatchedAt").desc, Column("id")).limit(current.limit + 1).fetchAll(db)
          let hasHistory = rows.isEmpty && !current.search.isEmpty ? (try all.fetchOne(db) != nil) : !rows.isEmpty
          return Page(rows: Array(rows.prefix(current.limit)), hasHistory: hasHistory, more: rows.count > current.limit)
        }
        for try await value in observation.removeDuplicates().values(in: database.reader) {
          try Task.checkCancellation()
          result = value
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .toolbar {
      Button(L("history.clear.title"), systemImage: "trash") { pendingClear = request }
        .disabled(result?.hasHistory != true)
        .confirmationDialog(L("history.clear.title"),
          isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
          presenting: pendingClear) { selection in
          Button(L("history.clear.label"), role: .destructive) {
            Task {
              do {
                _ = try await database.write { db in
                  var rows = DBWatchHistory.filter(Column("playlistId") == selection.playlist)
                  if !selection.scope.isEmpty { rows = rows.filter(Column("type") == selection.scope) }
                  return try rows.deleteAll(db)
                }
              } catch { self.error = NetworkErrorText.describe(error) }
            }
          }
          Button(L("common.cancel"), role: .cancel) {}
        } message: { selection in
          Text(L("history.clear.message." + (selection.scope.isEmpty ? "all" : selection.scope)))
        }
    }
    .modifier(UnavailableHistoryAlert(item: $unavailable, error: $error))
    .macError($error)
  }
  private func play(_ row: DBWatchHistory) {
    Task {
      do {
        playback.start(try await MediaSelection.history(row, source: source, database: database))
      } catch let error as URLError where source.kind == .m3u && error.code == .badURL { unavailable = row }
      catch { self.error = NetworkErrorText.describe(error) }
    }
  }
}

private struct UnavailableHistoryAlert: ViewModifier {
  @Environment(\.appDatabase) private var database
  @Binding var item: DBWatchHistory?
  @Binding var error: String?

  func body(content: Content) -> some View {
    content.alert(L("m3u.history.unavailable.title"),
      isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }), presenting: item) { row in
      Button(L("history.item.remove"), role: .destructive) {
        Task {
          do { _ = try await database.write { try row.delete($0) } }
          catch { self.error = NetworkErrorText.describe(error) }
        }
      }
      Button(L("common.cancel"), role: .cancel) {}
    } message: { _ in Text(L("m3u.history.unavailable.message")) }
  }
}

struct MacDownloads: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var playback: DesktopPlayback
  private let manager = DownloadManager.shared
  let source: Playlist
  let query: String
  nonisolated private struct Results: Equatable, Sendable {
    let libraryIsEmpty: Bool
    let sections: DownloadSections
  }
  @State private var results: Results?
  @State private var cancelling: DBDownloadedItem?
  private struct Request: Hashable {
    let playlist: UUID
    let search: String
  }
  @State private var error: String?
  @State private var missing: DBDownloadedItem?
  @State private var deleting: DBDownloadedItem?
  var body: some View {
    let request = Request(playlist: source.id, search: query.trimmingCharacters(in: .whitespacesAndNewlines))
    VStack(alignment: .leading, spacing: 0) {
      Text(L("download.title")).font(.largeTitle.bold()).padding(.horizontal, 26).padding(.vertical, 14)
      if let results {
        let sections = results.sections
        if sections.isEmpty {
          ContentUnavailableView(L(results.libraryIsEmpty ? "download.empty.title" : "favorites.empty.no_result.title"),
            systemImage: results.libraryIsEmpty ? "arrow.down.circle" : "magnifyingglass",
            description: results.libraryIsEmpty ? Text(L("download.empty.message")) : nil)
        } else {
          List {
            section(L("download.status.downloading"), sections.inProgress)
            section(L("download.status.queued"), sections.queued)
            section(L("download.status.failed"), sections.failed)
            section(L("dashboard.movies"), sections.completedMovies)
            ForEach(sections.completedEpisodeGroups) { group in
              section(group.title, group.episodes)
            }
          }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onChange(of: source.id) { _, _ in results = nil }
    .task(id: request) {
      do {
        if !request.search.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
        let observation = ValueObservation.tracking { db in
          let rows = try DBDownloadedItem.filter(Column("playlistId") == request.playlist)
            .order(Column("createdAt").desc, Column("id")).fetchAll(db)
          return Results(libraryIsEmpty: rows.isEmpty, sections: DownloadSections.make(from: rows, matching: request.search))
        }
        for try await value in observation.removeDuplicates().values(in: database.reader) {
          try Task.checkCancellation()
          results = value
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .confirmationDialog(
      L("download.missing_file.title"),
      isPresented: Binding(get: { missing != nil }, set: { if !$0 { missing = nil } }),
      presenting: missing
    ) { item in
      Button(L("download.retry")) { retry(item) }
      Button(L("common.cancel"), role: .cancel) {}
    } message: { _ in
      Text(L("download.missing_file.message"))
    }
    .confirmationDialog(
      L("download.delete"),
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      presenting: deleting
    ) { item in
      Button(L("download.delete"), role: .destructive) {
        Task { await manager.delete(id: item.id) }
      }
      Button(L("common.cancel"), role: .cancel) {}
    } message: {
      Text(verbatim: $0.title)
    }
    .confirmationDialog(ML("cancel_transfer"),
      isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
      presenting: cancelling) { item in
        Button(ML("cancel_transfer"), role: .destructive) { manager.cancel(id: item.id) }
        Button(ML("keep_transfer"), role: .cancel) {}
      } message: { Text(verbatim: $0.title) }
    .macError($error)
  }
  @ViewBuilder private func section(_ title: String, _ rows: [DBDownloadedItem]) -> some View {
    if !rows.isEmpty {
      Section {
        ForEach(rows) { item in rowView(item) }
      } header: { Text(verbatim: title) }
    }
  }

  private func subtitle(for row: DBDownloadedItem) -> String {
    var parts: [String] = []
    if row.type != "episode" || row.downloadStatus != .completed, let series = row.secondaryTitle, !series.isEmpty {
      parts.append(series)
    }
    if row.type == "episode" {
      if let season = row.seasonNumber { parts.append(L("series.season_format", season)) }
      if let episode = row.episodeNumber { parts.append(L("series.episode_format", episode)) }
    }
    return parts.joined(separator: " · ")
  }

  private func rowView(_ row: DBDownloadedItem) -> some View {
    let unfinished = row.downloadStatus == .downloading || row.downloadStatus == .queued
    return HStack(spacing: 12) {
      CachedImage(url: row.imageURL.flatMap(URL.init(string:)), width: 48, height: 48,
        iconName: row.type == "episode" ? "play.tv" : "film", loadProfile: .grid)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: row.title).font(.headline).lineLimit(2)
        let text = subtitle(for: row)
        if !text.isEmpty {
          Text(verbatim: text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        switch row.downloadStatus {
        case .downloading:
          MacDownloadProgress(row: row).frame(maxWidth: 220, alignment: .leading)
        case .failed:
          Text(DownloadFormatting.failureText(row.errorMessage)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        case .completed:
          Text(DownloadFormatting.byteCount(Int64(row.totalBytes))).font(.caption).foregroundStyle(.secondary)
        case .queued: EmptyView()
        }
      }
      Spacer()
      switch row.downloadStatus {
      case .completed: Button(L("movie.play"), systemImage: "play.fill") { play(row) }
      case .failed: Button(L("download.retry")) { retry(row) }
      case .downloading, .queued: Button(L("download.cancel")) { cancelling = row }
      }
      if !unfinished {
        Button(L("download.delete"), systemImage: "trash", role: .destructive) { deleting = row }
          .labelStyle(.iconOnly)
      }
    }.padding(.vertical, 5)
      .contextMenu {
        if row.downloadStatus == .completed { Button(L("download.play")) { play(row) } }
        if row.downloadStatus == .failed { Button(L("download.retry")) { retry(row) } }
        Button(L(unfinished ? "download.cancel" : "download.delete"), role: .destructive) {
          if unfinished { cancelling = row } else { deleting = row }
        }
      }
  }
  private func play(_ row: DBDownloadedItem) {
    Task {
      guard let file = await manager.localURL(forId: row.id) else {
        missing = row
        return
      }
      playback.start(
        MediaSelection(
          url: file, playlistId: source.id, streamId: row.streamId,
          type: row.type == "episode" ? "series" : "vod",
          title: row.title, secondaryTitle: row.secondaryTitle, artwork: row.imageURL,
          ext: row.containerExtension, seriesId: row.seriesId, downloadID: row.id))
    }
  }
  private func retry(_ row: DBDownloadedItem) {
    guard let url = URL(string: row.remoteURL) else {
      error = L("onboarding.error.invalid_address")
      return
    }
    Task {
      await manager.enqueue(
        id: row.id, playlistId: row.playlistId, streamId: row.streamId, type: row.type,
        title: row.title,
        secondaryTitle: row.secondaryTitle, imageURL: row.imageURL, remoteURL: url,
        containerExtension: row.containerExtension,
        seriesId: row.seriesId, seasonNumber: row.seasonNumber, episodeNumber: row.episodeNumber)
    }
  }
}

private struct MacDownloadProgress: View {
  let row: DBDownloadedItem
  @ObservedObject private var manager = DownloadManager.shared

  var body: some View {
    DownloadProgressFooter(progress: manager.progress[row.id], stored: DownloadProgress(
      totalBytes: Int64(row.totalBytes), downloadedBytes: Int64(row.downloadedBytes)))
  }
}

func isFileImportCancellation(_ error: Error) -> Bool {
  error is CancellationError || (error as? CocoaError)?.code == .userCancelled
}

extension View {
  func macError(_ message: Binding<String?>) -> some View {
    alert(
      L("common.error"),
      isPresented: Binding(
        get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
    ) {
      Button(L("common.ok")) {}
    } message: {
      Text(message.wrappedValue ?? "")
    }
  }
}
