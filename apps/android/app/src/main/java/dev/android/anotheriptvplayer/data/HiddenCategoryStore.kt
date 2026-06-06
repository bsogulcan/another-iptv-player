package dev.android.anotheriptvplayer.data

import android.content.Context
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/**
 * Kotlin port of iOS `HiddenCategoryStore`.
 *
 * Persists "hide this category from the dashboard" choices per playlist +
 * content type (`live`, `vod`, `series`). iOS uses UserDefaults; we use
 * Android `SharedPreferences` with the same key layout
 * (`hidden_categories.<playlistId>.<type>`) so semantics match.
 *
 * Writes bump a [revision] counter; [observeHidden] re-emits whenever the
 * counter changes so consumers see updates as soon as the user toggles a
 * category. This mirrors the iOS `@Published var version` pattern.
 */
class HiddenCategoryStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(
        "hidden_categories",
        Context.MODE_PRIVATE,
    )

    private val _revision = MutableStateFlow(0L)
    @Suppress("unused")
    val revision = _revision.asStateFlow()

    private fun key(playlistId: String, type: String): String = "$playlistId.$type"

    fun hiddenIds(playlistId: String, type: String): Set<String> =
        prefs.getStringSet(key(playlistId, type), emptySet()).orEmpty()

    fun isHidden(playlistId: String, type: String, categoryId: String): Boolean =
        hiddenIds(playlistId, type).contains(categoryId)

    /** Reactive read — emits the current set every time anything changes. */
    fun observeHidden(playlistId: String, type: String): Flow<Set<String>> =
        _revision.map { hiddenIds(playlistId, type) }.distinctUntilChanged()

    fun setHidden(
        hide: Boolean,
        playlistId: String,
        type: String,
        categoryId: String,
    ) {
        val key = key(playlistId, type)
        // `getStringSet` returns a defensive copy that's safe to read but
        // not safe to pass back to `putStringSet`; SharedPreferences caches
        // it internally and may return the same reference next time. Always
        // construct a new HashSet for the write.
        val current = HashSet(prefs.getStringSet(key, emptySet()).orEmpty())
        val changed = if (hide) current.add(categoryId) else current.remove(categoryId)
        if (!changed) return
        prefs.edit().putStringSet(key, current).apply()
        _revision.value = _revision.value + 1L
    }

    fun toggle(playlistId: String, type: String, categoryId: String) {
        setHidden(!isHidden(playlistId, type, categoryId), playlistId, type, categoryId)
    }

    /** Called when a playlist is deleted — drops every key for that id. */
    fun removeAll(playlistId: String) {
        val editor = prefs.edit()
        var changed = false
        for (type in arrayOf("live", "vod", "series", "m3u")) {
            val k = key(playlistId, type)
            if (prefs.contains(k)) {
                editor.remove(k)
                changed = true
            }
        }
        if (changed) {
            editor.apply()
            _revision.value = _revision.value + 1L
        }
    }
}
