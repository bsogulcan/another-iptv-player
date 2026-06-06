package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `watchHistory` table.
 *
 * iOS counterparts: `WatchHistoryRequest`, `RecentWatchHistoryRequest`,
 * `WatchProgressMapRequest`, `LatestSeriesWatchHistoryRequest` plus the
 * upserts driven from `VideoPlayerController.persistWatchHistoryIfNeeded`.
 *
 * Row id format mirrors iOS exactly: `"{playlistId}_{type}_{streamId}"` so
 * the table doubles as a per-stream progress map.
 */
@Dao
interface WatchHistoryDao {

    @Query("SELECT * FROM watchHistory WHERE id = :id LIMIT 1")
    suspend fun findById(id: String): WatchHistoryEntity?

    @Query("SELECT * FROM watchHistory WHERE id = :id LIMIT 1")
    fun observeById(id: String): Flow<WatchHistoryEntity?>

    /**
     * iOS `RecentWatchHistoryRequest`: VOD + the most recent episode of each
     * series, ordered by recency. We don't dedupe series here — callers do it
     * in Kotlin so the SQL stays portable across the iOS port.
     */
    @Query(
        """
        SELECT * FROM watchHistory
        WHERE playlistId = :playlistId
        ORDER BY lastWatchedAt DESC
        LIMIT :limit
        """
    )
    fun observeRecent(playlistId: String, limit: Int = 20): Flow<List<WatchHistoryEntity>>

    @Query(
        """
        SELECT * FROM watchHistory
        WHERE playlistId = :playlistId AND type = :type
        ORDER BY lastWatchedAt DESC
        LIMIT :limit
        """
    )
    fun observeRecentByType(
        playlistId: String,
        type: String,
        limit: Int = 20,
    ): Flow<List<WatchHistoryEntity>>

    /** iOS `WatchProgressMapRequest`: streamId → fractional progress. */
    @Query(
        """
        SELECT streamId AS streamId,
               CASE WHEN durationMs > 0 THEN (lastTimeMs * 1.0 / durationMs) ELSE 0 END AS progress
        FROM watchHistory
        WHERE playlistId = :playlistId AND type = :type
        """
    )
    suspend fun progressMap(playlistId: String, type: String): List<ProgressRow>

    /** Latest episode watched for a given series (used by the autoplay-next shell). */
    @Query(
        """
        SELECT * FROM watchHistory
        WHERE playlistId = :playlistId AND seriesId = :seriesId
        ORDER BY lastWatchedAt DESC
        LIMIT 1
        """
    )
    suspend fun latestForSeries(playlistId: String, seriesId: String): WatchHistoryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(row: WatchHistoryEntity)

    @Query("DELETE FROM watchHistory WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM watchHistory WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)
}

/** Lightweight projection — DAO returns a list of these instead of allocating a Map directly. */
data class ProgressRow(val streamId: String, val progress: Double)
