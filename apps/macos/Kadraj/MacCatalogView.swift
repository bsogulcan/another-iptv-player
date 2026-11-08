import GRDB
import GRDBQuery
import SwiftUI

struct MacCatalogView: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var playback: DesktopPlayback
  @ObservedObject private var hidden = HiddenCategoryStore.shared
  @AppStorage("mac.posterPresentation") private var posters = true
  @AppStorage private var order: CatalogOrder
  @State private var filters = CatalogFilters()
  @State private var facetValues: [String] = []
  @State private var showFilters = false
  @State private var scope: MediaKind?
  @State private var group: String?
  @State private var groups: [CatalogGroup] = []
  @State private var items: [CatalogItem] = []
  @State private var searchSections: [MacCatalogQuery.SearchSection] = []
  @State private var displayedQuery: MacCatalogQuery?
  @State private var watchProgress: [String: Double] = [:]
  @State private var countLimit = 100
  @State private var loading = true
  @State private var more = false
  @State private var retry = 0
  @State private var error: String?
  @State private var selected: CatalogItem.ID?
  @State private var refreshID: UUID?
  @State private var phase: String?
  @State private var refreshError: String?
  private var refreshType: CatalogContentType? {
    guard !recentOnly, source.kind == .xtream, !favorites, !isSearch, kinds.count == 1 else { return nil }
    switch kinds[0] {
    case .live: return .live
    case .vod: return .vod
    case .series: return .series
    case .m3u: return nil
    }
  }
  let source: Playlist
  let kinds: [MediaKind]
  let title: String
  let search: String
  let favorites: Bool
  let isSearch: Bool
  let recentOnly: Bool
  let category: CatalogGroup?
  @State private var recentItems: [CatalogItem] = []
  let open: (CatalogItem, MacCatalogQuery) -> Void

  init(
    source: Playlist, kinds: [MediaKind], title: String, search: String, favorites: Bool,
    isSearch: Bool, initialFavoriteKind: MediaKind? = nil, recentOnly: Bool = false, category: CatalogGroup? = nil,
    open: @escaping (CatalogItem, MacCatalogQuery) -> Void
  ) {
    self.source = source
    self.kinds = kinds
    self.title = title
    self.search = search
    self.favorites = favorites
    self.isSearch = isSearch
    self.recentOnly = recentOnly
    self.category = category
    _group = State(initialValue: category?.id)
    self.open = open
    _scope = State(initialValue: favorites && kinds.contains(.vod) ? (initialFavoriteKind ?? .vod) : nil)
    let key =
      isSearch ? "search" : favorites ? "favorites" : kinds.map(\.rawValue).joined(separator: ".")
    _order = AppStorage(wrappedValue: .provider, "mac.catalog.sort." + key)
  }

  private var selectedKind: MediaKind? { scope ?? (kinds.count == 1 ? kinds[0] : nil) }
  private var progressType: String? {
    switch selectedKind {
    case .vod, .m3u: "vod"
    case .series: "series"
    default: nil
    }
  }
  private func progress(for item: CatalogItem) -> Double? {
    item.usesPoster ? watchProgress[item.streamKey] : nil
  }

  private var orders: [CatalogOrder] {
    selectedKind == .live || selectedKind == .m3u ? [.provider, .az, .za] : CatalogOrder.allCases
  }
  private var facetQuery: MacCatalogQuery {
    var query = request
    query.filters = CatalogFilters()
    query.order = .provider
    query.limit = 0
    return query
  }
  private var request: MacCatalogQuery {
    let types = scope.map { [$0] } ?? kinds
    return MacCatalogQuery(
      playlistID: source.id, kinds: types,
      search: search.trimmingCharacters(in: .whitespacesAndNewlines),
      selectedGroup: group, favoritesOnly: favorites,
      order: recentOnly ? .recent : orders.contains(order) ? order : .provider,
      hidden: Dictionary(
        uniqueKeysWithValues: types.map {
          ($0, hidden.hiddenIds(playlistId: source.id, type: $0.rawValue))
        }),
      limit: recentOnly ? MacCatalogQuery.recentShelfLimit : countLimit + 1, filters: filters, recentlyAddedOnly: recentOnly)
  }
  private var playbackQuery: MacCatalogQuery {
    var query = displayedQuery ?? request
    if !query.recentlyAddedOnly { query.limit = Int.max }
    return query
  }
  private var shelfQuery: MacCatalogQuery? {
    guard !recentOnly, !favorites, !isSearch, kinds == [.vod] || kinds == [.series],
      request.search.isEmpty, group == nil, filters == CatalogFilters() else { return nil }
    var query = request
    query.order = .recent
    query.recentlyAddedOnly = true
    query.limit = MacCatalogQuery.recentShelfLimit
    return query
  }

  private var shelfGroups: [CatalogGroup] {
    guard usesPosters, shelfQuery != nil, let kind = selectedKind else { return [] }
    let excluded = hidden.hiddenIds(playlistId: source.id, type: kind.rawValue)
    return groups.filter { !excluded.contains($0.id) }
  }

  @ViewBuilder private var historyShelf: some View {
    if let kind = selectedKind, source.kind == .xtream, !favorites, !isSearch, !recentOnly,
       group == nil, request.search.isEmpty, filters == CatalogFilters() {
      MacCatalogHistoryShelf(source: source, kind: kind)
    }
  }

  private var usesPosters: Bool { posters && !(kinds.count == 1 && kinds[0] == .live) }
  private var catalogHeader: some View {
    HStack {
      Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
      Spacer()
      if kinds.count > 1 {
        Picker(L(favorites ? "favorites.type" : "search.title"), selection: $scope) {
          if !favorites { Text(L("search.all")).tag(nil as MediaKind?) }
          ForEach(kinds, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.pickerStyle(.segmented).labelsHidden().fixedSize()
      } else if !recentOnly && category == nil && !groups.isEmpty {
        let kind = kinds[0]
        MacCategoryPicker(groups: groups, kind: kind, selection: $group, playlistID: source.id)
      }
    }.padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 16)
  }

  private var catalogContents: some View {
    VStack(alignment: .leading, spacing: 0) {
      catalogHeader
      if let phase {
        HStack {
          ProgressView().controlSize(.small)
          Text(phase).font(.callout)
          Button(L("common.cancel")) {
            refreshID = nil
            self.phase = nil
          }
        }.padding(.horizontal, 26).padding(.bottom, 10)
      } else if let refreshError {
        HStack {
          Label(refreshError, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
          Button(L("common.try_again")) { refreshID = UUID() }
        }.padding(.horizontal, 26).padding(.bottom, 10)
      }
      if !usesPosters || (shelfGroups.isEmpty && items.isEmpty) { historyShelf }
      if isSearch && request.search.count < 2 {
        ContentUnavailableView(
          L("search.title"), systemImage: "magnifyingglass",
          description: Text(L("search.min_chars")))
      } else if let error {
        ContentUnavailableView {
          Label(L("loading.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button(L("common.try_again")) { retry += 1 }
        }
      } else if isSearch && scope == nil && kinds.count > 1 && !searchSections.isEmpty {
        groupedSearch
      } else if !shelfGroups.isEmpty {
        grid
      } else if (loading || displayedQuery?.kinds != request.kinds) && items.isEmpty {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if items.isEmpty && filters != CatalogFilters() {
        ContentUnavailableView {
          Label(
            L("favorites.empty.no_result.title"), systemImage: "line.3.horizontal.decrease.circle")
        } actions: {
          Button(L("filter.clear")) { filters = CatalogFilters() }
        }
      } else if items.isEmpty {
        ContentUnavailableView(
          L(
            favorites && request.search.isEmpty ? favoriteEmptyKey : "favorites.empty.no_result.title"),
          systemImage: favorites ? "heart" : "magnifyingglass")
      } else {
        if usesPosters { grid } else {
          if shelfQuery != nil && !recentItems.isEmpty { recentHeading.padding(.horizontal, 26) }
          table
        }
        if more {
          Button(ML("load_more")) { countLimit += 100 }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ToolbarContentBuilder private var catalogToolbar: some ToolbarContent {
    if refreshType != nil {
      ToolbarItem {
        Button(ML("refresh_catalog"), systemImage: "arrow.clockwise") { refreshID = UUID() }
          .disabled(refreshID != nil)
      }
    }
    if !recentOnly {
      ToolbarItem {
        Menu {
          Picker(
            L("sort.title"),
            selection: Binding(
              get: { orders.contains(order) ? order : .provider }, set: { order = $0 })
          ) {
            ForEach(orders) { order in Text(L(order.rawValue)).tag(order) }
          }.pickerStyle(.inline)
        } label: {
          Label(L("sort.title"), systemImage: "arrow.up.arrow.down")
        }
      }
    }
    if !recentOnly, let kind = selectedKind, kind != .m3u {
      ToolbarItem {
        Button {
          showFilters.toggle()
        } label: {
          Label(
            L("filter.title"),
            systemImage: filters == CatalogFilters()
              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }.accessibilityLabel(L("filter.title")).help(L("filter.title"))
          .popover(isPresented: $showFilters) { filterPanel(kind) }
      }
    }
    if kinds != [.live] && !(isSearch && scope == nil && kinds.count > 1) {
      ToolbarItem {
        Picker(ML("presentation"), selection: $posters) {
          Label(ML("posters"), systemImage: "square.grid.2x2").tag(true)
          Label(ML("table"), systemImage: "list.bullet").tag(false)
        }.pickerStyle(.segmented).labelsHidden()
      }
    }
  }

  var body: some View {
    catalogContents
    .toolbar { catalogToolbar }
    .task(id: refreshID) {
      guard let id = refreshID, let type = refreshType else { return }
      refreshError = nil
      phase = L("phase.fetch_categories")
      defer {
        if refreshID == id {
          refreshID = nil
          phase = nil
        }
      }
      do {
        let store = PlaylistContentStore(database: database)
        try await store.syncFromNetworkReplacingLocal(playlist: source, only: type) { message in
          if refreshID == id { phase = message }
        }
        try Task.checkCancellation()
        await PlaylistContentStore.shared.reloadFromDatabaseIfActive(playlistId: source.id, only: type)
      } catch is CancellationError {
        return
      } catch {
        if !Task.isCancelled && refreshID == id {
          refreshError = L("misc.refresh_error", NetworkErrorText.describe(error))
        }
      }
    }
    .task(id: kinds) {
      guard !recentOnly, category == nil, kinds.count == 1 else {
        groups = []
        return
      }
      let pid = source.id
      let kind = kinds[0]
      do {
        for try await value in ValueObservation.tracking({
          try MacCatalogQuery.groups(in: $0, playlist: pid, kind: kind)
        }).values(in: database.reader) {
          groups = value
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .task(id: shelfQuery) {
      recentItems = []
      guard let query = shelfQuery else { return }
      do {
        for try await items in ValueObservation.tracking({ try query.fetch($0) }).values(in: database.reader) {
          try Task.checkCancellation()
          recentItems = items
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .task(id: progressType) {
      watchProgress = [:]
      guard let type = progressType else { return }
      for await map in WatchProgressMapRequest(playlistId: source.id, type: type).publisher(in: database).values {
        guard !Task.isCancelled else { return }
        watchProgress = map
      }
    }
    .task(id: facetQuery) {
      let query = facetQuery
      guard !recentOnly, !(isSearch && (query.search.count < 2 || CatalogTextSearch.Query(query.search).isEmpty)), query.kinds == [.vod] || query.kinds == [.series]
      else {
        facetValues = []
        return
      }
      do {
        for try await values in ValueObservation.tracking({ try query.facetValues($0) }).values(
          in: database.reader)
        {
          try Task.checkCancellation()
          facetValues = values
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
    .task(id: LoadKey(query: request, retry: retry, grouped: !shelfGroups.isEmpty)) { await observe(request) }
    .onChange(of: search) { _, _ in countLimit = 100 }
    .onChange(of: group) { _, _ in
      countLimit = 100
      filters.values = []
    }
    .onChange(of: filters) { _, _ in countLimit = 100 }
    .onChange(of: scope) { _, _ in
      countLimit = 100
      group = nil
      filters = CatalogFilters()
    }
  }
  private func filterPanel(_ kind: MediaKind) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L("filter.title")).font(.headline)
      if kind == .live {
        Toggle(L("filter.catchup"), isOn: $filters.catchup)
        Toggle(L("filter.has_epg"), isOn: $filters.hasEPG)
      } else {
        if kind == .vod { Toggle(L("filter.unwatched"), isOn: $filters.unwatched) }
        Toggle(L("filter.rating_7_plus"), isOn: $filters.highRated)
        let values = Set(facetValues).union(filters.values).sorted {
          $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        if values.count > (kind == .vod && filters.values.isEmpty ? 1 : 0) {
          Divider()
          Text(L(kind == .vod ? "filter.file_type" : "filter.genre")).font(.headline)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
              ForEach(values, id: \.self) { value in
                Toggle(
                  kind == .vod ? value.uppercased() : value,
                  isOn: Binding(
                    get: { filters.values.contains(value) },
                    set: {
                      if $0 { filters.values.insert(value) } else { filters.values.remove(value) }
                    }))
              }
            }
          }.frame(height: CGFloat(min(9, values.count)) * 23)
        }
      }
      Divider()
      Button(L("filter.clear")) { filters = CatalogFilters() }.disabled(filters == CatalogFilters())
    }.toggleStyle(.checkbox).padding(14).frame(width: 250, alignment: .leading)
  }
  private struct LoadKey: Hashable {
    let query: MacCatalogQuery
    let retry: Int
    let grouped: Bool
  }
  private func observe(_ request: MacCatalogQuery) async {
    loading = true
    error = nil
    if !shelfGroups.isEmpty {
      items = []
      more = false
      loading = false
      return
    }
    do {
      if isSearch && (request.search.count < 2 || CatalogTextSearch.Query(request.search).isEmpty) {
        searchSections = []
        displayedQuery = request
        items = []
        more = false
        loading = false
        return
      }
      if displayedQuery?.kinds != request.kinds {
        items = []
        searchSections = []
      }
      if !request.search.isEmpty { try await Task.sleep(for: .milliseconds(isSearch ? 250 : 150)) }
      if isSearch && request.kinds.count > 1 {
        for try await sections in ValueObservation.tracking({ try request.searchSections($0) }).values(in: database.reader) {
          try Task.checkCancellation()
          displayedQuery = request
          searchSections = sections
          items = []
          more = false
          loading = false
        }
        return
      }
      for try await page in ValueObservation.tracking({ try request.fetch($0) }).values(
        in: database.reader)
      {
        try Task.checkCancellation()
        displayedQuery = request
        more = !recentOnly && page.count == request.limit
        items = recentOnly ? page : Array(page.prefix(request.limit - 1))
        loading = false
      }
    } catch {
      if !Task.isCancelled {
        self.error = NetworkErrorText.describe(error)
        loading = false
      }
    }
  }

  private func loadNextPageIfNeeded(_ item: CatalogItem) {
    guard more, items.count == countLimit,
      items.suffix(15).contains(where: { $0.id == item.id })
    else { return }
    countLimit += 100
  }

  private var favoriteEmptyKey: String {
    switch selectedKind {
    case .live: "favorites.empty.live"
    case .vod: "favorites.empty.movie"
    case .series: "favorites.empty.series"
    default: "favorites.empty.title"
    }
  }

  private var groupedSearch: some View {
    List {
      ForEach(searchSections) { section in
        Section {
          ForEach(section.preview) { item in
            Button { open(item, playbackQuery) } label: {
              HStack(spacing: 12) {
                CatalogArtwork(item: item, poster: item.usesPoster)
                  .frame(width: 42, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                  Text(verbatim: item.title).font(.headline)
                  if !item.category.isEmpty {
                    Text(verbatim: item.category).font(.caption).foregroundStyle(.secondary)
                  }
                }
                Spacer()
                if let rating = ContentRating.displayText(item.rating) {
                  Label(rating, systemImage: "star").foregroundStyle(.secondary)
                }
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
              .accessibilityLabel(BrowseAccessibility.cardLabel(title: item.title, rating: item.rating, category: item.category))
              .contextMenu { actions(for: item) }
          }
          if section.count > section.preview.count {
            Button(L("search.more_results_format", section.count - section.preview.count)) { scope = section.kind }
          }
        } header: {
          HStack {
            Text(section.kind.title)
            Text(section.count, format: .number).foregroundStyle(.secondary)
          }
        }
      }
    }.listStyle(.inset)
  }

  @ViewBuilder private func progressBar(for item: CatalogItem) -> some View {
    if let fraction = progress(for: item), fraction > 0 {
      ProgressView(value: fraction).progressViewStyle(.linear).accessibilityHidden(true)
    }
  }

  private var recentHeading: some View {
    HStack {
      Text(L("recently_added.title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
      Spacer()
      NavigationLink(value: CatalogDestination.recentlyAdded(source.id, kinds[0])) {
        Text(ML("see_all"))
      }.buttonStyle(.link).accessibilityLabel(ML("see_all") + " · " + L("recently_added.title"))
    }
  }

  private func card(_ item: CatalogItem, query: MacCatalogQuery) -> some View {
    Button {
      open(item, query)
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        CatalogArtwork(item: item, poster: item.usesPoster)
          .overlay(alignment: .bottom) { progressBar(for: item) }
        Text(verbatim: item.title).font(.headline).lineLimit(2)
        if !item.usesPoster { MacChannelProgramme(item: item) }
        if query.selectedGroup == nil && !item.category.isEmpty {
          Text(verbatim: item.category).font(.caption).foregroundStyle(.secondary).lineLimit(
            1)
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      BrowseAccessibility.cardLabel(
        title: item.title, rating: item.rating, category: item.category)
    )
    .accessibilityValue(BrowseAccessibility.progressValue(progress(for: item)))
    .modifier(MacChannelProgrammeAccessibility(item: item))
    .contextMenu { actions(for: item, query: query) }
  }

  private var grid: some View {
    ScrollView {
      if let query = shelfQuery, !recentItems.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          recentHeading
          MacFeaturedCarousel(source: source, items: Array(recentItems.prefix(5)), query: query, open: open)
          if shelfGroups.isEmpty { Text(L("search.all")).font(.title2.bold()).accessibilityAddTraits(.isHeader) }
        }.padding(.horizontal, 26).padding(.bottom, 10)
      }
      historyShelf
      if !shelfGroups.isEmpty, let kind = selectedKind {
        LazyVStack(alignment: .leading, spacing: 24) {
          ForEach(shelfGroups) { group in
            let query = categoryQuery(group)
            MacCategoryShelf(group: group, query: query, kind: kind,
              hide: { hidden.setHidden(true, playlistId: source.id, type: kind.rawValue, categoryId: group.id) },
              card: { card($0, query: query) })
          }
        }.padding(.horizontal, 26).padding(.bottom, 24)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 143, maximum: 225), spacing: 16, alignment: .top)],
          alignment: .leading, spacing: 20
        ) {
          ForEach(items) { item in
            card(item, query: playbackQuery)
              .onAppear { loadNextPageIfNeeded(item) }
          }
        }.padding(.horizontal, 26).padding(.bottom, 24)
      }
    }
  }
  private func categoryQuery(_ group: CatalogGroup) -> MacCatalogQuery {
    var query = request
    query.selectedGroup = group.id
    query.limit = Int.max
    return query
  }

  private var table: some View {
    Table(items, selection: $selected) {
      TableColumn(ML("title")) { item in
        HStack(spacing: 9) {
          CatalogArtwork(item: item, poster: false).frame(width: 47)
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: item.title)
            progressBar(for: item)
          }
          .accessibilityElement(children: .combine)
          .accessibilityValue(BrowseAccessibility.progressValue(progress(for: item)))
          if item.favorite {
            Image(systemName: "heart.fill").foregroundStyle(.secondary).accessibilityLabel(
              L("favorites.title"))
          }
        }.padding(.vertical, 3).onAppear { loadNextPageIfNeeded(item) }
      }.width(min: 170, ideal: 340)
      TableColumn(L("category_picker.title"), value: \.category).width(min: 80, ideal: 150)
      TableColumn(kinds == [.live] ? L("epg.now") : L("settings.playlist.type")) { item in
        if kinds == [.live] {
          MacChannelProgramme(item: item, inTable: true)
        } else {
          Text(item.displayMedia.title)
        }
      }.width(min: 72, ideal: kinds == [.live] ? 200 : 100)
    }
    .contextMenu(forSelectionType: CatalogItem.ID.self) { ids in
      if let item = items.first(where: { ids.contains($0.id) }) { actions(for: item) }
    } primaryAction: { ids in
      if let item = items.first(where: { ids.contains($0.id) }) { open(item, playbackQuery) }
    }
    .onKeyPress(.return) {
      guard let item = items.first(where: { $0.id == selected }) else { return .ignored }
      open(item, playbackQuery)
      return .handled
    }
  }
  private func playM3UMovie(_ item: CatalogItem) {
    Task {
      do {
        playback.start(
          try await MediaSelection.resolve(item, in: source, database: database),
          catalog: playbackQuery)
      } catch { self.error = NetworkErrorText.describe(error) }
    }
  }
  @ViewBuilder private func actions(for item: CatalogItem, query: MacCatalogQuery? = nil) -> some View {
    Button(ML("open")) { open(item, query ?? playbackQuery) }
    if item.isM3UMovie {
      Button(L("movie.play"), systemImage: "play.fill") { playM3UMovie(item) }
      MacDownloadAction(
        id: DownloadManager.idFor(m3uChannel: source.id, channelId: item.streamKey),
        play: { playM3UMovie(item) }
      ) {
        Task {
          do {
            try await MediaSelection.resolve(item, in: source, database: database).enqueueDownload()
          } catch { self.error = NetworkErrorText.describe(error) }
        }
      }
    }
    Button(
      ML(item.favorite ? "unfavorite" : "favorite"),
      systemImage: item.favorite ? "heart.slash" : "heart"
    ) {
      Task {
        do { try await item.setFavorite(!item.favorite, in: database) } catch {
          self.error = NetworkErrorText.describe(error)
        }
      }
    }
  }
}

struct MacFeaturedCarousel: View {
  @State private var heroHeight: CGFloat = 360
  let source: Playlist
  @State private var checkedSeries: Set<String> = []
  let items: [CatalogItem]
  let query: MacCatalogQuery
  let open: (CatalogItem, MacCatalogQuery) -> Void
  @Environment(\.appDatabase) private var database
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @Environment(\.scenePhase) private var phase
  private enum Page: Equatable { case title(String), collection }
  @State private var selection: Page?
  @State private var visible = false
  @State private var hovered = false
  private struct Metadata: Equatable, Sendable {
    let backdrop: String?
    let date: String?
    let genre: String?
    let rating: String?
  }
  @State private var metadata: [String: Metadata] = [:]

  private var page: Int {
    switch selection {
    case .title(let id): items.firstIndex { $0.id == id } ?? 0
    case .collection: items.count
    case nil: 0
    }
  }
  private var selected: CatalogItem? { items.indices.contains(page) ? items[page] : nil }
  static func allowsAutomaticPaging(visible: Bool, hovered: Bool, reduceMotion: Bool, voiceOver: Bool, phase: ScenePhase) -> Bool {
    visible && !hovered && !reduceMotion && !voiceOver && phase == .active
  }
  private var canAdvance: Bool {
    Self.allowsAutomaticPaging(visible: visible, hovered: hovered, reduceMotion: reduceMotion, voiceOver: voiceOver, phase: phase)
  }

  var body: some View {
    VStack(spacing: 6) {
      if let item = selected {
        Button {
          var featured = query
          featured.limit = items.count
          open(item, featured)
        } label: {
          ZStack(alignment: .bottomLeading) {
            if let url = MacDetailArtwork.url(metadata[item.streamKey]?.backdrop) {
              GeometryReader { box in
                CachedImage(url: url, width: box.size.width, height: box.size.height, cornerRadius: 0, contentMode: .fill)
              }
              LinearGradient(colors: [.black.opacity(0.84), .clear], startPoint: .bottom, endPoint: .top)
              copy(item).foregroundStyle(.white).padding(18)
            } else {
              HStack(spacing: 18) {
                CatalogArtwork(item: item, poster: true).frame(width: (heroHeight - 32) * 2 / 3)
                copy(item)
                Spacer()
              }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
          }.frame(height: heroHeight).background(.quaternary, in: .rect(cornerRadius: 10)).clipShape(.rect(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityValue(metadataLine(item))
      } else {
        NavigationLink(value: CatalogDestination.recentlyAdded(query.playlistID, query.kinds[0])) {
          Label(ML("see_all") + " · " + L("recently_added.title"), systemImage: "square.grid.2x2")
            .frame(maxWidth: .infinity).frame(height: heroHeight).background(.quaternary, in: .rect(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier("featured.collection")
      }
      HStack(spacing: 12) {
        Button { move(-1) } label: { Image(systemName: "chevron.backward") }
          .accessibilityLabel(ML("previous"))
        Text("\(page + 1) / \(items.count + 1)").monospacedDigit().foregroundStyle(.secondary)
        Button { move(1) } label: { Image(systemName: "chevron.forward") }
          .accessibilityLabel(ML("next"))
      }.buttonStyle(.borderless)
    }
    .onGeometryChange(for: CGFloat.self, of: { box in
      min(420, max(300, (box.size.width * 0.4).rounded()))
    }) { heroHeight = $0 }
    .onHover { hovered = $0 }
    .onGeometryChange(for: Bool.self, of: { box in
      guard let viewport = box.bounds(of: .scrollView) else { return false }
      return viewport.intersects(CGRect(origin: .zero, size: box.size))
    }) { visible = $0 }
    .task(id: canAdvance ? page : -1) {
      guard canAdvance else { return }
      do { try await Task.sleep(for: .seconds(7)) } catch { return }
      move(1)
    }
    .task(id: items.map(\.id)) {
      let client = XtreamAPIClient(playlist: source)
      for item in items {
        guard !Task.isCancelled else { return }
        guard let id = Int(item.streamKey) else { continue }
        do {
          if item.media == .vod {
            let record = DBVODStream.filter(Column("playlistId") == source.id && Column("streamId") == id)
            guard let row = try await database.read({ try record.fetchOne($0) }), !row.metadataLoaded else { continue }
            let info = try await client.getVODInfo(vodId: id)
            try Task.checkCancellation()
            try await database.write { db in
              guard let current = try Playlist.fetchOne(db, key: source.id), current.usesSameProvider(as: source),
                let latest = try record.fetchOne(db), latest.name == row.name, !latest.metadataLoaded else { return }
              _ = try DetailMetadata.storeMovie(info, streamId: id, playlistId: source.id, db: db)
            }
          } else {
            let record = DBSeries.filter(Column("playlistId") == source.id && Column("seriesId") == id)
            guard !checkedSeries.contains(item.id), let row = try await database.read({ try record.fetchOne($0) }),
                  MacDetailArtwork.url(row.backdropPath) == nil else { continue }
            let info = try await client.getSeriesInfo(seriesId: id)
            try Task.checkCancellation()
            try await database.write { db in
              guard let current = try Playlist.fetchOne(db, key: source.id), current.usesSameProvider(as: source),
                    let latest = try record.fetchOne(db), latest.name == row.name,
                    latest.backdropPath?.isEmpty != false else { return }
              try DetailMetadata.series(latest, response: info).update(db)
            }
            checkedSeries.insert(item.id)
          }
        } catch { if Task.isCancelled { return } }
      }
    }
    .task(id: items.map(\.id)) {
      if case .title(let id) = selection, !items.contains(where: { $0.id == id }) { selection = nil }
      if selection == nil { selection = items.first.map { .title($0.id) } }
      let featured = items
      do {
        for try await rows in ValueObservation.tracking({ db in
          var result: [String: Metadata] = [:]
          for item in featured {
            guard let id = Int(item.streamKey) else { continue }
            if item.media == .vod {
              if let row = try DBVODStream.filter(Column("playlistId") == item.playlistId && Column("streamId") == id).fetchOne(db) {
                result[item.streamKey] = Metadata(backdrop: row.backdropPath, date: row.releaseDate, genre: row.genre, rating: row.rating)
              }
            } else {
              if let row = try DBSeries.filter(Column("playlistId") == item.playlistId && Column("seriesId") == id).fetchOne(db) {
                result[item.streamKey] = Metadata(backdrop: row.backdropPath, date: row.releaseDate, genre: row.genre, rating: row.rating)
              }
            }
          }
          return result
        }).values(in: database.reader) {
          try Task.checkCancellation()
          metadata = rows
        }
      } catch { if !Task.isCancelled { metadata = [:] } }
    }
  }

  private func metadataLine(_ item: CatalogItem) -> String {
    let data = metadata[item.streamKey]
    return [DetailFormatting.year(from: data?.date), data?.genre, ContentRating.displayText(data?.rating ?? item.rating).map { "★ " + $0 }]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }

  private func copy(_ item: CatalogItem) -> some View {
    let line = metadataLine(item)
    return VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: item.title).font(.title.bold()).lineLimit(2)
      if !line.isEmpty { Text(verbatim: line).font(.subheadline).lineLimit(1) }
    }
  }

  private func move(_ delta: Int) {
    let next = (page + items.count + 1 + delta) % (items.count + 1)
    selection = items.indices.contains(next) ? .title(items[next].id) : .collection
  }
}

private struct MacCatalogHistoryShelf: View {
  let source: Playlist
  let kind: MediaKind
  @Query<RecentWatchHistoryRequest> private var rows: [DBWatchHistory]

  init(source: Playlist, kind: MediaKind) {
    self.source = source
    self.kind = kind
    _rows = Query(RecentWatchHistoryRequest(playlistId: source.id, limit: 20, type: kind.rawValue), in: \.appDatabase)
  }

  var body: some View {
    if !rows.isEmpty {
      let title = L("continue_watching.title")
      MacHistoryShelf(source: source, rows: rows, title: title) {
        NavigationLink(value: CatalogDestination.history(source.id, kind)) { Text(ML("see_all")) }
          .buttonStyle(.link).accessibilityLabel(ML("see_all") + " · " + title)
      }.padding(.horizontal, 26).padding(.bottom, 12)
    }
  }
}

struct MacCatalogHistory: View {
  let source: Playlist
  let kind: MediaKind
  @State private var search = ""
  var body: some View {
    MacHistory(source: source, query: search, initialScope: kind.rawValue)
      .navigationTitle(L("history.title"))
      .searchable(text: $search, placement: .toolbar, prompt: Text(L("history.search_placeholder")))
  }
}

struct MacCategoryCollection: View {
  let source: Playlist
  let kind: MediaKind
  let category: CatalogGroup
  let open: (CatalogItem, MacCatalogQuery) -> Void
  @State private var search = ""

  var body: some View {
    MacCatalogView(source: source, kinds: [kind], title: category.name, search: search,
      favorites: false, isSearch: false, category: category, open: open)
      .navigationTitle(category.name)
      .searchable(text: $search, placement: .toolbar, prompt: Text(L("search.placeholder")))
  }
}

private struct MacCategoryShelf<Card: View>: View {
  @Environment(\.appDatabase) private var database
  let group: CatalogGroup
  let query: MacCatalogQuery
  let kind: MediaKind
  let hide: () -> Void
  let card: (CatalogItem) -> Card
  @State private var limit = 12
  @State private var items: [CatalogItem]?
  @State private var more = false
  @State private var retry = 0
  @State private var error: String?

  private var page: MacCatalogQuery {
    var page = query
    page.limit = limit + 1
    return page
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(verbatim: group.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
        Spacer()
        if items?.isEmpty == false {
          NavigationLink(value: CatalogDestination.category(query.playlistID, kind, group)) {
            Text(ML("see_all"))
          }.buttonStyle(.link).accessibilityLabel(ML("see_all") + " · " + group.name)
        }
      }
      .contextMenu {
        Button(L("kit.menu.hide_category"), systemImage: "eye.slash", action: hide)
      }
      if let error {
        HStack {
          Label(error, systemImage: "exclamationmark.triangle")
          Button(L("common.try_again")) { retry += 1 }
        }
      } else if let items, !items.isEmpty {
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 14) {
            ForEach(items) { item in
              card(item).frame(width: 128)
                .onAppear {
                  if more, items.count == limit, item.id == items.last?.id { limit += 12 }
                }
            }
          }
        }
      } else if items != nil {
        Text(L(kind == .series ? "series.empty.no_in_category" : "vod.empty.no_in_category"))
          .font(.caption).foregroundStyle(.secondary)
      } else {
        ProgressView().controlSize(.small).frame(height: 192)
      }
    }
    .task(id: PageRequest(query: page, retry: retry)) {
      let request = page
      error = nil
      do {
        for try await rows in ValueObservation.tracking({ try request.fetch($0) }).values(in: database.reader) {
          try Task.checkCancellation()
          more = rows.count == request.limit
          items = Array(rows.prefix(request.limit - 1))
        }
      } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
    }
  }
  private struct PageRequest: Hashable { let query: MacCatalogQuery; let retry: Int }
}

struct MacCategoryPicker: View {
  let groups: [CatalogGroup]
  let kind: MediaKind
  @Binding var selection: String?
  var playlistID: UUID? = nil
  @Environment(\.appDatabase) private var database
  @ObservedObject private var hidden = HiddenCategoryStore.shared
  @State private var counts: [String: Int]?
  @State private var presented = false
  @State private var search = ""
  @FocusState private var searchFocused: Bool

  private func display(_ group: CatalogGroup) -> String {
    if group.id == PlaylistContentStore.uncategorizedCategoryId { return L("content.uncategorized") }
    return kind == .m3u ? M3UContentStore.displayName(forGroup: group.name) : group.name
  }

  var body: some View {
    let selected = groups.first { $0.id == selection }.map(display)
    Button {
      search = ""
      presented = true
    } label: {
      Label(
        selected ?? L("category_picker.title"), systemImage: "line.3.horizontal.decrease.circle"
      )
      .lineLimit(1)
    }
    .help(L("category_picker.title"))
    .popover(isPresented: $presented) {
      VStack(alignment: .leading, spacing: 0) {
        TextField(L("category_picker.search_placeholder"), text: $search)
          .textFieldStyle(.roundedBorder).focused($searchFocused).padding(10)
        Divider()
        let query = CatalogTextSearch.Query(search)
        let isBlank = search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let matches = isBlank ? groups : groups.filter { query.matches(display($0)) }
        let excluded = playlistID.map { hidden.hiddenIds(playlistId: $0, type: kind.rawValue) } ?? []
        let hiddenMatches = matches.filter { excluded.contains($0.id) }
        if matches.isEmpty && !isBlank {
          ContentUnavailableView(
            L("favorites.empty.no_result.title"), systemImage: "magnifyingglass")
        } else {
          List {
            if isBlank { choice(L("search.all"), id: nil) }
            ForEach(matches.filter { !excluded.contains($0.id) }) { group in row(group, isHidden: false) }
            if !hiddenMatches.isEmpty {
              Section(L("category_picker.hidden_section")) {
                ForEach(hiddenMatches) { group in row(group, isHidden: true) }
              }
            }
          }.listStyle(.plain)
        }
      }.frame(width: 300, height: 340).onAppear { searchFocused = true }
        .task(id: playlistID) {
          guard let playlistID else { return }
          let query = MacCatalogQuery(playlistID: playlistID, kinds: [kind])
          do {
            for try await value in ValueObservation.tracking({ try query.categoryCounts($0) }).values(in: database.reader) {
              try Task.checkCancellation()
              counts = value
            }
          } catch { if !Task.isCancelled { counts = nil } }
        }
    }
  }

  private func row(_ group: CatalogGroup, isHidden: Bool) -> some View {
    let name = display(group)
    let visibility = L(isHidden ? "category_picker.unhide" : "category_picker.hide")
    return HStack(spacing: 6) {
      if isHidden {
        Button { setHidden(false, group) } label: {
          Text(verbatim: name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary)
          .accessibilityLabel(name).accessibilityHint(visibility)
      } else {
        choice(name, id: group.id)
      }
      if let counts {
        Text(counts[group.id, default: 0], format: .number)
          .monospacedDigit().foregroundStyle(.secondary).font(.caption)
      }
      if playlistID != nil {
        Button { setHidden(!isHidden, group) } label: {
          Image(systemName: isHidden ? "eye" : "eye.slash")
        }.buttonStyle(.borderless).help(visibility)
          .accessibilityLabel(visibility + " · " + name)
      }
    }.contextMenu {
      if playlistID != nil {
        Button(visibility, systemImage: isHidden ? "eye" : "eye.slash") { setHidden(!isHidden, group) }
      }
    }
  }

  private func setHidden(_ value: Bool, _ group: CatalogGroup) {
    guard let playlistID else { return }
    if value && selection == group.id { selection = nil }
    hidden.setHidden(value, playlistId: playlistID, type: kind.rawValue, categoryId: group.id)
  }

  private func choice(_ name: String, id: String?) -> some View {
    Button {
      selection = id
      presented = false
    } label: {
      HStack {
        Text(verbatim: name).lineLimit(1)
        Spacer()
        if selection == id { Image(systemName: "checkmark").foregroundStyle(.tint) }
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(name)
      .accessibilityAddTraits(selection == id ? .isSelected : [])
  }
}

struct CatalogArtwork: View {
  let item: CatalogItem
  let poster: Bool
  let artworkURL: URL?

  init(item: CatalogItem, poster: Bool) {
    self.init(item: item, poster: poster, artworkURL: item.artwork.flatMap(URL.init(string:)))
  }

  init(item: CatalogItem, poster: Bool, artworkURL: URL?) {
    self.item = item
    self.poster = poster
    self.artworkURL = artworkURL
  }
  var body: some View {
    Rectangle().fill(.quaternary)
      .aspectRatio(poster ? 2 / 3 : 16 / 9, contentMode: .fit)
      .overlay {
        GeometryReader { box in
          // Nearby window widths share the same decoded thumbnail.
          let width = box.size.width
          let decodeWidth: CGFloat = width <= 48 ? 48 : width <= 160 ? 160 : max(225, ceil(width / 64) * 64)
          CachedImage(url: artworkURL, width: width, height: box.size.height,
                      cornerRadius: 7, contentMode: poster ? .fill : .fit,
                      iconName: item.displayMedia.symbol, loadProfile: .grid,
                      decodeWidth: decodeWidth, decodeHeight: decodeWidth * (poster ? 1.5 : 9 / 16),
                      showsTile: !poster)
        }
      }
      .clipShape(.rect(cornerRadius: 7))
      .accessibilityHidden(true)
  }
}


private extension CatalogItem {
  func programme(in snapshot: EPGSnapshot?) -> EPGProgramme? {
    guard let snapshot, !usesPoster else { return nil }
    let id = EPGConstants.normalizeChannelKey(epgID)
    let name = EPGConstants.normalizeChannelKey(epgName) ?? EPGConstants.normalizeChannelKey(title)
    return snapshot[id]?.now ?? snapshot[name]?.now
  }
}

struct MacChannelProgramme: View {
  let item: CatalogItem
  var inTable = false
  @Environment(\.epgSnapshot) private var snapshot

  var body: some View {
    if snapshot != nil {
      Text(verbatim: item.programme(in: snapshot)?.title ?? " ")
        .font(inTable ? .body : .caption).foregroundStyle(.secondary).lineLimit(1)
    }
  }
}

struct MacChannelProgrammeAccessibility: ViewModifier {
  let item: CatalogItem
  @Environment(\.epgSnapshot) private var snapshot

  func body(content: Content) -> some View {
    if item.usesPoster {
      content
    } else {
      content.accessibilityValue(item.programme(in: snapshot).map {
        L("epg.a11y.now_playing_format", $0.title)
      } ?? "")
    }
  }
}
