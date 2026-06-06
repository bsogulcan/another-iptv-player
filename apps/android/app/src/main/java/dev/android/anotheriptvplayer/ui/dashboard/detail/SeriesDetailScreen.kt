package dev.android.anotheriptvplayer.ui.dashboard.detail

import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Tv
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.android.anotheriptvplayer.data.FavoriteRepository
import dev.android.anotheriptvplayer.data.local.EpisodeEntity
import dev.android.anotheriptvplayer.data.local.SeasonEntity
import dev.android.anotheriptvplayer.data.local.SeriesEntity
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.networking.XtreamApiClient
import dev.android.anotheriptvplayer.ui.LocalFavoriteRepository
import dev.android.anotheriptvplayer.ui.LocalPlaylistRepository
import dev.android.anotheriptvplayer.ui.LocalSeriesRepository
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch

/**
 * Kotlin port of iOS `SeriesDetailView`.
 *
 * Reactively reads the series row and its seasons from SQLite. On first
 * entry, if `seasonsLoaded == false`, kicks off `get_series_info` and
 * merges seasons + episodes + series metadata in a single Room transaction
 * (see `SeriesRepository.applyInfo`). Episodes for the selected season are
 * a separate Flow so picking a new season just swaps the subscription.
 *
 * Tapping an episode navigates into the native `PlayerScreen` (kind
 * `SERIES_EPISODE`); the global "İzle" plays the first episode of the
 * first season the same way.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesDetailScreen(
    playlistId: String,
    seriesId: Int,
    onBack: () -> Unit,
    onPlayEpisode: (episodeId: String) -> Unit,
) {
    val context = LocalContext.current
    val playlistRepository = LocalPlaylistRepository.current
    val seriesRepository = LocalSeriesRepository.current
    val favoriteRepository = LocalFavoriteRepository.current
    val scope = rememberCoroutineScope()

    val isFavorite by favoriteRepository.observeIsFavorite(seriesId, playlistId, FavoriteRepository.Type.SERIES)
        .collectAsStateWithLifecycle(initialValue = false)

    var playlist by remember(playlistId) { mutableStateOf<Playlist?>(null) }
    LaunchedEffect(playlistId) {
        playlist = playlistRepository.find(playlistId)
    }

    val series by seriesRepository.observeSeries(seriesId, playlistId)
        .collectAsStateWithLifecycle(initialValue = null)
    val seasons by seriesRepository.observeSeasons(seriesId, playlistId)
        .collectAsStateWithLifecycle(initialValue = emptyList())

    var selectedSeasonId by remember(seriesId, playlistId) { mutableStateOf<String?>(null) }
    LaunchedEffect(seasons) {
        // Pick the first season once the list lands. iOS picks the season
        // containing the most-recently-watched episode; that lookup needs
        // watch-history queries which haven't been ported yet, so the
        // simpler iOS fallback (first season) is what we do today.
        if (selectedSeasonId == null) {
            selectedSeasonId = seasons.firstOrNull()?.id
        } else if (seasons.none { it.id == selectedSeasonId }) {
            // Seasons reshuffled after a re-sync — fall back to the first.
            selectedSeasonId = seasons.firstOrNull()?.id
        }
    }

    val episodes by remember(selectedSeasonId) {
        selectedSeasonId?.let { seriesRepository.observeEpisodes(it) } ?: flowOf(emptyList())
    }.collectAsStateWithLifecycle(initialValue = emptyList())

    var isFetchingInfo by remember(seriesId, playlistId) { mutableStateOf(false) }
    var fetchError by remember(seriesId, playlistId) { mutableStateOf<String?>(null) }

    LaunchedEffect(playlist?.id, series?.seriesId, series?.seasonsLoaded) {
        val pl = playlist ?: return@LaunchedEffect
        val current = series ?: return@LaunchedEffect
        if (current.seasonsLoaded || isFetchingInfo) return@LaunchedEffect
        isFetchingInfo = true
        fetchError = null
        try {
            val client = XtreamApiClient(pl)
            val info = client.getSeriesInfo(current.seriesId)
            seriesRepository.applyInfo(current.seriesId, pl.id, info)
        } catch (e: Throwable) {
            Log.w(TAG, "getSeriesInfo failed", e)
            fetchError = e.message
        } finally {
            isFetchingInfo = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = series?.name ?: "",
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
                                streamId = seriesId,
                                playlistId = playlistId,
                                type = FavoriteRepository.Type.SERIES,
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
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                ),
            )
        },
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { _ ->
        when {
            series == null && fetchError != null -> ErrorState(message = fetchError ?: "Bilinmeyen hata")
            series == null -> LoadingState(message = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_loading_series))
            else -> {
                val pl = playlist
                SeriesDetailContent(
                    series = series!!,
                    playlist = pl,
                    seasons = seasons,
                    selectedSeasonId = selectedSeasonId,
                    onSelectSeason = { selectedSeasonId = it },
                    episodes = episodes,
                    seasonsLoading = isFetchingInfo,
                    onWatchFirst = {
                        val first = seasons.firstOrNull() ?: return@SeriesDetailContent
                        scope.launch {
                            val ep = seriesRepository.firstEpisodeInSeason(first.id) ?: return@launch
                            onPlayEpisode(ep.id)
                        }
                    },
                    onPlayEpisode = { ep -> onPlayEpisode(ep.id) },
                    onTrailer = { trailerUrl ->
                        runCatching {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(trailerUrl)))
                        }.onFailure {
                            Toast.makeText(context, context.getString(dev.android.anotheriptvplayer.R.string.detail_trailer_failed), Toast.LENGTH_SHORT).show()
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun SeriesDetailContent(
    series: SeriesEntity,
    playlist: Playlist?,
    seasons: List<SeasonEntity>,
    selectedSeasonId: String?,
    onSelectSeason: (String) -> Unit,
    episodes: List<EpisodeEntity>,
    seasonsLoading: Boolean,
    onWatchFirst: () -> Unit,
    onPlayEpisode: (EpisodeEntity) -> Unit,
    onTrailer: (String) -> Unit,
) {
    val rating10 = series.rating5Based?.let { it * 2 }
    val heroConfig = DetailHeroConfig(
        title = series.name,
        backdropUrl = series.backdropPath,
        posterUrl = series.cover,
        year = DetailFormatting.year(series.releaseDate),
        runtime = DetailFormatting.seriesRuntime(series.episodeRunTime),
        rating10 = rating10,
        ratingText = series.rating,
        placeholderIcon = Icons.Default.Tv,
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        DetailHero(config = heroConfig)

        val genres = DetailFormatting.genreList(series.genre)
        if (genres.isNotEmpty()) {
            GenreChipRow(genres = genres)
        }

        DetailActionBar(
            primaryTitle = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_watch),
            onPrimary = onWatchFirst,
            primaryIcon = Icons.Default.PlayArrow,
            trailerTitle = series.youtubeTrailer.normaliseTrailer()?.let { "Fragman" },
            onTrailer = series.youtubeTrailer.normaliseTrailer()?.let { url -> { onTrailer(url) } },
        )

        val plot = series.plot?.trim().orEmpty()
        if (plot.isNotEmpty()) {
            DetailPlotBlock(plot = plot)
        }

        val director = series.director?.trim().orEmpty()
        if (director.isNotEmpty()) {
            DetailInfoTextBlock(label = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_director), value = director)
        }

        val cast = series.cast?.trim().orEmpty()
        if (cast.isNotEmpty()) {
            DetailInfoTextBlock(label = "Oyuncular", value = cast, maxLines = 3)
        }

        // Seasons section.
        SeasonsSection(
            series = series,
            seasons = seasons,
            selectedSeasonId = selectedSeasonId,
            onSelectSeason = onSelectSeason,
            episodes = episodes,
            seasonsLoading = seasonsLoading,
            onPlayEpisode = onPlayEpisode,
        )

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

@Composable
private fun SeasonsSection(
    series: SeriesEntity,
    seasons: List<SeasonEntity>,
    selectedSeasonId: String?,
    onSelectSeason: (String) -> Unit,
    episodes: List<EpisodeEntity>,
    seasonsLoading: Boolean,
    onPlayEpisode: (EpisodeEntity) -> Unit,
) {
    if (seasons.isEmpty()) {
        val message = if (series.seasonsLoaded) {
            androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_no_seasons)
        } else if (seasonsLoading) {
            androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_seasons_loading)
        } else {
            androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_seasons_failed)
        }
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
        )
        return
    }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Sezonlar",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
            )
            val selected = seasons.firstOrNull { it.id == selectedSeasonId }
            selected?.episodeCount?.let { count ->
                Text(
                    text = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_episode_count_format, count),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        SeasonTabBar(
            seasons = seasons,
            selectedId = selectedSeasonId,
            onSelect = onSelectSeason,
        )

        val selected = seasons.firstOrNull { it.id == selectedSeasonId }
        val overview = selected?.overview?.trim().orEmpty()
        if (overview.isNotEmpty()) {
            Text(
                text = overview,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }

        EpisodeList(episodes = episodes, onPlay = onPlayEpisode)
    }
}

// ---- Helpers ----

private fun String?.normaliseTrailer(): String? {
    val raw = this?.trim().orEmpty()
    if (raw.isEmpty()) return null
    return if (raw.startsWith("http", ignoreCase = true)) raw
    else "https://www.youtube.com/watch?v=$raw"
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

private const val TAG = "SeriesDetailScreen"
