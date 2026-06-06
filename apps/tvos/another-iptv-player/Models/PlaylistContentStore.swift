import Foundation
import GRDB
import Combine

@MainActor
final class PlaylistContentStore: ObservableObject {
    static let shared = PlaylistContentStore()

    @Published private(set) var activePlaylistId: UUID?
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var loadError: String?
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

    // MARK: - Filtering

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

    // MARK: - Load

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
            let hasCategories = try await PlaylistContentLoader.hasAnyCategory(playlistId: playlist.id)
            if !hasCategories {
                isLoading = true
                loadingMessage = L("phase.preparing")
                try await PlaylistSyncService.syncReplacingLocal(playlist: playlist) { phase in
                    Task { @MainActor in
                        guard self.loadToken == token else { return }
                        self.loadingMessage = phase.localizedMessage
                    }
                }
                guard loadToken == token else { return }
                loadingMessage = L("phase.preparing_list")
            }

            try await hydrate(playlistId: playlist.id, token: token, showLoading: true)
        } catch {
            guard loadToken == token else { return }
            loadError = error.localizedDescription
            loadingMessage = nil
            isLoading = false
        }
    }

    func reloadFromDatabaseIfActive(playlistId: UUID) async {
        guard activePlaylistId == playlistId else { return }
        do {
            try await reloadFromDatabase(playlistId: playlistId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func reloadFromDatabase(playlistId: UUID) async throws {
        try await hydrate(playlistId: playlistId, token: loadToken, showLoading: false)
    }

    // MARK: - Refresh (used by Settings → Refresh button)

    func refreshFromNetwork(
        playlist: Playlist,
        progress: @escaping (PlaylistSyncService.Phase) -> Void = { _ in }
    ) async throws {
        try await PlaylistSyncService.syncReplacingLocal(playlist: playlist, progress: progress)
        try await reloadFromDatabase(playlistId: playlist.id)
    }

    // MARK: - Private

    private func hydrate(playlistId: UUID, token: UUID?, showLoading: Bool) async throws {
        let cats = try await PlaylistContentLoader.fetchCategories(playlistId: playlistId)
        guard loadToken == token else { return }
        liveCategories = cats.live
        vodCategories = cats.vod
        seriesCategories = cats.series
        streamsLoaded = false

        if showLoading {
            loadingMessage = nil
            isLoading = false
        }

        async let liveTask   = PlaylistContentLoader.fetchLiveStreams(playlistId: playlistId)
        async let vodTask    = PlaylistContentLoader.fetchVODStreams(playlistId: playlistId)
        async let seriesTask = PlaylistContentLoader.fetchSeries(playlistId: playlistId)

        let (ls, vs, si) = try await (liveTask, vodTask, seriesTask)
        guard loadToken == token else { return }
        liveStreams = ls.streams
        liveStreamsByCategoryId = ls.byCategory
        vodStreams = vs.streams
        vodStreamsByCategoryId = vs.byCategory
        seriesItems = si.items
        seriesItemsByCategoryId = si.byCategory
        streamsLoaded = true
    }
}
