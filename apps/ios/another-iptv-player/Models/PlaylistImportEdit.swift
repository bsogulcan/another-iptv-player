import Foundation
import GRDB

enum PlaylistImportConflict: LocalizedError {
    case changed
    var errorDescription: String? { L("playlist.import.changed") }
}

extension Playlist {
    nonisolated func usesSameProvider(as other: Playlist) -> Bool {
        id == other.id && kind == other.kind && serverURL == other.serverURL
            && username == other.username && password == other.password
    }

    /// Merge only the form's changes onto the live row in the catalogue write.
    /// The downloaded rows belong to the credentials the request started with.
    nonisolated func mergingImportEdit(from original: Playlist, in db: Database) throws -> Playlist {
        guard id == original.id, var current = try Playlist.fetchOne(db, key: id),
              current.usesSameProvider(as: original) else {
            throw PlaylistImportConflict.changed
        }
        if name != original.name {
            guard current.name == original.name || current.name == name else { throw PlaylistImportConflict.changed }
            current.name = name
        }
        if filterAdultContent != original.filterAdultContent { current.filterAdultContent = filterAdultContent }
        let providerChanged = serverURL != original.serverURL || username != original.username || password != original.password
        current.serverURL = serverURL
        current.username = username
        current.password = password
        if providerChanged {
            current.timeshiftStyle = nil
            current.serverTimezone = kind == .xtream ? serverTimezone : nil
        } else if let serverTimezone, current.serverTimezone == original.serverTimezone {
            current.serverTimezone = serverTimezone
        }
        return current
    }
}
