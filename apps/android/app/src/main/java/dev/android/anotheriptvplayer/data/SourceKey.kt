package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.model.Playlist
import java.security.MessageDigest

/**
 * Stable, non-secret identifier for a playlist, used to scope sync items
 * (`sync/key = "<sourceKey>:<contentType>:<contentId>"`). Derived from the
 * server + account identity rather than the local playlist row id, which is
 * generated per install and would differ across a user's devices for what
 * is otherwise "the same playlist". The password is deliberately excluded
 * so it never reaches the sync server. Kotlin counterpart of the Tizen
 * client's `playlistSourceKey` (`apps/tizen/src/sync/sourceKey.ts`).
 */
fun playlistSourceKey(playlist: Playlist): String {
    val raw = "${playlist.kind.dbValue}:${playlist.serverUrl}:${playlist.username}"
    val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { "%02x".format(it) }
}
