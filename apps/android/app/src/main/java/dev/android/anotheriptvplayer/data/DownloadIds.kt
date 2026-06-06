package dev.android.anotheriptvplayer.data

/**
 * Kotlin port of iOS `DownloadManager.idFor(...)` factories.
 *
 * Keeping these as plain functions (not a sealed class) means the IDs round-
 * trip cleanly through WorkManager `tags` and DAO query strings.
 */
object DownloadIds {
    fun vod(playlistId: String, streamId: Int): String = "vod.$playlistId.$streamId"
    fun episode(playlistId: String, episodeId: String): String = "episode.$playlistId.$episodeId"
    fun m3uChannel(playlistId: String, channelId: String): String = "vod.$playlistId.m3u_$channelId"
}
