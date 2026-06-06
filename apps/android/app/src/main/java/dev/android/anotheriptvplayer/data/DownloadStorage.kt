package dev.android.anotheriptvplayer.data

import android.content.Context
import java.io.File

/**
 * Kotlin port of iOS `DownloadStorage`.
 *
 * Maps stable item IDs to a relative path inside the app's downloads cache
 * directory. The directory lives under the app's external-files area on
 * Android so the user can wipe everything via Settings → Apps → Storage
 * without losing the rest of the app's state.
 *
 * Path layout: `<root>/<playlistId>/<contentId>.<ext>`.
 *
 * Returning `relativePath` instead of absolute lets us store stable strings
 * in the DB even if the user moves the app or restores a backup.
 */
class DownloadStorage(context: Context) {

    val rootDir: File = run {
        // `getExternalFilesDir` returns a sandbox path that survives reboots
        // and doesn't need extra runtime permissions, but is wiped on app
        // uninstall — exactly the lifetime we want for VOD downloads.
        val external = context.getExternalFilesDir(null)
            ?: context.filesDir // Fallback if external storage isn't mounted.
        File(external, "Downloads").apply { mkdirs() }
    }

    fun relativePath(playlistId: String, contentId: String, extension: String?): String {
        val safeExt = extension?.takeIf { it.isNotBlank() }?.lowercase() ?: "mp4"
        return "$playlistId/$contentId.$safeExt"
    }

    fun absolutePath(relativePath: String): File = File(rootDir, relativePath)

    fun delete(relativePath: String) {
        val file = absolutePath(relativePath)
        if (file.exists()) file.delete()
    }

    fun usedBytes(): Long {
        var total = 0L
        rootDir.walkBottomUp().forEach { if (it.isFile) total += it.length() }
        return total
    }
}
