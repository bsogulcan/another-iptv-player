import Foundation
import GRDB

// The rich mode (`-UITestsFixture rich`): what it adds to the Xtream demo playlist.
//
// The small demo catalog cannot reach a season, an episode, a guide cell, a
// Continue Watching card or a populated Favorites screen, and its names are all
// short ASCII. Everything here is written at seed time from constants; the only
// input is the seed time, which anchors the guide, the history and the favourites.
extension MockFixture {

    /// What a test needs to find the rows of the rich mode.
    enum Rich {
        /// Seasons loaded: an empty season 0 "Specials", then two seasons of twelve episodes.
        static let seriesWithSeasonsId = 2001
        /// Seasons loaded: one season of four episodes. Every other series still
        /// has `seasonsLoaded` false and asks the panel when it is opened.
        static let seriesWithOneSeasonId = 2002

        static let largeFilmCategoryId = "vod-classics"
        static let largeFilmCategoryCount = 300
        static let emptyLiveCategoryId = "live-empty"
        static let emptyFilmCategoryId = "vod-empty"
        static let emptySeriesCategoryId = "series-empty"
        /// Items per content type whose category id is nil or names no category.
        static let uncategorizedCount = 5

        static let channelWithoutLogoId = 510
        /// A film title of about 60 characters.
        static let longestTitleFilmId = 1110

        /// The demo channels that have a guide, with the id each carries. Two ids
        /// are mixed case: the lookup has to fold them to the stored key.
        static let guideChannels: [(streamId: Int, epgId: String)] = [
            (101, "WorldNews24.demo"),
            (102, "businesstoday.demo"),
            (201, "sportscentral.demo"),
            (202, "footballlive.demo"),
            (203, "TennisPro.demo"),
            (301, "cinemachannel.demo"),
            (302, "musichits.demo"),
            (303, "comedyplus.demo"),
            (304, "discoverystories.demo"),
            (401, "cartoonworld.demo"),
        ]
        /// The demo channels without a guide id and without guide data.
        static let channelsWithoutGuide = [103, 204, 402]
        /// Has a day-long placeholder under its real programmes.
        static let placeholderGuideChannelId = 201
        /// Advertises a catch-up archive of `archiveDays`.
        static let archiveChannelId = 101
        static let archiveDays = 2

        static let favoriteChannelIds = [101, 302]
        static let favoriteFilmIds = [1001, 1007, 1108]
        static let favoriteSeriesIds = [2001, 2005]

        /// Watched to 40 %.
        static let filmInProgressId = 1002
        /// Watched to 99 %: counts as finished, starts over instead of resuming.
        static let filmFinishedId = 1004
        /// Season 1, episode 3 of `seriesWithSeasonsId`, watched to 55 %.
        static let episodeInProgressId = episodeId(seriesId: seriesWithSeasonsId, season: 1, episode: 3)
        static let recentChannelId = 301

        /// Panel id of a seeded episode ("210103" for series 2001, season 1, episode 3).
        static func episodeId(seriesId: Int, season: Int, episode: Int) -> String {
            String((seriesId - 1_980) * 10_000 + season * 100 + episode)
        }

        /// `added` of the newest film and `lastModified` of the newest series; each
        /// following item is an hour older, so "recently added" has one order.
        static let newestTimestamp = 1_760_000_000
        /// The head of that order. It mixes demo titles with the long and the
        /// non-Latin ones, so a Recently Added shelf shows all of them.
        static let newestFilmIds = [1001, 1108, 1002, 1110, 1003, 1101, 1004, 1104, 1005, 1106]
        static let newestSeriesIds = [2001, 2106, 2002, 2107, 2003, 2101, 2004, 2104, 2005, 2105]
    }

    /// A seed step referred to a row an earlier step should have written.
    struct MissingRow: Error {
        var table: String
        var id: String
    }

    static func seedRichCatalog(db: Database, playlistId: UUID, now: Date, calendar: Calendar = .current) throws {
        try insertDemoRows(db: db, playlistId: playlistId)
        try insertRichLive(db: db, playlistId: playlistId)
        try insertRichVOD(db: db, playlistId: playlistId)
        try insertRichSeries(db: db, playlistId: playlistId)
        try insertRichSeasons(db: db, playlistId: playlistId)
        try insertRichGuide(db: db, playlistId: playlistId, now: now, calendar: calendar)
        try insertRichHistory(db: db, playlistId: playlistId, now: now)
        try insertRichFavorites(db: db, playlistId: playlistId, now: now)
    }

    // MARK: - Lookups

    private static func storedChannel(_ streamId: Int, playlistId: UUID, db: Database) throws -> DBLiveStream {
        guard let row = try DBLiveStream
            .filter(Column("playlistId") == playlistId && Column("streamId") == streamId)
            .fetchOne(db) else { throw MissingRow(table: DBLiveStream.databaseTableName, id: String(streamId)) }
        return row
    }

    private static func storedFilm(_ streamId: Int, playlistId: UUID, db: Database) throws -> DBVODStream {
        guard let row = try DBVODStream
            .filter(Column("playlistId") == playlistId && Column("streamId") == streamId)
            .fetchOne(db) else { throw MissingRow(table: DBVODStream.databaseTableName, id: String(streamId)) }
        return row
    }

    private static func storedSeries(_ seriesId: Int, playlistId: UUID, db: Database) throws -> DBSeries {
        guard let row = try DBSeries
            .filter(Column("playlistId") == playlistId && Column("seriesId") == seriesId)
            .fetchOne(db) else { throw MissingRow(table: DBSeries.databaseTableName, id: String(seriesId)) }
        return row
    }

    /// Position of every id in "newest first" order: `head` as given, then the
    /// remaining ids in the order they come in.
    private static func recencyRanks(of ids: [Int], newestFirst head: [Int]) -> [Int: Int] {
        let inHead = Set(head)
        var ranks: [Int: Int] = [:]
        for (rank, id) in (head + ids.filter { !inHead.contains($0) }).enumerated() where ranks[id] == nil {
            ranks[id] = rank
        }
        return ranks
    }

    private static let people = ["Avery Stone", "Rowan Hale", "Quinn Mercer", "Harper Vale",
                                 "Ellis Ward", "Sawyer Lane", "Reese Calder", "Dana Whitlock"]

    private static func person(_ index: Int) -> String { people[index % people.count] }

    private static func castList(_ index: Int) -> String {
        (1...4).map { person(index + $0) }.joined(separator: ", ")
    }

    // MARK: - Live

    private static func insertRichLive(db: Database, playlistId: UUID) throws {
        let categories: [(String, String)] = [
            ("live-world", "International"),
            (Rich.emptyLiveCategoryId, "Radio"),
        ]
        for (offset, (id, name)) in categories.enumerated() {
            try DBCategory(id: id, name: name, parentId: nil, type: "live", sortIndex: 100 + offset, playlistId: playlistId).insert(db)
        }

        // Names that need more than ASCII lowercasing to be found ("isik", "izle",
        // "cocuk"), right-to-left and Cyrillic names, two that wrap under a tile
        // (the second is 60 characters), and five channels outside every category:
        // three without a category id, two whose category the panel no longer lists.
        let channels: [(Int, String, String?)] = [
            (501, "IŞIK TV", "live-world"),
            (502, "İZLE", "live-world"),
            (503, "Çocuk", "live-world"),
            (504, "أخبار العالم", "live-world"),
            (505, "سينما الليل", "live-world"),
            (506, "Новости Мира", "live-world"),
            (507, "Вечернее Кино", "live-world"),
            (508, "Documentary & Nature Channel International", "live-world"),
            (509, "The Community Television Network of the Northern Territories", "live-world"),
            (Rich.channelWithoutLogoId, "Local Access", "live-world"),
            (901, "Test Card", nil),
            (902, "Backup Feed A", nil),
            (903, "Backup Feed B", nil),
            (904, "Regional Relay East", "live-retired"),
            (905, "Regional Relay West", "live-retired"),
        ]
        for (offset, (streamId, name, category)) in channels.enumerated() {
            try DBLiveStream(
                streamId: streamId,
                name: name,
                streamIcon: streamId == Rich.channelWithoutLogoId ? nil : artwork("live", streamId, w: 200, h: 200),
                epgChannelId: nil,
                categoryId: category,
                sortIndex: 100 + offset,
                playlistId: playlistId
            ).insert(db)
        }
    }

    // MARK: - Films

    private static func insertRichVOD(db: Database, playlistId: UUID) throws {
        let categories: [(String, String)] = [
            ("vod-world", "World Cinema"),
            (Rich.largeFilmCategoryId, "Classics"),
            (Rich.emptyFilmCategoryId, "Coming Soon"),
        ]
        for (offset, (id, name)) in categories.enumerated() {
            try DBCategory(id: id, name: name, parentId: nil, type: "vod", sortIndex: 100 + offset, playlistId: playlistId).insert(db)
        }

        var sortIndex = 100
        func insert(_ streamId: Int, _ name: String, category: String?, year: String, rating: String?, mkv: Bool) throws {
            try DBVODStream(
                streamId: streamId,
                name: name,
                streamIcon: artwork("vod", streamId, w: 400, h: 600),
                categoryId: category,
                rating: rating,
                containerExtension: mkv ? "mkv" : "mp4",
                plot: "A captivating placeholder synopsis for demo purposes.",
                releaseDate: year,
                rating5Based: rating.flatMap { Double($0) }.map { $0 / 2 },
                metadataLoaded: true,
                sortIndex: sortIndex,
                playlistId: playlistId
            ).insert(db)
            sortIndex += 1
        }

        // 1108 and 1109 wrap to two lines under a poster, 1110 is 61 characters.
        let world: [(Int, String, String, String?)] = [
            (1101, "İZLE: Bir Şehir Hikâyesi", "2021", "7.8"),
            (1102, "Çocuk Masalları", "2019", "6.9"),
            (1103, "IŞIK", "2022", "7.1"),
            (1104, "ليلة في المدينة", "2020", "7.5"),
            (1105, "الطريق إلى البحر", "2018", nil),
            (1106, "Долгая дорога домой", "2021", "8.0"),
            (1107, "Тихий берег", "2017", "6.7"),
            (1108, "The Extraordinary Voyage of the Lighthouse Keeper", "2023", "7.7"),
            (1109, "A Brief History of Almost Everything That Went Wrong", "2022", "6.4"),
            (Rich.longestTitleFilmId, "The Incredibly Long and Winding Road to the Edge of the World", "2024", "7.2"),
        ]
        for (streamId, name, year, rating) in world {
            try insert(streamId, name, category: "vod-world", year: year, rating: rating, mkv: streamId % 3 == 0)
        }

        let uncategorized: [(Int, String, String?)] = [
            (1901, "Unsorted Reel One", nil),
            (1902, "Unsorted Reel Two", nil),
            (1903, "Unsorted Reel Three", nil),
            (1904, "Retired Shelf Feature", "vod-retired"),
            (1905, "Retired Shelf Double Bill", "vod-retired"),
        ]
        for (streamId, name, category) in uncategorized {
            try insert(streamId, name, category: category, year: "2020", rating: nil, mkv: false)
        }

        // One category long enough to page, with a share of unrated films.
        for i in 0..<Rich.largeFilmCategoryCount {
            let rating = i % 7 == 0 ? nil : String(format: "%.1f", 5.0 + Double(i % 45) / 10.0)
            try insert(3_000 + i, title(i), category: Rich.largeFilmCategoryId,
                       year: String(1950 + i % 50), rating: rating, mkv: i % 3 == 0)
        }

        try completeFilms(db: db, playlistId: playlistId)
    }

    /// Gives every film of the playlist, the demo ones included, its `added` time
    /// and the details the movie page shows (genres, running time, director, cast,
    /// backdrop). The demo mode leaves all of these empty.
    private static func completeFilms(db: Database, playlistId: UUID) throws {
        let genres: [String: String] = [
            "vod-action": "Action, Thriller",
            "vod-drama": "Drama",
            "vod-comedy": "Comedy, Family",
            "vod-scifi": "Sci-Fi, Adventure",
            "vod-doc": "Documentary, Nature",
            "vod-world": "Drama, World Cinema",
        ]
        let classicGenres = ["Drama", "Comedy, Romance", "Adventure", "Mystery, Crime", "Western"]

        let films = try DBVODStream
            .filter(Column("playlistId") == playlistId)
            .order(Column("sortIndex"))
            .fetchAll(db)
        let ranks = recencyRanks(of: films.map(\.streamId), newestFirst: Rich.newestFilmIds)

        for var film in films {
            let id = film.streamId
            let isClassic = film.categoryId == Rich.largeFilmCategoryId
            film.genre = isClassic ? classicGenres[id % classicGenres.count] : genres[film.categoryId ?? ""]
            let minutes = 82 + id % 49
            film.duration = String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
            film.director = person(id)
            film.cast = castList(id)
            // Half of the long category has no backdrop: its page falls back to the poster.
            if !isClassic || id % 2 == 0 {
                film.backdropPath = artwork("backdrop", id, w: 1_280, h: 720)
            }
            film.added = String(Rich.newestTimestamp - (ranks[id] ?? films.count) * 3_600)
            try film.update(db)
        }
    }

    // MARK: - Series

    private static func insertRichSeries(db: Database, playlistId: UUID) throws {
        let categories: [(String, String)] = [
            ("series-world", "World Series"),
            (Rich.emptySeriesCategoryId, "Coming Soon"),
        ]
        for (offset, (id, name)) in categories.enumerated() {
            try DBCategory(id: id, name: name, parentId: nil, type: "series", sortIndex: 100 + offset, playlistId: playlistId).insert(db)
        }

        // 2106 wraps to two lines under a poster, 2107 is 60 characters.
        let series: [(Int, String, String?, String?)] = [
            (2101, "IŞIK ve Gölge", "series-world", "7.4"),
            (2102, "Çocukluk Yılları", "series-world", "8.0"),
            (2103, "İZLE ve Öğren", "series-world", nil),
            (2104, "حكايات المدينة", "series-world", "7.7"),
            (2105, "Город у моря", "series-world", "7.3"),
            (2106, "The Remarkable Adventures of an Ordinary Family", "series-world", "6.9"),
            (2107, "Chronicles of the Forgotten Kingdom Beyond the Northern Seas", "series-world", "8.2"),
            (2901, "Pilot Reel One", nil, nil),
            (2902, "Pilot Reel Two", nil, nil),
            (2903, "Pilot Reel Three", nil, nil),
            (2904, "Retired Shelf Stories", "series-retired", nil),
            (2905, "Retired Shelf Tales", "series-retired", nil),
        ]
        for (offset, (seriesId, name, category, rating)) in series.enumerated() {
            try DBSeries(
                seriesId: seriesId,
                name: name,
                cover: artwork("series", seriesId, w: 400, h: 600),
                plot: "An engaging placeholder description for demo purposes.",
                releaseDate: "2023",
                rating: rating,
                rating5Based: rating.flatMap { Double($0) }.map { $0 / 2 },
                categoryId: category,
                sortIndex: 100 + offset,
                seasonsLoaded: false,
                playlistId: playlistId
            ).insert(db)
        }

        let genres: [String: String] = [
            "series-drama": "Drama",
            "series-thriller": "Thriller, Crime",
            "series-comedy": "Comedy",
            "series-doc": "Documentary",
            "series-world": "Drama, World",
        ]
        let all = try DBSeries
            .filter(Column("playlistId") == playlistId)
            .order(Column("sortIndex"))
            .fetchAll(db)
        let ranks = recencyRanks(of: all.map(\.seriesId), newestFirst: Rich.newestSeriesIds)
        for var item in all {
            item.genre = genres[item.categoryId ?? ""]
            item.lastModified = String(Rich.newestTimestamp - (ranks[item.seriesId] ?? all.count) * 3_600)
            try item.update(db)
        }
    }

    // MARK: - Seasons and episodes

    private struct SeasonSeed {
        var number: Int
        var name: String
        var overview: String
        var airDate: String
        var voteAverage: Double?
        var episodes: [String]
    }

    private static func insertRichSeasons(db: Database, playlistId: UUID) throws {
        try insertSeasons(db: db, playlistId: playlistId, seriesId: Rich.seriesWithSeasonsId, seasons: [
            // Listed by the panel, but with no episode behind it.
            SeasonSeed(number: 0, name: "Specials",
                       overview: "Behind the scenes, cast interviews and the holiday special.",
                       airDate: "2022-12-24", voteAverage: nil, episodes: []),
            SeasonSeed(number: 1, name: "Season 1",
                       overview: "A research team arrives at a remote northern station as the long night begins, and finds that the last crew left more than their notes behind.",
                       airDate: "2023-01-12", voteAverage: 8.3,
                       episodes: ["Arrival", "First Frost", "The Long Night", "Signals", "Thin Ice", "The Lighthouse",
                                  "Whiteout", "Old Maps", "The Crossing", "Aurora",
                                  "What the Tide Brought In and What It Took Away Again", "Midwinter"]),
            SeasonSeed(number: 2, name: "Season 2",
                       overview: "Spring opens the sea lanes, and with them the question of who else knows about the station.",
                       airDate: "2024-02-08", voteAverage: 8.6,
                       episodes: ["Thaw", "New Arrivals", "The Ferry", "Static", "Low Sun", "The Survey",
                                  "Borrowed Time", "North by Northeast", "The Storm Front", "Radio Silence",
                                  "Homecoming", "Solstice"]),
        ])
        try insertSeasons(db: db, playlistId: playlistId, seriesId: Rich.seriesWithOneSeasonId, seasons: [
            SeasonSeed(number: 1, name: "Season 1",
                       overview: "One trial, four days, and a jury that cannot agree on what it saw.",
                       airDate: "2024-09-03", voteAverage: 8.1,
                       episodes: ["Opening Statements", "The Witness", "Reasonable Doubt", "Closing Arguments"]),
        ])
    }

    /// Writes what a series page stores after it has asked the panel: the seasons,
    /// their episodes, and the series row marked as loaded, so opening the series
    /// makes no request.
    private static func insertSeasons(db: Database, playlistId: UUID, seriesId: Int, seasons: [SeasonSeed]) throws {
        var item = try storedSeries(seriesId, playlistId: playlistId, db: db)

        for season in seasons {
            let seasonId = DBSeason.scopedId(playlistId: playlistId, seriesId: seriesId, seasonNumber: season.number)
            try DBSeason(
                id: seasonId,
                seasonNumber: season.number,
                name: season.name,
                overview: season.overview,
                cover: artwork("season", seriesId * 10 + season.number, w: 400, h: 600),
                airDate: season.airDate,
                episodeCount: season.episodes.count,
                voteAverage: season.voteAverage,
                seriesId: seriesId,
                playlistId: playlistId
            ).insert(db)

            for (offset, title) in season.episodes.enumerated() {
                let number = offset + 1
                let episodeId = Rich.episodeId(seriesId: seriesId, season: season.number, episode: number)
                // The first episode of a season has a synopsis long enough to be cut off.
                let plot = number == 1
                    ? "\(item.name), season \(season.number), episode \(number). A longer placeholder synopsis for demo purposes: it sets the scene, introduces everyone who matters and still has room for a second and a third sentence, so the row has to decide where to cut it off."
                    : "\(item.name), season \(season.number), episode \(number). A placeholder synopsis for demo purposes."
                try DBEpisode(
                    id: DBEpisode.scopedId(playlistId: playlistId, panelEpisodeId: episodeId),
                    episodeId: episodeId,
                    episodeNum: number,
                    title: title,
                    containerExtension: number % 4 == 0 ? "mkv" : "mp4",
                    info: plot,
                    cover: artwork("episode", Int(episodeId) ?? number, w: 640, h: 360),
                    duration: String(format: "00:%02d:%02d", 42 + (number * 7) % 17, (number * 13) % 60),
                    rating: String(format: "%.1f", 7.0 + Double((number * 3) % 20) / 10.0),
                    seasonId: seasonId
                ).insert(db)
            }
        }

        item.seasonsLoaded = true
        item.cast = castList(seriesId)
        item.director = person(seriesId)
        item.episodeRunTime = "47"
        item.backdropPath = artwork("backdrop", seriesId, w: 1_280, h: 720)
        try item.update(db)
    }

    // MARK: - Guide

    private static func insertRichGuide(db: Database, playlistId: UUID, now: Date, calendar: Calendar) throws {
        let shapes: [Int: GuideShape] = [
            101: .news, 102: .business, 201: .sport, 202: .sport, 203: .events,
            301: .film, 302: .music, 303: .comedy, 304: .documentary, 401: .kids,
        ]

        var channels: [GuideChannel] = []
        for (streamId, epgId) in Rich.guideChannels {
            var stream = try storedChannel(streamId, playlistId: playlistId, db: db)
            stream.epgChannelId = epgId
            if streamId == Rich.archiveChannelId {
                stream.tvArchive = 1
                stream.tvArchiveDuration = Rich.archiveDays
            }
            try stream.update(db)

            channels.append(guideChannel(
                key: guideKey(epgId),
                displayName: stream.name,
                iconURL: stream.streamIcon,
                shape: shapes[streamId] ?? .news,
                hasDayPlaceholder: streamId == Rich.placeholderGuideChannelId
            ))
        }

        try insertGuide(db: db, playlistId: playlistId, sourceType: .xtreamXMLTV, sourceURL: nil,
                        channels: channels, now: now, calendar: calendar)
    }

    // MARK: - Watch history

    /// The rows the player would have written. Positions are measured against the
    /// demo stream that fixture playback is redirected to, so Resume lands inside it.
    private static func insertRichHistory(db: Database, playlistId: UUID, now: Date) throws {
        let duration = demoStreamDurationMs

        func insertFilm(_ streamId: Int, percent: Int, minutesAgo: Int) throws {
            let film = try storedFilm(streamId, playlistId: playlistId, db: db)
            let details = [film.genre, film.releaseDate].compactMap { $0 }.filter { !$0.isEmpty }
            try DBWatchHistory(
                id: "\(playlistId)_vod_\(streamId)",
                playlistId: playlistId,
                streamId: String(streamId),
                type: "vod",
                lastTimeMs: duration * percent / 100,
                durationMs: duration,
                lastWatchedAt: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
                seriesId: nil,
                title: film.name,
                secondaryTitle: details.isEmpty ? nil : details.joined(separator: " · "),
                imageURL: film.streamIcon,
                containerExtension: film.containerExtension
            ).insert(db)
        }

        try insertFilm(Rich.filmInProgressId, percent: 40, minutesAgo: 20)

        let episodeId = Rich.episodeInProgressId
        // By the playlist-scoped row id: another playlist may hold the same panel id.
        let episodeRowId = DBEpisode.scopedId(playlistId: playlistId, panelEpisodeId: episodeId)
        guard let episode = try DBEpisode.fetchOne(db, key: episodeRowId) else {
            throw MissingRow(table: DBEpisode.databaseTableName, id: episodeId)
        }
        let show = try storedSeries(Rich.seriesWithSeasonsId, playlistId: playlistId, db: db)
        try DBWatchHistory(
            id: "\(playlistId)_series_\(episodeId)",
            playlistId: playlistId,
            streamId: episodeId,
            type: "series",
            lastTimeMs: duration * 55 / 100,
            durationMs: duration,
            lastWatchedAt: now.addingTimeInterval(-2 * 3_600),
            seriesId: String(show.seriesId),
            title: episode.title ?? show.name,
            secondaryTitle: show.name,
            imageURL: episode.cover ?? show.cover,
            containerExtension: episode.containerExtension
        ).insert(db)

        // A live row has no position and no duration; the player files it under
        // the channel's category.
        let channel = try storedChannel(Rich.recentChannelId, playlistId: playlistId, db: db)
        let categoryName = try channel.categoryId.flatMap { id in
            try DBCategory
                .filter(Column("playlistId") == playlistId && Column("type") == "live" && Column("id") == id)
                .fetchOne(db)?.name
        }
        try DBWatchHistory(
            id: "\(playlistId)_live_\(channel.streamId)",
            playlistId: playlistId,
            streamId: String(channel.streamId),
            type: "live",
            lastTimeMs: 0,
            durationMs: 0,
            lastWatchedAt: now.addingTimeInterval(-5 * 3_600),
            seriesId: nil,
            title: channel.name,
            secondaryTitle: categoryName,
            imageURL: channel.streamIcon,
            containerExtension: nil
        ).insert(db)

        try insertFilm(Rich.filmFinishedId, percent: 99, minutesAgo: 26 * 60)
    }

    // MARK: - Favourites

    private static func insertRichFavorites(db: Database, playlistId: UUID, now: Date) throws {
        let favorites: [(String, [Int])] = [
            ("live", Rich.favoriteChannelIds),
            ("vod", Rich.favoriteFilmIds),
            ("series", Rich.favoriteSeriesIds),
        ]
        for (type, ids) in favorites {
            // The Favorites screen lists newest first: keep the order of the id lists.
            for (offset, id) in ids.enumerated() {
                try DBFavorite(streamId: id, playlistId: playlistId, type: type,
                               createdAt: now.addingTimeInterval(TimeInterval(-offset * 60))).insert(db)
            }
        }
    }
}
