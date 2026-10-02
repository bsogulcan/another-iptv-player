import Foundation
import GRDB
import Combine

/// The favourite ids of one Xtream playlist, per content type. The type strings are
/// the ones `DBFavorite.type` stores: "live", "vod", "series".
nonisolated struct XtreamFavoriteIDs: Equatable, Sendable {
    var live: Set<Int> = []
    var vod: Set<Int> = []
    var series: Set<Int> = []

    func contains(_ streamId: Int, type: String) -> Bool {
        switch type {
        case "live": return live.contains(streamId)
        case "vod": return vod.contains(streamId)
        case "series": return series.contains(streamId)
        default: return false
        }
    }

    /// An unknown type is ignored, as it is never a favourite.
    mutating func set(_ favorite: Bool, streamId: Int, type: String) {
        switch type {
        case "live": Self.update(&live, favorite, streamId)
        case "vod": Self.update(&vod, favorite, streamId)
        case "series": Self.update(&series, favorite, streamId)
        default: break
        }
    }

    private static func update(_ ids: inout Set<Int>, _ favorite: Bool, _ streamId: Int) {
        if favorite {
            ids.insert(streamId)
        } else {
            ids.remove(streamId)
        }
    }
}

/// Writes Xtream favourites. Every writer states the row it wants instead of
/// flipping what it believes is there: a second tap that arrives before the first
/// write is visible then repeats the same statement and changes nothing, where an
/// unconditional insert ran into the primary key.
///
/// `nonisolated`: the statements run on the database's writer queue.
nonisolated enum FavoriteWriter {
    /// Makes the item a favourite, or not one. Setting the state it already has is
    /// not an error and leaves the row (and its date) as it is.
    static func set(
        _ favorite: Bool,
        streamId: Int,
        type: String,
        playlistId: UUID,
        in database: AppDatabase
    ) async throws {
        try await database.write { db in
            if favorite {
                try insert(streamId: streamId, type: type, playlistId: playlistId, db: db)
            } else {
                try delete(streamId: streamId, type: type, playlistId: playlistId, db: db)
            }
        }
    }

    /// Flips the stored state and returns the new one. The state is read inside the
    /// write, for a caller that does not know it. A caller that shows the state
    /// should use `set` with the state its label promised.
    @discardableResult
    static func toggle(
        streamId: Int,
        type: String,
        playlistId: UUID,
        in database: AppDatabase
    ) async throws -> Bool {
        try await database.write { db in
            let isFavorite = try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM favorite WHERE streamId = ? AND playlistId = ? AND type = ? LIMIT 1",
                arguments: [streamId, playlistId, type]
            ) ?? false
            if isFavorite {
                try delete(streamId: streamId, type: type, playlistId: playlistId, db: db)
            } else {
                try insert(streamId: streamId, type: type, playlistId: playlistId, db: db)
            }
            return !isFavorite
        }
    }

    /// All favourite ids of a playlist, grouped by type.
    static func ids(playlistId: UUID, db: Database) throws -> XtreamFavoriteIDs {
        var ids = XtreamFavoriteIDs()
        let rows = try Row.fetchCursor(
            db,
            sql: "SELECT streamId, type FROM favorite WHERE playlistId = ?",
            arguments: [playlistId]
        )
        while let row = try rows.next() {
            ids.set(true, streamId: row[0], type: row[1])
        }
        return ids
    }

    private static func insert(streamId: Int, type: String, playlistId: UUID, db: Database) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO favorite (streamId, playlistId, type, createdAt) VALUES (?, ?, ?, ?)",
            arguments: [streamId, playlistId, type, Date()]
        )
    }

    private static func delete(streamId: Int, type: String, playlistId: UUID, db: Database) throws {
        try db.execute(
            sql: "DELETE FROM favorite WHERE streamId = ? AND playlistId = ? AND type = ?",
            arguments: [streamId, playlistId, type]
        )
    }
}

/// The favourites of the active Xtream playlist, in memory.
///
/// Lists need to know whether an item is a favourite (context menus, the star on a
/// detail page) without opening a database observation per card. This store keeps
/// one observation for the whole playlist and answers from a set.
///
/// It is not the only writer. Screens that write `DBFavorite` rows themselves keep
/// doing so; the observation picks every change up, whoever made it.
///
/// Cards must not observe the store: one toggle would then re-render every card a
/// lazy stack keeps alive. Observe it in the small view that shows the state (a
/// menu item, a star button).
@MainActor
final class XtreamFavoriteStore: ObservableObject {
    static let shared = XtreamFavoriteStore()

    /// Favourite ids of the tracked playlist. Empty until `track(playlistId:)` was
    /// called and its first read arrived.
    @Published private(set) var ids = XtreamFavoriteIDs()

    private(set) var trackedPlaylistId: UUID?
    /// Whether `ids` has been read from the database for the tracked playlist.
    private var isLoaded = false

    /// Counts `track` calls that changed the playlist, so work that was started
    /// for an earlier playlist can tell it is no longer wanted.
    private var session = 0
    /// Writes of this store to the tracked playlist that have not finished.
    private var pendingWrites = 0
    /// An observed value was left out while a write was pending, or a write failed:
    /// `ids` has to be read again once the last pending write is done.
    private var needsReload = false
    /// The most recent write of this store. Each write waits for the one before
    /// it: two taps in a row otherwise reach the writer queue in either order, and
    /// "on, then off" could end as "on".
    private var lastWrite: Task<Bool, Never>?

    private let database: AppDatabase
    private var observation: AnyCancellable?

    /// The app uses `shared`. Tests pass a database of their own.
    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Starts following a playlist's favourites; call it when the playlist becomes
    /// the active one. Calling it again for the same playlist does nothing.
    func track(playlistId: UUID) {
        guard trackedPlaylistId != playlistId else { return }
        trackedPlaylistId = playlistId
        session += 1
        isLoaded = false
        pendingWrites = 0
        needsReload = false
        observation?.cancel()
        // The previous playlist's ids must not answer for this one while its first
        // read is on the way: stream ids repeat between panels.
        if ids != XtreamFavoriteIDs() {
            ids = XtreamFavoriteIDs()
        }

        observation = ValueObservation
            .tracking { db in try FavoriteWriter.ids(playlistId: playlistId, db: db) }
            .removeDuplicates()
            .publisher(in: database.reader)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        Log.error("Favorites", "observation ended: \(error)")
                    }
                },
                receiveValue: { [weak self] value in
                    guard let self, self.trackedPlaylistId == playlistId else { return }
                    // While a write of this store is on its way, `ids` is ahead of
                    // the database. A value read before that write would take the
                    // change back for a moment (a star that flickers on a double
                    // tap), so it is left out and `ids` is read again afterwards.
                    guard self.pendingWrites == 0 else {
                        self.needsReload = true
                        return
                    }
                    self.isLoaded = true
                    if self.ids != value {
                        self.ids = value
                    }
                }
            )
    }

    /// Whether the item is a favourite in the tracked playlist.
    func isFavorite(_ streamId: Int, type: String) -> Bool {
        ids.contains(streamId, type: type)
    }

    /// As `isFavorite(_:type:)`, for a caller that cannot be sure its playlist is
    /// the tracked one: nil while the store cannot tell (another playlist is
    /// tracked, or the first read has not arrived).
    func favoriteState(_ streamId: Int, type: String, playlistId: UUID) -> Bool? {
        guard playlistId == trackedPlaylistId, isLoaded else { return nil }
        return ids.contains(streamId, type: type)
    }

    /// Writes the state. For the tracked playlist `ids` changes at once, before the
    /// write: the star or the menu label answers the tap immediately, and a second
    /// tap sees the new state. Returns when the write is done and `ids` agrees with
    /// the database again.
    func setFavorite(_ favorite: Bool, streamId: Int, type: String, playlistId: UUID) async {
        let isTracked = playlistId == trackedPlaylistId
        let session = session
        if isTracked {
            var updated = ids
            updated.set(favorite, streamId: streamId, type: type)
            if updated != ids {
                ids = updated
            }
            pendingWrites += 1
        }

        // A task of its own, so the write also happens when the caller's task is
        // cancelled (a menu or a screen that goes away right after the tap).
        let previous = lastWrite
        let database = database
        let write = Task { () -> Bool in
            _ = await previous?.value
            do {
                try await FavoriteWriter.set(favorite, streamId: streamId, type: type, playlistId: playlistId, in: database)
                return true
            } catch {
                Log.error("Favorites", "write failed (\(type) \(streamId)): \(error)")
                return false
            }
        }
        lastWrite = write
        let succeeded = await write.value

        // Another playlist is tracked by now: its counters were reset and are not
        // this write's to touch.
        guard isTracked, session == self.session else { return }
        pendingWrites -= 1
        if !succeeded {
            // Nothing reached the database, so no observation will take the early
            // update back.
            needsReload = true
        }
        if pendingWrites == 0, needsReload {
            await reload()
        }
    }

    /// Flips the state of an item.
    func toggle(_ streamId: Int, type: String, playlistId: UUID) async {
        if let isFavorite = favoriteState(streamId, type: type, playlistId: playlistId) {
            await setFavorite(!isFavorite, streamId: streamId, type: type, playlistId: playlistId)
            return
        }
        // The store does not know the current state: let the database decide.
        do {
            try await FavoriteWriter.toggle(streamId: streamId, type: type, playlistId: playlistId, in: database)
        } catch {
            Log.error("Favorites", "toggle failed (\(type) \(streamId)): \(error)")
        }
    }

    /// Reads the tracked playlist's ids. The read happens after the writes it
    /// follows, so its result includes them.
    private func reload() async {
        guard let playlistId = trackedPlaylistId else { return }
        let session = session
        needsReload = false
        let stored = try? await database.read { db in
            try FavoriteWriter.ids(playlistId: playlistId, db: db)
        }
        guard session == self.session else { return }
        guard let stored, pendingWrites == 0 else {
            // A write that started meanwhile is ahead of this read (or the read
            // failed): try again when the next write is done.
            needsReload = true
            return
        }
        isLoaded = true
        if ids != stored {
            ids = stored
        }
    }
}
