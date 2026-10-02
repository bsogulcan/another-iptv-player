import Foundation
import GRDB
import Testing
@testable import another_iptv_player

@Suite("EPG guide performance guards")
struct EPGGuidePerformanceTests {

    @Test
    func groupsLargeGuideByChannelWithoutLosingRows() {
        let channelCount = 1_000
        let programmesPerChannel = 30
        var rows: [EPGGuideProgrammeRecord] = []
        rows.reserveCapacity(channelCount * programmesPerChannel)
        for index in 0..<(channelCount * programmesPerChannel) {
            rows.append(EPGGuideProgrammeRecord(
                channelKey: "channel-\(index % channelCount)",
                startTs: Int64(index * 1_800),
                stopTs: Int64(index * 1_800 + 1_800),
                title: "Programme \(index)"
            ))
        }

        let grouped = EPGStore.groupGuideProgrammes(rows)

        #expect(grouped.count == channelCount)
        #expect(grouped.values.reduce(0) { $0 + $1.count } == rows.count)
    }

    @Test
    func nowIndexKeepsLatestStartedProgrammeAndFoldsAliases() {
        // Deliberately unordered: the minute query no longer sorts its rows.
        let rows = [
            EPGGuideProgrammeRecord(channelKey: "news", startTs: 3_600, stopTs: 7_200, title: "Bulletin"),
            EPGGuideProgrammeRecord(channelKey: "sport", startTs: 3_000, stopTs: 9_000, title: "Match"),
            EPGGuideProgrammeRecord(channelKey: "news", startTs: 0, stopTs: 86_400, title: "Placeholder")
        ]

        let index = EPGStore.makeNowIndex(rows, resolution: [
            "news hd": "news",       // alias of a stored key
            "sport": "news",         // a stored key is never overwritten by an alias
            "radio": "no-guide"      // alias whose stored key has nothing on air
        ])

        #expect(index.count == 3)
        #expect(index["news"]?.now?.title == "Bulletin")
        #expect(index["news hd"]?.now?.title == "Bulletin")
        #expect(index["sport"]?.now?.title == "Match")
        #expect(index["radio"] == nil)
        #expect(index["news"]?.now?.start == Date(timeIntervalSince1970: 3_600))
        #expect(index["news"]?.now?.stop == Date(timeIntervalSince1970: 7_200))
    }

    @Test
    func nowIndexQueryReturnsOnlyProgrammesOnAir() async throws {
        let database = AppDatabase.empty()
        let playlistId = UUID()
        let otherPlaylistId = UUID()
        let now: Int64 = 1_800_000_000

        // (playlist, channelKey, start offset, stop offset, title), offsets from `now`.
        let programmes: [(UUID, String, Int64, Int64, String)] = [
            (playlistId, "news", -7_200, -3_600, "Earlier"),
            (playlistId, "news", -600, 600, "Bulletin"),
            (playlistId, "news", 600, 4_200, "Later"),
            (playlistId, "film", -3_600, 82_800, "Placeholder"),
            (playlistId, "film", -60, 1_800, "Film"),
            (playlistId, "edge", -1_800, 0, "Just ended"),
            (playlistId, "edge", 0, 1_800, "Just started"),
            (playlistId, "upcoming", 60, 3_660, "Not yet"),
            (otherPlaylistId, "news", -600, 600, "Other playlist")
        ]

        try await database.write { db in
            for id in [playlistId, otherPlaylistId] {
                try db.execute(
                    sql: """
                        INSERT INTO playlist (id, name, serverURL, username, password)
                        VALUES (?, 'Test', 'https://example.com', '', '')
                        """,
                    arguments: [id]
                )
            }
            for (id, channelKey, start, stop, title) in programmes {
                try db.execute(
                    sql: """
                        INSERT INTO epgProgramme
                            (playlistId, channelKey, startTs, stopTs, title)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [id, channelKey, now + start, now + stop, title]
                )
            }
        }

        let index = try await database.read { db in
            try EPGStore.fetchNowIndex(db, playlistId: playlistId, now: now,
                                       resolution: ["news hd": "news"])
        }

        #expect(index.count == 4)
        #expect(index["news"]?.now?.title == "Bulletin")
        #expect(index["news hd"]?.now?.title == "Bulletin")
        #expect(index["film"]?.now?.title == "Film")
        #expect(index["edge"]?.now?.title == "Just started")
        #expect(index["upcoming"] == nil)
    }

    @Test
    func layoutsAreStoredOnlyForChannelsWithGuideData() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(86_400)
        let programme = EPGProgramme(
            channelKey: "with-guide",
            title: "News",
            start: start.addingTimeInterval(3_600),
            stop: start.addingTimeInterval(7_200)
        )
        var wanted = Set((0..<20_000).map { "no-data-\($0)" })
        wanted.insert("with-guide")

        let layouts = EPGGuideViewModel.makeLayouts(
            byKey: [
                "with-guide": [programme],
                "stale-channel": [programme]
            ],
            wantedKeys: wanted,
            dayStart: start,
            dayEnd: end,
            hourWidth: 120,
            version: 1
        )

        #expect(layouts.count == 1)
        #expect(layouts["with-guide"]?.cells.contains { $0.programme?.title == "News" } == true)
        #expect(layouts["stale-channel"] == nil)
    }

    @Test
    func databaseCreatesAtomicRefreshStagingTables() async throws {
        let database = AppDatabase.empty()
        let names = try await database.read { db in
            try Set(String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name IN ('epgProgrammeStaging', 'epgChannelStaging')
                """))
        }

        #expect(names == ["epgProgrammeStaging", "epgChannelStaging"])
    }

    @Test
    func publishingStagedGuideReplacesLiveGuideAndClearsStaging() async throws {
        let database = AppDatabase.empty()
        let playlistId = UUID()

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, serverURL, username, password)
                    VALUES (?, 'Test', 'https://example.com', '', '')
                    """,
                arguments: [playlistId]
            )
            try db.execute(
                sql: """
                    INSERT INTO epgProgramme
                        (playlistId, channelKey, startTs, stopTs, title)
                    VALUES (?, 'news', 100, 200, 'Old programme')
                    """,
                arguments: [playlistId]
            )
            try db.execute(
                sql: """
                    INSERT INTO epgProgrammeStaging
                        (playlistId, channelKey, startTs, stopTs, title)
                    VALUES (?, 'news', 200, 300, 'New programme')
                    """,
                arguments: [playlistId]
            )

            try EPGRefreshCoordinator.publishStagedGuide(in: db, playlistId: playlistId)
        }

        let result = try await database.read { db in
            let liveTitles = try String.fetchAll(
                db,
                sql: "SELECT title FROM epgProgramme WHERE playlistId = ? ORDER BY startTs",
                arguments: [playlistId]
            )
            let stagedCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM epgProgrammeStaging WHERE playlistId = ?",
                arguments: [playlistId]
            ) ?? -1
            return (liveTitles, stagedCount)
        }

        #expect(result.0 == ["New programme"])
        #expect(result.1 == 0)
    }
}
