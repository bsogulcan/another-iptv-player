import Foundation
import Testing
@testable import another_iptv_player

/// The parts of the Movies browse screens that are plain functions: the shelf search,
/// the "recently added" shelf and the play queue of a film opened from the history.
@MainActor
@Suite("Movies browse logic")
struct VODBrowseLogicTests {
    private let playlist = PlaylistCatalogFixture.playlist()

    private func category(_ id: String, _ name: String) -> DBCategory {
        var row = PlaylistCatalogFixture.category(id, type: "vod", in: playlist)
        row.name = name
        return row
    }

    private func movie(_ id: Int, _ name: String? = nil, category: String?, added: String? = nil) -> VODWithCategory {
        var stream = PlaylistCatalogFixture.vod(id, category: category, added: added, in: playlist)
        if let name { stream.name = name }
        return VODWithCategory(stream: stream, categoryName: "")
    }

    private func ids(_ items: [VODWithCategory]?) -> [Int]? {
        items?.map(\.stream.streamId)
    }

    // MARK: - Home status

    /// The store as it is once a catalog is fully loaded; each test changes what it is about.
    private func status(
        isActivePlaylist: Bool = true,
        isLoading: Bool = false,
        loadError: String? = nil,
        streamsLoaded: Bool = true,
        hasItems: Bool = true,
        hasVisibleCategories: Bool = true
    ) -> VODHomeStatus {
        VODHomeStatus.resolve(
            isActivePlaylist: isActivePlaylist,
            isLoading: isLoading,
            loadError: loadError,
            streamsLoaded: streamsLoaded,
            hasItems: hasItems,
            hasVisibleCategories: hasVisibleCategories
        )
    }

    @Test
    func aPlaylistThatIsStillOpeningIsPreparing() {
        #expect(status(isActivePlaylist: false) == .preparing)
        #expect(status(isLoading: true, streamsLoaded: false, hasItems: false, hasVisibleCategories: false) == .preparing)
    }

    @Test
    func categoriesWithoutMoviesYetAreLoadingShelvesNotAnEmptyCatalog() {
        // Between the two steps of a load: the categories are in, the movies are not.
        #expect(status(streamsLoaded: false, hasItems: false) == .shelves(isStreamsLoading: true))
        // No category yet either: the movies can still bring the "uncategorized" one.
        #expect(status(streamsLoaded: false, hasItems: false, hasVisibleCategories: false) == .preparing)
    }

    @Test
    func aLoadedCatalogShowsItsShelves() {
        #expect(status() == .shelves(isStreamsLoading: false))
        // Categories and no movie at all: every shelf says so, none of them is loading.
        #expect(status(hasItems: false) == .shelves(isStreamsLoading: false))
    }

    @Test
    func aReloadKeepsTheShelvesOfTheOldLists() {
        #expect(status(streamsLoaded: false, hasItems: true) == .shelves(isStreamsLoading: false))
        #expect(status(isLoading: true, streamsLoaded: false, hasItems: true) == .shelves(isStreamsLoading: false))
    }

    @Test
    func noCategoryNeedsALoadedCatalogWithoutVisibleCategories() {
        #expect(status(hasVisibleCategories: false) == .noCategory)
        #expect(status(hasItems: false, hasVisibleCategories: false) == .noCategory)
    }

    @Test
    func aLoadErrorReplacesTheShelvesOnlyWhenTheyHaveNoContent() {
        // The first download failed: nothing was ever loaded.
        #expect(status(loadError: "x", streamsLoaded: false, hasItems: false, hasVisibleCategories: false) == .failed("x"))
        // The categories came in and reading the movies failed.
        #expect(status(loadError: "x", streamsLoaded: false, hasItems: false) == .failed("x"))
        // A reload failed: the catalog that was on screen is still complete.
        #expect(status(loadError: "x") == .shelves(isStreamsLoading: false))
        #expect(status(loadError: "x", hasVisibleCategories: false) == .failed("x"))
        // A retry is running: its progress, not the previous error.
        #expect(status(isLoading: true, loadError: "x", streamsLoaded: false, hasItems: false, hasVisibleCategories: false) == .preparing)
    }

    // MARK: - Shelf search

    private var shelfCategories: [DBCategory] {
        [category("1", "Action"), category("2", "Drama"), category("3", "Kids"), category("4", "Action Classics")]
    }

    private var shelfItems: [String: [VODWithCategory]] {
        [
            "1": [movie(10, "Midnight Horizon", category: "1"), movie(11, "Steel Rain", category: "1")],
            "2": [movie(20, "Quiet Days", category: "2"), movie(21, "Horizon Line", category: "2")],
            "3": [movie(30, "Paper Boats", category: "3")],
            // "4" has no bucket: an empty category.
        ]
    }

    @Test
    func aNameHitKeepsOnlyTheMatchingMoviesOfACategory() throws {
        let match = try #require(
            VODShelfSearch.shelves(matching: "horizon", categories: shelfCategories, itemsByCategory: shelfItems)
        )

        #expect(match.categories.map(\.id) == ["1", "2"])
        #expect(ids(match.itemsByCategory["1"]) == [10])
        #expect(ids(match.itemsByCategory["2"]) == [21])
        #expect(match.itemsByCategory["3"] == nil)
    }

    @Test
    func aCategoryWhoseNameMatchesStaysWhole() throws {
        let match = try #require(
            VODShelfSearch.shelves(matching: "action", categories: shelfCategories, itemsByCategory: shelfItems)
        )

        // Neither film of "Action" has the word in its name; the empty category is
        // listed too, as it is without a search.
        #expect(match.categories.map(\.id) == ["1", "4"])
        #expect(ids(match.itemsByCategory["1"]) == [10, 11])
        #expect(ids(match.itemsByCategory["4"]) == [])
    }

    @Test
    func theSearchFoldsCaseAccentsAndPunctuation() throws {
        var items = shelfItems
        items["3"] = [movie(30, "Amélie: The Return", category: "3")]

        let match = try #require(
            VODShelfSearch.shelves(matching: "AMELIE return", categories: shelfCategories, itemsByCategory: items)
        )

        #expect(match.categories.map(\.id) == ["3"])
        #expect(ids(match.itemsByCategory["3"]) == [30])
    }

    @Test
    func aSearchWithoutLettersOrDigitsMatchesNothing() throws {
        let match = try #require(
            VODShelfSearch.shelves(matching: "--", categories: shelfCategories, itemsByCategory: shelfItems)
        )

        #expect(match.categories.isEmpty)
        #expect(match.itemsByCategory.isEmpty)
    }

    @Test
    func aCategoryThatWasNotPassedInIsNotSearched() throws {
        // The caller leaves hidden categories out; their buckets are still in the map.
        let visible = shelfCategories.filter { $0.id != "2" }

        let match = try #require(
            VODShelfSearch.shelves(matching: "horizon", categories: visible, itemsByCategory: shelfItems)
        )

        #expect(match.categories.map(\.id) == ["1"])
        #expect(match.itemsByCategory["2"] == nil)
    }

    @Test
    func aCancelledShelfSearchReturnsNothing() async {
        let categories = shelfCategories
        let items = shelfItems
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return VODShelfSearch.shelves(matching: "horizon", categories: categories, itemsByCategory: items)
        }

        #expect(await task.value == nil)
    }

    // MARK: - Recently added

    private func candidates(_ count: Int, category: (Int) -> String) -> [DBVODStream] {
        (0..<count).map { index in
            PlaylistCatalogFixture.vod(index, category: category(index), added: String(10_000 - index), in: playlist)
        }
    }

    @Test
    func withNothingHiddenTheShelfIsTheHeadOfTheCandidates() {
        let all = candidates(25) { _ in "a" }

        let shelf = VODRecentlyAdded.shelfItems(from: all, hidden: [])

        #expect(shelf.map(\.streamId) == Array(0..<20))
    }

    @Test
    func hiddenCategoriesAreSkippedAndTheOrderIsKept() {
        let all = candidates(60) { $0.isMultiple(of: 2) ? "a" : "b" }

        let shelf = VODRecentlyAdded.shelfItems(from: all, hidden: ["a"])

        #expect(shelf.count == VODRecentlyAdded.shelfLimit)
        #expect(shelf.map(\.streamId) == (0..<20).map { $0 * 2 + 1 })
    }

    @Test
    func aShortShelfIsOnlyCutShortWhenTheCandidateListWasFull() {
        let limit = PlaylistContentStore.recentCandidateLimit

        // The store handed over everything it had: the shelf is complete as it is.
        #expect(!VODRecentlyAdded.isCutShort(shelfCount: 5, candidateCount: 50))
        #expect(!VODRecentlyAdded.isCutShort(shelfCount: 0, candidateCount: 0))
        // A full shelf needs nothing more, however many candidates there were.
        #expect(!VODRecentlyAdded.isCutShort(shelfCount: VODRecentlyAdded.shelfLimit, candidateCount: limit))
        // Hidden categories used up the list: older visible movies may exist.
        #expect(VODRecentlyAdded.isCutShort(shelfCount: 5, candidateCount: limit))
        #expect(VODRecentlyAdded.isCutShort(shelfCount: 0, candidateCount: limit))
    }

    /// A catalog whose 300 newest movies sit in one category, followed by older movies
    /// of another, with rows that must never reach the shelf mixed in.
    private var catalogWithBusyCategory: [VODWithCategory] {
        var streams: [VODWithCategory] = []
        for index in 0..<300 {
            streams.append(movie(index, category: "busy", added: String(50_000 - index)))
        }
        for index in 300..<340 {
            streams.append(movie(index, category: "quiet", added: String(20_000 - index)))
        }
        streams.append(movie(900, category: "quiet", added: nil))
        streams.append(movie(901, category: "quiet", added: "soon"))
        streams.append(movie(902, category: "unlisted", added: "99999"))
        streams.append(movie(903, category: nil, added: "99998"))
        return streams
    }

    @Test
    func theCatalogPassFindsWhatTheCandidatesCouldNotHold() {
        let streams = catalogWithBusyCategory
        let listed: Set<String> = ["busy", "quiet"]
        // What the store publishes for this catalog.
        let candidates = PlaylistContentStore.newestIndices(
            count: streams.count, limit: PlaylistContentStore.recentCandidateLimit
        ) { index in
            let stream = streams[index].stream
            guard PlaylistContentStore.isListed(stream.categoryId, in: listed) else { return nil }
            return stream.added.flatMap { Int($0) }
        }.map { streams[$0].stream }

        let shelf = VODRecentlyAdded.shelfItems(from: candidates, hidden: ["busy"])
        #expect(shelf.isEmpty)
        #expect(VODRecentlyAdded.isCutShort(shelfCount: shelf.count, candidateCount: candidates.count))

        let newest = VODRecentlyAdded.newest(in: streams, visibleCategoryIds: ["quiet"])
        #expect(newest.map(\.streamId) == Array(300..<320))
    }

    @Test
    func theCatalogPassAgreesWithTheCandidatesWhereBothApply() {
        let streams = catalogWithBusyCategory
        let listed: Set<String> = ["busy", "quiet"]
        let candidates = PlaylistContentStore.newestIndices(
            count: streams.count, limit: PlaylistContentStore.recentCandidateLimit
        ) { index in
            let stream = streams[index].stream
            guard PlaylistContentStore.isListed(stream.categoryId, in: listed) else { return nil }
            return stream.added.flatMap { Int($0) }
        }.map { streams[$0].stream }

        let shelf = VODRecentlyAdded.shelfItems(from: candidates, hidden: [])
        let newest = VODRecentlyAdded.newest(in: streams, visibleCategoryIds: listed)

        #expect(shelf.map(\.streamId) == Array(0..<20))
        #expect(newest.map(\.streamId) == shelf.map(\.streamId))
    }

    @Test
    func equalTimestampsKeepTheCatalogOrder() {
        let streams = [
            movie(1, category: "a", added: "100"),
            movie(2, category: "a", added: "200"),
            movie(3, category: "a", added: "100"),
            movie(4, category: "a", added: "200"),
        ]

        let newest = VODRecentlyAdded.newest(in: streams, visibleCategoryIds: ["a"])

        #expect(newest.map(\.streamId) == [2, 4, 1, 3])
    }

    // MARK: - History play queue

    @Test
    func aFilmFromTheHistoryIsQueuedWithItsCategory() throws {
        let buckets = [
            "1": [movie(10, category: "1"), movie(11, category: "1"), movie(12, category: "1")],
            "2": [movie(20, category: "2")],
        ]

        let match = try #require(VODHistoryQueue.locate(streamId: 11, in: buckets))

        #expect(match.movie.streamId == 11)
        #expect(match.queue.map(\.streamId) == [10, 11, 12])
    }

    @Test
    func aFilmThatLeftTheCatalogHasNoQueue() {
        let buckets = ["1": [movie(10, category: "1")]]

        #expect(VODHistoryQueue.locate(streamId: 99, in: buckets) == nil)
        #expect(VODHistoryQueue.locate(streamId: 10, in: [:]) == nil)
    }
}
