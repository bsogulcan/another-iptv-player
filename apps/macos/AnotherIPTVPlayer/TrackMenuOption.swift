import Foundation

struct TrackMenuOption: Identifiable, Hashable {
  let id: Int
  let title: String
  let detail: String?
  let langCode: String?
  /// mpv `track-list/N/external`: external file track added via `sub-add`.
  let isExternal: Bool
  /// Başlık gerçek metadata değil, index'ten türetilmiş ("Parça 2" gibi). Tercih olarak
  /// SAKLANMAMALI — bir sonraki videoda pozisyonu aynı olan alakasız parçayı seçtirir.
  let isSyntheticTitle: Bool

  init(
    id: Int, title: String, detail: String? = nil, langCode: String? = nil,
    isExternal: Bool = false, isSyntheticTitle: Bool = false
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.langCode = langCode
    self.isExternal = isExternal
    self.isSyntheticTitle = isSyntheticTitle
  }
}
