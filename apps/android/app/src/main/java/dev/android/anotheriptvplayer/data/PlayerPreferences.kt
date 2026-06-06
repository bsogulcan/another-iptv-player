package dev.android.anotheriptvplayer.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Kotlin port of the iOS player `UserDefaults.register(defaults:)` block —
 * the three "player.…" preferences set during app init.
 *
 * Exposes each preference as a [StateFlow] so Compose screens can collect
 * them and re-render when the user toggles a switch elsewhere. Writes go
 * through the setter, which both persists the value and republishes.
 *
 * Defaults match iOS exactly so existing dashboards / settings screens
 * behave the same regardless of platform.
 */
class PlayerPreferences(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _pipEnabled = MutableStateFlow(prefs.getBoolean(KEY_PIP, DEFAULT_PIP))
    val pipEnabled: StateFlow<Boolean> = _pipEnabled.asStateFlow()

    private val _continuePlayingInBackground = MutableStateFlow(
        prefs.getBoolean(KEY_BG_PLAY, DEFAULT_BG_PLAY),
    )
    val continuePlayingInBackground: StateFlow<Boolean> =
        _continuePlayingInBackground.asStateFlow()

    private val _speedUpOnLongPress = MutableStateFlow(
        prefs.getBoolean(KEY_LONG_PRESS_SPEED, DEFAULT_LONG_PRESS_SPEED),
    )
    val speedUpOnLongPress: StateFlow<Boolean> = _speedUpOnLongPress.asStateFlow()

    fun setPipEnabled(value: Boolean) {
        prefs.edit().putBoolean(KEY_PIP, value).apply()
        _pipEnabled.value = value
    }

    fun setContinuePlayingInBackground(value: Boolean) {
        prefs.edit().putBoolean(KEY_BG_PLAY, value).apply()
        _continuePlayingInBackground.value = value
    }

    fun setSpeedUpOnLongPress(value: Boolean) {
        prefs.edit().putBoolean(KEY_LONG_PRESS_SPEED, value).apply()
        _speedUpOnLongPress.value = value
    }

    companion object {
        private const val PREFS_NAME = "player"
        private const val KEY_PIP = "pipEnabled"
        private const val KEY_BG_PLAY = "continuePlayingInBackground"
        private const val KEY_LONG_PRESS_SPEED = "speedUpOnLongPress"

        private const val DEFAULT_PIP = true
        private const val DEFAULT_BG_PLAY = true
        private const val DEFAULT_LONG_PRESS_SPEED = true
    }
}
