package dev.android.anotheriptvplayer.ui.favorites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.android.anotheriptvplayer.ui.LocalFavoriteRepository
import dev.android.anotheriptvplayer.ui.dashboard.ImageKind
import androidx.compose.ui.res.stringResource
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.ui.dashboard.LiveStreamCard
import dev.android.anotheriptvplayer.ui.dashboard.PosterCard

/** Per-tab type for the segmented switcher. */
enum class FavoriteType(val key: String, val labelRes: Int, val icon: ImageVector) {
    LIVE("live", R.string.search_type_live, Icons.Default.LiveTv),
    VOD("vod", R.string.settings_vod_count, Icons.Default.Movie),
    SERIES("series", R.string.settings_series_count, Icons.Default.Tv);

    companion object {
        fun fromKey(key: String?): FavoriteType = entries.firstOrNull { it.key == key } ?: VOD
    }
}

/**
 * Kotlin port of iOS `FavoritesView`.
 *
 * Segmented switcher (Canlı / Film / Dizi) plus a grid for the active
 * segment. Each grid pulls a Flow from [dev.android.anotheriptvplayer.data.FavoriteRepository]
 * — Room auto-refreshes when the user toggles a favorite from any detail
 * screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(
    playlistId: String,
    initialType: String,
    onBack: () -> Unit,
    onOpenMovie: (Int) -> Unit,
    onOpenSeries: (Int) -> Unit,
    onPlayLive: (streamId: Int) -> Unit,
) {
    val favoriteRepository = LocalFavoriteRepository.current

    var selected by remember(initialType) { mutableStateOf(FavoriteType.fromKey(initialType)) }

    val liveFavs by favoriteRepository.observeLive(playlistId)
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val vodFavs by favoriteRepository.observeVod(playlistId)
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val seriesFavs by favoriteRepository.observeSeries(playlistId)
        .collectAsStateWithLifecycle(initialValue = emptyList())

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_favorites)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.common_back),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            FavoriteTypeSegmentedButtons(
                selected = selected,
                onSelect = { selected = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            )

            when (selected) {
                FavoriteType.LIVE -> {
                    if (liveFavs.isEmpty()) {
                        EmptyState(icon = Icons.Default.LiveTv, message = stringResource(R.string.empty_favorites_live))
                    } else {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(110.dp),
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            items(liveFavs.size, key = { idx -> "live_${liveFavs[idx].id}" }) { idx ->
                                val row = liveFavs[idx]
                                LiveStreamCard(
                                    name = row.stream.name,
                                    iconUrl = row.stream.streamIcon,
                                    onClick = { onPlayLive(row.stream.streamId) },
                                )
                            }
                        }
                    }
                }
                FavoriteType.VOD -> {
                    if (vodFavs.isEmpty()) {
                        EmptyState(icon = Icons.Default.Movie, message = stringResource(R.string.empty_favorites_vod))
                    } else {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(110.dp),
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            items(vodFavs.size, key = { idx -> "vod_${vodFavs[idx].id}" }) { idx ->
                                val row = vodFavs[idx]
                                PosterCard(
                                    name = row.stream.name,
                                    coverUrl = row.stream.streamIcon,
                                    kind = ImageKind.Movie,
                                    onClick = { onOpenMovie(row.stream.streamId) },
                                )
                            }
                        }
                    }
                }
                FavoriteType.SERIES -> {
                    if (seriesFavs.isEmpty()) {
                        EmptyState(icon = Icons.Default.Tv, message = stringResource(R.string.empty_favorites_series))
                    } else {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(110.dp),
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            items(seriesFavs.size, key = { idx -> "series_${seriesFavs[idx].id}" }) { idx ->
                                val row = seriesFavs[idx]
                                PosterCard(
                                    name = row.series.name,
                                    coverUrl = row.series.cover,
                                    kind = ImageKind.Series,
                                    onClick = { onOpenSeries(row.series.seriesId) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FavoriteTypeSegmentedButtons(
    selected: FavoriteType,
    onSelect: (FavoriteType) -> Unit,
    modifier: Modifier = Modifier,
) {
    val all = FavoriteType.entries
    SingleChoiceSegmentedButtonRow(modifier = modifier) {
        all.forEachIndexed { index, type ->
            SegmentedButton(
                shape = SegmentedButtonDefaults.itemShape(index = index, count = all.size),
                selected = type == selected,
                onClick = { onSelect(type) },
                icon = { Icon(type.icon, contentDescription = null) },
                label = { Text(stringResource(type.labelRes)) },
            )
        }
    }
}

@Composable
private fun EmptyState(icon: ImageVector, message: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(32.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(48.dp),
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
