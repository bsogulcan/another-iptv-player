package dev.android.anotheriptvplayer

import android.app.Application
import dev.android.anotheriptvplayer.data.DownloadManager
import dev.android.anotheriptvplayer.data.DownloadStorage
import dev.android.anotheriptvplayer.data.FavoriteRepository
import dev.android.anotheriptvplayer.data.HiddenCategoryStore
import dev.android.anotheriptvplayer.data.LastPlaylistStore
import dev.android.anotheriptvplayer.data.M3uContentStore
import dev.android.anotheriptvplayer.data.M3uFavoriteStore
import dev.android.anotheriptvplayer.data.M3uImporter
import dev.android.anotheriptvplayer.data.PlayerPreferences
import dev.android.anotheriptvplayer.data.PlaylistContentStore
import dev.android.anotheriptvplayer.data.PlaylistRepository
import dev.android.anotheriptvplayer.data.RatingManager
import dev.android.anotheriptvplayer.data.SeriesRepository
import dev.android.anotheriptvplayer.data.VodRepository
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.LiveStreamEntity

/**
 * App-wide singleton holder.
 *
 * Mirrors the iOS `AppDatabase.shared` pattern: a single SQLite instance and
 * the repositories that wrap it live here, lazily created on first use.
 * The Composition tree reaches them via [dev.android.anotheriptvplayer.ui.LocalPlaylistRepository]
 * and [dev.android.anotheriptvplayer.ui.LocalPlaylistContentStore].
 */
class AnotherIptvPlayerApp : Application() {

    private val database: AppDatabase by lazy { AppDatabase.get(this) }

    /**
     * Direct access for [dev.android.anotheriptvplayer.data.DownloadWorker]
     * which can't reach into the composition layer. Treat as package-private
     * even though Kotlin can't express that; mark with the
     * `ForDownloads` suffix so its single caller is obvious.
     */
    val appDatabaseForDownloads: AppDatabase get() = database

    val playlistRepository: PlaylistRepository by lazy {
        PlaylistRepository(database.playlistDao())
    }

    /**
     * Process-wide active-playlist catalog. iOS uses a `@MainActor`
     * singleton (`PlaylistContentStore.shared`); we hold one instance here
     * so the catalog survives back-stack pops.
     */
    val playlistContentStore: PlaylistContentStore by lazy {
        PlaylistContentStore(database, this)
    }

    /** Per-movie reads / writes for the detail screen. */
    val vodRepository: VodRepository by lazy {
        VodRepository(database.vodStreamDao())
    }

    /** Per-series reads / writes — drives `SeriesDetailScreen`. */
    val seriesRepository: SeriesRepository by lazy {
        SeriesRepository(database)
    }

    /** Star toggle + favorites list grids. */
    val favoriteRepository: FavoriteRepository by lazy {
        FavoriteRepository(database.favoriteDao())
    }

    /** Tracks which catalog categories the user has hidden per playlist. */
    val hiddenCategoryStore: HiddenCategoryStore by lazy {
        HiddenCategoryStore(this)
    }

    /**
     * Persists the playlist the user last opened. Mirrors iOS
     * `UserDefaults.lastPlaylistId` — read once at app launch to auto-open
     * the previous dashboard, cleared when the user navigates back to the
     * playlist list.
     */
    val lastPlaylistStore: LastPlaylistStore by lazy {
        LastPlaylistStore(this)
    }

    /** Active M3U playlist channel cache (counterpart of iOS `M3UContentStore.shared`). */
    val m3uContentStore: M3uContentStore by lazy { M3uContentStore(database) }

    /** Reactive M3U favourites set, driven by Room observations. */
    val m3uFavoriteStore: M3uFavoriteStore by lazy { M3uFavoriteStore(database) }

    /** "Replace whole playlist" import path used by the AddM3UPlaylistScreen. */
    val m3uImporter: M3uImporter by lazy { M3uImporter(database) }

    /** Filesystem layout helper for downloads — exposed for the WorkManager Worker. */
    val downloadStorageForWorker: DownloadStorage by lazy { DownloadStorage(this) }

    /** Orchestrator for VOD/episode downloads. iOS counterpart: `DownloadManager.shared`. */
    val downloadManager: DownloadManager by lazy {
        DownloadManager(this, database, downloadStorageForWorker)
    }

    /** App Store review prompt eligibility tracker. Holds *only* the eligibility decision. */
    val ratingManager: RatingManager by lazy { RatingManager(this) }

    /**
     * Player UX preferences (PiP, background playback, long-press 2× speed).
     * iOS counterpart: the `UserDefaults.register(defaults:)` block in the
     * app delegate.
     */
    val playerPreferences: PlayerPreferences by lazy { PlayerPreferences(this) }

    /**
     * Single-row live-stream lookup. Used by [ui.player.PlayerViewModel] to
     * resolve a channel id → name + (optional) extension before handing the
     * URL to libmpv. Skipping the dedicated `LiveStreamRepository` wrapper —
     * everything else for live streams flows through `PlaylistContentStore`'s
     * bulk catalogue feeds.
     */
    suspend fun findLiveStream(streamId: Int, playlistId: String): LiveStreamEntity? =
        database.liveStreamDao().findById(streamId, playlistId)
}
