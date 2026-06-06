package dev.android.anotheriptvplayer.data

import androidx.room.withTransaction
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.EpisodeEntity
import dev.android.anotheriptvplayer.data.local.SeasonEntity
import dev.android.anotheriptvplayer.data.local.SeriesEntity
import dev.android.anotheriptvplayer.networking.XtreamSeason
import dev.android.anotheriptvplayer.networking.XtreamSeriesInfoResponse
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Per-series operations over `series`, `season`, and `episode` — the
 * Android counterpart of iOS `SeriesDetailView.fetchSeriesInfo` plus the
 * GRDB queries the detail screen subscribes to.
 *
 * The `applyInfo` flow rewrites the series + its seasons + episodes in one
 * Room transaction, including the iOS "virtual seasons" fallback for
 * providers that return episodes keyed by season number with no
 * `seasons[]` array.
 */
class SeriesRepository(private val database: AppDatabase) {

    private val seriesDao = database.seriesDao()
    private val seasonDao = database.seasonDao()
    private val episodeDao = database.episodeDao()

    fun observeSeries(seriesId: Int, playlistId: String): Flow<SeriesEntity?> =
        seriesDao.observeById(seriesId, playlistId)

    fun observeSeasons(seriesId: Int, playlistId: String): Flow<List<SeasonEntity>> =
        seasonDao.observeBySeries(seriesId, playlistId)

    fun observeEpisodes(seasonId: String): Flow<List<EpisodeEntity>> =
        episodeDao.observeBySeason(seasonId)

    suspend fun firstEpisodeInSeason(seasonId: String): EpisodeEntity? =
        episodeDao.firstInSeason(seasonId)

    suspend fun findEpisode(id: String): EpisodeEntity? = episodeDao.findById(id)

    /**
     * Merges a `get_series_info` response onto the persisted catalogue.
     * Equivalent to iOS `fetchSeriesInfo` — runs everything in one
     * transaction so a partial write can't leave a half-loaded series in
     * "loaded" state.
     */
    suspend fun applyInfo(
        seriesId: Int,
        playlistId: String,
        info: XtreamSeriesInfoResponse,
    ): SeriesEntity? {
        val current = seriesDao.findById(seriesId, playlistId) ?: return null

        // iOS pattern: when the server returns no seasons but does return
        // an episodes map keyed by season number, synthesise virtual
        // seasons so the UI has something to render.
        val apiSeasons = info.seasons.orEmpty()
        val episodesByKey = info.episodes.orEmpty()

        val processedSeasons: List<XtreamSeason> = if (apiSeasons.isEmpty() && episodesByKey.isNotEmpty()) {
            episodesByKey.keys
                .mapNotNull { it.toIntOrNull() }
                .sorted()
                .map { num ->
                    XtreamSeason(
                        name = "Sezon $num",
                        seasonNumber = num,
                    )
                }
        } else {
            apiSeasons
        }

        val seasonRows = mutableListOf<SeasonEntity>()
        val episodeRows = mutableListOf<EpisodeEntity>()

        for (apiSeason in processedSeasons) {
            val seasonNum = apiSeason.seasonNumber ?: 0
            // Stable id pattern from iOS: "<seriesId>_<seasonNumber>".
            val seasonId = "${seriesId}_$seasonNum"
            seasonRows += SeasonEntity(
                id = seasonId,
                seasonNumber = seasonNum,
                name = apiSeason.name ?: "Sezon $seasonNum",
                overview = apiSeason.overview,
                cover = apiSeason.cover,
                seriesId = seriesId,
                playlistId = playlistId,
                airDate = apiSeason.airDate,
                episodeCount = apiSeason.episodeCount,
                voteAverage = apiSeason.voteAverage,
            )

            val eps = episodesByKey[seasonNum.toString()].orEmpty()
            for (ep in eps) {
                val epInfo = ep.info
                val cover = epInfo?.movieImage ?: epInfo?.cover
                episodeRows += EpisodeEntity(
                    // iOS uses ep.id if present, otherwise a UUID. The
                    // catalogue's primary key is just the local id.
                    id = ep.id ?: UUID.randomUUID().toString(),
                    episodeId = ep.id,
                    episodeNum = ep.episodeNum,
                    title = ep.title,
                    containerExtension = ep.containerExtension,
                    info = epInfo?.plot,
                    cover = cover,
                    duration = epInfo?.duration,
                    rating = epInfo?.rating,
                    seasonId = seasonId,
                )
            }
        }

        val seriesDetails = info.info
        val updatedSeries = current.copy(
            seasonsLoaded = true,
            cast = seriesDetails?.cast ?: current.cast,
            director = seriesDetails?.director ?: current.director,
            genre = seriesDetails?.genre ?: current.genre,
            plot = seriesDetails?.plot ?: current.plot,
            releaseDate = seriesDetails?.releaseDate ?: current.releaseDate,
            rating = seriesDetails?.rating ?: current.rating,
            lastModified = seriesDetails?.lastModified ?: current.lastModified,
            rating5Based = seriesDetails?.rating5Based ?: current.rating5Based,
            backdropPath = seriesDetails?.backdropPath?.firstOrNull() ?: current.backdropPath,
            youtubeTrailer = seriesDetails?.youtubeTrailer ?: current.youtubeTrailer,
            episodeRunTime = seriesDetails?.episodeRunTime ?: current.episodeRunTime,
        )

        database.withTransaction {
            // Delete-then-insert keeps the rows in sync if seasons / episodes
            // disappeared on the provider side. Cascade FK takes care of
            // dropping orphaned episodes when their season is removed, but
            // the explicit delete protects against the case where seasons
            // *were* persisted from a previous (now-buggy) fetch.
            episodeDao.deleteBySeries(seriesId, playlistId)
            seasonDao.deleteBySeries(seriesId, playlistId)

            seasonDao.upsertAll(seasonRows)
            episodeDao.upsertAll(episodeRows)
            seriesDao.update(updatedSeries)
        }
        return updatedSeries
    }
}
