package dev.android.anotheriptvplayer.data

import android.content.Context
import android.util.Log
import androidx.room.withTransaction
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.CategoryEntity
import dev.android.anotheriptvplayer.data.local.LiveStreamEntity
import dev.android.anotheriptvplayer.data.local.LiveStreamWithCategory
import dev.android.anotheriptvplayer.data.local.SeriesEntity
import dev.android.anotheriptvplayer.data.local.SeriesWithCategory
import dev.android.anotheriptvplayer.data.local.VodStreamEntity
import dev.android.anotheriptvplayer.data.local.VodStreamWithCategory
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.networking.XtreamApiClient
import dev.android.anotheriptvplayer.networking.XtreamCategory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Kotlin port of iOS `PlaylistContentStore`.
 *
 * Owns the catalog (categories + streams + series) for the currently
 * "active" playlist. Backed by SQLite — exposed to the UI as [StateFlow]s.
 *
 * Lifecycle of [loadPlaylist]:
 *  1. If the playlist isn't bootstrapped (no rows in `category`), call
 *     [syncFromNetworkReplacingLocal] which clears the playlist's catalog
 *     and reinserts everything in one Room transaction.
 *  2. Phase 1 — read categories from SQLite. Fast (a few ms); UI flips out
 *     of the loading state as soon as this lands.
 *  3. Phase 2 — read live / vod / series streams in parallel. UI shows
 *     content category-by-category as it arrives.
 *
 * [loadToken] is used the same way as iOS: when the active playlist changes
 * mid-flight, the new token invalidates any pending publishes from the
 * previous load.
 */
class PlaylistContentStore(
    private val database: AppDatabase,
    context: Context,
    private val apiClientFactory: (Playlist) -> XtreamApiClient = ::XtreamApiClient,
) {

    private val appContext: Context = context.applicationContext

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /**
     * iOS uses `loadToken: UUID?` on `@MainActor` and reads it synchronously
     * from closures. We get the same single-writer guarantee by confining
     * writes to the [scope] (Main dispatcher) and marking the field volatile
     * so HTTP-completion callbacks resuming on IO can also compare safely.
     */
    @Volatile private var loadToken: UUID? = null

    private val _activePlaylistId = MutableStateFlow<String?>(null)
    val activePlaylistId: StateFlow<String?> = _activePlaylistId.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _loadingMessage = MutableStateFlow<String?>(null)
    val loadingMessage: StateFlow<String?> = _loadingMessage.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError: StateFlow<String?> = _loadError.asStateFlow()

    /** True once phase 2 finishes; categories alone don't flip this. */
    private val _streamsLoaded = MutableStateFlow(false)
    val streamsLoaded: StateFlow<Boolean> = _streamsLoaded.asStateFlow()

    private val _liveCategories = MutableStateFlow<List<CategoryEntity>>(emptyList())
    val liveCategories: StateFlow<List<CategoryEntity>> = _liveCategories.asStateFlow()
    private val _vodCategories = MutableStateFlow<List<CategoryEntity>>(emptyList())
    val vodCategories: StateFlow<List<CategoryEntity>> = _vodCategories.asStateFlow()
    private val _seriesCategories = MutableStateFlow<List<CategoryEntity>>(emptyList())
    val seriesCategories: StateFlow<List<CategoryEntity>> = _seriesCategories.asStateFlow()

    private val _liveStreams = MutableStateFlow<List<LiveStreamWithCategory>>(emptyList())
    val liveStreams: StateFlow<List<LiveStreamWithCategory>> = _liveStreams.asStateFlow()
    private val _vodStreams = MutableStateFlow<List<VodStreamWithCategory>>(emptyList())
    val vodStreams: StateFlow<List<VodStreamWithCategory>> = _vodStreams.asStateFlow()
    private val _seriesItems = MutableStateFlow<List<SeriesWithCategory>>(emptyList())
    val seriesItems: StateFlow<List<SeriesWithCategory>> = _seriesItems.asStateFlow()

    private val _liveStreamsByCategoryId =
        MutableStateFlow<Map<String, List<LiveStreamWithCategory>>>(emptyMap())
    val liveStreamsByCategoryId: StateFlow<Map<String, List<LiveStreamWithCategory>>> =
        _liveStreamsByCategoryId.asStateFlow()
    private val _vodStreamsByCategoryId =
        MutableStateFlow<Map<String, List<VodStreamWithCategory>>>(emptyMap())
    val vodStreamsByCategoryId: StateFlow<Map<String, List<VodStreamWithCategory>>> =
        _vodStreamsByCategoryId.asStateFlow()
    private val _seriesItemsByCategoryId =
        MutableStateFlow<Map<String, List<SeriesWithCategory>>>(emptyMap())
    val seriesItemsByCategoryId: StateFlow<Map<String, List<SeriesWithCategory>>> =
        _seriesItemsByCategoryId.asStateFlow()

    fun loadPlaylist(playlist: Playlist) {
        scope.launch { loadPlaylistSuspending(playlist) }
    }

    /**
     * Convenience for callers that already have a coroutine to await on
     * (e.g. tests, or UI that wants to chain navigation after the sync).
     */
    suspend fun loadPlaylistSuspending(playlist: Playlist) {
        val token = UUID.randomUUID()
        loadToken = token

        _loadError.value = null
        _loadingMessage.value = null

        if (_activePlaylistId.value != playlist.id) {
            clearLists()
            _activePlaylistId.value = playlist.id
            _isLoading.value = true
        } else if (_liveCategories.value.isEmpty()) {
            _isLoading.value = true
        }

        try {
            val needsSync = needsNetworkBootstrap(playlist.id)
            if (needsSync) {
                _isLoading.value = true
                _loadingMessage.value = appContext.getString(R.string.sync_preparing)
                syncFromNetworkReplacingLocal(playlist) { msg ->
                    if (loadToken == token) _loadingMessage.value = msg
                }
                if (loadToken != token) return
                _loadingMessage.value = appContext.getString(R.string.sync_list_preparing)
            }

            // Phase 1 — categories.
            val cats = fetchCategoriesOnly(playlist.id)
            if (loadToken != token) return
            _liveCategories.value = cats.live
            _vodCategories.value = cats.vod
            _seriesCategories.value = cats.series
            _streamsLoaded.value = false
            _loadingMessage.value = null
            _isLoading.value = false

            // Phase 2 — content in parallel.
            val (live, vod, series) = parallelStreams(playlist.id)
            if (loadToken != token) return
            _liveStreams.value = live
            _liveStreamsByCategoryId.value = live.groupBy { it.stream.categoryId.orEmpty() }
            _vodStreams.value = vod
            _vodStreamsByCategoryId.value = vod.groupBy { it.stream.categoryId.orEmpty() }
            _seriesItems.value = series
            _seriesItemsByCategoryId.value = series.groupBy { it.series.categoryId.orEmpty() }
            _streamsLoaded.value = true
        } catch (e: Throwable) {
            if (loadToken != token) return
            Log.e(TAG, "loadPlaylist failed", e)
            _loadError.value = e.message ?: e.javaClass.simpleName
            _loadingMessage.value = null
            _isLoading.value = false
        }
    }

    /**
     * Triggered from Settings → "Full refresh" on iOS. Reloads from disk
     * after the catalog has been re-synced.
     */
    suspend fun reloadFromDatabaseIfActive(playlistId: String) {
        if (_activePlaylistId.value != playlistId) return
        try {
            reloadFromDatabase(playlistId)
        } catch (e: Throwable) {
            _loadError.value = e.message
        }
    }

    suspend fun reloadFromDatabase(playlistId: String) {
        val cats = fetchCategoriesOnly(playlistId)
        _liveCategories.value = cats.live
        _vodCategories.value = cats.vod
        _seriesCategories.value = cats.series
        _streamsLoaded.value = false

        val (live, vod, series) = parallelStreams(playlistId)
        _liveStreams.value = live
        _liveStreamsByCategoryId.value = live.groupBy { it.stream.categoryId.orEmpty() }
        _vodStreams.value = vod
        _vodStreamsByCategoryId.value = vod.groupBy { it.stream.categoryId.orEmpty() }
        _seriesItems.value = series
        _seriesItemsByCategoryId.value = series.groupBy { it.series.categoryId.orEmpty() }
        _streamsLoaded.value = true
    }

    // -------- Internal helpers --------

    private fun clearLists() {
        _liveCategories.value = emptyList()
        _vodCategories.value = emptyList()
        _seriesCategories.value = emptyList()
        _liveStreams.value = emptyList()
        _vodStreams.value = emptyList()
        _seriesItems.value = emptyList()
        _liveStreamsByCategoryId.value = emptyMap()
        _vodStreamsByCategoryId.value = emptyMap()
        _seriesItemsByCategoryId.value = emptyMap()
        _streamsLoaded.value = false
    }

    private data class CategoriesBundle(
        val live: List<CategoryEntity>,
        val vod: List<CategoryEntity>,
        val series: List<CategoryEntity>,
    )

    private suspend fun needsNetworkBootstrap(playlistId: String): Boolean =
        database.categoryDao().countForPlaylist(playlistId) == 0

    /**
     * Snapshot of catalog-row counts for a single playlist. iOS
     * `PlaylistSettingsView.fetchLocalStats` issues the same four queries
     * (we don't include `watchHistory` yet — that table has no DAO).
     */
    data class CatalogStats(
        val liveCount: Int,
        val vodCount: Int,
        val seriesCount: Int,
    )

    suspend fun fetchStats(playlistId: String): CatalogStats = CatalogStats(
        liveCount = database.liveStreamDao().countForPlaylist(playlistId),
        vodCount = database.vodStreamDao().countForPlaylist(playlistId),
        seriesCount = database.seriesDao().countForPlaylist(playlistId),
    )

    private suspend fun fetchCategoriesOnly(playlistId: String): CategoriesBundle {
        val dao = database.categoryDao()
        return CategoriesBundle(
            live = dao.getByPlaylistAndType(playlistId, "live"),
            vod = dao.getByPlaylistAndType(playlistId, "vod"),
            series = dao.getByPlaylistAndType(playlistId, "series"),
        )
    }

    private data class StreamsBundle(
        val live: List<LiveStreamWithCategory>,
        val vod: List<VodStreamWithCategory>,
        val series: List<SeriesWithCategory>,
    )

    private suspend fun parallelStreams(playlistId: String): StreamsBundle {
        return kotlinx.coroutines.coroutineScope {
            val live = async { database.liveStreamDao().getWithCategory(playlistId) }
            val vod = async { database.vodStreamDao().getWithCategory(playlistId) }
            val series = async { database.seriesDao().getWithCategory(playlistId) }
            awaitAll(live, vod, series).let {
                @Suppress("UNCHECKED_CAST")
                StreamsBundle(
                    live = it[0] as List<LiveStreamWithCategory>,
                    vod = it[1] as List<VodStreamWithCategory>,
                    series = it[2] as List<SeriesWithCategory>,
                )
            }
        }
    }

    // -------- Network sync (Xtream → SQLite) --------

    /**
     * Mirrors iOS `syncFromNetworkReplacingLocal`. Wipes the playlist's
     * catalog, fetches the six lists (3 category + 3 stream), applies the
     * adult-content filter, and inserts everything inside a single Room
     * transaction so a mid-write crash leaves the catalog empty (and thus
     * eligible for re-sync) rather than half-written.
     */
    suspend fun syncFromNetworkReplacingLocal(
        playlist: Playlist,
        progress: (String) -> Unit,
    ) {
        progress(appContext.getString(R.string.sync_clearing))
        val pid = playlist.id
        val api = apiClientFactory(playlist)

        // Network fetches first, outside the transaction — long-running I/O
        // and Room write transactions don't mix.
        progress(appContext.getString(R.string.sync_categories))
        val liveCats = api.getLiveCategories()
        val vodCats = api.getVODCategories()
        val seriesCats = api.getSeriesCategories()

        progress(appContext.getString(R.string.sync_live))
        val liveStreamsApi = api.getLiveStreams()

        progress(appContext.getString(R.string.sync_movies))
        val vodsApi = api.getVODStreams()

        progress(appContext.getString(R.string.sync_series))
        val seriesApi = api.getSeries()

        val filterAdult = playlist.filterAdultContent
        val adultLiveCatIds = if (filterAdult) AdultContentFilter.adultCategoryIds(liveCats) else emptySet()
        val adultVodCatIds = if (filterAdult) AdultContentFilter.adultCategoryIds(vodCats) else emptySet()
        val adultSeriesCatIds = if (filterAdult) AdultContentFilter.adultCategoryIds(seriesCats) else emptySet()

        val categoryRows = mutableListOf<CategoryEntity>().apply {
            addAll(mapCategoryRows(liveCats, type = "live", playlistId = pid, filterAdult = filterAdult))
            addAll(mapCategoryRows(vodCats, type = "vod", playlistId = pid, filterAdult = filterAdult))
            addAll(mapCategoryRows(seriesCats, type = "series", playlistId = pid, filterAdult = filterAdult))
        }

        val liveRows = liveStreamsApi
            .filterIndexed { _, stream ->
                !filterAdult || !AdultContentFilter.isAdultLiveStream(stream, adultLiveCatIds)
            }
            .mapIndexed { index, stream ->
                LiveStreamEntity(
                    streamId = stream.streamId ?: 0,
                    name = stream.name ?: appContext.getString(R.string.common_unnamed),
                    streamIcon = stream.streamIcon,
                    epgChannelId = stream.epgChannelId,
                    categoryId = stream.categoryId,
                    sortIndex = index,
                    playlistId = pid,
                )
            }

        val vodRows = vodsApi
            .filterIndexed { _, stream ->
                !filterAdult || !AdultContentFilter.isAdultVODStream(stream, adultVodCatIds)
            }
            .mapIndexed { index, stream ->
                VodStreamEntity(
                    streamId = stream.streamId ?: 0,
                    name = stream.name ?: appContext.getString(R.string.common_unnamed),
                    streamIcon = stream.streamIcon,
                    categoryId = stream.categoryId,
                    rating = stream.rating,
                    containerExtension = stream.containerExtension,
                    sortIndex = index,
                    playlistId = pid,
                    added = stream.added,
                )
            }

        val seriesRows = seriesApi
            .filterIndexed { _, s ->
                !filterAdult || s.categoryId?.let { it !in adultSeriesCatIds } ?: true
            }
            .mapIndexed { index, s ->
                SeriesEntity(
                    seriesId = s.seriesId ?: 0,
                    name = s.name ?: appContext.getString(R.string.common_unnamed),
                    cover = s.cover,
                    plot = s.plot,
                    genre = s.genre,
                    rating = s.rating,
                    categoryId = s.categoryId,
                    sortIndex = index,
                    seasonsLoaded = false,
                    playlistId = pid,
                    cast = s.cast,
                    director = s.director,
                    releaseDate = s.releaseDate,
                    lastModified = s.lastModified,
                    youtubeTrailer = s.youtubeTrailer,
                )
            }

        progress(appContext.getString(R.string.sync_persisting))
        database.withTransaction {
            // DELETE order matters when foreign keys are on: children first.
            database.liveStreamDao().deleteByPlaylist(pid)
            database.vodStreamDao().deleteByPlaylist(pid)
            database.seriesDao().deleteByPlaylist(pid)
            database.categoryDao().deleteByPlaylist(pid)

            database.categoryDao().upsertAll(categoryRows)
            database.liveStreamDao().upsertAll(liveRows)
            database.vodStreamDao().upsertAll(vodRows)
            database.seriesDao().upsertAll(seriesRows)
        }
    }

    private fun mapCategoryRows(
        categories: List<XtreamCategory>,
        type: String,
        playlistId: String,
        filterAdult: Boolean,
    ): List<CategoryEntity> =
        categories
            .filter { !filterAdult || it.categoryName?.let { name -> !AdultContentFilter.isAdultCategoryName(name) } ?: true }
            .mapIndexedNotNull { index, cat ->
                val id = cat.categoryId ?: return@mapIndexedNotNull null
                CategoryEntity(
                    id = id,
                    name = cat.categoryName ?: appContext.getString(R.string.common_unnamed),
                    parentId = cat.parentId,
                    type = type,
                    sortIndex = index,
                    playlistId = playlistId,
                )
            }

    companion object {
        private const val TAG = "PlaylistContentStore"
    }
}
