package dev.android.anotheriptvplayer.player

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Compose binding that hands the SurfaceView's Surface to [player] and
 * pulls it back on tear-down. Mirrors the role of iOS
 * `MPVPlayerVideoSurface` (which hosts a MetalLayer fed by `NativeVideoOutput`)
 * but on Android libmpv renders directly into our `ANativeWindow`, so there's
 * no intermediate texture pipeline.
 *
 * The black-letterbox container is intentional: libmpv pads the video to fit
 * `wid`'s window if no aspect is enforced, so we wrap the SurfaceView in a
 * Box with `Modifier.aspectRatio(...)` driven by the player's reported
 * `videoDisplay{Width,Height}`. When the video size isn't known yet we fall
 * back to 16:9 to avoid a "0-sized" collapse during first-frame wait.
 */
@Composable
fun MPVSurfaceView(
    player: MPVPlayer,
    modifier: Modifier = Modifier,
) {
    val w by player.videoDisplayWidth.collectAsState()
    val h by player.videoDisplayHeight.collectAsState()

    val aspect = if (w > 0 && h > 0) w.toFloat() / h.toFloat() else 16f / 9f

    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        AndroidView(
            // Repeated recompositions otherwise tear down + recreate the
            // SurfaceView, which forces a libmpv VO reinit + first-frame
            // latency hit on every state change. The factory + DisposableEffect
            // pair below already manages attach/detach correctly.
            factory = { ctx ->
                SurfaceView(ctx).apply {
                    // Without this, SurfaceView punches its "hole" BEHIND the
                    // window background — and our parent PlayerScreen Box has
                    // a `.background(Color.Black)`, which covers the hole and
                    // hides the actual decoded frames. Media-overlay z-order
                    // draws the surface on top of the window background but
                    // still below other views, so the controls overlay above
                    // stays visible.
                    setZOrderMediaOverlay(true)
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) {
                            player.attachSurface(holder.surface)
                        }
                        override fun surfaceChanged(
                            holder: SurfaceHolder, format: Int, width: Int, height: Int,
                        ) {
                            // No-op: libmpv reads back the window size from the
                            // ANativeWindow on each frame; we don't need to
                            // re-issue any property changes here.
                        }
                        override fun surfaceDestroyed(holder: SurfaceHolder) {
                            player.detachSurface()
                        }
                    })
                }
            },
            // `fillMaxSize` inside an `aspectRatio` box: aspectRatio sets
            // the container's bounds to match the video's aspect, fillMaxSize
            // makes the SurfaceView fill those bounds. The previous
            // `wrapContentSize()` allowed the SurfaceView to collapse to its
            // intrinsic 0×0 size — frames decoded but had nowhere to render.
            modifier = Modifier
                .aspectRatio(aspect)
                .fillMaxSize(),
        )
    }

    // Belt-and-suspenders cleanup: even if the SurfaceView's lifecycle
    // somehow leaks the holder callback (e.g. Compose tree torn down before
    // surfaceDestroyed fires), this ensures libmpv never holds a dangling
    // ANativeWindow.
    DisposableEffect(player) {
        onDispose { player.detachSurface() }
    }
}
