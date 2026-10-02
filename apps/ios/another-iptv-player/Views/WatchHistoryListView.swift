import SwiftUI
import Combine
import GRDBQuery
import GRDB

/// Tam izleme geçmişi grid ekranı.
/// - Parameters:
///   - `playlist`: kimin geçmişi
///   - `typeFilter`: `"live"` / `"vod"` / `"series"` / nil (M3U: tümü)
///   - `onPlay`: öğeye tıklandığında çağrılır; her ekran kendi oynatma mantığını uygular.
struct WatchHistoryListView: View {
    let playlist: Playlist
    let typeFilter: String?
    let onPlay: (DBWatchHistory) -> Void

    /// `nil` until the database has answered; see `LoadedRequest`.
    @Query<LoadedRequest<RecentWatchHistoryRequest>> private var loadedItems: [DBWatchHistory]?
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearConfirm = false
    @Environment(\.appDatabase) private var appDatabase

    init(playlist: Playlist, typeFilter: String?, onPlay: @escaping (DBWatchHistory) -> Void) {
        self.playlist = playlist
        self.typeFilter = typeFilter
        self.onPlay = onPlay
        _loadedItems = Query(
            LoadedRequest(RecentWatchHistoryRequest(playlistId: playlist.id, limit: 500, type: typeFilter)),
            in: \.appDatabase
        )
    }

    private func filtered(_ items: [DBWatchHistory]) -> [DBWatchHistory] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        let query = CatalogTextSearch.Query(q)
        return items.filter { query.matches($0.title) }
    }

    private var navTitle: String {
        switch typeFilter {
        case "live":   return L("history.title.live")
        case "vod":    return L("history.title.vod")
        case "series": return L("history.title.series")
        default:       return L("history.title")
        }
    }

    var body: some View {
        let items = loadedItems ?? []
        // Tek geçiş: `filtered` computed'ını hem isEmpty hem ForEach için ayrı ayrı
        // okumak her render'da 500 satırı iki kez normalize edip tarıyordu.
        let results = filtered(items)
        Group {
            if loadedItems == nil {
                // Nothing delivered yet: drawing "No history" here would flash it
                // in front of a history that arrives a moment later.
                Color.clear
            } else if items.isEmpty {
                CatalogEmptyView(.message(
                    title: L("history.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: L("history.empty.message")
                ))
            } else if results.isEmpty {
                CatalogEmptyView(.noSearchResults)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)],
                        spacing: 20
                    ) {
                        ForEach(results) { item in
                            Button {
                                onPlay(item)
                            } label: {
                                HistoryCard(item: item, width: 160, height: 95, loadProfile: .grid)
                            }
                            .buttonStyle(.cardPress)
                            .accessibilityIdentifier(HistoryCard.accessibilityIdentifier(for: item, in: playlist))
                            .historyItemContextMenu(item, onPlay: onPlay)
                        }
                    }
                    .padding(16)
                    // Keyed on the unfiltered list: a removed card lets the others
                    // reflow, typing in the search field stays instant.
                    .animation(.default, value: items.map(\.id))
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: L("history.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                debouncedQuery = ""
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onDisappear { debounceTask?.cancel(); debounceTask = nil }
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L("history.clear.label"))
                    // Attached to the button so the dialog is anchored to it (a
                    // popover on iPad and on iOS 26) instead of a centred alert.
                    .confirmationDialog(
                        L("history.clear.title"),
                        isPresented: $showClearConfirm
                    ) {
                        Button(L("history.clear.label"), role: .destructive) {
                            Task { await clearHistory() }
                        }
                        Button(L("common.cancel"), role: .cancel) { }
                    } message: {
                        Text(clearConfirmMessage)
                    }
                }
            }
        }
    }

    private var clearConfirmMessage: String {
        switch typeFilter {
        case "live":   return L("history.clear.message.live")
        case "vod":    return L("history.clear.message.vod")
        case "series": return L("history.clear.message.series")
        default:       return L("history.clear.message.all")
        }
    }

    private func clearHistory() async {
        let pid = playlist.id
        let type = typeFilter
        do {
            try await appDatabase.write { db in
                if let type {
                    try db.execute(
                        sql: "DELETE FROM watchHistory WHERE playlistId = ? AND type = ?",
                        arguments: [pid, type]
                    )
                } else {
                    try db.execute(
                        sql: "DELETE FROM watchHistory WHERE playlistId = ?",
                        arguments: [pid]
                    )
                }
            }
        } catch {
            Log.error("WatchHistory", "clear failed: \(error)")
        }
    }
}

// MARK: - First value

/// Wraps a list request so that "the database has not answered yet" (`nil`) and
/// "the list is empty" (`[]`) are different values.
///
/// The list requests deliver asynchronously on purpose (a synchronous first read
/// of a long list would run on the main thread), so the first body of a screen
/// gets the request's default value. With `[]` as that default the screen cannot
/// tell the two cases apart and draws its empty state for a frame before the rows
/// replace it. The wrapper changes neither the scheduling nor the observation,
/// only the default value.
struct LoadedRequest<Base: Queryable>: Queryable {
    static var defaultValue: Base.Value? { nil }

    let base: Base

    init(_ base: Base) {
        self.base = base
    }

    func publisher(in context: Base.Context) throws -> AnyPublisher<Base.Value?, Base.ValuePublisher.Failure> {
        try base.publisher(in: context)
            .map { $0 as Base.Value? }
            .eraseToAnyPublisher()
    }
}
