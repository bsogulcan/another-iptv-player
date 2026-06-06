import SwiftUI
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

    @Query<RecentWatchHistoryRequest> private var items: [DBWatchHistory]
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @Environment(\.appDatabase) private var appDatabase

    init(playlist: Playlist, typeFilter: String?, onPlay: @escaping (DBWatchHistory) -> Void) {
        self.playlist = playlist
        self.typeFilter = typeFilter
        self.onPlay = onPlay
        _items = Query(
            RecentWatchHistoryRequest(playlistId: playlist.id, limit: 500, type: typeFilter),
            in: \.appDatabase
        )
    }

    private var filtered: [DBWatchHistory] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { CatalogTextSearch.matches(search: q, text: $0.title) }
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
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    L("history.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L("history.empty.message"))
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    L("favorites.empty.no_result.title"),
                    systemImage: "magnifyingglass",
                    description: Text(L("category_picker.not_found.message"))
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                        spacing: 20
                    ) {
                        ForEach(filtered) { item in
                            HistoryCardGridItem(item: item) {
                                onPlay(item)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, prompt: L("history.search_placeholder"))
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L("history.clear.label"))
                }
            }
        }
        .alert(L("history.clear.title"), isPresented: $showClearConfirm) {
            Button(L("common.cancel"), role: .cancel) { }
            Button(L("common.confirm_delete_yes"), role: .destructive) {
                Task { await clearHistory() }
            }
        } message: {
            Text(clearAlertMessage)
        }
    }

    private var clearAlertMessage: String {
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
            print("WatchHistory clear error: \(error)")
        }
    }
}

/// ContinueWatchingRow'daki `HistoryCard`'ın grid eş değeri — biraz daha büyük kart,
/// sol altta progress; başlık + altyazı aşağıda.
private struct HistoryCardGridItem: View {
    let item: DBWatchHistory
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    CachedImage(
                        url: item.imageURL.flatMap { URL(string: $0) },
                        width: 160,
                        height: 95,
                        cornerRadius: 10,
                        contentMode: .fill,
                        iconName: item.type == "live" ? "tv" : "film"
                    )

                    if item.type != "live" && item.durationMs > 0 {
                        let progress = Double(item.lastTimeMs) / Double(item.durationMs)
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.black.opacity(0.55))
                                .frame(height: 3)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 160 * min(max(progress, 0), 1), height: 3)
                        }
                    }
                }
                .frame(width: 160, height: 95)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle = item.secondaryTitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 160, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
