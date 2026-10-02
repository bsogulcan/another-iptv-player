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

    /// Now/next for the active playlist. `nil` means its channel cards carry no
    /// now/next line; the cards key the line's space on this being non-nil.
    ///
    /// A playlist that is expected to have a guide gets `.empty` the moment it
    /// becomes active (a snapshot that only appeared with the first index made
    /// every shelf grow after it was on screen) and keeps a snapshot for as long as
    /// nothing says otherwise. It goes to nil when the guide is switched off, and
    /// when a refresh attempt has finished and none of the playlist's channels
    /// match anything in the stored guide: a panel without a guide should not
    /// leave an empty line under every card for ever. See `tick()`.
    @Published private(set) var snapshot: EPGSnapshot?
    @Published private(set) var refreshState: [UUID: EPGRefreshState] = [:]
    @Published private(set) var lastSuccess: [UUID: Date] = [:]
    /// 'Show TV guide' of the active playlist, as stored in its row. True while no
    /// playlist is active. While it is false the store publishes no snapshot, runs
    /// no minute timer and starts no refresh; the stored guide rows are kept, so
    /// switching it back on shows the lines again without a download.
    @Published private(set) var isGuideEnabled = true

    private var activePlaylistId: UUID?
    private var resolution: [String: String] = [:]   // aliasKey → stored channelKey
    /// `resolution` has been read for the active playlist. Until then an empty map
    /// means "not known yet", not "no channel has a guide".
    private var resolutionLoaded = false
    /// A refresh attempt for the active playlist has ended, in success or failure,
    /// in this run or an earlier one. Before that, a guide that matches nothing is
    /// simply not there yet.
    private var attemptFinished = false
    /// The active playlist is expected to have a guide (`expectsGuide`), whether
    /// or not one has been downloaded yet. Follows the stored row, not the copy a
    /// caller happens to hold (see `noteGuideExpectation`).
    private var guideExpected = false
    /// What the persisted line answer of the active playlist was last set to, so
    /// the minute tick does not write the defaults again for an unchanged answer.
    private var rememberedLineReserved: Bool?
    /// The app went to the background and has not become active since.
    private var isInBackground = false
    private var version = 0
    /// Ticks overlap (minute timer vs. a refresh finishing) and their reads can
    /// complete out of order; these keep an older index from replacing a newer one.
    private var tickSequence = 0
    private var publishedTickSequence = 0

    private var tickTask: Task<Void, Never>?
    private var activeRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    private let database: AppDatabase
    private let defaults: UserDefaults
    private let downloader: EPGDownloader

    /// The app uses `shared`. Tests build their own store on an in-memory database,
    /// a private defaults suite and a downloader over a stubbed session; such a
    /// store has no lifecycle observers.
    init(database: AppDatabase = .shared, defaults: UserDefaults = .standard,
         downloader: EPGDownloader = EPGDownloader()) {
        self.database = database
        self.defaults = defaults
        self.downloader = downloader
    }

    /// Called by the `shared` factory right after `init` returns. The notification
    /// closures capture `self`, which inside `init` is still a mutable variable —
    /// a Swift 6 concurrency error for `@Sendable` closures.
    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applicationDidEnterBackground() }
        })
        // Utility priority for both triggers: what they may start is a guide
        // download and parse, which should not compete with a filter or a sort the
        // user is waiting for. Nothing awaits these tasks, so nothing raises it.
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task(priority: .utility) { @MainActor [weak self] in await self?.applicationDidBecomeActive() }
        })
        NetworkStatus.shared.$reconnectCount
            .dropFirst()
            .sink { [weak self] _ in
                Task(priority: .utility) { @MainActor [weak self] in await self?.networkDidReconnect() }
            }
            .store(in: &cancellables)
    }

    // MARK: - App lifecycle and connectivity

    /// Internal, like the two below, so the unit tests can drive them.
    func applicationDidEnterBackground() {
        isInBackground = true
        stopTimer()
    }

    /// The timer sleeps to the next minute boundary before its first tick, so
    /// after a stay in the background the cards would show the programme from
    /// before it for up to a minute; and nothing else looks at the guide's age
    /// while the process stays alive. Both are done here, once per real return:
    /// Control Centre, a notification banner and the app switcher end in the same
    /// notification without the app having left, and must not redraw every card.
    func applicationDidBecomeActive() async {
        let returned = isInBackground
        isInBackground = false
        guard let playlistId = activePlaylistId, isGuideEnabled else { return }
        // Before the awaits: a move to the background during them stops this timer.
        startTimerIfActive()
        guard returned else { return }
        await tick()
        await refreshIfStale(playlistId: playlistId)
    }

    /// A refresh that failed while the network was away is tried again when it
    /// comes back. The guide's age and the retry cooldown still decide. In the
    /// background nothing is fetched: becoming active asks the same question.
    func networkDidReconnect() async {
        guard let playlistId = activePlaylistId, isGuideEnabled, !isInBackground else { return }
        await refreshIfStale(playlistId: playlistId)
    }

    // MARK: - Active playlist lifecycle

    func setActivePlaylist(_ playlist: Playlist?) {
        guard activePlaylistId != playlist?.id else { return }
        activePlaylistId = playlist?.id
        resolution = [:]
        resolutionLoaded = false
        attemptFinished = false
        guideExpected = false
        rememberedLineReserved = nil
        guard let playlist else {
            snapshot = nil
            stopTimer()
            if !isGuideEnabled { isGuideEnabled = true }
            return
        }
        // From the copy for now; `reload` reads the row and corrects both.
        if isGuideEnabled != playlist.epgEnabled { isGuideEnabled = playlist.epgEnabled }
        if !isGuideEnabled { stopTimer() }
        guideExpected = Self.expectsGuide(playlist)
        // Same answer the dashboard gave the cards on its first frame, so the
        // placeholder replaces nil without moving anything.
        snapshot = Self.isLineReserved(for: playlist, defaults: defaults) ? .empty : nil
        Task { await self.reload(playlist: playlist) }
    }

    /// Rebuilds the resolution map + snapshot and (re)starts the minute timer.
    /// With the guide switched off only the map is built (the guide screen and
    /// catch-up resolve channels through it); `tick` and the timer do nothing.
    func reload(playlist: Playlist) async {
        guard playlist.id == activePlaylistId else { return }
        await loadSourceStatus(playlist: playlist)
        await rebuildResolution(playlist: playlist)
        await tick()
        startTimerIfActive()
    }

    // MARK: - 'Show TV guide'

    /// Settings calls this after it has saved the switch to the playlist row. Off
    /// takes the now/next lines away at once and stops the timer; on brings them
    /// back from the stored guide and then checks whether it needs a refresh.
    /// The row stays the authority: every later read of it sets the flag again.
    func setGuideEnabled(_ enabled: Bool, playlist: Playlist) async {
        guard playlist.id == activePlaylistId else { return }
        guard enabled else {
            guideExpected = false
            applyGuideEnabled(false)
            return
        }
        applyGuideEnabled(true)
        await reload(playlist: playlist)
        await refreshIfStale(playlist: playlist)
    }

    private func applyGuideEnabled(_ enabled: Bool) {
        guard enabled != isGuideEnabled else { return }
        isGuideEnabled = enabled
        guard !enabled else { return }
        stopTimer()
        if snapshot != nil { snapshot = nil }
    }

    // MARK: - Reserved now/next line

    /// A guide is expected when the playlist has somewhere to get one from and has
    /// not switched it off: every Xtream panel serves XMLTV, an M3U playlist needs
    /// a guide URL (from its header or entered by the user).
    nonisolated static func expectsGuide(_ playlist: Playlist) -> Bool {
        guard playlist.epgEnabled else { return false }
        return playlist.kind == .xtream || playlist.effectiveEPGURL != nil
    }

    private static func lineReservedKey(_ playlistId: UUID) -> String {
        "epg.lineReserved.\(playlistId.uuidString)"
    }

    /// True when the channel cards of `playlist` should reserve the now/next line.
    /// Answerable before the store has loaded anything, so a dashboard can inject
    /// it on its first frame. Never with the guide switched off. Otherwise the
    /// answer the store reached the last time this playlist was open, which may be
    /// a no (its channels matched nothing in the guide); and while there is no
    /// such answer yet, whether a guide is expected.
    static func isLineReserved(for playlist: Playlist, defaults: UserDefaults = .standard) -> Bool {
        guard playlist.epgEnabled else { return false }
        if let known = defaults.object(forKey: lineReservedKey(playlist.id)) as? Bool { return known }
        return expectsGuide(playlist)
    }

    /// The same answer for a view that observes the store. Once `playlist` is the
    /// active one it follows the published snapshot, so the line and the snapshot
    /// cannot disagree when a guide appears or goes away during the session.
    func isLineReserved(for playlist: Playlist) -> Bool {
        guard playlist.id == activePlaylistId else {
            return Self.isLineReserved(for: playlist, defaults: defaults)
        }
        return snapshot != nil
    }

    /// Drops the persisted answer of a deleted playlist.
    static func forgetLineReservation(playlistId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lineReservedKey(playlistId))
    }

    /// Records whether the index just built leaves a snapshot published, for the
    /// first frame of the next launch. Stored as a real yes or no: "no" has to
    /// outweigh the expectation, or a playlist whose panel has no guide would
    /// start every launch with the line and lose it a moment later.
    private func rememberLineReserved(_ reserved: Bool, playlistId: UUID) {
        guard rememberedLineReserved != reserved else { return }
        rememberedLineReserved = reserved
        defaults.set(reserved, forKey: Self.lineReservedKey(playlistId))
    }

    /// Settings can change what the active playlist expects (the guide switched
    /// on or off, an XMLTV URL saved). The answer is taken from the stored row: the
    /// dashboard, the guide and the settings sections each pass the copy they were
    /// opened with, and an older copy must neither drop a line the row asks for
    /// nor bring back one it has given up. When the row cannot be read, the copy
    /// may only raise the expectation. Reserving the line here puts it in place
    /// before a download starts, instead of when it lands; not once an attempt has
    /// finished, though: from then on `tick` knows whether anything matched, and
    /// a line reserved here would only be taken away again after the refresh.
    private func noteGuideExpectation(stored row: Playlist?, passed playlist: Playlist) {
        guard playlist.id == activePlaylistId else { return }
        if let row {
            guideExpected = Self.expectsGuide(row)
            applyGuideEnabled(row.epgEnabled)
        } else {
            if playlist.epgEnabled { applyGuideEnabled(true) }
            if Self.expectsGuide(playlist) { guideExpected = true }
        }
        if isGuideEnabled, guideExpected, !attemptFinished, snapshot == nil { snapshot = .empty }
    }

    /// Takes in one read of the playlist row and its guide source. Returns true
    /// when that read switched the guide on: the caller then has an index to build
    /// and a timer to start.
    @discardableResult
    private func noteStoredGuideState(_ stored: (playlist: Playlist?, source: DBEPGSource?)?,
                                      passed playlist: Playlist) -> Bool {
        if let success = stored?.source?.lastSuccessAt, lastSuccess[playlist.id] != success {
            lastSuccess[playlist.id] = success
        }
        // The rest describes the active playlist, which may have changed during
        // the read.
        guard playlist.id == activePlaylistId else { return false }
        if Self.hasFinishedAttempt(stored?.source) { attemptFinished = true }
        let wasEnabled = isGuideEnabled
        noteGuideExpectation(stored: stored?.playlist, passed: playlist)
        return isGuideEnabled && !wasEnabled
    }

    /// The coordinator stamps `fetchedAt` when an attempt starts, and one of the
    /// other two when it ends.
    private nonisolated static func hasFinishedAttempt(_ source: DBEPGSource?) -> Bool {
        guard let source else { return false }
        return source.lastSuccessAt != nil || source.lastError != nil
    }

    /// The playlist row and its guide source as stored now, in one read. Nil when
    /// the read fails.
    private func storedGuideState(playlistId: UUID) async -> (playlist: Playlist?, source: DBEPGSource?)? {
        try? await database.read { db in
            (try Playlist.fetchOne(db, key: playlistId), try DBEPGSource.fetchOne(db, key: playlistId))
        }
    }

    private func loadSourceStatus(playlist: Playlist) async {
        let stored = await storedGuideState(playlistId: playlist.id)
        noteStoredGuideState(stored, passed: playlist)
    }

    // MARK: - Timer

    private func startTimerIfActive() {
        guard activePlaylistId != nil, isGuideEnabled, !isInBackground, tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let nextBoundary = (now.timeIntervalSince1970 / 60.0).rounded(.down) * 60 + 60
                let delay = max(1, nextBoundary - now.timeIntervalSince1970)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }
                // A store other than `shared` can go away; its timer ends with it.
                guard let self else { break }
                await self.tick()
            }
        }
    }

    private func stopTimer() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Now/next index

    func tick() async {
        guard let pid = activePlaylistId, isGuideEnabled else {
            if snapshot != nil { snapshot = nil }
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        // Captured here because the fold below runs off the main actor.
        let aliases = resolution
        let aliasesLoaded = resolutionLoaded
        tickSequence += 1
        let sequence = tickSequence

        let dict: [String: EPGNowNext]
        do {
            // The query and the whole fold stay on GRDB's reader queue. The main
            // thread also presents FFmpeg video frames, so with a large guide doing
            // this after the `await` hitched playback once a minute.
            dict = try await database.read { db in
                try Self.fetchNowIndex(db, playlistId: pid, now: now, resolution: aliases)
            }
        } catch {
            return
        }
        // The guide may have been switched off, or the playlist left, during the
        // read; publishing now would bring the lines back.
        guard pid == activePlaylistId, isGuideEnabled, sequence > publishedTickSequence else { return }
        publishedTickSequence = sequence

        let reserved: Bool
        if !dict.isEmpty || !aliases.isEmpty {
            // Some channel of the playlist has a guide (the parser stores only
            // channels the playlist has), or a short-EPG answer is on air.
            reserved = true
        } else if !aliasesLoaded {
            // Too early to tell, and nothing to show: leave things as they are.
            return
        } else {
            // Nothing matches. That is the normal state before the first download
            // of an expected guide, and the line waits for it. Once an attempt has
            // finished it is the answer: this playlist has no guide to show. A
            // later refresh that does match brings the line back through the
            // branch above; a refresh in progress changes nothing here, so the
            // line does not come and go around it.
            reserved = guideExpected && !attemptFinished
        }
        rememberLineReserved(reserved, playlistId: pid)
        guard reserved else {
            if snapshot != nil { snapshot = nil }
            return
        }
        guard !dict.isEmpty else {
            // Nothing on air, but the line stays reserved. A snapshot that still
            // holds programmes (they have since ended) is replaced by an empty one;
            // the placeholder, or an already empty snapshot, is left alone.
            if snapshot?.byChannelKey.isEmpty != true {
                version += 1
                snapshot = EPGSnapshot(version: version, byChannelKey: [:])
            }
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
        let map = try? await database.read { db -> [String: String] in
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
        // A failed read keeps the map there was; it says nothing about the guide.
        guard playlist.id == activePlaylistId, let map else { return }
        resolution = map
        resolutionLoaded = true
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
        Self.storedKey(idKey: idKey, nameKey: nameKey, in: resolution)
    }

    /// The alias map as it stands now (channel id or name key → stored guide key).
    /// A value copy for work that resolves every channel away from the main actor,
    /// such as the guide building its rows; take it in the same main-actor step as
    /// the channel list and resolve with `storedKey(idKey:nameKey:in:)`.
    var resolutionSnapshot: [String: String] { resolution }

    /// `storedKey(idKey:nameKey:)` against a map taken from `resolutionSnapshot`.
    nonisolated static func storedKey(idKey: String?, nameKey: String?,
                                      in resolution: [String: String]) -> String? {
        if let idKey, let s = resolution[idKey] { return s }
        if let nameKey, let s = resolution[nameKey] { return s }
        if let idKey { return idKey }   // direct fallback
        return nil
    }

    // MARK: - Queries

    func programmes(playlistId: UUID, channelKey: String, from: Date, to: Date) async throws -> [EPGProgramme] {
        let f = Int64(from.timeIntervalSince1970)
        let t = Int64(to.timeIntervalSince1970)
        return try await database.read { db in
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
        return try await database.read { db in
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
        return try await database.read { db in
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
        return try await database.read { db in
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
        // With the guide switched off there is no snapshot for the answer to show
        // up in, so the panel is not asked.
        if playlist.id == activePlaylistId, !isGuideEnabled { return }
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
        let written: Void? = try? await database.write { db in
            for r in rows { try r.insert(db) }
        }
        return written != nil
    }

    // MARK: - Refresh orchestration

    /// Whether an automatic refresh is due: not while the last success is younger
    /// than the TTL, and not within the cooldown of an attempt that did not end in
    /// success. The cooldown covers a failure that follows an earlier success too:
    /// without it a guide that starts failing is downloaded again on every opening
    /// of the playlist, every return to the app and every reconnect. `fetchedAt`
    /// is stamped when an attempt starts and `lastError` is cleared only by a
    /// success, so an attempt cut short by the app being killed counts as failed
    /// if the one before it failed, and not otherwise.
    nonisolated static func shouldRefresh(source: DBEPGSource?, now: Date) -> Bool {
        guard let source else { return true }
        if let success = source.lastSuccessAt,
           now.timeIntervalSince(success) < EPGConstants.refreshTTL { return false }
        if let attempt = source.fetchedAt,
           source.lastSuccessAt == nil || source.lastError != nil,
           now.timeIntervalSince(attempt) < EPGConstants.retryCooldown { return false }
        return true
    }

    func refreshIfStale(playlist: Playlist) async {
        await refreshIfStale(playlistId: playlist.id, passed: playlist)
    }

    /// For callers that hold no playlist value, or only an old one: the store's own
    /// triggers (return to the foreground, network back). Reads the row and does
    /// nothing when the playlist is gone.
    func refreshIfStale(playlistId: UUID) async {
        await refreshIfStale(playlistId: playlistId, passed: nil)
    }

    private func refreshIfStale(playlistId: UUID, passed: Playlist?) async {
        let stored = await storedGuideState(playlistId: playlistId)
        // The stored row decides what is fetched and whether anything is: a copy
        // may be older than the last save of the switch, the URL or the password.
        guard let playlist = stored?.playlist ?? passed else { return }
        if noteStoredGuideState(stored, passed: playlist) {
            await tick()
            startTimerIfActive()
        }
        guard playlist.epgEnabled else { return }
        guard Self.shouldRefresh(source: stored?.source, now: Date()) else { return }
        // M3U with no configured source → nothing to do.
        if playlist.kind == .m3u, playlist.effectiveEPGURL == nil { return }
        await runRefresh(playlist: playlist)
    }

    /// The Refresh buttons: no TTL, no cooldown. The switch still counts, as read
    /// from the row: with the guide off nothing is downloaded for the playlist.
    func forceRefresh(playlist: Playlist) async {
        let stored = await storedGuideState(playlistId: playlist.id)
        let current = stored?.playlist ?? playlist
        if noteStoredGuideState(stored, passed: current) {
            await tick()
            startTimerIfActive()
        }
        guard current.epgEnabled else { return }
        await runRefresh(playlist: current)
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
        let coordinator = EPGRefreshCoordinator(downloader: downloader, database: database)
        do {
            // Runs off the main actor (`refresh` is `@concurrent`); only the
            // progress closure comes back here.
            _ = try await coordinator.refresh(playlist: playlist) { [weak self] phase in
                self?.refreshState[playlist.id] = .refreshing(phase)
            }
            refreshState[playlist.id] = .idle
            lastSuccess[playlist.id] = Date()
        } catch is CancellationError {
            refreshState[playlist.id] = .idle
            return
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshState[playlist.id] = .failed(message)
        }
        guard playlist.id == activePlaylistId else { return }
        // The attempt has an outcome, so an index that matches nothing now means
        // the playlist has no guide to show (see `tick`). The map is rebuilt after
        // a failure too: a feed that parses but holds none of the playlist's
        // channels is reported as a failure and has replaced the stored guide.
        attemptFinished = true
        await rebuildResolution(playlist: playlist)
        await tick()
    }

    // MARK: - Helpers

    private func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
