import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// Regression locks for the live player's channel banner, its "next programme" lookup
/// and the short-EPG fallback's request memory.
/// (Source: ios-player-airplay-review.md, live-tv-ux-2 and live-tv-ux-7.)

// MARK: - Next programme lookup

struct PlayerNextProgrammeQueryTests {
    /// One guide row: (playlist, channelKey, start offset, stop offset, title), offsets
    /// in seconds from `base`.
    private typealias Row = (UUID, String, Int64, Int64, String)

    private static func makeDatabase(
        base: Int64, playlists: [UUID], programmes: [Row]
    ) async throws -> AppDatabase {
        let database = AppDatabase.empty()
        try await database.write { db in
            for id in playlists {
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
                    arguments: [id, channelKey, base + start, base + stop, title]
                )
            }
        }
        return database
    }

    @Test
    func returnsTheFirstProgrammeAfterTheOneOnAir() async throws {
        let base: Int64 = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(base))
        let onAirStart = now.addingTimeInterval(-600)
        let playlistId = UUID()
        let otherPlaylistId = UUID()
        let database = try await Self.makeDatabase(
            base: base,
            playlists: [playlistId, otherPlaylistId],
            programmes: [
                (playlistId, "news", -7_200, -600, "Earlier"),
                (playlistId, "news", -600, 600, "Bulletin"),
                (playlistId, "news", 600, 4_200, "Weather"),
                (playlistId, "news", 4_200, 7_800, "Late film"),
                (playlistId, "sport", 60, 3_660, "Match"),
                (otherPlaylistId, "news", 30, 900, "Other playlist")
            ]
        )

        let next = try await database.read { db in
            try PlayerNextProgrammeQuery.fetch(
                db, playlistId: playlistId, channelKey: "news", after: onAirStart, now: now
            )
        }

        #expect(next?.title == "Weather")
        #expect(next?.channelKey == "news")
        #expect(next?.start == now.addingTimeInterval(600))
        #expect(next?.stop == now.addingTimeInterval(4_200))
    }

    /// Overlapping guide data can leave a short entry that started after the programme
    /// on air and is already over; it is not "next".
    @Test
    func skipsEntriesThatHaveAlreadyEnded() async throws {
        let base: Int64 = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(base))
        let onAirStart = now.addingTimeInterval(-3_600)
        let playlistId = UUID()
        let database = try await Self.makeDatabase(
            base: base,
            playlists: [playlistId],
            programmes: [
                (playlistId, "film", -3_600, 3_600, "Film"),
                (playlistId, "film", -1_800, -900, "Stale filler"),
                (playlistId, "film", 3_600, 7_200, "Documentary")
            ]
        )

        let next = try await database.read { db in
            try PlayerNextProgrammeQuery.fetch(
                db, playlistId: playlistId, channelKey: "film", after: onAirStart, now: now
            )
        }

        #expect(next?.title == "Documentary")
    }

    @Test
    func returnsNothingWhenTheGuideEndsWithTheProgrammeOnAir() async throws {
        let base: Int64 = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(base))
        let onAirStart = now.addingTimeInterval(-600)
        let playlistId = UUID()
        let database = try await Self.makeDatabase(
            base: base,
            playlists: [playlistId],
            programmes: [(playlistId, "news", -600, 600, "Bulletin")]
        )

        let next = try await database.read { db in
            try PlayerNextProgrammeQuery.fetch(
                db, playlistId: playlistId, channelKey: "news", after: onAirStart, now: now
            )
        }

        #expect(next == nil)
    }
}

// MARK: - Banner model

@MainActor
struct PlayerChannelBannerModelTests {
    private static func programme(
        _ channelKey: String, start: TimeInterval, stop: TimeInterval, title: String
    ) -> EPGProgramme {
        EPGProgramme(
            channelKey: channelKey,
            title: title,
            start: Date(timeIntervalSince1970: start),
            stop: Date(timeIntervalSince1970: stop)
        )
    }

    @Test
    func showMakesTheBannerVisibleAndHideClearsIt() {
        let model = PlayerChannelBannerModel()
        #expect(!model.isVisible)

        model.show()
        #expect(model.isVisible)
        // A second zap inside the window keeps the same banner up.
        model.show()
        #expect(model.isVisible)

        model.hide()
        #expect(!model.isVisible)
    }

    /// The banner is a transient cue: about three seconds, not a sticky overlay.
    @Test
    func bannerStaysUpForAboutThreeSeconds() {
        #expect(PlayerChannelBannerModel.visibleNanoseconds == 3_000_000_000)
    }

    /// After a zap the previous channel's "next" value is still stored until the new
    /// lookup returns. It must not be offered under the new channel's programme.
    @Test
    func nextIsOfferedOnlyForTheProgrammeItFollows() {
        let model = PlayerChannelBannerModel()
        let onAir = Self.programme("news", start: 1_000, stop: 2_000, title: "Bulletin")
        let following = Self.programme("news", start: 2_000, stop: 3_000, title: "Weather")
        model.setNextProgramme(following)

        #expect(model.next(after: onAir) == following)
        // Another channel.
        #expect(model.next(after: Self.programme("sport", start: 1_000, stop: 2_000, title: "Match")) == nil)
        // The stored value became the programme on air (boundary passed, lookup pending).
        #expect(model.next(after: following) == nil)
        #expect(model.next(after: nil) == nil)
    }

    @Test
    func loadNextReadsTheGuideAndClearsWithoutAProgramme() async throws {
        let playlistId = UUID()
        let database = AppDatabase.empty()
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, serverURL, username, password)
                    VALUES (?, 'Test', 'https://example.com', '', '')
                    """,
                arguments: [playlistId]
            )
            // Far in the future, so the row is "not ended" whenever the test runs.
            try db.execute(
                sql: """
                    INSERT INTO epgProgramme
                        (playlistId, channelKey, startTs, stopTs, title)
                    VALUES (?, 'news', 32000000000, 32000003600, 'Weather')
                    """,
                arguments: [playlistId]
            )
        }
        let onAir = Self.programme("news", start: 1_000, stop: 2_000, title: "Bulletin")
        let model = PlayerChannelBannerModel()

        await model.loadNext(after: onAir, playlistId: playlistId, in: database)
        #expect(model.nextProgramme?.title == "Weather")
        #expect(model.next(after: onAir)?.title == "Weather")

        await model.loadNext(after: nil, playlistId: playlistId, in: database)
        #expect(model.nextProgramme == nil)
    }
}

// MARK: - Short-EPG fallback request memory

@MainActor
struct LiveShortEPGAttemptsTests {
    @Test
    func aChannelIsAskedOncePerRetryInterval() {
        let attempts = LiveShortEPGAttempts()
        let playlistId = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(attempts.claim(playlistId: playlistId, streamId: 7, now: start))
        // Zapping past the same channel again does not ask the panel again.
        #expect(!attempts.claim(playlistId: playlistId, streamId: 7, now: start.addingTimeInterval(60)))
        #expect(!attempts.claim(
            playlistId: playlistId, streamId: 7,
            now: start.addingTimeInterval(LiveShortEPGAttempts.retryInterval - 1)
        ))
        // Once the interval has passed the channel may be asked again, and that attempt
        // starts a new interval.
        let later = start.addingTimeInterval(LiveShortEPGAttempts.retryInterval)
        #expect(attempts.claim(playlistId: playlistId, streamId: 7, now: later))
        #expect(!attempts.claim(playlistId: playlistId, streamId: 7, now: later.addingTimeInterval(1)))
    }

    @Test
    func channelsAndPlaylistsAreTrackedSeparately() {
        let attempts = LiveShortEPGAttempts()
        let playlistId = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(attempts.claim(playlistId: playlistId, streamId: 7, now: now))
        #expect(attempts.claim(playlistId: playlistId, streamId: 8, now: now))
        #expect(attempts.claim(playlistId: UUID(), streamId: 7, now: now))
    }
}
