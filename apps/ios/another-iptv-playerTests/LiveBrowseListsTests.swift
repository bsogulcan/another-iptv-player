import Foundation
import Testing
@testable import another_iptv_player

@Suite("Live browse lists")
struct LiveBrowseListsTests {
    private let playlistId = UUID()

    private func category(_ id: String, _ name: String, sortIndex: Int = 0) -> DBCategory {
        DBCategory(id: id, name: name, parentId: nil, type: "live", sortIndex: sortIndex, playlistId: playlistId)
    }

    private func channel(
        _ id: Int,
        _ name: String,
        category: String? = "1",
        archive: Int = 0,
        epg: String? = nil
    ) -> LiveStreamWithCategory {
        LiveStreamWithCategory(
            stream: DBLiveStream(
                streamId: id, name: name, streamIcon: nil, epgChannelId: epg,
                categoryId: category, sortIndex: id, playlistId: playlistId,
                tvArchive: archive, tvArchiveDuration: archive > 0 ? 3 : 0
            ),
            categoryName: "Category \(category ?? "-")"
        )
    }

    private func names(_ items: [LiveStreamWithCategory]) -> [String] {
        items.map(\.stream.name)
    }

    // MARK: - Home shelves for a search

    private var news: DBCategory { category("1", "News", sortIndex: 0) }
    private var sports: DBCategory { category("2", "Sports", sortIndex: 1) }
    private var kids: DBCategory { category("3", "Kids", sortIndex: 2) }

    private var catalog: [String: [LiveStreamWithCategory]] {
        [
            "1": [channel(1, "World News 24"), channel(2, "Sports Tonight"), channel(3, "Weather")],
            "2": [channel(4, "Arena One", category: "2"), channel(5, "Goal TV", category: "2")],
            "3": [channel(6, "Cartoon Sports Club", category: "3"), channel(7, "Toons", category: "3")],
        ]
    }

    private func shelves(_ search: String, hidden: Set<String> = []) -> LiveBrowseLists.Shelves {
        LiveBrowseLists.shelves(
            matching: search, categories: [news, sports, kids], itemsByCategory: catalog, hidden: hidden
        )
    }

    @Test
    func categoryFoundByItsNameKeepsAllItsChannels() {
        let result = shelves("sports")
        #expect(names(result.itemsByCategory["2"] ?? []) == ["Arena One", "Goal TV"])
    }

    @Test
    func otherCategoriesKeepOnlyTheChannelsThatMatch() {
        let result = shelves("sports")
        #expect(names(result.itemsByCategory["1"] ?? []) == ["Sports Tonight"])
        #expect(names(result.itemsByCategory["3"] ?? []) == ["Cartoon Sports Club"])
    }

    @Test
    func categoryWithoutAMatchIsLeftOut() {
        let result = shelves("goal")
        #expect(result.categories.map(\.id) == ["2"])
        #expect(result.itemsByCategory.keys.sorted() == ["2"])
    }

    @Test
    func shelvesStayInCatalogOrder() {
        #expect(shelves("sports").categories.map(\.id) == ["1", "2", "3"])
    }

    @Test
    func hiddenCategoryIsLeftOutEvenWhenItMatches() {
        let result = shelves("sports", hidden: ["2"])
        #expect(result.categories.map(\.id) == ["1", "3"])
        #expect(result.itemsByCategory["2"] == nil)
    }

    @Test
    func searchFoldsCaseAccentsAndPunctuation() {
        #expect(shelves("WORLD-news").categories.map(\.id) == ["1"])
    }

    @Test
    func searchWithoutALetterOrDigitFindsNothing() {
        let result = shelves("--")
        #expect(result.categories.isEmpty)
        #expect(result.itemsByCategory.isEmpty)
    }

    // MARK: - All Channels

    private var allChannels: [LiveStreamWithCategory] {
        [
            channel(1, "Today Sports", category: "1"),
            channel(2, "Sports", category: "2"),
            channel(3, "Movies One", category: "3"),
            channel(4, "Sports News", category: "2"),
            channel(5, "Orphan", category: nil),
        ]
    }

    @Test
    func withoutHiddenCategoriesOrSearchItIsTheCatalogInOrder() {
        let source = allChannels
        let result = LiveBrowseLists.allChannels(source, hidden: [], search: "")
        #expect(result.items == source)
        #expect(result.streams == source.map(\.stream))
    }

    @Test
    func channelsOfHiddenCategoriesAreLeftOut() {
        let result = LiveBrowseLists.allChannels(allChannels, hidden: ["2"], search: "")
        #expect(result.streams.map(\.streamId) == [1, 3, 5])
    }

    @Test
    func searchRanksExactThenPrefixThenTheRest() {
        let result = LiveBrowseLists.allChannels(allChannels, hidden: [], search: "sports")
        #expect(names(result.items) == ["Sports", "Sports News", "Today Sports"])
    }

    @Test
    func searchRunsOnWhatIsLeftAfterHiding() {
        let result = LiveBrowseLists.allChannels(allChannels, hidden: ["2"], search: "sports")
        #expect(names(result.items) == ["Today Sports"])
    }

    @Test
    func streamsFollowTheItemsOneToOne() {
        let result = LiveBrowseLists.allChannels(allChannels, hidden: ["3"], search: "s")
        #expect(result.streams == result.items.map(\.stream))
        #expect(!result.items.isEmpty)
    }

    // MARK: - A grid's own sort and filter

    private var grid: [LiveStreamWithCategory] {
        [
            channel(1, "Delta", archive: 1, epg: "delta.tv"),
            channel(2, "alpha", epg: ""),
            channel(3, "Charlie", archive: 1),
            channel(4, "Bravo", epg: "bravo.tv"),
        ]
    }

    @Test
    func defaultOrderWithoutAFilterKeepsTheList() {
        let source = grid
        let result = LiveBrowseLists.arranged(source, sort: .defaultOrder, filter: [])
        #expect(result.items == source)
        #expect(result.streams == source.map(\.stream))
    }

    @Test
    func nameSortIgnoresCaseAndTheQueueFollowsIt() {
        let ascending = LiveBrowseLists.arranged(grid, sort: .nameAsc, filter: [])
        #expect(names(ascending.items) == ["alpha", "Bravo", "Charlie", "Delta"])
        #expect(ascending.streams.map(\.streamId) == [2, 4, 3, 1])

        let descending = LiveBrowseLists.arranged(grid, sort: .nameDesc, filter: [])
        #expect(descending.streams.map(\.streamId) == [1, 3, 4, 2])
    }

    @Test
    func catchupFilterKeepsOnlyChannelsWithAnArchive() {
        let result = LiveBrowseLists.arranged(grid, sort: .defaultOrder, filter: .catchup)
        #expect(result.streams.map(\.streamId) == [1, 3])
    }

    @Test
    func guideFilterKeepsOnlyChannelsWithAGuideId() {
        let result = LiveBrowseLists.arranged(grid, sort: .defaultOrder, filter: .hasEPG)
        #expect(result.streams.map(\.streamId) == [1, 4])
    }

    @Test
    func filtersCombineAndTheSortRunsOnTheirResult() {
        let both = LiveBrowseLists.arranged(grid, sort: .nameAsc, filter: [.catchup, .hasEPG])
        #expect(both.streams.map(\.streamId) == [1])

        let sorted = LiveBrowseLists.arranged(grid, sort: .nameAsc, filter: .catchup)
        #expect(names(sorted.items) == ["Charlie", "Delta"])
    }

    @Test
    func filterThatRemovesEverythingGivesAnEmptyQueue() {
        let result = LiveBrowseLists.arranged([channel(2, "alpha")], sort: .nameAsc, filter: .catchup)
        #expect(result.items.isEmpty)
        #expect(result.streams.isEmpty)
    }

    // MARK: - Cancellation

    /// A run whose task was cancelled must not hand back a list: its caller is gone or
    /// has moved on, and a half-built list must never be mistaken for the answer.
    @Test
    func cancelledRunsReturnNothing() async {
        let source = grid
        let counts = await Task.detached { () -> [Int] in
            withUnsafeCurrentTask { $0?.cancel() }
            let arranged = LiveBrowseLists.arranged(source, sort: .nameAsc, filter: [])
            let all = LiveBrowseLists.allChannels(source, hidden: [], search: "a")
            return [arranged.items.count, arranged.streams.count, all.items.count, all.streams.count]
        }.value
        #expect(counts == [0, 0, 0, 0])
    }

    @Test
    func cancelledShelfSearchStopsBeforeTheFirstCategory() async {
        let categories = [news, sports, kids]
        let items = catalog
        let found = await Task.detached { () -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            return LiveBrowseLists.shelves(
                matching: "sports", categories: categories, itemsByCategory: items, hidden: []
            ).categories.count
        }.value
        #expect(found == 0)
    }
}
