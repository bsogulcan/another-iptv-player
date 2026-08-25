import Foundation
import CryptoKit

/// Stable, non-secret identifier for a playlist, used to scope sync items
/// (`sync/key = "<sourceKey>:<contentType>:<contentId>"`). Derived from the
/// server + account identity rather than the local playlist row id, which is
/// generated per install and would differ across a user's devices for what
/// is otherwise "the same playlist". The password is deliberately excluded
/// so it never reaches the sync server. Swift counterpart of the Tizen
/// client's `playlistSourceKey` (`apps/tizen/src/sync/sourceKey.ts`).
func playlistSourceKey(_ playlist: Playlist) -> String {
    let raw = "\(playlist.kind.rawValue):\(playlist.serverURL):\(playlist.username)"
    let digest = SHA256.hash(data: Data(raw.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
