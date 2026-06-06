package dev.android.anotheriptvplayer.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

/**
 * Room entity stubs for the iOS `AppDatabase` tables that the Android UI does
 * not consume yet.
 *
 * They live here so the schema is created up-front (matching the iOS schema
 * at v1), even though the corresponding DAOs/features land later. As features
 * are ported from iOS, the matching DAO sits next to the entity it queries.
 */

@Entity(
    tableName = "category",
    primaryKeys = ["id", "playlistId", "type"],
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["playlistId", "type", "sortIndex"], name = "idx_category_playlist_type_sort")],
)
data class CategoryEntity(
    val id: String,
    val name: String,
    val parentId: Int? = null,
    /** `live`, `vod`, or `series`. */
    val type: String,
    val sortIndex: Int = 0,
    val playlistId: String,
)

@Entity(
    tableName = "liveStream",
    primaryKeys = ["streamId", "playlistId"],
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["playlistId", "sortIndex"], name = "idx_liveStream_playlist_sort")],
)
data class LiveStreamEntity(
    val streamId: Int,
    val name: String,
    val streamIcon: String? = null,
    val epgChannelId: String? = null,
    val categoryId: String? = null,
    val sortIndex: Int = 0,
    val playlistId: String,
)

@Entity(
    tableName = "vodStream",
    primaryKeys = ["streamId", "playlistId"],
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(value = ["playlistId", "sortIndex"], name = "idx_vodStream_playlist_sort"),
        Index(value = ["playlistId", "added"], name = "idx_vodStream_playlist_added"),
    ],
)
data class VodStreamEntity(
    val streamId: Int,
    val name: String,
    val streamIcon: String? = null,
    val categoryId: String? = null,
    val rating: String? = null,
    val containerExtension: String? = null,
    val sortIndex: Int = 0,
    val playlistId: String,
    // metadata block (iOS `addVODMetadata` + `addVODAddedTimestamp` migrations)
    val director: String? = null,
    val cast: String? = null,
    val plot: String? = null,
    val genre: String? = null,
    val releaseDate: String? = null,
    val rating5Based: Double? = null,
    val backdropPath: String? = null,
    val youtubeTrailer: String? = null,
    val duration: String? = null,
    val tmdbId: String? = null,
    val kinopoiskUrl: String? = null,
    val metadataLoaded: Boolean = false,
    val added: String? = null,
)

@Entity(
    tableName = "series",
    primaryKeys = ["seriesId", "playlistId"],
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(value = ["playlistId", "sortIndex"], name = "idx_series_playlist_sort"),
        Index(value = ["playlistId", "lastModified"], name = "idx_series_playlist_lastModified"),
    ],
)
data class SeriesEntity(
    val seriesId: Int,
    val name: String,
    val cover: String? = null,
    val plot: String? = null,
    val genre: String? = null,
    val rating: String? = null,
    val categoryId: String? = null,
    val sortIndex: Int = 0,
    val seasonsLoaded: Boolean = false,
    val playlistId: String,
    // metadata block (iOS `addComprehensiveSeriesMetadata`)
    val cast: String? = null,
    val director: String? = null,
    val releaseDate: String? = null,
    val lastModified: String? = null,
    val rating5Based: Double? = null,
    val backdropPath: String? = null,
    val youtubeTrailer: String? = null,
    val episodeRunTime: String? = null,
)

@Entity(
    tableName = "season",
    indices = [Index(value = ["seriesId", "playlistId"])],
    foreignKeys = [
        ForeignKey(
            entity = SeriesEntity::class,
            parentColumns = ["seriesId", "playlistId"],
            childColumns = ["seriesId", "playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class SeasonEntity(
    @androidx.room.PrimaryKey
    val id: String,
    val seasonNumber: Int,
    val name: String? = null,
    val overview: String? = null,
    val cover: String? = null,
    val seriesId: Int,
    val playlistId: String,
    val airDate: String? = null,
    val episodeCount: Int? = null,
    val voteAverage: Double? = null,
)

@Entity(
    tableName = "episode",
    indices = [Index("seasonId")],
    foreignKeys = [
        ForeignKey(
            entity = SeasonEntity::class,
            parentColumns = ["id"],
            childColumns = ["seasonId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class EpisodeEntity(
    @androidx.room.PrimaryKey
    val id: String,
    val episodeId: String? = null,
    val episodeNum: Int? = null,
    val title: String? = null,
    val containerExtension: String? = null,
    val info: String? = null,
    val cover: String? = null,
    val duration: String? = null,
    val rating: String? = null,
    val seasonId: String,
)

@Entity(
    tableName = "favorite",
    primaryKeys = ["streamId", "playlistId", "type"],
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("playlistId")],
)
data class FavoriteEntity(
    val streamId: Int,
    val playlistId: String,
    /** `live`, `vod`, or `series`. */
    val type: String,
    val createdAt: Long = System.currentTimeMillis(),
)

@Entity(
    tableName = "watchHistory",
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index("playlistId"),
        Index(value = ["lastWatchedAt"], name = "index_watchHistory_lastWatchedAt"),
    ],
)
data class WatchHistoryEntity(
    @androidx.room.PrimaryKey
    val id: String,
    val playlistId: String,
    val streamId: String,
    /** `live`, `vod`, or `series`. */
    val type: String,
    val lastTimeMs: Long = 0,
    val durationMs: Long = 0,
    val lastWatchedAt: Long = System.currentTimeMillis(),
    val title: String,
    val secondaryTitle: String? = null,
    val imageUrl: String? = null,
    val seriesId: String? = null,
    val containerExtension: String? = null,
)

@Entity(
    tableName = "m3uChannel",
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["playlistId", "groupTitle", "sortIndex"], name = "idx_m3uChannel_playlist_group")],
)
data class M3uChannelEntity(
    @androidx.room.PrimaryKey
    val id: String,
    val playlistId: String,
    val name: String,
    val url: String,
    val tvgId: String? = null,
    val tvgName: String? = null,
    val tvgLogo: String? = null,
    val tvgCountry: String? = null,
    val groupTitle: String? = null,
    val userAgent: String? = null,
    val sortIndex: Int = 0,
)

@Entity(
    tableName = "m3uFavorite",
    primaryKeys = ["channelId", "playlistId"],
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["playlistId", "createdAt"], name = "idx_m3uFavorite_playlist")],
)
data class M3uFavoriteEntity(
    val channelId: String,
    val playlistId: String,
    val createdAt: Long = System.currentTimeMillis(),
)

@Entity(
    tableName = "downloadedItem",
    foreignKeys = [
        ForeignKey(
            entity = dev.android.anotheriptvplayer.model.Playlist::class,
            parentColumns = ["id"],
            childColumns = ["playlistId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["playlistId", "createdAt"], name = "idx_downloadedItem_playlist")],
)
data class DownloadedItemEntity(
    @androidx.room.PrimaryKey
    val id: String,
    val playlistId: String,
    val streamId: String,
    /** `vod` or `episode`. */
    val type: String,
    val title: String,
    val secondaryTitle: String? = null,
    val imageUrl: String? = null,
    val remoteUrl: String,
    val localPath: String,
    val containerExtension: String? = null,
    val totalBytes: Long = 0,
    val downloadedBytes: Long = 0,
    /** `downloading`, `completed`, or `failed`. */
    val status: String,
    val errorMessage: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val completedAt: Long? = null,
    val seriesId: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
)
