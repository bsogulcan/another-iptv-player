package dev.android.anotheriptvplayer.player

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf

/**
 * State shared between [dev.android.anotheriptvplayer.MainActivity] and
 * the active `PlayerScreen` composition.
 *
 * Three knobs:
 *  - `pipTrigger` — bumped from `MainActivity.onUserLeaveHint`. PlayerScreen
 *    observes it and calls `enterPip(aspect)` so playback transitions into
 *    Picture-in-Picture when the user hits home / app switcher.
 *  - `isInPip` — observed by PlayerScreen so the overlay can hide its chrome
 *    while in PiP.
 *  - `brightnessOverride` — `null` = system brightness, otherwise 0..1 sets
 *    `window.attributes.screenBrightness`. The Activity reads this whenever
 *    it changes and pushes the value onto the window.
 *
 * iOS counterpart spreads these across `MPVPlayerPiPContainer` (`pipManualSignal`,
 * scenePhase observer) and `PlayerControlCenterStyleEdgeSliders.brightness`.
 */
class PlayerActivityState {
    var pipTrigger: MutableState<Int> = mutableStateOf(0)
    var isInPip: MutableState<Boolean> = mutableStateOf(false)
    var brightnessOverride: MutableState<Float?> = mutableStateOf(null)
}

val LocalPlayerActivityState = compositionLocalOf { PlayerActivityState() }
