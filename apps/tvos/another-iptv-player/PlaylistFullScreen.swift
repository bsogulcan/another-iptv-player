import Foundation

/// Playlist ekleme / düzenleme tam ekran sunumu.
enum PlaylistFullScreen: Identifiable, Equatable {
    /// Tür seç → (Xtream | M3U) form; tek `NavigationStack` içinde.
    case add
    case edit(Playlist)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let p): return "edit-\(p.id.uuidString)"
        }
    }
}
