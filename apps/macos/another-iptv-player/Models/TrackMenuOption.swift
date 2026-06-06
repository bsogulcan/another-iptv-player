import Foundation

/// Oynatıcı parçası (video / audio / subtitle) UI menü temsili.
/// iOS'ta VideoPlayerController içinde tanımlıydı; macOS portunda Models'a çekildi
/// çünkü PlaybackTrackPreferences (model) bağımlısı ve player henüz port edilmedi.
struct TrackMenuOption: Identifiable, Hashable {
  let id: Int
  let title: String
  let detail: String?
  let langCode: String?

  init(id: Int, title: String, detail: String? = nil, langCode: String? = nil) {
    self.id = id
    self.title = title
    self.detail = detail
    self.langCode = langCode
  }
}
