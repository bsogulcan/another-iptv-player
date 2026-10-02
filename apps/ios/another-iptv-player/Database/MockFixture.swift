import Foundation
import GRDB

/// Seeds the shared database with placeholder content so App Store screenshots
/// can be captured without a real (copyrighted) IPTV playlist. Activated only
/// when the app is launched with `-UITests 1` (fastlane snapshot run).
///
/// What gets seeded depends on `mode`. The seed functions take the database and
/// the playlist ids, so they also run against an in-memory database in unit tests.
enum MockFixture {

    static let isActive: Bool = {
        let args = CommandLine.arguments
        if args.contains("-UITests") { return true }
        if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "YES" {
            return true
        }
        return false
    }()

    enum Mode: Equatable {
        /// The small demo catalog. The App Store screenshots are taken on it, so
        /// its content must not change.
        case demo
        /// `-UITestsFixture rich`: the demo catalog plus what the screens behind it
        /// need to show anything (seasons and episodes, guide data, watch history,
        /// favourites, awkward names and category shapes) and a second playlist of
        /// kind M3U. See `MockFixture+Rich.swift` and `MockFixture+M3U.swift`.
        case rich
        /// `-UITestsCatalogScale <n>`: the large synthetic catalog.
        case large
    }

    static let mode: Mode = mode(
        catalogScale: catalogScale,
        fixture: UserDefaults.standard.string(forKey: "UITestsFixture")
    )

    /// The scale argument wins: the large catalog reuses the demo playlist id.
    static func mode(catalogScale: Int, fixture: String?) -> Mode {
        if catalogScale > 0 { return .large }
        return fixture == "rich" ? .rich : .demo
    }

    static let demoPlaylistId: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    /// The M3U playlist of the rich mode.
    static let m3uPlaylistId: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555556")!
    /// Every playlist a fixture mode can create.
    static let fixturePlaylistIds: [UUID] = [demoPlaylistId, m3uPlaylistId]

    /// The playlist that opens at launch: the Xtream demo playlist, or with
    /// `-UITestsStartPlaylist m3u` the M3U one, which only the rich mode has.
    static func startPlaylistId(mode: Mode, startPlaylist: String?) -> UUID {
        mode == .rich && startPlaylist == "m3u" ? m3uPlaylistId : demoPlaylistId
    }

    /// Reseeds the demo playlist synchronously so the UI shows populated
    /// data the moment the dashboard appears. Safe to call once from
    /// `App.init`. No-ops when not in UITest mode.
    static func seedIfNeeded() {
        guard isActive else { return }

        resetBrowseState(playlistIds: fixturePlaylistIds)

        let mode = self.mode
        if mode == .large {
            // An M3U playlist left by a rich run would be a second row in the
            // playlist list of a catalog that is otherwise kept between launches.
            _ = try? AppDatabase.shared.writeSync { db in
                try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [m3uPlaylistId])
            }
            seedLargeCatalogIfNeeded()
            UserDefaults.standard.set(demoPlaylistId.uuidString, forKey: "lastPlaylistId")
            return
        }

        do {
            try AppDatabase.shared.writeSync { db in
                try seed(mode, db: db, playlistId: demoPlaylistId, m3uPlaylistId: m3uPlaylistId, now: Date())
            }
        } catch {
            Log.error("MockFixture", "seeding failed: \(error.localizedDescription)")
        }

        let start = startPlaylistId(mode: mode, startPlaylist: UserDefaults.standard.string(forKey: "UITestsStartPlaylist"))
        UserDefaults.standard.set(start.uuidString, forKey: "lastPlaylistId")
    }

    /// Everything the demo or the rich mode writes, for one write transaction.
    /// Both rebuild their playlists from nothing on every launch: that is what
    /// keeps a test independent of the favourites and history an earlier one left.
    /// `now` anchors every time-dependent row (guide, history, favourites).
    static func seed(_ mode: Mode, db: Database, playlistId: UUID, m3uPlaylistId: UUID,
                     now: Date, calendar: Calendar = .current) throws {
        switch mode {
        case .rich:
            try seedRichCatalog(db: db, playlistId: playlistId, now: now, calendar: calendar)
            try seedM3UPlaylist(db: db, playlistId: m3uPlaylistId, now: now, calendar: calendar)
        case .demo:
            try seedDemoCatalog(db: db, playlistId: playlistId, now: now)
            // The demo mode has one playlist; drop the one a rich run left.
            try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [m3uPlaylistId])
        case .large:
            // Kept between launches; `seedLargeCatalogIfNeeded` builds it.
            break
        }
    }

    // MARK: - Browse state

    /// Removes the browse state an earlier run left in the defaults: the restored
    /// tab, the three sort choices (a stored sort also decides which code path a
    /// grid takes), the hidden and the collapsed categories of the fixture
    /// playlists, whether their channel cards reserved a guide line last time,
    /// and the in-app language, which would win over `-AppleLanguages`. What is
    /// left is what a fresh install sees, as in a fastlane run.
    ///
    /// Removed, not pinned through launch arguments: the argument domain shadows
    /// every later write, so a pinned sort would stop responding in the test that
    /// changes it. A test may still pin a key that way; arguments are not touched.
    static func resetBrowseState(playlistIds: [UUID], in defaults: UserDefaults = .standard) {
        var keys = [
            "dashboard_selected_tab",
            "live.sortOption",
            "vod.sortOption",
            "series.sortOption",
            "app.selected_language",
        ]
        for id in playlistIds {
            keys.append("epg.collapsedCategories.\(id.uuidString)")
            keys.append("epg.lineReserved.\(id.uuidString)")
            for type in ["live", "vod", "series", "m3u"] {
                keys.append("hidden_categories.\(id.uuidString).\(type)")
            }
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Demo catalog

    /// The default mode: the small catalog, and the guide marked as refreshed.
    static func seedDemoCatalog(db: Database, playlistId: UUID, now: Date) throws {
        try insertDemoRows(db: db, playlistId: playlistId)
        try stampGuideSource(db: db, playlistId: playlistId, sourceType: .xtreamXMLTV, url: nil, now: now)
    }

    /// The playlist row and the small catalog, replacing whatever the playlist held.
    static func insertDemoRows(db: Database, playlistId: UUID) throws {
        try? db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [playlistId])
        try insertDemoPlaylist(db: db, playlistId: playlistId)
        try insertLive(db: db, playlistId: playlistId)
        try insertVOD(db: db, playlistId: playlistId)
        try insertSeries(db: db, playlistId: playlistId)
    }

    /// Records a guide refresh that succeeded at `now`. Deleting a fixture playlist
    /// takes its guide bookkeeping along, and with no such row every launch started
    /// a guide download from the placeholder host.
    static func stampGuideSource(db: Database, playlistId: UUID, sourceType: EPGSourceType, url: String?,
                                 now: Date, programmeCount: Int = 0, channelCount: Int = 0) throws {
        try DBEPGSource(
            playlistId: playlistId,
            sourceType: sourceType.rawValue,
            url: url,
            fetchedAt: now,
            lastSuccessAt: now,
            programmeCount: programmeCount,
            channelCount: channelCount
        ).insert(db)
    }

    private static func insertDemoPlaylist(db: Database, playlistId: UUID) throws {
        let playlist = Playlist(
            id: playlistId,
            name: "Demo Playlist",
            serverURL: "https://example.com",
            username: "demo",
            password: "demo"
        )
        try playlist.insert(db)
    }

    private static func insertLive(db: Database, playlistId: UUID) throws {
        let categories: [(String, String)] = [
            ("live-news", "News"),
            ("live-sports", "Sports"),
            ("live-entertainment", "Entertainment"),
            ("live-kids", "Kids"),
        ]
        for (idx, (id, name)) in categories.enumerated() {
            let c = DBCategory(id: id, name: name, parentId: nil, type: "live", sortIndex: idx, playlistId: playlistId)
            try c.insert(db)
        }

        let channels: [(Int, String, String)] = [
            (101, "World News 24",         "live-news"),
            (102, "Business Today",        "live-news"),
            (103, "Morning Update",        "live-news"),
            (201, "Sports Central",        "live-sports"),
            (202, "Football Live",         "live-sports"),
            (203, "Tennis Pro",            "live-sports"),
            (204, "Motorsport HD",         "live-sports"),
            (301, "Cinema Channel",        "live-entertainment"),
            (302, "Music Hits",            "live-entertainment"),
            (303, "Comedy Plus",           "live-entertainment"),
            (304, "Discovery Stories",     "live-entertainment"),
            (401, "Cartoon World",         "live-kids"),
            (402, "Learning Time",         "live-kids"),
        ]
        for (idx, (sid, name, cat)) in channels.enumerated() {
            let s = DBLiveStream(
                streamId: sid,
                name: name,
                streamIcon: artwork("live", sid, w: 200, h: 200),
                epgChannelId: nil,
                categoryId: cat,
                sortIndex: idx,
                playlistId: playlistId
            )
            try s.insert(db)
        }
    }

    private static func insertVOD(db: Database, playlistId: UUID) throws {
        let categories: [(String, String)] = [
            ("vod-action",   "Action"),
            ("vod-drama",    "Drama"),
            ("vod-comedy",   "Comedy"),
            ("vod-scifi",    "Sci-Fi"),
            ("vod-doc",      "Documentary"),
        ]
        for (idx, (id, name)) in categories.enumerated() {
            let c = DBCategory(id: id, name: name, parentId: nil, type: "vod", sortIndex: idx, playlistId: playlistId)
            try c.insert(db)
        }

        let movies: [(Int, String, String, String, String?)] = [
            (1001, "Midnight Horizon",     "vod-action",  "2024", "8.1"),
            (1002, "Echoes of Tomorrow",   "vod-scifi",   "2023", "7.4"),
            (1003, "The Quiet Path",       "vod-drama",   "2023", "7.9"),
            (1004, "City Lights",          "vod-drama",   "2022", "7.2"),
            (1005, "Velocity",             "vod-action",  "2024", "6.8"),
            (1006, "Laugh Out Loud",       "vod-comedy",  "2023", "6.5"),
            (1007, "Beyond the Stars",     "vod-scifi",   "2024", "8.4"),
            (1008, "Wild Planet",          "vod-doc",     "2023", "8.7"),
            (1009, "Ocean Depths",         "vod-doc",     "2024", "8.9"),
            (1010, "Last Departure",       "vod-action",  "2023", "7.3"),
            (1011, "Family Ties",          "vod-comedy",  "2024", "7.0"),
            (1012, "Whispers in the Wind", "vod-drama",   "2022", "7.6"),
        ]
        for (idx, (sid, name, cat, year, rating)) in movies.enumerated() {
            let s = DBVODStream(
                streamId: sid,
                name: name,
                streamIcon: artwork("vod", sid, w: 400, h: 600),
                categoryId: cat,
                rating: rating,
                containerExtension: "mp4",
                plot: "A captivating placeholder synopsis for demo purposes.",
                releaseDate: year,
                rating5Based: rating.flatMap { Double($0) }.map { $0 / 2 },
                metadataLoaded: true,
                sortIndex: idx,
                playlistId: playlistId
            )
            try s.insert(db)
        }
    }

    private static func insertSeries(db: Database, playlistId: UUID) throws {
        let categories: [(String, String)] = [
            ("series-drama",    "Drama"),
            ("series-thriller", "Thriller"),
            ("series-comedy",   "Comedy"),
            ("series-doc",      "Documentary"),
        ]
        for (idx, (id, name)) in categories.enumerated() {
            let c = DBCategory(id: id, name: name, parentId: nil, type: "series", sortIndex: idx, playlistId: playlistId)
            try c.insert(db)
        }

        let series: [(Int, String, String, String?)] = [
            (2001, "Northern Lights",     "series-drama",    "8.5"),
            (2002, "The Verdict",         "series-thriller", "8.1"),
            (2003, "Sunset Avenue",       "series-drama",    "7.9"),
            (2004, "Open Workshop",       "series-comedy",   "7.2"),
            (2005, "Hidden Truths",       "series-thriller", "8.6"),
            (2006, "Modern Family Days",  "series-comedy",   "7.6"),
            (2007, "Built to Last",       "series-doc",      "8.9"),
            (2008, "Coastlines",          "series-doc",      "8.4"),
        ]
        for (idx, (sid, name, cat, rating)) in series.enumerated() {
            let s = DBSeries(
                seriesId: sid,
                name: name,
                cover: artwork("series", sid, w: 400, h: 600),
                plot: "An engaging placeholder description for demo purposes.",
                releaseDate: "2024",
                rating: rating,
                rating5Based: rating.flatMap { Double($0) }.map { $0 / 2 },
                categoryId: cat,
                sortIndex: idx,
                seasonsLoaded: false,
                playlistId: playlistId
            )
            try s.insert(db)
        }
    }

    // MARK: - Large synthetic catalog

    /// `-UITestsCatalogScale <n>` replaces the small demo catalog with a synthetic one of
    /// roughly n x (300 channels, 700 movies, 200 series), so UI tests can exercise
    /// pagination, scroll retention and search ranking at realistic sizes.
    static let catalogScale: Int = UserDefaults.standard.integer(forKey: "UITestsCatalogScale")
    /// `-UITestsImageBase <url>` serves artwork from that base instead of picsum.photos;
    /// `none` leaves every item without artwork, so a test run needs no network.
    static let imageBase: String? = UserDefaults.standard.string(forKey: "UITestsImageBase")

    private static let adjectives = ["Silent", "Midnight", "Golden", "Broken", "Hidden", "Last", "First", "Dark", "Bright", "Lost", "Wild", "Frozen", "Burning", "Secret", "Crimson", "Electric", "Hollow", "Distant", "Eternal", "Savage", "Gentle", "Fallen", "Rising", "Quiet", "Restless", "Iron", "Paper", "Glass", "Silver", "Scarlet", "Northern", "Southern", "Endless", "Sudden", "Bitter", "Sweet", "Ancient", "Modern", "Final", "Invisible"]
    static let nouns = ["River", "Horizon", "Empire", "Garden", "Storm", "Kingdom", "Mirror", "Voyage", "Harbor", "Promise", "Shadow", "Legacy", "Station", "Island", "Canyon", "Orchard", "Witness", "Frontier", "Lantern", "Compass", "Harvest", "Signal", "Avenue", "Bridge", "Desert", "Forest", "Ocean", "Mountain", "Valley", "Summer", "Winter", "Detective", "Stranger", "Captain", "Doctor", "Hunter", "Dreamer", "Runner", "Painter", "Soldier"]

    static func title(_ i: Int) -> String {
        let a = adjectives[i % adjectives.count]
        let n = nouns[(i / adjectives.count) % nouns.count]
        let round = i / (adjectives.count * nouns.count)
        return round == 0 ? "The \(a) \(n)" : "The \(a) \(n) \(round + 1)"
    }

    static func artwork(_ kind: String, _ id: Int, w: Int, h: Int) -> String? {
        if let base = imageBase {
            return base == "none" ? nil : "\(base)/\(kind)/\(id).jpg"
        }
        return posterURL(seed: "\(kind)-\(id)", w: w, h: h)
    }

    private static func seedLargeCatalogIfNeeded() {
        let liveCount = 300 * catalogScale, vodCount = 700 * catalogScale, seriesCount = 200 * catalogScale
        do {
            let existing = try AppDatabase.shared.writeSync { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM vodStream WHERE playlistId = ?", arguments: [demoPlaylistId]) ?? 0
            }
            if existing == vodCount { return }
            try AppDatabase.shared.writeSync { db in
                try? db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [demoPlaylistId])
                try insertDemoPlaylist(db: db, playlistId: demoPlaylistId)

                func categories(_ type: String, _ count: Int, _ label: String) throws -> [String] {
                    var ids: [String] = []
                    for i in 0..<count {
                        let id = "\(type)-cat-\(i)"
                        try DBCategory(id: id, name: "\(label) \(nouns[i % nouns.count]) \(i + 1)", parentId: nil, type: type, sortIndex: i, playlistId: demoPlaylistId).insert(db)
                        ids.append(id)
                    }
                    return ids
                }
                /// Uneven category sizes: a few categories are much larger than the rest.
                func bucket(_ i: Int, _ cats: [String]) -> String {
                    let h = (i &* 2654435761) % 97
                    let big = max(1, cats.count / 10)
                    let idx = h < 45 ? (i % big) : (i % cats.count)
                    return cats[idx]
                }

                let liveCats = try categories("live", min(400, 20 + catalogScale), "Channels")
                for i in 0..<liveCount {
                    try DBLiveStream(
                        streamId: 100_000 + i,
                        name: "\(nouns[i % nouns.count]) TV \(i + 1) HD",
                        streamIcon: artwork("live", i, w: 200, h: 200),
                        epgChannelId: nil,
                        categoryId: bucket(i, liveCats),
                        sortIndex: i,
                        playlistId: demoPlaylistId
                    ).insert(db)
                }

                let vodCats = try categories("vod", min(400, 30 + catalogScale), "Movies")
                for i in 0..<vodCount {
                    let rating = String(format: "%.1f", 4.0 + Double(i % 55) / 10.0)
                    try DBVODStream(
                        streamId: 1_000_000 + i,
                        name: title(i),
                        streamIcon: artwork("vod", i, w: 400, h: 600),
                        categoryId: bucket(i, vodCats),
                        rating: rating,
                        containerExtension: i % 3 == 0 ? "mkv" : "mp4",
                        plot: "A captivating placeholder synopsis for demo purposes.",
                        releaseDate: String(1980 + i % 45),
                        rating5Based: (Double(rating) ?? 0) / 2,
                        metadataLoaded: true,
                        added: String(1_700_000_000 + i * 37),
                        sortIndex: i,
                        playlistId: demoPlaylistId
                    ).insert(db)
                }

                let seriesCats = try categories("series", min(300, 15 + catalogScale), "Series")
                for i in 0..<seriesCount {
                    let rating = String(format: "%.1f", 5.0 + Double(i % 45) / 10.0)
                    try DBSeries(
                        seriesId: 2_000_000 + i,
                        name: title(i + 17),
                        cover: artwork("series", i, w: 400, h: 600),
                        plot: "An engaging placeholder description for demo purposes.",
                        releaseDate: String(1995 + i % 30),
                        rating: rating,
                        rating5Based: (Double(rating) ?? 0) / 2,
                        categoryId: bucket(i, seriesCats),
                        sortIndex: i,
                        seasonsLoaded: false,
                        playlistId: demoPlaylistId
                    ).insert(db)
                }

                for i in 0..<8 {
                    let sid = 1_000_000 + i * 11
                    try DBWatchHistory(
                        id: "\(demoPlaylistId)_vod_\(sid)",
                        playlistId: demoPlaylistId,
                        streamId: String(sid),
                        type: "vod",
                        lastTimeMs: 600_000 + i * 240_000,
                        durationMs: 6_000_000,
                        lastWatchedAt: Date().addingTimeInterval(TimeInterval(-i * 3600)),
                        seriesId: nil,
                        title: title(i * 11),
                        secondaryTitle: nil,
                        imageURL: artwork("vod", i * 11, w: 400, h: 600),
                        containerExtension: "mp4"
                    ).insert(db)
                }
                for i in 0..<24 {
                    try DBFavorite(streamId: 1_000_000 + i * 5, playlistId: demoPlaylistId, type: "vod").insert(db)
                    try DBFavorite(streamId: 100_000 + i * 5, playlistId: demoPlaylistId, type: "live").insert(db)
                }
            }
        } catch {
            Log.error("MockFixture", "large catalog seeding failed: \(error.localizedDescription)")
        }
    }

    /// Deterministic, copyright-safe placeholder image URLs.
    /// picsum.photos serves CC0 photos and accepts a seed string for stability.
    private static func posterURL(seed: String, w: Int, h: Int) -> String {
        "https://picsum.photos/seed/\(seed)/\(w)/\(h)"
    }

    // MARK: - Playback

    /// Apple's BipBop HLS test stream — long-lived, designed for sample
    /// playback. Cookie/UA free, no 403. Ten minutes long, which is what the
    /// seeded watch positions are measured against.
    static let demoStreamURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
    static let demoStreamDurationMs = 600_000

    /// Substituted for any VOD/series playback request made against a fixture
    /// playlist so we can drive the player in screenshots without touching
    /// copyrighted streams (or the placeholder host, which serves none).
    static func demoPlaybackURL(playlistId: UUID) -> URL? {
        guard isActive else { return nil }
        return fixtureStreamURL(playlistId: playlistId)
    }

    /// The demo stream for a fixture playlist, nil for any other playlist.
    static func fixtureStreamURL(playlistId: UUID) -> URL? {
        guard fixturePlaylistIds.contains(playlistId) else { return nil }
        return URL(string: demoStreamURL)
    }
}
