package dev.android.anotheriptvplayer.data

import android.content.Context

/**
 * Persists which playlist the user last opened from the list, so the next
 * launch can jump straight back into the dashboard.
 *
 * Mirrors the iOS `UserDefaults` key `lastPlaylistId` exactly: a single string
 * UUID, written on open and cleared when the user navigates back to the list.
 *
 * The auto-load attempt itself is a one-shot per process (see
 * `AppNavigation`); if the saved id no longer exists in the DB we silently
 * clear it so the next launch starts at the list.
 */
class LastPlaylistStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE,
    )

    fun read(): String? = prefs.getString(KEY, null)

    fun write(playlistId: String) {
        prefs.edit().putString(KEY, playlistId).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS_NAME = "session"
        private const val KEY = "lastPlaylistId"
    }
}
