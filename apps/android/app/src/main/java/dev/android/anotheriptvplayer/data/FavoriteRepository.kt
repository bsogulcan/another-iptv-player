package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.data.local.FavoriteDao
import dev.android.anotheriptvplayer.data.local.FavoriteEntity
import dev.android.anotheriptvplayer.data.local.LiveStreamWithCategory
import dev.android.anotheriptvplayer.data.local.SeriesWithCategory
import dev.android.anotheriptvplayer.data.local.VodStreamWithCategory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

/**
 * Thin wrapper over [FavoriteDao]. Kotlin equivalent of iOS
 * `toggleFavorite` snippets inside `MovieDetailView` / `SeriesDetailView`.
 *
 * [Type] is the iOS-compatible string discriminator (`"live"`, `"vod"`,
 * `"series"`) used across the favorites JOIN queries.
 */
class FavoriteRepository(private val dao: FavoriteDao) {

    object Type {
        const val LIVE = "live"
        const val VOD = "vod"
        const val SERIES = "series"
    }

    fun observeIsFavorite(streamId: Int, playlistId: String, type: String): Flow<Boolean> =
        dao.observeIsFavorite(streamId, playlistId, type)

    fun observeLive(playlistId: String): Flow<List<LiveStreamWithCategory>> =
        dao.observeFavoriteLive(playlistId)

    fun observeVod(playlistId: String): Flow<List<VodStreamWithCategory>> =
        dao.observeFavoriteVod(playlistId)

    fun observeSeries(playlistId: String): Flow<List<SeriesWithCategory>> =
        dao.observeFavoriteSeries(playlistId)

    suspend fun setFavorite(
        streamId: Int,
        playlistId: String,
        type: String,
        favorite: Boolean,
    ) {
        if (favorite) {
            dao.insert(FavoriteEntity(streamId = streamId, playlistId = playlistId, type = type))
        } else {
            dao.delete(streamId, playlistId, type)
        }
    }

    /** Reads the current state once and flips it. iOS `toggleFavorite` parity. */
    suspend fun toggle(streamId: Int, playlistId: String, type: String) {
        val isFav = dao.observeIsFavorite(streamId, playlistId, type).first()
        setFavorite(streamId, playlistId, type, !isFav)
    }
}
