import Foundation
import Testing
@testable import another_iptv_player

@Suite("CatalogTextSearch ranking")
struct CatalogTextSearchRankingTests {

    private func ranked(_ names: [String], _ search: String) -> [String] {
        CatalogTextSearch.rankedFilter(names, search: search) { $0 }
    }

    // MARK: - Tiers

    @Test
    func exactMatchComesFirst() {
        let names = ["Sports News", "Today Sports", "Sports", "Sports Plus"]
        #expect(ranked(names, "sports").first == "Sports")
    }

    @Test
    func prefixMatchComesBeforeTheRest() {
        let names = ["Acrobat", "EN - Batman", "Combat Zone", "Batman Begins"]
        #expect(ranked(names, "bat") == ["Batman Begins", "Acrobat", "Combat Zone", "EN - Batman"])
    }

    @Test
    func tiersAreExactThenPrefixThenRestAlphabeticalInside() {
        let names = [
            "Today Sports", "Sports Tonight", "News", "SPORTS", "Motorsports",
            "Sports News", "sports!", "Cinema",
        ]
        #expect(ranked(names, "sports") == [
            "SPORTS", "sports!",                 // the name is the query
            "Sports News", "Sports Tonight",     // the name starts with it
            "Motorsports", "Today Sports",       // it is somewhere inside
        ])
    }

    @Test
    func tiersCompareTheWholeQueryWithoutSpacesOrPunctuation() {
        let names = ["My Fox TV", "Fox TV Extra", "FOX-TV", "Fox Sports"]
        #expect(ranked(names, "fox tv") == ["FOX-TV", "Fox TV Extra", "My Fox TV"])
        #expect(ranked(names, "foxtv") == ["FOX-TV", "Fox TV Extra", "My Fox TV"])
        // The words match in any order, but only the typed order makes a name exact or a prefix.
        #expect(Set(ranked(names, "tv fox")) == ["FOX-TV", "Fox TV Extra", "My Fox TV"])
        #expect(ranked(["My Fox TV", "TV Fox"], "tv fox") == ["TV Fox", "My Fox TV"])
    }

    @Test
    func tiersFoldLikeTheMatcher() {
        let names = ["Yeni IŞIK", "Işık Spor", "IŞIK", "ＩＳＩＫ ４Ｋ"]
        for search in ["isik", "ışık", "IŞIK", "ｉｓｉｋ"] {
            let result = ranked(names, search)
            #expect(result.first == "IŞIK")
            #expect(Set(result.dropFirst().dropLast()) == ["Işık Spor", "ＩＳＩＫ ４Ｋ"])
            #expect(result.last == "Yeni IŞIK")
        }
    }

    @Test
    func onlyMatchesAreKept() {
        let names = ["Alpha", "Beta", "Alphabet", "Gamma"]
        #expect(ranked(names, "alpha") == ["Alpha", "Alphabet"])
        #expect(ranked(names, "delta").isEmpty)
        #expect(ranked([], "alpha").isEmpty)
    }

    // MARK: - Stability

    private nonisolated struct Entry: Equatable, Sendable {
        let id: Int
        let name: String
    }

    @Test
    func equalNamesKeepTheirInputOrderInsideEveryTier() {
        let entries = [
            Entry(id: 1, name: "The Echo"),
            Entry(id: 2, name: "Echo"),
            Entry(id: 3, name: "Echo Park"),
            Entry(id: 4, name: "ECHO"),
            Entry(id: 5, name: "THE ECHO"),
            Entry(id: 6, name: "echo park"),
            Entry(id: 7, name: "echo"),
            Entry(id: 8, name: "the echo"),
            Entry(id: 9, name: "Echo"),
            Entry(id: 10, name: "ECHO PARK"),
        ]
        let result = CatalogTextSearch.rankedFilter(entries, search: "echo") { $0.name }
        #expect(result.map(\.id) == [2, 4, 7, 9, 3, 6, 10, 1, 5, 8])
    }

    @Test
    func rankingIsTheSameOnEveryRun() {
        let names = (0..<500).map { "Channel \($0 % 50) HD" } + ["channel", "Channel 7"]
        let first = ranked(names, "channel")
        #expect(first.count == names.count)
        #expect(first.first == "channel")
        for _ in 0..<3 { #expect(ranked(names, "channel") == first) }
    }

    // MARK: - Searches without words

    @Test
    func blankSearchReturnsTheItemsUntouched() {
        let names = ["Zeta", "Alpha", "Beta"]
        #expect(ranked(names, "") == names)
        #expect(ranked(names, "   ") == names)
    }

    @Test
    func punctuationOnlySearchReturnsNothing() {
        let names = ["Zeta", "Alpha", "--", ""]
        #expect(ranked(names, "--").isEmpty)
        #expect(ranked(names, " ! ").isEmpty)
    }

    // MARK: - Cancellation

    @Test
    func rankedFilterReturnsNothingWhenAlreadyCancelled() async {
        let names = ["Sports", "Sports 2", "News"]
        let result = await Task { () -> [[String]] in
            withUnsafeCurrentTask { $0?.cancel() }
            return [
                CatalogTextSearch.rankedFilter(names, search: "sports") { $0 },
                CatalogTextSearch.rankedFilter(names, search: "") { $0 },
            ]
        }.value
        #expect(result == [[], []])
    }

    @Test
    func rankedFilterStopsScanningOnceCancelled() async {
        let names = (0..<40_000).map { "Channel \($0)" }
        let outcome = await Task { () -> (result: [String], scanned: Int) in
            var scanned = 0
            let result = CatalogTextSearch.rankedFilter(names, search: "channel") { name in
                scanned += 1
                if scanned == 3_000 { withUnsafeCurrentTask { $0?.cancel() } }
                return name
            }
            return (result, scanned)
        }.value
        #expect(outcome.result.isEmpty)
        #expect(outcome.scanned >= 3_000)
        #expect(outcome.scanned < names.count / 2)
    }

    @Test
    func rankedFilterReturnsNothingWhenCancelledAfterTheScan() async {
        // Cancelled on the last name: the scan is complete and only the sort is left.
        let names = (0..<6_000).map { "Channel \(($0 * 7919) % 6_000)" }
        let result = await Task { () -> [String] in
            var scanned = 0
            return CatalogTextSearch.rankedFilter(names, search: "channel") { name in
                scanned += 1
                if scanned == names.count { withUnsafeCurrentTask { $0?.cancel() } }
                return name
            }
        }.value
        #expect(result.isEmpty)
    }

    @Test
    func rankedFilterAbandonsTheSortOnceCancelled() async {
        // Every name is a hit and the input is shuffled, so the sort has real work to do.
        let names = (0..<6_000).map { "Channel \(($0 * 7919) % 6_000)" }
        // No sort can finish in fewer comparisons than this: each element has to be
        // compared with a neighbour at least once.
        let fewestToFinish = names.count - 1

        var completed = 0
        let sorted = CatalogTextSearch.rankedFilter(names, search: "channel", sortComparisons: &completed) { $0 }
        #expect(sorted.count == names.count)
        #expect(completed >= fewestToFinish)

        let outcome = await Task { () -> (result: [String], scanned: Int, comparisons: Int) in
            var scanned = 0
            var comparisons = 0
            let result = CatalogTextSearch.rankedFilter(names, search: "channel", sortComparisons: &comparisons) { name in
                scanned += 1
                if scanned == names.count { withUnsafeCurrentTask { $0?.cancel() } }
                return name
            }
            return (result, scanned, comparisons)
        }.value
        #expect(outcome.result.isEmpty)
        // The scan saw every name, so the comparisons below belong to a sort that started.
        #expect(outcome.scanned == names.count)
        #expect(outcome.comparisons > 0)
        // Returning [] is not enough: a sort that ran to the end before its result was
        // dropped would have held a core for the whole collation pass.
        #expect(outcome.comparisons < fewestToFinish)
    }

    @Test
    func sortComparisonsStartFromZeroOnEveryCall() async {
        var comparisons = 99
        #expect(CatalogTextSearch.rankedFilter(["Beta", "Alpha"], search: "a", sortComparisons: &comparisons) { $0 } == ["Alpha", "Beta"])
        #expect((1..<99).contains(comparisons))
        // Nothing is sorted for a blank search, a search without words or a cancelled task.
        comparisons = 99
        #expect(CatalogTextSearch.rankedFilter(["Beta", "Alpha"], search: " ", sortComparisons: &comparisons) { $0 } == ["Beta", "Alpha"])
        #expect(comparisons == 0)
        comparisons = 99
        #expect(CatalogTextSearch.rankedFilter(["Beta", "Alpha"], search: "--", sortComparisons: &comparisons) { $0 }.isEmpty)
        #expect(comparisons == 0)
        let cancelled = await Task { () -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            var comparisons = 99
            _ = CatalogTextSearch.rankedFilter(["Beta", "Alpha"], search: "a", sortComparisons: &comparisons) { $0 }
            return comparisons
        }.value
        #expect(cancelled == 0)
    }

    @Test
    func relevanceSortsIgnoreCancellation() async {
        // Only the cancellable entry point may return a short list; a sort is a sort.
        let names = ["Sports Tonight", "Sports", "Today Sports"]
        let result = await Task { () -> [String] in
            withUnsafeCurrentTask { $0?.cancel() }
            return CatalogTextSearch.sortLiveByRelevance(
                names.enumerated().map { index, name in
                    LiveStreamWithCategory(
                        stream: DBLiveStream(
                            streamId: index, name: name, streamIcon: nil, epgChannelId: nil,
                            categoryId: nil, sortIndex: index, playlistId: UUID()
                        ),
                        categoryName: "Cat"
                    )
                },
                search: "sports"
            ).map(\.stream.name)
        }.value
        #expect(result == ["Sports", "Sports Tonight", "Today Sports"])
    }

    // MARK: - detached

    @Test
    func detachedReturnsTheResultOfTheWork() async {
        let names = ["Today Sports", "Sports Tonight", "News"]
        let result = await CatalogTextSearch.detached {
            CatalogTextSearch.rankedFilter(names, search: "sports") { $0 }
        }
        #expect(result == ["Sports Tonight", "Today Sports"])
    }

    @Test
    func detachedRunsOffTheMainThread() async {
        let onMainThread = await CatalogTextSearch.detached(priority: .utility) { Thread.isMainThread }
        #expect(onMainThread == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func detachedIsCancelledWithItsCaller() async {
        let caller = Task {
            await CatalogTextSearch.detached { () -> Bool in
                // Spins until the cancellation arrives; the deadline only bounds a failure.
                let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
                while !Task.isCancelled, DispatchTime.now().uptimeNanoseconds < deadline {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return Task.isCancelled
            }
        }
        caller.cancel()
        let sawCancellation = await caller.value
        #expect(sawCancellation == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheCallerEmptiesARunningRankedFilter() async {
        let names = (0..<4_096).map { "Channel \($0)" }
        let caller = Task {
            await CatalogTextSearch.detached { () -> [String] in
                let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
                while !Task.isCancelled, DispatchTime.now().uptimeNanoseconds < deadline {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return CatalogTextSearch.rankedFilter(names, search: "channel") { $0 }
            }
        }
        caller.cancel()
        let result = await caller.value
        #expect(result.isEmpty)
    }

    // MARK: - Cost

    /// The comparator the relevance sorts used before: it folds both names and the
    /// query again inside every comparison.
    private nonisolated static func previousRelevanceSort(_ names: [String], search: String) -> [String] {
        names.sorted { n1, n2 in
            let e1 = CatalogTextSearch.equals(search: search, text: n1), e2 = CatalogTextSearch.equals(search: search, text: n2)
            if e1 != e2 { return e1 && !e2 }
            let s1 = CatalogTextSearch.startsWith(search: search, text: n1), s2 = CatalogTextSearch.startsWith(search: search, text: n2)
            if s1 != s2 { return s1 && !s2 }
            return n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
        }
    }

    @Test(.timeLimit(.minutes(5)))
    func rankedFilterIsFasterThanFilterThenComparatorSort() {
        var names = CatalogSearchFixtures.titles(count: 100_000)
        // A few rows for the two upper tiers, so the comparison covers all three. No "i" in
        // them: a Turkish device does not treat "I" and "i" as the same letter when sorting.
        names[10] = "Story"
        names[20_000] = "STORY"
        names[40_000] = "Story Mode"
        names[60_000] = "story mode"
        names[80_000] = "Story & Co"
        let search = "story"

        let clock = ContinuousClock()
        var previous: [String] = []
        let previousTime = clock.measure {
            let filtered = names.filter { CatalogTextSearch.matches(search: search, text: $0) }
            previous = Self.previousRelevanceSort(filtered, search: search)
        }
        var ranked: [String] = []
        let rankedTime = clock.measure {
            ranked = CatalogTextSearch.rankedFilter(names, search: search) { $0 }
        }

        Log.info("SearchBench", "100k titles, \(ranked.count) hits: rankedFilter \(rankedTime), filter + comparator sort \(previousTime)")
        #expect(ranked.count > 5_000)
        #expect(ranked.prefix(5) == ["Story", "STORY", "Story & Co", "Story Mode", "story mode"])
        #expect(ranked == previous)
        #expect(rankedTime < previousTime, "rankedFilter \(rankedTime), filter + comparator sort \(previousTime)")
    }
}
