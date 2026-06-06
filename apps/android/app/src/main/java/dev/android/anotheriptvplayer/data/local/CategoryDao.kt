package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `category` table (live / vod / series buckets).
 *
 * iOS counterpart: GRDB `DBCategory` queries inside
 * `PlaylistContentStore.fetchCategoriesOnly` and
 * `syncFromNetworkReplacingLocal`. The ordering on `sortIndex` reproduces
 * the Xtream API's natural order, which iOS persists by writing rows in
 * iteration order.
 */
@Dao
interface CategoryDao {

    @Query(
        "SELECT * FROM category WHERE playlistId = :playlistId AND type = :type " +
            "ORDER BY sortIndex"
    )
    fun observeByPlaylistAndType(playlistId: String, type: String): Flow<List<CategoryEntity>>

    @Query(
        "SELECT * FROM category WHERE playlistId = :playlistId AND type = :type " +
            "ORDER BY sortIndex"
    )
    suspend fun getByPlaylistAndType(playlistId: String, type: String): List<CategoryEntity>

    @Query("SELECT COUNT(*) FROM category WHERE playlistId = :playlistId")
    suspend fun countForPlaylist(playlistId: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<CategoryEntity>)

    @Query("DELETE FROM category WHERE playlistId = :playlistId")
    suspend fun deleteByPlaylist(playlistId: String)
}
