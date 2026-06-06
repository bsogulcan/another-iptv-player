package dev.android.anotheriptvplayer.data

import android.content.Context
import dev.android.anotheriptvplayer.BuildConfig
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Kotlin port of iOS `RatingManager`.
 *
 * In-app review eligibility tracker with the same rules as iOS:
 *  - at least 4 "successful sessions" recorded across launches,
 *  - app version differs from the version we last prompted in,
 *  - more than 90 days since the last prompt.
 *
 * Successful sessions dedupe per process via [didCountThisLaunch] so the
 * same launch can't inflate the counter.
 *
 * **Why no Play Core dependency yet:** the iOS port uses
 * `SKStoreReviewController.requestReview(in:)`; the Android counterpart is
 * Play Core's in-app review API, which adds a non-trivial library. We isolate
 * the eligibility decision here so a UI layer can call into Play Core later
 * without changing the rest of the codebase — for now [shouldRequestReview]
 * returns the same boolean the iOS layer evaluates and the UI no-ops.
 */
class RatingManager(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val didCountThisLaunch = AtomicBoolean(false)

    fun registerSuccessfulSession() {
        if (!didCountThisLaunch.compareAndSet(false, true)) return
        val next = (prefs.getInt(KEY_COUNT, 0) + 1).coerceAtLeast(0)
        prefs.edit().putInt(KEY_COUNT, next).apply()
    }

    /** True when iOS would have called `requestReview(in:)`. */
    fun shouldRequestReview(): Boolean {
        val count = prefs.getInt(KEY_COUNT, 0)
        if (count < MIN_SESSIONS) return false
        if (prefs.getString(KEY_LAST_VERSION, null) == BuildConfig.VERSION_NAME) return false
        val lastPromptMs = prefs.getLong(KEY_LAST_PROMPT, 0L)
        if (lastPromptMs != 0L && System.currentTimeMillis() - lastPromptMs < COOLDOWN_MS) return false
        return true
    }

    /** Call from the UI when the in-app review flow has actually been launched. */
    fun markReviewPrompted() {
        prefs.edit()
            .putString(KEY_LAST_VERSION, BuildConfig.VERSION_NAME)
            .putLong(KEY_LAST_PROMPT, System.currentTimeMillis())
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "rating"
        private const val KEY_COUNT = "successfulSessionCount"
        private const val KEY_LAST_VERSION = "lastPromptVersion"
        private const val KEY_LAST_PROMPT = "lastPromptDateMs"
        private const val MIN_SESSIONS = 4
        private const val COOLDOWN_MS = 90L * 24L * 60L * 60L * 1000L
    }
}
