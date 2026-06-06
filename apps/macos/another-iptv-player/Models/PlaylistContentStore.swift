import Foundation
import GRDB
import Combine

/// Aktif playlist kataloğunu bellekte tutar; açılışta veritabanından yükler, gerekirse API ile doldurur.
@MainActor
final class PlaylistContentStore: ObservableObject {
    static let shared = PlaylistContentStore()

    @Published private(set) var activePlaylistId: UUID?
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var loadError: String?
    /// Kategoriler yüklendi ama içerik (stream) verileri henüz yüklenmedi
    @Published private(set) var streamsLoaded = false

    @Published private(set) var liveCategories: [DBCategory] = []
    @Published private(set) var vodCategories: [DBCategory] = []
    @Published private(set) var seriesCategories: [DBCategory] = []
    @Published private(set) var liveStreams: [LiveStreamWithCategory] = []
    @Published private(set) var vodStreams: [VODWithCategory] = []
    @Published private(set) var seriesItems: [SeriesWithCategory] = []

    @Published private(set) var liveStreamsByCategoryId: [String: [LiveStreamWithCategory]] = [:]
    @Published private(set) var vodStreamsByCategoryId: [String: [VODWithCategory]] = [:]
    @Published private(set) var seriesItemsByCategoryId: [String: [SeriesWithCategory]] = [:]

    private var loadToken: UUID?
    private init() {}

    private func clearLists() {
        liveCategories = []
        vodCategories = []
        seriesCategories = []
        liveStreams = []
        vodStreams = []
        seriesItems = []
        liveStreamsByCategoryId = [:]
        vodStreamsByCategoryId = [:]
        seriesItemsByCategoryId = [:]
        streamsLoaded = false
    }

    // MARK: - Filtreleme (UI)

    /// O(1) dictionary lookup yerine O(n) full-array scan yapan eski yaklaşım kaldırıldı.
    func liveStreams(inCategoryId categoryId: String, searchText: String) -> [LiveStreamWithCategory] {
        let base = liveStreamsByCategoryId[categoryId] ?? []
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
        return CatalogTextSearch.sortLiveByRelevance(filtered, search: q)
    }

    func vodStreams(inCategoryId categoryId: String, searchText: String) -> [VODWithCategory] {
        let base = vodStreamsByCategoryId[categoryId] ?? []
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
        return CatalogTextSearch.sortVODByRelevance(filtered, search: q)
    }

    func seriesItems(inCategoryId categoryId: String, searchText: String) -> [SeriesWithCategory] {
        let base = seriesItemsByCategoryId[categoryId] ?? []
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.series.name) }
        return CatalogTextSearch.sortSeriesByRelevance(filtered, search: q)
    }

    func liveStreams(searchText: String) -> [LiveStreamWithCategory] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let filtered = liveStreams.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
        return CatalogTextSearch.sortLiveByRelevance(filtered, search: q)
    }

    func vodStreams(searchText: String) -> [VODWithCategory] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let filtered = vodStreams.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
        return CatalogTextSearch.sortVODByRelevance(filtered, search: q)
    }

    func seriesItems(searchText: String) -> [SeriesWithCategory] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let filtered = seriesItems.filter { CatalogTextSearch.matches(search: q, text: $0.series.name) }
        return CatalogTextSearch.sortSeriesByRelevance(filtered, search: q)
    }

    // MARK: - Açılış

    func loadPlaylist(_ playlist: Playlist) async {
        let token = UUID()
        loadToken = token
        loadError = nil
        loadingMessage = nil

        if activePlaylistId != playlist.id {
            clearLists()
            activePlaylistId = playlist.id
            isLoading = true
        } else if liveCategories.isEmpty {
            isLoading = true
        }

        do {
            let needsSync = try await Self.needsNetworkBootstrap(playlistId: playlist.id)
            if needsSync {
                isLoading = true
                loadingMessage = L("phase.preparing")
                try await syncFromNetworkReplacingLocal(playlist: playlist) { msg in
                    guard self.loadToken == token else { return }
                    self.loadingMessage = msg
                }
                guard loadToken == token else { return }
                loadingMessage = L("phase.preparing_list")
            }

            // Faz 1: Sadece kategoriler (çok hızlı – genellikle < 5 ms)
            let cats = try await AppDatabase.shared.read { db in
                try Self.fetchCategoriesOnly(playlistId: playlist.id, db: db)
            }
            guard loadToken == token else { return }
            liveCategories = cats.live
            vodCategories = cats.vod
            seriesCategories = cats.series
            streamsLoaded = false
            loadingMessage = nil
            isLoading = false   // ← UI kategorilerle hemen gösterilir

            // Faz 2: İçerikler paralel olarak yüklenir (arka planda)
            async let liveTask   = AppDatabase.shared.read { db in try Self.fetchLiveStreamsData(playlistId: playlist.id, db: db) }
            async let vodTask    = AppDatabase.shared.read { db in try Self.fetchVODStreamsData(playlistId: playlist.id, db: db) }
            async let seriesTask = AppDatabase.shared.read { db in try Self.fetchSeriesData(playlistId: playlist.id, db: db) }

            let (ls, vs, si) = try await (liveTask, vodTask, seriesTask)
            guard loadToken == token else { return }
            liveStreams = ls.streams
            liveStreamsByCategoryId = ls.byCategory
            vodStreams = vs.streams
            vodStreamsByCategoryId = vs.byCategory
            seriesItems = si.items
            seriesItemsByCategoryId = si.byCategory
            streamsLoaded = true
        } catch {
            guard loadToken == token else { return }
            loadError = error.localizedDescription
            loadingMessage = nil
            isLoading = false
        }
    }

    /// Ayarlar’dan tam yenileme sonrası belleği güncelle.
    func reloadFromDatabaseIfActive(playlistId: UUID) async {
        guard activePlaylistId == playlistId else { return }
        do {
            try await reloadFromDatabase(playlistId: playlistId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static func needsNetworkBootstrap(playlistId: UUID) async throws -> Bool {
        try await AppDatabase.shared.read { db in
            let cat = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category WHERE playlistId = ?", arguments: [playlistId]) ?? 0
            return cat == 0
        }
    }

    func reloadFromDatabase(playlistId: UUID) async throws {
        // Faz 1: Kategoriler (hızlı)
        let cats = try await AppDatabase.shared.read { db in
            try Self.fetchCategoriesOnly(playlistId: playlistId, db: db)
        }
        liveCategories = cats.live
        vodCategories = cats.vod
        seriesCategories = cats.series
        streamsLoaded = false

        // Faz 2: İçerikler paralel
        async let liveTask   = AppDatabase.shared.read { db in try Self.fetchLiveStreamsData(playlistId: playlistId, db: db) }
        async let vodTask    = AppDatabase.shared.read { db in try Self.fetchVODStreamsData(playlistId: playlistId, db: db) }
        async let seriesTask = AppDatabase.shared.read { db in try Self.fetchSeriesData(playlistId: playlistId, db: db) }

        let (ls, vs, si) = try await (liveTask, vodTask, seriesTask)
        liveStreams = ls.streams
        liveStreamsByCategoryId = ls.byCategory
        vodStreams = vs.streams
        vodStreamsByCategoryId = vs.byCategory
        seriesItems = si.items
        seriesItemsByCategoryId = si.byCategory
        streamsLoaded = true
    }

    // MARK: - DB Fetch Helpers

    private struct CategoriesBundle {
        let live: [DBCategory]
        let vod: [DBCategory]
        let series: [DBCategory]
    }

    private struct LiveStreamsData {
        let streams: [LiveStreamWithCategory]
        let byCategory: [String: [LiveStreamWithCategory]]
    }

    private struct VODStreamsData {
        let streams: [VODWithCategory]
        let byCategory: [String: [VODWithCategory]]
    }

    private struct SeriesData {
        let items: [SeriesWithCategory]
        let byCategory: [String: [SeriesWithCategory]]
    }

    private static func fetchCategoriesOnly(playlistId: UUID, db: Database) throws -> CategoriesBundle {
        let live = try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == "live")
            .order(Column("sortIndex"))
            .fetchAll(db)
        let vod = try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == "vod")
            .order(Column("sortIndex"))
            .fetchAll(db)
        let series = try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == "series")
            .order(Column("sortIndex"))
            .fetchAll(db)
        return CategoriesBundle(live: live, vod: vod, series: series)
    }

    private static func fetchLiveStreamsData(playlistId: UUID, db: Database) throws -> LiveStreamsData {
        let sql = """
        SELECT liveStream.*, category.name AS categoryName
        FROM liveStream
        JOIN category ON liveStream.categoryId = category.id
                     AND liveStream.playlistId = category.playlistId
                     AND category.type = 'live'
        WHERE liveStream.playlistId = ?
        ORDER BY liveStream.sortIndex
        """
        let streams = try LiveStreamWithCategory.fetchAll(db, sql: sql, arguments: [playlistId])
        return LiveStreamsData(streams: streams, byCategory: Dictionary(grouping: streams) { $0.stream.categoryId ?? "" })
    }

    private static func fetchVODStreamsData(playlistId: UUID, db: Database) throws -> VODStreamsData {
        let sql = """
        SELECT vodStream.*, category.name AS categoryName
        FROM vodStream
        JOIN category ON vodStream.categoryId = category.id
                     AND vodStream.playlistId = category.playlistId
                     AND category.type = 'vod'
        WHERE vodStream.playlistId = ?
        ORDER BY vodStream.sortIndex
        """
        let streams = try VODWithCategory.fetchAll(db, sql: sql, arguments: [playlistId])
        return VODStreamsData(streams: streams, byCategory: Dictionary(grouping: streams) { $0.stream.categoryId ?? "" })
    }

    private static func fetchSeriesData(playlistId: UUID, db: Database) throws -> SeriesData {
        let sql = """
        SELECT series.*, category.name AS categoryName
        FROM series
        JOIN category ON series.categoryId = category.id
                     AND series.playlistId = category.playlistId
                     AND category.type = 'series'
        WHERE series.playlistId = ?
        ORDER BY series.sortIndex
        """
        let items = try SeriesWithCategory.fetchAll(db, sql: sql, arguments: [playlistId])
        return SeriesData(items: items, byCategory: Dictionary(grouping: items) { $0.series.categoryId ?? "" })
    }

    // MARK: - Ağ senkronu (Xtream → SQLite)

    /// Ayarlar ekranı: aşamalı ilerleme mesajı ile tam yenileme.
    func syncFromNetworkReplacingLocal(playlist: Playlist, progress: @escaping (String) -> Void) async throws {
        progress(L("phase.clearing_content"))
        let client = XtreamAPIClient(playlist: playlist)
        let pid = playlist.id

        try await AppDatabase.shared.write { db in
            try db.execute(sql: "DELETE FROM category WHERE playlistId = ?", arguments: [pid])
            try db.execute(sql: "DELETE FROM liveStream WHERE playlistId = ?", arguments: [pid])
            try db.execute(sql: "DELETE FROM vodStream WHERE playlistId = ?", arguments: [pid])
            try db.execute(sql: "DELETE FROM series WHERE playlistId = ?", arguments: [pid])
        }

        progress(L("phase.fetch_categories"))
        let liveCats = try await client.getLiveCategories()
        let vodCats = try await client.getVODCategories()
        let seriesCats = try await client.getSeriesCategories()

        progress(L("phase.fetch_live"))
        let liveStreamsAPI = try await client.getLiveStreams()

        progress(L("phase.fetch_movies"))
        let vods = try await client.getVODStreams()

        progress(L("phase.fetch_series"))
        let series = try await client.getSeries()

        // Yetişkin içerik filtresi
        let filterAdult = playlist.filterAdultContent
        let adultLiveCatIds  = filterAdult ? AdultContentFilter.adultCategoryIds(from: liveCats)   : []
        let adultVodCatIds   = filterAdult ? AdultContentFilter.adultCategoryIds(from: vodCats)    : []
        let adultSeriesCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: seriesCats) : []

        progress(L("phase.save_db"))
        try await AppDatabase.shared.write { db in
            for (index, cat) in liveCats.enumerated() {
                if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "live", sortIndex: index, playlistId: pid)
                try dbCat.save(db)
            }
            for (index, cat) in vodCats.enumerated() {
                if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "vod", sortIndex: index, playlistId: pid)
                try dbCat.save(db)
            }
            for (index, cat) in seriesCats.enumerated() {
                if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "series", sortIndex: index, playlistId: pid)
                try dbCat.save(db)
            }

            for (index, stream) in liveStreamsAPI.enumerated() {
                if filterAdult, AdultContentFilter.isAdultLiveStream(stream, adultCategoryIds: adultLiveCatIds) { continue }
                let dbStream = DBLiveStream(streamId: stream.id, name: stream.name ?? L("content.unnamed"), streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId, categoryId: stream.categoryId, sortIndex: index, playlistId: pid)
                try dbStream.save(db)
            }

            for (index, stream) in vods.enumerated() {
                if filterAdult, AdultContentFilter.isAdultVODStream(stream, adultCategoryIds: adultVodCatIds) { continue }
                var dbVOD = DBVODStream(streamId: stream.id, name: stream.name ?? L("content.unnamed"), streamIcon: stream.streamIcon, categoryId: stream.categoryId, rating: stream.rating, containerExtension: stream.containerExtension, sortIndex: index, playlistId: pid)
                dbVOD.added = stream.added
                try dbVOD.save(db)
            }

            for (index, s) in series.enumerated() {
                if filterAdult, let cid = s.categoryId, adultSeriesCatIds.contains(cid) { continue }
                let dbSeries = DBSeries(
                    seriesId: s.id,
                    name: s.name ?? L("content.unnamed"),
                    cover: s.cover,
                    plot: s.plot,
                    cast: s.cast,
                    director: s.director,
                    genre: s.genre,
                    releaseDate: s.releaseDate,
                    rating: s.rating,
                    lastModified: s.lastModified,
                    youtubeTrailer: s.youtubeTrailer,
                    categoryId: s.categoryId,
                    sortIndex: index,
                    playlistId: pid
                )
                try dbSeries.save(db)
            }
        }
    }
}
