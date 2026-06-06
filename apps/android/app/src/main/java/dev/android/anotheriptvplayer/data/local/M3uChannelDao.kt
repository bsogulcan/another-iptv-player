package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * Data access for the `m3uChannel` table — populated by `M3uImporter` once a
 * playlist's text body has been parsed. iOS counterpart: GRDB writes inside
 * `M3UImporter.replace` and reads via `M3UContentStore.fetchChannels`.
 *
 * Rows are deterministically keyed by SHA-256 of `playlistId:url`, so a later
 * reimport preserves favourite / watch-history links provided the URL stays
 * the same.
 */
@Dao
interface M3uChannelDao {

    @Query(
        "SELECT * FROM m3uChannel WHERE playlistId = :playlistId ORDER BY sortIndex"
    )
    suspend fun getByPlaylist(playlistId: String): List<M3uChannelEntity>

    @Query("SELECT * FROM m3uChannel WHERE id = :id LIMIT 1")
    suspend fun findById(id: String): M3uChannelEntity?

    @Query("SELECT COUNT(*) FROM m3uChannel WHERE playlistId = :playlistId")
    suspend fun countForPlaylist(playlistId: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<M3uChannelEntity>)

    @Query("DELETE FROM m3uChannel WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)
}
