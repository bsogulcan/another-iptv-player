package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `downloadedItem` table — the offline-arc store the
 * Downloads screen consumes and `DownloadManager` writes into.
 *
 * iOS counterpart: GRDB `DBDownloadedItem` reads/writes in
 * `Models/DownloadManager.swift`.
 */
@Dao
interface DownloadedItemDao {

    @Query("SELECT * FROM downloadedItem WHERE id = :id LIMIT 1")
    suspend fun findById(id: String): DownloadedItemEntity?

    @Query("SELECT * FROM downloadedItem WHERE id = :id LIMIT 1")
    fun observeById(id: String): Flow<DownloadedItemEntity?>

    @Query(
        """
        SELECT * FROM downloadedItem
        WHERE playlistId = :playlistId
        ORDER BY createdAt DESC
        """
    )
    fun observeByPlaylist(playlistId: String): Flow<List<DownloadedItemEntity>>

    @Query("SELECT * FROM downloadedItem WHERE status = 'queued' ORDER BY createdAt")
    suspend fun queuedItems(): List<DownloadedItemEntity>

    /** Currently-downloading rows for the queue pump (iOS `pumpQueue`). */
    @Query("SELECT * FROM downloadedItem WHERE status = 'downloading'")
    suspend fun inFlight(): List<DownloadedItemEntity>

    @Query(
        "SELECT COUNT(*) FROM downloadedItem WHERE playlistId = :playlistId AND status = 'downloading'"
    )
    suspend fun activeCountForPlaylist(playlistId: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(row: DownloadedItemEntity)

    @Update
    suspend fun update(row: DownloadedItemEntity)

    @Query("UPDATE downloadedItem SET status = :status, errorMessage = :errorMessage WHERE id = :id")
    suspend fun setStatus(id: String, status: String, errorMessage: String? = null)

    @Query(
        """
        UPDATE downloadedItem
           SET downloadedBytes = :downloaded, totalBytes = :total
         WHERE id = :id
        """
    )
    suspend fun setProgress(id: String, downloaded: Long, total: Long)

    @Query(
        """
        UPDATE downloadedItem
           SET status = 'completed', completedAt = :completedAt, downloadedBytes = totalBytes
         WHERE id = :id
        """
    )
    suspend fun markComplete(id: String, completedAt: Long)

    @Query("DELETE FROM downloadedItem WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM downloadedItem WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)

    @Query("SELECT COALESCE(SUM(totalBytes), 0) FROM downloadedItem WHERE status = 'completed'")
    suspend fun completedBytes(): Long
}
