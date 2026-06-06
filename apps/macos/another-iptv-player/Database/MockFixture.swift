import Foundation
import GRDB

/// Seeds the shared database with placeholder content so App Store screenshots
/// can be captured without a real (copyrighted) IPTV playlist. Activated only
/// when the app is launched with `-UITests 1` (fastlane snapshot run).
enum MockFixture {

    static let isActive: Bool = {
        let args = CommandLine.arguments
        if args.contains("-UITests") { return true }
        if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "YES" {
            return true
        }
        return false
    }()

    static let demoPlaylistId: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Reseeds the demo playlist synchronously so the UI shows populated
    /// data the moment the dashboard appears. Safe to call once from
    /// `App.init`. No-ops when not in UITest mode.
    static func seedIfNeeded() {
        guard isActive else { return }

        do {
            try AppDatabase.shared.writeSync { db in
                try? db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [demoPlaylistId])
                try insertDemoPlaylist(db: db)
                try insertLive(db: db)
                try insertVOD(db: db)
                try insertSeries(db: db)
            }
        } catch {
            Log.error("MockFixture", "seeding failed: \(error.localizedDescription)")
        }

        UserDefaults.standard.set(demoPlaylistId.uuidString, forKey: "lastPlaylistId")
    }

    private static func insertDemoPlaylist(db: Database) throws {
        var playlist = Playlist(
            id: demoPlaylistId,
            name: "Demo Playlist",
            serverURL: "https://example.com",
            username: "demo",
            password: "demo"
        )
        try playlist.insert(db)
    }

    private static func insertLive(db: Database) throws {
        let categories: [(String, String)] = [
            ("live-news", "News"),
            ("live-sports", "Sports"),
            ("live-entertainment", "Entertainment"),
            ("live-kids", "Kids"),
        ]
        for (idx, (id, name)) in categories.enumerated() {
            var c = DBCategory(id: id, name: name, parentId: nil, type: "live", sortIndex: idx, playlistId: demoPlaylistId)
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
            var s = DBLiveStream(
                streamId: sid,
                name: name,
                streamIcon: posterURL(seed: "live-\(sid)", w: 200, h: 200),
                epgChannelId: nil,
                categoryId: cat,
                sortIndex: idx,
                playlistId: demoPlaylistId
            )
            try s.insert(db)
        }
    }

    private static func insertVOD(db: Database) throws {
        let categories: [(String, String)] = [
            ("vod-action",   "Action"),
            ("vod-drama",    "Drama"),
            ("vod-comedy",   "Comedy"),
            ("vod-scifi",    "Sci-Fi"),
            ("vod-doc",      "Documentary"),
        ]
        for (idx, (id, name)) in categories.enumerated() {
            var c = DBCategory(id: id, name: name, parentId: nil, type: "vod", sortIndex: idx, playlistId: demoPlaylistId)
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
            var s = DBVODStream(
                streamId: sid,
                name: name,
                streamIcon: posterURL(seed: "vod-\(sid)", w: 400, h: 600),
                categoryId: cat,
                rating: rating,
                containerExtension: "mp4",
                plot: "A captivating placeholder synopsis for demo purposes.",
                releaseDate: year,
                rating5Based: rating.flatMap { Double($0) }.map { $0 / 2 },
                metadataLoaded: true,
                sortIndex: idx,
                playlistId: demoPlaylistId
            )
            try s.insert(db)
        }
    }

    private static func insertSeries(db: Database) throws {
        let categories: [(String, String)] = [
            ("series-drama",    "Drama"),
            ("series-thriller", "Thriller"),
            ("series-comedy",   "Comedy"),
            ("series-doc",      "Documentary"),
        ]
        for (idx, (id, name)) in categories.enumerated() {
            var c = DBCategory(id: id, name: name, parentId: nil, type: "series", sortIndex: idx, playlistId: demoPlaylistId)
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
            var s = DBSeries(
                seriesId: sid,
                name: name,
                cover: posterURL(seed: "series-\(sid)", w: 400, h: 600),
                plot: "An engaging placeholder description for demo purposes.",
                releaseDate: "2024",
                rating: rating,
                rating5Based: rating.flatMap { Double($0) }.map { $0 / 2 },
                categoryId: cat,
                sortIndex: idx,
                seasonsLoaded: false,
                playlistId: demoPlaylistId
            )
            try s.insert(db)
        }
    }

    /// Deterministic, copyright-safe placeholder image URLs.
    /// picsum.photos serves CC0 photos and accepts a seed string for stability.
    private static func posterURL(seed: String, w: Int, h: Int) -> String {
        "https://picsum.photos/seed/\(seed)/\(w)/\(h)"
    }

    /// Big Buck Bunny — Creative Commons short film, the de-facto industry
    /// reference video, hosted by Google for sample use. Substituted for any
    /// VOD/series playback request made against the demo playlist so we can
    /// drive the player in screenshots without touching copyrighted streams.
    static func demoPlaybackURL(playlistId: UUID) -> URL? {
        guard isActive, playlistId == demoPlaylistId else { return nil }
        // Apple's BipBop HLS test stream — long-lived, designed for sample
        // playback. Cookie/UA free, no 403.
        return URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")
    }
}
