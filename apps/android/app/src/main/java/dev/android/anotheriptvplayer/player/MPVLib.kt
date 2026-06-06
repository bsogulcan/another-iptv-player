package dev.android.anotheriptvplayer.player

import android.view.Surface

/**
 * Thin Kotlin facade over the JNI bridge in `cpp/mpv_jni.cpp`.
 *
 * Mirrors the iOS Swift surface that talks directly to libmpv via the
 * bridging header (`ios/another-iptv-player/another-iptv-player-Bridging-Header.h`).
 * Higher-level state, threading, and lifecycle live in [MPVPlayer] — this
 * object is intentionally a 1:1 mapping of `client.h` so callers always know
 * exactly which mpv API they're invoking.
 *
 * Handles are opaque [Long]s minted by JNI; never dereference them on the
 * Kotlin side.
 *
 * Loaded in static-init order:
 *   1. `libmpv.so` (media-kit prebuilt, staged into `jniLibs/` by the Vendor
 *      Makefile)
 *   2. `libmediakitandroidhelper.so` (small helper bundled alongside libmpv)
 *   3. `libanotheriptv_mpv_jni.so` (our CMake target — links against libmpv)
 *
 * The order matters: the JNI bridge dlopens libmpv symbols at load time, so
 * its `.so` must come last.
 */
object MPVLib {

    init {
        System.loadLibrary("mpv")
        System.loadLibrary("mediakitandroidhelper")
        System.loadLibrary("anotheriptv_mpv_jni")
    }

    // ---------------------------------------------------------------------
    // Constants — mirror `client.h` enums.
    // ---------------------------------------------------------------------

    object Format {
        const val NONE = 0
        const val STRING = 1
        const val OSD_STRING = 2
        const val FLAG = 3
        const val INT64 = 4
        const val DOUBLE = 5
        const val NODE = 6
        const val NODE_ARRAY = 7
        const val NODE_MAP = 8
        const val BYTE_ARRAY = 9
    }

    object Event {
        const val NONE = 0
        const val SHUTDOWN = 1
        const val LOG_MESSAGE = 2
        const val GET_PROPERTY_REPLY = 3
        const val SET_PROPERTY_REPLY = 4
        const val COMMAND_REPLY = 5
        const val START_FILE = 6
        const val END_FILE = 7
        const val FILE_LOADED = 8
        const val IDLE = 11
        const val TICK = 14
        const val CLIENT_MESSAGE = 16
        const val VIDEO_RECONFIG = 17
        const val AUDIO_RECONFIG = 18
        const val SEEK = 20
        const val PLAYBACK_RESTART = 21
        const val PROPERTY_CHANGE = 22
        const val QUEUE_OVERFLOW = 24
        const val HOOK = 25
    }

    object EndFileReason {
        const val EOF = 0
        const val STOP = 2
        const val QUIT = 3
        const val ERROR = 4
        const val REDIRECT = 5
    }

    // Subset of `mpv_error` used for `END_FILE` error classification; full set
    // is in `client.h`. We classify in [MPVPlayer.userFacingPlaybackFailureMessage].
    object Error {
        const val SUCCESS = 0
        const val LOADING_FAILED = -13
        const val AO_INIT_FAILED = -14
        const val VO_INIT_FAILED = -15
        const val NOTHING_TO_PLAY = -16
        const val UNKNOWN_FORMAT = -17
        const val UNSUPPORTED = -18
        const val NOT_IMPLEMENTED = -19
        const val GENERIC = -20
    }

    // ---------------------------------------------------------------------
    // Listener — invoked from the C++ drain thread (attached as daemon).
    //
    // Implementations MUST be cheap and thread-safe; do not hold locks that
    // any UI thread or `mpv_*` caller might also be waiting on, or you'll
    // deadlock the event drain.
    // ---------------------------------------------------------------------

    interface EventListener {
        /** mpv_event.event_id == PROPERTY_CHANGE; arg is `reply_userdata`. */
        fun onPropertyChange(replyUserdata: Long)
        /** Per-line log emission from `mpv_request_log_messages`. */
        fun onLogMessage(level: String?, prefix: String?, text: String?)
        /** mpv_event.event_id == END_FILE; reason/error from `mpv_event_end_file`. */
        fun onEndFile(reason: Int, error: Int)
        /** Catch-all: start_file, file_loaded, playback_restart, shutdown, etc. */
        fun onEvent(eventId: Int)
    }

    // ---------------------------------------------------------------------
    // Handle lifecycle.
    // ---------------------------------------------------------------------

    /** `mpv_create`; returns an opaque handle (0 on failure). */
    fun create(): Long = nativeCreate()

    /** `mpv_initialize`; returns 0 on success, negative `mpv_error` on failure. */
    fun initialize(handle: Long): Int = nativeInitialize(handle)

    /** `mpv_terminate_destroy`; safe to call from any thread, joins drain thread. */
    fun terminateDestroy(handle: Long) = nativeTerminateDestroy(handle)

    /** `mpv_error_string` — human-readable error name (e.g. "loading failed"). */
    fun errorString(code: Int): String = nativeErrorString(code)

    /** Pass `null` to clear. Holds a global ref until cleared or handle destroyed. */
    fun setEventListener(handle: Long, listener: EventListener?) =
        nativeSetEventListener(handle, listener)

    /** mpv log levels: "no", "fatal", "error", "warn", "info", "v", "debug", "trace". */
    fun requestLogMessages(handle: Long, minLevel: String): Int =
        nativeRequestLogMessages(handle, minLevel)

    fun observeProperty(handle: Long, replyId: Long, name: String, format: Int): Int =
        nativeObserveProperty(handle, replyId, name, format)

    fun unobserveProperty(handle: Long, replyId: Long): Int =
        nativeUnobserveProperty(handle, replyId)

    // ---------------------------------------------------------------------
    // Commands + options + properties.
    // ---------------------------------------------------------------------

    /** Vector command: `mpv_command(["loadfile", url, "replace"])` and friends. */
    fun command(handle: Long, args: Array<String>): Int = nativeCommand(handle, args)

    /** String command: equivalent of `mpv_command_string("seek 5 relative")`. */
    fun commandString(handle: Long, cmd: String): Int = nativeCommandString(handle, cmd)

    fun setOptionString(handle: Long, name: String, value: String): Int =
        nativeSetOptionString(handle, name, value)

    fun setPropertyString(handle: Long, name: String, value: String): Int =
        nativeSetPropertyString(handle, name, value)

    fun setPropertyDouble(handle: Long, name: String, value: Double): Int =
        nativeSetPropertyDouble(handle, name, value)

    fun setPropertyLong(handle: Long, name: String, value: Long): Int =
        nativeSetPropertyLong(handle, name, value)

    fun setPropertyBoolean(handle: Long, name: String, value: Boolean): Int =
        nativeSetPropertyBoolean(handle, name, value)

    /** Returns null if mpv reports the property is unavailable. */
    fun getPropertyString(handle: Long, name: String): String? =
        nativeGetPropertyString(handle, name)

    fun getPropertyDouble(handle: Long, name: String): Double? =
        nativeGetPropertyDouble(handle, name)

    fun getPropertyLong(handle: Long, name: String): Long? =
        nativeGetPropertyLong(handle, name)

    fun getPropertyBoolean(handle: Long, name: String): Boolean? =
        nativeGetPropertyBoolean(handle, name)

    // ---------------------------------------------------------------------
    // Surface attachment.
    //
    // libmpv with `gpu-context=android` reads the `wid` property as the
    // address of an `ANativeWindow*`; the JNI side handles the conversion +
    // ownership.
    // ---------------------------------------------------------------------

    /** Attach a Compose/View `SurfaceHolder` surface. Replaces any prior surface. */
    fun attachSurface(handle: Long, surface: Surface): Int =
        nativeAttachSurface(handle, surface)

    /** Detach without destroying the mpv handle; safe to follow with [attachSurface]. */
    fun detachSurface(handle: Long): Int = nativeDetachSurface(handle)

    // ---------------------------------------------------------------------
    // JNI declarations — kept private; everything above is the public API.
    // ---------------------------------------------------------------------

    @JvmStatic private external fun nativeCreate(): Long
    @JvmStatic private external fun nativeInitialize(handle: Long): Int
    @JvmStatic private external fun nativeTerminateDestroy(handle: Long)
    @JvmStatic private external fun nativeErrorString(code: Int): String

    @JvmStatic private external fun nativeSetEventListener(handle: Long, listener: EventListener?)
    @JvmStatic private external fun nativeRequestLogMessages(handle: Long, level: String): Int
    @JvmStatic private external fun nativeObserveProperty(
        handle: Long, replyId: Long, name: String, format: Int,
    ): Int
    @JvmStatic private external fun nativeUnobserveProperty(handle: Long, replyId: Long): Int

    @JvmStatic private external fun nativeCommand(handle: Long, args: Array<String>): Int
    @JvmStatic private external fun nativeCommandString(handle: Long, cmd: String): Int

    @JvmStatic private external fun nativeSetOptionString(handle: Long, name: String, value: String): Int
    @JvmStatic private external fun nativeSetPropertyString(handle: Long, name: String, value: String): Int
    @JvmStatic private external fun nativeSetPropertyDouble(handle: Long, name: String, value: Double): Int
    @JvmStatic private external fun nativeSetPropertyLong(handle: Long, name: String, value: Long): Int
    @JvmStatic private external fun nativeSetPropertyBoolean(handle: Long, name: String, value: Boolean): Int

    @JvmStatic private external fun nativeGetPropertyString(handle: Long, name: String): String?
    @JvmStatic private external fun nativeGetPropertyDouble(handle: Long, name: String): Double?
    @JvmStatic private external fun nativeGetPropertyLong(handle: Long, name: String): Long?
    @JvmStatic private external fun nativeGetPropertyBoolean(handle: Long, name: String): Boolean?

    @JvmStatic private external fun nativeAttachSurface(handle: Long, surface: Surface): Int
    @JvmStatic private external fun nativeDetachSurface(handle: Long): Int
}
