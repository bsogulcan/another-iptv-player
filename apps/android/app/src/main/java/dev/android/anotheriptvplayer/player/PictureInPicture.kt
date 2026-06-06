package dev.android.anotheriptvplayer.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.util.Rational

/**
 * Kotlin counterpart of iOS `MPVPlayerPiPContainer.processManualPiPTrigger`
 * and the auto-enter triggered by `willResignActive`.
 *
 * Android Picture-in-Picture is purely Activity-level: we enter PiP by
 * calling [Activity.enterPictureInPictureMode] with a [PictureInPictureParams]
 * containing the video aspect ratio. The OS handles the layout transition,
 * the on-screen controls, and the resize callbacks; our Compose tree stays
 * untouched.
 *
 * Caller pattern:
 *   ```
 *   val activity = LocalContext.current.findActivity()
 *   IconButton(onClick = { activity?.enterPip(aspect) }) { … }
 *   ```
 */

fun Context.findActivity(): Activity? {
    var ctx: Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

/** No-op on devices without PiP. Returns whether PiP was actually triggered. */
fun Activity.enterPip(aspect: Float): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    val params = PictureInPictureParams.Builder().apply {
        // Android requires the aspect ratio's numerator/denominator to be in
        // the (0.418410, 2.390000) range — clamp to be safe.
        val clamped = aspect.coerceIn(0.42f, 2.39f)
        val rational = Rational((clamped * 1000).toInt().coerceAtLeast(1), 1000)
        setAspectRatio(rational)
    }.build()
    return enterPictureInPictureMode(params)
}
