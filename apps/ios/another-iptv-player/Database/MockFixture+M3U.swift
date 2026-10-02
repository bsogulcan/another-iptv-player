import Foundation
import GRDB

// The second playlist of the rich mode, of kind M3U. Without it no M3U screen
// can be reached in a UI test, and nothing ever shows two playlists in the list.
extension MockFixture {

    /// What a test needs to find the rows of the M3U playlist.
    enum M3U {
        static let playlistName = "Demo M3U"
        static let guideURL = "https://example.com/guide.xml"

        static let newsGroup = "News"
        /// The group long enough to page.
        static let largeGroup = "World"
        /// Entries whose URL ends in `.mp4` or `.mkv`: the app treats them as films.
        static let filmGroup = "Movies"

        static let newsCount = 12
        static let largeGroupCount = 400
        static let filmCount = 24
        /// Channels with a missing, empty or blank `group-title`.
        static let ungroupedCount = 4
        static let channelCount = newsCount + largeGroupCount + filmCount + ungroupedCount

        /// In the news group, and a favourite.
        static let favoriteChannelName = "Harbor News"
        /// Has no `tvg-id`; its guide is found through the guide channel's display name.
        static let nameMatchedChannelName = "Canyon Bulletin"
        /// How many channels have guide rows: nine in the news group, the first
        /// twelve of the large one.
        static let guideChannelCount = 21
        /// Channels that carry a `tvg-id` the guide has no rows for.
        static let unmatchedTvgIds = ["frontiernews.demo", "islandlive.demo"]

        /// Live entries play the demo stream. The query does nothing but make every
        /// URL distinct, and with it every channel id, which is derived from the URL.
        static func liveURL(_ number: Int) -> String {
            "\(MockFixture.demoStreamURL)?channel=\(number)"
        }

        /// `.mp4` entries play a ten-minute sample file; there is no public `.mkv`
        /// sample of that standing, so those point at the placeholder host.
        static func filmURL(_ number: Int, mkv: Bool) -> String {
            mkv
                ? "https://example.com/movie/demo/demo/\(number).mkv"
                : "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/v2/main.mp4?film=\(number)"
        }

        static func isMKV(film index: Int) -> Bool { index % 3 == 2 }

        static func filmName(_ index: Int) -> String {
            "\(MockFixture.title(400 + index)) (\(1990 + index))"
        }
    }

    static func seedM3UPlaylist(db: Database, playlistId: UUID, now: Date, calendar: Calendar = .current) throws {
        try? db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [playlistId])
        // With a guide URL the playlist counts as having a guide from its first
        // frame; the bookkeeping row written below keeps the app from fetching it.
        try Playlist(
            id: playlistId,
            name: M3U.playlistName,
            serverURL: "https://example.com/playlist.m3u",
            type: .m3u,
            m3uEpgURL: M3U.guideURL
        ).insert(db)

        var sortIndex = 0
        func insert(_ name: String, url: String, group: String?, tvgId: String? = nil,
                    logo: String?) throws -> DBM3UChannel {
            let channel = DBM3UChannel(
                // The id an import of the same list would give the channel.
                id: M3UImporter.stableChannelID(playlistId: playlistId, url: url),
                playlistId: playlistId,
                name: name,
                url: url,
                tvgId: tvgId,
                tvgLogo: logo,
                groupTitle: group,
                sortIndex: sortIndex
            )
            try channel.insert(db)
            sortIndex += 1
            return channel
        }
        func logo() -> String? { artwork("live", 700_000 + sortIndex, w: 200, h: 200) }

        var guide: [GuideChannel] = []
        var favorites: [DBM3UChannel] = []

        // News. Eight channels match the guide by `tvg-id` (the first in mixed
        // case), two carry an id the guide does not know, one is matched by name
        // and one has neither id nor guide.
        let news: [(String, String?, GuideShape?)] = [
            (M3U.favoriteChannelName, "HarborNews.demo", .news),
            ("Capital 24", "capital24.demo", .news),
            ("Metro Report", "metroreport.demo", .business),
            ("Coastline TV", "coastline.demo", .documentary),
            ("Summit Sports", "summitsports.demo", .sport),
            ("Valley Today", "valleytoday.demo", .news),
            ("Northern Dispatch", "northerndispatch.demo", .documentary),
            ("Daily Ledger", "dailyledger.demo", .business),
            ("Frontier News", M3U.unmatchedTvgIds[0], nil),
            ("Island Live", M3U.unmatchedTvgIds[1], nil),
            (M3U.nameMatchedChannelName, nil, .news),
            ("Lantern TV", nil, nil),
        ]
        for (name, tvgId, shape) in news {
            let channel = try insert(name, url: M3U.liveURL(sortIndex + 1), group: M3U.newsGroup, tvgId: tvgId, logo: logo())
            if name == M3U.favoriteChannelName { favorites.append(channel) }
            guard let shape else { continue }
            // The name-matched channel's guide rows sit under an id the playlist never mentions.
            let key = tvgId.map { guideKey($0) } ?? "canyonbulletin.demo"
            guide.append(guideChannel(key: key, displayName: name, iconURL: channel.tvgLogo, shape: shape))
        }

        // The large group, with the names that need folding, a right-to-left and a
        // Cyrillic one, one that wraps and one channel without a logo.
        let named: [Int: String] = [
            3: "IŞIK TV",
            4: "İZLE",
            5: "Çocuk",
            6: "أخبار العالم",
            7: "Новости Мира",
            8: "Documentary & Nature Channel International",
        ]
        let shapes: [GuideShape] = [.film, .comedy, .documentary, .music, .kids, .sport]
        for i in 0..<M3U.largeGroupCount {
            let name = named[i] ?? "\(nouns[i % nouns.count]) TV \(i + 1)"
            let tvgId = i < 12 ? "world\(i + 1).demo" : nil
            let channel = try insert(name, url: M3U.liveURL(sortIndex + 1), group: M3U.largeGroup,
                                     tvgId: tvgId, logo: i == 9 ? nil : logo())
            if let tvgId {
                guide.append(guideChannel(key: guideKey(tvgId), displayName: name, iconURL: channel.tvgLogo,
                                          shape: shapes[i % shapes.count]))
            }
        }

        var films: [DBM3UChannel] = []
        for i in 0..<M3U.filmCount {
            let film = try insert(M3U.filmName(i), url: M3U.filmURL(i + 1, mkv: M3U.isMKV(film: i)), group: M3U.filmGroup,
                                  logo: artwork("vod", 700_000 + sortIndex, w: 400, h: 600))
            films.append(film)
        }

        let ungrouped: [(String, String?)] = [
            ("Test Pattern", nil),
            ("Spare Feed 1", nil),
            ("Spare Feed 2", ""),
            ("Relay 9", "   "),
        ]
        for (name, group) in ungrouped {
            _ = try insert(name, url: M3U.liveURL(sortIndex + 1), group: group, logo: logo())
        }

        try insertGuide(db: db, playlistId: playlistId, sourceType: .m3uXMLTV, sourceURL: M3U.guideURL,
                        channels: guide, now: now, calendar: calendar)

        // One live favourite and one film, newest first as the list shows them.
        favorites.append(films[0])
        for (offset, channel) in favorites.enumerated() {
            try DBM3UFavorite(channelId: channel.id, playlistId: playlistId,
                              createdAt: now.addingTimeInterval(TimeInterval(-offset * 60))).insert(db)
        }

        // A film watched to 30 %, as the player stores it for an M3U entry.
        let watched = films[1]
        try DBWatchHistory(
            id: "\(playlistId)_vod_\(watched.id)",
            playlistId: playlistId,
            streamId: watched.id,
            type: "vod",
            lastTimeMs: demoStreamDurationMs * 30 / 100,
            durationMs: demoStreamDurationMs,
            lastWatchedAt: now.addingTimeInterval(-45 * 60),
            seriesId: nil,
            title: watched.name,
            secondaryTitle: watched.groupTitle,
            imageURL: watched.tvgLogo,
            containerExtension: "mp4"
        ).insert(db)
    }
}
