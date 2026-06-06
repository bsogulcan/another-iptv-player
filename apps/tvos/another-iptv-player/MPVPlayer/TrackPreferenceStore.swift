import Foundation

/// Persisted audio / subtitle / video track preferences, carried across episodes
/// and titles. Mirrors the iOS `PlaybackTrackPreferences` model: the anchor is
/// the normalized language code (the only thing stable across files); when a
/// track has no usable lang, a diacritic-folded title token is stored as a
/// fallback. Subtitles off is a first-class state via a sentinel in
/// `subtitleLang` so it survives round-trips without ambiguity.
enum TrackPreferenceStore {
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

    // MARK: - Writes

    static func saveAudio(from track: MPVTrack) {
        var s = load()
        if let lang = normalizeLang(track.lang), !lang.isEmpty {
            s.audioLang = lang
            s.audioTitleFallback = nil
        } else {
            s.audioLang = nil
            s.audioTitleFallback = normalizeTitleToken(track.displayName)
        }
        save(s)
    }

    static func saveSubtitle(from track: MPVTrack) {
        var s = load()
        if let lang = normalizeLang(track.lang), !lang.isEmpty {
            s.subtitleLang = lang
            s.subtitleTitleFallback = nil
        } else {
            s.subtitleLang = nil
            s.subtitleTitleFallback = normalizeTitleToken(track.displayName)
        }
        save(s)
    }

    static func saveSubtitleDisabled() {
        var s = load()
        s.subtitleLang = subtitleOffSentinel
        s.subtitleTitleFallback = nil
        save(s)
    }

    static func saveVideo(from track: MPVTrack) {
        var s = load()
        if let lang = normalizeLang(track.lang), !lang.isEmpty {
            s.videoLang = lang
            s.videoTitleFallback = nil
        } else {
            s.videoLang = nil
            s.videoTitleFallback = normalizeTitleToken(track.displayName)
        }
        save(s)
    }

    // MARK: - Reads

    /// Returns the track to auto-select for audio, or nil to keep mpv's default.
    static func pickAudio(from tracks: [MPVTrack], prefs: Storage) -> MPVTrack? {
        guard !tracks.isEmpty else { return nil }
        if let lang = prefs.audioLang, !lang.isEmpty,
           let t = tracks.first(where: { langMatches(stored: lang, trackLang: $0.lang) }) {
            return t
        }
        if let fb = prefs.audioTitleFallback, !fb.isEmpty,
           let t = tracks.first(where: { normalizeTitleToken($0.displayName) == fb }) {
            return t
        }
        return nil
    }

    /// Returns the track to auto-select for video, or nil to keep mpv's default.
    static func pickVideo(from tracks: [MPVTrack], prefs: Storage) -> MPVTrack? {
        guard !tracks.isEmpty else { return nil }
        if let lang = prefs.videoLang, !lang.isEmpty,
           let t = tracks.first(where: { langMatches(stored: lang, trackLang: $0.lang) }) {
            return t
        }
        if let fb = prefs.videoTitleFallback, !fb.isEmpty,
           let t = tracks.first(where: { normalizeTitleToken($0.displayName) == fb }) {
            return t
        }
        return nil
    }

    enum SubtitleResolution: Equatable {
        case disabled
        case track(MPVTrack)
        case noPreference
    }

    static func pickSubtitle(from tracks: [MPVTrack], prefs: Storage) -> SubtitleResolution {
        if prefs.subtitleLang == subtitleOffSentinel { return .disabled }
        guard !tracks.isEmpty else { return .noPreference }
        if let lang = prefs.subtitleLang, !lang.isEmpty,
           let t = tracks.first(where: { langMatches(stored: lang, trackLang: $0.lang) }) {
            return .track(t)
        }
        if let fb = prefs.subtitleTitleFallback, !fb.isEmpty,
           let t = tracks.first(where: { normalizeTitleToken($0.displayName) == fb }) {
            return .track(t)
        }
        return .noPreference
    }

    // MARK: - Normalization

    static func normalizeLang(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty else { return nil }
        if let r = s.firstIndex(of: "-") { s = String(s[..<r]) }
        if let r = s.firstIndex(of: "_") { s = String(s[..<r]) }
        return s.isEmpty ? nil : s
    }

    /// Loose match: exact, prefix either direction, or matching 2-letter
    /// ISO-639-1 head (covers `eng` vs `en`, `tur-TR` vs `tr`, etc.).
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
