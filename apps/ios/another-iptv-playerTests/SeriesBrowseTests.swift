import Foundation
import Testing
@testable import another_iptv_player

@Suite("Series browse logic")
struct SeriesBrowseTests {
    private let playlist = PlaylistCatalogFixture.playlist()

    private func series(_ id: Int, category: String?, lastModified: String? = nil, name: String? = nil) -> DBSeries {
        var row = PlaylistCatalogFixture.series(id, category: category, lastModified: lastModified, in: playlist)
        if let name { row.name = name }
        return row
    }

    private func item(_ id: Int, category: String?, lastModified: String? = nil, name: String? = nil) -> SeriesWithCategory {
        SeriesWithCategory(
            series: series(id, category: category, lastModified: lastModified, name: name),
            categoryName: category ?? ""
        )
    }

    private func category(_ id: String, name: String) -> DBCategory {
        DBCategory(id: id, name: name, parentId: nil, type: "series", sortIndex: 0, playlistId: playlist.id)
    }

    // MARK: - Recently Added from the store's candidates

    @Test
    func recentShelfKeepsCandidateOrderAndDropsHiddenCategories() {
        let candidates = [
            series(1, category: "a"), series(2, category: "hidden"), series(3, category: "b"),
            series(4, category: nil), series(5, category: "a"),
        ]
        let shelf = SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: ["a", "b"])
        #expect(shelf.map(\.seriesId) == [1, 3, 5])
    }

    @Test
    func recentShelfStopsAtTheLimit() {
        let candidates = (1...50).map { series($0, category: "a") }
        #expect(SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: ["a"]).map(\.seriesId) == Array(1...20))
        #expect(SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: ["a"], limit: 3).map(\.seriesId) == [1, 2, 3])
        #expect(SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: ["a"], limit: 0).isEmpty)
        #expect(SeriesBrowse.recentShelf(from: [], visibleCategoryIds: ["a"]).isEmpty)
        #expect(SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: []).isEmpty)
    }

    @Test
    func catalogPassIsNeededOnlyForAShortShelfFromAFullCandidateList() {
        let full = PlaylistContentStore.recentCandidateLimit
        // A full shelf never needs it.
        #expect(!SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: 20, candidateCount: full))
        // A short shelf from a list that was not cut off is simply all there is.
        #expect(!SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: 5, candidateCount: full - 1))
        #expect(!SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: 0, candidateCount: 0))
        // A short shelf from a full list: hidden categories pushed visible series out.
        #expect(SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: 19, candidateCount: full))
        #expect(SeriesBrowse.recentShelfNeedsCatalogPass(shelfCount: 0, candidateCount: full))
    }

    // MARK: - Recently Added from the whole catalog

    /// The definition the catalog pass has to meet, written the obvious way.
    private func referenceRecents(_ items: [SeriesWithCategory], visible: Set<String>, limit: Int) -> [Int] {
        let dated = items.enumerated().compactMap { offset, item -> (offset: Int, stamp: Int, id: Int)? in
            guard visible.contains(item.series.categoryId ?? "") else { return nil }
            guard let stamp = item.series.lastModified.flatMap({ Int($0) }) else { return nil }
            return (offset, stamp, item.series.seriesId)
        }
        let sorted = dated.sorted { $0.stamp != $1.stamp ? $0.stamp > $1.stamp : $0.offset < $1.offset }
        return sorted.prefix(limit).map(\.id)
    }

    @Test
    func catalogPassFindsTheNewestVisibleSeries() {
        var items: [SeriesWithCategory] = []
        // The newest 300 are all in a hidden category.
        for id in 0..<300 { items.append(item(id, category: "hidden", lastModified: String(9_000 + id))) }
        // Older ones in visible categories, with duplicate and unusable timestamps.
        for id in 300..<400 {
            let stamp: String?
            switch id % 5 {
            case 0: stamp = nil
            case 1: stamp = "soon"
            case 2: stamp = "1500"
            default: stamp = String(1_000 + id)
            }
            items.append(item(id, category: id % 2 == 0 ? "a" : "b", lastModified: stamp))
        }
        // No category of its own, and one the playlist does not list.
        items.append(item(400, category: nil, lastModified: "99999"))
        items.append(item(401, category: "gone", lastModified: "99998"))

        let visible: Set<String> = ["a", "b"]
        let result = SeriesBrowse.recentShelfFromCatalog(items, visibleCategoryIds: visible)
        #expect(result.count == 20)
        #expect(result.map(\.seriesId) == referenceRecents(items, visible: visible, limit: 20))
        #expect(result.allSatisfy { visible.contains($0.categoryId ?? "") })

        let onlyA = SeriesBrowse.recentShelfFromCatalog(items, visibleCategoryIds: ["a"], limit: 7)
        #expect(onlyA.map(\.seriesId) == referenceRecents(items, visible: ["a"], limit: 7))
    }

    @Test
    func catalogPassAgreesWithTheCandidatesWhenNothingWasCutOff() {
        // What the store publishes: every dated series of a listed category, newest first.
        let items = (0..<120).map { item($0, category: $0 % 3 == 0 ? "hidden" : "a", lastModified: String(($0 * 37) % 101)) }
        let listed: Set<String> = ["a", "hidden"]
        let newest = PlaylistContentStore.newestIndices(
            count: items.count, limit: PlaylistContentStore.recentCandidateLimit
        ) { index in
            listed.contains(items[index].series.categoryId ?? "") ? items[index].series.lastModified.flatMap { Int($0) } : nil
        }
        let candidates = newest.map { items[$0].series }

        let fromCandidates = SeriesBrowse.recentShelf(from: candidates, visibleCategoryIds: ["a"])
        let fromCatalog = SeriesBrowse.recentShelfFromCatalog(items, visibleCategoryIds: ["a"])
        #expect(fromCandidates.map(\.seriesId) == fromCatalog.map(\.seriesId))
        #expect(fromCandidates.count == 20)
    }

    @Test
    func catalogPassOfAnEmptyOrUndatedCatalogIsEmpty() {
        #expect(SeriesBrowse.recentShelfFromCatalog([], visibleCategoryIds: ["a"]).isEmpty)
        let undated = (0..<10).map { item($0, category: "a") }
        #expect(SeriesBrowse.recentShelfFromCatalog(undated, visibleCategoryIds: ["a"]).isEmpty)
    }

    // MARK: - Shelves for a search

    private var drama: DBCategory { category("d", name: "Drama") }
    private var comedy: DBCategory { category("c", name: "Comedy Night") }
    private var empty: DBCategory { category("e", name: "Documentaries") }

    private var catalog: [String: [SeriesWithCategory]] {
        [
            "d": [item(1, category: "d", name: "Northern Lights"), item(2, category: "d", name: "Night Shift")],
            "c": [item(3, category: "c", name: "Office Hours"), item(4, category: "c", name: "Late Night Lights")],
        ]
    }

    private func shelves(_ search: String) -> SeriesBrowse.ShelfMatches? {
        SeriesBrowse.shelves(matching: search, categories: [drama, comedy, empty], itemsByCategory: catalog)
    }

    @Test
    func aMatchingSeriesKeepsItsCategoryWithTheHitsOnly() throws {
        let result = try #require(shelves("lights"))
        #expect(result.categories.map(\.id) == ["d", "c"])
        #expect(result.itemsByCategory["d"]?.map(\.series.seriesId) == [1])
        #expect(result.itemsByCategory["c"]?.map(\.series.seriesId) == [4])
    }

    @Test
    func aMatchingCategoryNameKeepsAllItsSeries() throws {
        // "Night" is in the name of one category and in a title of the other.
        let result = try #require(shelves("night"))
        #expect(result.categories.map(\.id) == ["d", "c"])
        #expect(result.itemsByCategory["d"]?.map(\.series.seriesId) == [2])
        #expect(result.itemsByCategory["c"]?.map(\.series.seriesId) == [3, 4])
    }

    @Test
    func aMatchingCategoryWithoutSeriesIsKept() throws {
        let result = try #require(shelves("documentaries"))
        #expect(result.categories.map(\.id) == ["e"])
        #expect(result.itemsByCategory["e"]?.isEmpty == true)
    }

    @Test
    func theSearchFoldsCaseAccentsAndPunctuation() throws {
        let result = try #require(shelves("NÖRTHERN-lights"))
        #expect(result.categories.map(\.id) == ["d"])
        #expect(result.itemsByCategory["d"]?.map(\.series.seriesId) == [1])
    }

    @Test
    func nothingMatchesASearchWithoutLettersOrDigits() throws {
        let result = try #require(shelves("--"))
        #expect(result.categories.isEmpty)
        #expect(result.itemsByCategory.isEmpty)
    }

    @Test
    func aSearchWithoutHitsIsEmpty() throws {
        let result = try #require(shelves("zebra"))
        #expect(result.categories.isEmpty)
    }

    @Test
    func aCancelledSearchReturnsNothingInsteadOfAnEmptyResult() async {
        let categories = [drama, comedy, empty]
        let catalog = self.catalog
        let wasAbandoned = await Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return SeriesBrowse.shelves(matching: "lights", categories: categories, itemsByCategory: catalog) == nil
        }.value
        #expect(wasAbandoned)
    }
}

@Suite("Series shelf prefetch")
struct SeriesShelfPrefetchTests {
    private func url(_ name: String) -> URL { URL(string: "https://img.example/\(name).jpg")! }

    private func head(_ names: [String], width: CGFloat = 120, height: CGFloat = 180) -> SeriesBrowse.HeadPrefetch {
        SeriesBrowse.HeadPrefetch(urls: names.map(url), width: width, height: height)
    }

    @Test
    func appearingStartsTheWholeHead() {
        let change = SeriesBrowse.prefetchChange(from: nil, to: head(["a", "b"]))
        #expect(change.stop == nil)
        #expect(change.start == head(["a", "b"]))
    }

    @Test
    func disappearingStopsWhatWasStartedNotTheCurrentItems() {
        // Started with the full shelf; a search has since narrowed it to one hit.
        let started = head(["a", "b", "c"])
        let change = SeriesBrowse.prefetchChange(from: started, to: nil)
        #expect(change.stop == started)
        #expect(change.start == nil)
    }

    @Test
    func aNarrowedShelfStopsOnlyTheCoversItLost() {
        let change = SeriesBrowse.prefetchChange(from: head(["a", "b", "c"]), to: head(["b"]))
        #expect(change.stop == head(["a", "c"]))
        #expect(change.start == nil)
    }

    @Test
    func aChangedHeadStopsTheOldCoversAndStartsTheNewOnes() {
        let change = SeriesBrowse.prefetchChange(from: head(["a", "b"]), to: head(["b", "c"]))
        #expect(change.stop == head(["a"]))
        #expect(change.start == head(["c"]))
    }

    @Test
    func aSizeChangeRebuildsEveryRequest() {
        let old = head(["a", "b"])
        let new = head(["a", "b"], width: 150, height: 225)
        let change = SeriesBrowse.prefetchChange(from: old, to: new)
        #expect(change.stop == old)
        #expect(change.start == new)
    }

    @Test
    func anUnchangedHeadDoesNothing() {
        let change = SeriesBrowse.prefetchChange(from: head(["a"]), to: head(["a"]))
        #expect(change.stop == nil)
        #expect(change.start == nil)
    }
}
