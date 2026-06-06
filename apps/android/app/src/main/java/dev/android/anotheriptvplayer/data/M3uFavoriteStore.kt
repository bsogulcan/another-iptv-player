package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.M3uChannelEntity
import dev.android.anotheriptvplayer.data.local.M3uFavoriteEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Kotlin port of iOS `M3UFavoriteStore`.
 *
 * Tracks favourite channel IDs per playlist as a reactive `Set<String>` so
 * card / row UIs can render the star icon without doing a per-row query.
 * Backed by [M3uFavoriteDao.observeFavoriteIds].
 */
class M3uFavoriteStore(private val database: AppDatabase) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var observationJob: Job? = null

    private val _favoriteIds = MutableStateFlow<Set<String>>(emptySet())
    val favoriteIds: StateFlow<Set<String>> = _favoriteIds.asStateFlow()

    /** Begin observing the favourites of the supplied playlist. Cancels any prior observation. */
    fun track(playlistId: String) {
        observationJob?.cancel()
        observationJob = scope.launch {
            database.m3uFavoriteDao().observeFavoriteIds(playlistId).collectLatest { ids ->
                _favoriteIds.value = ids.toSet()
            }
        }
    }

    fun stop() {
        observationJob?.cancel()
        observationJob = null
        _favoriteIds.value = emptySet()
    }

    fun isFavorite(channelId: String): Boolean = channelId in _favoriteIds.value

    suspend fun toggle(channel: M3uChannelEntity) {
        if (channel.id in _favoriteIds.value) {
            database.m3uFavoriteDao().delete(channel.id, channel.playlistId)
        } else {
            database.m3uFavoriteDao().insert(
                M3uFavoriteEntity(
                    channelId = channel.id,
                    playlistId = channel.playlistId,
                ),
            )
        }
    }
}
