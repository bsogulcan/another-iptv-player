import Foundation

/// Kullanıcının seçtiği ses / altyazı / görüntü parçası tercihleri; sonraki videolarda dil veya başlık eşleşmesiyle uygulanır.
enum PlaybackTrackPreferences {
  private static let key = "playback.trackPreferences.v1"
  private static let subtitleOffSentinel = "__off__"

  struct Storage: Codable, Equatable {
    var audioLang: String?
    var audioTitleFallback: String?
    var subtitleLang: String?
    var subtitleTitleFallback: String?
    var videoLang: String?
    var videoTitleFallback: String?
  }

  static func load() -> Storage {
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode(Storage.self, from: data)
    else {
      return Storage()
    }
    return decoded
  }

  private static func save(_ storage: Storage) {
    guard let data = try? JSONEncoder().encode(storage) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  static func saveAudio(from option: TrackMenuOption) {
    var s = load()
    if let lang = option.normalizedLang, !lang.isEmpty {
      s.audioLang = lang
      s.audioTitleFallback = nil
    } else {
      s.audioLang = nil
      s.audioTitleFallback = normalizeTitleToken(option.title)
    }
    save(s)
  }

  static func saveSubtitle(from option: TrackMenuOption) {
    var s = load()
    if option.id < 0 {
      s.subtitleLang = subtitleOffSentinel
      s.subtitleTitleFallback = nil
    } else if let lang = option.normalizedLang, !lang.isEmpty {
      s.subtitleLang = lang
      s.subtitleTitleFallback = nil
    } else {
      s.subtitleLang = nil
      s.subtitleTitleFallback = normalizeTitleToken(option.title)
    }
    save(s)
  }

  static func saveVideo(from option: TrackMenuOption) {
    var s = load()
    if let lang = option.normalizedLang, !lang.isEmpty {
      s.videoLang = lang
      s.videoTitleFallback = nil
    } else {
      s.videoLang = nil
      s.videoTitleFallback = normalizeTitleToken(option.title)
    }
    save(s)
  }

  /// `nil` = mevcut mpv seçimini koru.
  static func pickVideo(from tracks: [TrackMenuOption], prefs: Storage) -> Int? {
    guard !tracks.isEmpty else { return nil }
    if let lang = prefs.videoLang, !lang.isEmpty,
       let t = tracks.first(where: { langMatches(stored: lang, trackLang: $0.normalizedLang) })
    {
      return t.id
    }
    if let fb = prefs.videoTitleFallback, !fb.isEmpty,
       let t = tracks.first(where: { normalizeTitleToken($0.title) == fb })
    {
      return t.id
    }
    return nil
  }

  static func pickAudio(from tracks: [TrackMenuOption], prefs: Storage) -> Int? {
    guard !tracks.isEmpty else { return nil }
    if let lang = prefs.audioLang, !lang.isEmpty,
       let t = tracks.first(where: { langMatches(stored: lang, trackLang: $0.normalizedLang) })
    {
      return t.id
    }
    if let fb = prefs.audioTitleFallback, !fb.isEmpty,
       let t = tracks.first(where: { normalizeTitleToken($0.title) == fb })
    {
      return t.id
    }
    return nil
  }

  /// Dönüş `-1` = altyazı kapalı.
  static func pickSubtitle(from tracks: [TrackMenuOption], prefs: Storage) -> Int? {
    if prefs.subtitleLang == subtitleOffSentinel { return -1 }
    let realTracks = tracks.filter { $0.id >= 0 }
    guard !realTracks.isEmpty else { return nil }
    if let lang = prefs.subtitleLang, !lang.isEmpty,
       let t = realTracks.first(where: { langMatches(stored: lang, trackLang: $0.normalizedLang) })
    {
      return t.id
    }
    if let fb = prefs.subtitleTitleFallback, !fb.isEmpty,
       let t = realTracks.first(where: { normalizeTitleToken($0.title) == fb })
    {
      return t.id
    }
    return nil
  }

  static func normalizeLang(_ raw: String?) -> String? {
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else {
      return nil
    }
    if let r = s.firstIndex(of: "-") { s = String(s[..<r]) }
    if let r = s.firstIndex(of: "_") { s = String(s[..<r]) }
    return s.isEmpty ? nil : s
  }

  static func langMatches(stored: String, trackLang: String?) -> Bool {
    guard let t = normalizeLang(trackLang) else { return false }
    let s = normalizeLang(stored) ?? stored.lowercased()
    if t == s { return true }
    if t.hasPrefix(s) || s.hasPrefix(t) { return true }
    let s2 = String(s.prefix(2))
    let t2 = String(t.prefix(2))
    if s2.count == 2, t2.count == 2, s2 == t2 { return true }
    return false
  }

  static func normalizeTitleToken(_ raw: String) -> String {
    raw
      .folding(options: .diacriticInsensitive, locale: .current)
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension TrackMenuOption {
  var normalizedLang: String? {
    PlaybackTrackPreferences.normalizeLang(langCode)
  }
}
