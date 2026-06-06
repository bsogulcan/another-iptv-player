package dev.android.anotheriptvplayer.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build

/**
 * Kotlin port of the AudioSession setup iOS does in
 * `VideoPlayerController.setupAudioHandler` — minus the iOS-specific bits
 * (Bluetooth A2DP / AirPlay options) which are handled by the system on
 * Android anyway.
 *
 * The PlayerScreen calls [request] in `DisposableEffect`'s effect block and
 * [release] in `onDispose`. Focus loss handler pauses the player so a phone
 * call / navigation prompt / another media app's audio stops us cleanly.
 */
class PlayerAudioFocus(
    private val context: Context,
    private val onPause: () -> Unit,
    private val onResume: () -> Unit,
) {

    private val audioManager =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var request: AudioFocusRequest? = null
    private val listener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> onPause()
            AudioManager.AUDIOFOCUS_GAIN -> onResume()
        }
    }

    fun request(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(listener)
                .setAcceptsDelayedFocusGain(true)
                .build()
            request = req
            audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    fun release() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            request?.let { audioManager.abandonAudioFocusRequest(it) }
            request = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(listener)
        }
    }
}
