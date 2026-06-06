package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * Data access for the `liveStream` table.
 *
 * The join query mirrors iOS `PlaylistContentStore.fetchLiveStreamsData`:
 * an INNER JOIN with `category` on `(categoryId, playlistId, type='live')`,
 * then ordered by `sortIndex` to preserve API-original order.
 */
@Dao
interface LiveStreamDao {

    @Query(
        """
        SELECT liveStream.*, category.name AS categoryName
        FROM liveStream
        JOIN category ON liveStream.categoryId = category.id
                     AND liveStream.playlistId = category.playlistId
                     AND category.type = 'live'
        WHERE liveStream.playlistId = :playlistId
        ORDER BY liveStream.sortIndex
        """
    )
    suspend fun getWithCategory(playlistId: String): List<LiveStreamWithCategory>

    @Query(
        """
        SELECT * FROM liveStream
        WHERE streamId = :streamId AND playlistId = :playlistId
        LIMIT 1
        """
    )
    suspend fun findById(streamId: Int, playlistId: String): LiveStreamEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<LiveStreamEntity>)

    @Query("SELECT COUNT(*) FROM liveStream WHERE playlistId = :playlistId")
    suspend fun countForPlaylist(playlistId: String): Int

    @Query("DELETE FROM liveStream WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)
}
