package dev.android.anotheriptvplayer.ui.player

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPicture
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.res.stringResource
import dev.android.anotheriptvplayer.AnotherIptvPlayerApp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.player.LocalPlayerActivityState
import dev.android.anotheriptvplayer.player.MPVPlayer
import dev.android.anotheriptvplayer.player.MPVSurfaceView
import dev.android.anotheriptvplayer.player.PlayerAudioFocus
import dev.android.anotheriptvplayer.player.enterPip
import dev.android.anotheriptvplayer.player.findActivity
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop

/**
 * Full-screen video player. Hosts an [MPVSurfaceView] for libmpv to render
 * into and an auto-hiding overlay with the basic transport controls.
 *
 * Mirrors iOS `PlayerView` + `PlayerOverlayController` at the surface level;
 * advanced overlays (track menu, subtitle settings, edge sliders) come in
 * follow-up tasks as we port the iOS feature set screen by screen.
 *
 * The overlay shows on first frame, auto-hides after 3s of inactivity, and
 * reappears on tap. Back press always pops to the previous screen and
 * triggers `onCleared` on the VM, which disposes the libmpv handle.
 */
@Composable
fun PlayerScreen(
    playlistId: String,
    streamRef: String,
    kind: PlayerViewModel.Kind,
    onBack: () -> Unit,
    onPlayNextEpisode: (episodeId: String) -> Unit = {},
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    val vm: PlayerViewModel = viewModel(
        factory = PlayerViewModel.factory(app, playlistId, streamRef, kind),
    )
    val player = vm.player
    val resolveError by vm.resolveError.collectAsState()
    val title by vm.title.collectAsState()
    val shouldOfferAutoplay by vm.shouldOfferAutoplay.collectAsState()
    val nextEpisode by vm.nextEpisode.collectAsState()

    // If MPVPlayer construction failed (native lib not loaded, mpv_initialize
    // returned an error, …), `player` is null and `resolveError` is already
    // populated. Render the error-only path so we don't NPE on player.* below.
    if (player == null) {
        PlayerInitErrorScreen(
            message = resolveError ?: stringResource(R.string.error_player_init),
            onBack = onBack,
        )
        return
    }

    val isPaused by player.isPaused.collectAsState()
    val isBuffering by player.isBuffering.collectAsState()
    val isReady by player.isReady.collectAsState()
    val position by player.position.collectAsState()
    val duration by player.duration.collectAsState()
    val isSeekable by player.isSeekable.collectAsState()
    val failureMessage by player.playbackFailureMessage.collectAsState()
    val recentLogs by player.recentMpvLogs.collectAsState()

    val videoTracks by player.videoTracks.collectAsState()
    val audioTracks by player.audioTracks.collectAsState()
    val subtitleTracks by player.subtitleTracks.collectAsState()
    val currentVideoTrackId by player.currentVideoTrackId.collectAsState()
    val currentAudioTrackId by player.currentAudioTrackId.collectAsState()
    val currentSubtitleTrackId by player.currentSubtitleTrackId.collectAsState()
    val videoWidth by player.videoDisplayWidth.collectAsState()
    val videoHeight by player.videoDisplayHeight.collectAsState()

    var overlayVisible by remember { mutableStateOf(true) }
    var lastInteraction by remember { mutableStateOf(0L) }
    var showTracksSheet by remember { mutableStateOf(false) }
    var showSubtitleSheet by remember { mutableStateOf(false) }

    // Audio focus — pauses on focus loss (incoming call, alarm, other media),
    // resumes on focus gain. iOS equivalent: AVAudioSession interruption
    // notification handler in `VideoPlayerController`.
    DisposableEffect(player) {
        val focus = PlayerAudioFocus(
            context = context,
            onPause = { player.pause() },
            onResume = { player.play() },
        )
        focus.request()
        onDispose { focus.release() }
    }

    // Auto-PiP: react to MainActivity.onUserLeaveHint (the Activity bumps the
    // pipTrigger counter). Gated on the `player.pipEnabled` preference so the
    // user can opt out; `drop(1)` skips the initial value at composition time.
    val activityState = LocalPlayerActivityState.current
    val playerPrefs = dev.android.anotheriptvplayer.ui.LocalPlayerPreferences.current
    val pipEnabled by playerPrefs.pipEnabled.collectAsState()
    LaunchedEffect(player, isReady, pipEnabled) {
        if (!isReady) return@LaunchedEffect
        if (!pipEnabled) return@LaunchedEffect
        snapshotFlow { activityState.pipTrigger.value }
            .drop(1)
            .collect {
                val activity = context.findActivity() ?: return@collect
                val w = player.videoDisplayWidth.value
                val h = player.videoDisplayHeight.value
                val aspect = if (w > 0 && h > 0) w.toFloat() / h.toFloat() else 16f / 9f
                activity.enterPip(aspect)
            }
    }

    // Reset Activity-level brightness override when PlayerScreen leaves the
    // composition so the rest of the app gets system brightness back.
    DisposableEffect(Unit) {
        onDispose { activityState.brightnessOverride.value = null }
    }

    // Auto-hide overlay 3s after the last interaction; re-shows on tap.
    // Skipped while paused / buffering so the controls stay reachable when
    // the user is mid-decision.
    LaunchedEffect(overlayVisible, isPaused, isBuffering, lastInteraction) {
        if (!overlayVisible || isPaused || isBuffering) return@LaunchedEffect
        delay(3000)
        overlayVisible = false
    }

    BackHandler {
        // Always pop; ViewModel.onCleared() disposes the mpv handle.
        onBack()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {
                overlayVisible = !overlayVisible
                lastInteraction = System.currentTimeMillis()
            },
    ) {
        MPVSurfaceView(player = player)

        // Gesture overlay sits *between* the surface and the controls overlay
        // so vertical drags (brightness/volume) and long-press (2× speed)
        // still work when the overlay is hidden. Hidden while in PiP.
        if (!activityState.isInPip.value) {
            PlayerGestureLayer(
                onSetPlaybackRate = { rate -> player.setPlaybackRate(rate) },
            )
        }

        // Spinner overlay while buffering OR before first FILE_LOADED.
        if (isBuffering || !isReady) {
            Box(
                modifier = Modifier.align(Alignment.Center),
            ) {
                CircularProgressIndicator(color = Color.White)
            }
        }

        AnimatedVisibility(
            visible = overlayVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize(),
        ) {
            PlayerOverlay(
                title = title,
                isPaused = isPaused,
                isSeekable = isSeekable,
                positionSeconds = position,
                durationSeconds = duration,
                showPipButton = true,
                showTracksButton = videoTracks.isNotEmpty() ||
                    audioTracks.isNotEmpty() ||
                    subtitleTracks.size > 1,
                onPlayPause = {
                    if (isPaused) player.play() else player.pause()
                    lastInteraction = System.currentTimeMillis()
                },
                onSeekBack10 = {
                    player.jumpRelative(-10)
                    lastInteraction = System.currentTimeMillis()
                },
                onSeekFwd10 = {
                    player.jumpRelative(10)
                    lastInteraction = System.currentTimeMillis()
                },
                onScrub = { fraction ->
                    player.seekToFraction(fraction)
                    lastInteraction = System.currentTimeMillis()
                },
                onEnterPip = {
                    val activity = context.findActivity() ?: return@PlayerOverlay
                    val aspect = if (videoWidth > 0 && videoHeight > 0) {
                        videoWidth.toFloat() / videoHeight.toFloat()
                    } else 16f / 9f
                    activity.enterPip(aspect)
                    lastInteraction = System.currentTimeMillis()
                },
                onOpenTracks = {
                    showTracksSheet = true
                    lastInteraction = System.currentTimeMillis()
                },
                onOpenSubtitles = {
                    showSubtitleSheet = true
                    lastInteraction = System.currentTimeMillis()
                },
                onBack = onBack,
            )
        }

        if (shouldOfferAutoplay && nextEpisode != null) {
            AutoplayNextOverlay(
                title = nextEpisode!!.title ?: stringResource(
                    R.string.player_episode_default_format,
                    nextEpisode!!.episodeNum?.toString().orEmpty(),
                ),
                onCancel = { vm.consumeAutoplayOffer() },
                onPlay = {
                    vm.consumeAutoplayOffer()
                    onPlayNextEpisode(nextEpisode!!.id)
                },
            )
        }

        if (showSubtitleSheet) {
            SubtitleAppearanceSheet(
                player = player,
                onDismiss = { showSubtitleSheet = false },
            )
        }

        if (showTracksSheet) {
            TracksSheet(
                videoTracks = videoTracks,
                audioTracks = audioTracks,
                subtitleTracks = subtitleTracks,
                currentVideoTrackId = currentVideoTrackId,
                currentAudioTrackId = currentAudioTrackId,
                currentSubtitleTrackId = currentSubtitleTrackId,
                onSelectVideo = player::selectVideoTrack,
                onSelectAudio = player::selectAudioTrack,
                onSelectSubtitle = player::selectSubtitleTrack,
                onDismiss = { showTracksSheet = false },
            )
        }

        // Failure overlay — covers either resolve-side or playback-side errors.
        // While we're stabilising the libmpv bring-up the overlay surfaces the
        // recent mpv log buffer so we can see the actual cause (vo init,
        // mediacodec init, HTTP status, TLS) without an `adb logcat` session.
        // Once playback is solid across IPTV providers, trim this back to the
        // single localized message and drop the log dump.
        val combinedError = resolveError ?: failureMessage
        if (combinedError != null) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0xCC000000))
                    .systemBarsPadding()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = combinedError,
                    color = Color.White,
                    fontSize = 16.sp,
                )
                if (recentLogs.isNotEmpty()) {
                    Text(
                        text = stringResource(R.string.player_mpv_recent_logs, recentLogs.size),
                        color = Color(0xCCFFFFFF),
                        fontSize = 12.sp,
                    )
                    LazyColumn(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        items(recentLogs) { line ->
                            Text(
                                text = line,
                                color = Color(0xDDFFFFFF),
                                fontSize = 10.sp,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerOverlay(
    title: String,
    isPaused: Boolean,
    isSeekable: Boolean,
    positionSeconds: Double,
    durationSeconds: Double,
    showPipButton: Boolean,
    showTracksButton: Boolean,
    onPlayPause: () -> Unit,
    onSeekBack10: () -> Unit,
    onSeekFwd10: () -> Unit,
    onScrub: (Float) -> Unit,
    onEnterPip: () -> Unit,
    onOpenTracks: () -> Unit,
    onOpenSubtitles: () -> Unit,
    onBack: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0x55000000))
            .systemBarsPadding(),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        // Top bar.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.common_back),
                    tint = Color.White,
                )
            }
            Text(
                text = title,
                color = Color.White,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 4.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            IconButton(onClick = onOpenSubtitles) {
                Icon(
                    Icons.Default.Subtitles,
                    contentDescription = stringResource(R.string.player_subtitles),
                    tint = Color.White,
                )
            }
            if (showTracksButton) {
                IconButton(onClick = onOpenTracks) {
                    Icon(
                        Icons.Default.Tune,
                        contentDescription = stringResource(R.string.player_tracks),
                        tint = Color.White,
                    )
                }
            }
            if (showPipButton) {
                IconButton(onClick = onEnterPip) {
                    Icon(
                        Icons.Default.PictureInPicture,
                        contentDescription = stringResource(R.string.player_pip),
                        tint = Color.White,
                    )
                }
            }
        }

        // Center controls.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onSeekBack10, enabled = isSeekable) {
                Icon(
                    Icons.Default.Replay10,
                    contentDescription = stringResource(R.string.player_seek_back_10),
                    tint = if (isSeekable) Color.White else Color(0x55FFFFFF),
                    modifier = Modifier.size(40.dp),
                )
            }
            Spacer(Modifier.width(24.dp))
            IconButton(onClick = onPlayPause) {
                Icon(
                    imageVector = if (isPaused) Icons.Default.PlayArrow else Icons.Default.Pause,
                    contentDescription = if (isPaused) stringResource(R.string.common_play) else stringResource(R.string.common_pause),
                    tint = Color.White,
                    modifier = Modifier.size(56.dp),
                )
            }
            Spacer(Modifier.width(24.dp))
            IconButton(onClick = onSeekFwd10, enabled = isSeekable) {
                Icon(
                    Icons.Default.Forward10,
                    contentDescription = stringResource(R.string.player_seek_fwd_10),
                    tint = if (isSeekable) Color.White else Color(0x55FFFFFF),
                    modifier = Modifier.size(40.dp),
                )
            }
        }

        // Bottom seek bar — fraction-based to keep the slider stable when
        // duration jitters during buffering / live seeks.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            val frac = if (durationSeconds > 0.0) {
                (positionSeconds / durationSeconds).toFloat().coerceIn(0f, 1f)
            } else {
                0f
            }
            Slider(
                value = frac,
                onValueChange = { onScrub(it) },
                enabled = isSeekable && durationSeconds > 0.0,
                colors = SliderDefaults.colors(
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color(0x66FFFFFF),
                    thumbColor = Color.White,
                ),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = formatTimecode(positionSeconds),
                    color = Color.White,
                    fontSize = 12.sp,
                )
                Text(
                    text = formatTimecode(durationSeconds),
                    color = Color.White,
                    fontSize = 12.sp,
                )
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun PlayerInitErrorScreen(message: String, onBack: () -> Unit) {
    BackHandler { onBack() }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .systemBarsPadding()
            .padding(16.dp),
    ) {
        Column(
            modifier = Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = message,
                color = Color.White,
                fontSize = 16.sp,
            )
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.common_back),
                    tint = Color.White,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TracksSheet(
    videoTracks: List<MPVPlayer.TrackInfo>,
    audioTracks: List<MPVPlayer.TrackInfo>,
    subtitleTracks: List<MPVPlayer.TrackInfo>,
    currentVideoTrackId: Int,
    currentAudioTrackId: Int,
    currentSubtitleTrackId: Int,
    onSelectVideo: (Int) -> Unit,
    onSelectAudio: (Int) -> Unit,
    onSelectSubtitle: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (videoTracks.size > 1) {
                TrackSection(
                    title = "Video",
                    icon = Icons.Default.PictureInPicture,
                    tracks = videoTracks,
                    selectedId = currentVideoTrackId,
                    onSelect = onSelectVideo,
                )
            }
            if (audioTracks.size > 1) {
                TrackSection(
                    title = "Ses",
                    icon = Icons.Default.Tune,
                    tracks = audioTracks,
                    selectedId = currentAudioTrackId,
                    onSelect = onSelectAudio,
                )
            }
            if (subtitleTracks.size > 1) {
                TrackSection(
                    title = stringResource(R.string.player_section_subtitles),
                    icon = Icons.Default.Subtitles,
                    tracks = subtitleTracks,
                    selectedId = currentSubtitleTrackId,
                    onSelect = onSelectSubtitle,
                )
            }
        }
    }
}

@Composable
private fun TrackSection(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tracks: List<MPVPlayer.TrackInfo>,
    selectedId: Int,
    onSelect: (Int) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(text = title, style = MaterialTheme.typography.titleMedium)
        }
        tracks.forEach { track ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        onSelect(track.id)
                    }
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = track.title,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (track.id == selectedId) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                    )
                    track.detail?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (track.id == selectedId) {
                    Text("✓", color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun AutoplayNextOverlay(
    title: String,
    onCancel: () -> Unit,
    onPlay: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xCC000000))
            .systemBarsPadding()
            .padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = stringResource(R.string.player_next_episode),
                color = Color(0xCCFFFFFF),
                fontSize = 12.sp,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = title,
                color = Color.White,
                fontSize = 18.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(20.dp))
            Row {
                androidx.compose.material3.TextButton(onClick = onCancel) {
                    Text(stringResource(R.string.common_cancel), color = Color.White)
                }
                Spacer(Modifier.width(12.dp))
                androidx.compose.material3.Button(onClick = onPlay) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.common_play))
                }
            }
        }
    }
}

private fun formatTimecode(seconds: Double): String {
    if (!seconds.isFinite() || seconds <= 0.0) return "00:00"
    val total = seconds.toInt()
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format("%02d:%02d:%02d", h, m, s)
    else String.format("%02d:%02d", m, s)
}
