package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

/** Data access for the local sync outbox — see [SyncOutboxEntity]. */
@Dao
interface SyncOutboxDao {

    @Insert
    suspend fun insert(row: SyncOutboxEntity): Long

    @Query("SELECT * FROM syncOutbox ORDER BY id ASC LIMIT :limit")
    suspend fun batch(limit: Int): List<SyncOutboxEntity>

    @Query("DELETE FROM syncOutbox WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<Long>)

    @Query("SELECT COUNT(*) FROM syncOutbox")
    suspend fun count(): Int
}
