import Foundation
import GRDB
import Combine

/// Content-type scope for catalog sync/refresh: pull-to-refresh syncs only the
/// pulled tab's data instead of the whole catalog.
enum CatalogContentType {
    case live, vod, series
}

/// Aktif playlist kataloğunu bellekte tutar; açılışta veritabanından yükler, gerekirse API ile doldurur.
@MainActor
final class PlaylistContentStore: ObservableObject {
    static let shared = PlaylistContentStore()

    @Published private(set) var activePlaylistId: UUID?
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var loadError: String?
    /// A failed network refresh of a catalog that is already on screen. Kept apart from
    /// `loadError` (the catalog could not be loaded at all) because the two need
    /// different surfaces and a different retry: this one must hit the network again.
    @Published var refreshError: String?
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

    /// Movies of a listed category with a numeric `added` timestamp, newest first, at
    /// most `recentCandidateLimit`. Computed with the catalog read so the "recently
    /// added" shelf can be filled in the same pass as the category shelves; a view only
    /// has to drop the categories it does not show and keep as many items as it needs.
    @Published private(set) var recentVODCandidates: [DBVODStream] = []
    /// Same for series, by `lastModified`.
    @Published private(set) var recentSeriesCandidates: [DBSeries] = []

    /// Change signals, one per content type. A revision goes up every time that type's
    /// categories or items are replaced, and always as the last assignment of the whole
    /// change (flags and the active playlist included), so whoever reacts to it reads
    /// the final state. `streamsLoaded` alone cannot play this role: it does not change
    /// when the categories land, nor on a scoped reload.
    @Published private(set) var liveRevision = 0
    @Published private(set) var vodRevision = 0
    @Published private(set) var seriesRevision = 0

    private var loadToken: UUID?
    private let database: AppDatabase
    private let makeClient: @MainActor (Playlist) -> XtreamAPIClient

    /// The app only ever uses `shared`. The parameters exist for tests, which run a
    /// private instance against an in-memory database and a canned panel client.
    init(
        database: AppDatabase = .shared,
        makeClient: @escaping @MainActor (Playlist) -> XtreamAPIClient = { XtreamAPIClient(playlist: $0) }
    ) {
        self.database = database
        self.makeClient = makeClient
    }

    /// Empties the catalog without signalling it: a clear is always part of a larger
    /// change (a playlist switch, an unload), and that change bumps the revisions once
    /// its own state is in place.
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
        recentVODCandidates = []
        recentSeriesCandidates = []
        streamsLoaded = false
    }

    // MARK: - Assignment

    // The three `assign` functions are the only places that put streams into the
    // published state. None of them bumps a revision: the caller does that once
    // everything belonging to the same change is in place.

    private func assign(_ catalog: LiveCatalog) {
        liveCategories = catalog.categories
        liveStreams = catalog.streams
        liveStreamsByCategoryId = catalog.byCategory
    }

    private func assign(_ catalog: VODCatalog) {
        vodCategories = catalog.categories
        vodStreams = catalog.streams
        vodStreamsByCategoryId = catalog.byCategory
        recentVODCandidates = catalog.recent
    }

    private func assign(_ catalog: SeriesCatalog) {
        seriesCategories = catalog.categories
        seriesItems = catalog.items
        seriesItemsByCategoryId = catalog.byCategory
        recentSeriesCandidates = catalog.recent
    }

    private func bumpAllRevisions() {
        liveRevision &+= 1
        vodRevision &+= 1
        seriesRevision &+= 1
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
        let interval = BrowsePerformance.begin("CatalogLoad")
        defer { BrowsePerformance.end("CatalogLoad", interval) }
        let token = UUID()
        loadToken = token
        loadError = nil
        loadingMessage = nil

        if activePlaylistId != playlist.id {
            clearLists()
            refreshError = nil
            activePlaylistId = playlist.id
            isLoading = true
            bumpAllRevisions()
        } else if liveCategories.isEmpty {
            isLoading = true
        }

        do {
            // Faz 1: Sadece kategoriler (çok hızlı – genellikle < 5 ms)
            var cats = try await database.read { db in
                try Self.fetchCategoriesOnly(playlistId: playlist.id, db: db)
            }
            guard loadToken == token else { return }

            // No category at all means the catalog was never downloaded: fetch it from
            // the panel first. The category read doubles as that check, which saves a
            // database round trip before the first paint of every ordinary launch.
            if cats.isEmpty {
                isLoading = true
                loadingMessage = L("phase.preparing")
                try await syncFromNetworkReplacingLocal(playlist: playlist) { msg in
                    guard self.loadToken == token else { return }
                    self.loadingMessage = msg
                }
                guard loadToken == token else { return }
                loadingMessage = L("phase.preparing_list")
                cats = try await database.read { db in
                    try Self.fetchCategoriesOnly(playlistId: playlist.id, db: db)
                }
                guard loadToken == token else { return }
            }

            liveCategories = cats.live
            vodCategories = cats.vod
            seriesCategories = cats.series
            streamsLoaded = false
            loadingMessage = nil
            isLoading = false   // ← UI kategorilerle hemen gösterilir
            bumpAllRevisions()

            // Faz 2: İçerikler paralel olarak yüklenir (arka planda)
            let database = self.database
            async let liveTask   = database.read { db in try Self.fetchLiveCatalog(playlistId: playlist.id, db: db) }
            async let vodTask    = database.read { db in try Self.fetchVODCatalog(playlistId: playlist.id, db: db) }
            async let seriesTask = database.read { db in try Self.fetchSeriesCatalog(playlistId: playlist.id, db: db) }

            // Each catalog brings its own category list again: it comes from the same
            // read as the streams and ends with the "uncategorized" entry when needed.
            let (ls, vs, si) = try await (liveTask, vodTask, seriesTask)
            guard loadToken == token else { return }
            assign(ls)
            assign(vs)
            assign(si)
            streamsLoaded = true
            bumpAllRevisions()
        } catch {
            guard loadToken == token else { return }
            loadError = NetworkErrorText.describe(error)
            loadingMessage = nil
            isLoading = false
        }
    }

    /// Dashboard'dan playlist seçicisine dönünce çağrılır: yüz binlerce satırlık
    /// katalog kopyaları (flat + kategori sözlükleri) singleton'da kalmasın.
    /// Yeniden girişte `loadPlaylist` zaten sıfırdan yükler.
    func unload() {
        let interval = BrowsePerformance.begin("CatalogUnload")
        defer { BrowsePerformance.end("CatalogUnload", interval) }
        loadToken = nil
        activePlaylistId = nil
        clearLists()
        loadError = nil
        refreshError = nil
        loadingMessage = nil
        isLoading = false
        bumpAllRevisions()
    }

    /// Full network sync followed by an in-memory reload, the same path as "Refresh
    /// all" in Settings. A failure goes to `refreshError`; the sync is atomic, so the
    /// local content survives it.
    func refreshFromNetwork(playlist: Playlist) async {
        clearRefreshError(ifActive: playlist.id)
        do {
            try await syncFromNetworkReplacingLocal(playlist: playlist) { [weak self] msg in
                self?.setLoadingMessage(msg, ifActive: playlist.id)
            }
            await reloadFromDatabaseIfActive(playlistId: playlist.id)
        } catch {
            reportRefreshFailure(error, playlistId: playlist.id)
        }
        setLoadingMessage(nil, ifActive: playlist.id)
    }

    /// Scoped pull-to-refresh: only the pulled tab's content type is refetched and
    /// rewritten (e.g. the Movies tab syncs VOD categories + streams); the other
    /// types keep their local data untouched.
    func refreshFromNetwork(playlist: Playlist, only type: CatalogContentType) async {
        clearRefreshError(ifActive: playlist.id)
        do {
            try await syncFromNetworkReplacingLocal(playlist: playlist, only: type) { [weak self] msg in
                self?.setLoadingMessage(msg, ifActive: playlist.id)
            }
            await reloadFromDatabaseIfActive(playlistId: playlist.id, only: type)
        } catch {
            reportRefreshFailure(error, playlistId: playlist.id)
        }
        setLoadingMessage(nil, ifActive: playlist.id)
    }

    // A refresh can outlive its playlist (the user switched while the panel was still
    // answering). Its outcome then belongs to nobody: an error would alert on the
    // playlist now open, and its progress text would overwrite that playlist's own.

    private func clearRefreshError(ifActive playlistId: UUID) {
        guard activePlaylistId == playlistId else { return }
        refreshError = nil
    }

    private func reportRefreshFailure(_ error: Error, playlistId: UUID) {
        guard activePlaylistId == playlistId else { return }
        refreshError = NetworkErrorText.describe(error)
    }

    private func setLoadingMessage(_ message: String?, ifActive playlistId: UUID) {
        guard activePlaylistId == playlistId else { return }
        loadingMessage = message
    }

    /// Ayarlar’dan tam yenileme sonrası belleği güncelle.
    func reloadFromDatabaseIfActive(playlistId: UUID) async {
        guard activePlaylistId == playlistId else { return }
        do {
            try await reloadFromDatabase(playlistId: playlistId)
        } catch {
            guard activePlaylistId == playlistId else { return }
            loadError = NetworkErrorText.describe(error)
        }
    }

    /// Scoped in-memory reload: refreshes only one content type's categories and
    /// items. `streamsLoaded` is left alone on purpose: flipping it would blank every
    /// shelf of the tab for a moment; the type's revision is the change signal.
    func reloadFromDatabaseIfActive(playlistId: UUID, only type: CatalogContentType) async {
        guard activePlaylistId == playlistId else { return }
        do {
            switch type {
            case .live:
                let catalog = try await database.read { db in
                    try Self.fetchLiveCatalog(playlistId: playlistId, db: db)
                }
                guard activePlaylistId == playlistId else { return }
                assign(catalog)
                liveRevision &+= 1
            case .vod:
                let catalog = try await database.read { db in
                    try Self.fetchVODCatalog(playlistId: playlistId, db: db)
                }
                guard activePlaylistId == playlistId else { return }
                assign(catalog)
                vodRevision &+= 1
            case .series:
                let catalog = try await database.read { db in
                    try Self.fetchSeriesCatalog(playlistId: playlistId, db: db)
                }
                guard activePlaylistId == playlistId else { return }
                assign(catalog)
                seriesRevision &+= 1
            }
        } catch {
            guard activePlaylistId == playlistId else { return }
            loadError = NetworkErrorText.describe(error)
        }
    }

    /// Replaces the whole in-memory catalog in one step. The lists stay as they are
    /// until the new ones are complete, so a reload never publishes a half catalog.
    /// `streamsLoaded` is down while the reads run, as during a load: a screen that
    /// follows only that flag still learns that the catalog was replaced.
    func reloadFromDatabase(playlistId: UUID) async throws {
        guard activePlaylistId == playlistId else { return }
        let wasLoaded = streamsLoaded
        streamsLoaded = false

        let database = self.database
        async let liveTask   = database.read { db in try Self.fetchLiveCatalog(playlistId: playlistId, db: db) }
        async let vodTask    = database.read { db in try Self.fetchVODCatalog(playlistId: playlistId, db: db) }
        async let seriesTask = database.read { db in try Self.fetchSeriesCatalog(playlistId: playlistId, db: db) }

        let ls: LiveCatalog, vs: VODCatalog, si: SeriesCatalog
        do {
            (ls, vs, si) = try await (liveTask, vodTask, seriesTask)
        } catch {
            // Nothing was replaced, so the lists in memory are as complete as before.
            // Only ever raise the flag here: a load running next to this reload owns
            // the lowered state.
            if wasLoaded, activePlaylistId == playlistId { streamsLoaded = true }
            throw error
        }
        // The playlist may have been closed or switched while the reads ran.
        guard activePlaylistId == playlistId else { return }
        assign(ls)
        assign(vs)
        assign(si)
        streamsLoaded = true
        bumpAllRevisions()
    }

    // MARK: - DB Fetch Helpers

    // Everything below runs inside GRDB read closures, off the main actor.

    nonisolated private struct CategoriesBundle {
        let live: [DBCategory]
        let vod: [DBCategory]
        let series: [DBCategory]

        var isEmpty: Bool { live.isEmpty && vod.isEmpty && series.isEmpty }
    }

    /// One content type as it is published: `categories` ends with the synthetic
    /// "uncategorized" entry when `byCategory` has that bucket.
    nonisolated struct LiveCatalog {
        let categories: [DBCategory]
        let streams: [LiveStreamWithCategory]
        let byCategory: [String: [LiveStreamWithCategory]]
    }

    nonisolated struct VODCatalog {
        let categories: [DBCategory]
        let streams: [VODWithCategory]
        let byCategory: [String: [VODWithCategory]]
        let recent: [DBVODStream]
    }

    nonisolated struct SeriesCatalog {
        let categories: [DBCategory]
        let items: [SeriesWithCategory]
        let byCategory: [String: [SeriesWithCategory]]
        let recent: [DBSeries]
    }

    nonisolated private static func fetchCategories(playlistId: UUID, type: String, db: Database) throws -> [DBCategory] {
        try DBCategory
            .filter(Column("playlistId") == playlistId && Column("type") == type)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }

    nonisolated private static func fetchCategoriesOnly(playlistId: UUID, db: Database) throws -> CategoriesBundle {
        CategoriesBundle(
            live: try fetchCategories(playlistId: playlistId, type: "live", db: db),
            vod: try fetchCategories(playlistId: playlistId, type: "vod", db: db),
            series: try fetchCategories(playlistId: playlistId, type: "series", db: db)
        )
    }

    /// Kategorisi olmayan/yetim streamlerin toplandığı sentetik kategori id'si.
    /// HiddenCategoryStore bu id ile persist edebilsin diye sabittir.
    nonisolated static let uncategorizedCategoryId = "__uncategorized__"

    /// Upper bound of `recentVODCandidates` / `recentSeriesCandidates`. Large enough
    /// that hiding a few busy categories still leaves a full shelf; a consumer that
    /// ends up short while the list is at this size knows older items were cut off.
    /// Hidden categories are the only way to get there: items no shelf can show
    /// (see `isListed`) never take a slot.
    nonisolated static let recentCandidateLimit = 200

    // Xtream panelleri category_id'si null/'0'/kategori listesinde olmayan streamler
    // döndürebilir. INNER JOIN bunları tüm ekranlardan sessizce düşürüyordu; LEFT JOIN +
    // COALESCE ile korunur ve "Kategorisiz" başlığı altında gösterilirler.
    //
    // Each fetch reads its categories in the same read as the streams: the bucketing
    // needs the valid ids, and a snapshot taken in one read cannot disagree with itself
    // while a sync is writing. Rows are decoded by column index (see `CatalogRows`).

    nonisolated static func fetchLiveCatalog(playlistId: UUID, db: Database) throws -> LiveCatalog {
        let categories = try fetchCategories(playlistId: playlistId, type: "live", db: db)
        let sql = """
        SELECT \(CatalogRows.liveColumns), COALESCE(category.name, ?) AS categoryName
        FROM liveStream
        LEFT JOIN category ON liveStream.categoryId = category.id
                     AND liveStream.playlistId = category.playlistId
                     AND category.type = 'live'
        WHERE liveStream.playlistId = ?
        ORDER BY liveStream.sortIndex
        """
        var streams: [LiveStreamWithCategory] = []
        let rows = try Row.fetchCursor(db, sql: sql, arguments: [L("content.uncategorized"), playlistId])
        while let row = try rows.next() {
            streams.append(try CatalogRows.live(row))
        }
        let byCategory = bucketed(streams, validIds: Set(categories.map(\.id))) { $0.stream.categoryId }
        return LiveCatalog(
            categories: appendingUncategorized(categories, to: byCategory, type: "live", playlistId: playlistId),
            streams: streams,
            byCategory: byCategory
        )
    }

    nonisolated static func fetchVODCatalog(playlistId: UUID, db: Database) throws -> VODCatalog {
        let categories = try fetchCategories(playlistId: playlistId, type: "vod", db: db)
        let sql = """
        SELECT \(CatalogRows.vodColumns), COALESCE(category.name, ?) AS categoryName
        FROM vodStream
        LEFT JOIN category ON vodStream.categoryId = category.id
                     AND vodStream.playlistId = category.playlistId
                     AND category.type = 'vod'
        WHERE vodStream.playlistId = ?
        ORDER BY vodStream.sortIndex
        """
        var streams: [VODWithCategory] = []
        let rows = try Row.fetchCursor(db, sql: sql, arguments: [L("content.uncategorized"), playlistId])
        while let row = try rows.next() {
            streams.append(try CatalogRows.vod(row))
        }
        let validIds = Set(categories.map(\.id))
        let byCategory = bucketed(streams, validIds: validIds) { $0.stream.categoryId }
        let recent = newestIndices(count: streams.count, limit: recentCandidateLimit) { index in
            let stream = streams[index].stream
            guard isListed(stream.categoryId, in: validIds) else { return nil }
            return stream.added.flatMap { Int($0) }
        }
        return VODCatalog(
            categories: appendingUncategorized(categories, to: byCategory, type: "vod", playlistId: playlistId),
            streams: streams,
            byCategory: byCategory,
            recent: recent.map { streams[$0].stream }
        )
    }

    nonisolated static func fetchSeriesCatalog(playlistId: UUID, db: Database) throws -> SeriesCatalog {
        let categories = try fetchCategories(playlistId: playlistId, type: "series", db: db)
        let sql = """
        SELECT \(CatalogRows.seriesColumns), COALESCE(category.name, ?) AS categoryName
        FROM series
        LEFT JOIN category ON series.categoryId = category.id
                     AND series.playlistId = category.playlistId
                     AND category.type = 'series'
        WHERE series.playlistId = ?
        ORDER BY series.sortIndex
        """
        var items: [SeriesWithCategory] = []
        let rows = try Row.fetchCursor(db, sql: sql, arguments: [L("content.uncategorized"), playlistId])
        while let row = try rows.next() {
            items.append(try CatalogRows.series(row))
        }
        let validIds = Set(categories.map(\.id))
        let byCategory = bucketed(items, validIds: validIds) { $0.series.categoryId }
        let recent = newestIndices(count: items.count, limit: recentCandidateLimit) { index in
            let series = items[index].series
            guard isListed(series.categoryId, in: validIds) else { return nil }
            return series.lastModified.flatMap { Int($0) }
        }
        return SeriesCatalog(
            categories: appendingUncategorized(categories, to: byCategory, type: "series", playlistId: playlistId),
            items: items,
            byCategory: byCategory,
            recent: recent.map { items[$0].series }
        )
    }

    /// Groups items by category id, in their original order. An item whose category
    /// id is nil, empty or not in `validIds` goes to the synthetic "uncategorized"
    /// bucket, so every key of the result is a category that can be shown.
    nonisolated static func bucketed<T>(
        _ items: [T], validIds: Set<String>, categoryId: (T) -> String?
    ) -> [String: [T]] {
        var result: [String: [T]] = [:]
        for item in items {
            let id = categoryId(item) ?? ""
            let key = (id.isEmpty || !validIds.contains(id)) ? uncategorizedCategoryId : id
            result[key, default: []].append(item)
        }
        return result
    }

    /// Whether an item can appear on a "recently added" shelf. The shelves match an
    /// item's own category id against the categories they show, and the synthetic
    /// "uncategorized" id is never an item's own, so an item of an unlisted category
    /// would only use up one of the candidate slots.
    nonisolated static func isListed(_ categoryId: String?, in validIds: Set<String>) -> Bool {
        validIds.contains(categoryId ?? "")
    }

    /// Sentetik "Kategorisiz" bucket'ı doluysa kategori listesinin sonuna görünür bir
    /// kategori ekler; boşsa listeyi aynen döndürür.
    nonisolated static func appendingUncategorized(
        _ categories: [DBCategory],
        to byCategory: [String: [some Any]],
        type: String,
        playlistId: UUID
    ) -> [DBCategory] {
        guard let orphans = byCategory[uncategorizedCategoryId], !orphans.isEmpty else { return categories }
        var result = categories
        result.append(DBCategory(
            id: uncategorizedCategoryId,
            name: L("content.uncategorized"),
            parentId: nil,
            type: type,
            sortIndex: (categories.map(\.sortIndex).max() ?? -1) + 1,
            playlistId: playlistId
        ))
        return result
    }

    /// Indices of the `limit` entries with the highest timestamp, highest first.
    /// Entries for which `timestamp` returns nil are skipped. Equal timestamps keep
    /// their original order, so the result does not depend on the sort algorithm.
    /// Only (timestamp, index) pairs are sorted: moving whole records around costs
    /// about ten times as much on a six-figure catalog.
    nonisolated static func newestIndices(count: Int, limit: Int, timestamp: (Int) -> Int?) -> [Int] {
        var keyed: [(timestamp: Int, index: Int)] = []
        for index in 0..<max(count, 0) {
            if let value = timestamp(index) {
                keyed.append((value, index))
            }
        }
        keyed.sort { lhs, rhs in
            lhs.timestamp != rhs.timestamp ? lhs.timestamp > rhs.timestamp : lhs.index < rhs.index
        }
        return keyed.prefix(max(limit, 0)).map(\.index)
    }

    // MARK: - Ağ senkronu (Xtream → SQLite)

    /// Ayarlar ekranı: aşamalı ilerleme mesajı ile tam yenileme.
    /// Yerel içerik, tüm ağ istekleri başarıyla tamamlanana kadar SİLİNMEZ: silme ve yeniden
    /// yazma tek transaction'da yapılır ki panel/ağ hatası çalışan kütüphaneyi boşaltmasın.
    func syncFromNetworkReplacingLocal(playlist: Playlist, progress: @escaping (String) -> Void) async throws {
        let client = makeClient(playlist)
        let pid = playlist.id

        // Altı endpoint bağımsız — paralel çekim yenileme süresini ciddi kısaltır.
        progress(L("phase.fetch_categories"))
        async let liveCatsTask = client.getLiveCategories()
        async let vodCatsTask = client.getVODCategories()
        async let seriesCatsTask = client.getSeriesCategories()
        async let liveStreamsTask = client.getLiveStreams()
        async let vodsTask = client.getVODStreams()
        async let seriesTask = client.getSeries()
        let (liveCats, vodCats, seriesCats, liveStreamsAPI, vods, series) = try await (
            liveCatsTask, vodCatsTask, seriesCatsTask, liveStreamsTask, vodsTask, seriesTask
        )

        let callerFilterAdult = playlist.filterAdultContent
        progress(L("phase.save_db"))
        try await database.write { db in
            let filterAdult = try Self.adultFilterEnabled(playlistId: pid, fallback: callerFilterAdult, db: db)
            // Delete-then-insert inside one transaction: rolls back together on any error.
            try Self.replaceLiveCatalog(db: db, pid: pid, categories: liveCats, streams: liveStreamsAPI, filterAdult: filterAdult)
            try Self.replaceVODCatalog(db: db, pid: pid, categories: vodCats, streams: vods, filterAdult: filterAdult)
            try Self.replaceSeriesCatalog(db: db, pid: pid, categories: seriesCats, series: series, filterAdult: filterAdult)
        }
    }

    /// Scoped sync: refetches and rewrites a single content type; the other types'
    /// rows are left untouched. Same atomic delete-then-insert guarantee per type.
    func syncFromNetworkReplacingLocal(
        playlist: Playlist, only type: CatalogContentType, progress: @escaping (String) -> Void
    ) async throws {
        let client = makeClient(playlist)
        let pid = playlist.id
        let callerFilterAdult = playlist.filterAdultContent

        progress(L("phase.fetch_categories"))
        switch type {
        case .live:
            async let catsTask = client.getLiveCategories()
            async let streamsTask = client.getLiveStreams()
            let (cats, streams) = try await (catsTask, streamsTask)
            progress(L("phase.save_db"))
            try await database.write { db in
                let filterAdult = try Self.adultFilterEnabled(playlistId: pid, fallback: callerFilterAdult, db: db)
                try Self.replaceLiveCatalog(db: db, pid: pid, categories: cats, streams: streams, filterAdult: filterAdult)
            }
        case .vod:
            async let catsTask = client.getVODCategories()
            async let streamsTask = client.getVODStreams()
            let (cats, streams) = try await (catsTask, streamsTask)
            progress(L("phase.save_db"))
            try await database.write { db in
                let filterAdult = try Self.adultFilterEnabled(playlistId: pid, fallback: callerFilterAdult, db: db)
                try Self.replaceVODCatalog(db: db, pid: pid, categories: cats, streams: streams, filterAdult: filterAdult)
            }
        case .series:
            async let catsTask = client.getSeriesCategories()
            async let seriesTask = client.getSeries()
            let (cats, items) = try await (catsTask, seriesTask)
            progress(L("phase.save_db"))
            try await database.write { db in
                let filterAdult = try Self.adultFilterEnabled(playlistId: pid, fallback: callerFilterAdult, db: db)
                try Self.replaceSeriesCatalog(db: db, pid: pid, categories: cats, series: items, filterAdult: filterAdult)
            }
        }
    }

    // MARK: - DB rewrite helpers (shared by full and scoped sync and by the importer)

    /// Whether a sync has to drop adult content. The `Playlist` a caller holds is a
    /// snapshot from when the playlist was opened, while the switch in Settings
    /// writes the row; reading the row inside the write transaction makes every sync
    /// obey the current setting. The snapshot only decides when the row is missing.
    nonisolated static func adultFilterEnabled(playlistId: UUID, fallback: Bool, db: Database) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT filterAdultContent FROM playlist WHERE id = ?", arguments: [playlistId]
        ) ?? fallback
    }

    // The three helpers delete a type's rows and write the new ones. Rows are written
    // with INSERT OR REPLACE: `save` would first try an UPDATE that cannot match
    // anything after the DELETE, doubling the statements per row, and REPLACE keeps
    // last-one-wins for ids a panel sends twice.

    static func replaceLiveCatalog(
        db: Database, pid: UUID, categories: [XtreamCategory], streams: [XtreamLiveStream], filterAdult: Bool
    ) throws {
        let adultCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: categories) : []
        try db.execute(sql: "DELETE FROM category WHERE playlistId = ? AND type = 'live'", arguments: [pid])
        try db.execute(sql: "DELETE FROM liveStream WHERE playlistId = ?", arguments: [pid])
        for (index, cat) in categories.enumerated() {
            if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
            let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "live", sortIndex: index, playlistId: pid)
            try dbCat.insert(db, onConflict: .replace)
        }
        for (index, stream) in streams.enumerated() {
            if filterAdult, AdultContentFilter.isAdultLiveStream(stream, adultCategoryIds: adultCatIds) { continue }
            let dbStream = DBLiveStream(streamId: stream.id, name: stream.name ?? L("content.unnamed"), streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId, categoryId: stream.categoryId, sortIndex: index, playlistId: pid, tvArchive: stream.tvArchive ?? 0, tvArchiveDuration: stream.tvArchiveDuration ?? 0)
            try dbStream.insert(db, onConflict: .replace)
        }
    }

    static func replaceVODCatalog(
        db: Database, pid: UUID, categories: [XtreamCategory], streams: [XtreamVODStream], filterAdult: Bool
    ) throws {
        let adultCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: categories) : []
        try db.execute(sql: "DELETE FROM category WHERE playlistId = ? AND type = 'vod'", arguments: [pid])
        try db.execute(sql: "DELETE FROM vodStream WHERE playlistId = ?", arguments: [pid])
        for (index, cat) in categories.enumerated() {
            if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
            let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "vod", sortIndex: index, playlistId: pid)
            try dbCat.insert(db, onConflict: .replace)
        }
        for (index, stream) in streams.enumerated() {
            if filterAdult, AdultContentFilter.isAdultVODStream(stream, adultCategoryIds: adultCatIds) { continue }
            var dbVOD = DBVODStream(streamId: stream.id, name: stream.name ?? L("content.unnamed"), streamIcon: stream.streamIcon, categoryId: stream.categoryId, rating: stream.rating, containerExtension: stream.containerExtension, sortIndex: index, playlistId: pid)
            dbVOD.added = stream.added
            try dbVOD.insert(db, onConflict: .replace)
        }
    }

    static func replaceSeriesCatalog(
        db: Database, pid: UUID, categories: [XtreamCategory], series: [XtreamSeries], filterAdult: Bool
    ) throws {
        let adultCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: categories) : []
        try db.execute(sql: "DELETE FROM category WHERE playlistId = ? AND type = 'series'", arguments: [pid])
        try db.execute(sql: "DELETE FROM series WHERE playlistId = ?", arguments: [pid])
        for (index, cat) in categories.enumerated() {
            if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
            let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? L("content.unnamed"), parentId: cat.parentId, type: "series", sortIndex: index, playlistId: pid)
            try dbCat.insert(db, onConflict: .replace)
        }
        for (index, s) in series.enumerated() {
            if filterAdult, let cid = s.categoryId, adultCatIds.contains(cid) { continue }
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
            try dbSeries.insert(db, onConflict: .replace)
        }
    }
}

// MARK: - Bulk row decoding

/// Decodes catalog rows by column index. The join records are `Decodable`, and GRDB's
/// row decoder looks every property up by name through a keyed container: for a
/// six-figure catalog that is most of the time between launch and the first poster.
/// Reading the columns positionally is several times faster.
///
/// The price is that each column list and the function next to it must stay in the
/// same order, and that a new column of a record has to be added to both. The
/// "categoryName" alias of the catalog queries is always the column after the list.
nonisolated enum CatalogRows {
    static let liveColumns = """
        liveStream.streamId, liveStream.name, liveStream.streamIcon, liveStream.epgChannelId, \
        liveStream.categoryId, liveStream.sortIndex, liveStream.playlistId, \
        liveStream.tvArchive, liveStream.tvArchiveDuration
        """

    static func live(_ row: Row) throws -> LiveStreamWithCategory {
        var columns = ColumnReader(row)
        let stream = DBLiveStream(
            streamId: try columns.next(),
            name: try columns.next(),
            streamIcon: try columns.next(),
            epgChannelId: try columns.next(),
            categoryId: try columns.next(),
            sortIndex: try columns.next(),
            playlistId: try columns.next(),
            tvArchive: try columns.next(),
            tvArchiveDuration: try columns.next()
        )
        return LiveStreamWithCategory(stream: stream, categoryName: try columns.next())
    }

    static let vodColumns = """
        vodStream.streamId, vodStream.name, vodStream.streamIcon, vodStream.categoryId, \
        vodStream.rating, vodStream.containerExtension, vodStream.director, vodStream."cast", \
        vodStream.plot, vodStream.genre, vodStream.releaseDate, vodStream.rating5Based, \
        vodStream.backdropPath, vodStream.youtubeTrailer, vodStream.duration, vodStream.tmdbId, \
        vodStream.kinopoiskURL, vodStream.metadataLoaded, vodStream.added, vodStream.sortIndex, \
        vodStream.playlistId
        """

    static func vod(_ row: Row) throws -> VODWithCategory {
        var columns = ColumnReader(row)
        let stream = DBVODStream(
            streamId: try columns.next(),
            name: try columns.next(),
            streamIcon: try columns.next(),
            categoryId: try columns.next(),
            rating: try columns.next(),
            containerExtension: try columns.next(),
            director: try columns.next(),
            cast: try columns.next(),
            plot: try columns.next(),
            genre: try columns.next(),
            releaseDate: try columns.next(),
            rating5Based: try columns.next(),
            backdropPath: try columns.next(),
            youtubeTrailer: try columns.next(),
            duration: try columns.next(),
            tmdbId: try columns.next(),
            kinopoiskURL: try columns.next(),
            metadataLoaded: try columns.next(),
            added: try columns.next(),
            sortIndex: try columns.next(),
            playlistId: try columns.next()
        )
        return VODWithCategory(stream: stream, categoryName: try columns.next())
    }

    static let seriesColumns = """
        series.seriesId, series.name, series.cover, series.plot, series."cast", series.director, \
        series.genre, series.releaseDate, series.rating, series.lastModified, series.rating5Based, \
        series.backdropPath, series.youtubeTrailer, series.episodeRunTime, series.categoryId, \
        series.sortIndex, series.seasonsLoaded, series.playlistId
        """

    static func series(_ row: Row) throws -> SeriesWithCategory {
        var columns = ColumnReader(row)
        let series = DBSeries(
            seriesId: try columns.next(),
            name: try columns.next(),
            cover: try columns.next(),
            plot: try columns.next(),
            cast: try columns.next(),
            director: try columns.next(),
            genre: try columns.next(),
            releaseDate: try columns.next(),
            rating: try columns.next(),
            lastModified: try columns.next(),
            rating5Based: try columns.next(),
            backdropPath: try columns.next(),
            youtubeTrailer: try columns.next(),
            episodeRunTime: try columns.next(),
            categoryId: try columns.next(),
            sortIndex: try columns.next(),
            seasonsLoaded: try columns.next(),
            playlistId: try columns.next()
        )
        return SeriesWithCategory(series: series, categoryName: try columns.next())
    }

    /// Hands out the columns of a row from left to right. Arguments are evaluated in
    /// source order, so an initializer call written in column order needs no indices.
    /// Throws like the `Decodable` path does when a value cannot be converted.
    private struct ColumnReader {
        private let row: Row
        private var index = 0

        init(_ row: Row) {
            self.row = row
        }

        mutating func next<Value: DatabaseValueConvertible & StatementColumnConvertible>() throws -> Value {
            defer { index += 1 }
            return try row.decode(Value.self, atIndex: index)
        }
    }
}
