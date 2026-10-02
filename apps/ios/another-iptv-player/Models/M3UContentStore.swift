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
    /// A refresh (download, parse, import) that failed. Kept apart from `loadError`:
    /// that one reports the stored list failing to load and offers to load it
    /// again, while a failed refresh leaves the stored list in place and on screen.
    /// Written by whoever runs the refresh; the store only resets it.
    @Published var refreshError: String?

    @Published private(set) var channels: [DBM3UChannel] = []
    @Published private(set) var channelsByGroup: [String: [DBM3UChannel]] = [:]
    @Published private(set) var groupNames: [String] = []
    /// Bumped whenever the lists above are replaced or cleared. Views key their
    /// follow-up work on this instead of on `channels`: comparing two separately
    /// fetched arrays of equal content walks the whole catalog on the main thread.
    @Published private(set) var revision = 0

    /// Position of each channel in `channels` by id, built with the grouping.
    private var channelIndexById: [String: Int] = [:]

    /// `group-title` boş olan kanallar için kullanılan KANONİK anahtar. Lookup'lar
    /// (queue, panel, hidden-category id'leri) her zaman bu anahtarı kullanmalı;
    /// kullanıcıya gösterirken `displayName(forGroup:)` ile yerelleştirilir.
    /// Not: HiddenCategoryStore bu değeri id olarak persist ettiği için değiştirmek
    /// mevcut kullanıcıların gizli kategori seçimlerini bozar — "Diğer" kalmalı.
    nonisolated static let ungroupedLabel = "Diğer"

    /// Görünen ad: kanonik ungrouped anahtarı aktif dile çevrilir, diğerleri aynen döner.
    /// Panel kurucuları detached task'ta çalıştığı için nonisolated.
    nonisolated static func displayName(forGroup group: String) -> String {
        group == ungroupedLabel ? L("m3u.ungrouped_label") : group
    }

    private var loadToken: UUID?

    private let database: AppDatabase

    /// The app uses `shared`; tests build their own store on an in-memory database.
    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Public API

    func loadPlaylist(_ playlist: Playlist) async {
        let token = UUID()
        loadToken = token
        loadError = nil

        if activePlaylistId != playlist.id {
            clearLists()
            refreshError = nil
            activePlaylistId = playlist.id
        }

        isLoading = true
        // Only the latest request clears the flag. One that was superseded returns
        // early while its successor is still fetching, and clearing it here showed
        // the empty state in place of the spinner until that one landed.
        defer { if loadToken == token { isLoading = false } }

        do {
            let stored = try await fetchStored(for: playlist)
            guard loadToken == token else { return }
            let prepared = await prepareOffMain(stored.channels, filterAdult: stored.filterAdult)
            guard loadToken == token else { return }
            apply(channels: prepared.channels, grouping: prepared.grouping)
        } catch {
            guard loadToken == token else { return }
            loadError = error.localizedDescription
        }
    }

    /// Dashboard'dan çıkışta 310K+ kanallık kopyalar singleton'da kalmasın (bkz.
    /// PlaylistContentStore.unload).
    func unload() {
        loadToken = nil
        activePlaylistId = nil
        clearLists()
        loadError = nil
        refreshError = nil
        isLoading = false
    }

    func reloadIfActive(playlist: Playlist) async {
        guard activePlaylistId == playlist.id else { return }
        // Same "latest request wins" rule as `loadPlaylist`. The read, the filter
        // and the grouping each cross an await, and an older result must not land
        // on top of a newer one or on a store that was unloaded meanwhile.
        let token = UUID()
        loadToken = token
        // With lists on screen a reload is silent. With none (a first load that
        // this request has just superseded, or an empty playlist) it is the load,
        // and takes over the flag under the same rule as `loadPlaylist`.
        if channels.isEmpty { isLoading = true }
        defer { if loadToken == token { isLoading = false } }
        do {
            let stored = try await fetchStored(for: playlist)
            guard loadToken == token else { return }
            let prepared = await prepareOffMain(stored.channels, filterAdult: stored.filterAdult)
            guard loadToken == token else { return }
            apply(channels: prepared.channels, grouping: prepared.grouping)
        } catch {
            guard loadToken == token else { return }
            loadError = error.localizedDescription
        }
    }

    // MARK: - Lookup

    /// The loaded channel with this id, or nil when it is not in the visible list
    /// (removed by a re-import, or hidden by the adult filter).
    func channel(id: String) -> DBM3UChannel? {
        guard let index = channelIndexById[id], channels.indices.contains(index) else { return nil }
        return channels[index]
    }

    /// Previous/next queue for a channel: the other channels of its group, in list
    /// order. Looked up under the canonical group key; a localized label would
    /// miss and leave the player with a queue of one.
    func queue(for channel: DBM3UChannel) -> [DBM3UChannel] {
        channelsByGroup[Self.groupKey(for: channel)] ?? [channel]
    }

    /// The key `channelsByGroup` files a channel under: its trimmed `group-title`,
    /// or `ungroupedLabel` when it has none.
    nonisolated static func groupKey(for channel: DBM3UChannel) -> String {
        let raw = channel.groupTitle?.trimmingCharacters(in: .whitespaces)
        return raw?.isEmpty == false ? raw! : ungroupedLabel
    }

    /// Live or VOD, the way the TV guide separates them: a channel whose URL cannot
    /// be parsed counts as live. Parses the URL, so over a whole catalog this
    /// belongs in a detached task (hence nonisolated), not on the main actor.
    nonisolated static func isLive(_ channel: DBM3UChannel) -> Bool {
        guard let url = M3UParser.sanitizedURL(from: channel.url) else { return true }
        return M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle).isLive
    }

    /// The live channels of `channels`, in order. See `isLive(_:)`.
    nonisolated static func liveChannels(in channels: [DBM3UChannel]) -> [DBM3UChannel] {
        channels.filter { isLive($0) }
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
        channelIndexById = [:]
        revision &+= 1
    }

    private func apply(channels: [DBM3UChannel], grouping: Grouping) {
        self.channels = channels
        self.channelsByGroup = grouping.byGroup
        self.groupNames = grouping.names
        self.channelIndexById = grouping.indexById
        // Last, so whoever reacts to the revision reads the new lists.
        revision &+= 1
    }

    /// The playlist's channels together with its adult-filter setting, in one read.
    /// The setting comes from the row: `playlist` is the value the calling screen
    /// was opened with, and re-applying its flag after a refresh brought back the
    /// channels a filter switched on since then had hidden. The argument only
    /// stands in when the row cannot be found.
    private func fetchStored(for playlist: Playlist) async throws -> (filterAdult: Bool, channels: [DBM3UChannel]) {
        let playlistId = playlist.id
        let fallbackFilter = playlist.filterAdultContent
        return try await database.read { db in
            let filterAdult = try Playlist.fetchOne(db, key: playlistId)?.filterAdultContent ?? fallbackFilter
            let channels = try DBM3UChannel
                .filter(Column("playlistId") == playlistId)
                .order(Column("sortIndex"))
                .fetchAll(db)
            return (filterAdult, channels)
        }
    }

    /// 310K kanalı ana thread'de gruplamak 100-500ms takılmaya yol açar; detached task'a at.
    /// The adult filter runs in the same task for the same reason: it tokenizes
    /// every channel name.
    private func prepareOffMain(_ fetched: [DBM3UChannel],
                                filterAdult: Bool) async -> (channels: [DBM3UChannel], grouping: Grouping) {
        await Task.detached(priority: .userInitiated) {
            let visible = Self.applyAdultFilter(fetched, enabled: filterAdult)
            return (visible, Self.group(channels: visible))
        }.value
    }

    nonisolated private struct Grouping: Sendable {
        var byGroup: [String: [DBM3UChannel]]
        var names: [String]
        var indexById: [String: Int]
    }

    /// Kanal adı veya group-title'ı yetişkin anahtar kelimesi içeriyorsa kanalı eler.
    /// DB'yi değiştirmez — sadece görünür seti filtreler. Toggle anlık etki eder.
    nonisolated private static func applyAdultFilter(_ channels: [DBM3UChannel], enabled: Bool) -> [DBM3UChannel] {
        guard enabled else { return channels }
        // A catalog has far fewer group titles than channels: judge each title once.
        var adultGroups: [String: Bool] = [:]
        return channels.filter { ch in
            if AdultContentFilter.isAdultCategoryName(ch.name) { return false }
            guard let group = ch.groupTitle else { return true }
            if let known = adultGroups[group] { return !known }
            let isAdult = AdultContentFilter.isAdultCategoryName(group)
            adultGroups[group] = isAdult
            return !isAdult
        }
    }

    nonisolated private static func group(channels: [DBM3UChannel]) -> Grouping {
        var byGroup: [String: [DBM3UChannel]] = [:]
        var names: [String] = []
        var indexById: [String: Int] = [:]
        byGroup.reserveCapacity(min(channels.count / 8, 4096))
        indexById.reserveCapacity(channels.count)
        for (index, ch) in channels.enumerated() {
            let key = groupKey(for: ch)
            if byGroup[key] == nil { names.append(key) }
            byGroup[key, default: []].append(ch)
            indexById[ch.id] = index
        }
        return Grouping(byGroup: byGroup, names: names, indexById: indexById)
    }
}
