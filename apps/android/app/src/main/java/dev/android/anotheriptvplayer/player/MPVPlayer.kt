package dev.android.anotheriptvplayer.player

import android.content.Context
import android.util.Log
import android.view.Surface
import dev.android.anotheriptvplayer.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * High-level libmpv player that mirrors `ios/another-iptv-player/MPVPlayer/MPVPlayer.swift`.
 *
 * Public surface (`StateFlow` properties + [load]/[play]/[pause]/[seek]/...)
 * matches the iOS class field-for-field so the UI layer can be ported screen
 * by screen without re-deriving state. All mpv API calls are serialised on a
 * dedicated single-thread executor (`mpvQueue` on iOS), and observed property
 * changes flow back from the JNI drain thread into the StateFlows.
 *
 * Lifecycle: `MPVPlayer()` immediately creates + initialises libmpv. Caller
 * must invoke [attachSurface] from `SurfaceHolder.surfaceCreated`, then
 * [load] to start playback, then [dispose] (or rely on GC; `dispose` joins
 * the drain thread synchronously so prefer it).
 */
class MPVPlayer(context: Context) {

    private val appContext: Context = context.applicationContext

    // ---------------------------------------------------------------------
    // Published state (1:1 with iOS @Published fields).
    // ---------------------------------------------------------------------

    private val _isReady = MutableStateFlow(false)
    val isReady: StateFlow<Boolean> = _isReady.asStateFlow()

    private val _isPaused = MutableStateFlow(true)
    val isPaused: StateFlow<Boolean> = _isPaused.asStateFlow()

    private val _isSeekable = MutableStateFlow(false)
    val isSeekable: StateFlow<Boolean> = _isSeekable.asStateFlow()

    private val _position = MutableStateFlow(0.0)
    val position: StateFlow<Double> = _position.asStateFlow()

    private val _duration = MutableStateFlow(0.0)
    val duration: StateFlow<Double> = _duration.asStateFlow()

    private val _isBuffering = MutableStateFlow(false)
    val isBuffering: StateFlow<Boolean> = _isBuffering.asStateFlow()

    private val _isCompleted = MutableStateFlow(false)
    val isCompleted: StateFlow<Boolean> = _isCompleted.asStateFlow()

    private val _volume = MutableStateFlow(100.0)
    val volume: StateFlow<Double> = _volume.asStateFlow()

    private val _playbackRate = MutableStateFlow(1.0)
    val playbackRate: StateFlow<Double> = _playbackRate.asStateFlow()

    private val _videoDisplayWidth = MutableStateFlow(0)
    val videoDisplayWidth: StateFlow<Int> = _videoDisplayWidth.asStateFlow()

    private val _videoDisplayHeight = MutableStateFlow(0)
    val videoDisplayHeight: StateFlow<Int> = _videoDisplayHeight.asStateFlow()

    private val _mediaTitle = MutableStateFlow("")
    val mediaTitle: StateFlow<String> = _mediaTitle.asStateFlow()

    private val _bufferTimelineEnd = MutableStateFlow(0.0)
    val bufferTimelineEnd: StateFlow<Double> = _bufferTimelineEnd.asStateFlow()

    private val _playbackFailureMessage = MutableStateFlow<String?>(null)
    val playbackFailureMessage: StateFlow<String?> = _playbackFailureMessage.asStateFlow()

    /**
     * Rolling window of the most recent mpv log lines (warn/error/fatal). UI
     * surfaces these in the failure overlay so we can diagnose bring-up issues
     * without `adb logcat` — the JNI bridge already mirrors everything to
     * logcat, but a phone-only debug view shortens the feedback loop.
     */
    private val _recentMpvLogs = MutableStateFlow<List<String>>(emptyList())
    val recentMpvLogs: StateFlow<List<String>> = _recentMpvLogs.asStateFlow()

    /** Mirrors iOS `isPlaybackEstablished`: true after FILE_LOADED / PLAYBACK_RESTART. */
    private val _isPlaybackEstablished = MutableStateFlow(false)
    val isPlaybackEstablished: StateFlow<Boolean> = _isPlaybackEstablished.asStateFlow()

    // ---------------------------------------------------------------------
    // Track lists (video / audio / subtitle). Mirrors iOS
    // `VideoPlayerController.videoTracks` etc. — UI-facing menu options that
    // already include language + codec detail labels so views don't need to
    // re-format them.
    // ---------------------------------------------------------------------

    private val _videoTracks = MutableStateFlow<List<TrackInfo>>(emptyList())
    val videoTracks: StateFlow<List<TrackInfo>> = _videoTracks.asStateFlow()

    private val _audioTracks = MutableStateFlow<List<TrackInfo>>(emptyList())
    val audioTracks: StateFlow<List<TrackInfo>> = _audioTracks.asStateFlow()

    /** First element has id -1 ("Kapalı"), like iOS. */
    private val _subtitleTracks = MutableStateFlow<List<TrackInfo>>(emptyList())
    val subtitleTracks: StateFlow<List<TrackInfo>> = _subtitleTracks.asStateFlow()

    private val _currentVideoTrackId = MutableStateFlow(-1)
    val currentVideoTrackId: StateFlow<Int> = _currentVideoTrackId.asStateFlow()
    private val _currentAudioTrackId = MutableStateFlow(-1)
    val currentAudioTrackId: StateFlow<Int> = _currentAudioTrackId.asStateFlow()
    private val _currentSubtitleTrackId = MutableStateFlow(-1)
    val currentSubtitleTrackId: StateFlow<Int> = _currentSubtitleTrackId.asStateFlow()

    /** UI-facing menu row. iOS counterpart: `TrackMenuOption`. */
    data class TrackInfo(
        val id: Int,
        val title: String,
        val detail: String? = null,
        val langCode: String? = null,
    )

    // ---------------------------------------------------------------------
    // Internals.
    // ---------------------------------------------------------------------

    private val handle: Long
    private val isDisposed = AtomicBoolean(false)
    /** Serializes all mpv API calls; same role as iOS `mpvQueue`. */
    private val mpvQueue: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "MPVPlayer.mpv").apply { isDaemon = true }
        }
    /** Set true after FILE_LOADED / PLAYBACK_RESTART; gates pipeline-readiness publishing. */
    @Volatile private var playbackPipelinePrimed = false
    /** Cancellable watchdog matching iOS `loadTimeoutWorkItem`. */
    private var loadTimeoutFuture: ScheduledFuture<*>? = null
    /** Throttle for `time-pos` updates (matches iOS 0.12s). */
    @Volatile private var lastPositionPublishNanos: Long = 0
    /** True once a Surface is attached via [attachSurface]. */
    @Volatile private var hasSurface = false
    /**
     * `loadfile` request received before the SurfaceView was ready. With
     * `gpu-context=android`, mpv's VO needs a `wid` before it can serve
     * frames; firing loadfile without one trips a `vo init failed` END_FILE
     * and we surface "cannot reach server" even though the network is fine.
     * iOS doesn't hit this race because `vo=libmpv` is FBO-based and lazy.
     */
    private var pendingLoad: PendingLoad? = null

    private data class PendingLoad(
        val url: String,
        val play: Boolean,
        val startSeconds: Double?,
        val liveLowLatency: Boolean,
    )

    // Declared before `init` so `MPVLib.setEventListener(handle, eventListener)`
    // below sees a fully-constructed object. The listener has no construction
    // dependencies on the rest of the class — it only reaches back through
    // method calls fired by the JNI drain thread.
    private val eventListener = object : MPVLib.EventListener {
        override fun onPropertyChange(replyUserdata: Long) {
            when (replyUserdata) {
                PROP_TIME_POS -> publishPositionThrottled()
                PROP_VIDEO_PARAMS, PROP_VIDEO_OUT_PARAMS -> publishVideoSize()
                else -> publishPlaybackState()
            }
        }

        override fun onLogMessage(level: String?, prefix: String?, text: String?) {
            handleLogMessage(level ?: return, prefix ?: "", text ?: "")
        }

        override fun onEndFile(reason: Int, error: Int) {
            cancelLoadTimeoutWatchdog()
            playbackPipelinePrimed = false
            _isPlaybackEstablished.value = false
            if (reason == MPVLib.EndFileReason.ERROR) {
                publishEndFileFailureMessage(error)
            }
        }

        override fun onEvent(eventId: Int) {
            when (eventId) {
                MPVLib.Event.START_FILE -> {
                    playbackPipelinePrimed = false
                    _isPlaybackEstablished.value = false
                    clearPlaybackFailure()
                }
                MPVLib.Event.FILE_LOADED,
                MPVLib.Event.PLAYBACK_RESTART -> {
                    playbackPipelinePrimed = true
                    cancelLoadTimeoutWatchdog()
                    // Loading-phase ffmpeg/http warnings sometimes fire after the pipeline
                    // is already serving frames; reset to avoid a sticky overlay.
                    clearPlaybackFailure()
                    _isPlaybackEstablished.value = true
                    _isReady.value = true
                    publishPlaybackState()
                    reloadTrackList()
                }
                MPVLib.Event.VIDEO_RECONFIG -> publishVideoSize()
                MPVLib.Event.AUDIO_RECONFIG -> reloadTrackList()
            }
        }
    }

    init {
        handle = MPVLib.create()
        require(handle != 0L) { "mpv_create failed" }

        // Options that must be set BEFORE mpv_initialize (vo selection, GPU
        // context, hwdec). Setting them after init either is a no-op or
        // forces an expensive re-init of the VO machinery.
        //
        // VO fallback chain: mpv accepts a comma-separated list and walks it
        // until something inits. On real devices `vo=gpu` (GL + mediacodec-copy
        // decode) is the most flexible — handles every codec libavcodec can
        // demux. If GL init fails (e.g. Android Studio emulator's gfxstream
        // returns EGL_BAD_ATTRIBUTE for mpv's context attribs), mpv falls
        // through to `vo=mediacodec_embed` which decodes via HW MediaCodec
        // straight onto our SurfaceView.
        //
        // Caveat: the emulator's `c2.goldfish.h264.decoder` is independently
        // broken — it allocates output buffers but never marks them as used.
        // So even with this fallback, video typically won't render in the
        // Android Studio emulator; testing playback needs a real device.
        // Single matched HW pair: MediaCodec decodes straight onto the
        // SurfaceView's Surface, no GL involvement.
        //
        // We tried a `vo=gpu,mediacodec_embed` fallback chain first, but the
        // two VOs need *different* hwdec modes — `gpu` wants `mediacodec-copy`
        // (decoded YUV pushed to GL), while `mediacodec_embed` only renders
        // when the decoder outputs directly to its surface (`hwdec=mediacodec`,
        // no copy). The single global `hwdec` setting can't satisfy both, so
        // when fallback kicked in on real devices audio + metadata played but
        // video never appeared (`Both surface and native_window are NULL` from
        // the ffmpeg mediacodec path).
        //
        // Sticking to the matched pair keeps the codec → surface → screen
        // path unambiguous. Tradeoff: codecs the device's MediaCodec doesn't
        // support (rare for IPTV: typically h264/hevc/vp9/av1) will fail
        // outright instead of falling back to a CPU/GL render path.
        MPVLib.setOptionString(handle, "vo", "mediacodec_embed")
        MPVLib.setOptionString(handle, "hwdec", "mediacodec")
        // Don't pin the AO — let mpv pick `aaudio` on API 26+, falling back to
        // `opensles` on older devices; hard-pinning `audiotrack` errors out on
        // builds where that AO wasn't compiled in.
        MPVLib.setOptionString(handle, "idle", "yes")
        // `force-window=no` keeps mpv from spinning up a window before a file
        // is loaded — important when our Surface hasn't been attached yet.
        MPVLib.setOptionString(handle, "force-window", "no")

        val initRc = MPVLib.initialize(handle)
        check(initRc >= 0) { "mpv_initialize failed: rc=$initRc (${MPVLib.errorString(initRc)})" }

        applyDefaultProperties()
        registerPropertyObservers()
        // `info` instead of iOS `warn`: mpv on Android sometimes only logs the
        // real root cause (mediacodec init, surface ready, demuxer probe) at
        // info — the warn output alone makes "Sunucuya ulaşılamıyor" failures
        // unactionable. Cheap; events fire on the drain thread anyway.
        MPVLib.requestLogMessages(handle, "info")
        MPVLib.setEventListener(handle, eventListener)
    }

    // ---------------------------------------------------------------------
    // Public API — every entry point either bounces onto `mpvQueue` or
    // touches only thread-safe state (`StateFlow`).
    // ---------------------------------------------------------------------

    fun attachSurface(surface: Surface) = onMpvQueue {
        val rc = MPVLib.attachSurface(handle, surface)
        if (rc < 0) {
            Log.w(TAG, "attachSurface rc=$rc (${MPVLib.errorString(rc)})")
            return@onMpvQueue
        }
        hasSurface = true
        Log.i(TAG, "Surface attached; flushing any pending load (pending=${pendingLoad != null})")
        pendingLoad?.let { req ->
            pendingLoad = null
            applyLoadNow(req)
        }
    }

    fun detachSurface() = onMpvQueue {
        hasSurface = false
        val rc = MPVLib.detachSurface(handle)
        if (rc < 0) Log.w(TAG, "detachSurface rc=$rc (${MPVLib.errorString(rc)})")
    }

    /**
     * Mirror of iOS `load(_:play:startSeconds:liveLowLatency:)`.
     *
     * @param url stream URL (HLS / TS / MP4 / …).
     * @param play if true, immediately unpause once loaded.
     * @param startSeconds resume position; passed as `start=` arg to `loadfile`.
     * @param liveLowLatency tighten buffers for live IPTV (matches iOS).
     */
    fun load(
        url: String,
        play: Boolean = true,
        startSeconds: Double? = null,
        liveLowLatency: Boolean = false,
    ) = onMpvQueue {
        val req = PendingLoad(url, play, startSeconds, liveLowLatency)
        if (!hasSurface) {
            // Defer: mpv will be told to loadfile the moment the SurfaceView
            // hands us its Surface. Without this guard `gpu-context=android`
            // fails VO init and we surface "cannot reach server" instead of
            // the real "no surface yet".
            Log.i(TAG, "load() before surface ready — deferring url=$url")
            pendingLoad = req
            return@onMpvQueue
        }
        applyLoadNow(req)
    }

    private fun applyLoadNow(req: PendingLoad) {
        clearPlaybackFailure()
        cancelLoadTimeoutWatchdog()
        playbackPipelinePrimed = false
        _isPlaybackEstablished.value = false

        applyStreamBufferPolicy(req.liveLowLatency)

        val args = buildList {
            add("loadfile")
            add(req.url)
            add("replace")
            if (req.startSeconds != null && req.startSeconds.isFinite() && req.startSeconds > 0) {
                add("start=${req.startSeconds}")
            }
        }.toTypedArray()
        Log.i(TAG, "loadfile args=${args.toList()}")
        val rc = MPVLib.command(handle, args)
        if (rc < 0) Log.w(TAG, "loadfile rc=$rc (${MPVLib.errorString(rc)}) args=${args.toList()}")

        if (req.play) setPaused(false)
        publishPlaybackState()
        scheduleLoadTimeoutWatchdog()
    }

    fun play() = onMpvQueue {
        val eof = MPVLib.getPropertyBoolean(handle, "eof-reached") ?: false
        if (eof) MPVLib.commandString(handle, "seek 0 absolute")
        setPaused(false)
    }

    fun pause() = onMpvQueue { setPaused(true) }

    /** Absolute seek in seconds (matches iOS `seek(to:)`). */
    fun seek(seconds: Double) = onMpvQueue {
        MPVLib.commandString(handle, "seek $seconds absolute")
    }

    /** Relative jump (e.g. ±10s overlay buttons). */
    fun jumpRelative(seconds: Int) = onMpvQueue {
        MPVLib.commandString(handle, "seek $seconds relative")
    }

    /** Fractional seek (0..1); convenience for scrubbing UIs. */
    fun seekToFraction(fraction: Float) = onMpvQueue {
        val dur = MPVLib.getPropertyDouble(handle, "duration") ?: 0.0
        if (dur <= 0.0 || !fraction.isFinite()) return@onMpvQueue
        val target = fraction.coerceIn(0f, 1f).toDouble() * dur
        MPVLib.commandString(handle, "seek $target absolute")
    }

    fun setVolume(value: Double) = onMpvQueue {
        MPVLib.setPropertyDouble(handle, "volume", value)
    }

    fun setPlaybackRate(value: Double) = onMpvQueue {
        MPVLib.setPropertyDouble(handle, "speed", value)
    }

    /**
     * Mirrors iOS `selectVideoTrack(id:)`. Pass `-1` to disable a stream.
     * Track ids are taken from [videoTracks] / [audioTracks] / [subtitleTracks].
     */
    fun selectVideoTrack(id: Int) = onMpvQueue {
        MPVLib.setPropertyLong(handle, "vid", id.toLong())
        _currentVideoTrackId.value = id
    }

    fun selectAudioTrack(id: Int) = onMpvQueue {
        MPVLib.setPropertyLong(handle, "aid", id.toLong())
        _currentAudioTrackId.value = id
    }

    /** Pass `-1` to disable subtitles entirely. */
    fun selectSubtitleTrack(id: Int) = onMpvQueue {
        MPVLib.setPropertyLong(handle, "sid", id.toLong())
        _currentSubtitleTrackId.value = id
    }

    /** Positive = subtitle plays later, negative = earlier. Range ±10s mirrors iOS. */
    fun setSubtitleDelay(seconds: Double) = onMpvQueue {
        MPVLib.setPropertyDouble(handle, "sub-delay", seconds)
    }

    /**
     * Internal-ish: surface the raw `sub-*` write so [applySubtitleAppearance]
     * (in `SubtitleAppearance.kt`) can apply the cosmetic settings without
     * pulling MPVLib into a public dependency.
     */
    fun setSubtitleProperty(name: String, value: String) = onMpvQueue {
        MPVLib.setPropertyString(handle, name, value)
    }

    /**
     * Refresh the cached track list from mpv. Called automatically after
     * FILE_LOADED + AUDIO_RECONFIG; public so a UI action ("Reload tracks")
     * can trigger it manually.
     */
    fun reloadTrackList() = onMpvQueue {
        val countLong = MPVLib.getPropertyLong(handle, "track-list/count") ?: 0L
        val count = countLong.toInt().coerceAtLeast(0)
        val videos = ArrayList<TrackInfo>(count)
        val audios = ArrayList<TrackInfo>(count)
        val subs = ArrayList<TrackInfo>(count + 1).apply {
            add(TrackInfo(id = -1, title = appContext.getString(R.string.track_off)))
        }
        for (i in 0 until count) {
            val type = MPVLib.getPropertyString(handle, "track-list/$i/type") ?: continue
            val id = MPVLib.getPropertyLong(handle, "track-list/$i/id")?.toInt() ?: continue
            val title = MPVLib.getPropertyString(handle, "track-list/$i/title")
            val lang = MPVLib.getPropertyString(handle, "track-list/$i/lang")
            val codec = MPVLib.getPropertyString(handle, "track-list/$i/codec")
            val displayTitle = listOfNotNull(
                title?.takeIf { it.isNotBlank() },
                lang?.takeIf { it.isNotBlank() },
            ).joinToString(" — ").ifBlank { appContext.getString(R.string.track_index, id) }
            val detail = listOfNotNull(
                lang?.takeIf { it.isNotBlank() },
                codec?.takeIf { it.isNotBlank() },
            ).joinToString(" · ").ifBlank { null }
            val info = TrackInfo(id = id, title = displayTitle, detail = detail, langCode = lang)
            when (type) {
                "video" -> videos += info
                "audio" -> audios += info
                "sub" -> subs += info
            }
        }
        _videoTracks.value = videos
        _audioTracks.value = audios
        _subtitleTracks.value = subs
        _currentVideoTrackId.value = MPVLib.getPropertyLong(handle, "vid")?.toInt() ?: -1
        _currentAudioTrackId.value = MPVLib.getPropertyLong(handle, "aid")?.toInt() ?: -1
        _currentSubtitleTrackId.value = MPVLib.getPropertyLong(handle, "sid")?.toInt() ?: -1
    }

    /**
     * Tears down the mpv handle, joins the JNI drain thread, releases any
     * attached `ANativeWindow`. Safe to call multiple times; subsequent calls
     * are no-ops. Always call from a viewmodel's `onCleared` or similar.
     */
    fun dispose() {
        if (!isDisposed.compareAndSet(false, true)) return
        cancelLoadTimeoutWatchdog()
        // Hand-off to the mpv queue so any in-flight `loadfile`/`seek` queued
        // by the UI completes before we destroy the handle; iOS does the same.
        mpvQueue.execute {
            try {
                MPVLib.setEventListener(handle, null)
                MPVLib.terminateDestroy(handle)
            } catch (t: Throwable) {
                Log.w(TAG, "dispose failed", t)
            }
        }
        mpvQueue.shutdown()
        // 1s is enough for a clean tear-down; longer means JNI is wedged
        // and we don't want to block the UI thread waiting.
        mpvQueue.awaitTermination(1, TimeUnit.SECONDS)

        // Reset published state on the UI's thread (StateFlow already handles
        // cross-thread emission).
        _isReady.value = false
        _isPaused.value = true
        _position.value = 0.0
        _duration.value = 0.0
        _isBuffering.value = false
        _isCompleted.value = false
        _videoDisplayWidth.value = 0
        _videoDisplayHeight.value = 0
        _mediaTitle.value = ""
        _bufferTimelineEnd.value = 0.0
        _playbackFailureMessage.value = null
        _isPlaybackEstablished.value = false
        _videoTracks.value = emptyList()
        _audioTracks.value = emptyList()
        _subtitleTracks.value = emptyList()
        _currentVideoTrackId.value = -1
        _currentAudioTrackId.value = -1
        _currentSubtitleTrackId.value = -1
    }

    // ---------------------------------------------------------------------
    // Default profile — port of iOS `applyDefaultProperties`.
    //
    // Two divergences from iOS:
    //   * `hwdec=mediacodec` instead of `videotoolbox` (set as an option pre-init).
    //   * No `tone-mapping` / `hdr-compute-peak`; Android mediacodec path
    //     gives us a yuv420p surface, peak detection is irrelevant there.
    // ---------------------------------------------------------------------

    private fun applyDefaultProperties() {
        val props = arrayOf(
            "pause" to "yes",
            "keep-open" to "yes",
            "audio-display" to "no",
            // Log + END_FILE friendly timeout (matches iOS).
            "network-timeout" to "14",
            // Cheap bilinear: invisible on phone DPI, ~2× cheaper than spline36.
            "scale" to "bilinear",
            "dscale" to "bilinear",
            "cache" to "yes",
            "cache-on-disk" to "yes",
            "hr-seek" to "default",
            "hr-seek-framedrop" to "yes",
            "vid" to "auto",
            "video-sync" to "audio",
            "interpolation" to "no",
            "video-timing-offset" to "0",
            "osd-level" to "0",
            "demuxer-max-bytes" to "${32 * 1024 * 1024}",
            "demuxer-max-back-bytes" to "${32 * 1024 * 1024}",
        )
        for ((k, v) in props) {
            val rc = MPVLib.setPropertyString(handle, k, v)
            if (rc < 0) Log.v(TAG, "skip $k=$v rc=$rc")
        }
    }

    /** Mirror of iOS `applyStreamBufferPolicy`; tighter buffers for live IPTV. */
    private fun applyStreamBufferPolicy(liveLowLatency: Boolean) {
        if (liveLowLatency) {
            MPVLib.setPropertyString(handle, "cache", "yes")
            MPVLib.setPropertyString(handle, "cache-on-disk", "no")
            MPVLib.setPropertyString(handle, "cache-secs", "5")
            MPVLib.setPropertyString(handle, "demuxer-readahead-secs", "2")
            MPVLib.setPropertyString(handle, "demuxer-max-bytes", "${4 * 1024 * 1024}")
            MPVLib.setPropertyString(handle, "demuxer-max-back-bytes", "${512 * 1024}")
        } else {
            MPVLib.setPropertyString(handle, "cache", "yes")
            MPVLib.setPropertyString(handle, "cache-on-disk", "yes")
            MPVLib.setPropertyString(handle, "cache-secs", "300")
            MPVLib.setPropertyString(handle, "demuxer-readahead-secs", "10")
            MPVLib.setPropertyString(handle, "demuxer-max-bytes", "${32 * 1024 * 1024}")
            MPVLib.setPropertyString(handle, "demuxer-max-back-bytes", "${32 * 1024 * 1024}")
        }
    }

    // ---------------------------------------------------------------------
    // Property observers — reply IDs are dense + stable so the listener can
    // switch on them without an extra name lookup.
    // ---------------------------------------------------------------------

    private fun registerPropertyObservers() {
        val observations = listOf(
            PROP_TIME_POS         to ("time-pos" to MPVLib.Format.DOUBLE),
            PROP_DURATION         to ("duration" to MPVLib.Format.DOUBLE),
            PROP_PAUSE            to ("pause" to MPVLib.Format.FLAG),
            PROP_EOF_REACHED      to ("eof-reached" to MPVLib.Format.FLAG),
            PROP_PAUSED_FOR_CACHE to ("paused-for-cache" to MPVLib.Format.FLAG),
            PROP_VOLUME           to ("volume" to MPVLib.Format.DOUBLE),
            PROP_SPEED            to ("speed" to MPVLib.Format.DOUBLE),
            PROP_MEDIA_TITLE      to ("media-title" to MPVLib.Format.STRING),
            PROP_VIDEO_PARAMS     to ("video-params" to MPVLib.Format.NODE),
            PROP_VIDEO_OUT_PARAMS to ("video-out-params" to MPVLib.Format.NODE),
            PROP_SEEKABLE         to ("seekable" to MPVLib.Format.FLAG),
            PROP_DEMUX_CACHE_TIME to ("demuxer-cache-time" to MPVLib.Format.DOUBLE),
        )
        for ((id, np) in observations) {
            val (name, fmt) = np
            val rc = MPVLib.observeProperty(handle, id, name, fmt)
            if (rc < 0) Log.v(TAG, "observe $name rc=$rc")
        }
    }

    // ---------------------------------------------------------------------
    // Event drain handlers (run on the JNI daemon thread).
    // ---------------------------------------------------------------------

    private fun publishPositionThrottled() {
        val now = System.nanoTime()
        // 120ms throttle; same constant as iOS `publishPositionThrottled`.
        if (now - lastPositionPublishNanos < 120_000_000L) return
        lastPositionPublishNanos = now
        val pos = MPVLib.getPropertyDouble(handle, "time-pos") ?: 0.0
        val cacheEnd = MPVLib.getPropertyDouble(handle, "demuxer-cache-time") ?: 0.0
        if (_position.value != pos) _position.value = pos
        if (_bufferTimelineEnd.value != cacheEnd) _bufferTimelineEnd.value = cacheEnd
    }

    private fun publishVideoSize() {
        // video-out-params is the final post-VF size (what we should size the
        // SurfaceView to); video-params is the demuxer-reported size and is
        // only useful when video-out-params isn't ready yet (e.g. pre-VO init).
        val dw = MPVLib.getPropertyLong(handle, "video-out-params/dw")
            ?: MPVLib.getPropertyLong(handle, "video-params/dw")
            ?: 0L
        val dh = MPVLib.getPropertyLong(handle, "video-out-params/dh")
            ?: MPVLib.getPropertyLong(handle, "video-params/dh")
            ?: 0L
        if (_videoDisplayWidth.value != dw.toInt()) _videoDisplayWidth.value = dw.toInt()
        if (_videoDisplayHeight.value != dh.toInt()) _videoDisplayHeight.value = dh.toInt()
    }

    private fun publishPlaybackState() {
        val pos = MPVLib.getPropertyDouble(handle, "time-pos") ?: 0.0
        val dur = MPVLib.getPropertyDouble(handle, "duration") ?: 0.0
        val paused = MPVLib.getPropertyBoolean(handle, "pause") ?: true
        val eof = MPVLib.getPropertyBoolean(handle, "eof-reached") ?: false
        val buffering = MPVLib.getPropertyBoolean(handle, "paused-for-cache") ?: false
        val vol = MPVLib.getPropertyDouble(handle, "volume") ?: 100.0
        val spd = MPVLib.getPropertyDouble(handle, "speed") ?: 1.0
        val title = MPVLib.getPropertyString(handle, "media-title") ?: ""
        val seekable = MPVLib.getPropertyBoolean(handle, "seekable") ?: false
        val cacheEnd = MPVLib.getPropertyDouble(handle, "demuxer-cache-time") ?: 0.0

        if (_position.value != pos) _position.value = pos
        if (_duration.value != dur) _duration.value = dur
        if (_isPaused.value != paused) _isPaused.value = paused
        if (_isCompleted.value != eof) _isCompleted.value = eof
        if (_isBuffering.value != buffering) _isBuffering.value = buffering
        if (_volume.value != vol) _volume.value = vol
        if (_playbackRate.value != spd) _playbackRate.value = spd
        if (_mediaTitle.value != title) _mediaTitle.value = title
        if (_isSeekable.value != seekable) _isSeekable.value = seekable
        if (_bufferTimelineEnd.value != cacheEnd) _bufferTimelineEnd.value = cacheEnd
        publishVideoSize()
    }

    // ---------------------------------------------------------------------
    // Log → failure classification (mirror of iOS `handleMpvLogMessage`).
    // ---------------------------------------------------------------------

    private fun handleLogMessage(level: String, prefix: String, text: String) {
        // Forward every mpv line to logcat (trimmed) so a `adb logcat -s mpv:*`
        // session shows the demuxer / VO / mediacodec story end-to-end. Worth
        // the verbosity during the IPTV bring-up; tighten back to "warn" once
        // the player is stable across providers.
        val line = text.trimEnd('\n')
        when (level) {
            "fatal", "error" -> Log.e("mpv", "$prefix: $line")
            "warn"           -> Log.w("mpv", "$prefix: $line")
            "info", "status" -> Log.i("mpv", "$prefix: $line")
            else             -> Log.d("mpv", "[$level] $prefix: $line")
        }

        // Keep the on-device rolling buffer focused on signal — drop status/v/
        // trace noise so the failure overlay can show the lines that actually
        // explain the failure (warn/error/fatal).
        if (level == "warn" || level == "error" || level == "fatal") {
            val tagged = "[$level] $prefix: $line"
            val current = _recentMpvLogs.value
            val next = (current + tagged).takeLast(RECENT_LOG_MAX)
            _recentMpvLogs.value = next
        }

        if (playbackPipelinePrimed) return
        if (!shouldSurfaceLogAsPlaybackFailure(level, prefix, text)) return

        cancelLoadTimeoutWatchdog()
        val msg = userFacingMessageFromLogLine(level, text)
        if (_playbackFailureMessage.value == null) {
            _playbackFailureMessage.value = msg
        }
        Log.i(TAG, "surfaced failure: [$level] $prefix: $text → $msg")
    }

    private fun shouldSurfaceLogAsPlaybackFailure(
        level: String, prefix: String, text: String,
    ): Boolean {
        val p = prefix.lowercase()
        val combined = (p + " " + text).lowercase()

        // VO/AO chatter during init is noisy + not user-actionable.
        if (p == "vo" || p == "ao" || p.startsWith("vo/") || p.startsWith("ao/")) return false

        val openPrefixes = listOf(
            "ffmpeg", "lavf", "demuxer", "demux", "stream", "http", "https", "network",
            "libavformat", "read_file", "ffmpeg/http", "ffmpeg/tcp", "ffmpeg/tls",
        )
        val openHints = listOf(
            "connection refused", "connection timed out", "connection reset", "timed out",
            "network is unreachable", "no route to host", "could not connect",
            "failed to connect", "http error", "server returned", "http status",
            "http response", "403 forbidden", "404 not found", "401 unauthorized",
            "500 internal", "502 bad gateway", "503 service", "tls:", "ssl error",
            "certificate", "resolve host", "name or service not known",
            "failed to open", "error opening", "invalid data found",
            "i/o error", "input/output error", "operation timed out",
            "host is down", "broken pipe", "errno",
        )
        val warnOnlyHints = listOf(
            "connection refused", "connection timed out", "connection reset", "timed out",
            "network is unreachable", "no route to host", "could not connect",
            "failed to connect", "http error", "server returned", "http status",
            "http response", "403 forbidden", "404 not found", "401 unauthorized",
            "500 internal", "502 bad gateway", "503 service", "tls:", "ssl error",
            "certificate", "resolve host", "name or service not known",
            "operation timed out", "host is down", "broken pipe",
        )

        return when (level) {
            "fatal" -> true
            "error" -> openPrefixes.any { p.contains(it) } || openHints.any { combined.contains(it) }
            "warn"  -> warnOnlyHints.any { combined.contains(it) }
            else    -> false
        }
    }

    private fun userFacingMessageFromLogLine(level: String, text: String): String {
        val t = text.lowercase()
        val res = when {
            t.contains("403") || t.contains("forbidden") -> R.string.mpv_error_forbidden
            t.contains("401") || t.contains("unauthorized") -> R.string.mpv_error_unauthorized
            t.contains("404") || t.contains("not found") -> R.string.mpv_error_not_found
            t.contains("timed out") || t.contains("timeout") -> R.string.error_timeout
            level == "fatal" -> R.string.mpv_error_playback_init
            else -> R.string.error_server_unreachable
        }
        return appContext.getString(res)
    }

    private fun publishEndFileFailureMessage(mpvError: Int) {
        val res = when (mpvError) {
            MPVLib.Error.LOADING_FAILED,
            MPVLib.Error.UNKNOWN_FORMAT,
            MPVLib.Error.GENERIC -> R.string.error_server_unreachable
            MPVLib.Error.UNSUPPORTED -> R.string.mpv_error_unsupported
            MPVLib.Error.NOTHING_TO_PLAY -> R.string.mpv_error_nothing_to_play
            MPVLib.Error.AO_INIT_FAILED,
            MPVLib.Error.VO_INIT_FAILED -> R.string.mpv_error_av_init
            else -> R.string.mpv_error_check_network
        }
        val message = appContext.getString(res)
        // Keep specific mpv-level errors visible even if a vague log already
        // populated the message; matches iOS `specificMpvCodes` carve-out.
        val specific = mpvError in setOf(
            MPVLib.Error.NOTHING_TO_PLAY,
            MPVLib.Error.UNKNOWN_FORMAT,
            MPVLib.Error.UNSUPPORTED,
            MPVLib.Error.AO_INIT_FAILED,
            MPVLib.Error.VO_INIT_FAILED,
        )
        if (_playbackFailureMessage.value == null || specific) {
            _playbackFailureMessage.value = message
        }
    }

    private fun clearPlaybackFailure() {
        _playbackFailureMessage.value = null
    }

    // ---------------------------------------------------------------------
    // Load timeout watchdog (mirror of iOS `scheduleLoadTimeoutWatchdog`).
    // ---------------------------------------------------------------------

    private fun cancelLoadTimeoutWatchdog() {
        loadTimeoutFuture?.cancel(false)
        loadTimeoutFuture = null
    }

    private fun scheduleLoadTimeoutWatchdog() {
        cancelLoadTimeoutWatchdog()
        loadTimeoutFuture = mpvQueue.schedule({
            if (isDisposed.get() || playbackPipelinePrimed) return@schedule
            if (_playbackFailureMessage.value == null) {
                _playbackFailureMessage.value = appContext.getString(R.string.error_timeout)
            }
        }, 16, TimeUnit.SECONDS)
    }

    // ---------------------------------------------------------------------
    // Helpers.
    // ---------------------------------------------------------------------

    private fun setPaused(paused: Boolean) {
        val rc = MPVLib.setPropertyBoolean(handle, "pause", paused)
        if (rc < 0) Log.w(TAG, "set pause=$paused rc=$rc")
        _isPaused.value = paused
    }

    /** Runs `block` on `mpvQueue`. Silently drops calls after `dispose`. */
    private inline fun onMpvQueue(crossinline block: () -> Unit) {
        if (isDisposed.get()) return
        mpvQueue.execute {
            if (isDisposed.get()) return@execute
            try { block() } catch (t: Throwable) { Log.e(TAG, "mpvQueue", t) }
        }
    }

    companion object {
        private const val TAG = "MPVPlayer"
        private const val RECENT_LOG_MAX = 80

        // Property observation reply IDs — keep contiguous to make the
        // listener `when` switch a jump table.
        private const val PROP_TIME_POS = 1L
        private const val PROP_DURATION = 2L
        private const val PROP_PAUSE = 3L
        private const val PROP_EOF_REACHED = 4L
        private const val PROP_PAUSED_FOR_CACHE = 5L
        private const val PROP_VOLUME = 6L
        private const val PROP_SPEED = 7L
        private const val PROP_MEDIA_TITLE = 8L
        private const val PROP_VIDEO_PARAMS = 9L
        private const val PROP_VIDEO_OUT_PARAMS = 10L
        private const val PROP_SEEKABLE = 11L
        private const val PROP_DEMUX_CACHE_TIME = 12L
    }
}
