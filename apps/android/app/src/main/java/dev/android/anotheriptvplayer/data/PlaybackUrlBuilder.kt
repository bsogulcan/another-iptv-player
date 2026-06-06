package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.model.Playlist

/**
 * Kotlin port of iOS `PlaybackURLBuilder`.
 *
 * Builds direct-playback URLs for the Xtream stream endpoints. The base
 * URL goes through the same normalisation as the API client
 * ([dev.android.anotheriptvplayer.networking.XtreamApiClient]), with one
 * difference: `player_api.php` is stripped (instead of appended) because
 * the stream endpoints live under `/<u>/<p>/<id>` and friends.
 */
class PlaybackUrlBuilder(private val playlist: Playlist) {

    private val cleanBaseUrl: String
        get() {
            var base = playlist.serverUrl.trim()
            if (!base.startsWith("http://", ignoreCase = true) &&
                !base.startsWith("https://", ignoreCase = true)
            ) {
                base = "http://$base"
            }
            if (base.endsWith("/")) base = base.dropLast(1)
            val lower = base.lowercase()
            base = when {
                lower.endsWith("/player_api.php") -> base.dropLast("/player_api.php".length)
                lower.endsWith("player_api.php") -> base.dropLast("player_api.php".length)
                else -> base
            }
            return base.replace(" ", "")
        }

    private val authPath: String
        get() = "${playlist.username.trim()}/${playlist.password.trim()}"

    /** Live channel — extension is optional (some servers stream raw TS). */
    fun liveUrl(streamId: Int, extension: String? = null): String {
        val base = "$cleanBaseUrl/$authPath/$streamId"
        return if (extension.isNullOrEmpty()) base else "$base.$extension"
    }

    /** VOD / movie playback. iOS defaults to `mp4` when container is missing. */
    fun movieUrl(streamId: Int, containerExtension: String?): String {
        val ext = containerExtension?.takeIf { it.isNotEmpty() } ?: "mp4"
        return "$cleanBaseUrl/movie/$authPath/$streamId.$ext"
    }

    fun seriesUrl(streamId: String, containerExtension: String?): String {
        val ext = containerExtension?.takeIf { it.isNotEmpty() } ?: "mp4"
        return "$cleanBaseUrl/series/$authPath/$streamId.$ext"
    }
}
