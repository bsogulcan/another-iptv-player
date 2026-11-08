import Foundation
import GRDB

nonisolated enum WatchHistoryWriter {
    /// Removes one history row by its id. A row that is already gone is not an error.
    static func remove(id: String, in database: AppDatabase) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM watchHistory WHERE id = ?", arguments: [id])
        }
    }
}
