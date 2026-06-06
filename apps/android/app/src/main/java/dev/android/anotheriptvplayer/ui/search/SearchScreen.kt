package dev.android.anotheriptvplayer.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import dev.android.anotheriptvplayer.AnotherIptvPlayerApp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.data.CatalogTextSearch
import dev.android.anotheriptvplayer.data.CatalogTextSearch.normalize
import dev.android.anotheriptvplayer.model.PlaylistKind
import dev.android.anotheriptvplayer.ui.LocalPlaylistContentStore
import dev.android.anotheriptvplayer.ui.LocalPlaylistRepository

/**
 * Global search across the active playlist. Mirrors iOS `SearchView`.
 *
 * Xtream playlists search live + VOD + series; M3U playlists search the
 * single channel list. Matching uses [CatalogTextSearch.matches] so the
 * Turkish-locale normalisation lines up with what the dashboards do.
 *
 * Results are flat (no per-type grouping yet) and ordered by exact → prefix
 * → alphabetic, the same relevance contract iOS uses.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    playlistId: String,
    onBack: () -> Unit,
    onOpenLive: (streamId: Int) -> Unit,
    onOpenMovie: (streamId: Int) -> Unit,
    onOpenSeries: (seriesId: Int) -> Unit,
    onPlayM3uChannel: (channelId: String) -> Unit,
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    val repository = LocalPlaylistRepository.current
    val xtreamStore = LocalPlaylistContentStore.current
    val m3uStore = app.m3uContentStore

    var query by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf<PlaylistKind?>(null) }

    LaunchedEffect(playlistId) {
        kind = repository.find(playlistId)?.kind
    }

    val xtreamLive by xtreamStore.liveStreams.collectAsState()
    val xtreamVod by xtreamStore.vodStreams.collectAsState()
    val xtreamSeries by xtreamStore.seriesItems.collectAsState()
    val m3uChannels by m3uStore.channels.collectAsState()

    val resultsState = remember(query, kind, xtreamLive, xtreamVod, xtreamSeries, m3uChannels) {
        derivedStateOf<List<SearchHit>> {
            if (query.isBlank()) emptyList()
            else when (kind) {
                PlaylistKind.M3U -> m3uChannels
                    .filter { CatalogTextSearch.matches(query, it.name) }
                    .sortedWith(relevance(query) { it.name })
                    .take(200)
                    .map { SearchHit.M3u(it.id, it.name, it.tvgLogo, it.groupTitle) }
                PlaylistKind.XTREAM -> {
                    val list = mutableListOf<SearchHit>()
                    list += xtreamLive
                        .filter { CatalogTextSearch.matches(query, it.stream.name) }
                        .sortedWith(relevance(query) { it.stream.name })
                        .take(80)
                        .map { SearchHit.Live(it.stream.streamId, it.stream.name, it.stream.streamIcon, it.categoryName) }
                    list += xtreamVod
                        .filter { CatalogTextSearch.matches(query, it.stream.name) }
                        .sortedWith(relevance(query) { it.stream.name })
                        .take(80)
                        .map { SearchHit.Movie(it.stream.streamId, it.stream.name, it.stream.streamIcon, it.categoryName) }
                    list += xtreamSeries
                        .filter { CatalogTextSearch.matches(query, it.series.name) }
                        .sortedWith(relevance(query) { it.series.name })
                        .take(80)
                        .map { SearchHit.Series(it.series.seriesId, it.series.name, it.series.cover, it.categoryName) }
                    list
                }
                else -> emptyList()
            }
        }
    }
    val results = resultsState.value

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_search)) },
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
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text(stringResource(R.string.common_search) + "…") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (query.isBlank()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        stringResource(R.string.empty_search_idle),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else if (results.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        stringResource(R.string.empty_search_no_results),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    items(results, key = { hit -> hit.key }) { hit ->
                        SearchRow(hit, onClick = {
                            when (hit) {
                                is SearchHit.Live -> onOpenLive(hit.id)
                                is SearchHit.Movie -> onOpenMovie(hit.id)
                                is SearchHit.Series -> onOpenSeries(hit.id)
                                is SearchHit.M3u -> onPlayM3uChannel(hit.channelId)
                            }
                        })
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchRow(hit: SearchHit, onClick: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val image = hit.image
            if (image.isNullOrBlank()) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surface),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = hit.icon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                AsyncImage(
                    model = image,
                    contentDescription = null,
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surface),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = hit.title,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "${hit.typeLabel} · ${hit.subtitle ?: ""}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

private fun <T> relevance(query: String, name: (T) -> String): Comparator<T> {
    val nq = normalize(query)
    return compareByDescending<T> { CatalogTextSearch.equals(name(it), query) }
        .thenByDescending { normalize(name(it)).startsWith(nq) }
        .thenBy { normalize(name(it)) }
}

private sealed class SearchHit(
    val key: String,
    val title: String,
    val image: String?,
    val subtitle: String?,
    val typeLabelRes: Int,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    val typeLabel: String
        @Composable get() = stringResource(typeLabelRes)

    class Live(val id: Int, t: String, img: String?, sub: String?) :
        SearchHit("live-$id", t, img, sub, R.string.search_type_live, Icons.Default.LiveTv)
    class Movie(val id: Int, t: String, img: String?, sub: String?) :
        SearchHit("vod-$id", t, img, sub, R.string.settings_vod_count, Icons.Default.Movie)
    class Series(val id: Int, t: String, img: String?, sub: String?) :
        SearchHit("series-$id", t, img, sub, R.string.settings_series_count, Icons.Default.Tv)
    class M3u(val channelId: String, t: String, img: String?, sub: String?) :
        SearchHit("m3u-$channelId", t, img, sub, R.string.screen_m3u_channels, Icons.Default.LiveTv)
}
