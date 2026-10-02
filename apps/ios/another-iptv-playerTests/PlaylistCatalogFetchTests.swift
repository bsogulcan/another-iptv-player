import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The catalog reads of `PlaylistContentStore`: positional row decoding, the
/// "uncategorized" bucket and the recently-added candidates.
@Suite("Playlist catalog fetch")
struct PlaylistCatalogFetchTests {
    private let playlist = PlaylistCatalogFixture.playlist()
    private let uncategorized = PlaylistContentStore.uncategorizedCategoryId

    /// The query the store used before it decoded by column index: `SELECT *`
    /// through the records' `Decodable` conformance.
    private static func referenceSQL(table: String, type: String) -> String {
        """
        SELECT \(table).*, COALESCE(category.name, ?) AS categoryName
        FROM \(table)
        LEFT JOIN category ON \(table).categoryId = category.id
                     AND \(table).playlistId = category.playlistId
                     AND category.type = '\(type)'
        WHERE \(table).playlistId = ?
        ORDER BY \(table).sortIndex
        """
    }

    // MARK: - Decode equivalence

    @Test
    func liveRowsDecodeLikeTheDecodablePath() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let category = DBCategory(id: "1", name: "News", parentId: 7, type: "live", sortIndex: 0, playlistId: pid)
        let full = DBLiveStream(
            streamId: 1, name: "Full", streamIcon: "http://img/1.png", epgChannelId: "full.tv",
            categoryId: "1", sortIndex: 0, playlistId: pid, tvArchive: 1, tvArchiveDuration: 7
        )
        let bare = DBLiveStream(
            streamId: 2, name: "Bare", streamIcon: nil, epgChannelId: nil,
            categoryId: nil, sortIndex: 1, playlistId: pid
        )
        try await database.write { db in
            try category.insert(db)
            try full.insert(db)
            try bare.insert(db)
        }

        let fallbackName = L("content.uncategorized")
        let sql = Self.referenceSQL(table: "liveStream", type: "live")
        let (fast, reference) = try await database.read { db in
            (
                try PlaylistContentStore.fetchLiveCatalog(playlistId: pid, db: db).streams,
                try LiveStreamWithCategory.fetchAll(db, sql: sql, arguments: [fallbackName, pid])
            )
        }

        #expect(fast == reference)
        #expect(fast.map(\.stream) == [full, bare])
        #expect(fast.map(\.categoryName) == ["News", fallbackName])
    }

    @Test
    func movieRowsDecodeLikeTheDecodablePath() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let category = DBCategory(id: "10", name: "Drama", parentId: nil, type: "vod", sortIndex: 0, playlistId: pid)
        // Every column gets its own value so a swapped pair cannot go unnoticed.
        var full = DBVODStream(
            streamId: 10, name: "Full", streamIcon: "icon", categoryId: "10",
            rating: "7.5", containerExtension: "mkv", sortIndex: 0, playlistId: pid
        )
        full.director = "director"
        full.cast = "cast"
        full.plot = "plot"
        full.genre = "genre"
        full.releaseDate = "2020-01-02"
        full.rating5Based = 3.5
        full.backdropPath = "backdrop"
        full.youtubeTrailer = "trailer"
        full.duration = "01:30:00"
        full.tmdbId = "603"
        full.kinopoiskURL = "kinopoisk"
        full.metadataLoaded = true
        full.added = "1700000000"
        let bare = DBVODStream(
            streamId: 11, name: "Bare", streamIcon: nil, categoryId: nil,
            rating: nil, containerExtension: nil, sortIndex: 1, playlistId: pid
        )
        let rows = [full, bare]
        try await database.write { db in
            try category.insert(db)
            for row in rows { try row.insert(db) }
        }

        let fallbackName = L("content.uncategorized")
        let sql = Self.referenceSQL(table: "vodStream", type: "vod")
        let (fast, reference) = try await database.read { db in
            (
                try PlaylistContentStore.fetchVODCatalog(playlistId: pid, db: db).streams,
                try VODWithCategory.fetchAll(db, sql: sql, arguments: [fallbackName, pid])
            )
        }

        #expect(fast == reference)
        #expect(fast.map(\.stream) == rows)
        #expect(fast.map(\.categoryName) == ["Drama", fallbackName])
    }

    @Test
    func seriesRowsDecodeLikeTheDecodablePath() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let category = DBCategory(id: "20", name: "Shows", parentId: nil, type: "series", sortIndex: 0, playlistId: pid)
        let full = DBSeries(
            seriesId: 20, name: "Full", cover: "cover", plot: "plot", cast: "cast", director: "director",
            genre: "genre", releaseDate: "2019-03-04", rating: "8", lastModified: "1700000500",
            rating5Based: 4.5, backdropPath: "backdrop", youtubeTrailer: "trailer", episodeRunTime: "45",
            categoryId: "20", sortIndex: 0, seasonsLoaded: true, playlistId: pid
        )
        let bare = DBSeries(seriesId: 21, name: "Bare", cover: nil, categoryId: nil, sortIndex: 1, playlistId: pid)
        let rows = [full, bare]
        try await database.write { db in
            try category.insert(db)
            for row in rows { try row.insert(db) }
        }

        let fallbackName = L("content.uncategorized")
        let sql = Self.referenceSQL(table: "series", type: "series")
        let (fast, reference) = try await database.read { db in
            (
                try PlaylistContentStore.fetchSeriesCatalog(playlistId: pid, db: db).items,
                try SeriesWithCategory.fetchAll(db, sql: sql, arguments: [fallbackName, pid])
            )
        }

        #expect(fast == reference)
        #expect(fast.map(\.series) == rows)
        #expect(fast.map(\.categoryName) == ["Shows", fallbackName])
    }

    /// A column added to a table (and to its record) must be added to the positional
    /// list as well; the record's memberwise initializer does not force that when the
    /// new property has a default value.
    @Test
    func columnListsNameEveryColumnOfTheirTable() async throws {
        let database = AppDatabase.empty()
        let (live, vod, series) = try await database.read { db in
            (
                try db.columns(in: "liveStream").map(\.name),
                try db.columns(in: "vodStream").map(\.name),
                try db.columns(in: "series").map(\.name)
            )
        }

        #expect(Self.columnNames(CatalogRows.liveColumns, table: "liveStream").sorted() == live.sorted())
        #expect(Self.columnNames(CatalogRows.vodColumns, table: "vodStream").sorted() == vod.sorted())
        #expect(Self.columnNames(CatalogRows.seriesColumns, table: "series").sorted() == series.sorted())
    }

    private static func columnNames(_ list: String, table: String) -> [String] {
        list.split(separator: ",").map { entry in
            entry
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\(table).", with: "")
                .replacingOccurrences(of: "\"", with: "")
        }
    }

    // MARK: - Uncategorized bucket

    @Test
    func liveStreamsWithoutAValidCategoryAreBucketedAsUncategorized() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let categories = [
            PlaylistCatalogFixture.category("1", type: "live", sortIndex: 4, in: playlist),
            // Same id under another type: must not make a live stream "categorized".
            PlaylistCatalogFixture.category("999", type: "vod", in: playlist),
        ]
        let streams = [
            PlaylistCatalogFixture.live(1, category: "1", in: playlist),
            PlaylistCatalogFixture.live(2, category: nil, in: playlist),
            PlaylistCatalogFixture.live(3, category: "0", in: playlist),
            PlaylistCatalogFixture.live(4, category: "999", in: playlist),
            PlaylistCatalogFixture.live(5, category: "", in: playlist),
        ]
        try await database.write { db in
            for row in categories { try row.insert(db) }
            for row in streams { try row.insert(db) }
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchLiveCatalog(playlistId: pid, db: db)
        }

        #expect(Set(catalog.byCategory.keys) == ["1", uncategorized])
        #expect(catalog.byCategory["1"]?.map(\.stream.streamId) == [1])
        #expect(catalog.byCategory[uncategorized]?.map(\.stream.streamId) == [2, 3, 4, 5])
        #expect(catalog.streams.map(\.stream.streamId) == [1, 2, 3, 4, 5])

        #expect(catalog.categories.map(\.id) == ["1", uncategorized])
        let synthetic = try #require(catalog.categories.last)
        #expect(synthetic.type == "live")
        #expect(synthetic.sortIndex == 5)
        #expect(synthetic.playlistId == pid)
        #expect(synthetic.name == L("content.uncategorized"))
    }

    @Test
    func moviesAndSeriesGetTheSameBucket() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let categories = [
            PlaylistCatalogFixture.category("10", type: "vod", in: playlist),
            PlaylistCatalogFixture.category("20", type: "series", in: playlist),
        ]
        let movies = [
            PlaylistCatalogFixture.vod(100, category: "10", in: playlist),
            PlaylistCatalogFixture.vod(101, category: "20", in: playlist),
        ]
        let shows = [
            PlaylistCatalogFixture.series(500, category: nil, in: playlist),
            PlaylistCatalogFixture.series(501, category: "20", in: playlist),
        ]
        try await database.write { db in
            for row in categories { try row.insert(db) }
            for row in movies { try row.insert(db) }
            for row in shows { try row.insert(db) }
        }

        let (vod, series) = try await database.read { db in
            (
                try PlaylistContentStore.fetchVODCatalog(playlistId: pid, db: db),
                try PlaylistContentStore.fetchSeriesCatalog(playlistId: pid, db: db)
            )
        }

        #expect(vod.categories.map(\.id) == ["10", uncategorized])
        #expect(vod.byCategory[uncategorized]?.map(\.stream.streamId) == [101])
        #expect(vod.byCategory["10"]?.map(\.stream.streamId) == [100])
        #expect(series.categories.map(\.id) == ["20", uncategorized])
        #expect(series.byCategory[uncategorized]?.map(\.series.seriesId) == [500])
        #expect(series.byCategory["20"]?.map(\.series.seriesId) == [501])
    }

    @Test
    func aFullyCategorizedCatalogGetsNoSyntheticCategory() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let category = PlaylistCatalogFixture.category("1", type: "live", in: playlist)
        let stream = PlaylistCatalogFixture.live(1, category: "1", in: playlist)
        try await database.write { db in
            try category.insert(db)
            try stream.insert(db)
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchLiveCatalog(playlistId: pid, db: db)
        }

        #expect(catalog.categories == [category])
        #expect(Array(catalog.byCategory.keys) == ["1"])
    }

    @Test
    func bucketingKeepsCatalogOrderInsideEachBucket() {
        let items = [("a", "1"), ("b", nil), ("c", "1"), ("d", "2"), ("e", "")]
        let buckets = PlaylistContentStore.bucketed(items, validIds: ["1"]) { $0.1 }

        #expect(buckets["1"]?.map(\.0) == ["a", "c"])
        #expect(buckets[uncategorized]?.map(\.0) == ["b", "d", "e"])
        #expect(buckets.count == 2)
    }

    // MARK: - Recently added candidates

    @Test
    func newestIndicesSortByTimestampDescendingAndSkipMissingOnes() {
        let stamps: [Int?] = [5, nil, 9, 1, 7]
        let indices = PlaylistContentStore.newestIndices(count: stamps.count, limit: 10) { stamps[$0] }

        #expect(indices == [2, 4, 0, 3])
    }

    @Test
    func newestIndicesBreakTiesByOriginalPosition() {
        let stamps = [3, 8, 3, 8, 3]
        let indices = PlaylistContentStore.newestIndices(count: stamps.count, limit: 10) { stamps[$0] }

        #expect(indices == [1, 3, 0, 2, 4])
    }

    @Test
    func newestIndicesStopAtTheLimit() {
        let stamps = Array(0..<50)

        #expect(PlaylistContentStore.newestIndices(count: 50, limit: 3) { stamps[$0] } == [49, 48, 47])
        #expect(PlaylistContentStore.newestIndices(count: 50, limit: 0) { stamps[$0] }.isEmpty)
        #expect(PlaylistContentStore.newestIndices(count: 0, limit: 3) { stamps[$0] }.isEmpty)
    }

    @Test
    func recentMoviesAreNewestFirstNumericOnlyAndCapped() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let limit = PlaylistContentStore.recentCandidateLimit
        let dated = limit + 5
        // 37 and 205 share no factor, so the timestamps are all different and in an
        // order unrelated to the catalog order.
        var movies = (0..<dated).map { index in
            PlaylistCatalogFixture.vod(
                index + 1, category: "10", added: String(1_700_000_000 + (index * 37) % dated), in: playlist
            )
        }
        movies.append(PlaylistCatalogFixture.vod(9_000, category: "10", added: nil, in: playlist))
        movies.append(PlaylistCatalogFixture.vod(9_001, category: "10", added: "soon", in: playlist))
        movies.append(PlaylistCatalogFixture.vod(9_002, category: "10", added: "", in: playlist))
        movies.append(PlaylistCatalogFixture.vod(9_003, category: "10", added: " 1800000000", in: playlist))
        let category = PlaylistCatalogFixture.category("10", type: "vod", in: playlist)
        let rows = movies
        try await database.write { db in
            try category.insert(db)
            for row in rows { try row.insert(db) }
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchVODCatalog(playlistId: pid, db: db)
        }

        #expect(limit == 200)
        #expect(catalog.recent.count == limit)
        let stamps = catalog.recent.compactMap { $0.added.flatMap { Int($0) } }
        let newest = 1_700_000_000 + dated - 1
        #expect(stamps == (0..<limit).map { newest - $0 })

        // Same result as sorting the whole catalog, which is what the screens used to do.
        let fullSort = catalog.streams
            .compactMap { item in item.stream.added.flatMap { Int($0) }.map { (item.stream.streamId, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
        #expect(catalog.recent.map(\.streamId) == fullSort)
    }

    @Test
    func recentMoviesWithEqualTimestampsKeepCatalogOrder() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let category = PlaylistCatalogFixture.category("10", type: "vod", in: playlist)
        let movies = [
            PlaylistCatalogFixture.vod(1, category: "10", added: "100", in: playlist),
            PlaylistCatalogFixture.vod(2, category: "10", added: "300", in: playlist),
            PlaylistCatalogFixture.vod(3, category: "10", added: "100", in: playlist),
            PlaylistCatalogFixture.vod(4, category: "10", added: "300", in: playlist),
            PlaylistCatalogFixture.vod(5, category: "10", added: "200", in: playlist),
        ]
        try await database.write { db in
            try category.insert(db)
            for row in movies { try row.insert(db) }
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchVODCatalog(playlistId: pid, db: db)
        }

        #expect(catalog.recent.map(\.streamId) == [2, 4, 5, 1, 3])
    }

    /// A panel can send streams for bouquets it does not list as categories. No shelf
    /// shows them as "recently added", so they must not push listed movies out of the
    /// candidates, however new they are.
    @Test
    func recentMoviesLeaveOutItemsWithoutAListedCategory() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let limit = PlaylistContentStore.recentCandidateLimit
        let categories = [
            PlaylistCatalogFixture.category("10", type: "vod", in: playlist),
            // Listed, but for another content type.
            PlaylistCatalogFixture.category("20", type: "series", in: playlist),
        ]
        // More orphans than the cap, every one newer than every listed movie.
        let orphanCategories: [String?] = [nil, "", "0", "77", "20"]
        let orphanCount = limit + 40
        var movies = (0..<orphanCount).map { index in
            PlaylistCatalogFixture.vod(
                1_000 + index, category: orphanCategories[index % orphanCategories.count],
                added: String(1_800_000_000 + index), in: playlist
            )
        }
        let listedCount = 30
        movies += (0..<listedCount).map { index in
            PlaylistCatalogFixture.vod(index + 1, category: "10", added: String(1_700_000_000 + index), in: playlist)
        }
        let rows = movies
        try await database.write { db in
            for row in categories { try row.insert(db) }
            for row in rows { try row.insert(db) }
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchVODCatalog(playlistId: pid, db: db)
        }

        #expect(catalog.recent.map(\.streamId) == Array((1...listedCount).reversed()))
        // Left out of the candidates only: they are still in the catalog, under
        // "uncategorized".
        #expect(catalog.streams.count == orphanCount + listedCount)
        #expect(catalog.byCategory[uncategorized]?.count == orphanCount)

        // What a screen computes from the whole catalog: keep the categories it
        // shows, sort, take the first 20.
        let shown: Set<String> = ["10", uncategorized]
        let fullSort = catalog.streams
            .filter { shown.contains($0.stream.categoryId ?? "") }
            .compactMap { item in item.stream.added.flatMap { Int($0) }.map { (item.stream.streamId, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
        let fromCandidates = catalog.recent
            .filter { shown.contains($0.categoryId ?? "") }
            .prefix(20)
            .map(\.streamId)
        #expect(fromCandidates == fullSort)
    }

    @Test
    func recentSeriesLeaveOutItemsWithoutAListedCategory() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let limit = PlaylistContentStore.recentCandidateLimit
        let category = PlaylistCatalogFixture.category("20", type: "series", in: playlist)
        let orphanCount = limit + 10
        var shows = (0..<orphanCount).map { index in
            PlaylistCatalogFixture.series(
                1_000 + index, category: index.isMultiple(of: 2) ? nil : "99",
                lastModified: String(1_800_000_000 + index), in: playlist
            )
        }
        shows.append(PlaylistCatalogFixture.series(1, category: "20", lastModified: "1700000001", in: playlist))
        shows.append(PlaylistCatalogFixture.series(2, category: "20", lastModified: "1700000002", in: playlist))
        let rows = shows
        try await database.write { db in
            try category.insert(db)
            for row in rows { try row.insert(db) }
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchSeriesCatalog(playlistId: pid, db: db)
        }

        #expect(catalog.recent.map(\.seriesId) == [2, 1])
        #expect(catalog.byCategory[uncategorized]?.count == orphanCount)
    }

    @Test
    func anItemIsListedOnlyUnderOneOfTheCategoryIdsGiven() {
        let ids: Set<String> = ["10", "11"]

        #expect(PlaylistContentStore.isListed("10", in: ids))
        #expect(!PlaylistContentStore.isListed("12", in: ids))
        #expect(!PlaylistContentStore.isListed("", in: ids))
        #expect(!PlaylistContentStore.isListed(nil, in: ids))
        #expect(!PlaylistContentStore.isListed(uncategorized, in: ids))
        #expect(!PlaylistContentStore.isListed("10", in: []))
    }

    @Test
    func recentSeriesAreOrderedByLastModified() async throws {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let pid = playlist.id
        let category = PlaylistCatalogFixture.category("20", type: "series", in: playlist)
        let shows = [
            PlaylistCatalogFixture.series(1, category: "20", lastModified: "50", in: playlist),
            PlaylistCatalogFixture.series(2, category: "20", lastModified: nil, in: playlist),
            PlaylistCatalogFixture.series(3, category: "20", lastModified: "70", in: playlist),
            PlaylistCatalogFixture.series(4, category: "20", lastModified: "50", in: playlist),
            PlaylistCatalogFixture.series(5, category: "20", lastModified: "n/a", in: playlist),
        ]
        try await database.write { db in
            try category.insert(db)
            for row in shows { try row.insert(db) }
        }

        let catalog = try await database.read { db in
            try PlaylistContentStore.fetchSeriesCatalog(playlistId: pid, db: db)
        }

        #expect(catalog.recent.map(\.seriesId) == [3, 1, 4])
    }
}
