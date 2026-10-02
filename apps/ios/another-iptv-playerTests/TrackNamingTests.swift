import Foundation
import Testing
@testable import another_iptv_player

/// Rows of the track sheet and the saved preferences that are matched against them.
/// The engine builds the rows from live player objects, so the rules live in
/// `TrackNaming` and `PlaybackTrackPreferences` and are locked here without a player.

// MARK: - Row titles

struct TrackTitleTests {
    private let english = Locale(identifier: "en")

    private func title(
        _ name: String, language: String?, codec: String? = nil, locale: String = "en"
    ) -> TrackNaming.Title {
        TrackNaming.title(
            name: name,
            languageCode: language,
            codecName: codec,
            fallback: "Track 2",
            locale: Locale(identifier: locale)
        )
    }

    /// KSPlayer fills a missing title with the language code.
    @Test func languageCodeAsNameBecomesTheLanguageName() {
        #expect(title("tur", language: "tur") == .init(text: "Turkish", isSynthetic: true))
        #expect(title("tur", language: "tur", locale: "tr").text == "Türkçe")
        #expect(title("", language: "eng").text == "English")
        #expect(title("TUR", language: "tur").text == "Turkish")
    }

    @Test func bothSpellingsOfThreeLetterCodesResolve() {
        #expect(title("ger", language: "ger").text == "German")
        #expect(title("deu", language: "deu").text == "German")
        #expect(title("fre", language: "fre").text == "French")
        #expect(title("chi", language: "chi").text == "Chinese")
        #expect(title("tr", language: "tr").text == "Turkish")
    }

    /// French and other languages write language names in lower case.
    @Test func languageNameStartsWithACapital() {
        #expect(title("eng", language: "eng", locale: "fr").text == "Anglais")
        #expect(title("fra", language: "fra", locale: "fr").text == "Français")
    }

    /// Without a title or a language KSPlayer reports the codec name.
    @Test func codecNameAsNameFallsBackToThePosition() {
        #expect(
            title("aac (LC)", language: nil, codec: "aac (LC)")
                == .init(text: "Track 2", isSynthetic: true)
        )
        #expect(title("subrip", language: nil, codec: "subrip").text == "Track 2")
        #expect(title("h264", language: nil, codec: "h264 (Baseline)").text == "Track 2")
        #expect(title("", language: nil).text == "Track 2")
    }

    @Test func titleTagIsKept() {
        #expect(
            title("Director's commentary", language: "eng", codec: "ac3")
                == .init(text: "Director's commentary", isSynthetic: false)
        )
        #expect(title("  Surround 5.1 ", language: nil).text == "Surround 5.1")
    }

    /// Codes Foundation has no name for are still better than a position.
    @Test func codeWithoutANameIsShownAsIs() {
        #expect(title("qaa", language: "qaa") == .init(text: "qaa", isSynthetic: true))
    }

    /// "pob" is not an ISO code, but common for Brazilian Portuguese releases.
    @Test func releaseCodeIsResolvedThroughTheLanguageTable() {
        #expect(title("pob", language: "pob").text == "Portuguese")
    }

    @Test func undeterminedIsNotALanguage() {
        #expect(title("und", language: "und").text == "Track 2")
        #expect(TrackNaming.languageName(forCode: "und", locale: english) == nil)
        #expect(TrackNaming.languageName(forCode: nil, locale: english) == nil)
        #expect(TrackNaming.languageName(forCode: "  ", locale: english) == nil)
    }

    @Test func regionIsNamedWhenTheTagCarriesOne() {
        #expect(TrackNaming.languageName(forCode: "pt-BR", locale: english) == "Portuguese (Brazil)")
        #expect(TrackNaming.languageName(forCode: "pt", locale: english) == "Portuguese")
    }

    /// KSPlayer appends "(hearing impaired)" to the name of such subtitle tracks.
    @Test func hearingImpairedMarkerIsShortened() {
        #expect(
            title("eng(hearing impaired)", language: "eng")
                == .init(text: "English (SDH)", isSynthetic: true)
        )
        #expect(
            title("Full(hearing impaired)", language: "eng")
                == .init(text: "Full (SDH)", isSynthetic: false)
        )
        #expect(title("subrip(hearing impaired)", language: nil, codec: "subrip").text == "Track 2 (SDH)")
    }

    @Test func detailNamesTheLanguageOfATitledTrackOnly() {
        let commentary = TrackNaming.Title(text: "Commentary", isSynthetic: false)
        #expect(
            TrackNaming.detailLanguageName(for: commentary, languageCode: "eng", locale: english)
                == "English"
        )
        // The title already says it.
        let named = TrackNaming.Title(text: "ENGLISH 5.1", isSynthetic: false)
        #expect(
            TrackNaming.detailLanguageName(for: named, languageCode: "eng", locale: english) == nil
        )
        // The title is the language name itself.
        let synthetic = TrackNaming.Title(text: "English", isSynthetic: true)
        #expect(
            TrackNaming.detailLanguageName(for: synthetic, languageCode: "eng", locale: english) == nil
        )
        #expect(
            TrackNaming.detailLanguageName(for: commentary, languageCode: nil, locale: english) == nil
        )
    }

    /// KSPlayer's codec name carries a profile suffix that is not the stream's.
    @Test func codecLabelDropsTheProfile() {
        #expect(TrackNaming.codecLabel("h264 (Baseline)") == "H.264")
        #expect(TrackNaming.codecLabel("eac3 (Dolby Digital Plus + Dolby Atmos)") == "E-AC-3")
        #expect(TrackNaming.codecLabel("aac (LC)") == "AAC")
        #expect(TrackNaming.codecLabel("subrip") == "SRT")
        #expect(TrackNaming.codecLabel("hdmv_pgs_subtitle") == "PGS")
        #expect(TrackNaming.codecLabel("wmav2") == "WMAV2")
        #expect(TrackNaming.codecLabel("") == nil)
        #expect(TrackNaming.codecLabel(nil) == nil)
    }
}

// MARK: - Saving and matching preferences

struct TrackPreferenceMatchingTests {
    private typealias Prefs = PlaybackTrackPreferences

    private let off = TrackMenuOption(id: -1, title: "Off")

    /// The row title is a localized language name; the preference is the language.
    @Test func subtitleIsMatchedByLanguageAcrossSpellings() throws {
        let chosen = TrackMenuOption(id: 0, title: "Turkish", langCode: "tur", isSyntheticTitle: true)
        let stored = try #require(Prefs.storage(Prefs.Storage(), savingSubtitle: chosen))
        #expect(stored.subtitleLang == "tur")
        #expect(stored.subtitleTitleFallback == nil)

        let next = [
            off,
            TrackMenuOption(id: 0, title: "English", langCode: "en", isSyntheticTitle: true),
            TrackMenuOption(id: 1, title: "Türkçe altyazı", langCode: "tr"),
        ]
        #expect(Prefs.pickSubtitle(from: next, prefs: stored) == 1)
    }

    @Test func subtitleLanguageWithoutAMatchKeepsThePlayersChoice() {
        let prefs = Prefs.Storage(subtitleLang: "tur")
        let tracks = [off, TrackMenuOption(id: 0, title: "English", langCode: "eng", isSyntheticTitle: true)]
        #expect(Prefs.pickSubtitle(from: tracks, prefs: prefs) == nil)
        #expect(Prefs.pickSubtitle(from: [off], prefs: prefs) == nil)
    }

    @Test func subtitlesSwitchedOffStayOff() throws {
        let stored = try #require(
            Prefs.storage(Prefs.Storage(subtitleLang: "tur"), savingSubtitle: off)
        )
        let tracks = [off, TrackMenuOption(id: 0, title: "Turkish", langCode: "tur", isSyntheticTitle: true)]
        #expect(Prefs.pickSubtitle(from: tracks, prefs: stored) == -1)
    }

    /// An imported file is remembered per title elsewhere; it must not replace the
    /// language (or "off") that applies to everything else.
    @Test func importedFileLeavesThePreferenceAlone() {
        let imported = TrackMenuOption(id: 3, title: "movie.tr.srt", isExternal: true)
        #expect(Prefs.storage(Prefs.Storage(subtitleLang: "tur"), savingSubtitle: imported) == nil)
    }

    /// "Track 2" says nothing the next item could be matched by.
    @Test func rowWithoutLanguageOrTitleLeavesThePreferenceAlone() {
        let untagged = TrackMenuOption(id: 1, title: "Track 2", isSyntheticTitle: true)
        let current = Prefs.Storage(audioLang: "tur", subtitleLang: "tur", videoLang: "eng")
        #expect(Prefs.storage(current, savingAudio: untagged) == nil)
        #expect(Prefs.storage(current, savingSubtitle: untagged) == nil)
        #expect(Prefs.storage(current, savingVideo: untagged) == nil)
    }

    @Test func titleTagIsStoredAndMatchedAsTagged() throws {
        let commentary = TrackMenuOption(id: 2, title: "Commentary")
        let stored = try #require(Prefs.storage(Prefs.Storage(audioLang: "tur"), savingAudio: commentary))
        #expect(stored.audioLang == nil)
        #expect(stored.audioTitleFallback == "commentary")

        let tracks = [
            // Same text, but a display name rather than a tag of the stream.
            TrackMenuOption(id: 0, title: "Commentary", isSyntheticTitle: true),
            TrackMenuOption(id: 1, title: "COMMENTARY"),
        ]
        #expect(Prefs.pickAudio(from: tracks, prefs: stored) == 1)
    }

    @Test func audioLanguageIsStoredAndMatched() throws {
        let chosen = TrackMenuOption(id: 1, title: "Türkçe", langCode: "tur", isSyntheticTitle: true)
        let stored = try #require(Prefs.storage(Prefs.Storage(), savingAudio: chosen))
        #expect(stored.audioLang == "tur")
        let tracks = [
            TrackMenuOption(id: 0, title: "English", langCode: "eng", isSyntheticTitle: true),
            TrackMenuOption(id: 5, title: "Turkish", langCode: "tr-TR", isSyntheticTitle: true),
        ]
        #expect(Prefs.pickAudio(from: tracks, prefs: stored) == 5)
    }

    /// Before subtitle rows carried a language, an untitled track's code was stored as
    /// its title.
    @Test func languageTagStoredAsTitleIsReadAsLanguage() {
        let migrated = Prefs.migrated(Prefs.Storage(subtitleTitleFallback: "tur"))
        #expect(migrated == Prefs.Storage(subtitleLang: "tur"))

        let tracks = [off, TrackMenuOption(id: 0, title: "Turkish", langCode: "tr", isSyntheticTitle: true)]
        #expect(Prefs.pickSubtitle(from: tracks, prefs: migrated) == 0)
    }

    @Test func otherStoredValuesAreNotMigrated() {
        // A three-letter title that is not a language of the table.
        let title = Prefs.Storage(subtitleTitleFallback: "dub")
        #expect(Prefs.migrated(title) == title)
        let withLanguage = Prefs.Storage(subtitleLang: "eng", subtitleTitleFallback: "tur")
        #expect(Prefs.migrated(withLanguage) == withLanguage)
        let audio = Prefs.Storage(audioTitleFallback: "tur")
        #expect(Prefs.migrated(audio) == audio)
    }

    @Test func languagesAreMatchedThroughTheTableOnly() {
        #expect(Prefs.langMatches(stored: "tr", trackLang: "tur"))
        #expect(Prefs.langMatches(stored: "ger", trackLang: "de"))
        #expect(Prefs.langMatches(stored: "pt", trackLang: "pt-BR"))
        // Shared prefixes are not a relation.
        #expect(!Prefs.langMatches(stored: "pt", trackLang: "pol"))
        #expect(!Prefs.langMatches(stored: "tur", trackLang: "tuk"))
        #expect(!Prefs.langMatches(stored: "tur", trackLang: nil))
    }

    @Test func tableKnowsBothSpellings() {
        #expect(Prefs.twoLetterCode(for: "ger") == "de")
        #expect(Prefs.twoLetterCode(for: "deu") == "de")
        #expect(Prefs.twoLetterCode(for: "DE") == "de")
        #expect(Prefs.twoLetterCode(for: "dub") == nil)
        #expect(Prefs.isKnownLanguageCode("tur"))
        #expect(!Prefs.isKnownLanguageCode("subrip"))
    }
}

// MARK: - Audio language before playback

struct PreferredAudioIndexTests {
    private typealias Prefs = PlaybackTrackPreferences

    @Test func firstTrackInThePreferredLanguageWins() {
        let index = Prefs.preferredAudioIndex(
            languageCodes: ["eng", "tur", "tur"], selectable: [true, true, true],
            preferredLanguage: "tr"
        )
        #expect(index == 1)
    }

    /// A track FFmpeg cannot decode is never chosen, whatever its language.
    @Test func unselectableTrackIsSkipped() {
        let index = Prefs.preferredAudioIndex(
            languageCodes: ["tur", "eng", "tur"], selectable: [false, true, true],
            preferredLanguage: "tur"
        )
        #expect(index == 2)
        let none = Prefs.preferredAudioIndex(
            languageCodes: ["tur"], selectable: [false], preferredLanguage: "tur"
        )
        #expect(none == nil)
    }

    @Test func noPreferenceOrNoMatchLeavesThePickToThePlayer() {
        #expect(
            Prefs.preferredAudioIndex(
                languageCodes: ["eng", "tur"], selectable: [true, true], preferredLanguage: nil
            ) == nil
        )
        #expect(
            Prefs.preferredAudioIndex(
                languageCodes: ["eng", "tur"], selectable: [true, true], preferredLanguage: ""
            ) == nil
        )
        #expect(
            Prefs.preferredAudioIndex(
                languageCodes: ["eng", nil], selectable: [true, true], preferredLanguage: "tur"
            ) == nil
        )
        #expect(
            Prefs.preferredAudioIndex(languageCodes: [], selectable: [], preferredLanguage: "tur") == nil
        )
    }

    @Test func missingSelectableEntriesCountAsSelectable() {
        let index = Prefs.preferredAudioIndex(
            languageCodes: ["eng", "tur"], selectable: [], preferredLanguage: "tur"
        )
        #expect(index == 1)
    }
}

// MARK: - Simultaneous subtitle cues

struct SubtitleCueMergeTests {
    private func cues(_ strings: [String]) -> [NSAttributedString] {
        strings.map { NSAttributedString(string: $0) }
    }

    @Test func singleCueIsPassedThrough() {
        let cue = NSAttributedString(string: "Hello")
        #expect(KSPlayerEngine.mergedSubtitleText([cue]) === cue)
    }

    @Test func overlappingCuesAreStackedInOrder() {
        let merged = KSPlayerEngine.mergedSubtitleText(cues(["- Where to?", "- Home."]))
        #expect(merged?.string == "- Where to?\n- Home.")
    }

    /// ASS files repeat a line across layers for outline and shadow effects.
    @Test func repeatedLineIsShownOnce() {
        let merged = KSPlayerEngine.mergedSubtitleText(cues(["Sign", "Sign", "Dialogue"]))
        #expect(merged?.string == "Sign\nDialogue")
    }

    @Test func emptyCuesAreDropped() {
        #expect(KSPlayerEngine.mergedSubtitleText([]) == nil)
        #expect(KSPlayerEngine.mergedSubtitleText(cues(["", "  \n"])) == nil)
        #expect(KSPlayerEngine.mergedSubtitleText(cues(["", "Only"]))?.string == "Only")
    }

    @Test func blockIsCapped() {
        let merged = KSPlayerEngine.mergedSubtitleText(cues(["1", "2", "3", "4", "5", "6"]))
        let lines = merged?.string.components(separatedBy: "\n")
        #expect(lines?.count == KSPlayerEngine.maxSimultaneousSubtitleCues)
        #expect(lines?.first == "1")
    }
}
