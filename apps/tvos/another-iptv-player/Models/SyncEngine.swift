import Foundation
import Combine
import GRDB

enum SyncStatus: Equatable {
    case idle
    case syncing
    case error(String)
}

/// Drives the self-hosted sync feature: queues local watch-progress changes
/// to an on-device outbox, flushes them to the configured sync-server, and
/// applies what other devices pushed — including favorites and hidden
/// categories, which this platform doesn't have UI for yet but which land
/// in the same GRDB tables the other platforms already write to. Swift
/// counterpart of the Tizen client's `sync/syncEngine.ts`.
///
/// Entirely opt-in — every enqueue method is a no-op until a server URL and
/// device token are configured, so nothing here runs for users who never
/// turn sync on.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published private(set) var status: SyncStatus = .idle

    private let api = SyncAPIClient()
    private var syncTask: Task<Void, Never>?
    private var pushDebounceTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private init() {}

    // MARK: - Config (UserDefaults-backed)

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let serverURL = "sync.serverURL"
        static let deviceToken = "sync.deviceToken"
        static let deviceId = "sync.deviceId"
        static let accountUsername = "sync.accountUsername"
        static let autoSyncEnabled = "sync.autoSyncEnabled"
        static let intervalMinutes = "sync.intervalMinutes"
        static let cursor = "sync.cursor"
        static let lastSyncedAt = "sync.lastSyncedAt"
        static let lastSyncError = "sync.lastSyncError"
    }

    var serverURL: String? {
        get { defaults.string(forKey: Keys.serverURL) }
        set { defaults.set(newValue, forKey: Keys.serverURL) }
    }

    var deviceToken: String? {
        get { defaults.string(forKey: Keys.deviceToken) }
        set { defaults.set(newValue, forKey: Keys.deviceToken) }
    }

    var deviceId: Int64? {
        get {
            guard let value = defaults.object(forKey: Keys.deviceId) as? NSNumber else { return nil }
            return value.int64Value
        }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: Keys.deviceId) }
    }

    var accountUsername: String? {
        get { defaults.string(forKey: Keys.accountUsername) }
        set { defaults.set(newValue, forKey: Keys.accountUsername) }
    }

    var autoSyncEnabled: Bool {
        get { (defaults.object(forKey: Keys.autoSyncEnabled) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Keys.autoSyncEnabled) }
    }

    /// Minutes between periodic syncs while the app is running; 0 = manual only.
    var intervalMinutes: Int {
        get { (defaults.object(forKey: Keys.intervalMinutes) as? Int) ?? 30 }
        set { defaults.set(newValue, forKey: Keys.intervalMinutes) }
    }

    /// Delta-pull cursor. Reset to 0 to force a full replay from the server.
    var cursor: Int64 {
        get { Int64(defaults.integer(forKey: Keys.cursor)) }
        set { defaults.set(newValue, forKey: Keys.cursor) }
    }

    var lastSyncedAt: Date? {
        get { defaults.object(forKey: Keys.lastSyncedAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastSyncedAt) }
    }

    var lastSyncError: String? {
        get { defaults.string(forKey: Keys.lastSyncError) }
        set { defaults.set(newValue, forKey: Keys.lastSyncError) }
    }

    var isConfigured: Bool { serverURL != nil && deviceToken != nil }

    /// A newly added playlist might match one another device already pushed
    /// favorites/progress for before this device ever synced; those pushes
    /// are behind the current cursor, so replay from the start to pick them up.
    func resetCursor() { cursor = 0 }

    func clearAccount() {
        deviceToken = nil
        deviceId = nil
        accountUsername = nil
        cursor = 0
        lastSyncedAt = nil
        lastSyncError = nil
    }

    // MARK: - Lifecycle

    /// Called once at app launch.
    func bootSync() {
        if isConfigured { runSync() }
        startPeriodicSync()
    }

    /// Push pending local changes, then pull and apply remote changes.
    /// Concurrent callers share one in-flight run.
    @discardableResult
    func runSync() -> Task<Void, Never> {
        if let existing = syncTask, !existing.isCancelled { return existing }
        let task = Task { [weak self] in
            guard let self else { return }
            guard self.isConfigured else { return }
            self.status = .syncing
            do {
                try await self.flushOutbox()
                try await self.pullAndApply()
                self.lastSyncedAt = Date()
                self.lastSyncError = nil
                self.status = .idle
            } catch {
                self.lastSyncError = error.localizedDescription
                self.status = .error(error.localizedDescription)
            }
            self.syncTask = nil
        }
        syncTask = task
        return task
    }

    /// Call after queuing a local change: pushes soon without waiting for the full periodic interval.
    func schedulePush() {
        guard isConfigured else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.runSync()
        }
    }

    func startPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = nil
        guard isConfigured, autoSyncEnabled, intervalMinutes > 0 else { return }
        let intervalNanos = UInt64(intervalMinutes) * 60_000_000_000
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                if Task.isCancelled { return }
                guard let self else { return }
                await self.runSync().value
            }
        }
    }

    func stopPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    // MARK: - Account

    func register(serverURL: String, username: String, password: String) async throws {
        try await api.register(serverURL: serverURL, username: username, password: password)
    }

    /// Signs in, persists the resulting device token, and (re)starts periodic sync.
    func signIn(serverURL: String, username: String, password: String, deviceName: String) async throws {
        let response = try await api.requestDeviceToken(
            serverURL: serverURL, username: username, password: password, deviceName: deviceName
        )
        self.serverURL = serverURL
        self.deviceToken = response.token
        self.deviceId = response.deviceId
        self.accountUsername = username
        self.cursor = 0
        startPeriodicSync()
        runSync()
    }

    /// Revokes this device's token server-side (best-effort) and forgets local sync state.
    func signOut() async {
        if let deviceId, let serverURL, let deviceToken {
            _ = try? await api.revokeDevice(serverURL: serverURL, token: deviceToken, deviceId: deviceId)
        }
        clearAccount()
        stopPeriodicSync()
    }

    func listDevices() async throws -> [SyncDeviceInfo] {
        guard let serverURL, let deviceToken else { throw SyncAPIError.invalidURL }
        return try await api.listDevices(serverURL: serverURL, token: deviceToken)
    }

    func revokeDevice(_ deviceId: Int64) async throws {
        guard let serverURL, let deviceToken else { throw SyncAPIError.invalidURL }
        try await api.revokeDevice(serverURL: serverURL, token: deviceToken, deviceId: deviceId)
        if deviceId == self.deviceId {
            clearAccount()
            stopPeriodicSync()
        }
    }

    func outboxCount() async -> Int {
        (try? await AppDatabase.shared.read { db in try DBSyncOutboxItem.fetchCount(db) }) ?? 0
    }

    // MARK: - Enqueue (best-effort: never throws, sync must not break local writes)

    func enqueueFavoriteChange(playlistId: UUID, contentType: String, itemId: String, favorited: Bool) {
        guard isConfigured else { return }
        Task { [weak self] in
            guard let self else { return }
            if let playlist = await self.findPlaylist(playlistId) {
                let sourceKey = playlistSourceKey(playlist)
                await self.appendOutbox(DBSyncOutboxItem(
                    kind: "favorite",
                    key: "\(sourceKey):\(contentType):\(itemId)",
                    payload: "{}",
                    updatedAt: Self.nowMs(),
                    deleted: !favorited
                ))
            }
            self.schedulePush()
        }
    }

    func enqueueProgressChange(_ history: DBWatchHistory) {
        guard isConfigured else { return }
        Task { [weak self] in
            guard let self else { return }
            if let playlist = await self.findPlaylist(history.playlistId) {
                let sourceKey = playlistSourceKey(playlist)
                let payload = SyncPayload(
                    positionSeconds: Double(history.lastTimeMs) / 1000.0,
                    durationSeconds: Double(history.durationMs) / 1000.0,
                    title: history.title,
                    secondaryTitle: history.secondaryTitle,
                    imageURL: history.imageURL,
                    containerExtension: history.containerExtension,
                    seriesId: history.seriesId
                )
                let payloadData = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
                let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
                await self.appendOutbox(DBSyncOutboxItem(
                    kind: "progress",
                    key: "\(sourceKey):\(history.type):\(history.streamId)",
                    payload: payloadString,
                    updatedAt: Int64(history.lastWatchedAt.timeIntervalSince1970 * 1000),
                    deleted: false
                ))
            }
            self.schedulePush()
        }
    }

    func enqueueProgressDelete(playlistId: UUID, type: String, streamId: String) {
        guard isConfigured else { return }
        Task { [weak self] in
            guard let self else { return }
            if let playlist = await self.findPlaylist(playlistId) {
                let sourceKey = playlistSourceKey(playlist)
                await self.appendOutbox(DBSyncOutboxItem(
                    kind: "progress",
                    key: "\(sourceKey):\(type):\(streamId)",
                    payload: "{}",
                    updatedAt: Self.nowMs(),
                    deleted: true
                ))
            }
            self.schedulePush()
        }
    }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func findPlaylist(_ id: UUID) async -> Playlist? {
        do {
            return try await AppDatabase.shared.read { db in try Playlist.fetchOne(db, key: id) }
        } catch {
            return nil
        }
    }

    private func appendOutbox(_ item: DBSyncOutboxItem) async {
        do {
            try await AppDatabase.shared.write { db in try item.insert(db) }
        } catch {
            // best-effort — sync must not break the local write that already succeeded
        }
    }

    // MARK: - Push

    private func flushOutbox() async throws {
        guard let serverURL, let deviceToken else { return }
        while true {
            let batch = try await AppDatabase.shared.read { db in
                try DBSyncOutboxItem.order(Column("createdAt")).limit(500).fetchAll(db)
            }
            if batch.isEmpty { return }

            let wireItems: [SyncWireItem] = batch.map { row in
                let payload = (try? JSONDecoder().decode(SyncPayload.self, from: Data(row.payload.utf8))) ?? .empty
                return SyncWireItem(kind: row.kind, key: row.key, payload: payload, updatedAt: row.updatedAt, deleted: row.deleted)
            }
            // Both "applied" and "stale" mean the server accepted the request
            // and processed it (stale just means a newer write already won)
            // — either way this device's copy of that item is no longer pending.
            _ = try await api.push(items: wireItems, serverURL: serverURL, token: deviceToken)

            let ids = batch.map { $0.id }
            try await AppDatabase.shared.write { db in
                try DBSyncOutboxItem.deleteAll(db, keys: ids)
            }
        }
    }

    // MARK: - Pull

    private func pullAndApply() async throws {
        guard let serverURL, let deviceToken else { return }
        while true {
            let result = try await api.pull(since: cursor, serverURL: serverURL, token: deviceToken)
            if !result.items.isEmpty {
                let playlists = try await AppDatabase.shared.read { db in try Playlist.fetchAll(db) }
                var bySourceKey: [String: Playlist] = [:]
                for playlist in playlists {
                    bySourceKey[playlistSourceKey(playlist)] = playlist
                }
                for item in result.items {
                    try await applyPulledItem(item, playlistsBySourceKey: bySourceKey)
                }
            }
            cursor = result.cursor
            if !result.hasMore { return }
        }
    }

    private func applyPulledItem(_ item: SyncWireItem, playlistsBySourceKey: [String: Playlist]) async throws {
        let parts = item.key.components(separatedBy: ":")
        guard parts.count >= 3 else { return }
        let sourceKey = parts[0]
        let contentType = parts[1]
        let contentId = parts.dropFirst(2).joined(separator: ":")
        guard let playlist = playlistsBySourceKey[sourceKey] else { return }

        switch item.kind {
        case "favorite":
            try await applyFavorite(playlistId: playlist.id, contentType: contentType, itemId: contentId, deleted: item.deleted)
        case "progress":
            try await applyProgress(playlistId: playlist.id, type: contentType, streamId: contentId, item: item)
        default:
            // "hidden_category" included — this platform has no UI for it yet.
            break
        }
    }

    private func applyFavorite(playlistId: UUID, contentType: String, itemId: String, deleted: Bool) async throws {
        if contentType == "m3u" {
            try await AppDatabase.shared.write { db in
                if deleted {
                    try db.execute(
                        sql: "DELETE FROM m3uFavorite WHERE channelId = ? AND playlistId = ?",
                        arguments: [itemId, playlistId]
                    )
                } else {
                    let fav = DBM3UFavorite(channelId: itemId, playlistId: playlistId)
                    try fav.save(db)
                }
            }
            return
        }
        guard let streamId = Int(itemId) else { return }
        try await AppDatabase.shared.write { db in
            if deleted {
                try DBFavorite
                    .filter(Column("streamId") == streamId && Column("playlistId") == playlistId && Column("type") == contentType)
                    .deleteAll(db)
            } else {
                let fav = DBFavorite(streamId: streamId, playlistId: playlistId, type: contentType)
                try fav.save(db)
            }
        }
    }

    private func applyProgress(playlistId: UUID, type: String, streamId: String, item: SyncWireItem) async throws {
        let id = "\(playlistId)_\(type)_\(streamId)"
        if item.deleted {
            try await AppDatabase.shared.write { db in
                try DBWatchHistory.filter(Column("id") == id).deleteAll(db)
            }
            return
        }
        let payload = item.payload
        let history = DBWatchHistory(
            id: id,
            playlistId: playlistId,
            streamId: streamId,
            type: type,
            lastTimeMs: Int((payload.positionSeconds ?? 0) * 1000),
            durationMs: Int((payload.durationSeconds ?? 0) * 1000),
            lastWatchedAt: Date(timeIntervalSince1970: Double(item.updatedAt) / 1000.0),
            seriesId: payload.seriesId,
            title: payload.title ?? streamId,
            secondaryTitle: payload.secondaryTitle,
            imageURL: payload.imageURL,
            containerExtension: payload.containerExtension
        )
        try await AppDatabase.shared.write { db in try history.save(db) }
    }
}
