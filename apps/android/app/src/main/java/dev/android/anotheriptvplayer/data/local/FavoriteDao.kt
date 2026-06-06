package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `favorite` table. iOS counterparts:
 *  - `FavoriteLiveRequest` / `FavoriteVODRequest` / `FavoriteSeriesRequest`
 *  - `IsFavoriteRequest` (used by the detail screens for the star toggle)
 *  - manual `insert` / `deleteAll` in `MovieDetailView.toggleFavorite`
 *
 * Composite key: `(streamId, playlistId, type)`. Created-at timestamp is
 * the order key for the favorites list.
 */
@Dao
interface FavoriteDao {

    @Query(
        "SELECT EXISTS(SELECT 1 FROM favorite WHERE streamId = :streamId AND playlistId = :playlistId AND type = :type)"
    )
    fun observeIsFavorite(streamId: Int, playlistId: String, type: String): Flow<Boolean>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(row: FavoriteEntity)

    @Query("DELETE FROM favorite WHERE streamId = :streamId AND playlistId = :playlistId AND type = :type")
    suspend fun delete(streamId: Int, playlistId: String, type: String)

    @Query(
        """
        SELECT liveStream.*, category.name AS categoryName
        FROM favorite
        JOIN liveStream ON favorite.streamId = liveStream.streamId
                       AND favorite.playlistId = liveStream.playlistId
        JOIN category ON liveStream.categoryId = category.id
                     AND liveStream.playlistId = category.playlistId
                     AND category.type = 'live'
        WHERE favorite.playlistId = :playlistId AND favorite.type = 'live'
        ORDER BY favorite.createdAt DESC
        """
    )
    fun observeFavoriteLive(playlistId: String): Flow<List<LiveStreamWithCategory>>

    @Query(
        """
        SELECT vodStream.*, category.name AS categoryName
        FROM favorite
        JOIN vodStream ON favorite.streamId = vodStream.streamId
                       AND favorite.playlistId = vodStream.playlistId
        JOIN category ON vodStream.categoryId = category.id
                     AND vodStream.playlistId = category.playlistId
                     AND category.type = 'vod'
        WHERE favorite.playlistId = :playlistId AND favorite.type = 'vod'
        ORDER BY favorite.createdAt DESC
        """
    )
    fun observeFavoriteVod(playlistId: String): Flow<List<VodStreamWithCategory>>

    @Query(
        """
        SELECT series.*, category.name AS categoryName
        FROM favorite
        JOIN series ON favorite.streamId = series.seriesId
                   AND favorite.playlistId = series.playlistId
        JOIN category ON series.categoryId = category.id
                     AND series.playlistId = category.playlistId
                     AND category.type = 'series'
        WHERE favorite.playlistId = :playlistId AND favorite.type = 'series'
        ORDER BY favorite.createdAt DESC
        """
    )
    fun observeFavoriteSeries(playlistId: String): Flow<List<SeriesWithCategory>>
}
