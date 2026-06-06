package dev.android.anotheriptvplayer.ui.player

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import dev.android.anotheriptvplayer.AnotherIptvPlayerApp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.data.PlaybackUrlBuilder
import dev.android.anotheriptvplayer.data.local.EpisodeEntity
import dev.android.anotheriptvplayer.data.local.WatchHistoryEntity
import dev.android.anotheriptvplayer.player.MPVPlayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * Holds the libmpv player across config changes so screen rotation doesn't
 * tear down playback. Mirrors the role of iOS `VideoPlayerController`
 * (`ios/another-iptv-player/Networking/VideoPlayerController.swift`) — that
 * class outlives the SwiftUI view tree for the same reason.
 *
 * Construct via [PlayerViewModel.factory]; the factory wires the playlist +
 * stream IDs in. The VM resolves them to a stream URL, kicks off
 * [MPVPlayer.load], and surfaces the result through [title]/[player].
 */
class PlayerViewModel(
    application: Application,
    private val playlistId: String,
    /**
     * Opaque identifier for the source to play. Interpretation depends on
     * [kind]: for [Kind.MOVIE] / [Kind.LIVE] it's the integer Xtream
     * `stream_id` (encoded as a String for nav uniformity); for
     * [Kind.SERIES_EPISODE] it's the `episode.id` Room primary key (already
     * a String). Keeping a single ref string lets the three nav routes share
     * one ViewModel signature.
     */
    private val streamRef: String,
    private val kind: Kind,
) : AndroidViewModel(application) {

    enum class Kind { MOVIE, SERIES_EPISODE, LIVE, M3U_CHANNEL }

    private val _title = MutableStateFlow("")
    val title: StateFlow<String> = _title.asStateFlow()

    /** Non-null once URL resolution has failed; UI flips to an error state. */
    private val _resolveError = MutableStateFlow<String?>(null)
    val resolveError: StateFlow<String?> = _resolveError.asStateFlow()

    /**
     * Snapshot of the metadata the watch-history writer needs. Populated by
     * [resolveAndLoad] once we've fetched the underlying row; the position
     * collector reads it on every 5s tick. Null until resolve completes (so
     * we don't write a half-formed row at process start).
     */
    private data class WatchMeta(
        val historyId: String,
        val type: String,
        val streamId: String,
        val seriesId: String?,
        val title: String,
        val secondaryTitle: String?,
        val imageUrl: String?,
    )

    @Volatile private var watchMeta: WatchMeta? = null

    /**
     * Last episode of the current series (used by the autoplay-next overlay
     * in `PlayerScreen`). Null when the player isn't on a series episode or
     * the current episode is already the final one.
     */
    private val _nextEpisode = MutableStateFlow<EpisodeEntity?>(null)
    val nextEpisode: StateFlow<EpisodeEntity?> = _nextEpisode.asStateFlow()

    /** True once EOF reached for an episode and a follow-up exists. */
    private val _shouldOfferAutoplay = MutableStateFlow(false)
    val shouldOfferAutoplay: StateFlow<Boolean> = _shouldOfferAutoplay.asStateFlow()

    // Guarded construction: MPVPlayer's init block calls into libmpv, which can
    // throw (UnsatisfiedLinkError if the JNI .so isn't packaged, IllegalState
    // if mpv_initialize fails on this device). Letting that propagate out of
    // the VM constructor crashes the whole process — surface it as an error
    // overlay instead so we keep the device + we still get a logcat line.
    //
    // Declared after `_resolveError` so the catch can publish into it.
    val player: MPVPlayer? = try {
        MPVPlayer(application)
    } catch (t: Throwable) {
        Log.e(TAG, "MPVPlayer() construction failed", t)
        val detail = "${t.javaClass.simpleName}: ${t.message ?: "unknown"}"
        _resolveError.value = application.getString(R.string.resolve_player_init_failed, detail)
        null
    }

    init {
        if (player != null) {
            viewModelScope.launch { resolveAndLoad() }
            startWatchHistoryWriter()
            startAutoplayWatcher()
        }
    }

    /**
     * Every ~5s while we have a position update, upsert the watch-history
     * row for the current stream. iOS does the same in
     * `VideoPlayerController.persistWatchHistoryIfNeeded`. The DAO does
     * `INSERT OR REPLACE` so a no-op write is just a write — no diff needed.
     */
    private fun startWatchHistoryWriter() {
        val mpv = player ?: return
        viewModelScope.launch(Dispatchers.IO) {
            combine(mpv.position, mpv.duration) { pos, dur -> pos to dur }
                .distinctUntilChanged()
                .collectLatest { (pos, dur) ->
                    val meta = watchMeta ?: return@collectLatest
                    val now = System.currentTimeMillis()
                    if (lastHistoryWriteMs != 0L && now - lastHistoryWriteMs < HISTORY_WRITE_INTERVAL_MS) {
                        return@collectLatest
                    }
                    lastHistoryWriteMs = now
                    upsertHistory(meta, pos, dur)
                }
        }
    }

    /**
     * Watches `isCompleted`; when an episode reaches EOF and we have a
     * `nextEpisode` cached, flip [shouldOfferAutoplay] so the overlay shows
     * a "Next: …" prompt. UI resets the flag once handled.
     */
    private fun startAutoplayWatcher() {
        val mpv = player ?: return
        if (kind != Kind.SERIES_EPISODE) return
        viewModelScope.launch {
            mpv.isCompleted.collectLatest { completed ->
                _shouldOfferAutoplay.value = completed && _nextEpisode.value != null
            }
        }
    }

    private suspend fun upsertHistory(meta: WatchMeta, positionSeconds: Double, durationSeconds: Double) {
        val app = getApplication<AnotherIptvPlayerApp>()
        val positionMs = (positionSeconds * 1000.0).toLong().coerceAtLeast(0L)
        val durationMs = (durationSeconds * 1000.0).toLong().coerceAtLeast(0L)
        // Live (no duration) — still record a row so it shows up in the
        // "recently watched" rail, but with zero progress fraction.
        val row = WatchHistoryEntity(
            id = meta.historyId,
            playlistId = playlistId,
            streamId = meta.streamId,
            type = meta.type,
            lastTimeMs = if (meta.type == "live") 0L else positionMs,
            durationMs = if (meta.type == "live") 0L else durationMs,
            lastWatchedAt = System.currentTimeMillis(),
            title = meta.title,
            secondaryTitle = meta.secondaryTitle,
            imageUrl = meta.imageUrl,
            seriesId = meta.seriesId,
            containerExtension = null,
        )
        runCatching { app.appDatabaseForDownloads.watchHistoryDao().upsert(row) }
    }

    @Volatile private var lastHistoryWriteMs: Long = 0L

    private suspend fun resolveAndLoad() {
        val mpv = player ?: return
        val app = getApplication<AnotherIptvPlayerApp>()
        val playlist = app.playlistRepository.find(playlistId)
        if (playlist == null) {
            _resolveError.value = app.getString(R.string.resolve_playlist_not_found)
            return
        }
        val builder = PlaybackUrlBuilder(playlist)
        when (kind) {
            Kind.MOVIE -> {
                val streamId = streamRef.toIntOrNull()
                val movie = streamId?.let { app.vodRepository.find(it, playlistId) }
                if (movie == null) {
                    _resolveError.value = app.getString(R.string.resolve_movie_not_found)
                    return
                }
                _title.value = movie.name
                watchMeta = WatchMeta(
                    historyId = "${playlistId}_vod_${movie.streamId}",
                    type = "vod",
                    streamId = movie.streamId.toString(),
                    seriesId = null,
                    title = movie.name,
                    secondaryTitle = movie.genre,
                    imageUrl = movie.streamIcon ?: movie.backdropPath,
                )
                val url = builder.movieUrl(
                    streamId = movie.streamId,
                    containerExtension = movie.containerExtension,
                )
                // Resume from saved progress if any (iOS `historyManager.resume`).
                val resumeSeconds = readResumeSeconds(watchMeta!!.historyId)
                mpv.load(url, play = true, startSeconds = resumeSeconds, liveLowLatency = false)
            }
            Kind.SERIES_EPISODE -> {
                val episode = app.seriesRepository.findEpisode(streamRef)
                if (episode == null) {
                    _resolveError.value = app.getString(R.string.resolve_episode_not_found)
                    return
                }
                val displayTitle = episode.title?.takeIf { it.isNotBlank() }
                    ?: app.getString(R.string.player_episode_default_format, episode.episodeNum?.toString().orEmpty()).trim()
                _title.value = displayTitle

                // Look up the parent series for the secondary title + cover.
                val seasonId = episode.seasonId
                val seriesNumberFromId = seasonId.substringBefore('_').toIntOrNull()
                val seriesEntity = seriesNumberFromId?.let {
                    app.seriesRepository.observeSeries(it, playlistId)
                    app.appDatabaseForDownloads.seriesDao().findById(it, playlistId)
                }
                watchMeta = WatchMeta(
                    historyId = "${playlistId}_series_${episode.id}",
                    type = "series",
                    streamId = episode.id,
                    seriesId = seriesEntity?.seriesId?.toString(),
                    title = displayTitle,
                    secondaryTitle = seriesEntity?.name,
                    imageUrl = episode.cover ?: seriesEntity?.cover,
                )
                computeNextEpisode(episode, seriesEntity?.seriesId)

                val urlStreamId = episode.episodeId?.takeIf { it.isNotBlank() } ?: episode.id
                val url = builder.seriesUrl(
                    streamId = urlStreamId,
                    containerExtension = episode.containerExtension,
                )
                val resumeSeconds = readResumeSeconds(watchMeta!!.historyId)
                mpv.load(url, play = true, startSeconds = resumeSeconds, liveLowLatency = false)
            }
            Kind.LIVE -> {
                val streamId = streamRef.toIntOrNull()
                val channel = streamId?.let { app.findLiveStream(it, playlistId) }
                if (channel == null) {
                    _resolveError.value = app.getString(R.string.resolve_channel_not_found)
                    return
                }
                _title.value = channel.name
                watchMeta = WatchMeta(
                    historyId = "${playlistId}_live_${channel.streamId}",
                    type = "live",
                    streamId = channel.streamId.toString(),
                    seriesId = null,
                    title = channel.name,
                    secondaryTitle = null,
                    imageUrl = channel.streamIcon,
                )
                val url = builder.liveUrl(streamId = channel.streamId)
                mpv.load(url, play = true, startSeconds = null, liveLowLatency = true)
            }
            Kind.M3U_CHANNEL -> {
                val channel = app.appDatabaseForDownloads
                    .m3uChannelDao()
                    .findById(streamRef)
                if (channel == null) {
                    _resolveError.value = app.getString(R.string.resolve_channel_not_found)
                    return
                }
                _title.value = channel.name
                watchMeta = WatchMeta(
                    historyId = "${playlistId}_live_${channel.id}",
                    type = "live",
                    streamId = channel.id,
                    seriesId = null,
                    title = channel.name,
                    secondaryTitle = channel.groupTitle,
                    imageUrl = channel.tvgLogo,
                )
                mpv.load(channel.url, play = true, startSeconds = null, liveLowLatency = true)
            }
        }
    }

    private suspend fun readResumeSeconds(historyId: String): Double? {
        return withContext(Dispatchers.IO) {
            val row = getApplication<AnotherIptvPlayerApp>()
                .appDatabaseForDownloads
                .watchHistoryDao()
                .findById(historyId) ?: return@withContext null
            val pos = row.lastTimeMs / 1000.0
            val dur = row.durationMs / 1000.0
            // Don't resume in the last 30 seconds — iOS `RESUME_TAIL`. The user
            // most likely finished the file; restart from 0 instead.
            if (dur > 0 && pos > 0 && pos < dur - 30.0) pos else null
        }
    }

    /**
     * Resolves the "next" episode for the autoplay-next prompt. Implements
     * iOS `SeriesPlaybackOrdering.neighbors`: flatten seasons in number order,
     * then episodes in episodeNum order, find current episode by id, return
     * the next item.
     */
    private suspend fun computeNextEpisode(current: EpisodeEntity, seriesId: Int?) {
        val sid = seriesId ?: return
        val app = getApplication<AnotherIptvPlayerApp>()
        val db = app.appDatabaseForDownloads
        val seasons = db.seasonDao().getBySeries(sid, playlistId)
        val flat = mutableListOf<EpisodeEntity>()
        for (s in seasons) {
            // EpisodeDao.observeBySeason emits ORDER BY episodeNum; we want the
            // synchronous read here, so go through findById's sibling — pull
            // via a quick suspend list call via a custom query.
            flat += episodesInSeasonOrdered(s.id)
        }
        val idx = flat.indexOfFirst { it.id == current.id }
        _nextEpisode.value = if (idx >= 0 && idx < flat.lastIndex) flat[idx + 1] else null
    }

    private suspend fun episodesInSeasonOrdered(seasonId: String): List<EpisodeEntity> {
        // EpisodeDao exposes `observeBySeason` (Flow) but no suspend list
        // variant. Snapshot the Flow by collecting the first emission.
        val app = getApplication<AnotherIptvPlayerApp>()
        val dao = app.appDatabaseForDownloads.episodeDao()
        return dao.observeBySeason(seasonId).firstOrNull() ?: emptyList()
    }

    fun consumeAutoplayOffer() {
        _shouldOfferAutoplay.value = false
    }

    override fun onCleared() {
        super.onCleared()
        // Final write — block briefly so the row lands before the VM dies.
        // `runBlocking` is acceptable here because onCleared isn't on a
        // sensitive thread and the I/O is a single upsert.
        val meta = watchMeta
        val mpv = player
        if (meta != null && mpv != null) {
            runBlocking(Dispatchers.IO + NonCancellable) {
                upsertHistory(meta, mpv.position.value, mpv.duration.value)
            }
        }
        player?.dispose()
    }

    companion object {
        private const val TAG = "PlayerViewModel"
        private const val HISTORY_WRITE_INTERVAL_MS = 5_000L

        fun factory(
            application: Application,
            playlistId: String,
            streamRef: String,
            kind: Kind,
        ) = viewModelFactory {
            initializer {
                PlayerViewModel(application, playlistId, streamRef, kind)
            }
        }
    }
}

