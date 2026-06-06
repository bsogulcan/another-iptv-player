package dev.android.anotheriptvplayer.networking

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Kotlin port of `XtreamModels.swift`.
 *
 * Decoding is intentionally lenient — every scalar field goes through
 * [FlexibleString] / [FlexibleInt] / [FlexibleDouble] so the same provider
 * returning `"stream_id": 42` or `"stream_id": "42"` both work. This matches
 * what iOS does with `decodeFlexibleStringIfPresent` and friends, and is what
 * makes the integration robust against real-world Xtream servers.
 *
 * Optional/missing fields are tolerated by `kotlinx.serialization` when the
 * Json instance is built with `ignoreUnknownKeys = true` and the property has
 * a default; see [XtreamJson].
 */

// MARK: - Auth

@Serializable
data class XtreamAuthResponse(
    @SerialName("user_info") val userInfo: XtreamUserInfo? = null,
    @SerialName("server_info") val serverInfo: XtreamServerInfo? = null,
)

@Serializable
data class XtreamUserInfo(
    @Serializable(with = FlexibleString::class) val username: String? = null,
    @Serializable(with = FlexibleString::class) val password: String? = null,
    @Serializable(with = FlexibleString::class) val message: String? = null,
    @Serializable(with = FlexibleInt::class) val auth: Int? = null,
    @Serializable(with = FlexibleString::class) val status: String? = null,
    @SerialName("exp_date") @Serializable(with = FlexibleString::class) val expDate: String? = null,
    @SerialName("is_trial") @Serializable(with = FlexibleString::class) val isTrial: String? = null,
    @SerialName("active_cons") @Serializable(with = FlexibleString::class) val activeCons: String? = null,
    @SerialName("created_at") @Serializable(with = FlexibleString::class) val createdAt: String? = null,
    @SerialName("max_connections") @Serializable(with = FlexibleString::class) val maxConnections: String? = null,
)

@Serializable
data class XtreamServerInfo(
    @Serializable(with = FlexibleString::class) val url: String? = null,
    @Serializable(with = FlexibleString::class) val port: String? = null,
    @SerialName("https_port") @Serializable(with = FlexibleString::class) val httpsPort: String? = null,
    @SerialName("server_protocol") @Serializable(with = FlexibleString::class) val serverProtocol: String? = null,
    @SerialName("rtmp_port") @Serializable(with = FlexibleString::class) val rtmpPort: String? = null,
    @Serializable(with = FlexibleString::class) val timezone: String? = null,
    @SerialName("time_now") @Serializable(with = FlexibleString::class) val timeNow: String? = null,
)

// MARK: - Category

@Serializable
data class XtreamCategory(
    @SerialName("category_id") @Serializable(with = FlexibleString::class) val categoryId: String? = null,
    @SerialName("category_name") @Serializable(with = FlexibleString::class) val categoryName: String? = null,
    @SerialName("parent_id") @Serializable(with = FlexibleInt::class) val parentId: Int? = null,
)

// MARK: - Streams

@Serializable
data class XtreamLiveStream(
    @SerialName("stream_id") @Serializable(with = FlexibleInt::class) val streamId: Int? = null,
    @SerialName("stream_icon") @Serializable(with = FlexibleString::class) val streamIcon: String? = null,
    @SerialName("epg_channel_id") @Serializable(with = FlexibleString::class) val epgChannelId: String? = null,
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @SerialName("category_id") @Serializable(with = FlexibleString::class) val categoryId: String? = null,
    @SerialName("is_adult") @Serializable(with = FlexibleInt::class) val isAdult: Int? = null,
)

@Serializable
data class XtreamVODStream(
    @SerialName("stream_id") @Serializable(with = FlexibleInt::class) val streamId: Int? = null,
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @SerialName("stream_icon") @Serializable(with = FlexibleString::class) val streamIcon: String? = null,
    @SerialName("category_id") @Serializable(with = FlexibleString::class) val categoryId: String? = null,
    @Serializable(with = FlexibleString::class) val rating: String? = null,
    @SerialName("container_extension") @Serializable(with = FlexibleString::class) val containerExtension: String? = null,
    @SerialName("is_adult") @Serializable(with = FlexibleInt::class) val isAdult: Int? = null,
    @Serializable(with = FlexibleString::class) val added: String? = null,
)

@Serializable
data class XtreamSeries(
    @SerialName("series_id") @Serializable(with = FlexibleInt::class) val seriesId: Int? = null,
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @Serializable(with = FlexibleString::class) val cover: String? = null,
    @Serializable(with = FlexibleString::class) val plot: String? = null,
    @Serializable(with = FlexibleString::class) val cast: String? = null,
    @Serializable(with = FlexibleString::class) val director: String? = null,
    @Serializable(with = FlexibleString::class) val genre: String? = null,
    @Serializable(with = FlexibleString::class) val rating: String? = null,
    @SerialName("category_id") @Serializable(with = FlexibleString::class) val categoryId: String? = null,
    // iOS keeps the camelCased "releaseDate" JSON key as-is.
    @SerialName("releaseDate") @Serializable(with = FlexibleString::class) val releaseDate: String? = null,
    @SerialName("youtube_trailer") @Serializable(with = FlexibleString::class) val youtubeTrailer: String? = null,
    @SerialName("last_modified") @Serializable(with = FlexibleString::class) val lastModified: String? = null,
)

// MARK: - Series Info

@Serializable
data class XtreamSeriesInfoResponse(
    val seasons: List<XtreamSeason>? = null,
    val info: XtreamSeriesDetails? = null,
    val episodes: Map<String, List<XtreamEpisode>>? = null,
)

@Serializable
data class XtreamSeriesDetails(
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @Serializable(with = FlexibleString::class) val cover: String? = null,
    @Serializable(with = FlexibleString::class) val plot: String? = null,
    @Serializable(with = FlexibleString::class) val cast: String? = null,
    @Serializable(with = FlexibleString::class) val director: String? = null,
    @Serializable(with = FlexibleString::class) val genre: String? = null,
    @Serializable(with = FlexibleString::class) val rating: String? = null,
    @SerialName("releaseDate") @Serializable(with = FlexibleString::class) val releaseDate: String? = null,
    @SerialName("last_modified") @Serializable(with = FlexibleString::class) val lastModified: String? = null,
    @SerialName("rating_5based") @Serializable(with = FlexibleDouble::class) val rating5Based: Double? = null,
    @SerialName("backdrop_path") val backdropPath: List<String>? = null,
    @SerialName("youtube_trailer") @Serializable(with = FlexibleString::class) val youtubeTrailer: String? = null,
    @SerialName("episode_run_time") @Serializable(with = FlexibleString::class) val episodeRunTime: String? = null,
)

@Serializable
data class XtreamSeason(
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @SerialName("season_number") @Serializable(with = FlexibleInt::class) val seasonNumber: Int? = null,
    @Serializable(with = FlexibleString::class) val cover: String? = null,
    @Serializable(with = FlexibleString::class) val overview: String? = null,
    @SerialName("air_date") @Serializable(with = FlexibleString::class) val airDate: String? = null,
    @SerialName("episode_count") @Serializable(with = FlexibleInt::class) val episodeCount: Int? = null,
    @SerialName("vote_average") @Serializable(with = FlexibleDouble::class) val voteAverage: Double? = null,
)

@Serializable
data class XtreamEpisode(
    @Serializable(with = FlexibleString::class) val id: String? = null,
    @SerialName("episode_num") @Serializable(with = FlexibleInt::class) val episodeNum: Int? = null,
    @Serializable(with = FlexibleString::class) val title: String? = null,
    @SerialName("container_extension") @Serializable(with = FlexibleString::class) val containerExtension: String? = null,
    val info: XtreamEpisodeInfo? = null,
)

@Serializable
data class XtreamEpisodeInfo(
    @Serializable(with = FlexibleString::class) val plot: String? = null,
    @Serializable(with = FlexibleString::class) val duration: String? = null,
    @Serializable(with = FlexibleString::class) val rating: String? = null,
    @Serializable(with = FlexibleString::class) val cover: String? = null,
    @SerialName("movie_image") @Serializable(with = FlexibleString::class) val movieImage: String? = null,
)

// MARK: - VOD Info

@Serializable
data class XtreamVODInfoResponse(
    val info: XtreamVODInfo? = null,
    @SerialName("movie_data") val movieData: XtreamVODMovieData? = null,
)

@Serializable
data class XtreamVODInfo(
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @SerialName("movie_image") @Serializable(with = FlexibleString::class) val movieImage: String? = null,
    @SerialName("cover_big") @Serializable(with = FlexibleString::class) val coverBig: String? = null,
    @Serializable(with = FlexibleString::class) val plot: String? = null,
    @Serializable(with = FlexibleString::class) val cast: String? = null,
    @Serializable(with = FlexibleString::class) val director: String? = null,
    @Serializable(with = FlexibleString::class) val genre: String? = null,
    @SerialName("releasedate") @Serializable(with = FlexibleString::class) val releaseDate: String? = null,
    @Serializable(with = FlexibleString::class) val rating: String? = null,
    @SerialName("backdrop_path") val backdropPath: List<String>? = null,
    @SerialName("youtube_trailer") @Serializable(with = FlexibleString::class) val youtubeTrailer: String? = null,
    @Serializable(with = FlexibleString::class) val duration: String? = null,
    @SerialName("duration_secs") @Serializable(with = FlexibleInt::class) val durationSecs: Int? = null,
    @SerialName("tmdb_id") @Serializable(with = FlexibleString::class) val tmdbId: String? = null,
    @SerialName("kinopoisk_url") @Serializable(with = FlexibleString::class) val kinopoiskUrl: String? = null,
)

@Serializable
data class XtreamVODMovieData(
    @SerialName("stream_id") @Serializable(with = FlexibleInt::class) val streamId: Int? = null,
    @Serializable(with = FlexibleString::class) val name: String? = null,
    @Serializable(with = FlexibleString::class) val added: String? = null,
    @SerialName("category_id") @Serializable(with = FlexibleString::class) val categoryId: String? = null,
    @SerialName("container_extension") @Serializable(with = FlexibleString::class) val containerExtension: String? = null,
    @SerialName("custom_sid") @Serializable(with = FlexibleString::class) val customSid: String? = null,
    @SerialName("direct_source") @Serializable(with = FlexibleString::class) val directSource: String? = null,
)
