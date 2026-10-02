import Foundation
import Combine
import GRDB
import UIKit

enum EPGRefreshState: Equatable {
    case idle
    case refreshing(EPGRefreshPhase?)
    case failed(String)

    var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

/// Lightweight record used by the timeline grid. Long descriptions and artwork
/// are fetched only when the user opens a programme, keeping the day view's peak
/// memory proportional to titles rather than the full XMLTV payload.
nonisolated struct EPGGuideProgrammeRecord: FetchableRecord, Decodable, Sendable {
    let channelKey: String
    let startTs: Int64
    let stopTs: Int64
    let title: String

    var programme: EPGProgramme {
        EPGProgramme(
            channelKey: channelKey,
            title: title,
            start: Date(timeIntervalSince1970: TimeInterval(startTs)),
            stop: Date(timeIntervalSince1970: TimeInterval(stopTs))
        )
    }
}

/// Central EPG store. Owns a single in-memory now/next index (published once per
/// minute as an `EPGSnapshot`) plus per-playlist refresh orchestration. One store,
/// one active playlist at a time — the snapshot dictionary carries no playlist
/// dimension and is rebuilt whenever the active playlist changes.
@MainActor
final class EPGStore: ObservableObject {
    static let shared: EPGStore = {
        let store = EPGStore()
        store.registerLifecycleObservers()
        return store
    }()

    /// Now/next for the active playlist. `nil` = EPG not configured/loaded.
    @Published private(set) var snapshot: EPGSnapshot?
    @Published private(set) var refreshState: [UUID: EPGRefreshState] = [:]
    @Published private(set) var lastSuccess: [UUID: Date] = [:]

    private var activePlaylistId: UUID?
    private var resolution: [String: String] = [:]   // aliasKey → stored channelKey
    private var configured = false                    // active playlist has a successful epgSource
    private var version = 0
    /// Ticks overlap (minute timer vs. a refresh finishing) and their reads can
    /// complete out of order; these keep an older index from replacing a newer one.
    private var tickSequence = 0
    private var publishedTickSequence = 0

    private var tickTask: Task<Void, Never>?
    private var activeRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Called by the `shared` factory right after `init` returns. The notification
    /// closures capture `self`, which inside `init` is still a mutable variable —
    /// a Swift 6 concurrency error for `@Sendable` closures.
    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopTimer() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.startTimerIfActive() }
        })
    }

    // MARK: - Active playlist lifecycle

    func setActivePlaylist(_ playlist: Playlist?) {
        guard activePlaylistId != playlist?.id else { return }
        activePlaylistId = playlist?.id
        resolution = [:]
        configured = false
        snapshot = nil
        guard let playlist else { stopTimer(); return }
        Task { await self.reload(playlist: playlist) }
    }

    /// Rebuilds the resolution map + snapshot and (re)starts the minute timer.
    func reload(playlist: Playlist) async {
        guard playlist.id == activePlaylistId else { return }
        await loadSourceStatus(playlist: playlist)
        await rebuildResolution(playlist: playlist)
        await tick()
        startTimerIfActive()
    }

    private func loadSourceStatus(playlist: Playlist) async {
        let src = try? await AppDatabase.shared.read { db in
            try DBEPGSource.fetchOne(db, key: playlist.id)
        }
        if let success = (src ?? nil)?.lastSuccessAt {
            configured = true
            lastSuccess[playlist.id] = success
        } else {
            configured = ((src ?? nil) != nil)
        }
    }

    // MARK: - Timer

    private func startTimerIfActive() {
        guard activePlaylistId != nil, tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let nextBoundary = (now.timeIntervalSince1970 / 60.0).rounded(.down) * 60 + 60
                let delay = max(1, nextBoundary - now.timeIntervalSince1970)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.tick()
            }
        }
    }

    private func stopTimer() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Now/next index

    func tick() async {
        guard let pid = activePlaylistId else { snapshot = nil; return }
        let now = Int64(Date().timeIntervalSince1970)
        // Captured here because the fold below runs off the main actor.
        let aliases = resolution
        tickSequence += 1
        let sequence = tickSequence

        let dict: [String: EPGNowNext]
        do {
            // The query and the whole fold stay on GRDB's reader queue. The main
            // thread also presents FFmpeg video frames, so with a large guide doing
            // this after the `await` hitched playback once a minute.
            dict = try await AppDatabase.shared.read { db in
                try Self.fetchNowIndex(db, playlistId: pid, now: now, resolution: aliases)
            }
        } catch {
            return
        }
        guard pid == activePlaylistId, sequence > publishedTickSequence else { return }
        publishedTickSequence = sequence

        if dict.isEmpty && !configured {
            snapshot = nil
            return
        }
        // Publish once per minute even while now/next titles are unchanged. Card
        // progress bars derive their fraction from the current time and therefore
        // need a new snapshot version to redraw.
        version += 1
        snapshot = EPGSnapshot(version: version, byChannelKey: dict)
    }

    /// Runs inside the database reader closure, away from the main actor. Fetches
    /// only the programmes on air at `now`, and only the columns the snapshot's
    /// consumers read. No `ORDER BY`: a global sort made SQLite build a temporary
    /// B-tree, and `makeNowIndex` resolves overlaps itself. Kept internal so the
    /// query can be regression-tested against an in-memory database.
    nonisolated static func fetchNowIndex(_ db: Database, playlistId: UUID, now: Int64,
                                          resolution: [String: String]) throws -> [String: EPGNowNext] {
        let latestStop = now + Int64(EPGConstants.nowIndexMaxRemaining)
        let rows = try EPGGuideProgrammeRecord.fetchAll(db, sql: """
            SELECT channelKey, startTs, stopTs, title FROM epgProgramme
            WHERE playlistId = ? AND stopTs > ? AND stopTs <= ? AND startTs <= ?
            """, arguments: [playlistId, now, latestStop, now])
        return makeNowIndex(rows, resolution: resolution)
    }

    /// Folds on-air rows into the snapshot dictionary. When guide data overlaps
    /// (a day-long placeholder under a real programme) the row that started last
    /// wins, so the result does not depend on row order.
    nonisolated static func makeNowIndex(_ rows: [EPGGuideProgrammeRecord],
                                         resolution: [String: String]) -> [String: EPGNowNext] {
        var latest: [String: EPGGuideProgrammeRecord] = [:]
        latest.reserveCapacity(min(rows.count, 4_096))
        for row in rows {
            if let kept = latest[row.channelKey], kept.startTs >= row.startTs { continue }
            latest[row.channelKey] = row
        }
        let byStored = latest.mapValues { EPGNowNext(now: $0.programme) }

        // Fold in alias entries so lookups by a channel's own id/name resolve to
        // the stored (possibly display-name-matched) key.
        var dict = byStored
        for (alias, stored) in resolution where dict[alias] == nil {
            if let nn = byStored[stored] { dict[alias] = nn }
        }
        return dict
    }

    func nowNext(channelKey: String?) -> EPGNowNext? { snapshot?[channelKey] }

    // MARK: - Resolution

    func rebuildResolution(playlist: Playlist) async {
        let map = try? await AppDatabase.shared.read { db -> [String: String] in
            let channels = try DBEPGChannel.fetchAll(db, sql: "SELECT * FROM epgChannel WHERE playlistId = ?", arguments: [playlist.id])
            var storedKeys = Set<String>()
            var nameToStored: [String: String] = [:]
            for c in channels {
                storedKeys.insert(c.channelKey)
                if let dn = c.displayName?.lowercased(), !dn.isEmpty, nameToStored[dn] == nil {
                    nameToStored[dn] = c.channelKey
                }
            }
            let progKeys = try String.fetchAll(db, sql: "SELECT DISTINCT channelKey FROM epgProgramme WHERE playlistId = ?", arguments: [playlist.id])
            storedKeys.formUnion(progKeys)

            var map: [String: String] = [:]
            if playlist.kind == .xtream {
                let rows = try DBLiveStream.fetchAll(db, sql: "SELECT * FROM liveStream WHERE playlistId = ?", arguments: [playlist.id])
                for r in rows {
                    Self.resolveAlias(idKey: EPGConstants.normalizeChannelKey(r.epgChannelId),
                                      nameKey: EPGConstants.normalizeChannelKey(r.name),
                                      storedKeys: storedKeys, nameToStored: nameToStored, into: &map)
                }
            } else {
                let rows = try DBM3UChannel.fetchAll(db, sql: "SELECT * FROM m3uChannel WHERE playlistId = ?", arguments: [playlist.id])
                for r in rows {
                    Self.resolveAlias(idKey: EPGConstants.normalizeChannelKey(r.tvgId),
                                      nameKey: EPGConstants.normalizeChannelKey(r.tvgName ?? r.name),
                                      storedKeys: storedKeys, nameToStored: nameToStored, into: &map)
                }
            }
            return map
        }
        guard playlist.id == activePlaylistId else { return }
        resolution = map ?? [:]
    }

    private nonisolated static func resolveAlias(idKey: String?, nameKey: String?,
                                                 storedKeys: Set<String>, nameToStored: [String: String],
                                                 into map: inout [String: String]) {
        var stored: String?
        if let idKey, storedKeys.contains(idKey) { stored = idKey }
        else if let nameKey, let s = nameToStored[nameKey] { stored = s }
        guard let stored else { return }
        if let idKey { map[idKey] = stored }
        if let nameKey, map[nameKey] == nil { map[nameKey] = stored }
    }

    /// Resolves a channel's own id/name to the stored key its programmes live under.
    func storedKey(idKey: String?, nameKey: String?) -> String? {
        if let idKey, let s = resolution[idKey] { return s }
        if let nameKey, let s = resolution[nameKey] { return s }
        if let idKey { return idKey }   // direct fallback
        return nil
    }

    // MARK: - Queries

    func programmes(playlistId: UUID, channelKey: String, from: Date, to: Date) async throws -> [EPGProgramme] {
        let f = Int64(from.timeIntervalSince1970)
        let t = Int64(to.timeIntervalSince1970)
        return try await AppDatabase.shared.read { db in
            let rows = try DBEPGProgramme.fetchAll(db, sql: """
                SELECT * FROM epgProgramme
                WHERE playlistId = ? AND channelKey = ? AND stopTs > ? AND startTs < ?
                ORDER BY startTs
                """, arguments: [playlistId, channelKey, f, t])
            // Keep record conversion on GRDB's reader queue. This method belongs to
            // the main-actor store, so doing it after `await` blocks UI rendering.
            return rows.map(EPGProgramme.init(from:))
        }
    }

    /// All programmes for a playlist within a window, grouped by channelKey. Used by
    /// the guide grid — avoids a giant `channelKey IN (…)` clause (SQLite variable
    /// limit / slow) for playlists with thousands of channels.
    func programmes(playlistId: UUID, from: Date, to: Date) async throws -> [String: [EPGProgramme]] {
        let f = Int64(from.timeIntervalSince1970)
        let t = Int64(to.timeIntervalSince1970)
        return try await AppDatabase.shared.read { db in
            let rows = try EPGGuideProgrammeRecord.fetchAll(db, sql: """
                SELECT channelKey, startTs, stopTs, title FROM epgProgramme
                WHERE playlistId = ? AND stopTs > ? AND startTs < ?
                """, arguments: [playlistId, f, t])
            // The guide sorts each channel while building its layout. A global
            // ORDER BY forced SQLite to create a large temporary B-tree first.
            return Self.groupGuideProgrammes(rows)
        }
    }

    /// Loads the fields omitted from the grid query just before presenting the
    /// programme detail sheet. The composite primary key makes this an O(log n)
    /// point lookup.
    func programmeDetails(playlistId: UUID, channelKey: String, start: Date) async throws -> EPGProgramme? {
        let startTs = Int64(start.timeIntervalSince1970)
        return try await AppDatabase.shared.read { db in
            try DBEPGProgramme.fetchOne(db, sql: """
                SELECT * FROM epgProgramme
                WHERE playlistId = ? AND channelKey = ? AND startTs = ?
                """, arguments: [playlistId, channelKey, startTs])
                .map(EPGProgramme.init(from:))
        }
    }

    func programmes(playlistId: UUID, channelKeys: [String], from: Date, to: Date) async throws -> [String: [EPGProgramme]] {
        guard !channelKeys.isEmpty else { return [:] }
        let f = Int64(from.timeIntervalSince1970)
        let t = Int64(to.timeIntervalSince1970)
        let placeholders = databaseQuestionMarks(count: channelKeys.count)
        var args: [DatabaseValueConvertible] = [playlistId]
        args.append(contentsOf: channelKeys)
        args.append(f); args.append(t)
        return try await AppDatabase.shared.read { db in
            let rows = try DBEPGProgramme.fetchAll(db, sql: """
                SELECT * FROM epgProgramme
                WHERE playlistId = ? AND channelKey IN (\(placeholders)) AND stopTs > ? AND startTs < ?
                ORDER BY channelKey, startTs
                """, arguments: StatementArguments(args))
            return Self.groupProgrammes(rows)
        }
    }

    /// Runs inside the database reader closure for guide queries, away from the
    /// main actor. Kept internal so large synthetic datasets can regression-test it.
    nonisolated static func groupProgrammes(_ rows: [DBEPGProgramme]) -> [String: [EPGProgramme]] {
        var result: [String: [EPGProgramme]] = [:]
        result.reserveCapacity(min(rows.count, 4_096))
        for row in rows {
            result[row.channelKey, default: []].append(EPGProgramme(from: row))
        }
        return result
    }

    nonisolated static func groupGuideProgrammes(_ rows: [EPGGuideProgrammeRecord]) -> [String: [EPGProgramme]] {
        var result: [String: [EPGProgramme]] = [:]
        result.reserveCapacity(min(rows.count, 4_096))
        for row in rows {
            result[row.channelKey, default: []].append(row.programme)
        }
        return result
    }

    /// Catch-up detail: past programmes for a channel, clamped to its archive
    /// window. Falls back to `get_simple_data_table` when the stored (XMLTV) guide
    /// has no past coverage but the channel advertises an archive.
    func archiveProgrammes(playlist: Playlist, stream: DBLiveStream) async throws -> [EPGProgramme] {
        let idKey = EPGConstants.normalizeChannelKey(stream.epgChannelId)
        let nameKey = EPGConstants.normalizeChannelKey(stream.name)
        let key = storedKey(idKey: idKey, nameKey: nameKey) ?? "#stream:\(stream.streamId)"

        let now = Date()
        let days = min(max(stream.tvArchiveDuration, EPGConstants.minCatchupPastDays), EPGConstants.maxCatchupPastDays)
        let from = now.addingTimeInterval(-Double(days) * 86_400)

        var rows = try await programmes(playlistId: playlist.id, channelKey: key, from: from, to: now)
        let hasPast = rows.contains { $0.start < now }
        if !hasPast, stream.tvArchive == 1, playlist.kind == .xtream {
            await fetchSimpleDataTable(playlist: playlist, stream: stream, channelKey: key)
            rows = try await programmes(playlistId: playlist.id, channelKey: key, from: from, to: now)
        }
        return rows.filter { $0.start < now }
    }

    // MARK: - JSON fallback (player now/next + catch-up detail)

    /// Ensures the currently-playing channel has now/next when the XMLTV guide is
    /// missing it — pulls `get_short_epg` and stores it.
    func ensureShortEPG(playlist: Playlist, stream: DBLiveStream) async {
        guard playlist.kind == .xtream else { return }
        // The key the channel cards and the player look this channel up by. Without one
        // (no EPG id and no name) nothing could display the answer, so nothing is asked.
        guard let key = EPGChannelKey.forXtream(stream) else { return }
        if let existing = snapshot?[key], existing.now != nil { return }
        guard let response = try? await XtreamAPIClient(playlist: playlist).getShortEPG(streamId: stream.streamId) else { return }
        // Stored under the lookup key itself, not under a guide alias or the listing's
        // own `channel_id`: the index publishes a stored key as it is, so the lookup
        // above and the player's are direct hits whatever the alias map holds.
        let stored = await storeListings(response.epgListings, playlistId: playlist.id,
                                         fallbackKey: key, ignoresListingChannelId: true)
        // An empty or unusable answer leaves the index as it is: rebuilding it would
        // publish a new snapshot, and redraw every card, for no change.
        guard stored else { return }
        await tick()
    }

    private func fetchSimpleDataTable(playlist: Playlist, stream: DBLiveStream, channelKey: String) async {
        guard let response = try? await XtreamAPIClient(playlist: playlist).getSimpleDataTable(streamId: stream.streamId) else { return }
        await storeListings(response.epgListings, playlistId: playlist.id, fallbackKey: channelKey)
    }

    /// Returns true when at least one row was written.
    /// `ignoresListingChannelId`: store every row under `fallbackKey`, whatever
    /// `channel_id` the panel put in the listing. The short-EPG fallback needs that:
    /// its rows are read back under a key derived from the channel, and a listing id
    /// that differs from it would hide them from the lookup.
    @discardableResult
    private func storeListings(_ listings: [XtreamEPGListing], playlistId: UUID, fallbackKey: String,
                               ignoresListingChannelId: Bool = false) async -> Bool {
        let rows: [DBEPGProgramme] = listings.compactMap { listing in
            guard let start = listing.startTimestamp, let stop = listing.stopTimestamp, stop > start else { return nil }
            let key = ignoresListingChannelId
                ? fallbackKey
                : (EPGConstants.normalizeChannelKey(listing.channelId) ?? fallbackKey)
            return DBEPGProgramme(
                playlistId: playlistId, channelKey: key,
                startTs: Int64(start), stopTs: Int64(stop),
                title: listing.decodedTitle ?? "",
                subtitle: nil, desc: listing.decodedDescription,
                category: nil, iconURL: nil, episodeNum: nil
            )
        }
        guard !rows.isEmpty else { return false }
        // The write is one transaction: when it throws, nothing was stored.
        let written: Void? = try? await AppDatabase.shared.write { db in
            for r in rows { try r.insert(db) }
        }
        return written != nil
    }

    // MARK: - Refresh orchestration

    func refreshIfStale(playlist: Playlist) async {
        guard playlist.epgEnabled else { return }
        let src = try? await AppDatabase.shared.read { db in try DBEPGSource.fetchOne(db, key: playlist.id) }
        if let src = src ?? nil {
            if let last = src.lastSuccessAt, Date().timeIntervalSince(last) < EPGConstants.refreshTTL { return }
            if let attempt = src.fetchedAt, src.lastSuccessAt == nil,
               Date().timeIntervalSince(attempt) < EPGConstants.retryCooldown { return }
        }
        // M3U with no configured source → nothing to do.
        if playlist.kind == .m3u, playlist.effectiveEPGURL == nil { return }
        await runRefresh(playlist: playlist)
    }

    func forceRefresh(playlist: Playlist) async {
        await runRefresh(playlist: playlist)
    }

    private func runRefresh(playlist: Playlist) async {
        // Dedup concurrent refreshes for the same playlist.
        if let existing = activeRefreshTasks[playlist.id] {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            await self.performRefresh(playlist: playlist)
        }
        activeRefreshTasks[playlist.id] = task
        await task.value
        activeRefreshTasks[playlist.id] = nil
    }

    private func performRefresh(playlist: Playlist) async {
        refreshState[playlist.id] = .refreshing(nil)
        let coordinator = EPGRefreshCoordinator()
        do {
            _ = try await coordinator.refresh(playlist: playlist) { [weak self] phase in
                self?.refreshState[playlist.id] = .refreshing(phase)
            }
            refreshState[playlist.id] = .idle
            lastSuccess[playlist.id] = Date()
            if playlist.id == activePlaylistId {
                configured = true
                await rebuildResolution(playlist: playlist)
                await tick()
            }
        } catch is CancellationError {
            refreshState[playlist.id] = .idle
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshState[playlist.id] = .failed(message)
        }
    }

    // MARK: - Helpers

    private func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
