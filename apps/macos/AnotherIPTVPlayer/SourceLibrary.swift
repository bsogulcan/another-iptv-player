import GRDB
import GRDBQuery
import SwiftUI

private enum WorkspacePage: Hashable {
  case sources, discover
  case add(PlaylistKind)
  case edit(UUID)
  case catalog(MediaKind)
  case favorites, search, history, downloads, guide, settings
  var title: String {
    switch self {
    case .sources: L("playlists.title")
    case .discover: ML("discover")
    case .add: L("playlist_type.title")
    case .edit: L("common.edit")
    case .catalog(let kind): kind.title
    case .favorites: L("favorites.title")
    case .search: L("search.title")
    case .guide: L("epg.guide.title")
    case .history: L("history.title")
    case .downloads: L("download.title")
    case .settings: L("dashboard.settings")
    }
  }
}

enum CatalogDestination: Hashable {
  case item(CatalogItem, MacCatalogQuery?)
  case recentlyAdded(UUID, MediaKind)
  case category(UUID, MediaKind, CatalogGroup)
  case history(UUID, MediaKind)
}

struct SourceLibrary: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var language: LocalizationManager
  @EnvironmentObject private var playback: DesktopPlayback
  @State private var channelLaunch: Task<Void, Never>?
  @Query<PlaylistRequest> private var sources: [Playlist]?
  @AppStorage("lastPlaylistId") private var activeID = ""
  @AppStorage("mac.lastXtreamSection") private var lastXtreamSection = ""
  @AppStorage("mac.lastM3USection") private var lastM3USection = ""
  @State private var page: WorkspacePage? = .sources
  @State private var historyScope = ""
  @State private var favoriteEntryKind: MediaKind?
  @State private var detailPath: [CatalogDestination] = []
  @State private var query = ""
  @State private var removing: Playlist?
  @State private var failure: String?
  @State private var restored = false
  @State private var showEphemeralNotice = AppDatabase.isEphemeral

  init() { _sources = Query(PlaylistRequest(), in: \.appDatabase) }
  private var source: Playlist? { sources?.first { $0.id.uuidString == activeID } }
  private var current: WorkspacePage { page ?? .sources }
  private var activeKinds: [MediaKind] { source?.kind == .m3u ? [.m3u] : [.live, .vod, .series] }

  var body: some View {
    NavigationSplitView {
      List(selection: $page) {
        Label(L("playlists.title"), systemImage: "rectangle.stack").tag(WorkspacePage.sources)
        if let source {
          Section(source.name) {
            Label(ML("discover"), systemImage: "safari").tag(WorkspacePage.discover)
            ForEach(activeKinds, id: \.self) { kind in
              Label(kind.title, systemImage: kind.symbol).tag(WorkspacePage.catalog(kind))
            }
            if source.epgEnabled {
              Label(L("epg.guide.title"), systemImage: "calendar.badge.clock").tag(
                WorkspacePage.guide)
            }
            Label(L("search.title"), systemImage: "magnifyingglass").tag(WorkspacePage.search)
            Label(L("favorites.title"), systemImage: "heart").tag(WorkspacePage.favorites)
            Label(L("history.title"), systemImage: "clock").tag(WorkspacePage.history)
            Label(L("download.title"), systemImage: "arrow.down.circle").tag(
              WorkspacePage.downloads)
          }
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Another IPTV Player")
      .navigationSplitViewColumnWidth(min: 185, ideal: 214, max: 300)
      .safeAreaInset(edge: .bottom, alignment: .leading) {
        Button {
          navigate(.settings)
        } label: {
          Label(L("dashboard.settings"), systemImage: "gearshape")
        }
        .buttonStyle(.borderless).foregroundStyle(
          current == .settings ? Color.accentColor : Color.secondary
        )
        .accessibilityAddTraits(current == .settings ? .isSelected : [])
        .padding(.horizontal, 22).padding(.vertical, 14)
      }
    } detail: {
      NavigationStack(path: $detailPath) {
        Group {
          switch current {
          case .sources:
            playlistsPage
          case .discover:
            if let source {
              MacDiscoverView(
                source: source, open: { open($0, source: source) },
                browse: { navigate(.catalog($0)) }, history: { historyScope = $0; navigate(.history) }
              )
              .id(source.id)
            } else {
              playlistsPage
            }
          case .add(let kind):
            SourceEditor(kind: kind, saved: activate, cancel: { navigate(.sources) }).id(current)
          case .edit(let id):
            if let existing = sources?.first(where: { $0.id == id }) {
              SourceEditor(
                kind: existing.kind, editing: existing, saved: activate,
                cancel: { navigate(.sources) }
              ).id(current)
            }
          case .settings:
            MacPreferences(source: source, edit: { navigate(.edit($0.id)) })
          case .guide:
            if let source {
              MacGuide(source: source, settings: { navigate(.settings) }).id(source.id)
            }
          case .history:
            if let source {
              MacHistory(source: source, query: query, initialScope: historyScope).searchable(
                text: $query, placement: .toolbar, prompt: Text(L("history.search_placeholder")))
            }
          case .downloads:
            if let source {
              MacDownloads(source: source, query: query).searchable(
                text: $query, placement: .toolbar, prompt: Text(L("download.search_placeholder")))
            }
          case .catalog, .favorites, .search:
            if let source {
              MacCatalogView(
                source: source, kinds: kinds(for: current), title: current.title,
                search: query, favorites: current == .favorites, isSearch: current == .search, initialFavoriteKind: favoriteEntryKind,
                open: { open($0, source: source, query: $1) }
              )
              .id("\(source.id)/\(current)")
              .toolbar {
                if case .catalog(let kind) = current {
                  ToolbarItem {
                    Button(L("favorites.title"), systemImage: "heart") {
                      favoriteEntryKind = kind
                      navigate(.favorites)
                    }.accessibilityIdentifier("catalog-favorites")
                  }
                }
              }
              .searchable(text: $query, placement: .toolbar, prompt: Text(L(current == .favorites ? "favorites.search_placeholder" : "search.placeholder")))
            } else {
              playlistsPage
            }
          }
        }
        .background(.background)
        .navigationTitle(current.title)
        .navigationDestination(for: CatalogDestination.self) { destination in
          if let source {
            switch destination {
            case .item(let item, let query) where source.id == item.playlistId:
              MacMediaDetail(item: item, source: source, catalog: query)
            case .recentlyAdded(let id, let kind) where source.id == id:
              MacCatalogView(source: source, kinds: [kind], title: L("recently_added.title"), search: "",
                favorites: false, isSearch: false, recentOnly: true,
                open: { open($0, source: source, query: $1) })
                .navigationTitle(L("recently_added.title"))
            case .category(let id, let kind, let category) where source.id == id:
              MacCategoryCollection(source: source, kind: kind, category: category,
                open: { open($0, source: source, query: $1) })
            case .history(let id, let kind) where source.id == id:
              MacCatalogHistory(source: source, kind: kind)
            default: EmptyView()
            }
          }
        }
      }
    }
    .modifier(MacBrowseGuide(playlistId: source?.id))
    .id(language.selectedLanguage)
    .task(id: source?.id) {
      EPGStore.shared.setActivePlaylist(source)
      if let source, source.epgEnabled { await EPGStore.shared.refreshIfStale(playlist: source) }
    }
    .onReceive(playback.detailRequests) { item in
      guard item.playlistId == source?.id else { return }
      if case .item(let current, _)? = detailPath.last, current.id == item.id { return }
      detailPath.append(.item(item, nil))
    }
    .focusedSceneValue(\.showIPTVSettings, {
      playback.expanded = false
      navigate(.settings)
    })
    .onChange(of: page) { previous, next in
      if previous == .history && next != .history { historyScope = "" }
      if previous == .favorites && next != .favorites { favoriteEntryKind = nil }
      if let source {
        switch next {
        case .catalog(let kind):
          if source.kind == .m3u { lastM3USection = kind.rawValue } else { lastXtreamSection = kind.rawValue }
        case .discover:
          if source.kind == .m3u { lastM3USection = "" } else { lastXtreamSection = "" }
        default: break
        }
      }
      detailPath.removeAll()
      query = ""
    }
    .onChange(of: sources?.map(\.id), initial: true) { _, ids in
      guard let ids else { return }
      if case .edit(let id) = current, !ids.contains(id) { navigate(.sources) }
      if !restored {
        restored = true
        if let source { activate(source) }
      } else if !activeID.isEmpty, source == nil {
        activeID = ""
        navigate(.sources)
      }
    }
    .confirmationDialog(
      L("playlists.delete.title"),
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      presenting: removing
    ) { source in
      Button(L("common.delete"), role: .destructive) { delete(source) }
      Button(L("common.cancel"), role: .cancel) {}
    } message: { source in
      Text(L("onboarding.delete.title_named", source.name))
    }
    .alert(
      L("common.error"),
      isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button(L("common.ok")) {}
    } message: {
      Text(failure ?? "")
    }
    .alert(L("db.error.ephemeral_title"), isPresented: $showEphemeralNotice) {
      Button(L("common.ok")) {}
    } message: {
      Text(L("db.error.ephemeral_message"))
    }
    .modifier(MacArtworkPresentation())
  }

  private func kinds(for page: WorkspacePage) -> [MediaKind] {
    if case .catalog(let kind) = page { return [kind] }
    return activeKinds
  }

  @ViewBuilder private var playlistsPage: some View {
    if let sources {
      if sources.isEmpty {
        ContentUnavailableView {
          Label(L("playlists.empty.title"), systemImage: "rectangle.stack")
        } description: {
          Text(L("playlists.empty.message"))
        } actions: {
          addMenu.controlSize(.large).fixedSize()
        }
      } else {
        List {
          ForEach(sources.sorted { $0.createdAt < $1.createdAt }) { source in
            HStack(spacing: 12) {
              Image(systemName: source.kind == .m3u ? "list.bullet.rectangle" : "server.rack")
                .font(.title2).foregroundStyle(.tint).frame(width: 32)
              Button {
                activate(source)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(verbatim: source.name).font(.headline)
                  Text(verbatim: source.displaySource).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
              }.buttonStyle(.plain)
              Menu {
                Button(L("common.edit")) { navigate(.edit(source.id)) }
                Button(L("common.delete"), role: .destructive) { removing = source }
              } label: {
                Label(L("common.edit"), systemImage: "ellipsis.circle")
              }
              .menuStyle(.borderlessButton).fixedSize().labelStyle(.iconOnly)
            }.padding(.vertical, 7)
          }
        }.toolbar { ToolbarItem { addMenu } }
      }
    } else {
      ProgressView()
    }
  }
  private var addMenu: some View {
    Menu {
      Button(L("playlist_type.xtream.title")) { navigate(.add(.xtream)) }
      Button(L("playlist_type.m3u.title")) { navigate(.add(.m3u)) }
    } label: {
      Label(L("playlists.empty.add_button"), systemImage: "plus")
    }
  }
  private func open(_ item: CatalogItem, source: Playlist, query: MacCatalogQuery? = nil) {
    channelLaunch?.cancel()
    if item.media == .live || (item.media == .m3u && !item.isM3UMovie) {
      channelLaunch = Task {
        do {
          let target = try await MediaSelection.resolve(item, in: source, database: database)
          try Task.checkCancellation()
          playback.start(target, catalog: query)
        } catch { if !Task.isCancelled { failure = NetworkErrorText.describe(error) } }
      }
    } else {
      detailPath.append(.item(item, query))
    }
  }
  private func activate(_ source: Playlist) {
    if playback.current?.playlistId != source.id { playback.close() }
    activeID = source.id.uuidString
    let saved = source.kind == .m3u ? lastM3USection : lastXtreamSection
    if let kind = MediaKind(rawValue: saved), (source.kind == .m3u) == (kind == .m3u) {
      navigate(.catalog(kind))
    } else {
      navigate(.discover)
    }
  }
  private func navigate(_ next: WorkspacePage) {
    query = ""
    detailPath.removeAll()
    page = next
  }
  private func delete(_ source: Playlist) {
    Task {
      do {
        _ = try await database.write { db in try source.delete(db) }
        HiddenCategoryStore.shared.removeAll(playlistId: source.id)
        DownloadManager.shared.cleanupPlaylist(playlistId: source.id)
        ImportedSubtitleStore.removeAll(playlistId: source.id)
        SubtitleDelayStore.removeAll(playlistId: source.id)
        EPGStore.forgetLineReservation(playlistId: source.id)
      } catch { failure = NetworkErrorText.describe(error) }
    }
  }
}

struct SettingsActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
  var showIPTVSettings: (() -> Void)? {
    get { self[SettingsActionKey.self] }
    set { self[SettingsActionKey.self] = newValue }
  }
}
struct WorkspaceCommands: Commands {
  @FocusedValue(\.showIPTVSettings) private var show
  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button(L("dashboard.settings")) { show?() }.keyboardShortcut(
        ",", modifiers: .command, localization: .custom
      ).disabled(show == nil)
    }
  }
}


struct MacBrowseGuide: ViewModifier {
  let playlistId: UUID?
  @ObservedObject private var guide = EPGStore.shared

  func body(content: Content) -> some View {
    content.environment(\.epgSnapshot, guide.snapshot(for: playlistId))
  }
}
