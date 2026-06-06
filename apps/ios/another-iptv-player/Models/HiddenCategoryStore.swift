import Foundation
import Combine

/// Playlist + içerik tipi başına gizlenmiş kategori ID'lerini UserDefaults'ta saklar.
/// Yazımda `@Published` versiyon artar; `@ObservedObject` kullanan view'lar otomatik yenilenir.
@MainActor
final class HiddenCategoryStore: ObservableObject {
    static let shared = HiddenCategoryStore()

    @Published private(set) var version: Int = 0

    private init() {}

    private static func storageKey(playlistId: UUID, type: String) -> String {
        "hidden_categories.\(playlistId.uuidString).\(type)"
    }

    func hiddenIds(playlistId: UUID, type: String) -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.storageKey(playlistId: playlistId, type: type)) ?? []
        return Set(arr)
    }

    func isHidden(playlistId: UUID, type: String, categoryId: String) -> Bool {
        hiddenIds(playlistId: playlistId, type: type).contains(categoryId)
    }

    func setHidden(_ hide: Bool, playlistId: UUID, type: String, categoryId: String) {
        var current = hiddenIds(playlistId: playlistId, type: type)
        let changed: Bool
        if hide {
            changed = current.insert(categoryId).inserted
        } else {
            changed = current.remove(categoryId) != nil
        }
        guard changed else { return }
        UserDefaults.standard.set(Array(current), forKey: Self.storageKey(playlistId: playlistId, type: type))
        version &+= 1
    }

    func toggle(playlistId: UUID, type: String, categoryId: String) {
        let isCurrentlyHidden = isHidden(playlistId: playlistId, type: type, categoryId: categoryId)
        setHidden(!isCurrentlyHidden, playlistId: playlistId, type: type, categoryId: categoryId)
    }

    /// Playlist silindiğinde çağrılır — bu playlist'e ait tüm gizli kategori kayıtlarını siler.
    func removeAll(playlistId: UUID) {
        var changed = false
        for type in ["live", "vod", "series", "m3u"] {
            let key = Self.storageKey(playlistId: playlistId, type: type)
            if UserDefaults.standard.object(forKey: key) != nil {
                UserDefaults.standard.removeObject(forKey: key)
                changed = true
            }
        }
        if changed { version &+= 1 }
    }
}
