package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.data.local.VodStreamDao
import dev.android.anotheriptvplayer.data.local.VodStreamEntity
import dev.android.anotheriptvplayer.networking.XtreamVODInfo
import kotlinx.coroutines.flow.Flow

/**
 * Per-movie operations over the `vodStream` table.
 *
 * `PlaylistContentStore` already handles the catalog-wide sync. This
 * repository is the iOS `MovieDetailView` counterpart: a single row's
 * read/write + the `applyInfo` helper that merges an
 * [XtreamVODInfo] response onto the persisted record.
 */
class VodRepository(private val dao: VodStreamDao) {

    fun observe(streamId: Int, playlistId: String): Flow<VodStreamEntity?> =
        dao.observeById(streamId, playlistId)

    suspend fun find(streamId: Int, playlistId: String): VodStreamEntity? =
        dao.findById(streamId, playlistId)

    /**
     * Merges a `get_vod_info` response onto the persisted row. Mirrors iOS
     * `MovieDetailView.fetchMovieInfo`: every nullable field on the
     * response replaces the corresponding column iff it's non-null, the
     * `metadataLoaded` flag flips, and `rating5Based` is derived from the
     * text rating if numeric.
     *
     * Returns the updated entity, or null if the row no longer exists.
     */
    suspend fun applyInfo(streamId: Int, playlistId: String, info: XtreamVODInfo): VodStreamEntity? {
        val current = dao.findById(streamId, playlistId) ?: return null

        val rating5Based = info.rating?.trim()?.toDoubleOrNull()?.let { it / 2.0 }
            ?: current.rating5Based

        val updated = current.copy(
            director = info.director ?: current.director,
            cast = info.cast ?: current.cast,
            plot = info.plot ?: current.plot,
            genre = info.genre ?: current.genre,
            releaseDate = info.releaseDate ?: current.releaseDate,
            rating = info.rating ?: current.rating,
            rating5Based = rating5Based,
            // iOS persists only the first backdrop URL; we do the same so the
            // schema column is a plain string rather than a JSON array.
            backdropPath = info.backdropPath?.firstOrNull() ?: current.backdropPath,
            youtubeTrailer = info.youtubeTrailer ?: current.youtubeTrailer,
            duration = info.duration ?: current.duration,
            tmdbId = info.tmdbId ?: current.tmdbId,
            kinopoiskUrl = info.kinopoiskUrl ?: current.kinopoiskUrl,
            metadataLoaded = true,
        )
        dao.update(updated)
        return updated
    }
}
