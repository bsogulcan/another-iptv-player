import Foundation
import Testing
@testable import another_iptv_player

/// The parts of the M3U channel screens that are plain logic: which groups a search
/// leaves on screen, and which logos a card asks for and lets go of.
@Suite("M3U browse logic")
struct M3UBrowseLogicTests {

    private let playlistId = UUID()

    private func channel(_ name: String, group: String?, logo: String? = nil) -> DBM3UChannel {
        DBM3UChannel(
            id: name,
            playlistId: playlistId,
            name: name,
            url: "http://host/live/\(name).ts",
            tvgLogo: logo,
            groupTitle: group
        )
    }

    private var catalog: (groups: [String], byGroup: [String: [DBM3UChannel]]) {
        let news = [channel("World News", group: "News"), channel("Sport Report", group: "News")]
        let sports = [channel("Arena One", group: "Sports"), channel("Arena Two", group: "Sports")]
        let kids = [channel("Cartoons", group: "Kids")]
        let loose = [channel("Loose Sportsman", group: nil), channel("Nameless", group: nil)]
        return (
            ["News", "Sports", "Kids", M3UContentStore.ungroupedLabel],
            ["News": news, "Sports": sports, "Kids": kids, M3UContentStore.ungroupedLabel: loose]
        )
    }

    private func search(_ query: String) -> M3UGroupSearch.Result {
        M3UGroupSearch.run(query: query, revision: 7, groups: catalog.groups, channelsByGroup: catalog.byGroup)
    }

    // MARK: Search over groups

    @Test
    func aGroupWhoseNameMatchesStaysWhole() {
        let result = search("sports")
        // "Arena One" and "Arena Two" do not match on their own: the group name does.
        #expect(result.channelsByGroup["Sports"]?.map(\.name) == ["Arena One", "Arena Two"])
    }

    @Test
    func otherGroupsKeepOnlyTheMatchingChannels() {
        let result = search("sport")
        #expect(result.channelsByGroup["News"]?.map(\.name) == ["Sport Report"])
        #expect(result.channelsByGroup[M3UContentStore.ungroupedLabel]?.map(\.name) == ["Loose Sportsman"])
    }

    @Test
    func groupsWithoutAHitDropOutAndTheOrderIsThePlaylists() {
        let result = search("sport")
        #expect(result.groups == ["News", "Sports", M3UContentStore.ungroupedLabel])
        #expect(result.channelsByGroup["Kids"] == nil)
    }

    @Test
    func theResultCarriesWhatItWasComputedFrom() {
        let result = search("arena")
        #expect(result.query == "arena")
        #expect(result.revision == 7)
    }

    @Test
    func matchingIgnoresCaseAccentsAndPunctuation() {
        #expect(search("WORLD-news").groups == ["News"])
        #expect(search("cártoons").groups == ["Kids"])
    }

    @Test
    func aQueryWithoutLetterOrDigitMatchesNothing() {
        // It must not list the whole catalog as if every channel were a hit.
        let result = search("--")
        #expect(result.groups.isEmpty)
        #expect(result.channelsByGroup.isEmpty)
    }

    @Test
    func noHitAnywhereIsAnEmptyResult() {
        #expect(search("zzzz").groups.isEmpty)
    }

    @Test
    func theUngroupedBucketIsFoundByTheTitleItIsShownUnder() {
        // Stored under a fixed key, shown under a localized title; the viewer types the title.
        let shown = M3UContentStore.displayName(forGroup: M3UContentStore.ungroupedLabel)
        let result = search(shown)
        #expect(result.groups.contains(M3UContentStore.ungroupedLabel))
        #expect(result.channelsByGroup[M3UContentStore.ungroupedLabel]?.count == 2)
    }

    @Test
    func aCancelledSearchStopsEarly() async {
        let groups = catalog.groups
        let byGroup = catalog.byGroup
        let task = Task.detached { () -> M3UGroupSearch.Result in
            // Cancelled before the scan starts looking at its first group.
            withUnsafeCurrentTask { $0?.cancel() }
            return M3UGroupSearch.run(query: "sport", revision: 1, groups: groups, channelsByGroup: byGroup)
        }
        let result = await task.value
        #expect(result.groups.isEmpty)
    }

    // MARK: Grid signature

    @MainActor
    @Test
    func theGridSignatureIgnoresTheSelectionClosure() {
        let items = [channel("A", group: nil), channel("B", group: nil), channel("C", group: nil)]
        let first = M3UGroupGridContent(items: items, onChannelSelected: { _ in })
        let second = M3UGroupGridContent(items: items, onChannelSelected: nil)
        // A parent pass that only rebuilt the closure must not re-render the grid.
        #expect(first == second)
    }

    @MainActor
    @Test
    func theGridSignatureSeesAChangedList() {
        let a = channel("A", group: nil)
        let b = channel("B", group: nil)
        let c = channel("C", group: nil)
        let d = channel("D", group: nil)
        let base = M3UGroupGridContent(items: [a, b, c])
        #expect(base != M3UGroupGridContent(items: [a, b]))          // shorter
        #expect(base != M3UGroupGridContent(items: [d, b, c]))       // another head
        #expect(base != M3UGroupGridContent(items: [a, b, d]))       // another tail
        // Same list, but one is the outcome of a search: their empty states differ.
        #expect(base != M3UGroupGridContent(items: [a, b, c], isSearchResult: true))
    }

    // MARK: Logo look-ahead

    @Test
    func onlyEveryStrideThCardIsATrigger() {
        #expect(M3ULogoLookAhead.startRange(forCardAt: 0, stride: 8, count: 100) == 1..<17)
        #expect(M3ULogoLookAhead.startRange(forCardAt: 8, stride: 8, count: 100) == 9..<25)
        for index in 1..<8 {
            #expect(M3ULogoLookAhead.startRange(forCardAt: index, stride: 8, count: 100) == nil)
            #expect(M3ULogoLookAhead.stopRange(forCardAt: index, stride: 8, count: 100) == nil)
        }
    }

    @Test
    func aTriggerAsksForTwoStridesAndLetsGoOfTheFirst() {
        #expect(M3ULogoLookAhead.startRange(forCardAt: 10, stride: 5, count: 100) == 11..<21)
        #expect(M3ULogoLookAhead.stopRange(forCardAt: 10, stride: 5, count: 100) == 11..<16)
    }

    @Test
    func stoppedRangesOfNeighbouringTriggersDoNotOverlapAndLeaveNoGap() {
        // One prefetch task exists per image: a range stopped twice would cancel what
        // the other trigger still wants, a gap would never be stopped.
        var covered: [Int] = []
        for index in stride(from: 0, to: 40, by: 8) {
            guard let range = M3ULogoLookAhead.stopRange(forCardAt: index, stride: 8, count: 1000) else {
                Issue.record("card \(index) should be a trigger")
                continue
            }
            covered.append(contentsOf: range)
        }
        #expect(covered == Array(1..<41))
    }

    @Test
    func rangesAreClampedToTheList() {
        #expect(M3ULogoLookAhead.startRange(forCardAt: 16, stride: 8, count: 20) == 17..<20)
        #expect(M3ULogoLookAhead.stopRange(forCardAt: 16, stride: 8, count: 20) == 17..<20)
        // The last card has nothing after it.
        #expect(M3ULogoLookAhead.startRange(forCardAt: 16, stride: 8, count: 17) == nil)
        #expect(M3ULogoLookAhead.startRange(forCardAt: 0, stride: 8, count: 0) == nil)
    }

    @Test
    func aNonsenseStrideOrIndexIsNoTrigger() {
        #expect(M3ULogoLookAhead.startRange(forCardAt: 0, stride: 0, count: 10) == nil)
        #expect(M3ULogoLookAhead.startRange(forCardAt: -8, stride: 8, count: 10) == nil)
    }

    @Test
    func logoURLsSkipChannelsWithoutAUsableLogo() {
        let channels = [
            channel("A", group: nil, logo: "http://host/a.png"),
            channel("B", group: nil, logo: nil),
            channel("C", group: nil, logo: ""),
            channel("D", group: nil, logo: "http://host/d.png"),
        ]
        let urls = M3ULogoLookAhead.logoURLs(in: channels[0..<4])
        #expect(urls.map(\.absoluteString) == ["http://host/a.png", "http://host/d.png"])
        #expect(M3ULogoLookAhead.logoURLs(in: channels[1..<3]).isEmpty)
    }
}
