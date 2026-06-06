package dev.android.anotheriptvplayer.ui.dashboard.detail

import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.data.FavoriteRepository
import dev.android.anotheriptvplayer.networking.XtreamApiClient
import dev.android.anotheriptvplayer.ui.LocalFavoriteRepository
import dev.android.anotheriptvplayer.ui.LocalPlaylistRepository
import dev.android.anotheriptvplayer.ui.LocalVodRepository
import kotlinx.coroutines.launch

/**
 * Kotlin port of iOS `MovieDetailView`.
 *
 * Loads the playlist + observed VOD row reactively from SQLite. On first
 * entry, if the movie's `metadataLoaded` flag is false, kicks off a
 * `get_vod_info` round-trip and merges the response onto the row — Room's
 * observer then re-emits and the UI fills in director / cast / plot /
 * backdrop.
 *
 * "İzle" navigates to the native `PlayerScreen`, which spins up the libmpv
 * engine ([dev.android.anotheriptvplayer.player.MPVPlayer]) and plays the
 * constructed Xtream stream URL inline. The earlier `launchExternalPlayer`
 * Intent fallback has been retired now that we ship our own engine.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MovieDetailScreen(
    playlistId: String,
    streamId: Int,
    onBack: () -> Unit,
    onPlay: () -> Unit,
) {
    val context = LocalContext.current
    val playlistRepository = LocalPlaylistRepository.current
    val vodRepository = LocalVodRepository.current
    val favoriteRepository = LocalFavoriteRepository.current
    val scope = rememberCoroutineScope()

    val isFavorite by favoriteRepository.observeIsFavorite(streamId, playlistId, FavoriteRepository.Type.VOD)
        .collectAsStateWithLifecycle(initialValue = false)

    var playlist by remember(playlistId) { mutableStateOf<Playlist?>(null) }
    LaunchedEffect(playlistId) {
        playlist = playlistRepository.find(playlistId)
    }

    val movie by vodRepository.observe(streamId, playlistId)
        .collectAsStateWithLifecycle(initialValue = null)

    // Tracks the metadata fetch separately from the row-load — `movie` can
    // be non-null with `metadataLoaded == false`, in which case the
    // top-level layout shows the row's basics and the metadata fields fade
    // in once the fetch completes.
    var isFetchingMetadata by remember(streamId, playlistId) { mutableStateOf(false) }
    var fetchError by remember(streamId, playlistId) { mutableStateOf<String?>(null) }

    // Trigger the fetch once we know both the playlist + the row + the row
    // has never been enriched. iOS does this in `.task { fetchMovieInfo() }`.
    LaunchedEffect(playlist?.id, movie?.streamId, movie?.metadataLoaded) {
        val pl = playlist ?: return@LaunchedEffect
        val current = movie ?: return@LaunchedEffect
        if (current.metadataLoaded || isFetchingMetadata) return@LaunchedEffect
        isFetchingMetadata = true
        fetchError = null
        try {
            val client = XtreamApiClient(pl)
            val response = client.getVODInfo(current.streamId)
            val info = response.info
            if (info != null) {
                vodRepository.applyInfo(current.streamId, pl.id, info)
            } else {
                // No info block — still flip the flag so we don't retry on
                // every recomposition. iOS does the same.
                vodRepository.applyInfo(current.streamId, pl.id, dev.android.anotheriptvplayer.networking.XtreamVODInfo())
            }
        } catch (e: Throwable) {
            Log.w(TAG, "getVODInfo failed", e)
            fetchError = e.message
        } finally {
            isFetchingMetadata = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = movie?.name ?: "",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        scope.launch {
                            favoriteRepository.setFavorite(
                                streamId = streamId,
                                playlistId = playlistId,
                                type = FavoriteRepository.Type.VOD,
                                favorite = !isFavorite,
                            )
                        }
                    }) {
                        Icon(
                            imageVector = if (isFavorite) Icons.Default.Star else Icons.Default.StarBorder,
                            contentDescription = if (isFavorite) androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_favorite_remove) else androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_favorite_add),
                            tint = if (isFavorite) Color(0xFFFFC107) else MaterialTheme.colorScheme.onSurface,
                        )
                    }
                },
                // Transparent app bar so the hero's backdrop bleeds under
                // the top inset. The title fades in from the row name.
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                ),
            )
        },
        // Edge-to-edge — the hero draws through the top inset.
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { _ ->
        when {
            movie == null && fetchError != null -> ErrorState(
                message = fetchError ?: "Bilinmeyen hata",
            )
            movie == null -> LoadingState(message = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_loading_movie))
            else -> {
                val pl = playlist
                MovieDetailContent(
                    movie = movie!!,
                    playlist = pl,
                    onWatch = {
                        if (pl == null) return@MovieDetailContent
                        onPlay()
                    },
                    onTrailer = { trailerUrl ->
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(trailerUrl)),
                            )
                        }.onFailure {
                            Toast.makeText(
                                context,
                                context.getString(dev.android.anotheriptvplayer.R.string.detail_trailer_failed),
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun MovieDetailContent(
    movie: dev.android.anotheriptvplayer.data.local.VodStreamEntity,
    playlist: Playlist?,
    onWatch: () -> Unit,
    onTrailer: (String) -> Unit,
) {
    val rating10 = movie.rating5Based?.let { it * 2 }
    val heroConfig = DetailHeroConfig(
        title = movie.name,
        backdropUrl = movie.backdropPath,
        posterUrl = movie.streamIcon,
        year = DetailFormatting.year(movie.releaseDate),
        runtime = movie.duration?.trim()?.takeIf { it.isNotEmpty() },
        rating10 = rating10,
        ratingText = movie.rating,
        placeholderIcon = Icons.Default.Movie,
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        DetailHero(config = heroConfig)

        val genres = DetailFormatting.genreList(movie.genre)
        if (genres.isNotEmpty()) {
            GenreChipRow(genres = genres)
        }

        DetailActionBar(
            primaryTitle = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_watch),
            onPrimary = { onWatch() },
            primaryIcon = Icons.Default.PlayArrow,
            trailerTitle = movie.youtubeTrailer.normaliseTrailerUrl()?.let { "Fragman" },
            onTrailer = movie.youtubeTrailer.normaliseTrailerUrl()?.let { url -> { onTrailer(url) } },
        )

        val plot = movie.plot?.trim().orEmpty()
        if (plot.isNotEmpty()) {
            DetailPlotBlock(plot = plot)
        }

        val director = movie.director?.trim().orEmpty()
        if (director.isNotEmpty()) {
            DetailInfoTextBlock(label = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_director), value = director)
        }

        val cast = movie.cast?.trim().orEmpty()
        if (cast.isNotEmpty()) {
            DetailInfoTextBlock(label = "Oyuncular", value = cast, maxLines = 3)
        }

        // Show a hint when playlist hasn't loaded yet (very brief; usually
        // it lands before the user sees this).
        if (playlist == null) {
            Text(
                text = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_loading_playlist),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

/**
 * iOS accepts both a raw video id (`xyz123`) and a full URL for the
 * trailer column. Mirror that: prepend `https://www.youtube.com/watch?v=`
 * if it looks like just an id.
 */
private fun String?.normaliseTrailerUrl(): String? {
    val raw = this?.trim().orEmpty()
    if (raw.isEmpty()) return null
    return if (raw.startsWith("http", ignoreCase = true)) {
        raw
    } else {
        "https://www.youtube.com/watch?v=$raw"
    }
}

@Composable
private fun LoadingState(message: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(Modifier.height(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ErrorState(message: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            Icon(
                imageVector = Icons.Default.ErrorOutline,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(48.dp),
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

private const val TAG = "MovieDetailScreen"
