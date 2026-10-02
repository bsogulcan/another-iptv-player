import Foundation
import KSPlayer

/// External subtitle files the user imported via the Files picker.
/// Stored per content (`<playlistId>_<type>_<streamId>`) under Application
/// Support/ImportedSubtitles and re-added to mpv whenever the same content is played again.
/// Downloaded content plays with the same identity triple, so no extra mapping is needed.
enum ImportedSubtitleStore {
    private static let selectionKey = "importedSubtitles.selectedFile.v1"
    private static let normalizationKey = "importedSubtitles.normalized.v1"

    static func contentKey(playlistId: UUID, type: String, streamId: String) -> String {
        sanitize("\(playlistId.uuidString)_\(type)_\(streamId)")
    }

    /// What every content key of a playlist starts with. Stores keyed by `contentKey`
    /// use it to purge a deleted playlist's entries.
    static func contentKeyPrefix(playlistId: UUID) -> String {
        sanitize(playlistId.uuidString) + "_"
    }

    static func subtitleFiles(for contentKey: String) -> [URL] {
        normalizeLegacyFilesIfNeeded()
        guard let dir = try? directory(for: contentKey, create: false) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Imports the file picked in the document picker into the content folder; overwrites on name collision.
    /// The stored copy is normalised (UTF-8, display markup removed) because neither subtitle
    /// reader copes with the raw file: KSPlayer swallows every parse failure, so a file it
    /// cannot read used to import "successfully" and then never show. Throws a
    /// `SubtitleImportError` instead of saving such a file.
    static func importFile(at pickedURL: URL, for contentKey: String) throws -> URL {
        let accessed = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessed { pickedURL.stopAccessingSecurityScopedResource() } }
        let normalized = try SubtitleFileNormalizer.normalize(
            SubtitleFileNormalizer.boundedData(contentsOf: pickedURL)
        )
        // Created only once the file is known to be usable, so a rejected import leaves no empty folder.
        let dir = try directory(for: contentKey, create: true)
        let destination = dir.appendingPathComponent(pickedURL.lastPathComponent)
        try normalized.write(to: destination, options: .atomic)
        return destination
    }

    /// Rewrites one stored file in its normalised form. Returns whether the file changed.
    /// A file that cannot be normalised (unknown encoding, unsupported format) is left
    /// exactly as it is: it was the user's import, and deleting it is their call.
    @discardableResult
    static func normalizeStoredFile(at url: URL) -> Bool {
        guard let raw = try? SubtitleFileNormalizer.boundedData(contentsOf: url),
              let normalized = try? SubtitleFileNormalizer.normalize(raw),
              normalized != raw
        else { return false }
        return (try? normalized.write(to: url, options: .atomic)) != nil
    }

    static func removeFile(_ url: URL, for contentKey: String) {
        try? FileManager.default.removeItem(at: url)
        if selectedFileName(for: contentKey) == url.lastPathComponent {
            setSelectedFileName(nil, for: contentKey)
        }
    }

    /// File name of the external subtitle last selected for this content; used to auto-select on resume.
    static func selectedFileName(for contentKey: String) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String]
        return map?[contentKey]
    }

    static func setSelectedFileName(_ name: String?, for contentKey: String) {
        var map = (UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String]) ?? [:]
        if map[contentKey] == name { return }
        map[contentKey] = name
        UserDefaults.standard.set(map, forKey: selectionKey)
    }

    /// Playlist silinince: o playlist'e ait tüm altyazı klasörlerini ve seçim
    /// kayıtlarını temizler. contentKey her zaman "<playlistUUID>_..." ile başlar.
    static func removeAll(playlistId: UUID) {
        let prefix = contentKeyPrefix(playlistId: playlistId)
        let fm = FileManager.default
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) {
            let root = appSupport.appendingPathComponent("ImportedSubtitles", isDirectory: true)
            if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
                    try? fm.removeItem(at: entry)
                }
            }
        }
        var map = (UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String]) ?? [:]
        let orphanKeys = map.keys.filter { $0.hasPrefix(prefix) }
        guard !orphanKeys.isEmpty else { return }
        for key in orphanKeys { map.removeValue(forKey: key) }
        UserDefaults.standard.set(map, forKey: selectionKey)
    }

    /// Files imported before imports were normalised are raw copies: legacy code pages and
    /// literal `<i>` tags included. Rewrites them once, the first time any content asks for
    /// its files, so they reach the player and the AirPlay rendition as valid UTF-8 too.
    private static func normalizeLegacyFilesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: normalizationKey) else { return }
        // Set before the pass rather than after it: a file that brought the pass down would
        // otherwise be retried on every playback.
        defaults.set(true, forKey: normalizationKey)
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }
        let root = appSupport.appendingPathComponent("ImportedSubtitles", isDirectory: true)
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let files = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files { normalizeStoredFile(at: file) }
        }
    }

    private static func directory(for contentKey: String, create: Bool) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let dir = appSupport
            .appendingPathComponent("ImportedSubtitles", isDirectory: true)
            .appendingPathComponent(contentKey, isDirectory: true)
        if create, !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func sanitize(_ raw: String) -> String {
        String(raw.map { ch in
            (ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == ".") ? ch : "_"
        })
    }
}

/// Why an imported subtitle file was rejected. `errorDescription` is meant for the user.
nonisolated enum SubtitleImportError: LocalizedError, Equatable {
    /// The bytes are not text in any encoding the importer knows.
    case unreadableText
    /// Readable text, but not SubRip, WebVTT or ASS/SSA (MicroDVD `.sub`, SAMI `.smi`, ...):
    /// no parser in the app handles it.
    case unsupportedFormat
    /// A supported format from which no cue could be parsed.
    case noCues

    var errorDescription: String? {
        switch self {
        case .unreadableText: return L("player.subtitle_import.error.unreadable_text")
        case .unsupportedFormat: return L("player.subtitle_import.error.unsupported_format")
        case .noCues: return L("player.subtitle_import.error.no_cues")
        }
    }
}

/// Decodes subtitle bytes of unknown encoding. KSPlayer only tries UTF-8, Big5, GB18030 and
/// UTF-16 (and takes Big5 for most GBK text), and the AirPlay rendition reads UTF-8 only,
/// so an import is decoded here once and stored as UTF-8.
nonisolated enum SubtitleTextDecoder {
    struct Decoded: Equatable {
        let text: String
        let encoding: String.Encoding
    }

    static let windowsArabic = encoding(.windowsArabic)
    static let windowsHebrew = encoding(.windowsHebrew)
    static let gb18030 = encoding(.GB_18030_2000)
    static let big5 = encoding(.big5)
    static let shiftJIS = encoding(.dosJapanese)
    static let eucKR = encoding(.dosKorean)

    /// Code pages suggested to the detector whatever the device language: the ones the
    /// app's own languages were commonly written in, plus the two KSPlayer already tried.
    /// ISO-8859-9 and ISO-8859-1 need no entry of their own, Windows-1254 and Windows-1252
    /// being supersets of their printable ranges.
    private static let baselineLegacyEncodings: [String.Encoding] = [
        .windowsCP1252, .windowsCP1254, windowsArabic, .windowsCP1251, gb18030, big5,
    ]

    /// `nil` when the data is empty or matches no known encoding without loss.
    static func decode(
        _ data: Data,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Decoded? {
        guard !data.isEmpty else { return nil }
        // Certain answers first; the statistical detector only sees what is left.
        if let marked = decodeByteOrderMarked(data) { return marked }
        // Before UTF-8: ASCII-heavy UTF-16 is also valid UTF-8, with a NUL after every letter.
        if let encoding = unmarkedUTF16Encoding(of: data),
           let text = String(data: data, encoding: encoding) {
            return Decoded(text: text, encoding: encoding)
        }
        // Strict: Foundation returns nil for any invalid sequence, and legacy text with a
        // non-ASCII letter is practically never valid UTF-8.
        if let text = String(data: data, encoding: .utf8) {
            return Decoded(text: text, encoding: .utf8)
        }
        return decodeLegacy(data, preferredLanguages: preferredLanguages)
    }

    /// Suggested legacy encodings, the user's own languages first.
    static func legacyCandidates(preferredLanguages: [String]) -> [String.Encoding] {
        var ordered: [String.Encoding] = []
        func add(_ encodings: [String.Encoding]) {
            for encoding in encodings where !ordered.contains(encoding) { ordered.append(encoding) }
        }
        for identifier in preferredLanguages {
            let code = Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
            switch code {
            case "tr", "az": add([.windowsCP1254])
            case "ar", "fa", "ur": add([windowsArabic])
            case "ru", "uk", "bg", "be", "sr", "mk", "kk": add([.windowsCP1251])
            case "zh":
                let traditional = ["Hant", "TW", "HK", "MO"].contains { identifier.contains($0) }
                add(traditional ? [big5, gb18030] : [gb18030, big5])
            // Offered only to users of these languages: every extra single-byte page makes
            // the detector's guess for everyone else a little less certain.
            case "pl", "cs", "sk", "hu", "ro", "hr", "sl": add([.windowsCP1250])
            case "el": add([.windowsCP1253])
            case "he": add([windowsHebrew])
            case "ja": add([shiftJIS])
            case "ko": add([eucKR])
            default: add([.windowsCP1252])
            }
        }
        add(baselineLegacyEncodings)
        return ordered
    }

    private static func encoding(_ cfEncoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        )
    }

    private static func decodeByteOrderMarked(_ data: Data) -> Decoded? {
        // UTF-32 LE opens with the UTF-16 LE mark, so it has to be tested first.
        let marks: [(bytes: [UInt8], encoding: String.Encoding)] = [
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian),
        ]
        for mark in marks where data.starts(with: mark.bytes) {
            let body = data.dropFirst(mark.bytes.count)
            if let text = String(data: body, encoding: mark.encoding) {
                return Decoded(text: text, encoding: mark.encoding)
            }
        }
        return nil
    }

    /// UTF-16 without a mark. Timing lines are ASCII in every subtitle format, so one byte
    /// of most code units is NUL, always on the same side; no legacy code page and no
    /// UTF-8 text contains NUL at all.
    private static func unmarkedUTF16Encoding(of data: Data) -> String.Encoding? {
        let sample = data.prefix(4096)
        guard sample.count >= 4 else { return nil }
        var evenZeros = 0
        var oddZeros = 0
        for (offset, byte) in sample.enumerated() where byte == 0 {
            if offset.isMultiple(of: 2) { evenZeros += 1 } else { oddZeros += 1 }
        }
        // A quarter of the code units, almost all of them on one side.
        let threshold = sample.count / 8
        if oddZeros > threshold, evenZeros * 8 < oddZeros { return .utf16LittleEndian }
        if evenZeros > threshold, oddZeros * 8 < evenZeros { return .utf16BigEndian }
        return nil
    }

    private static func decodeLegacy(_ data: Data, preferredLanguages: [String]) -> Decoded? {
        let candidates = legacyCandidates(preferredLanguages: preferredLanguages)
        var converted: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: candidates.map { NSNumber(value: $0.rawValue) },
                .useOnlySuggestedEncodingsKey: true,
                // A lossy result would store replacement characters as if they were the text.
                .allowLossyKey: false,
            ],
            convertedString: &converted,
            usedLossyConversion: &usedLossyConversion
        )
        // The detector can name an encoding and still hand back no string (bytes that code
        // page leaves undefined). Guessing another page from there would store mojibake, so
        // that counts as undecodable.
        guard detected != 0, !usedLossyConversion.boolValue, let text = converted as String? else {
            return nil
        }
        return Decoded(text: text, encoding: String.Encoding(rawValue: detected))
    }
}

/// Turns the bytes of a picked subtitle file into what gets stored: UTF-8, LF line ends,
/// display markup removed, and only for a file playback can actually parse.
nonisolated enum SubtitleFileNormalizer {
    enum Format: Equatable {
        case subRip
        case webVTT
        case ass
    }

    /// Text subtitles are far below this; a binary VobSub `.sub` can be tens of megabytes
    /// and is not worth loading just to find out it is not text.
    static let maximumFileSize = 8 * 1024 * 1024

    static func boundedData(contentsOf url: URL) throws -> Data {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize {
            throw SubtitleImportError.unsupportedFormat
        }
        return try Data(contentsOf: url)
    }

    static func normalize(
        _ data: Data,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) throws -> Data {
        Data(try normalizedText(from: data, preferredLanguages: preferredLanguages).utf8)
    }

    static func normalizedText(
        from data: Data,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) throws -> String {
        guard !data.isEmpty else { throw SubtitleImportError.noCues }
        guard data.count <= maximumFileSize else { throw SubtitleImportError.unsupportedFormat }
        guard let decoded = SubtitleTextDecoder.decode(data, preferredLanguages: preferredLanguages) else {
            throw SubtitleImportError.unreadableText
        }
        var text = decoded.text
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        // KSPlayer's SRT and WebVTT parsers only continue a cue across "\n" or "\r\n"; a
        // lone "\r" would cut every cue after its first line.
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        guard let format = format(of: text) else { throw SubtitleImportError.unsupportedFormat }
        if format != .ass {
            // Both of those parsers print HTML-like tags verbatim. `{\an8}`-style override
            // blocks stay: KSPlayer consumes them, and the AirPlay path drops them in SRTParser.
            text = SRTParser.strippingMarkupTags(text)
            // ...and they read a whitespace-only line as cue text, which glues the following
            // cue (number and timing line included) onto the current one.
            text = text.replacingOccurrences(of: #"(?m)^[ \t]+$"#, with: "", options: .regularExpression)
            // Stripping can leave a cue without text. Both parsers skip every line break after a
            // timing line, so that cue would show the next cue's number, timing line and text.
            text = text.replacingOccurrences(of: emptyCuePattern, with: "", options: .regularExpression)
        }
        guard isPlayable(text, as: format) else { throw SubtitleImportError.noCues }
        return text
    }

    /// The start of a timing line, up to its arrow. The colon is required so that a line of
    /// dialogue such as "1 --> 2" is not taken for one.
    private static let cueTimingStart = #"[ \t]*\d+:\d[\d:.,]*[ \t]*-->"#

    /// A cue header (optional number, timing line) with no text before the next header or
    /// the end. A header followed by a blank line and then text is left alone.
    private static let emptyCuePattern =
        #"(?m)^(?:[ \t]*\d+[ \t]*\n)?\#(cueTimingStart)[^\n]*\n(?=\n+(?:[^\n]+\n)?\#(cueTimingStart)|\n*\z)"#

    /// The format KSPlayer will treat the text as. Same order and same tests as its parser
    /// list (ASS, WebVTT, SRT), which looks at the content and never at the file extension.
    static func format(of text: String) -> Format? {
        let head = text.drop(while: { $0.isWhitespace }).prefix(13).lowercased()
        if head.hasPrefix("[script info]") { return .ass }
        if head.hasPrefix("webvtt") { return .webVTT }
        if text.contains(" --> ") { return .subRip }
        return nil
    }

    private static func isPlayable(_ text: String, as format: Format) -> Bool {
        switch format {
        case .ass:
            // Not KSPlayer's parser here: its ASS parser is one shared instance with mutable
            // state, which playback may be using on another thread at this very moment.
            return hasPlayableASSStructure(text)
        case .subRip, .webVTT:
            // KSPlayer's own parser decides, so import and playback cannot disagree. For
            // non-ASS text it only runs the stateless SRT and WebVTT parsers.
            return (try? KSSubtitle().parse(data: Data(text.utf8))) != nil
        }
    }

    /// What KSPlayer's ASS parser needs: a `Format:` line, at least one `Dialogue:` line,
    /// and no `Style:` line shorter than the first `Format:` line (the parser indexes the
    /// style fields by that line's column count without a bounds check).
    private static func hasPlayableASSStructure(_ text: String) -> Bool {
        func fieldCount(_ line: Substring, after prefix: String) -> Int {
            line.dropFirst(prefix.count).split(separator: ",", omittingEmptySubsequences: false).count
        }
        var formatFieldCount: Int?
        var hasDialogue = false
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.drop(while: { $0 == " " || $0 == "\t" })
            let lowered = line.prefix(9).lowercased()
            if lowered.hasPrefix("format:") {
                if formatFieldCount == nil { formatFieldCount = fieldCount(line, after: "format:") }
            } else if lowered.hasPrefix("style:") {
                if let formatFieldCount, fieldCount(line, after: "style:") < formatFieldCount { return false }
            } else if lowered.hasPrefix("dialogue:") {
                hasDialogue = true
            }
        }
        return formatFieldCount != nil && hasDialogue
    }
}
