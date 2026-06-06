package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `season` table — populated on demand by
 * `getSeriesInfo`. iOS counterpart: `SeasonsRequest` GRDB query.
 */
@Dao
interface SeasonDao {

    @Query(
        """
        SELECT * FROM season
        WHERE seriesId = :seriesId AND playlistId = :playlistId
        ORDER BY seasonNumber
        """
    )
    fun observeBySeries(seriesId: Int, playlistId: String): Flow<List<SeasonEntity>>

    @Query(
        """
        SELECT * FROM season
        WHERE seriesId = :seriesId AND playlistId = :playlistId
        ORDER BY seasonNumber
        """
    )
    suspend fun getBySeries(seriesId: Int, playlistId: String): List<SeasonEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<SeasonEntity>)

    @Query(
        """
        DELETE FROM season
        WHERE seriesId = :seriesId AND playlistId = :playlistId
        """
    )
    suspend fun deleteBySeries(seriesId: Int, playlistId: String)
}
