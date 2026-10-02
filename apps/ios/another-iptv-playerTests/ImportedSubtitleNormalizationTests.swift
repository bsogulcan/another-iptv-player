import Foundation
import Testing
@testable import another_iptv_player

/// Builds an SRT document, one cue per line of text.
private func srtDocument(_ lines: [String], lineEnding: String = "\r\n") -> String {
    var out = ""
    for (index, line) in lines.enumerated() {
        let start = String(format: "%02d", index * 3)
        let end = String(format: "%02d", index * 3 + 2)
        out += "\(index + 1)\(lineEnding)00:00:\(start),000 --> 00:00:\(end),500\(lineEnding)\(line)\(lineEnding)\(lineEnding)"
    }
    return out
}

private let turkishLines = [
    "Kapıyı aç.", "Şimdi ne yapacağız?", "Öğretmen çocuğa güldü.", "İşte böyle, değil mi?", "Çok güzel bir gün.",
]

// MARK: - Encoding detection

@Suite("SubtitleTextDecoder")
struct SubtitleTextDecoderTests {

    @Test
    func emptyDataIsNotText() {
        #expect(SubtitleTextDecoder.decode(Data()) == nil)
    }

    @Test
    func decodesUTF8WithAndWithoutByteOrderMark() throws {
        let text = srtDocument(turkishLines)
        let plain = try #require(SubtitleTextDecoder.decode(Data(text.utf8)))
        #expect(plain.text == text)
        #expect(plain.encoding == .utf8)

        let marked = try #require(SubtitleTextDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)))
        #expect(marked.text == text)
        #expect(marked.encoding == .utf8)
    }

    @Test
    func decodesUTF16WithByteOrderMark() throws {
        let text = srtDocument(turkishLines)
        let little = Data([0xFF, 0xFE]) + (try #require(text.data(using: .utf16LittleEndian)))
        let big = Data([0xFE, 0xFF]) + (try #require(text.data(using: .utf16BigEndian)))
        #expect(SubtitleTextDecoder.decode(little) == SubtitleTextDecoder.Decoded(text: text, encoding: .utf16LittleEndian))
        #expect(SubtitleTextDecoder.decode(big) == SubtitleTextDecoder.Decoded(text: text, encoding: .utf16BigEndian))
    }

    /// ASCII-heavy UTF-16 is also valid UTF-8 (with NULs), so it has to be caught first.
    @Test
    func decodesUTF16WithoutByteOrderMark() throws {
        let text = srtDocument(turkishLines)
        let little = try #require(text.data(using: .utf16LittleEndian))
        let big = try #require(text.data(using: .utf16BigEndian))
        #expect(SubtitleTextDecoder.decode(little) == SubtitleTextDecoder.Decoded(text: text, encoding: .utf16LittleEndian))
        #expect(SubtitleTextDecoder.decode(big) == SubtitleTextDecoder.Decoded(text: text, encoding: .utf16BigEndian))
    }

    /// The audit's own sample, as raw Windows-1254 bytes: dotless i is 0xFD, c-cedilla 0xE7.
    @Test
    func decodesWindows1254Bytes() throws {
        var data = Data("1\r\n00:00:01,000 --> 00:00:04,000\r\n".utf8)
        data.append(contentsOf: [0x4B, 0x61, 0x70, 0xFD, 0x79, 0xFD, 0x20, 0x61, 0xE7, 0x2E])  // Kapıyı aç.
        data.append(contentsOf: Data("\r\n".utf8))
        let decoded = try #require(SubtitleTextDecoder.decode(data, preferredLanguages: ["en"]))
        #expect(decoded.text == "1\r\n00:00:01,000 --> 00:00:04,000\r\nKapıyı aç.\r\n")
    }

    /// Each legacy code page must come out right whatever the device language is: the
    /// language list only orders the suggestions.
    @Test(arguments: [["en"], ["tr-TR"], ["ru-RU"], ["ar"], ["zh-Hans-CN"], ["hi-IN", "de-DE"]])
    func decodesLegacyCodePages(preferredLanguages: [String]) throws {
        let latin5 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin5.rawValue))
        )
        let samples: [(name: String, encoding: String.Encoding, lines: [String])] = [
            ("Windows-1254", .windowsCP1254, turkishLines),
            ("ISO-8859-9", latin5, turkishLines),
            ("Windows-1252 de", .windowsCP1252, ["Schön, dass du da bist.", "Wir müssen über die Straße gehen.", "Das wäre großartig!"]),
            ("Windows-1252 fr", .windowsCP1252, ["Où est-ce que tu étais ?", "Ça va très bien, merci.", "Le garçon a mangé le gâteau."]),
            ("Windows-1252 es", .windowsCP1252, ["¿Dónde está el baño?", "Mañana será otro día.", "¡Qué sorpresa!"]),
            ("Windows-1252 pt", .windowsCP1252, ["Não sei o que você está fazendo.", "Então, vamos à praia amanhã.", "Coração"]),
            ("Windows-1251", .windowsCP1251, ["Привет, как дела?", "Я не знаю, что делать.", "Это очень хорошо.", "Спасибо большое!"]),
            ("Windows-1256", SubtitleTextDecoder.windowsArabic, ["مرحبا، كيف حالك؟", "لا أعرف ماذا أفعل.", "هذا جيد جدا.", "شكرا جزيلا!"]),
            ("GB18030", SubtitleTextDecoder.gb18030, ["你好，你怎么样？", "我不知道该怎么办。", "这个非常好。", "非常感谢！"]),
            ("Big5", SubtitleTextDecoder.big5, ["你好，你怎麼樣？", "我不知道該怎麼辦。", "這個非常好。", "非常感謝！"]),
        ]
        for sample in samples {
            let text = srtDocument(sample.lines)
            let data = try #require(text.data(using: sample.encoding), "\(sample.name) sample is not encodable")
            let decoded = SubtitleTextDecoder.decode(data, preferredLanguages: preferredLanguages)
            #expect(decoded?.text == text, "\(sample.name) with \(preferredLanguages)")
        }
    }

    @Test
    func suggestsTheUsersCodePagesFirst() {
        let turkish = SubtitleTextDecoder.legacyCandidates(preferredLanguages: ["tr-TR", "en-US"])
        #expect(turkish.prefix(2) == [.windowsCP1254, .windowsCP1252])

        let russian = SubtitleTextDecoder.legacyCandidates(preferredLanguages: ["ru"])
        #expect(russian.first == .windowsCP1251)

        let traditional = SubtitleTextDecoder.legacyCandidates(preferredLanguages: ["zh-Hant-TW"])
        #expect(traditional.prefix(2) == [SubtitleTextDecoder.big5, SubtitleTextDecoder.gb18030])

        // Whatever the language, the common pages are all offered, each once.
        for candidates in [turkish, russian, traditional] {
            #expect(Set(candidates).count == candidates.count)
            #expect(Set(candidates).isSuperset(of: [
                .windowsCP1252, .windowsCP1254, .windowsCP1251,
                SubtitleTextDecoder.windowsArabic, SubtitleTextDecoder.gb18030, SubtitleTextDecoder.big5,
            ]))
        }
        // Pages of languages the user does not read stay out of the suggestions.
        #expect(!turkish.contains(.windowsCP1250))
        #expect(SubtitleTextDecoder.legacyCandidates(preferredLanguages: ["pl"]).first == .windowsCP1250)
    }
}

// MARK: - Normalisation

@Suite("SubtitleFileNormalizer")
struct SubtitleFileNormalizerTests {

    @Test
    func detectsFormatFromContent() {
        #expect(SubtitleFileNormalizer.format(of: "\n[Script Info]\nTitle: x\n") == .ass)
        #expect(SubtitleFileNormalizer.format(of: "WEBVTT\n\n00:01.000 --> 00:02.000\nHi\n") == .webVTT)
        #expect(SubtitleFileNormalizer.format(of: "1\n00:00:01,000 --> 00:00:02,000\nHi\n") == .subRip)
        #expect(SubtitleFileNormalizer.format(of: "{0}{25}Hello") == nil)
        #expect(SubtitleFileNormalizer.format(of: "<SAMI>\n<BODY>\n<SYNC Start=0><P>Hello\n</BODY>\n</SAMI>") == nil)
    }

    @Test
    func reencodesLegacyTextAsUTF8WithUnixLineEnds() throws {
        let data = try #require(srtDocument(turkishLines).data(using: .windowsCP1254))
        let normalized = try SubtitleFileNormalizer.normalize(data, preferredLanguages: ["en"])
        #expect(normalized == Data(srtDocument(turkishLines, lineEnding: "\n").utf8))
    }

    @Test
    func dropsTheByteOrderMark() throws {
        let text = srtDocument(["Hello"], lineEnding: "\n")
        let normalized = try SubtitleFileNormalizer.normalize(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))
        #expect(normalized == Data(text.utf8))
    }

    /// KSPlayer prints HTML-like tags literally but consumes `{...}` override blocks itself,
    /// so only the former are removed from the stored copy.
    @Test
    func stripsTagsButKeepsOverrideBlocksInSubRip() throws {
        let source = "1\n00:00:01,000 --> 00:00:02,000\n<i>Hello</i> {\\an8}<font color=\"#fff\">world</font>\n"
        let text = try SubtitleFileNormalizer.normalizedText(from: Data(source.utf8))
        #expect(text == "1\n00:00:01,000 --> 00:00:02,000\nHello {\\an8}world\n")
    }

    @Test
    func stripsTagsInWebVTT() throws {
        let source = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n<v Roger><i>Hello</i></v>\n"
        let text = try SubtitleFileNormalizer.normalizedText(from: Data(source.utf8))
        #expect(text == "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\n")
    }

    /// A separator line holding only spaces would otherwise merge two cues during playback.
    @Test
    func emptiesWhitespaceOnlySeparatorLines() throws {
        let source = "1\n00:00:01,000 --> 00:00:02,000\nOne\n \t\n2\n00:00:03,000 --> 00:00:04,000\nTwo\n"
        let text = try SubtitleFileNormalizer.normalizedText(from: Data(source.utf8))
        #expect(text == "1\n00:00:01,000 --> 00:00:02,000\nOne\n\n2\n00:00:03,000 --> 00:00:04,000\nTwo\n")
    }

    /// A cue left without text would take the next cue's number, timing line and text as
    /// its own during playback, so its header goes too.
    @Test
    func dropsCuesLeftWithoutText() throws {
        let first = "1\n00:00:01,000 --> 00:00:02,000\nFirst cue\n\n"
        let third = "3\n00:00:05,000 --> 00:00:06,000\nThird cue\n"
        for emptyText in ["<i></i>", "<font color=\"#fff\"></font>", " \t"] {
            let source = first + "2\n00:00:03,000 --> 00:00:04,000\n\(emptyText)\n\n" + third
            let text = try SubtitleFileNormalizer.normalizedText(from: Data(source.utf8))
            #expect(!text.contains("00:00:03,000"), "\(emptyText.debugDescription)")
            #expect(SRTParser().parse(content: text).map(\.text) == ["First cue", "Third cue"])
        }
        let tagOnly = first + "2\n00:00:03,000 --> 00:00:04,000\n<i></i>\n\n" + third
        #expect(try SubtitleFileNormalizer.normalizedText(from: Data(tagOnly.utf8)) == first + "\n" + third)

        // WebVTT, with a cue identifier and cue settings, and an empty cue at the end.
        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nFirst\n\nb\n00:03.000 --> 00:04.000\n<c.yellow></c>\n\n"
            + "c\n00:05.000 --> 00:06.000\nThird\n\n00:07.000 --> 00:08.000\n<i></i>\n"
        #expect(
            try SubtitleFileNormalizer.normalizedText(from: Data(vtt.utf8))
                == "WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nFirst\n\nb\n\nc\n00:05.000 --> 00:06.000\nThird\n\n"
        )
    }

    /// Cues that do have text are never taken for empty ones, whatever the file's spacing.
    @Test
    func keepsCuesThatHaveText() throws {
        // Double-spaced: every line break of the file is "\r\r\n".
        let doubleSpaced = srtDocument(["One", "Two", "Three"], lineEnding: "\r\r\n")
        #expect(
            try SubtitleFileNormalizer.normalizedText(from: Data(doubleSpaced.utf8))
                == srtDocument(["One", "Two", "Three"], lineEnding: "\n\n")
        )
        // A blank line between the timing line and the text.
        let blankAfterTiming = "1\n00:00:01,000 --> 00:00:02,000\n\nOne\n\n2\n00:00:03,000 --> 00:00:04,000\n\nTwo\n"
        #expect(try SubtitleFileNormalizer.normalizedText(from: Data(blankAfterTiming.utf8)) == blankAfterTiming)
        // Dialogue that contains an arrow.
        let arrows = srtDocument(["A --> B", "1 --> 2", "Three"], lineEnding: "\n")
        #expect(try SubtitleFileNormalizer.normalizedText(from: Data(arrows.utf8)) == arrows)
    }

    private static let ass = """
    [Script Info]
    Title: Sample
    ScriptType: v4.00+

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, Bold, Italic, Alignment
    Style: Default,Arial,20,&H00FFFFFF,0,0,2

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\i1}Hello{\\i0} <i>world</i>

    """

    /// ASS markup is the parser's business: the text is re-encoded and otherwise untouched.
    @Test
    func leavesASSMarkupAlone() throws {
        let data = try #require(Self.ass.data(using: .utf16))
        let text = try SubtitleFileNormalizer.normalizedText(from: data)
        #expect(text == Self.ass)
    }

    @Test
    func rejectsASSThePlayerCannotParse() {
        let withoutDialogue = Self.ass.replacingOccurrences(of: "Dialogue:", with: "Comment:")
        #expect(throws: SubtitleImportError.noCues) {
            try SubtitleFileNormalizer.normalizedText(from: Data(withoutDialogue.utf8))
        }
        // A style line with fewer fields than its Format line.
        let shortStyle = Self.ass.replacingOccurrences(of: "Style: Default,Arial,20,&H00FFFFFF,0,0,2", with: "Style: Default,Arial")
        #expect(throws: SubtitleImportError.noCues) {
            try SubtitleFileNormalizer.normalizedText(from: Data(shortStyle.utf8))
        }
    }

    @Test
    func rejectsFormatsNoParserHandles() {
        let microDVD = "{0}{25}Hello\n{30}{60}World\n"
        let sami = "<SAMI>\n<BODY>\n<SYNC Start=0><P Class=ENCC>Hello\n</BODY>\n</SAMI>\n"
        for unsupported in [microDVD, sami] {
            #expect(throws: SubtitleImportError.unsupportedFormat) {
                try SubtitleFileNormalizer.normalizedText(from: Data(unsupported.utf8))
            }
        }
    }

    @Test
    func rejectsFilesWithoutCues() {
        #expect(throws: SubtitleImportError.noCues) {
            try SubtitleFileNormalizer.normalizedText(from: Data())
        }
        #expect(throws: SubtitleImportError.noCues) {
            try SubtitleFileNormalizer.normalizedText(from: Data("WEBVTT\n\n".utf8))
        }
        // Has the arrow that marks SRT, but nothing a cue could be read from.
        #expect(throws: SubtitleImportError.noCues) {
            try SubtitleFileNormalizer.normalizedText(from: Data("left --> right\n".utf8))
        }
    }

    /// Binary data (a VobSub `.sub`, for instance) must be refused one way or another.
    @Test
    func rejectsBinaryData() {
        let binary = Data((0..<2048).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        #expect(throws: SubtitleImportError.self) {
            try SubtitleFileNormalizer.normalizedText(from: binary)
        }
    }

    @Test
    func errorsHaveUserFacingDescriptions() {
        for error in [SubtitleImportError.unreadableText, .unsupportedFormat, .noCues] {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

// MARK: - Store

@Suite("ImportedSubtitleStore import")
struct ImportedSubtitleStoreImportTests {

    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtitle-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    private func storedFolder(for contentKey: String) throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        .appendingPathComponent("ImportedSubtitles", isDirectory: true)
        .appendingPathComponent(contentKey, isDirectory: true)
    }

    @Test
    func importStoresANormalisedCopy() throws {
        let source = srtDocument(["<i>Kapıyı aç.</i>", "Şimdi ne yapacağız?"])
        let picked = try temporaryFile(
            named: "film.tr.srt", contents: try #require(source.data(using: .windowsCP1254))
        )
        defer { try? FileManager.default.removeItem(at: picked.deletingLastPathComponent()) }
        let key = ImportedSubtitleStore.contentKey(playlistId: UUID(), type: "test", streamId: "1")

        let stored = try ImportedSubtitleStore.importFile(at: picked, for: key)
        defer { try? FileManager.default.removeItem(at: stored.deletingLastPathComponent()) }

        #expect(stored.lastPathComponent == "film.tr.srt")
        let expected = srtDocument(["Kapıyı aç.", "Şimdi ne yapacağız?"], lineEnding: "\n")
        #expect(try String(contentsOf: stored, encoding: .utf8) == expected)
        // The AirPlay rendition reads the same file with the app's own parser.
        #expect(SRTParser().parse(content: expected).map(\.text) == ["Kapıyı aç.", "Şimdi ne yapacağız?"])
    }

    @Test
    func importRejectsUnsupportedFilesWithoutStoringThem() throws {
        let picked = try temporaryFile(named: "film.sub", contents: Data("{0}{25}Hello\n".utf8))
        defer { try? FileManager.default.removeItem(at: picked.deletingLastPathComponent()) }
        let key = ImportedSubtitleStore.contentKey(playlistId: UUID(), type: "test", streamId: "2")

        #expect(throws: SubtitleImportError.unsupportedFormat) {
            try ImportedSubtitleStore.importFile(at: picked, for: key)
        }
        #expect(!FileManager.default.fileExists(atPath: try storedFolder(for: key).path))
    }

    /// Files imported by earlier versions are raw copies and get rewritten in place.
    @Test
    func normalisesAStoredLegacyFileOnce() throws {
        let source = srtDocument(["<b>Öğretmen çocuğa güldü.</b>"])
        let file = try temporaryFile(
            named: "legacy.srt", contents: try #require(source.data(using: .windowsCP1254))
        )
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(ImportedSubtitleStore.normalizeStoredFile(at: file))
        let expected = srtDocument(["Öğretmen çocuğa güldü."], lineEnding: "\n")
        #expect(try String(contentsOf: file, encoding: .utf8) == expected)
        // Already normalised: nothing left to rewrite.
        #expect(!ImportedSubtitleStore.normalizeStoredFile(at: file))
    }

    @Test
    func leavesAStoredFileItCannotNormaliseUntouched() throws {
        let contents = Data("{0}{25}Hello\n".utf8)
        let file = try temporaryFile(named: "legacy.sub", contents: contents)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(!ImportedSubtitleStore.normalizeStoredFile(at: file))
        #expect(try Data(contentsOf: file) == contents)
    }

    /// The prefix other per-content stores purge by has to match the keys themselves.
    @Test
    func everyContentKeyStartsWithThePlaylistPrefix() {
        let playlist = UUID()
        let prefix = ImportedSubtitleStore.contentKeyPrefix(playlistId: playlist)
        #expect(ImportedSubtitleStore.contentKey(playlistId: playlist, type: "vod", streamId: "42").hasPrefix(prefix))
        #expect(ImportedSubtitleStore.contentKey(playlistId: playlist, type: "series", streamId: "a/b c").hasPrefix(prefix))
        #expect(!ImportedSubtitleStore.contentKey(playlistId: UUID(), type: "vod", streamId: "42").hasPrefix(prefix))
    }
}

// MARK: - Playlist deletion

@Suite("SubtitleDelayStore purge")
struct SubtitleDelayStorePurgeTests {
    /// A private suite per test: nothing leaks into (or from) the app's own defaults.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "SubtitleDelayStorePurgeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test
    func removeAllDropsOnlyTheDeletedPlaylistsOffsets() {
        withDefaults { defaults in
            let deleted = UUID()
            let kept = UUID()
            let film = ImportedSubtitleStore.contentKey(playlistId: deleted, type: "vod", streamId: "1")
            let episode = ImportedSubtitleStore.contentKey(playlistId: deleted, type: "series", streamId: "2")
            let other = ImportedSubtitleStore.contentKey(playlistId: kept, type: "vod", streamId: "1")
            SubtitleDelayStore.setDelaySeconds(2.5, for: film, defaults: defaults)
            SubtitleDelayStore.setDelaySeconds(-1, for: episode, defaults: defaults)
            SubtitleDelayStore.setDelaySeconds(0.5, for: other, defaults: defaults)

            SubtitleDelayStore.removeAll(playlistId: deleted, defaults: defaults)

            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == 1)
            #expect(SubtitleDelayStore.delaySeconds(for: film, defaults: defaults) == 0)
            #expect(SubtitleDelayStore.delaySeconds(for: episode, defaults: defaults) == 0)
            #expect(SubtitleDelayStore.delaySeconds(for: other, defaults: defaults) == 0.5)
        }
    }

    @Test
    func removeAllForAPlaylistWithoutOffsetsChangesNothing() {
        withDefaults { defaults in
            let other = ImportedSubtitleStore.contentKey(playlistId: UUID(), type: "vod", streamId: "1")
            SubtitleDelayStore.setDelaySeconds(0.5, for: other, defaults: defaults)

            SubtitleDelayStore.removeAll(playlistId: UUID(), defaults: defaults)

            #expect(SubtitleDelayStore.entryCount(defaults: defaults) == 1)
            #expect(SubtitleDelayStore.delaySeconds(for: other, defaults: defaults) == 0.5)
        }
    }
}

// MARK: - Legacy subtitle offset in the style settings

@Suite("SubtitleAppearanceSettings coding")
struct SubtitleAppearanceSettingsCodingTests {

    /// Settings saved by earlier versions carry the old global offset: they still load,
    /// and the next save no longer writes it.
    @Test
    func legacyDelayIsDecodedButNotWrittenBack() throws {
        let legacy = Data(#"{"fontSize":48,"italic":true,"delaySeconds":2.5}"#.utf8)
        let decoded = try JSONDecoder().decode(SubtitleAppearanceSettings.self, from: legacy)
        #expect(decoded.fontSize == 48)
        #expect(decoded.italic)
        #expect(decoded.delaySeconds == 2.5)

        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["delaySeconds"] == nil)
        #expect(object["fontSize"] as? Int == 48)
        #expect(object["italic"] as? Bool == true)

        // What a save followed by a load yields: the style without the old offset.
        let reloaded = try JSONDecoder().decode(SubtitleAppearanceSettings.self, from: encoded)
        #expect(reloaded.delaySeconds == 0)
        #expect(reloaded.fontSize == 48)
    }
}
