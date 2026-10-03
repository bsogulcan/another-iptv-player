import Foundation
import GRDB
import Combine

/// M3U favorilerini hem yazar hem de aktif playlist için reactive bir set sunar.
/// `@Published favoriteIds` değiştiğinde UI otomatik güncellenir.
@MainActor
final class M3UFavoriteStore: ObservableObject {
    static let shared = M3UFavoriteStore()

    @Published private(set) var favoriteIds: Set<String> = []
    private var observationCancellable: AnyCancellable?
    private var trackedPlaylistId: UUID?

    @Published private(set) var isLoaded = false
    @Published private var loadError: String?
    private let database: AppDatabase
    private var session = 0

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func isLoaded(for playlistId: UUID) -> Bool {
        trackedPlaylistId == playlistId && isLoaded
    }

    func error(for playlistId: UUID) -> String? {
        trackedPlaylistId == playlistId ? loadError : nil
    }

    /// Aktif playlist değiştiğinde çağrılır; GRDB ValueObservation ile canlı abonelik kurar.
    func track(playlistId: UUID) {
        guard trackedPlaylistId != playlistId || loadError != nil else { return }
        trackedPlaylistId = playlistId
        observationCancellable?.cancel()
        session += 1
        let session = session
        isLoaded = false
        loadError = nil
        favoriteIds = []

        let observation = ValueObservation.tracking { db in
            try String.fetchAll(db,
                                sql: "SELECT channelId FROM m3uFavorite WHERE playlistId = ?",
                                arguments: [playlistId])
        }
        observationCancellable = observation
            .removeDuplicates()
            .publisher(in: database.reader, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.session == session else { return }
                    if case .failure(let error) = completion {
                        Log.error("M3UFavorites", "observation ended: \(error)")
                        // A later track call may restart a failed observation.
                        self.loadError = NetworkErrorText.describe(error)
                        self.isLoaded = false
                        self.favoriteIds = []
                    }
                },
                receiveValue: { [weak self] ids in
                    guard let self, self.session == session else { return }
                    self.favoriteIds = Set(ids)
                    self.isLoaded = true
                }
            )
    }

    func isFavorite(channelId: String) -> Bool {
        favoriteIds.contains(channelId)
    }

    /// Kanalı toggle'la. Callback'siz — ValueObservation yeniden yayacak.
    func toggle(channel: DBM3UChannel) async {
        do {
            try await database.write { db in
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT 1 FROM m3uFavorite WHERE channelId = ? AND playlistId = ? LIMIT 1",
                    arguments: [channel.id, channel.playlistId]
                ) ?? false

                if exists {
                    try db.execute(
                        sql: "DELETE FROM m3uFavorite WHERE channelId = ? AND playlistId = ?",
                        arguments: [channel.id, channel.playlistId]
                    )
                } else {
                    let fav = DBM3UFavorite(
                        channelId: channel.id,
                        playlistId: channel.playlistId
                    )
                    try fav.save(db)
                }
            }
        } catch {
            Log.error("M3UFavorites", "toggle failed: \(error)")
        }
    }
}
