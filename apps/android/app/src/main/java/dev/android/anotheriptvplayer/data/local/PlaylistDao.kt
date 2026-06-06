package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import dev.android.anotheriptvplayer.model.Playlist
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `playlist` table — the Android equivalent of the iOS
 * Playlist GRDB record. UI consumes [observeAll] as a Flow; writes are
 * suspend functions.
 */
@Dao
interface PlaylistDao {

    @Query("SELECT * FROM playlist ORDER BY createdAt ASC")
    fun observeAll(): Flow<List<Playlist>>

    @Query("SELECT * FROM playlist WHERE id = :id LIMIT 1")
    suspend fun findById(id: String): Playlist?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(playlist: Playlist)

    @Update
    suspend fun update(playlist: Playlist)

    @Delete
    suspend fun delete(playlist: Playlist)

    @Query("DELETE FROM playlist WHERE id = :id")
    suspend fun deleteById(id: String)
}
