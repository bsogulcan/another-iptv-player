import Foundation
import Testing
@testable import another_iptv_player

/// Deterministic catalog names for the search tests: ASCII, Turkish, accented Latin,
/// Cyrillic, Arabic and full-width forms, with the prefixes real panels put in front.
nonisolated enum CatalogSearchFixtures {
    private static let tags = ["EN - ", "TR: ", "", "AR | ", "DE ▎", "[4K] ", "UK| "]
    private static let first = [
        "The", "Dark", "Night", "Silent", "Last", "Işık", "Şehir", "Çılgın", "Amélie", "Мир",
        "Ёлка", "\u{0645}\u{0635}\u{0631}", "\u{0623}\u{062D}\u{0645}\u{062F}", "ＦＯＸ", "Star",
        "Blue", "Red", "İstanbul", "HISTORY", "Film",
    ]
    private static let second = [
        "Knight", "Movie", "Story", "Gölge", "Sports", "News", "Война",
        "\u{0645}\u{064F}\u{062D}\u{064E}\u{0645}\u{0651}\u{064E}\u{062F}", "４Ｋ", "House",
        "River", "Batman", "Spider-Man",
    ]

    static func titles(count: Int) -> [String] {
        (0..<count).map { i in
            let tag = tags[(i / 3) % tags.count]
            let a = first[(i * 7) % first.count]
            let b = second[(i / first.count) % second.count]
            return "\(tag)\(a) \(b) \(i)"
        }
    }

    /// Inputs that have tripped folds before: combining marks, compatibility forms,
    /// symbols, scripts without case, empty and punctuation-only names.
    static let oddities = [
        "", " ", "--", "####  UK SPORTS ####", "Šport 1 ᴴᴰ", "DE | ZDF neo ᵁᴴᴰ", "FR ▎TF1 4K",
        "beIN SPORTS 1 ⁵⁰ᶠᵖˢ", "Ελληνικά", "한국어 채널", "日本語チャンネル", "VIP★Movies", "①②③",
        "ǅ ǆ ß ﬁ", "x² ½", "9½ Weeks", "आज तक समाचार", "हिन्दी", "Straße", "📺 TV", "𝐀𝐁𝐂 bold",
        "\u{212A} kelvin", "\u{212B} angstrom", "E\u{0301}cole", "a\u{0308}b", "naïve café", "ıI iİ",
        "tab\there", "line\nbreak", "nbsp\u{00A0}here", "wide\u{3000}space", "ｶﾀｶﾅ", "カタカナ",
        "שָׁלוֹם", "AR | MBC \u{0645}\u{0635}\u{0631} 2", "\u{0645}\u{0640}\u{062D}\u{0640}\u{0645}\u{062F}",
        "The Dark Knight Rises (2012)", "the dark knight", "DARK", "dark", "K", "k", "4K", "0",
    ]

    static let searches = [
        "the", "t", "a", "e", "k", "K", "isik", "ışık", "film", "fox tv", "fox", "4k", "news",
        "sports 1", "é", "ß", "ss", "мир", "война", "\u{0645}\u{0635}\u{0631}",
        "\u{0627}\u{062D}\u{0645}\u{062F}", "--", "", " ", "abc", "the dark", "dark the",
        "dark knight rises 2012", "x2", "2012", "ｆｏｘ", "한국", "日本", "ecole", "ab", "ａ",
        "spiderman", "spider man 12", "knight", "zzz", "0", "tv",
    ]
}

@Suite("CatalogTextSearch ASCII fast path")
struct CatalogTextSearchFastPathTests {

    private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

    /// The fold as it was before it learned width and Arabic variants, and before the
    /// ASCII fast path existed.
    private func previousFold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// Width and Arabic folding are new; everywhere else the key must not have moved.
    private func hasNewlyFoldedScalars(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }
    }

    /// The words of a search, folded on the general path only.
    private func generalWords(_ search: String) -> [String] {
        search.split(whereSeparator: \.isWhitespace)
            .map { CatalogTextSearch.foldUnicode(String($0)) }
            .filter { !$0.isEmpty }
    }

    @Test
    func everyASCIICharacterFoldsLikeTheGeneralPath() {
        for value in UInt8(0)...UInt8(127) {
            let character = String(UnicodeScalar(value))
            for text in [character, "a\(character)B", "\(character)\(character)9"] {
                #expect(scalars(CatalogTextSearch.normalize(text)) == scalars(CatalogTextSearch.foldUnicode(text)))
            }
        }
    }

    @Test
    func normalizeAgreesWithTheGeneralPathOnAMixedCorpus() {
        let titles = CatalogSearchFixtures.titles(count: 3_000) + CatalogSearchFixtures.oddities
        var differing: [String] = []
        for title in titles where scalars(CatalogTextSearch.normalize(title)) != scalars(CatalogTextSearch.foldUnicode(title)) {
            differing.append(title)
        }
        #expect(differing.isEmpty, "\(differing.prefix(5))")
    }

    @Test
    func matchingAgreesWithTheGeneralPathOnAMixedCorpus() {
        let titles = CatalogSearchFixtures.titles(count: 6_000) + CatalogSearchFixtures.oddities
        let keys = titles.map { CatalogTextSearch.foldUnicode($0) }
        #expect(titles.contains { $0.utf8.allSatisfy { $0 < 0x80 } })
        #expect(titles.contains { !$0.utf8.allSatisfy { $0 < 0x80 } })

        for search in CatalogSearchFixtures.searches {
            let query = CatalogTextSearch.Query(search)
            let words = generalWords(search)
            let isBlank = search.allSatisfy(\.isWhitespace)
            var differing: [String] = []
            for (title, key) in zip(titles, keys) {
                let expected = words.isEmpty ? isBlank : words.allSatisfy { key.contains($0) }
                if query.matches(title) != expected { differing.append(title) }
            }
            #expect(differing.isEmpty, "search \"\(search)\": \(differing.prefix(5))")
        }
    }

    @Test
    func rankingAgreesWithTheGeneralPathOnAMixedCorpus() {
        let titles = CatalogSearchFixtures.titles(count: 6_000) + CatalogSearchFixtures.oddities
        let keys = titles.map { CatalogTextSearch.foldUnicode($0) }

        for search in CatalogSearchFixtures.searches {
            let words = generalWords(search)
            guard !words.isEmpty else { continue }
            let whole = CatalogTextSearch.foldUnicode(search)
            var hits: [(tier: Int, offset: Int)] = []
            for (offset, key) in keys.enumerated() where words.allSatisfy({ key.contains($0) }) {
                hits.append((key == whole ? 0 : key.hasPrefix(whole) ? 1 : 2, offset))
            }
            hits.sort { a, b in
                if a.tier != b.tier { return a.tier < b.tier }
                switch titles[a.offset].localizedCaseInsensitiveCompare(titles[b.offset]) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return a.offset < b.offset
                }
            }
            let expected = hits.map { titles[$0.offset] }
            let ranked = CatalogTextSearch.rankedFilter(titles, search: search) { $0 }
            #expect(ranked == expected, "search \"\(search)\"")
        }
    }

    @Test
    func keysOutsideWidthAndArabicFoldingDidNotChange() {
        let titles = (CatalogSearchFixtures.titles(count: 3_000) + CatalogSearchFixtures.oddities)
            .filter { !hasNewlyFoldedScalars($0) }
        #expect(titles.count > 1_000)
        var differing: [String] = []
        for title in titles where scalars(CatalogTextSearch.normalize(title)) != scalars(previousFold(title)) {
            differing.append(title)
        }
        #expect(differing.isEmpty, "\(differing.prefix(5))")
    }

    @Test
    func matchesOutsideWidthAndArabicFoldingDidNotChange() {
        let titles = (CatalogSearchFixtures.titles(count: 3_000) + CatalogSearchFixtures.oddities)
            .filter { !hasNewlyFoldedScalars($0) }
        // None of these searches mixes words with a punctuation-only token ("tom & jerry"):
        // such a token used to block every match and is now ignored, on purpose.
        let searches = CatalogSearchFixtures.searches.filter { !hasNewlyFoldedScalars($0) }
        for search in searches {
            let rawWords = search.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let previousWords = rawWords.map { previousFold($0) }
            var differing: [String] = []
            for title in titles {
                let key = previousFold(title)
                let previous = previousWords.isEmpty || previousWords.allSatisfy { key.contains($0) }
                if CatalogTextSearch.matches(search: search, text: title) != previous { differing.append(title) }
            }
            #expect(differing.isEmpty, "search \"\(search)\": \(differing.prefix(5))")
        }
    }
}
