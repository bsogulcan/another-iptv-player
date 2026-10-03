import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// What the UI-test fixture writes, seeded into an in-memory database.
///
/// The demo mode is pinned row for row, because the App Store screenshots are
/// taken on it. For the rich mode the tests hold the promises UI tests rely on:
/// the counts, that every row points at something that exists, and that the guide
/// has a programme on air at the moment it was seeded.
@Suite("Mock fixture")
struct MockFixtureTests {

    private let demoId = MockFixture.demoPlaylistId
    private let m3uId = MockFixture.m3uPlaylistId

    private let tables = [
        "playlist", "category", "liveStream", "vodStream", "series", "season", "episode",
        "favorite", "watchHistory", "downloadedItem", "m3uChannel", "m3uFavorite",
        "epgChannel", "epgProgramme", "epgSource",
    ]

    private func seeded(_ mode: MockFixture.Mode, now: Date = Date(), into database: AppDatabase = .empty()) throws -> AppDatabase {
        try database.writeSync { db in
            try MockFixture.seed(mode, db: db, playlistId: demoId, m3uPlaylistId: m3uId, now: now)
        }
        return database
    }

    /// A synchronous read. Called from here, `read` resolves to its synchronous
    /// form even when the test itself is async.
    private func read<T>(_ database: AppDatabase, _ body: (Database) throws -> T) throws -> T {
        try database.reader.read(body)
    }

    private func rowCounts(_ database: AppDatabase) throws -> [String: Int] {
        try read(database) { db in
            var counts: [String: Int] = [:]
            for table in tables {
                counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
            return counts
        }
    }

    private func count(_ sql: String, _ arguments: StatementArguments = [], in database: AppDatabase) throws -> Int {
        try read(database) { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    /// An afternoon, so "now" lies well inside the seeded day whatever the time zone.
    private var afternoon: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)).addingTimeInterval(14.5 * 3_600)
    }

    private func makeDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "MockFixtureTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private let demoCounts = [
        "playlist": 1, "category": 13, "liveStream": 13, "vodStream": 12, "series": 8,
        "season": 0, "episode": 0, "favorite": 0, "watchHistory": 0, "downloadedItem": 0,
        "m3uChannel": 0, "m3uFavorite": 0, "epgChannel": 0, "epgProgramme": 0, "epgSource": 1,
    ]

    // MARK: Demo mode

    @Test
    func demoModeSeedsTheSmallCatalogAndOneGuideBookkeepingRow() throws {
        let database = try seeded(.demo)
        #expect(try rowCounts(database) == demoCounts)

        try read(database) { db in
            let playlist = try #require(try Playlist.fetchOne(db, key: demoId))
            #expect(playlist.name == "Demo Playlist")
            #expect(playlist.kind == .xtream)

            let channels = try DBLiveStream.order(Column("sortIndex")).fetchAll(db)
            #expect(channels.first?.name == "World News 24")
            #expect(channels.allSatisfy { $0.epgChannelId == nil && $0.tvArchive == 0 })

            let films = try DBVODStream.order(Column("sortIndex")).fetchAll(db)
            #expect(films.first?.name == "Midnight Horizon")
            #expect(films.allSatisfy { $0.added == nil && $0.genre == nil && $0.metadataLoaded })
            if MockFixture.imageBase == nil {
                #expect(films.first?.streamIcon == "https://picsum.photos/seed/vod-1001/400/600")
                #expect(channels.first?.streamIcon == "https://picsum.photos/seed/live-101/200/200")
            }

            let series = try DBSeries.order(Column("sortIndex")).fetchAll(db)
            #expect(series.first?.name == "Northern Lights")
            #expect(series.allSatisfy { !$0.seasonsLoaded && $0.lastModified == nil })
        }
    }

    /// Without the bookkeeping row every launch started a guide download from the
    /// placeholder host.
    @Test
    func demoModeLeavesNoGuideRefreshToStart() async throws {
        let now = Date()
        let database = try seeded(.demo, now: now)
        let (playlist, source) = try read(database) { db in
            (try Playlist.fetchOne(db, key: demoId), try DBEPGSource.fetchOne(db, key: demoId))
        }
        let stamped = try #require(source?.lastSuccessAt)
        #expect(abs(stamped.timeIntervalSince(now)) < 1)
        #expect(source?.sourceType == EPGSourceType.xtreamXMLTV.rawValue)
        #expect(source?.programmeCount == 0)

        let (defaults, suite) = try makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = EPGStore(database: database, defaults: defaults)
        await store.refreshIfStale(playlist: try #require(playlist))
        #expect(store.refreshState[demoId] == nil)
    }

    @Test
    func demoModeDropsThePlaylistARichRunLeft() throws {
        let database = try seeded(.rich)
        #expect(try rowCounts(database)["playlist"] == 2)

        _ = try seeded(.demo, into: database)
        #expect(try rowCounts(database) == demoCounts)
    }

    // MARK: Rich mode: counts

    @Test
    func richModeRowCounts() throws {
        let database = try seeded(.rich, now: afternoon)
        let counts = try rowCounts(database)

        #expect(counts["playlist"] == 2)
        #expect(counts["epgSource"] == 2)
        #expect(counts["downloadedItem"] == 0)
        // Demo 13 + ten named channels + five outside every category.
        #expect(counts["liveStream"] == 28)
        // Demo 12 + ten named films + five outside every category + the long category.
        #expect(counts["vodStream"] == 27 + MockFixture.Rich.largeFilmCategoryCount)
        // Demo 8 + seven named series + five outside every category.
        #expect(counts["series"] == 20)
        // Demo 4 + 5 + 4, plus two live, three film and two series categories.
        #expect(counts["category"] == 20)
        #expect(counts["season"] == 4)
        #expect(counts["episode"] == 28)
        #expect(counts["favorite"] == 7)
        // Four on the Xtream playlist, one on the M3U playlist.
        #expect(counts["watchHistory"] == 5)
        #expect(counts["m3uChannel"] == MockFixture.M3U.channelCount)
        #expect(counts["m3uChannel"] == 440)
        #expect(counts["m3uFavorite"] == 2)
        #expect(counts["epgChannel"] == 10 + MockFixture.M3U.guideChannelCount)

        #expect(try count("SELECT COUNT(*) FROM favorite WHERE playlistId = ? AND type = 'live'", [demoId], in: database) == 2)
        #expect(try count("SELECT COUNT(*) FROM favorite WHERE playlistId = ? AND type = 'vod'", [demoId], in: database) == 3)
        #expect(try count("SELECT COUNT(*) FROM favorite WHERE playlistId = ? AND type = 'series'", [demoId], in: database) == 2)
        #expect(try count("SELECT COUNT(*) FROM watchHistory WHERE playlistId = ?", [demoId], in: database) == 4)
        #expect(try count("SELECT COUNT(*) FROM watchHistory WHERE playlistId = ?", [m3uId], in: database) == 1)
    }

    /// A relaunch reseeds; nothing may pile up, and the same seed time gives the same rows.
    @Test
    func richSeedingIsRepeatable() throws {
        let now = afternoon
        let first = try seeded(.rich, now: now)
        let counts = try rowCounts(first)
        _ = try seeded(.rich, now: now, into: first)
        #expect(try rowCounts(first) == counts)

        let second = try seeded(.rich, now: now)
        let films: (AppDatabase) throws -> [DBVODStream] = { database in
            try read(database) { db in try DBVODStream.order(Column("streamId")).fetchAll(db) }
        }
        let programmes: (AppDatabase) throws -> [DBEPGProgramme] = { database in
            try read(database) { db in
                try DBEPGProgramme.order(Column("playlistId"), Column("channelKey"), Column("startTs")).fetchAll(db)
            }
        }
        let channels: (AppDatabase) throws -> [DBM3UChannel] = { database in
            try read(database) { db in try DBM3UChannel.order(Column("sortIndex")).fetchAll(db) }
        }
        #expect(try films(first) == films(second))
        #expect(try programmes(first) == programmes(second))
        #expect(try channels(first) == channels(second))
    }

    // MARK: Rich mode: catalog

    @Test
    func richCatalogHasTheShapesTheBrowseScreensNeed() throws {
        let database = try seeded(.rich, now: afternoon)
        try read(database) { db in
            let categories = try DBCategory.filter(Column("playlistId") == demoId).fetchAll(db)
            let channels = try DBLiveStream.filter(Column("playlistId") == demoId).fetchAll(db)
            let films = try DBVODStream.filter(Column("playlistId") == demoId).fetchAll(db)
            let series = try DBSeries.filter(Column("playlistId") == demoId).fetchAll(db)

            func categoryIds(_ type: String) -> Set<String> {
                Set(categories.filter { $0.type == type }.map(\.id))
            }
            let liveCategories = categoryIds("live"), filmCategories = categoryIds("vod"), seriesCategories = categoryIds("series")

            // One long category, one empty category per type.
            #expect(films.filter { $0.categoryId == MockFixture.Rich.largeFilmCategoryId }.count == 300)
            #expect(liveCategories.contains(MockFixture.Rich.emptyLiveCategoryId))
            #expect(filmCategories.contains(MockFixture.Rich.emptyFilmCategoryId))
            #expect(seriesCategories.contains(MockFixture.Rich.emptySeriesCategoryId))
            #expect(!channels.contains { $0.categoryId == MockFixture.Rich.emptyLiveCategoryId })
            #expect(!films.contains { $0.categoryId == MockFixture.Rich.emptyFilmCategoryId })
            #expect(!series.contains { $0.categoryId == MockFixture.Rich.emptySeriesCategoryId })

            // Five per type outside every category, some with no id and some with an unknown one.
            func orphans(_ ids: [String?], _ valid: Set<String>) -> [String?] {
                ids.filter { $0 == nil || !valid.contains($0!) }
            }
            for found in [orphans(channels.map(\.categoryId), liveCategories),
                          orphans(films.map(\.categoryId), filmCategories),
                          orphans(series.map(\.categoryId), seriesCategories)] {
                #expect(found.count == MockFixture.Rich.uncategorizedCount)
                #expect(found.contains { $0 == nil })
                #expect(found.contains { $0 != nil })
            }

            // "Recently added" has exactly one order.
            let added = films.compactMap { $0.added.flatMap { Int($0) } }
            #expect(added.count == films.count)
            #expect(Set(added).count == films.count)
            let newestFilms = films.sorted { Int($0.added!)! > Int($1.added!)! }.prefix(10).map(\.streamId)
            #expect(newestFilms == MockFixture.Rich.newestFilmIds)

            let modified = series.compactMap { $0.lastModified.flatMap { Int($0) } }
            #expect(modified.count == series.count)
            #expect(Set(modified).count == series.count)
            let newestSeries = series.sorted { Int($0.lastModified!)! > Int($1.lastModified!)! }.prefix(10).map(\.seriesId)
            #expect(newestSeries == MockFixture.Rich.newestSeriesIds)

            // Exactly one channel without a logo.
            #expect(channels.filter { $0.streamIcon == nil }.map(\.streamId)
                    == (MockFixture.imageBase == "none" ? channels.map(\.streamId) : [MockFixture.Rich.channelWithoutLogoId]))

            // Names that wrap, and one of about sixty characters, in every type.
            let longest = try #require(films.first { $0.streamId == MockFixture.Rich.longestTitleFilmId })
            #expect((58...62).contains(longest.name.count))
            #expect(films.filter { (40...57).contains($0.name.count) }.count >= 2)
            #expect(channels.contains { (58...62).contains($0.name.count) })
            #expect(series.contains { (58...62).contains($0.name.count) })

            // Names an ASCII-only fold would miss, plus right-to-left and Cyrillic ones.
            let names = channels.map(\.name) + films.map(\.name) + series.map(\.name)
            for exact in ["IŞIK TV", "İZLE", "Çocuk"] {
                #expect(channels.contains { $0.name == exact })
            }
            for (query, expected) in [("isik", "IŞIK TV"), ("izle", "İZLE"), ("cocuk", "Çocuk")] {
                #expect(names.filter { CatalogTextSearch.matches(search: query, text: $0) }.contains(expected))
            }
            func uses(_ range: ClosedRange<UInt32>) -> (String) -> Bool {
                { $0.unicodeScalars.contains { range.contains($0.value) } }
            }
            #expect(channels.map(\.name).contains(where: uses(0x0600...0x06FF)))
            #expect(films.map(\.name).contains(where: uses(0x0600...0x06FF)))
            #expect(series.map(\.name).contains(where: uses(0x0600...0x06FF)))
            #expect(channels.map(\.name).contains(where: uses(0x0400...0x04FF)))
            #expect(films.map(\.name).contains(where: uses(0x0400...0x04FF)))
            #expect(series.map(\.name).contains(where: uses(0x0400...0x04FF)))

            // Opening a film must not ask the panel for its details.
            #expect(films.allSatisfy { $0.metadataLoaded })
        }
    }

    @Test
    func seasonsAndEpisodesAreCompleteForTwoSeries() throws {
        let database = try seeded(.rich, now: afternoon)
        try read(database) { db in
            let loaded = try DBSeries
                .filter(Column("playlistId") == demoId && Column("seasonsLoaded") == true)
                .fetchAll(db)
            #expect(Set(loaded.map(\.seriesId)) == [MockFixture.Rich.seriesWithSeasonsId, MockFixture.Rich.seriesWithOneSeasonId])

            let seasons = try DBSeason.order(Column("seriesId"), Column("seasonNumber")).fetchAll(db)
            let episodes = try DBEpisode.fetchAll(db)
            let seasonIds = Set(seasons.map(\.id))

            // Every episode belongs to a seeded season, every season to a loaded series.
            #expect(episodes.allSatisfy { seasonIds.contains($0.seasonId) })
            #expect(seasons.allSatisfy { season in loaded.contains { $0.seriesId == season.seriesId } })
            #expect(seasons.allSatisfy { $0.playlistId == demoId })

            func episodeCount(_ seriesId: Int, _ number: Int) -> Int {
                let id = DBSeason.scopedId(playlistId: demoId, seriesId: seriesId, seasonNumber: number)
                return episodes.filter { $0.seasonId == id }.count
            }
            let first = MockFixture.Rich.seriesWithSeasonsId
            #expect(seasons.filter { $0.seriesId == first }.map(\.seasonNumber) == [0, 1, 2])
            #expect(seasons.first { $0.seriesId == first && $0.seasonNumber == 0 }?.name == "Specials")
            #expect(episodeCount(first, 0) == 0)
            #expect(episodeCount(first, 1) == 12)
            #expect(episodeCount(first, 2) == 12)
            let second = MockFixture.Rich.seriesWithOneSeasonId
            #expect(seasons.filter { $0.seriesId == second }.map(\.seasonNumber) == [1])
            #expect(episodeCount(second, 1) == 4)

            // Ids as the series page writes them, counts as it would store them.
            for season in seasons {
                #expect(season.id == DBSeason.scopedId(playlistId: demoId, seriesId: season.seriesId, seasonNumber: season.seasonNumber))
                #expect(season.episodeCount == episodes.filter { $0.seasonId == season.id }.count)
                #expect(season.cover != nil || MockFixture.imageBase == "none")
            }
            #expect(Set(episodes.compactMap(\.episodeId)).count == episodes.count)
            for episode in episodes {
                #expect(episode.id == DBEpisode.scopedId(playlistId: demoId, panelEpisodeId: episode.episodeId))
                #expect(episode.episodeNum != nil)
                #expect(episode.title?.isEmpty == false)
                #expect(episode.info?.isEmpty == false)
                #expect(episode.duration?.isEmpty == false)
                #expect(episode.cover != nil || MockFixture.imageBase == "none")
            }
        }
    }

    // MARK: Rich mode: guide

    @Test
    func guideWindowIsTwoDaysAroundTheSeedDayInAnyTimeZone() throws {
        for identifier in ["UTC", "Europe/Istanbul", "Asia/Kolkata", "America/Los_Angeles", "Pacific/Auckland"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: identifier))
            for offset in stride(from: 0.0, to: 24 * 3_600, by: 5_400) {
                let now = Date(timeIntervalSince1970: 1_790_000_000 + offset)
                let window = MockFixture.guideWindow(around: now, calendar: calendar)
                #expect(window.duration == 48 * 3_600)
                #expect(window.contains(now))
                #expect(window.start == calendar.startOfDay(for: now).addingTimeInterval(-12 * 3_600))
            }
        }
    }

    @Test
    func guideCoversTenDemoChannelsAroundTheSeedTime() throws {
        let now = afternoon
        let database = try seeded(.rich, now: now)
        let window = MockFixture.guideWindow(around: now)
        let keys = MockFixture.Rich.guideChannels.map { MockFixture.guideKey($0.epgId) }

        try read(database) { db in
            let channels = try DBLiveStream.filter(Column("playlistId") == demoId).fetchAll(db)
            let withGuideId = channels.filter { $0.epgChannelId != nil }
            #expect(withGuideId.count == 10)
            #expect(Set(withGuideId.map(\.streamId)) == Set(MockFixture.Rich.guideChannels.map(\.streamId)))
            for id in MockFixture.Rich.channelsWithoutGuide {
                #expect(channels.first { $0.streamId == id }?.epgChannelId == nil)
            }
            // The key a channel card looks its programme up by is the stored key.
            #expect(Set(withGuideId.compactMap { EPGChannelKey.forXtream($0) }) == Set(keys))
            #expect(keys == MockFixture.Rich.guideChannels.compactMap { EPGConstants.normalizeChannelKey($0.epgId) })
            #expect(MockFixture.Rich.guideChannels.contains { $0.epgId != MockFixture.guideKey($0.epgId) })

            let guideChannels = try DBEPGChannel.filter(Column("playlistId") == demoId).fetchAll(db)
            #expect(Set(guideChannels.map(\.channelKey)) == Set(keys))

            let programmes = try DBEPGProgramme.filter(Column("playlistId") == demoId).fetchAll(db)
            #expect(Set(programmes.map(\.channelKey)) == Set(keys))
            #expect(programmes.map(\.startTs).min() == Int64(window.start.timeIntervalSince1970))
            #expect(programmes.map(\.stopTs).max() == Int64(window.end.timeIntervalSince1970))
            #expect(programmes.allSatisfy { !$0.title.isEmpty })

            // 15, 30 and 120 minute programmes, and one day-long placeholder.
            let minutes = programmes.map { Int(($0.stopTs - $0.startTs) / 60) }
            #expect(Set(minutes) == [15, 30, 120, 24 * 60])
            #expect(minutes.filter { $0 == 24 * 60 }.count == 1)

            let source = try #require(try DBEPGSource.fetchOne(db, key: demoId))
            #expect(source.programmeCount == programmes.count)
            #expect(source.channelCount == 10)
            #expect(source.lastSuccessAt == source.fetchedAt)

            // Every guide channel has something on air at the seed time.
            let nowTs = Int64(now.timeIntervalSince1970)
            let onAir = try EPGStore.fetchNowIndex(db, playlistId: demoId, now: nowTs, resolution: [:])
            for key in keys {
                #expect(onAir[key]?.now != nil, "nothing on air for \(key)")
            }
            #expect(onAir.count == keys.count)

            // The placeholder lies under real programmes: both overlap the seed
            // time, and the on-air lookup answers with the real one.
            let placeholderId = MockFixture.Rich.placeholderGuideChannelId
            let placeholderKey = try #require(MockFixture.Rich.guideChannels.first(where: { $0.streamId == placeholderId }).map { MockFixture.guideKey($0.epgId) })
            let overlapping = programmes.filter { $0.channelKey == placeholderKey && $0.startTs <= nowTs && $0.stopTs > nowTs }
            #expect(overlapping.count == 2)
            #expect(overlapping.contains { $0.title == MockFixture.guidePlaceholderTitle })
            #expect(onAir[placeholderKey]?.now?.title != MockFixture.guidePlaceholderTitle)
            // Where the feed has nothing else, the placeholder is what is on air.
            let earlyTs = Int64(Calendar.current.startOfDay(for: now).addingTimeInterval(3_600).timeIntervalSince1970)
            let early = try EPGStore.fetchNowIndex(db, playlistId: demoId, now: earlyTs, resolution: [:])
            #expect(early[placeholderKey]?.now?.title == MockFixture.guidePlaceholderTitle)

            // One channel with an archive, and past programmes inside its window.
            let archive = channels.filter { $0.tvArchive == 1 }
            #expect(archive.map(\.streamId) == [MockFixture.Rich.archiveChannelId])
            let archiveChannel = try #require(archive.first)
            #expect(archiveChannel.tvArchiveDuration == MockFixture.Rich.archiveDays)
            let archiveKey = try #require(EPGChannelKey.forXtream(archiveChannel))
            #expect(programmes.contains { programme in
                programme.channelKey == archiveKey && programme.stopTs <= nowTs
                    && CatchupAvailability.isPlayable(
                        tvArchive: archiveChannel.tvArchive,
                        tvArchiveDurationDays: archiveChannel.tvArchiveDuration,
                        programmeStart: Date(timeIntervalSince1970: TimeInterval(programme.startTs)),
                        now: now)
            })
        }
    }

    /// The whole path a channel card takes: the store resolves the channel's key
    /// and has a programme for it, for a guide seeded just now. Both playlists
    /// carry a fresh bookkeeping row, so the store starts no refresh.
    @Test
    func storeFindsAProgrammeOnAirRightAfterSeeding() async throws {
        let database = try seeded(.rich)
        let (defaults, suite) = try makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = EPGStore(database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }

        let (xtream, m3u, liveStreams, m3uChannels) = try read(database) { db in
            (try Playlist.fetchOne(db, key: demoId), try Playlist.fetchOne(db, key: m3uId),
             try DBLiveStream.filter(Column("playlistId") == demoId).fetchAll(db),
             try DBM3UChannel.filter(Column("playlistId") == m3uId).fetchAll(db))
        }

        let xtreamPlaylist = try #require(xtream)
        store.setActivePlaylist(xtreamPlaylist)
        await store.reload(playlist: xtreamPlaylist)
        for seed in MockFixture.Rich.guideChannels {
            let stream = try #require(liveStreams.first { $0.streamId == seed.streamId })
            #expect(store.nowNext(channelKey: EPGChannelKey.forXtream(stream))?.now != nil, "nothing on air for \(stream.name)")
        }
        for id in MockFixture.Rich.channelsWithoutGuide {
            let stream = try #require(liveStreams.first { $0.streamId == id })
            #expect(store.nowNext(channelKey: EPGChannelKey.forXtream(stream)) == nil)
        }
        await store.refreshIfStale(playlist: xtreamPlaylist)
        #expect(store.refreshState[demoId] == nil)

        let m3uPlaylist = try #require(m3u)
        #expect(m3uPlaylist.kind == .m3u)
        #expect(EPGStore.expectsGuide(m3uPlaylist))
        store.setActivePlaylist(m3uPlaylist)
        await store.reload(playlist: m3uPlaylist)
        let withGuide = m3uChannels.filter { store.nowNext(channelKey: EPGChannelKey.forM3U($0))?.now != nil }
        #expect(withGuide.count == MockFixture.M3U.guideChannelCount)
        // Matched through the guide channel's display name, not through a tvg-id.
        let byName = try #require(m3uChannels.first { $0.name == MockFixture.M3U.nameMatchedChannelName })
        #expect(byName.tvgId == nil)
        #expect(withGuide.contains(byName))
        // A tvg-id alone is no guide.
        for tvgId in MockFixture.M3U.unmatchedTvgIds {
            let channel = try #require(m3uChannels.first { $0.tvgId == tvgId })
            #expect(!withGuide.contains(channel))
        }
        await store.refreshIfStale(playlist: m3uPlaylist)
        #expect(store.refreshState[m3uId] == nil)
    }

    // MARK: Rich mode: history and favourites

    @Test
    func historyAndFavouritesPointAtExistingItems() throws {
        let now = afternoon
        let database = try seeded(.rich, now: now)

        // Favourites of each type join to a row of that type.
        #expect(try count("""
            SELECT COUNT(*) FROM favorite f JOIN liveStream s ON s.streamId = f.streamId AND s.playlistId = f.playlistId
            WHERE f.type = 'live'
            """, in: database) == 2)
        #expect(try count("""
            SELECT COUNT(*) FROM favorite f JOIN vodStream s ON s.streamId = f.streamId AND s.playlistId = f.playlistId
            WHERE f.type = 'vod'
            """, in: database) == 3)
        #expect(try count("""
            SELECT COUNT(*) FROM favorite f JOIN series s ON s.seriesId = f.streamId AND s.playlistId = f.playlistId
            WHERE f.type = 'series'
            """, in: database) == 2)
        #expect(try count("""
            SELECT COUNT(*) FROM m3uFavorite f JOIN m3uChannel c ON c.id = f.channelId AND c.playlistId = f.playlistId
            """, in: database) == 2)

        try read(database) { db in
            let history = try DBWatchHistory
                .filter(Column("playlistId") == demoId)
                .order(Column("lastWatchedAt").desc)
                .fetchAll(db)
            #expect(history.map(\.type) == ["vod", "series", "live", "vod"])
            #expect(history.allSatisfy { $0.id == "\(demoId)_\($0.type)_\($0.streamId)" })
            #expect(history.allSatisfy { $0.lastWatchedAt <= now })
            #expect(Set(history.map(\.lastWatchedAt)).count == history.count)

            // A film at 40 %: resumes.
            let inProgress = history[0]
            #expect(inProgress.streamId == String(MockFixture.Rich.filmInProgressId))
            #expect(inProgress.lastTimeMs * 100 == inProgress.durationMs * 40)
            #expect(inProgress.resumePositionMs(as: .film) == inProgress.lastTimeMs)
            // A film at 99 %: finished, starts over.
            let finished = history[3]
            #expect(finished.streamId == String(MockFixture.Rich.filmFinishedId))
            #expect(finished.lastTimeMs * 100 == finished.durationMs * 99)
            #expect(finished.resumePositionMs(as: .film) == nil)
            for row in [inProgress, finished] {
                let film = try #require(try DBVODStream
                    .filter(Column("playlistId") == demoId && Column("streamId") == Int(row.streamId))
                    .fetchOne(db))
                #expect(row.title == film.name)
                #expect(row.imageURL == film.streamIcon)
                // Positions are inside the stream that fixture playback is redirected to.
                #expect(row.durationMs == MockFixture.demoStreamDurationMs)
            }

            // An episode of the first series with seasons, keyed by the panel episode id.
            let episodeRow = history[1]
            #expect(episodeRow.seriesId == String(MockFixture.Rich.seriesWithSeasonsId))
            #expect(episodeRow.streamId == MockFixture.Rich.episodeInProgressId)
            let episode = try #require(try DBEpisode
                .fetchOne(db, key: DBEpisode.scopedId(playlistId: demoId, panelEpisodeId: episodeRow.streamId)))
            #expect(episode.seasonId == DBSeason.scopedId(playlistId: demoId, seriesId: MockFixture.Rich.seriesWithSeasonsId, seasonNumber: 1))
            #expect(episodeRow.title == episode.title)
            #expect(episodeRow.resumePositionMs(as: .episode) == episodeRow.lastTimeMs)
            let show = try #require(try DBSeries
                .filter(Column("playlistId") == demoId && Column("seriesId") == MockFixture.Rich.seriesWithSeasonsId)
                .fetchOne(db))
            #expect(episodeRow.secondaryTitle == show.name)

            // A live channel: no position, no duration.
            let liveRow = history[2]
            let channel = try #require(try DBLiveStream
                .filter(Column("playlistId") == demoId && Column("streamId") == Int(liveRow.streamId))
                .fetchOne(db))
            #expect(channel.streamId == MockFixture.Rich.recentChannelId)
            #expect(liveRow.title == channel.name)
            #expect(liveRow.durationMs == 0 && liveRow.lastTimeMs == 0)
            let category = try DBCategory
                .filter(Column("playlistId") == demoId && Column("type") == "live" && Column("id") == channel.categoryId)
                .fetchOne(db)
            #expect(liveRow.secondaryTitle != nil)
            #expect(liveRow.secondaryTitle == category?.name)

            // The M3U row is a film of that playlist.
            let m3uRows = try DBWatchHistory.filter(Column("playlistId") == m3uId).fetchAll(db)
            let m3uRow = try #require(m3uRows.first)
            let watched = try #require(try DBM3UChannel.fetchOne(db, key: m3uRow.streamId))
            #expect(watched.playlistId == m3uId)
            #expect(!M3UContentStore.isLive(watched))
            #expect(m3uRow.type == "vod")
            #expect(m3uRow.id == "\(m3uId)_vod_\(watched.id)")
            #expect(m3uRow.resumePositionMs(as: .film) == m3uRow.lastTimeMs)
        }
    }

    // MARK: Rich mode: M3U playlist

    @Test
    func m3uPlaylistHasThreeGroupsLooseChannelsAndFilms() throws {
        let database = try seeded(.rich, now: afternoon)
        try read(database) { db in
            let playlist = try #require(try Playlist.fetchOne(db, key: m3uId))
            #expect(playlist.kind == .m3u)
            #expect(playlist.name == MockFixture.M3U.playlistName)
            #expect(playlist.effectiveEPGURL == MockFixture.M3U.guideURL)

            let channels = try DBM3UChannel
                .filter(Column("playlistId") == m3uId)
                .order(Column("sortIndex"))
                .fetchAll(db)
            #expect(channels.count == MockFixture.M3U.channelCount)
            #expect(channels.map(\.sortIndex) == Array(0..<channels.count))

            // The ids an import of the same list would write, all distinct.
            #expect(Set(channels.map(\.id)).count == channels.count)
            #expect(channels.allSatisfy { $0.id == M3UImporter.stableChannelID(playlistId: m3uId, url: $0.url) })
            #expect(channels.allSatisfy { M3UParser.sanitizedURL(from: $0.url) != nil })

            let groups = Dictionary(grouping: channels, by: { M3UContentStore.groupKey(for: $0) })
            #expect(groups.count == 4)
            #expect(groups[MockFixture.M3U.newsGroup]?.count == MockFixture.M3U.newsCount)
            #expect(groups[MockFixture.M3U.largeGroup]?.count == 400)
            #expect(groups[MockFixture.M3U.filmGroup]?.count == MockFixture.M3U.filmCount)
            #expect(groups[M3UContentStore.ungroupedLabel]?.count == MockFixture.M3U.ungroupedCount)

            // The film group, and only it, is not live; both container types occur.
            let films = channels.filter { !M3UContentStore.isLive($0) }
            #expect(films == groups[MockFixture.M3U.filmGroup])
            let extensions = films.compactMap { URL(string: $0.url)?.pathExtension }
            #expect(Set(extensions) == ["mp4", "mkv"])
            #expect(extensions.count == films.count)

            // Some channels carry a tvg-id; the guide has rows for all but two of them.
            let tvgKeys = Set(channels.compactMap { EPGConstants.normalizeChannelKey($0.tvgId) })
            #expect(tvgKeys.count == 22)
            let guideKeys = Set(try String.fetchAll(db, sql: "SELECT DISTINCT channelKey FROM epgProgramme WHERE playlistId = ?", arguments: [m3uId]))
            #expect(guideKeys.count == MockFixture.M3U.guideChannelCount)
            #expect(tvgKeys.subtracting(guideKeys) == Set(MockFixture.M3U.unmatchedTvgIds))
            #expect(guideKeys.subtracting(tvgKeys).count == 1)

            let source = try #require(try DBEPGSource.fetchOne(db, key: m3uId))
            #expect(source.sourceType == EPGSourceType.m3uXMLTV.rawValue)
            #expect(source.lastSuccessAt != nil)
            let programmeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM epgProgramme WHERE playlistId = ?", arguments: [m3uId])
            #expect(source.programmeCount == programmeCount)

            #expect(channels.filter { $0.tvgLogo == nil }.count == (MockFixture.imageBase == "none" ? channels.count : 1))
            #expect(channels.contains { $0.name == "IŞIK TV" })
            #expect(channels.contains { $0.name == MockFixture.M3U.favoriteChannelName })
        }
    }

    // MARK: Launch arguments and defaults

    @Test
    func modeFollowsTheLaunchArguments() {
        #expect(MockFixture.mode(catalogScale: 0, fixture: nil) == .demo)
        #expect(MockFixture.mode(catalogScale: 0, fixture: "rich") == .rich)
        #expect(MockFixture.mode(catalogScale: 0, fixture: "unknown") == .demo)
        // The large catalog reuses the demo playlist id, so it cannot be combined.
        #expect(MockFixture.mode(catalogScale: 4, fixture: "rich") == .large)
    }

    @Test
    func m3uPlaylistOpensFirstOnlyWhenAskedAndOnlyInRichMode() {
        #expect(MockFixture.startPlaylistId(mode: .demo, startPlaylist: nil) == demoId)
        #expect(MockFixture.startPlaylistId(mode: .rich, startPlaylist: nil) == demoId)
        #expect(MockFixture.startPlaylistId(mode: .rich, startPlaylist: "m3u") == m3uId)
        // No M3U playlist exists in the other modes.
        #expect(MockFixture.startPlaylistId(mode: .demo, startPlaylist: "m3u") == demoId)
        #expect(MockFixture.startPlaylistId(mode: .large, startPlaylist: "m3u") == demoId)
    }

    @Test
    func everyFixturePlaylistPlaysTheDemoStream() {
        #expect(demoId != m3uId)
        #expect(MockFixture.fixturePlaylistIds == [demoId, m3uId])
        for id in MockFixture.fixturePlaylistIds {
            #expect(MockFixture.fixtureStreamURL(playlistId: id)?.absoluteString == MockFixture.demoStreamURL)
        }
        #expect(MockFixture.fixtureStreamURL(playlistId: UUID()) == nil)
        // Outside a fixture launch nothing is redirected.
        if !MockFixture.isActive {
            #expect(MockFixture.demoPlaybackURL(playlistId: demoId) == nil)
        }
    }

    @Test
    func browseStateOfAnEarlierRunIsRemovedAndNothingElse() throws {
        let (defaults, suite) = try makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let other = UUID()

        var browseKeys = [
            "dashboard_selected_tab",
            LiveSortOption.storageKey,
            VODSortOption.storageKey,
            SeriesSortOption.storageKey,
            "app.selected_language",
        ]
        for id in MockFixture.fixturePlaylistIds {
            browseKeys.append("epg.collapsedCategories.\(id.uuidString)")
            browseKeys.append("epg.lineReserved.\(id.uuidString)")
            browseKeys.append("browse.recentReserved.vod.\(id.uuidString)")
            browseKeys.append("browse.recentReserved.series.\(id.uuidString)")
            browseKeys += ["live", "vod", "series", "m3u"].map { "hidden_categories.\(id.uuidString).\($0)" }
        }
        let kept = [
            "lastPlaylistId",
            "dashboard_removed_home_tab_migration_v1",
            "player.pipEnabled",
            "hidden_categories.\(other.uuidString).live",
            "epg.collapsedCategories.\(other.uuidString)",
            "epg.lineReserved.\(other.uuidString)",
        ]
        for key in browseKeys + kept {
            defaults.set("stored", forKey: key)
        }

        MockFixture.resetBrowseState(playlistIds: MockFixture.fixturePlaylistIds, in: defaults)

        for key in browseKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) survived")
        }
        for key in kept {
            #expect(defaults.string(forKey: key) == "stored", "\(key) was removed")
        }
    }
}
