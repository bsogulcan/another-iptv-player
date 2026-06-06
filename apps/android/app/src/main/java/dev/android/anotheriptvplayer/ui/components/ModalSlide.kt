package dev.android.anotheriptvplayer.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt

/** Duration of the modal slide-up, kept in sync with the slide-down in AppNavigation. */
const val ModalSlideDurationMs = 320

/**
 * Wraps a screen so it slides up from the bottom on first appearance, the way a
 * native Android full-screen modal dialog does.
 *
 * The offset is applied with [offset] (a layout placement shift), not a
 * `graphicsLayer` translation, so touch targets move with the animation. A
 * `slideInVertically` NavHost transition does not do this reliably, which is
 * why the slide-up is driven here instead.
 */
@Composable
fun ModalSlideContainer(content: @Composable () -> Unit) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val fullHeightPx = constraints.maxHeight.toFloat()
        // Starts one screen-height below its resting place, then animates up.
        val translation = remember { Animatable(fullHeightPx) }

        LaunchedEffect(Unit) {
            translation.animateTo(
                targetValue = 0f,
                animationSpec = tween(ModalSlideDurationMs, easing = FastOutSlowInEasing),
            )
        }

        Box(
            modifier = Modifier.offset { IntOffset(0, translation.value.roundToInt()) },
        ) {
            content()
        }
    }
}
