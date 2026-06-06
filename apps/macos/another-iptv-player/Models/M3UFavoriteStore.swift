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

    private init() {}

    /// Aktif playlist değiştiğinde çağrılır; GRDB ValueObservation ile canlı abonelik kurar.
    func track(playlistId: UUID) {
        guard trackedPlaylistId != playlistId else { return }
        trackedPlaylistId = playlistId
        observationCancellable?.cancel()

        let observation = ValueObservation.tracking { db in
            try String.fetchAll(db,
                                sql: "SELECT channelId FROM m3uFavorite WHERE playlistId = ?",
                                arguments: [playlistId])
        }
        observationCancellable = observation
            .publisher(in: AppDatabase.shared.reader)
            .catch { _ in Just([]) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                self?.favoriteIds = Set(ids)
            }
    }

    func isFavorite(channelId: String) -> Bool {
        favoriteIds.contains(channelId)
    }

    /// Kanalı toggle'la. Callback'siz — ValueObservation yeniden yayacak.
    func toggle(channel: DBM3UChannel) async {
        do {
            try await AppDatabase.shared.write { db in
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
            print("M3UFavoriteStore toggle error: \(error)")
        }
    }
}
