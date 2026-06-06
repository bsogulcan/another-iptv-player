package dev.android.anotheriptvplayer.ui.player

import android.content.Context
import android.media.AudioManager
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrightnessHigh
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.player.LocalPlayerActivityState
import kotlinx.coroutines.delay

/**
 * Compose port of iOS `PlayerControlCenterStyleEdgeSliders` +
 * `PlayerMediaKitStyleTouchOverlay`.
 *
 * Vertical drag on the left half adjusts brightness via the Activity window's
 * `screenBrightness` attribute (the system-level brightness override iOS uses
 * `UIScreen.main.brightness` for); drag on the right half adjusts volume via
 * `AudioManager.STREAM_MUSIC`. Long-press anywhere triggers 2× playback speed
 * for the duration of the press.
 *
 * A floating chip in the centre shows the current value during the gesture.
 */
@Composable
fun PlayerGestureLayer(
    onSetPlaybackRate: (Double) -> Unit,
    modifier: Modifier = Modifier,
    speedUpRate: Double = 2.0,
    normalRate: Double = 1.0,
) {
    val context = LocalContext.current
    val activityState = LocalPlayerActivityState.current

    val audioManager = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    val maxVolume = remember { audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1) }

    var volume by remember {
        mutableFloatStateOf(
            audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / maxVolume,
        )
    }
    var brightness by remember {
        mutableFloatStateOf(activityState.brightnessOverride.value ?: 0.5f)
    }

    // Toast-style overlay state: which slider is active + the value.
    var feedback by remember { mutableStateOf<GestureFeedback?>(null) }
    LaunchedEffect(feedback) {
        if (feedback != null) {
            delay(700)
            feedback = null
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        // Two invisible vertical drag zones — left half = brightness, right
        // half = volume. They sit *below* the rest of the overlay so taps on
        // the controls still land, but drags get captured first.
        Row(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .pointerInput(maxVolume) {
                        detectVerticalDragGestures { _, delta ->
                            // -delta because a downward drag should decrease.
                            brightness = (brightness - delta / size.height.toFloat()).coerceIn(0f, 1f)
                            activityState.brightnessOverride.value = brightness
                            feedback = GestureFeedback.Brightness(brightness)
                        }
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onLongPress = {
                                onSetPlaybackRate(speedUpRate)
                                feedback = GestureFeedback.Speed(speedUpRate)
                            },
                            onPress = {
                                tryAwaitRelease()
                                onSetPlaybackRate(normalRate)
                            },
                        )
                    },
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .pointerInput(maxVolume) {
                        detectVerticalDragGestures { _, delta ->
                            volume = (volume - delta / size.height.toFloat()).coerceIn(0f, 1f)
                            val target = (volume * maxVolume).toInt().coerceIn(0, maxVolume)
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_MUSIC,
                                target,
                                0,
                            )
                            feedback = GestureFeedback.Volume(volume)
                        }
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onLongPress = {
                                onSetPlaybackRate(speedUpRate)
                                feedback = GestureFeedback.Speed(speedUpRate)
                            },
                            onPress = {
                                tryAwaitRelease()
                                onSetPlaybackRate(normalRate)
                            },
                        )
                    },
            )
        }

        feedback?.let { fb ->
            FeedbackChip(fb, modifier = Modifier.align(Alignment.Center))
        }
    }
}

private sealed class GestureFeedback {
    data class Brightness(val value: Float) : GestureFeedback()
    data class Volume(val value: Float) : GestureFeedback()
    data class Speed(val rate: Double) : GestureFeedback()
}

@Composable
private fun FeedbackChip(feedback: GestureFeedback, modifier: Modifier = Modifier) {
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = Color(0xCC1F1F1F),
        modifier = modifier,
    ) {
        when (feedback) {
            is GestureFeedback.Brightness -> SliderRow(
                icon = Icons.Default.BrightnessHigh,
                label = stringResource(R.string.player_brightness),
                fraction = feedback.value,
            )
            is GestureFeedback.Volume -> SliderRow(
                icon = Icons.Default.VolumeUp,
                label = stringResource(R.string.player_volume),
                fraction = feedback.value,
            )
            is GestureFeedback.Speed -> Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("⏩  ${feedback.rate}×", color = Color.White)
            }
        }
    }
}

@Composable
private fun SliderRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    fraction: Float,
) {
    Column(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
            Text("  $label", color = Color.White, style = MaterialTheme.typography.bodyMedium)
        }
        LinearProgressIndicator(
            progress = { fraction },
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(2.dp))
                .background(Color(0x55FFFFFF)),
        )
    }
}
