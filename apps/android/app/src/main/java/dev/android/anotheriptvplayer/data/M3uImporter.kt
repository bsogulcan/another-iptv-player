package dev.android.anotheriptvplayer.data

import androidx.room.withTransaction
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.M3uChannelEntity
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.networking.ParsedM3UChannel
import java.security.MessageDigest

/**
 * Kotlin port of iOS `M3UImporter.replace(...)`.
 *
 * Performs a "replace whole playlist" import in one Room transaction so a
 * crash mid-import leaves the catalog empty (eligible for re-import) rather
 * than half-written.
 *
 * Channel IDs are deterministic SHA-256 of `playlistId:url`, identical to
 * iOS — that way favourites + watch history survive a reimport that doesn't
 * change channel URLs.
 */
class M3uImporter(private val database: AppDatabase) {

    suspend fun replace(
        playlist: Playlist,
        channels: List<ParsedM3UChannel>,
        epgUrl: String?,
        clearServerUrl: Boolean = false,
    ) {
        val updated = playlist.copy(
            m3uEpgUrl = epgUrl,
            serverUrl = if (clearServerUrl) "" else playlist.serverUrl,
        )

        val rows = channels.mapIndexed { index, ch ->
            M3uChannelEntity(
                id = stableChannelId(playlist.id, ch.url, fallbackIndex = index),
                playlistId = playlist.id,
                name = ch.name,
                url = ch.url,
                tvgId = ch.tvgId,
                tvgName = ch.tvgName,
                tvgLogo = ch.tvgLogo,
                tvgCountry = ch.tvgCountry,
                groupTitle = ch.groupTitle,
                userAgent = ch.userAgent,
                sortIndex = index,
            )
        }

        database.withTransaction {
            database.playlistDao().update(updated)
            database.m3uChannelDao().deleteByPlaylist(playlist.id)
            // INSERT OR REPLACE — stable IDs mean re-imports preserve linked
            // favourites/watch history rows.
            database.m3uChannelDao().upsertAll(rows)
        }
    }

    companion object {
        fun stableChannelId(
            playlistId: String,
            url: String,
            fallbackIndex: Int = 0,
        ): String {
            val key = if (url.trim().isEmpty()) {
                "$playlistId:__idx:$fallbackIndex"
            } else {
                "$playlistId:${url.trim()}"
            }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(key.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }
    }
}
