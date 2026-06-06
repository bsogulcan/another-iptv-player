package dev.android.anotheriptvplayer.ui

import android.net.Uri
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideOutVertically
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import dev.android.anotheriptvplayer.ui.components.ModalSlideDurationMs
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import kotlinx.coroutines.launch
import dev.android.anotheriptvplayer.ui.dashboard.M3uDashboardScreen
import dev.android.anotheriptvplayer.ui.dashboard.PlaylistDashboardScreen
import dev.android.anotheriptvplayer.ui.downloads.DownloadsScreen
import dev.android.anotheriptvplayer.ui.history.WatchHistoryScreen
import dev.android.anotheriptvplayer.ui.search.SearchScreen
import dev.android.anotheriptvplayer.model.PlaylistKind
import dev.android.anotheriptvplayer.ui.dashboard.category.LiveCategoryDetailScreen
import dev.android.anotheriptvplayer.ui.dashboard.category.MovieCategoryDetailScreen
import dev.android.anotheriptvplayer.ui.dashboard.category.SeriesCategoryDetailScreen
import dev.android.anotheriptvplayer.ui.dashboard.detail.MovieDetailScreen
import dev.android.anotheriptvplayer.ui.dashboard.detail.SeriesDetailScreen
import dev.android.anotheriptvplayer.ui.favorites.FavoritesScreen
import dev.android.anotheriptvplayer.ui.playlist.AddM3UPlaylistScreen
import dev.android.anotheriptvplayer.ui.player.PlayerScreen
import dev.android.anotheriptvplayer.ui.player.PlayerViewModel
import dev.android.anotheriptvplayer.ui.playlist.AddXtreamPlaylistScreen
import dev.android.anotheriptvplayer.ui.playlist.PlaylistScreen

/** Route names for the app's navigation graph. */
private object Routes {
    const val PLAYLISTS = "playlists"
    const val ADD_XTREAM = "add_xtream"
    const val ADD_M3U = "add_m3u"
    const val DASHBOARD = "dashboard"
    const val MOVIE = "movie"
    const val SERIES = "series"
    const val LIVE_CATEGORY = "live_category"
    const val VOD_CATEGORY = "vod_category"
    const val SERIES_CATEGORY = "series_category"
    const val FAVORITES = "favorites"
    const val PLAYER_MOVIE = "player/movie"
    const val PLAYER_SERIES = "player/series"
    const val PLAYER_LIVE = "player/live"
    const val PLAYER_M3U = "player/m3u"
    const val SEARCH = "search"
    const val HISTORY = "history"
    const val DOWNLOADS = "downloads"

    /** Edit routes reuse the add screens with an optional playlist id. */
    fun xtream(playlistId: String? = null) =
        if (playlistId != null) "$ADD_XTREAM?playlistId=$playlistId" else ADD_XTREAM

    fun m3u(playlistId: String? = null) =
        if (playlistId != null) "$ADD_M3U?playlistId=$playlistId" else ADD_M3U

    fun dashboard(playlistId: String) = "$DASHBOARD/$playlistId"

    fun movie(playlistId: String, streamId: Int) = "$MOVIE/$playlistId/$streamId"

    fun series(playlistId: String, seriesId: Int) = "$SERIES/$playlistId/$seriesId"

    fun liveCategory(playlistId: String, categoryId: String) =
        "$LIVE_CATEGORY/$playlistId/${Uri.encode(categoryId)}"

    fun vodCategory(playlistId: String, categoryId: String) =
        "$VOD_CATEGORY/$playlistId/${Uri.encode(categoryId)}"

    fun seriesCategory(playlistId: String, categoryId: String) =
        "$SERIES_CATEGORY/$playlistId/${Uri.encode(categoryId)}"

    fun favorites(playlistId: String, type: String) = "$FAVORITES/$playlistId/$type"

    fun playerMovie(playlistId: String, streamId: Int) =
        "$PLAYER_MOVIE/$playlistId/$streamId"

    fun playerSeries(playlistId: String, episodeId: String) =
        "$PLAYER_SERIES/$playlistId/${Uri.encode(episodeId)}"

    fun playerLive(playlistId: String, streamId: Int) =
        "$PLAYER_LIVE/$playlistId/$streamId"

    fun playerM3u(playlistId: String, channelId: String) =
        "$PLAYER_M3U/$playlistId/${Uri.encode(channelId)}"

    fun search(playlistId: String) = "$SEARCH/$playlistId"
    fun history(playlistId: String) = "$HISTORY/$playlistId"
    fun downloads(playlistId: String) = "$DOWNLOADS/$playlistId"
}

private const val ARG_CHANNEL_ID = "channelId"

private const val ARG_STREAM_ID = "streamId"
private const val ARG_SERIES_ID = "seriesId"
private const val ARG_CATEGORY_ID = "categoryId"
private const val ARG_FAV_TYPE = "type"
private const val ARG_EPISODE_ID = "episodeId"

private const val ARG_PLAYLIST_ID = "playlistId"

@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val lastPlaylistStore = LocalLastPlaylistStore.current
    val playlistRepository = LocalPlaylistRepository.current
    val scope = rememberCoroutineScope()

    // Mirrors iOS `hasAttemptedAutoLoad`: try once per process to resume the
    // last opened playlist. If the saved id is missing from the DB, silently
    // drop it so the next launch starts at the list rather than retrying.
    var hasAttemptedAutoLoad by rememberSaveable { mutableStateOf(false) }
    val playlists by playlistRepository.observeAll().collectAsState(initial = null)
    LaunchedEffect(playlists, hasAttemptedAutoLoad) {
        val list = playlists ?: return@LaunchedEffect
        if (hasAttemptedAutoLoad) return@LaunchedEffect
        hasAttemptedAutoLoad = true
        val savedId = lastPlaylistStore.read() ?: return@LaunchedEffect
        val match = list.firstOrNull { it.id == savedId }
        if (match == null) {
            lastPlaylistStore.clear()
            return@LaunchedEffect
        }
        navController.navigate(Routes.dashboard(savedId)) {
            popUpTo(Routes.PLAYLISTS) { inclusive = false }
            launchSingleTop = true
        }
    }

    // Short fade for every nav transition — keeps the NavHost crossfade brief
    // so the modal slide-up driven by ModalSlideContainer is what the user sees.
    NavHost(
        navController = navController,
        startDestination = Routes.PLAYLISTS,
        enterTransition = { fadeIn(tween(120)) },
        exitTransition = { fadeOut(tween(120)) },
        popEnterTransition = { fadeIn(tween(120)) },
        popExitTransition = { fadeOut(tween(120)) },
    ) {
        composable(route = Routes.PLAYLISTS) {
            PlaylistScreen(
                onAddXtream = { navController.navigate(Routes.xtream()) },
                onAddM3u = { navController.navigate(Routes.m3u()) },
                onEditXtream = { id -> navController.navigate(Routes.xtream(id)) },
                onEditM3u = { id -> navController.navigate(Routes.m3u(id)) },
                onOpenPlaylist = { id ->
                    lastPlaylistStore.write(id)
                    navController.navigate(Routes.dashboard(id))
                },
            )
        }

        composable(
            route = "${Routes.DASHBOARD}/{$ARG_PLAYLIST_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) {
                    type = NavType.StringType
                    nullable = false
                },
            ),
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable

            // Branch on playlist kind: Xtream dashboards have the
            // Live/VOD/Series triple, M3U has one flat channel list.
            var resolvedKind by androidx.compose.runtime.remember(id) {
                androidx.compose.runtime.mutableStateOf<PlaylistKind?>(null)
            }
            androidx.compose.runtime.LaunchedEffect(id) {
                resolvedKind = playlistRepository.find(id)?.kind ?: PlaylistKind.XTREAM
            }

            val backWithCleanup: () -> Unit = {
                // Matches iOS `M3UDashboardView { lastPlaylistId removed }`:
                // explicit back to the list also clears the auto-load
                // marker so the next launch goes to the list, not back here.
                lastPlaylistStore.clear()
                navController.popBackStack()
            }

            when (resolvedKind) {
                PlaylistKind.M3U -> {
                    M3uDashboardScreen(
                        playlistId = id,
                        onBack = backWithCleanup,
                        onPlayChannel = { channelId, _, _ ->
                            navController.navigate(Routes.playerM3u(id, channelId))
                        },
                    )
                }
                else -> {
                    PlaylistDashboardScreen(
                        playlistId = id,
                        onBack = backWithCleanup,
                        onOpenMovie = { streamId ->
                            navController.navigate(Routes.movie(id, streamId))
                        },
                        onOpenSeries = { seriesId ->
                            navController.navigate(Routes.series(id, seriesId))
                        },
                        onOpenLiveCategory = { catId ->
                            navController.navigate(Routes.liveCategory(id, catId))
                        },
                        onOpenVodCategory = { catId ->
                            navController.navigate(Routes.vodCategory(id, catId))
                        },
                        onOpenSeriesCategory = { catId ->
                            navController.navigate(Routes.seriesCategory(id, catId))
                        },
                        onOpenFavorites = { type ->
                            navController.navigate(Routes.favorites(id, type))
                        },
                        onPlayLive = { streamId ->
                            navController.navigate(Routes.playerLive(id, streamId))
                        },
                        onOpenDownloads = {
                            navController.navigate(Routes.downloads(id))
                        },
                        onOpenHistory = {
                            navController.navigate(Routes.history(id))
                        },
                        onOpenSearch = {
                            navController.navigate(Routes.search(id))
                        },
                        onResumeEpisode = { eid ->
                            navController.navigate(Routes.playerSeries(id, eid))
                        },
                        appVersion = dev.android.anotheriptvplayer.BuildConfig.VERSION_NAME,
                    )
                }
            }
        }

        composable(
            route = "${Routes.MOVIE}/{$ARG_PLAYLIST_ID}/{$ARG_STREAM_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) {
                    type = NavType.StringType
                    nullable = false
                },
                navArgument(ARG_STREAM_ID) {
                    type = NavType.IntType
                },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val streamId = backStackEntry.arguments?.getInt(ARG_STREAM_ID)
                ?: return@composable
            MovieDetailScreen(
                playlistId = playlistId,
                streamId = streamId,
                onBack = { navController.popBackStack() },
                onPlay = {
                    navController.navigate(Routes.playerMovie(playlistId, streamId))
                },
            )
        }

        composable(
            route = "${Routes.PLAYER_MOVIE}/{$ARG_PLAYLIST_ID}/{$ARG_STREAM_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_STREAM_ID) { type = NavType.IntType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val streamId = backStackEntry.arguments?.getInt(ARG_STREAM_ID)
                ?: return@composable
            PlayerScreen(
                playlistId = playlistId,
                streamRef = streamId.toString(),
                kind = PlayerViewModel.Kind.MOVIE,
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = "${Routes.PLAYER_SERIES}/{$ARG_PLAYLIST_ID}/{$ARG_EPISODE_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_EPISODE_ID) { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val episodeId = backStackEntry.arguments?.getString(ARG_EPISODE_ID)
                ?: return@composable
            PlayerScreen(
                playlistId = playlistId,
                streamRef = episodeId,
                kind = PlayerViewModel.Kind.SERIES_EPISODE,
                onBack = { navController.popBackStack() },
                onPlayNextEpisode = { nextId ->
                    // Replace the current player entry so back goes to the
                    // series detail rather than the previous episode.
                    navController.navigate(Routes.playerSeries(playlistId, nextId)) {
                        popUpTo("${Routes.PLAYER_SERIES}/{$ARG_PLAYLIST_ID}/{$ARG_EPISODE_ID}") {
                            inclusive = true
                        }
                        launchSingleTop = true
                    }
                },
            )
        }

        composable(
            route = "${Routes.PLAYER_M3U}/{$ARG_PLAYLIST_ID}/{$ARG_CHANNEL_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_CHANNEL_ID) { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val channelId = backStackEntry.arguments?.getString(ARG_CHANNEL_ID)
                ?: return@composable
            PlayerScreen(
                playlistId = playlistId,
                streamRef = channelId,
                kind = PlayerViewModel.Kind.M3U_CHANNEL,
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = "${Routes.PLAYER_LIVE}/{$ARG_PLAYLIST_ID}/{$ARG_STREAM_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_STREAM_ID) { type = NavType.IntType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val streamId = backStackEntry.arguments?.getInt(ARG_STREAM_ID)
                ?: return@composable
            PlayerScreen(
                playlistId = playlistId,
                streamRef = streamId.toString(),
                kind = PlayerViewModel.Kind.LIVE,
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = "${Routes.SERIES}/{$ARG_PLAYLIST_ID}/{$ARG_SERIES_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) {
                    type = NavType.StringType
                    nullable = false
                },
                navArgument(ARG_SERIES_ID) {
                    type = NavType.IntType
                },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val seriesId = backStackEntry.arguments?.getInt(ARG_SERIES_ID)
                ?: return@composable
            SeriesDetailScreen(
                playlistId = playlistId,
                seriesId = seriesId,
                onBack = { navController.popBackStack() },
                onPlayEpisode = { episodeId ->
                    navController.navigate(Routes.playerSeries(playlistId, episodeId))
                },
            )
        }

        composable(
            route = "${Routes.LIVE_CATEGORY}/{$ARG_PLAYLIST_ID}/{$ARG_CATEGORY_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_CATEGORY_ID) { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val categoryId = backStackEntry.arguments?.getString(ARG_CATEGORY_ID)
                ?: return@composable
            LiveCategoryDetailScreen(
                playlistId = playlistId,
                categoryId = categoryId,
                onBack = { navController.popBackStack() },
                onPlayChannel = { streamId ->
                    navController.navigate(Routes.playerLive(playlistId, streamId))
                },
            )
        }

        composable(
            route = "${Routes.VOD_CATEGORY}/{$ARG_PLAYLIST_ID}/{$ARG_CATEGORY_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_CATEGORY_ID) { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val categoryId = backStackEntry.arguments?.getString(ARG_CATEGORY_ID)
                ?: return@composable
            MovieCategoryDetailScreen(
                playlistId = playlistId,
                categoryId = categoryId,
                onBack = { navController.popBackStack() },
                onOpenMovie = { streamId ->
                    navController.navigate(Routes.movie(playlistId, streamId))
                },
            )
        }

        composable(
            route = "${Routes.SERIES_CATEGORY}/{$ARG_PLAYLIST_ID}/{$ARG_CATEGORY_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_CATEGORY_ID) { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val categoryId = backStackEntry.arguments?.getString(ARG_CATEGORY_ID)
                ?: return@composable
            SeriesCategoryDetailScreen(
                playlistId = playlistId,
                categoryId = categoryId,
                onBack = { navController.popBackStack() },
                onOpenSeries = { seriesId ->
                    navController.navigate(Routes.series(playlistId, seriesId))
                },
            )
        }

        composable(
            route = "${Routes.FAVORITES}/{$ARG_PLAYLIST_ID}/{$ARG_FAV_TYPE}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType },
                navArgument(ARG_FAV_TYPE) { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val playlistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID)
                ?: return@composable
            val type = backStackEntry.arguments?.getString(ARG_FAV_TYPE) ?: "vod"
            FavoritesScreen(
                playlistId = playlistId,
                initialType = type,
                onBack = { navController.popBackStack() },
                onOpenMovie = { streamId ->
                    navController.navigate(Routes.movie(playlistId, streamId))
                },
                onOpenSeries = { seriesId ->
                    navController.navigate(Routes.series(playlistId, seriesId))
                },
                onPlayLive = { streamId ->
                    navController.navigate(Routes.playerLive(playlistId, streamId))
                },
            )
        }


        // Add / edit screens behave like native full-screen modal dialogs. The
        // slide-up is driven inside the screen by ModalSlideContainer — NavHost
        // slide transitions mis-place touch targets, so they are avoided here.
        composable(
            route = "${Routes.SEARCH}/{$ARG_PLAYLIST_ID}",
            arguments = listOf(navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType }),
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID) ?: return@composable
            SearchScreen(
                playlistId = id,
                onBack = { navController.popBackStack() },
                onOpenLive = { sid -> navController.navigate(Routes.playerLive(id, sid)) },
                onOpenMovie = { sid -> navController.navigate(Routes.movie(id, sid)) },
                onOpenSeries = { sid -> navController.navigate(Routes.series(id, sid)) },
                onPlayM3uChannel = { cid -> navController.navigate(Routes.playerM3u(id, cid)) },
            )
        }

        composable(
            route = "${Routes.HISTORY}/{$ARG_PLAYLIST_ID}",
            arguments = listOf(navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType }),
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID) ?: return@composable
            WatchHistoryScreen(
                playlistId = id,
                onBack = { navController.popBackStack() },
                onResumeMovie = { sid -> navController.navigate(Routes.movie(id, sid)) },
                onResumeSeries = { eid -> navController.navigate(Routes.playerSeries(id, eid)) },
                onPlayLive = { sid -> navController.navigate(Routes.playerLive(id, sid)) },
            )
        }

        composable(
            route = "${Routes.DOWNLOADS}/{$ARG_PLAYLIST_ID}",
            arguments = listOf(navArgument(ARG_PLAYLIST_ID) { type = NavType.StringType }),
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID) ?: return@composable
            DownloadsScreen(
                playlistId = id,
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = "${Routes.ADD_XTREAM}?playlistId={$ARG_PLAYLIST_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                },
            ),
            popExitTransition = {
                slideOutVertically(tween(ModalSlideDurationMs, easing = FastOutSlowInEasing)) { it }
            },
        ) { backStackEntry ->
            AddXtreamPlaylistScreen(
                onCancel = { navController.popBackStack() },
                onSaved = { playlistId ->
                    // Jump straight to the dashboard so the user can see the
                    // freshly-synced catalog — the modal slides away under
                    // the dashboard transition. The playlists list stays in
                    // the back stack so pressing Back returns there.
                    navController.navigate(Routes.dashboard(playlistId)) {
                        popUpTo(Routes.PLAYLISTS) { inclusive = false }
                        launchSingleTop = true
                    }
                },
                editingPlaylistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID),
            )
        }

        composable(
            route = "${Routes.ADD_M3U}?playlistId={$ARG_PLAYLIST_ID}",
            arguments = listOf(
                navArgument(ARG_PLAYLIST_ID) {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                },
            ),
            popExitTransition = {
                slideOutVertically(tween(ModalSlideDurationMs, easing = FastOutSlowInEasing)) { it }
            },
        ) { backStackEntry ->
            AddM3UPlaylistScreen(
                onCancel = { navController.popBackStack() },
                onSaved = { playlistId ->
                    navController.navigate(Routes.dashboard(playlistId)) {
                        popUpTo(Routes.PLAYLISTS) { inclusive = false }
                        launchSingleTop = true
                    }
                },
                editingPlaylistId = backStackEntry.arguments?.getString(ARG_PLAYLIST_ID),
            )
        }
    }
}
