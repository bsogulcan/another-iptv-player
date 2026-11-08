import GRDB
import SwiftUI

struct MacLiveChannelPicker: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var player: DesktopPlayback
  @ObservedObject private var hidden = HiddenCategoryStore.shared
  let source: Playlist
  let current: CatalogItem
  let order: CatalogOrder
  let didTune: () -> Void
  @State private var group: String?
  @State private var search = ""
  @State private var groups: [CatalogGroup] = []
  @State private var channels: [CatalogItem] = []
  @State private var limit = 100
  @State private var more = false
  @State private var loading = true
  @State private var failure: String?
  @State private var groupFailure: String?
  @State private var choice: CatalogItem?
  @State private var retry = 0

  init(source: Playlist, current: CatalogItem, order: CatalogOrder, didTune: @escaping () -> Void) {
    self.source = source
    self.current = current
    self.order = order
    self.didTune = didTune
    _group = State(initialValue: current.groupKey)
  }

  private var kind: MediaKind { source.kind == .xtream ? .live : .m3u }
  private var base: MacCatalogQuery {
    MacCatalogQuery(playlistID: source.id, kinds: [kind], order: order,
      hidden: [kind: hidden.hiddenIds(playlistId: source.id, type: kind.rawValue)], liveChannelsOnly: true)
  }
  private var request: MacCatalogQuery {
    var query = base
    query.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
    query.selectedGroup = group
    query.limit = limit + 1
    return query
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        TextField(L("search.placeholder"), text: $search).textFieldStyle(.roundedBorder)
        MacCategoryPicker(groups: groups, kind: kind, selection: $group)
      }.padding(10)
      Divider()
      if let failure = groupFailure ?? failure {
        ContentUnavailableView {
          Label(L("loading.error.title"), systemImage: "exclamationmark.triangle")
        } description: { Text(failure) } actions: {
          Button(L("common.try_again")) { retry += 1 }
        }
      } else if loading && channels.isEmpty {
        ProgressView().frame(maxHeight: .infinity)
      } else if channels.isEmpty {
        ContentUnavailableView(L("favorites.empty.no_result.title"), systemImage: "magnifyingglass")
      } else {
        List {
          ForEach(channels) { item in
            Button {
              if item.id == current.id { didTune() } else { choice = item }
            } label: {
              HStack {
                CatalogArtwork(item: item, poster: false).frame(width: 42)
                VStack(alignment: .leading) {
                  Text(verbatim: item.title).lineLimit(1)
                  MacChannelProgramme(item: item)
                }
                Spacer()
                if item.id == current.id { Image(systemName: "speaker.wave.2") }
              }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.title)
              .accessibilityAddTraits(item.id == current.id ? .isSelected : [])
              .modifier(MacChannelProgrammeAccessibility(item: item))
              .onAppear {
                if more, channels.count == limit, item.id == channels.last?.id { limit += 100 }
              }
          }
          if more {
            Button(ML("load_more")) { limit += 100 }
          }
        }.listStyle(.plain).disabled(loading)
      }
    }.frame(width: 380, height: 400)
      .modifier(MacBrowseGuide(playlistId: source.id))
      .onChange(of: search) { _, _ in resetPage() }
      .onChange(of: group) { _, _ in resetPage() }
      .task(id: ChannelPage(query: base, retry: retry)) {
        groupFailure = nil
        let query = base
        do {
          for try await value in ValueObservation.tracking({ try query.liveChannelGroups($0) })
            .values(in: database.reader) {
            try Task.checkCancellation()
            groups = value
            if let group, !groups.contains(where: { $0.id == group }) { self.group = nil }
          }
        } catch { if !Task.isCancelled { groupFailure = NetworkErrorText.describe(error) } }
      }
      .task(id: ChannelPage(query: request, retry: retry)) {
        let query = request
        failure = nil
        loading = true
        do {
          if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
          for try await value in ValueObservation.tracking({ try query.fetch($0) }).values(in: database.reader) {
            try Task.checkCancellation()
            more = value.count == query.limit
            channels = Array(value.prefix(query.limit - 1))
            loading = false
          }
        } catch { if !Task.isCancelled { failure = NetworkErrorText.describe(error) } }
      }
      .task(id: choice) {
        guard let choice else { return }
        var queue = base
        queue.selectedGroup = choice.groupKey
        queue.limit = Int.max
        do {
          try await player.tune(choice, in: source, catalog: queue)
          didTune()
        } catch {
          if !Task.isCancelled { failure = NetworkErrorText.describe(error); self.choice = nil }
        }
      }
  }

  private func resetPage() {
    channels = []
    loading = true
    limit = 100
  }

  private struct ChannelPage: Hashable {
    let query: MacCatalogQuery
    let retry: Int
  }
}
