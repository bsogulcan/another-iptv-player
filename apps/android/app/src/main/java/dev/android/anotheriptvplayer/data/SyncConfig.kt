package dev.android.anotheriptvplayer.data

import android.content.Context

/**
 * Settings for the self-hosted sync feature (server URL, device token,
 * auto-sync schedule). Plain `SharedPreferences`-backed properties, like
 * [PlayerPreferences] but without the `StateFlow` wrapping — the Settings UI
 * owns its own local state and re-reads these on demand, matching the
 * Tizen client's `sync/config.ts`.
 */
class SyncConfig(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var serverUrl: String?
        get() = prefs.getString(KEY_SERVER_URL, null)
        set(value) = prefs.edit().putStringOrRemove(KEY_SERVER_URL, value).apply()

    var deviceToken: String?
        get() = prefs.getString(KEY_DEVICE_TOKEN, null)
        set(value) = prefs.edit().putStringOrRemove(KEY_DEVICE_TOKEN, value).apply()

    var deviceId: Long?
        get() = prefs.getLong(KEY_DEVICE_ID, -1L).takeIf { it >= 0 }
        set(value) = putLongOrRemove(KEY_DEVICE_ID, value)

    var accountUsername: String?
        get() = prefs.getString(KEY_ACCOUNT_USERNAME, null)
        set(value) = prefs.edit().putStringOrRemove(KEY_ACCOUNT_USERNAME, value).apply()

    var autoSyncEnabled: Boolean
        get() = prefs.getBoolean(KEY_AUTO_SYNC, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_SYNC, value).apply()

    /** Minutes between periodic syncs while the app is foregrounded; 0 = manual only. */
    var intervalMinutes: Int
        get() = prefs.getInt(KEY_INTERVAL_MINUTES, 30)
        set(value) = prefs.edit().putInt(KEY_INTERVAL_MINUTES, value).apply()

    /** Delta-pull cursor. Reset to 0 to force a full replay from the server. */
    var cursor: Long
        get() = prefs.getLong(KEY_CURSOR, 0L)
        set(value) = prefs.edit().putLong(KEY_CURSOR, value).apply()

    var lastSyncedAt: Long?
        get() = prefs.getLong(KEY_LAST_SYNCED_AT, -1L).takeIf { it >= 0 }
        set(value) = putLongOrRemove(KEY_LAST_SYNCED_AT, value)

    var lastSyncError: String?
        get() = prefs.getString(KEY_LAST_SYNC_ERROR, null)
        set(value) = prefs.edit().putStringOrRemove(KEY_LAST_SYNC_ERROR, value).apply()

    val isConfigured: Boolean
        get() = serverUrl != null && deviceToken != null

    /** A newly added playlist might match one another device already pushed
     * favorites/progress for before this device ever synced; those pushes
     * are behind the current cursor, so replay from the start. */
    fun resetCursor() {
        cursor = 0L
    }

    /** Forgets everything except server URL (kept so the sign-in form stays filled in). */
    fun clearAccount() {
        deviceToken = null
        deviceId = null
        accountUsername = null
        cursor = 0L
        lastSyncedAt = null
        lastSyncError = null
    }

    private fun android.content.SharedPreferences.Editor.putStringOrRemove(
        key: String,
        value: String?,
    ): android.content.SharedPreferences.Editor =
        if (value == null) remove(key) else putString(key, value)

    private fun putLongOrRemove(key: String, value: Long?) {
        val editor = prefs.edit()
        if (value == null) editor.remove(key) else editor.putLong(key, value)
        editor.apply()
    }

    companion object {
        private const val PREFS_NAME = "sync"
        private const val KEY_SERVER_URL = "serverUrl"
        private const val KEY_DEVICE_TOKEN = "deviceToken"
        private const val KEY_DEVICE_ID = "deviceId"
        private const val KEY_ACCOUNT_USERNAME = "accountUsername"
        private const val KEY_AUTO_SYNC = "autoSyncEnabled"
        private const val KEY_INTERVAL_MINUTES = "intervalMinutes"
        private const val KEY_CURSOR = "cursor"
        private const val KEY_LAST_SYNCED_AT = "lastSyncedAt"
        private const val KEY_LAST_SYNC_ERROR = "lastSyncError"
    }
}
