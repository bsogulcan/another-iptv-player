package dev.android.anotheriptvplayer.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Data access for the `episode` table — populated alongside seasons when
 * `getSeriesInfo` runs. iOS counterpart: `EpisodesRequest` GRDB query.
 */
@Dao
interface EpisodeDao {

    @Query(
        """
        SELECT * FROM episode
        WHERE seasonId = :seasonId
        ORDER BY episodeNum
        """
    )
    fun observeBySeason(seasonId: String): Flow<List<EpisodeEntity>>

    /** First episode of a season ordered by `episodeNum`. iOS `playFirstEpisode`. */
    @Query(
        """
        SELECT * FROM episode
        WHERE seasonId = :seasonId
        ORDER BY episodeNum
        LIMIT 1
        """
    )
    suspend fun firstInSeason(seasonId: String): EpisodeEntity?

    @Query("SELECT * FROM episode WHERE id = :id LIMIT 1")
    suspend fun findById(id: String): EpisodeEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<EpisodeEntity>)

    @Query(
        """
        DELETE FROM episode
        WHERE seasonId IN (
            SELECT id FROM season
            WHERE seriesId = :seriesId AND playlistId = :playlistId
        )
        """
    )
    suspend fun deleteBySeries(seriesId: Int, playlistId: String)
}
