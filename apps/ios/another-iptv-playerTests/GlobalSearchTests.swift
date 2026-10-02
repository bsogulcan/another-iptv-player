import Foundation
import Testing
@testable import another_iptv_player

@Suite("Global search")
struct GlobalSearchTests {

    // MARK: - Matching and order

    @Test
    func ranksEveryTypeExactThenPrefixThenTheRest() async {
        let names = ["Acrobat", "EN - Batman", "Combat Zone", "Batman Begins", "Bat", "News"]
        let hits = await search("bat", in: catalog(live: names, movies: names, series: names))

        let expected = ["Bat", "Batman Begins", "Acrobat", "Combat Zone", "EN - Batman"]
        #expect(hits.live.map(\.stream.name) == expected)
        #expect(hits.movies.map(\.stream.name) == expected)
        #expect(hits.series.map(\.series.name) == expected)
    }

    @Test
    func findsNamesWhateverTheirCaseAccentsOrPunctuation() async {
        let items = catalog(
            live: ["BEIN SPORTS 1", "IŞIK TV", "FİLM 4K"],
            movies: ["Spider-Man", "Amélie", "Inception"],
            series: ["Şehir", "HISTORY HD"]
        )

        #expect(await search("bein", in: items).live.map(\.stream.name) == ["BEIN SPORTS 1"])
        #expect(await search("isik", in: items).live.map(\.stream.name) == ["IŞIK TV"])
        #expect(await search("film", in: items).live.map(\.stream.name) == ["FİLM 4K"])
        #expect(await search("spiderman", in: items).movies.map(\.stream.name) == ["Spider-Man"])
        #expect(await search("amelie", in: items).movies.map(\.stream.name) == ["Amélie"])
        #expect(await search("inception", in: items).movies.map(\.stream.name) == ["Inception"])
        #expect(await search("sehir", in: items).series.map(\.series.name) == ["Şehir"])
        #expect(await search("history", in: items).series.map(\.series.name) == ["HISTORY HD"])
    }

    @Test
    func everyWordOfTheQueryHasToMatch() async {
        let items = catalog(live: ["World News 24", "World Sport", "News Night"])
        let hits = await search("world news", in: items)
        #expect(hits.live.map(\.stream.name) == ["World News 24"])
    }

    @Test
    func aTypeWithoutHitsComesBackEmpty() async {
        let items = catalog(live: ["World News 24"], movies: ["Midnight Horizon"], series: ["Family Ties"])
        let hits = await search("midnight", in: items)
        #expect(hits.live.isEmpty)
        #expect(hits.movies.map(\.stream.name) == ["Midnight Horizon"])
        #expect(hits.series.isEmpty)
    }

    // MARK: - Hidden categories

    @Test
    func leavesOutHiddenCategoriesOfEachTypeOnly() async {
        // The same category id in all three types, hidden for movies alone.
        let items = GlobalSearch.Items(
            live: [live("Star One", category: "7"), live("Star Two", category: "8")],
            movies: [movie("Star Wars", category: "7"), movie("Star Trek", category: "8")],
            series: [series("Stargate", category: "7"), series("Starman", category: "8")]
        )
        let hits = await GlobalSearch.hits(
            for: "star",
            in: items,
            hidden: GlobalSearch.HiddenCategories(movies: ["7"])
        )

        #expect(hits.live.map(\.stream.name) == ["Star One", "Star Two"])
        #expect(hits.movies.map(\.stream.name) == ["Star Trek"])
        #expect(hits.series.map(\.series.name) == ["Stargate", "Starman"])
    }

    @Test
    func aHiddenCategoryNeverOutranksAVisibleOne() async {
        // The exact match is hidden; the visible hits keep their own order.
        let items = GlobalSearch.Items(movies: [
            movie("Alien Covenant", category: "1"),
            movie("Alien", category: "2"),
            movie("Aliens", category: "1"),
        ])
        let hits = await GlobalSearch.hits(
            for: "alien",
            in: items,
            hidden: GlobalSearch.HiddenCategories(movies: ["2"])
        )
        #expect(hits.movies.map(\.stream.name) == ["Alien Covenant", "Aliens"])
    }

    @Test
    func anItemWithoutCategoryIsHiddenWithTheEmptyId() async {
        let items = GlobalSearch.Items(live: [live("Loose Channel", category: nil), live("Listed Channel", category: "3")])

        let shown = await GlobalSearch.hits(for: "channel", in: items, hidden: GlobalSearch.HiddenCategories(live: ["9"]))
        #expect(shown.live.map(\.stream.name) == ["Listed Channel", "Loose Channel"])

        let hidden = await GlobalSearch.hits(for: "channel", in: items, hidden: GlobalSearch.HiddenCategories(live: [""]))
        #expect(hidden.live.map(\.stream.name) == ["Listed Channel"])
    }

    // MARK: - Queries without a word

    @Test(arguments: ["--", "!!", "  ", "\n", ""])
    func textWithoutALetterOrDigitFindsNothing(query: String) async {
        // Neither the whole catalog (a blank filter) nor a hidden category may come back.
        let items = catalog(live: ["World News 24"], movies: ["Midnight Horizon"], series: ["Family Ties"])
        let hits = await search(query, in: items)
        #expect(hits.live.isEmpty)
        #expect(hits.movies.isEmpty)
        #expect(hits.series.isEmpty)
    }

    // MARK: - Cancellation

    @Test
    func aCancelledSearchReturnsNothing() async {
        // Long enough that the scans are still running when the cancellation reaches them.
        let names = (0..<5_000).map { "Sports \($0)" }
        let items = catalog(live: names, movies: names, series: names)
        let hits = await Task { () -> GlobalSearch.Items in
            withUnsafeCurrentTask { $0?.cancel() }
            return await GlobalSearch.hits(for: "sports", in: items, hidden: GlobalSearch.HiddenCategories())
        }.value
        #expect(hits.live.isEmpty)
        #expect(hits.movies.isEmpty)
        #expect(hits.series.isEmpty)
    }

    // MARK: - Helpers

    private let playlistId = UUID()

    private func search(_ query: String, in items: GlobalSearch.Items) async -> GlobalSearch.Items {
        await GlobalSearch.hits(for: query, in: items, hidden: GlobalSearch.HiddenCategories())
    }

    private func catalog(live: [String] = [], movies: [String] = [], series: [String] = []) -> GlobalSearch.Items {
        GlobalSearch.Items(
            live: live.map { self.live($0, category: "1") },
            movies: movies.map { self.movie($0, category: "1") },
            series: series.map { self.series($0, category: "1") }
        )
    }

    private func live(_ name: String, category: String?) -> LiveStreamWithCategory {
        LiveStreamWithCategory(
            stream: DBLiveStream(
                streamId: name.hashValue,
                name: name,
                streamIcon: nil,
                epgChannelId: nil,
                categoryId: category,
                playlistId: playlistId
            ),
            categoryName: "Cat"
        )
    }

    private func movie(_ name: String, category: String?) -> VODWithCategory {
        VODWithCategory(
            stream: DBVODStream(
                streamId: name.hashValue,
                name: name,
                streamIcon: nil,
                categoryId: category,
                rating: nil,
                containerExtension: nil,
                playlistId: playlistId
            ),
            categoryName: "Cat"
        )
    }

    private func series(_ name: String, category: String?) -> SeriesWithCategory {
        SeriesWithCategory(
            series: DBSeries(
                seriesId: name.hashValue,
                name: name,
                cover: nil,
                categoryId: category,
                playlistId: playlistId
            ),
            categoryName: "Cat"
        )
    }
}
