import Foundation
import Testing
@testable import another_iptv_player

@Suite("CatalogTextSearch")
struct CatalogTextSearchTests {

    // MARK: - matches

    @Test
    func matchesIsCaseInsensitive() {
        #expect(CatalogTextSearch.matches(search: "news", text: "MORNING NEWS") == true)
        #expect(CatalogTextSearch.matches(search: "NEWS", text: "morning news") == true)
    }

    @Test
    func matchesIsDiacriticInsensitive() {
        #expect(CatalogTextSearch.matches(search: "istanbul", text: "İSTANBUL HABER") == true)
        #expect(CatalogTextSearch.matches(search: "sehir", text: "Şehir TV") == true)
        #expect(CatalogTextSearch.matches(search: "video", text: "VİDEO PLUS") == true)
    }

    @Test
    func matchesUppercaseLatinIWithLowercaseQuery() {
        // Regression: tr_TR lowercasing mapped "I"→"ı", so lowercase queries missed
        // any ALL-CAPS name containing "I" ("HISTORY HD" → "hıstory hd").
        #expect(CatalogTextSearch.matches(search: "history", text: "HISTORY HD") == true)
        #expect(CatalogTextSearch.matches(search: "film", text: "FILM 4K") == true)
        #expect(CatalogTextSearch.matches(search: "silicon", text: "SILICON VALLEY") == true)
    }

    @Test
    func matchesTurkishDotlessIQueries() {
        // Turkish dotless-ı queries must still match ALL-CAPS Turkish names.
        #expect(CatalogTextSearch.matches(search: "ışık", text: "IŞIK TV") == true)
        #expect(CatalogTextSearch.matches(search: "isik", text: "IŞIK TV") == true)
        #expect(CatalogTextSearch.matches(search: "çılgın", text: "CILGIN DUNYA") == true)
    }

    @Test
    func matchesIgnoresPunctuationAndSpaces() {
        // Non-alphanumeric characters are stripped on both sides.
        #expect(CatalogTextSearch.matches(search: "world news", text: "World-News HD") == true)
        #expect(CatalogTextSearch.matches(search: "fox.tv", text: "FOX TV") == true)
    }

    @Test
    func matchesAllWordsRequired() {
        #expect(CatalogTextSearch.matches(search: "sports tv", text: "Sports HD TV") == true)
        #expect(CatalogTextSearch.matches(search: "sports zone", text: "Sports HD TV") == false)
    }

    @Test
    func emptySearchAlwaysMatches() {
        #expect(CatalogTextSearch.matches(search: "", text: "anything") == true)
        #expect(CatalogTextSearch.matches(search: "   ", text: "anything") == true)
    }

    @Test
    func nonMatchingReturnsFalse() {
        #expect(CatalogTextSearch.matches(search: "sports", text: "News Channel") == false)
    }

    // MARK: - normalize

    @Test
    func normalizeFoldsCaseAccentsWidthAndPunctuation() {
        #expect(CatalogTextSearch.normalize("Spider-Man: No Way Home (2021)") == "spidermannowayhome2021")
        #expect(CatalogTextSearch.normalize("Amélie") == "amelie")
        #expect(CatalogTextSearch.normalize("IŞIK") == "isik")
        #expect(CatalogTextSearch.normalize("ışık") == "isik")
        #expect(CatalogTextSearch.normalize("ＦＯＸ ４Ｋ") == "fox4k")
        #expect(CatalogTextSearch.normalize("--") == "")
        #expect(CatalogTextSearch.normalize("") == "")
    }

    // MARK: - Query

    private func finds(_ search: String, _ text: String) -> Bool {
        CatalogTextSearch.Query(search).matches(text)
    }

    @Test
    func queryFindsDottedAndDotlessCapitalI() {
        // The fold does not depend on the device language: a Turkish locale lowercases
        // "I" to "ı" and "İ" to "i", an English one does the opposite.
        #expect(finds("film", "FİLM") == true)
        #expect(finds("film", "FILM") == true)
        #expect(finds("film", "Fılm") == true)
        #expect(finds("FİLM", "film 4k") == true)
        #expect(finds("FILM", "film 4k") == true)
        #expect(finds("bein", "BEIN SPORTS 1") == true)
        #expect(finds("bein", "BEİN SPORTS 1") == true)
        #expect(finds("history", "HISTORY HD") == true)
        #expect(finds("inception", "Inception") == true)
        #expect(finds("titanic", "TITANIC") == true)
        #expect(finds("TITANIC", "Titanic") == true)
        #expect(finds("isik", "IŞIK TV") == true)
        #expect(finds("ışık", "IŞIK TV") == true)
    }

    @Test
    func queryIgnoresAccentsInBothDirections() {
        #expect(finds("amelie", "Amélie") == true)
        #expect(finds("Amélie", "AMELIE POULAIN") == true)
        #expect(finds("sehir", "Şehir") == true)
        #expect(finds("şehir", "SEHIR TV") == true)
        #expect(finds("golge", "Gölge") == true)
        // Decomposed input (base letter + combining mark) folds like the composed one.
        #expect(finds("ecole", "E\u{0301}cole") == true)
        #expect(finds("елка", "Ёлка") == true)
        #expect(finds("strasse", "Straße") == true)
    }

    @Test
    func queryIgnoresPunctuationAndSpacing() {
        #expect(finds("spiderman", "Spider-Man") == true)
        #expect(finds("spider-man", "Spiderman") == true)
        #expect(finds("spider man", "SPIDERMAN") == true)
        #expect(finds("foxtv", "FOX TV") == true)
        #expect(finds("m*a*s*h", "MASH (1970)") == true)
        #expect(finds("mash", "M*A*S*H") == true)
        #expect(finds("wall e", "WALL·E") == true)
    }

    @Test
    func queryDropsTokensWithoutLettersOrDigits() {
        // "&" and "-" fold to nothing; they must neither block the match nor count as a word.
        #expect(finds("tom & jerry", "Tom & Jerry") == true)
        #expect(finds("tom & jerry", "Tom and Jerry") == true)
        #expect(finds("spider - man", "Spider-Man") == true)
        #expect(CatalogTextSearch.matches(search: "fox -- tv", text: "FOX TV") == true)
    }

    @Test
    func queryWithoutLettersOrDigitsMatchesNothing() {
        // A punctuation-only search must not return the whole catalog.
        for search in ["--", "!!", " - ", "&", "…"] {
            let query = CatalogTextSearch.Query(search)
            #expect(query.isEmpty == true)
            #expect(query.matches("FOX TV") == false)
            #expect(query.matches("") == false)
            #expect(CatalogTextSearch.matches(search: search, text: "FOX TV") == false)
        }
    }

    @Test
    func blankQueryIsEmptyAndMatchesEverything() {
        for search in ["", " ", "\t ", "\u{3000}"] {
            let query = CatalogTextSearch.Query(search)
            #expect(query.isEmpty == true)
            #expect(query.matches("anything") == true)
            #expect(query.matches("") == true)
        }
        #expect(CatalogTextSearch.Query("a").isEmpty == false)
        #expect(CatalogTextSearch.Query(" 4k ").isEmpty == false)
    }

    @Test
    func queryWordsMatchInAnyOrder() {
        #expect(finds("tv news", "News on TV") == true)
        #expect(finds("news tv", "News on TV") == true)
        #expect(finds("2012 dark knight", "The Dark Knight Rises (2012)") == true)
        #expect(finds("knight 2013", "The Dark Knight Rises (2012)") == false)
        #expect(finds("news news", "News on TV") == true)
        // Words are separated by any white space, including the ideographic space.
        #expect(finds("tv\u{3000}news", "News on TV") == true)
        #expect(finds("tv\nnews", "News on TV") == true)
    }

    @Test
    func queryFoldsArabicSpellingVariants() {
        let ahmad = "\u{0627}\u{062D}\u{0645}\u{062F}"                                  // احمد
        let ahmadHamza = "\u{0623}\u{062D}\u{0645}\u{062F}"                             // أحمد
        let muhammad = "\u{0645}\u{062D}\u{0645}\u{062F}"                               // محمد
        let muhammadVowelled = "\u{0645}\u{064F}\u{062D}\u{064E}\u{0645}\u{0651}\u{064E}\u{062F}"  // مُحَمَّد
        let muhammadStretched = "\u{0645}\u{0640}\u{062D}\u{0640}\u{0645}\u{062F}"     // مـحـمد (tatweel)
        let school = "\u{0645}\u{062F}\u{0631}\u{0633}\u{0647}"                        // مدرسه
        let schoolTaMarbuta = "\u{0645}\u{062F}\u{0631}\u{0633}\u{0629}"               // مدرسة
        let ali = "\u{0639}\u{0644}\u{064A}"                                            // علي
        let aliAlefMaqsura = "\u{0639}\u{0644}\u{0649}"                                 // على
        let aliFarsiYeh = "\u{0639}\u{0644}\u{06CC}"                                    // علی
        let other = "\u{0627}\u{062E}\u{0631}"                                          // اخر
        let otherMadda = "\u{0622}\u{062E}\u{0631}"                                     // آخر
        let islam = "\u{0627}\u{0633}\u{0644}\u{0627}\u{0645}"                          // اسلام
        let islamHamzaBelow = "\u{0625}\u{0633}\u{0644}\u{0627}\u{0645}"                // إسلام
        let book = "\u{0643}\u{062A}\u{0627}\u{0628}"                                   // كتاب
        let bookKeheh = "\u{06A9}\u{062A}\u{0627}\u{0628}"                              // کتاب

        let pairs = [
            (ahmad, ahmadHamza), (muhammad, muhammadVowelled), (muhammad, muhammadStretched),
            (school, schoolTaMarbuta), (ali, aliAlefMaqsura), (ali, aliFarsiYeh),
            (other, otherMadda), (islam, islamHamzaBelow), (book, bookKeheh),
        ]
        for (plain, variant) in pairs {
            #expect(finds(plain, "MBC \(variant) HD") == true)
            #expect(finds(variant, "MBC \(plain) HD") == true)
            #expect(CatalogTextSearch.equals(search: plain, text: variant) == true)
        }
        // Different words stay different.
        #expect(finds(ahmad, muhammad) == false)
    }

    @Test
    func queryFoldsFullWidthAndHalfWidthForms() {
        #expect(finds("abc", "ＡＢＣ") == true)
        #expect(finds("ＡＢＣ", "abc news") == true)
        #expect(finds("4k", "ＦＯＸ ４Ｋ") == true)
        #expect(finds("fox 4k", "ＦＯＸ ４Ｋ") == true)
        #expect(finds("ｆｏｘ", "FOX TV") == true)
        #expect(finds("２０１２", "The Dark Knight Rises (2012)") == true)
        // Half-width katakana is the same text as the full-width form.
        #expect(finds("カタカナ", "ｶﾀｶﾅ") == true)
        #expect(finds("ｶﾀｶﾅ", "カタカナ") == true)
    }

    @Test
    func wrapperAgreesWithPreparedQuery() {
        let names = ["FOX TV", "IŞIK TV", "Spider-Man", "ＦＯＸ ４Ｋ", "Ёлка", ""]
        for search in ["fox", "isik", "spider man", "4k", "елка", "", " ", "--", "zzz"] {
            let query = CatalogTextSearch.Query(search)
            for name in names {
                #expect(CatalogTextSearch.matches(search: search, text: name) == query.matches(name))
            }
        }
    }

    // MARK: - equals

    @Test
    func equalsIgnoresPunctuationAndDiacritics() {
        #expect(CatalogTextSearch.equals(search: "fox tv", text: "FOX-TV") == true)
        #expect(CatalogTextSearch.equals(search: "istanbul", text: "İstanbul") == true)
    }

    @Test
    func equalsReturnsFalseForDifferentText() {
        #expect(CatalogTextSearch.equals(search: "abc", text: "abcd") == false)
    }

    // MARK: - startsWith

    @Test
    func startsWithPrefixMatch() {
        #expect(CatalogTextSearch.startsWith(search: "spo", text: "Sports HD") == true)
        #expect(CatalogTextSearch.startsWith(search: "fox", text: "FOX TV") == true)
    }

    @Test
    func startsWithDoesNotMatchInfix() {
        #expect(CatalogTextSearch.startsWith(search: "tv", text: "Sports TV") == false)
    }

    // MARK: - sortLiveByRelevance

    @Test
    func sortLiveEmptySearchRespectsSortIndex() {
        let items = [
            makeLiveWithCat(name: "Zeta", sortIndex: 2),
            makeLiveWithCat(name: "Alpha", sortIndex: 0),
            makeLiveWithCat(name: "Beta", sortIndex: 1),
        ]
        let sorted = CatalogTextSearch.sortLiveByRelevance(items, search: "")
        #expect(sorted.map(\.stream.name) == ["Alpha", "Beta", "Zeta"])
    }

    @Test
    func sortLivePrioritizesExactMatch() {
        let items = [
            makeLiveWithCat(name: "Sports News"),
            makeLiveWithCat(name: "Sports"),
            makeLiveWithCat(name: "Sports Plus"),
        ]
        let sorted = CatalogTextSearch.sortLiveByRelevance(items, search: "sports")
        #expect(sorted.first?.stream.name == "Sports")
    }

    @Test
    func sortLivePrioritizesPrefixOverInfix() {
        let items = [
            makeLiveWithCat(name: "Today Sports"),
            makeLiveWithCat(name: "Sports Tonight"),
        ]
        let sorted = CatalogTextSearch.sortLiveByRelevance(items, search: "sports")
        #expect(sorted.first?.stream.name == "Sports Tonight")
    }

    // MARK: - sortVODByRelevance

    @Test
    func sortVODPrioritizesExactMatch() {
        let items = [
            makeVODWithCat(name: "Echoes of Tomorrow"),
            makeVODWithCat(name: "Echo"),
            makeVODWithCat(name: "Echo Chamber"),
        ]
        let sorted = CatalogTextSearch.sortVODByRelevance(items, search: "echo")
        #expect(sorted.first?.stream.name == "Echo")
    }

    // MARK: - sortSeriesByRelevance

    @Test
    func sortSeriesEmptySearchFollowsSortIndex() {
        let items = [
            makeSeriesWithCat(name: "B", sortIndex: 5),
            makeSeriesWithCat(name: "A", sortIndex: 1),
        ]
        let sorted = CatalogTextSearch.sortSeriesByRelevance(items, search: "")
        #expect(sorted.map(\.series.name) == ["A", "B"])
    }

    @Test
    func sortSeriesPrioritizesExactThenPrefix() {
        let items = [
            makeSeriesWithCat(name: "Lost in Space"),
            makeSeriesWithCat(name: "The Lost Room"),
            makeSeriesWithCat(name: "LOST"),
            makeSeriesWithCat(name: "Lost Girl"),
        ]
        let sorted = CatalogTextSearch.sortSeriesByRelevance(items, search: " lost ")
        #expect(sorted.map(\.series.name) == ["LOST", "Lost Girl", "Lost in Space", "The Lost Room"])
    }

    // MARK: - Relevance sorts keep their order

    /// The comparator the relevance sorts used when they still folded both names inside
    /// every comparison. The order it gives is the contract of the sorts.
    private func previousOrder(_ names: [String], search: String) -> [String] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        return names.sorted { n1, n2 in
            let e1 = CatalogTextSearch.equals(search: trimmed, text: n1), e2 = CatalogTextSearch.equals(search: trimmed, text: n2)
            if e1 != e2 { return e1 && !e2 }
            let s1 = CatalogTextSearch.startsWith(search: trimmed, text: n1), s2 = CatalogTextSearch.startsWith(search: trimmed, text: n2)
            if s1 != s2 { return s1 && !s2 }
            return n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
        }
    }

    private let relevanceFixture = [
        "Today Sports", "Sports Tonight", "SPORTS", "beIN Sports 1", "Sports News", "sports!",
        "Motorsports", "Fox TV", "FOX-TV", "Fox TV Extra", "My Fox TV", "IŞIK TV", "Işık Spor",
        "Zeta", "Alpha", "Ёлка", "ＦＯＸ ４Ｋ", "Spor", "Sport 1", "",
    ]

    @Test
    func relevanceSortsKeepThePreviousOrder() {
        for search in ["sports", "fox tv", "spor", "isik", "tv", "zzz", "--", " sport 1 "] {
            let expected = previousOrder(relevanceFixture, search: search)
            let live = CatalogTextSearch.sortLiveByRelevance(relevanceFixture.map { makeLiveWithCat(name: $0) }, search: search)
            let vod = CatalogTextSearch.sortVODByRelevance(relevanceFixture.map { makeVODWithCat(name: $0) }, search: search)
            let series = CatalogTextSearch.sortSeriesByRelevance(relevanceFixture.map { makeSeriesWithCat(name: $0) }, search: search)
            // A sort never drops a row, whether it matches the search or not.
            #expect(live.map(\.stream.name) == expected)
            #expect(vod.map(\.stream.name) == expected)
            #expect(series.map(\.series.name) == expected)
        }
    }

    @Test
    func rankedFilterAgreesWithFilterThenRelevanceSort() {
        let live = relevanceFixture.map { makeLiveWithCat(name: $0) }
        let vod = relevanceFixture.map { makeVODWithCat(name: $0) }
        let series = relevanceFixture.map { makeSeriesWithCat(name: $0) }
        for search in ["sports", "fox tv", "spor", "isik", "tv", "zzz", "--", "tv fox"] {
            let rankedLive = CatalogTextSearch.rankedFilter(live, search: search) { $0.stream.name }
            let sortedLive = CatalogTextSearch.sortLiveByRelevance(
                live.filter { CatalogTextSearch.matches(search: search, text: $0.stream.name) }, search: search)
            #expect(rankedLive == sortedLive)

            let rankedVOD = CatalogTextSearch.rankedFilter(vod, search: search) { $0.stream.name }
            let sortedVOD = CatalogTextSearch.sortVODByRelevance(
                vod.filter { CatalogTextSearch.matches(search: search, text: $0.stream.name) }, search: search)
            #expect(rankedVOD == sortedVOD)

            let rankedSeries = CatalogTextSearch.rankedFilter(series, search: search) { $0.series.name }
            let sortedSeries = CatalogTextSearch.sortSeriesByRelevance(
                series.filter { CatalogTextSearch.matches(search: search, text: $0.series.name) }, search: search)
            #expect(rankedSeries == sortedSeries)
        }
    }

    // MARK: - Helpers

    private let playlistId = UUID()

    private func makeLiveWithCat(name: String, sortIndex: Int = 0) -> LiveStreamWithCategory {
        LiveStreamWithCategory(
            stream: DBLiveStream(
                streamId: name.hashValue,
                name: name,
                streamIcon: nil,
                epgChannelId: nil,
                categoryId: nil,
                sortIndex: sortIndex,
                playlistId: playlistId
            ),
            categoryName: "Cat"
        )
    }

    private func makeVODWithCat(name: String, sortIndex: Int = 0) -> VODWithCategory {
        VODWithCategory(
            stream: DBVODStream(
                streamId: name.hashValue,
                name: name,
                streamIcon: nil,
                categoryId: nil,
                rating: nil,
                containerExtension: nil,
                sortIndex: sortIndex,
                playlistId: playlistId
            ),
            categoryName: "Cat"
        )
    }

    private func makeSeriesWithCat(name: String, sortIndex: Int = 0) -> SeriesWithCategory {
        SeriesWithCategory(
            series: DBSeries(
                seriesId: name.hashValue,
                name: name,
                cover: nil,
                categoryId: nil,
                sortIndex: sortIndex,
                playlistId: playlistId
            ),
            categoryName: "Cat"
        )
    }
}
