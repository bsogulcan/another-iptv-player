import Foundation

/// Kullanıcının seçtiği ses / altyazı / görüntü parçası tercihleri; sonraki videolarda dil veya başlık eşleşmesiyle uygulanır.
enum PlaybackTrackPreferences {
  nonisolated private static let key = "playback.trackPreferences.v1"
  nonisolated private static let subtitleOffSentinel = "__off__"

  /// `nonisolated`, like `load()` and the language helpers below: the audio language is
  /// also read on KSPlayer's open thread, before playback starts (`preferredAudioIndex`).
  nonisolated struct Storage: Codable, Equatable {
    var audioLang: String?
    var audioTitleFallback: String?
    var subtitleLang: String?
    var subtitleTitleFallback: String?
    var videoLang: String?
    var videoTitleFallback: String?
  }

  nonisolated static func load() -> Storage {
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode(Storage.self, from: data)
    else {
      return Storage()
    }
    return migrated(decoded)
  }

  private static func save(_ storage: Storage) {
    guard let data = try? JSONEncoder().encode(storage) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  /// Up to 2.4.0 subtitle rows carried no language code, so choosing an untitled track
  /// stored its language tag ("tur") as a title. Rows are now titled with the language's
  /// name, which that token can never equal; read it as the language it is.
  nonisolated static func migrated(_ storage: Storage) -> Storage {
    var s = storage
    if s.subtitleLang == nil, let token = s.subtitleTitleFallback, isKnownLanguageCode(token) {
      s.subtitleLang = token
      s.subtitleTitleFallback = nil
    }
    return s
  }

  static func saveAudio(from option: TrackMenuOption) {
    guard let s = storage(load(), savingAudio: option) else { return }
    save(s)
  }

  static func saveSubtitle(from option: TrackMenuOption) {
    guard let s = storage(load(), savingSubtitle: option) else { return }
    save(s)
  }

  static func saveVideo(from option: TrackMenuOption) {
    guard let s = storage(load(), savingVideo: option) else { return }
    save(s)
  }

  /// The stored preferences after choosing `option`, or nil when the choice says nothing
  /// a later item could be matched by and what is stored stays as it is.
  static func storage(_ current: Storage, savingAudio option: TrackMenuOption) -> Storage? {
    var s = current
    if let lang = option.normalizedLang, !lang.isEmpty {
      s.audioLang = lang
      s.audioTitleFallback = nil
    } else if !option.isSyntheticTitle {
      s.audioLang = nil
      s.audioTitleFallback = normalizeTitleToken(option.title)
    } else {
      // Sentetik ("Parça N") başlık saklanmaz: pozisyon bazlı olduğundan sonraki
      // videoda alakasız bir parçayı otomatik seçtirir.
      return nil
    }
    return s
  }

  static func storage(_ current: Storage, savingSubtitle option: TrackMenuOption) -> Storage? {
    var s = current
    if option.id < 0 {
      s.subtitleLang = subtitleOffSentinel
      s.subtitleTitleFallback = nil
    } else if option.isExternal {
      // An imported file is remembered for its own title (`ImportedSubtitleStore`).
      // Stored here, its file name would replace the language or "off" preference
      // that applies to every other title.
      return nil
    } else if let lang = option.normalizedLang, !lang.isEmpty {
      s.subtitleLang = lang
      s.subtitleTitleFallback = nil
    } else if !option.isSyntheticTitle {
      s.subtitleLang = nil
      s.subtitleTitleFallback = normalizeTitleToken(option.title)
    } else {
      return nil
    }
    return s
  }

  static func storage(_ current: Storage, savingVideo option: TrackMenuOption) -> Storage? {
    var s = current
    if let lang = option.normalizedLang, !lang.isEmpty {
      s.videoLang = lang
      s.videoTitleFallback = nil
    } else if !option.isSyntheticTitle {
      s.videoLang = nil
      s.videoTitleFallback = normalizeTitleToken(option.title)
    } else {
      return nil
    }
    return s
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
       let t = tracks.first(where: { titleMatches($0, token: fb) })
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
       let t = tracks.first(where: { titleMatches($0, token: fb) })
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
       let t = realTracks.first(where: { titleMatches($0, token: fb) })
    {
      return t.id
    }
    return nil
  }

  /// Titles are compared as the stream tags them. A row named after its language or its
  /// position carries a display text that changes with the app language.
  private static func titleMatches(_ option: TrackMenuOption, token: String) -> Bool {
    !option.isSyntheticTitle && normalizeTitleToken(option.title) == token
  }

  // MARK: - Audio language before playback

  /// The saved audio language, readable from any thread.
  nonisolated static func savedAudioLanguage() -> String? {
    guard let lang = load().audioLang, !lang.isEmpty else { return nil }
    return lang
  }

  /// Index of the first selectable track in the preferred audio language, or nil when
  /// there is no preference or no such track. Used while the source opens, so the
  /// preferred track is the one playback starts with instead of being switched to
  /// (a seek plus an audio flush) after the first frame.
  ///
  /// - Parameters:
  ///   - languageCodes: Language tag of every audio track, in track order.
  ///   - selectable: Whether the track at the same index may be chosen; a shorter
  ///     array leaves the remaining tracks selectable.
  nonisolated static func preferredAudioIndex(
    languageCodes: [String?],
    selectable: [Bool],
    preferredLanguage: String?
  ) -> Int? {
    guard let preferredLanguage, !preferredLanguage.isEmpty else { return nil }
    return languageCodes.indices.first { index in
      (index < selectable.count ? selectable[index] : true)
        && langMatches(stored: preferredLanguage, trackLang: languageCodes[index])
    }
  }

  // MARK: - Language codes

  nonisolated static func normalizeLang(_ raw: String?) -> String? {
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else {
      return nil
    }
    if let r = s.firstIndex(of: "-") { s = String(s[..<r]) }
    if let r = s.firstIndex(of: "_") { s = String(s[..<r]) }
    return s.isEmpty ? nil : s
  }

  /// ISO 639-1 (2 harf) → 639-2/B+T (3 harf) eşdeğerleri. Kör 2 harf prefix
  /// karşılaştırması "por/pol", "tur/tuk", "slv/slk", "rus/run", "fra/fry" gibi alakasız
  /// dilleri eşleştirip her videoda yanlış ses/altyazı seçiyordu.
  nonisolated private static let iso639Equivalents: [String: Set<String>] = [
    "en": ["eng"], "tr": ["tur"], "ar": ["ara"], "de": ["deu", "ger"],
    "es": ["spa"], "fr": ["fra", "fre"], "hi": ["hin"], "pt": ["por", "pob"],
    "ru": ["rus"], "zh": ["zho", "chi"], "it": ["ita"], "nl": ["nld", "dut"],
    "pl": ["pol"], "sv": ["swe"], "no": ["nor", "nob", "nno"], "da": ["dan"],
    "fi": ["fin"], "el": ["ell", "gre"], "he": ["heb"], "ja": ["jpn"],
    "ko": ["kor"], "cs": ["ces", "cze"], "sk": ["slk", "slo"], "sl": ["slv"],
    "hu": ["hun"], "ro": ["ron", "rum"], "bg": ["bul"], "sr": ["srp"],
    "hr": ["hrv"], "uk": ["ukr"], "fa": ["fas", "per"], "ur": ["urd"],
    "th": ["tha"], "vi": ["vie"], "id": ["ind"], "ms": ["msa", "may"],
    "az": ["aze"], "kk": ["kaz"], "sq": ["sqi", "alb"], "bs": ["bos"],
    "mk": ["mkd", "mac"], "ku": ["kur"],
  ]

  nonisolated static func langMatches(stored: String, trackLang: String?) -> Bool {
    guard let t = normalizeLang(trackLang) else { return false }
    let s = normalizeLang(stored) ?? stored.lowercased()
    if t == s { return true }
    // 2↔3 harf eşdeğerliği yalnız açık tablo üzerinden — prefix sezgisi yok.
    if let eq = iso639Equivalents[s], eq.contains(t) { return true }
    if let eq = iso639Equivalents[t], eq.contains(s) { return true }
    return false
  }

  /// The two-letter code of a language the table knows, for either of its spellings.
  nonisolated static func twoLetterCode(for raw: String?) -> String? {
    guard let code = normalizeLang(raw) else { return nil }
    if iso639Equivalents[code] != nil { return code }
    return iso639Equivalents.first(where: { $0.value.contains(code) })?.key
  }

  /// Only codes of the table count: a three-letter title such as "dub" must not be
  /// mistaken for a language.
  nonisolated static func isKnownLanguageCode(_ raw: String) -> Bool {
    twoLetterCode(for: raw) != nil
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

/// Row texts of the track sheet, built from what the stream reports. Kept free of
/// player types so they can be tested.
nonisolated enum TrackNaming {
  struct Title: Equatable {
    let text: String
    /// The text is a language name or a positional fallback, not a title tag of the
    /// stream. It changes with the app language and is never stored as a preference.
    let isSynthetic: Bool
  }

  /// KSPlayer appends this to the name of a hearing-impaired subtitle track.
  static let hearingImpairedMarker = "(hearing impaired)"
  static let hearingImpairedLabel = "SDH"

  /// Title of a track row.
  ///
  /// - Parameters:
  ///   - name: `MediaPlayerTrack.name`. KSPlayer fills it with the title tag, else the
  ///     language code, else the codec name; only the first is a title.
  ///   - codecName: KSPlayer's codec name including its profile suffix ("h264 (High)").
  ///   - fallback: Text for a track with neither a title nor a language ("Track 2").
  static func title(
    name: String,
    languageCode: String?,
    codecName: String?,
    fallback: String,
    locale: Locale
  ) -> Title {
    var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var isHearingImpaired = false
    if base.lowercased().hasSuffix(hearingImpairedMarker) {
      base = String(base.dropLast(hearingImpairedMarker.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      isHearingImpaired = true
    }
    let suffix = isHearingImpaired ? " (\(hearingImpairedLabel))" : ""
    if isTitleTag(base, languageCode: languageCode, codecName: codecName) {
      return Title(text: base + suffix, isSynthetic: false)
    }
    if let language = languageName(forCode: languageCode, locale: locale) {
      return Title(text: language + suffix, isSynthetic: true)
    }
    // A code Foundation has no name for ("qaa", "mis") is still more telling than a
    // position.
    if let code = meaningfulCode(languageCode) {
      return Title(text: code + suffix, isSynthetic: true)
    }
    return Title(text: fallback + suffix, isSynthetic: true)
  }

  /// Whether `name` is a real title rather than the language code or codec name
  /// KSPlayer substitutes for a missing one.
  static func isTitleTag(_ name: String, languageCode: String?, codecName: String?) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return false }
    let substitutes = [languageCode, codecName, codecName.flatMap(codecBaseName)]
    return !substitutes.contains { substitute in
      guard let substitute, !substitute.isEmpty else { return false }
      return name.caseInsensitiveCompare(substitute) == .orderedSame
    }
  }

  /// Name of a language in `locale`, starting with a capital. Accepts ISO 639-1 codes,
  /// both ISO 639-2 spellings and tags with a region or script. Nil for codes without a
  /// name.
  static func languageName(forCode code: String?, locale: Locale) -> String? {
    guard let code = meaningfulCode(code) else { return nil }
    guard let base = PlaybackTrackPreferences.normalizeLang(code) else { return nil }
    // "pob" and similar release-group codes are unknown to Foundation.
    let candidates = [base, PlaybackTrackPreferences.twoLetterCode(for: base)]
    guard let plain = candidates.lazy.compactMap({ candidate -> String? in
      guard let candidate,
            let name = locale.localizedString(forLanguageCode: candidate),
            !name.isEmpty, name.caseInsensitiveCompare(candidate) != .orderedSame
      else { return nil }
      return name
    }).first else { return nil }
    // "pt-BR", "zh-Hans": keep the variant when Foundation can name it.
    let name = base.count < code.count ? (locale.localizedString(forIdentifier: code) ?? plain) : plain
    return name.prefix(1).uppercased(with: locale) + name.dropFirst()
  }

  /// The language of a track whose row is titled by its tag, for the detail line. Nil
  /// when the title already says it ("Turkish 5.1").
  static func detailLanguageName(for title: Title, languageCode: String?, locale: Locale) -> String? {
    guard !title.isSynthetic,
          let name = languageName(forCode: languageCode, locale: locale)
    else { return nil }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    return title.text.range(of: name, options: options, locale: locale) == nil ? name : nil
  }

  /// Short codec label for the detail line. KSPlayer's own name carries the first
  /// profile of FFmpeg's table whatever the stream uses ("h264 (Baseline)"), so only the
  /// codec itself is kept.
  static func codecLabel(_ codecName: String?) -> String? {
    guard let base = codecName.flatMap(codecBaseName), !base.isEmpty else { return nil }
    return codecLabels[base] ?? base.uppercased()
  }

  private static func codecBaseName(_ codecName: String) -> String? {
    codecName.split(separator: " ").first.map { $0.lowercased() }
  }

  /// "und" is the tag for "no language".
  private static func meaningfulCode(_ code: String?) -> String? {
    guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines),
          !code.isEmpty, code.lowercased() != "und"
    else { return nil }
    return code
  }

  private static let codecLabels: [String: String] = [
    "h264": "H.264", "hevc": "HEVC", "mpeg2video": "MPEG-2", "mpeg4": "MPEG-4",
    "av1": "AV1", "vp9": "VP9",
    "aac": "AAC", "ac3": "AC-3", "eac3": "E-AC-3", "dts": "DTS", "truehd": "TrueHD",
    "mp3": "MP3", "mp2": "MP2", "opus": "Opus", "vorbis": "Vorbis", "flac": "FLAC",
    "subrip": "SRT", "ass": "ASS", "ssa": "SSA", "webvtt": "WebVTT",
    "mov_text": "TX3G", "hdmv_pgs_subtitle": "PGS", "dvd_subtitle": "VobSub",
    "dvb_subtitle": "DVB", "dvb_teletext": "Teletext", "eia_608": "CC",
  ]
}
