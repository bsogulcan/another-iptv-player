package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `m3uFavorite` table — M3U channels can't reuse the
 * `favorite` table because that one keys on an integer Xtream `streamId`.
 *
 * iOS counterpart: GRDB `M3UFavoriteStore`'s `ValueObservation` over
 * `SELECT channelId FROM m3uFavorite WHERE playlistId = ?`.
 */
@Dao
interface M3uFavoriteDao {

    @Query(
        "SELECT channelId FROM m3uFavorite WHERE playlistId = :playlistId"
    )
    fun observeFavoriteIds(playlistId: String): Flow<List<String>>

    @Query(
        """
        SELECT m3uChannel.* FROM m3uFavorite
        JOIN m3uChannel ON m3uChannel.id = m3uFavorite.channelId
                       AND m3uChannel.playlistId = m3uFavorite.playlistId
        WHERE m3uFavorite.playlistId = :playlistId
        ORDER BY m3uFavorite.createdAt DESC
        """
    )
    fun observeFavorites(playlistId: String): Flow<List<M3uChannelEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(row: M3uFavoriteEntity)

    @Query("DELETE FROM m3uFavorite WHERE channelId = :channelId AND playlistId = :playlistId")
    suspend fun delete(channelId: String, playlistId: String)

    @Query(
        "SELECT EXISTS(SELECT 1 FROM m3uFavorite WHERE channelId = :channelId AND playlistId = :playlistId)"
    )
    suspend fun isFavorite(channelId: String, playlistId: String): Boolean
}
