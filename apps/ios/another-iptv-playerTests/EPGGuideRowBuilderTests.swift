import Foundation
import SwiftUI
import Testing
@testable import another_iptv_player

/// The guide's row model: what it lists, how it groups, what a search keeps, and
/// which queue a channel started from it gets.
@Suite("EPG guide rows")
struct EPGGuideRowBuilderTests {

    private let playlistId = UUID()

    // MARK: Fixtures

    private func live(_ id: Int, _ name: String, category: String?, categoryName: String,
                      epgId: String? = nil) -> LiveStreamWithCategory {
        LiveStreamWithCategory(
            stream: DBLiveStream(streamId: id, name: name, epgChannelId: epgId,
                                 categoryId: category, playlistId: playlistId),
            categoryName: categoryName
        )
    }

    /// News (valid), Sports (valid), then three orphans: no category, an empty one
    /// and one the panel does not list.
    private var xtreamEntries: [LiveStreamWithCategory] {
        [
            live(1, "World News", category: "10", categoryName: "News", epgId: "World.News"),
            live(2, "Football One", category: "20", categoryName: "Sports"),
            live(3, "Şehir TV", category: "10", categoryName: "News"),
            live(4, "No Category", category: nil, categoryName: "Uncategorized"),
            live(5, "Blank Category", category: "", categoryName: "Uncategorized"),
            live(6, "Orphan", category: "999", categoryName: "Uncategorized"),
            live(7, "Sports HD TV", category: "20", categoryName: "Sports")
        ]
    }

    /// Bucketed the way the catalog store publishes `liveStreamsByCategoryId`.
    private func buckets(_ entries: [LiveStreamWithCategory]) -> [String: [LiveStreamWithCategory]] {
        PlaylistContentStore.bucketed(entries, validIds: ["10", "20"]) { $0.stream.categoryId }
    }

    private func xtreamRows(hidden: Set<String>, aliases: [String: String] = [:]) -> EPGGuideRowSet {
        let entries = xtreamEntries
        return EPGGuideViewModel.makeRows(xtream: entries, aliases: aliases,
                                          hiddenCategoryIds: hidden, streamsByCategory: buckets(entries))
    }

    private func names(_ set: EPGGuideRowSet) -> [String] {
        set.sections.flatMap { $0.rows.map(\.displayName) }
    }

    private func channel(_ name: String, url: String, group: String?, tvgId: String? = nil) -> DBM3UChannel {
        DBM3UChannel(id: url, playlistId: playlistId, name: name, url: url, tvgId: tvgId, groupTitle: group)
    }

    // MARK: Xtream

    @Test
    func xtreamRowsAreGroupedByCategoryInFirstAppearanceOrder() {
        let set = xtreamRows(hidden: [])

        #expect(set.sections.first?.id == "10")
        #expect(set.sections.first?.title == "News")
        #expect(set.sections.first?.rows.map(\.displayName) == ["World News", "Şehir TV"])
        #expect(set.sections.dropFirst().first?.rows.map(\.displayName) == ["Football One", "Sports HD TV"])
        #expect(names(set).count == 7)
        // Every row keeps the stream it plays.
        #expect(set.sections.allSatisfy { $0.rows.allSatisfy { $0.liveStream != nil } })
    }

    @Test
    func xtreamChannelKeysGoThroughTheAliasMap() {
        let set = xtreamRows(hidden: [], aliases: [
            "world.news": "worldnews.uk",     // id alias
            "football one": "football.1"      // display-name match
        ])
        let keyByName = Dictionary(uniqueKeysWithValues:
            set.sections.flatMap(\.rows).map { ($0.displayName, $0.channelKey) })

        #expect(keyByName["World News"] == "worldnews.uk")
        #expect(keyByName["Football One"] == "football.1")
        // No alias and no EPG id: the normalized name stands in.
        #expect(keyByName["Sports HD TV"] == "sports hd tv")
        #expect(set.channelKeys == Set(keyByName.values))
    }

    @Test
    func hiddenXtreamCategoryIsNotListed() {
        let set = xtreamRows(hidden: ["20"])

        #expect(!set.sections.contains { $0.id == "20" })
        #expect(!names(set).contains("Football One"))
        #expect(!names(set).contains("Sports HD TV"))
        #expect(names(set).count == 5)
        #expect(!set.channelKeys.contains("football one"))
    }

    @Test
    func hidingUncategorizedRemovesEveryOrphan() {
        let set = xtreamRows(hidden: [PlaylistContentStore.uncategorizedCategoryId])

        #expect(names(set) == ["World News", "Şehir TV", "Football One", "Sports HD TV"])
    }

    @Test
    func hiddenIdThatIsAlsoAnOrphansOwnCategoryDoesNotHideIt() {
        // "999" is not a category of the playlist; its channel is listed under
        // "uncategorized", which is not hidden.
        let set = xtreamRows(hidden: ["999"])

        #expect(names(set).contains("Orphan"))
        #expect(names(set).count == 7)
    }

    @Test
    func everythingHiddenLeavesAnEmptySet() {
        let set = xtreamRows(hidden: ["10", "20", PlaylistContentStore.uncategorizedCategoryId])

        #expect(set.isEmpty)
        #expect(set.channelKeys.isEmpty)
    }

    @Test
    func largeCatalogKeepsEveryVisibleChannelInCatalogOrder() {
        let categoryCount = 200
        let entries = (0..<50_000).map { index in
            live(index, "Channel \(index)", category: "\(index % categoryCount)",
                 categoryName: "Category \(index % categoryCount)")
        }
        let valid = Set((0..<categoryCount).map(String.init))
        let byCategory = PlaylistContentStore.bucketed(entries, validIds: valid) { $0.stream.categoryId }
        let hidden = Set((0..<10).map(String.init))

        let set = EPGGuideViewModel.makeRows(xtream: entries, aliases: [:],
                                             hiddenCategoryIds: hidden, streamsByCategory: byCategory)

        #expect(set.sections.count == categoryCount - hidden.count)
        #expect(set.sections.map(\.id) == (10..<categoryCount).map(String.init))
        #expect(set.sections.reduce(0) { $0 + $1.rows.count } == 50_000 / categoryCount * (categoryCount - hidden.count))
        #expect(set.channelKeys.count == 50_000 / categoryCount * (categoryCount - hidden.count))
        // Inside a category the channels keep the catalog's order.
        #expect(set.sections.first?.rows.prefix(3).map(\.displayName) == ["Channel 10", "Channel 210", "Channel 410"])
    }

    // MARK: M3U

    private var m3uChannels: [DBM3UChannel] {
        [
            channel("News One", url: "http://host/live/1.ts", group: "News", tvgId: "News.One"),
            channel("A Film", url: "http://host/movie/2.mp4", group: "News"),
            channel("Loose", url: "http://host/live/3.ts", group: nil),
            channel("News Two", url: "http://host/live/4.ts", group: " News "),
            channel("Kids One", url: "http://host/live/5.ts", group: "Kids"),
            channel("Broken", url: "   ", group: "Kids")
        ]
    }

    @Test
    func m3uRowsAreTheLiveChannels() {
        let set = EPGGuideViewModel.makeRows(m3u: m3uChannels, aliases: ["news.one": "news1.tv"], hiddenGroups: [])

        // The film is dropped; a channel whose URL cannot be parsed counts as live.
        #expect(names(set) == ["News One", "News Two", "Loose", "Kids One", "Broken"])
        #expect(set.sections.first?.rows.first?.channelKey == "news1.tv")
        // The row id is the channel id, which playback resolves the channel by.
        #expect(set.sections.first?.rows.first?.id == "http://host/live/1.ts")
        #expect(set.sections.allSatisfy { $0.rows.allSatisfy { $0.liveStream == nil } })
    }

    @Test
    func hiddenM3UGroupIsNotListed() {
        // Hidden ids are the store's group keys: the trimmed title, or the
        // ungrouped label for a channel without one.
        let hidden: Set<String> = ["News", M3UContentStore.ungroupedLabel]
        let set = EPGGuideViewModel.makeRows(m3u: m3uChannels, aliases: [:], hiddenGroups: hidden)

        #expect(names(set) == ["Kids One", "Broken"])
    }

    // MARK: Search

    @Test
    func searchUsesTheSharedMatcher() {
        let sections = xtreamRows(hidden: []).sections

        func found(_ search: String) -> [String] {
            EPGGuideViewModel.filter(sections, search: search).flatMap { $0.rows.map(\.displayName) }
        }

        #expect(found("sehir") == ["Şehir TV"])
        #expect(found("ŞEHİR") == ["Şehir TV"])
        #expect(found("sports tv") == ["Sports HD TV"])
        #expect(found("news") == ["World News"])
        // Text without a letter or digit is a search that matches nothing.
        #expect(found("--").isEmpty)
    }

    @Test
    func searchDropsSectionsWithoutAMatchAndKeepsTheirOrder() {
        let sections = xtreamRows(hidden: []).sections

        let matched = EPGGuideViewModel.filter(sections, search: "one")

        #expect(matched.map(\.id) == ["20"])
        #expect(matched.first?.title == "Sports")
        #expect(matched.first?.rows.map(\.displayName) == ["Football One"])
    }

    // MARK: Queue of a channel started from the guide

    private func liveSections() -> (queue: [DBLiveStream], sections: [LiveChannelCategorySection]) {
        let byCategory = buckets(xtreamEntries)
        let order = [("10", "News"), ("20", "Sports"), (PlaylistContentStore.uncategorizedCategoryId, "Uncategorized")]
        let sections = order.map { id, title in
            LiveChannelCategorySection(id: id, title: title, streams: (byCategory[id] ?? []).map(\.stream))
        }
        return (sections.flatMap(\.streams), sections)
    }

    @Test
    func queueLeavesOutHiddenCategories() {
        let live = liveSections()
        let news = live.sections[0].streams[0]

        let visible = EPGGuidePlayback.visible(live, hiding: ["20"], including: news)

        #expect(visible.sections.map(\.id) == ["10", PlaylistContentStore.uncategorizedCategoryId])
        #expect(visible.queue.map(\.streamId) == [1, 3, 4, 5, 6])
    }

    @Test
    func queueKeepsTheSectionOfTheChannelBeingStarted() {
        let live = liveSections()
        let football = live.sections[1].streams[0]

        let visible = EPGGuidePlayback.visible(live, hiding: ["10", "20"], including: football)

        #expect(visible.sections.map(\.id) == ["20", PlaylistContentStore.uncategorizedCategoryId])
        #expect(visible.queue.contains { $0.streamId == football.streamId })
        #expect(!visible.queue.contains { $0.streamId == 1 })
    }

    @Test
    func queueIsUntouchedWhenNothingIsHidden() {
        let live = liveSections()

        let visible = EPGGuidePlayback.visible(live, hiding: [], including: live.queue[0])

        #expect(visible.sections == live.sections)
        #expect(visible.queue == live.queue)
    }

    // MARK: Following the calendar

    /// A clock the test moves by hand.
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private func model(clock: Clock) -> EPGGuideViewModel {
        let playlist = Playlist(id: playlistId, name: "Guide", serverURL: "http://host/list.m3u", type: .m3u)
        return EPGGuideViewModel(source: .m3u(playlist), now: { clock.date })
    }

    private var evening: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10
        components.hour = 23
        components.minute = 50
        return Calendar.current.date(from: components)!
    }

    @Test
    func guideOnTodayFollowsTheDayChange() async {
        let clock = Clock(evening)
        let model = model(clock: clock)
        let calendar = Calendar.current
        #expect(model.selectedDay == calendar.startOfDay(for: evening))
        #expect(model.followsToday)

        clock.date = evening.addingTimeInterval(20 * 60)
        await model.rollToTodayIfNeeded()

        #expect(model.selectedDay == calendar.startOfDay(for: clock.date))
        #expect(model.followsToday)
        // The chips move with it: yesterday is now the day the guide was opened on.
        #expect(model.availableDays.first == calendar.startOfDay(for: evening))
        #expect(model.availableDays.count == 9)
    }

    @Test
    func sameDayChangesNothing() async {
        let clock = Clock(evening)
        let model = model(clock: clock)
        let days = model.availableDays

        clock.date = evening.addingTimeInterval(5 * 60)
        await model.rollToTodayIfNeeded()

        #expect(model.selectedDay == Calendar.current.startOfDay(for: evening))
        #expect(model.availableDays == days)
    }

    @Test
    func aDayPickedOnPurposeStaysPut() async {
        let clock = Clock(evening)
        let model = model(clock: clock)
        let calendar = Calendar.current
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: evening))!

        await model.selectDay(dayAfterTomorrow)
        #expect(!model.followsToday)

        clock.date = evening.addingTimeInterval(20 * 60)
        await model.rollToTodayIfNeeded()

        #expect(model.selectedDay == dayAfterTomorrow)
        #expect(!model.followsToday)
    }

    @Test
    func aPickedDayThatBecomesTodayIsFollowedFromThenOn() async {
        let clock = Clock(evening)
        let model = model(clock: clock)
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: evening))!

        await model.selectDay(tomorrow)
        #expect(!model.followsToday)

        // Midnight passes: the picked day is the current one and stays selected.
        clock.date = evening.addingTimeInterval(20 * 60)
        await model.rollToTodayIfNeeded()
        #expect(model.selectedDay == tomorrow)
        #expect(model.followsToday)

        // The next midnight moves it on.
        clock.date = evening.addingTimeInterval(86_400 + 20 * 60)
        await model.rollToTodayIfNeeded()
        #expect(model.selectedDay == calendar.startOfDay(for: clock.date))
    }

    // MARK: Metrics

    @Test
    func regularWidthWidensOnlyTheChannelColumn() {
        let compact = EPGGuideMetrics.guide(regularWidth: false)
        let regular = EPGGuideMetrics.guide(regularWidth: true)

        #expect(compact == EPGGuideMetrics(compact: true))
        #expect(regular.channelColumnWidth > compact.channelColumnWidth)
        // The view model precomputes cell frames from the hour width: it must not
        // depend on the width class.
        #expect(regular.hourWidth == compact.hourWidth)
        #expect(regular.dayWidth == compact.dayWidth)
        #expect(regular.rowHeight == compact.rowHeight)
    }
    @Test
    func largerTextPreservesProgrammeTimeCoordinates() {
        let start = Date(timeIntervalSince1970: 0)
        for regular in [false, true] {
            let baseline = EPGGuideMetrics.guide(regularWidth: regular)
            let enlarged = EPGGuideMetrics.guide(regularWidth: regular, textScale: 3)
            #expect(enlarged.rowHeight == baseline.rowHeight * 1.5)
            #expect(enlarged.channelColumnWidth == baseline.channelColumnWidth * 1.5)
            #expect(enlarged.axisHeight == baseline.axisHeight * 1.5)
            #expect(enlarged.headerHeight == baseline.headerHeight * 1.5)
            #expect(enlarged.dayWidth == baseline.dayWidth)
            #expect(enlarged.x(for: start.addingTimeInterval(18_000), dayStart: start)
                    == baseline.x(for: start.addingTimeInterval(18_000), dayStart: start))
            #expect(EPGGuideMetrics.guide(regularWidth: regular, textScale: 0.8) == baseline)
        }
    }

}
