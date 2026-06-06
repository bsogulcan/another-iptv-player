import Foundation
import GRDB
import Combine

/// M3U playlist için aktif kanalları bellekte tutar. Xtream'in PlaylistContentStore'undan ayrıdır.
///
/// 310K+ kanalda grouping main thread'i durdurmasın diye `Task.detached`'te yapılır;
/// `loadToken` ile eşzamanlı load isteklerinde yalnızca sonuncusu store'a uygulanır.
@MainActor
final class M3UContentStore: ObservableObject {
    static let shared = M3UContentStore()

    @Published private(set) var activePlaylistId: UUID?
    @Published var isLoading = false
    @Published var loadError: String?

    @Published private(set) var channels: [DBM3UChannel] = []
    @Published private(set) var channelsByGroup: [String: [DBM3UChannel]] = [:]
    @Published private(set) var groupNames: [String] = []

    /// `group-title` boş olan kanallar için kullanılan etiket.
    static let ungroupedLabel = "Diğer"

    /// Aktif playlist'in filtre bayrağı — toggle değişince güncellenir ve sonraki load'da uygulanır.
    private var filterAdultContent: Bool = false

    private var loadToken: UUID?

    private init() {}

    // MARK: - Public API

    func loadPlaylist(_ playlist: Playlist) async {
        let token = UUID()
        loadToken = token
        loadError = nil

        if activePlaylistId != playlist.id {
            clearLists()
            activePlaylistId = playlist.id
        }
        filterAdultContent = playlist.filterAdultContent

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await fetchChannels(playlistId: playlist.id)
            guard loadToken == token else { return }
            let visible = applyAdultFilter(fetched, enabled: filterAdultContent)
            let grouped = await groupOffMain(visible)
            guard loadToken == token else { return }
            apply(channels: visible, grouping: grouped)
        } catch {
            guard loadToken == token else { return }
            loadError = error.localizedDescription
        }
    }

    func reloadIfActive(playlist: Playlist) async {
        guard activePlaylistId == playlist.id else { return }
        filterAdultContent = playlist.filterAdultContent
        do {
            let fetched = try await fetchChannels(playlistId: playlist.id)
            let visible = applyAdultFilter(fetched, enabled: filterAdultContent)
            let grouped = await groupOffMain(visible)
            apply(channels: visible, grouping: grouped)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Search

    func search(_ query: String) -> [DBM3UChannel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return channels.filter { CatalogTextSearch.matches(search: q, text: $0.name) }
    }

    // MARK: - Internal

    private func clearLists() {
        channels = []
        channelsByGroup = [:]
        groupNames = []
    }

    private func apply(channels: [DBM3UChannel], grouping: Grouping) {
        self.channels = channels
        self.channelsByGroup = grouping.byGroup
        self.groupNames = grouping.names
    }

    private func fetchChannels(playlistId: UUID) async throws -> [DBM3UChannel] {
        try await AppDatabase.shared.read { db in
            try DBM3UChannel
                .filter(Column("playlistId") == playlistId)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    /// 310K kanalı ana thread'de gruplamak 100-500ms takılmaya yol açar; detached task'a at.
    private func groupOffMain(_ channels: [DBM3UChannel]) async -> Grouping {
        let label = Self.ungroupedLabel
        return await Task.detached(priority: .userInitiated) {
            Self.group(channels: channels, ungroupedLabel: label)
        }.value
    }

    private struct Grouping: Sendable {
        var byGroup: [String: [DBM3UChannel]]
        var names: [String]
    }

    /// Kanal adı veya group-title'ı yetişkin anahtar kelimesi içeriyorsa kanalı eler.
    /// DB'yi değiştirmez — sadece görünür seti filtreler. Toggle anlık etki eder.
    nonisolated private func applyAdultFilter(_ channels: [DBM3UChannel], enabled: Bool) -> [DBM3UChannel] {
        guard enabled else { return channels }
        return channels.filter { ch in
            if AdultContentFilter.isAdultCategoryName(ch.name) { return false }
            if let group = ch.groupTitle, AdultContentFilter.isAdultCategoryName(group) { return false }
            return true
        }
    }

    nonisolated private static func group(channels: [DBM3UChannel], ungroupedLabel: String) -> Grouping {
        var byGroup: [String: [DBM3UChannel]] = [:]
        var names: [String] = []
        byGroup.reserveCapacity(min(channels.count / 8, 4096))
        for ch in channels {
            let raw = ch.groupTitle?.trimmingCharacters(in: .whitespaces)
            let key = (raw?.isEmpty == false ? raw! : ungroupedLabel)
            if byGroup[key] == nil { names.append(key) }
            byGroup[key, default: []].append(ch)
        }
        return Grouping(byGroup: byGroup, names: names)
    }
}
