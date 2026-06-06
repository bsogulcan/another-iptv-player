package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `series` table — mirrors iOS
 * `PlaylistContentStore.fetchSeriesData` plus the per-series reads/writes
 * that `SeriesDetailView` uses.
 *
 * Season and episode rows are populated on demand via [SeasonDao] /
 * [EpisodeDao] — they don't take part in the bulk-sync transaction
 * because they require an extra round-trip per series.
 */
@Dao
interface SeriesDao {

    @Query(
        """
        SELECT series.*, category.name AS categoryName
        FROM series
        JOIN category ON series.categoryId = category.id
                     AND series.playlistId = category.playlistId
                     AND category.type = 'series'
        WHERE series.playlistId = :playlistId
        ORDER BY series.sortIndex
        """
    )
    suspend fun getWithCategory(playlistId: String): List<SeriesWithCategory>

    /** Reactive read for the detail screen — re-emits when metadata fills in. */
    @Query("SELECT * FROM series WHERE seriesId = :seriesId AND playlistId = :playlistId LIMIT 1")
    fun observeById(seriesId: Int, playlistId: String): Flow<SeriesEntity?>

    @Query("SELECT * FROM series WHERE seriesId = :seriesId AND playlistId = :playlistId LIMIT 1")
    suspend fun findById(seriesId: Int, playlistId: String): SeriesEntity?

    @Update
    suspend fun update(row: SeriesEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<SeriesEntity>)

    @Query("SELECT COUNT(*) FROM series WHERE playlistId = :playlistId")
    suspend fun countForPlaylist(playlistId: String): Int

    @Query("DELETE FROM series WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)
}
