import GRDB
import SwiftUI
import StoreKit

struct MacDiscoverView: View {
  @Environment(\.requestReview) private var requestReview
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var playback: DesktopPlayback
  @ObservedObject private var hidden = HiddenCategoryStore.shared
  let source: Playlist
  let open: (CatalogItem) -> Void
  let browse: (MediaKind) -> Void
  let history: (String) -> Void
  @State private var shelves: [Shelf] = []
  @State private var featured: Feature?
  @State private var recent: [DBWatchHistory] = []
  @State private var recentLive: [DBWatchHistory] = []
  @State private var error: String?
  @State private var loaded = false

  nonisolated struct Shelf: Identifiable, Equatable {
    let kind: MediaKind
    let items: [CatalogItem]
    var id: MediaKind { kind }
  }
  nonisolated struct Feature: Equatable {
    let item: CatalogItem
    let backdrop: String?
    let plot: String?
  }
  nonisolated struct Snapshot: Equatable {
    let shelves: [Shelf]
    let featured: Feature?
    let recent: [DBWatchHistory]
    let recentLive: [DBWatchHistory]
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: source.name).font(.subheadline).foregroundStyle(.secondary)
            Text(ML("discover")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
          }
          if let featured { hero(featured) }
          if !recent.isEmpty {
            historyShelf(recent, title: L("continue_watching.title"), scope: "")
          }
          if !recentLive.isEmpty {
            historyShelf(recentLive, title: ML("recent_live_channels"), scope: "live")
          }
          ForEach(shelves) { shelf in
            VStack(alignment: .leading, spacing: 13) {
              header(shelf.kind.title) { browse(shelf.kind) }
              let count = min(6, max(2, Int((min(geometry.size.width, 1450) - 40) / 155)))
              LazyVGrid(
                columns: Array(
                  repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count),
                alignment: .leading
              ) {
                ForEach(shelf.items.prefix(count)) { item in
                  Button {
                    open(item)
                  } label: {
                    VStack(alignment: .leading, spacing: 6) {
                      CatalogArtwork(item: item, poster: item.usesPoster)
                      Text(verbatim: item.title).font(.headline).lineLimit(2)
                      if !item.usesPoster { MacChannelProgramme(item: item) }
                      if !item.category.isEmpty {
                        Text(verbatim: item.category).font(.caption).foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                    }
                  }.buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .modifier(MacChannelProgrammeAccessibility(item: item))
                }
              }
            }
          }
          if loaded && shelves.isEmpty && recent.isEmpty && recentLive.isEmpty {
            ContentUnavailableView(
              L("favorites.empty.no_result.title"), systemImage: "rectangle.stack")
          }
          if !loaded { ProgressView() }
        }.padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 28)
          .frame(maxWidth: 1450, alignment: .leading).frame(maxWidth: .infinity)
      }
    }
    .task(id: RefreshKey(playlist: source.id, version: hidden.version)) {
      let kinds: [MediaKind] = source.kind == .m3u ? [.m3u] : [.vod, .series, .live]
      let queries = kinds.map { kind in
        MacCatalogQuery(
          playlistID: source.id, kinds: [kind],
          order: [.vod, .series].contains(kind) ? .recent : .provider,
          hidden: [kind: hidden.hiddenIds(playlistId: source.id, type: kind.rawValue)], limit: 7)
      }
      do {
        for try await state in ValueObservation.tracking({ db in
          try Self.snapshot(queries: queries, playlist: source.id, db: db)
        }).values(in: database.reader) {
          try Task.checkCancellation()
          shelves = state.shelves
          featured = state.featured
          recent = state.recent
          recentLive = state.recentLive
          loaded = true
        }
      } catch {
        if !Task.isCancelled {
          self.error = NetworkErrorText.describe(error)
          loaded = true
        }
      }
    }
    .task(id: loaded && !shelves.isEmpty && playback.current == nil) {
      guard loaded, !shelves.isEmpty, playback.current == nil, !MockFixture.isActive,
        NSClassFromString("XCTestCase") == nil
      else { return }
      RatingManager.shared.registerSuccessfulSession()
      do { try await Task.sleep(for: .seconds(8)) } catch { return }
      guard playback.current == nil else { return }
      RatingManager.shared.requestReviewIfAppropriate(in: NSApp.keyWindow) { requestReview() }
    }
    .macError($error)
  }

  nonisolated static func snapshot(queries: [MacCatalogQuery], playlist: UUID, db: Database) throws
    -> Snapshot
  {
    let shelves = try queries.compactMap { query -> Shelf? in
      let items = try query.fetch(db)
      guard let kind = query.kinds.first, !items.isEmpty else { return nil }
      return Shelf(kind: kind, items: items)
    }
    var feature: Feature?
    for shelf in shelves where [.vod, .series].contains(shelf.kind) {
      guard let item = shelf.items.first, let id = Int(item.streamKey) else { continue }
      if item.media == .vod {
        let row = try DBVODStream.filter(
          Column("streamId") == id && Column("playlistId") == playlist
        ).fetchOne(db)
        feature = Feature(item: item, backdrop: row?.backdropPath, plot: row?.plot)
      } else {
        let row = try DBSeries.filter(Column("seriesId") == id && Column("playlistId") == playlist)
          .fetchOne(db)
        feature = Feature(item: item, backdrop: row?.backdropPath, plot: row?.plot)
      }
      break
    }
    let history = DBWatchHistory.filter(Column("playlistId") == playlist)
      .order(Column("lastWatchedAt").desc, Column("id"))
    let recentLive = try history.filter(Column("type") == "live").limit(8).fetchAll(db)
    let cursor = try history.filter(["vod", "series"].contains(Column("type"))).fetchCursor(db)
    var seenSeries = Set<String>()
    var recent: [DBWatchHistory] = []
    while recent.count < 8, let row = try cursor.next() {
      if row.type == "series", let series = row.seriesId, !series.isEmpty,
         !seenSeries.insert(series).inserted { continue }
      if row.resumePositionMs(as: row.type == "series" ? .episode : .film) != nil { recent.append(row) }
    }
    return Snapshot(shelves: shelves, featured: feature, recent: recent, recentLive: recentLive)
  }

  private func historyShelf(_ rows: [DBWatchHistory], title: String, scope: String) -> some View {
    MacHistoryShelf(source: source, rows: rows, title: title) {
      Button(ML("see_all")) { history(scope) }
        .buttonStyle(.link).accessibilityLabel(ML("see_all") + " · " + title)
    }
  }

  private struct RefreshKey: Hashable {
    let playlist: UUID
    let version: Int
  }
  private func header(_ text: String, action: @escaping () -> Void) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(text).font(.title2.bold()).accessibilityAddTraits(.isHeader)
      Spacer()
      Button(ML("see_all"), action: action).buttonStyle(.link)
    }
  }
  @ViewBuilder private func hero(_ feature: Feature) -> some View {
    if let raw = feature.backdrop, let url = URL(string: raw), url.scheme != nil {
      Color.black.frame(height: 232)
        .overlay {
          GeometryReader { geo in
            CachedImage(
              url: url, width: geo.size.width, height: geo.size.height, cornerRadius: 0,
              contentMode: .fill)
          }
        }
        .overlay {
          LinearGradient(
            colors: [.black.opacity(0.79), .black.opacity(0.35), .clear], startPoint: .leading,
            endPoint: .trailing)
        }
        .overlay(alignment: .bottomLeading) {
          heroCopy(feature).foregroundStyle(.white).padding(24).environment(\.colorScheme, .dark)
        }
        .clipShape(.rect(cornerRadius: 14))
    } else {
      HStack(alignment: .center, spacing: 22) {
        CatalogArtwork(item: feature.item, poster: true).frame(width: 116)
        heroCopy(feature)
        Spacer(minLength: 0)
      }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
        .quaternary.opacity(0.55), in: .rect(cornerRadius: 12))
    }
  }
  private func heroCopy(_ feature: Feature) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if !feature.item.category.isEmpty {
        Text(verbatim: feature.item.category).font(.subheadline.weight(.medium))
      }
      Text(verbatim: feature.item.title).font(
        .system(.largeTitle, design: .serif).weight(.semibold)
      ).lineLimit(2)
      if let plot = feature.plot, !plot.isEmpty {
        Text(verbatim: plot).lineLimit(2).frame(maxWidth: 540, alignment: .leading)
      }
      Button(ML("details"), systemImage: "info.circle") { open(feature.item) }.controlSize(.large)
        .padding(.top, 3)
    }
  }
}
