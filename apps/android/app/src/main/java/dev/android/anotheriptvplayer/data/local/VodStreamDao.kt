package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `vodStream` (movies) table — mirrors iOS
 * `PlaylistContentStore.fetchVODStreamsData` plus the per-movie reads /
 * writes that `MovieDetailView` uses.
 */
@Dao
interface VodStreamDao {

    @Query(
        """
        SELECT vodStream.*, category.name AS categoryName
        FROM vodStream
        JOIN category ON vodStream.categoryId = category.id
                     AND vodStream.playlistId = category.playlistId
                     AND category.type = 'vod'
        WHERE vodStream.playlistId = :playlistId
        ORDER BY vodStream.sortIndex
        """
    )
    suspend fun getWithCategory(playlistId: String): List<VodStreamWithCategory>

    /** Reactive read for the detail screen — emits again when metadata is filled in. */
    @Query("SELECT * FROM vodStream WHERE streamId = :streamId AND playlistId = :playlistId LIMIT 1")
    fun observeById(streamId: Int, playlistId: String): Flow<VodStreamEntity?>

    @Query("SELECT * FROM vodStream WHERE streamId = :streamId AND playlistId = :playlistId LIMIT 1")
    suspend fun findById(streamId: Int, playlistId: String): VodStreamEntity?

    /**
     * Recently added VODs — iOS sorts by `CAST(added AS INTEGER) DESC` to
     * handle the unix-seconds-as-string column. Limited because the dashboard
     * shelf only renders the top N anyway.
     */
    @Query(
        """
        SELECT vodStream.*, category.name AS categoryName
        FROM vodStream
        LEFT JOIN category ON vodStream.categoryId = category.id
                          AND vodStream.playlistId = category.playlistId
                          AND category.type = 'vod'
        WHERE vodStream.playlistId = :playlistId AND vodStream.added IS NOT NULL AND vodStream.added != ''
        ORDER BY CAST(vodStream.added AS INTEGER) DESC
        LIMIT :limit
        """
    )
    suspend fun recentlyAdded(playlistId: String, limit: Int = 30): List<VodStreamWithCategory>

    /** Single-row update — Room generates UPDATE by composite PK. */
    @Update
    suspend fun update(row: VodStreamEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<VodStreamEntity>)

    @Query("SELECT COUNT(*) FROM vodStream WHERE playlistId = :playlistId")
    suspend fun countForPlaylist(playlistId: String): Int

    @Query("DELETE FROM vodStream WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)
}
