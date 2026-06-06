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
        // "İstanbul" lower-folded with Turkish locale becomes "istanbul"
        #expect(CatalogTextSearch.matches(search: "istanbul", text: "İSTANBUL HABER") == true)
        #expect(CatalogTextSearch.matches(search: "sehir", text: "Şehir TV") == true)
        #expect(CatalogTextSearch.matches(search: "video", text: "VİDEO PLUS") == true)
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
