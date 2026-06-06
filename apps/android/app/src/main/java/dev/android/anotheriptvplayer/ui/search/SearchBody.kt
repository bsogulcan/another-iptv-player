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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import dev.android.anotheriptvplayer.data.local.LiveStreamWithCategory
import dev.android.anotheriptvplayer.data.local.SeriesWithCategory
import dev.android.anotheriptvplayer.data.local.VodStreamWithCategory
import dev.android.anotheriptvplayer.ui.LocalHiddenCategoryStore
import dev.android.anotheriptvplayer.ui.LocalPlaylistContentStore
import kotlinx.coroutines.delay

/**
 * Kotlin port of iOS `SearchView` + `SearchResultsView`.
 *
 * Layout: filter chips (Tümü/Canlı/Film/Dizi) on top, search field, then
 * three result sections collapsed to four rows each in "Tümü" view —
 * tapping "X sonuç daha" expands by switching to the single-type filter.
 *
 * Designed as a dashboard tab body — no top bar of its own. Hides
 * results from categories the user has hidden via [LocalHiddenCategoryStore].
 *
 * 250ms debounce + 2-char minimum match the iOS UX so the user doesn't
 * see flicker on every keystroke.
 */
@Composable
fun SearchBody(
    playlistId: String,
    onOpenMovie: (Int) -> Unit,
    onOpenSeries: (Int) -> Unit,
    onPlayLive: (streamId: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val contentStore = LocalPlaylistContentStore.current
    val hiddenStore = LocalHiddenCategoryStore.current

    var query by remember { mutableStateOf("") }
    var debouncedQuery by remember { mutableStateOf("") }
    LaunchedEffect(query) {
        val trimmed = query.trim()
        if (trimmed.length < 2) {
            debouncedQuery = ""
            return@LaunchedEffect
        }
        delay(250)
        debouncedQuery = trimmed
    }

    var filter by remember { mutableStateOf(SearchFilter.ALL) }

    val live by contentStore.liveStreams.collectAsStateWithLifecycle()
    val vod by contentStore.vodStreams.collectAsStateWithLifecycle()
    val series by contentStore.seriesItems.collectAsStateWithLifecycle()

    val hiddenLive by hiddenStore.observeHidden(playlistId, "live").collectAsState(initial = hiddenStore.hiddenIds(playlistId, "live"))
    val hiddenVod by hiddenStore.observeHidden(playlistId, "vod").collectAsState(initial = hiddenStore.hiddenIds(playlistId, "vod"))
    val hiddenSeries by hiddenStore.observeHidden(playlistId, "series").collectAsState(initial = hiddenStore.hiddenIds(playlistId, "series"))

    // derivedStateOf keeps the heavy filter+sort off of every key/scroll —
    // it only recomputes when one of the inputs actually changes.
    val liveResults by remember(live, hiddenLive, debouncedQuery) {
        derivedStateOf {
            if (debouncedQuery.isEmpty()) emptyList()
            else live
                .filter { (it.stream.categoryId ?: "") !in hiddenLive && matchesQuery(debouncedQuery, it.stream.name) }
                .sortedBy { it.stream.name.lowercase() }
        }
    }
    val movieResults by remember(vod, hiddenVod, debouncedQuery) {
        derivedStateOf {
            if (debouncedQuery.isEmpty()) emptyList()
            else vod
                .filter { (it.stream.categoryId ?: "") !in hiddenVod && matchesQuery(debouncedQuery, it.stream.name) }
                .sortedBy { it.stream.name.lowercase() }
        }
    }
    val seriesResults by remember(series, hiddenSeries, debouncedQuery) {
        derivedStateOf {
            if (debouncedQuery.isEmpty()) emptyList()
            else series
                .filter { (it.series.categoryId ?: "") !in hiddenSeries && matchesQuery(debouncedQuery, it.series.name) }
                .sortedBy { it.series.name.lowercase() }
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        FilterChipRow(selected = filter, onSelect = { filter = it })
        SearchField(
            value = query,
            onValueChange = { query = it },
        )

        when {
            debouncedQuery.isEmpty() -> EmptyHint(
                icon = Icons.Default.Search,
                message = if (query.trim().length in 1..1) {
                    androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.search_min_chars)
                } else {
                    androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.empty_search_idle)
                },
            )
            liveResults.isEmpty() && movieResults.isEmpty() && seriesResults.isEmpty() -> EmptyHint(
                icon = Icons.Default.Search,
                message = androidx.compose.ui.res.stringResource(
                    dev.android.anotheriptvplayer.R.string.search_no_results_for,
                    debouncedQuery,
                ),
            )
            else -> ResultsList(
                filter = filter,
                liveResults = liveResults,
                movieResults = movieResults,
                seriesResults = seriesResults,
                onSelectFilter = { filter = it },
                onPlayLive = { row -> onPlayLive(row.stream.streamId) },
                onOpenMovie = onOpenMovie,
                onOpenSeries = onOpenSeries,
            )
        }
    }
}

// ---- Filter chips ----

enum class SearchFilter(val displayNameRes: Int) {
    ALL(dev.android.anotheriptvplayer.R.string.search_type_all),
    LIVE(dev.android.anotheriptvplayer.R.string.search_type_live),
    MOVIES(dev.android.anotheriptvplayer.R.string.screen_movies),
    SERIES(dev.android.anotheriptvplayer.R.string.screen_series),
}

@Composable
private fun FilterChipRow(selected: SearchFilter, onSelect: (SearchFilter) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SearchFilter.entries.forEach { f ->
            val isSelected = f == selected
            val container =
                if (isSelected) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            val labelColor =
                if (isSelected) MaterialTheme.colorScheme.onPrimary
                else MaterialTheme.colorScheme.onSurface
            Text(
                text = androidx.compose.ui.res.stringResource(f.displayNameRes),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                color = labelColor,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(container)
                    .clickable { onSelect(f) }
                    .padding(horizontal = 14.dp, vertical = 7.dp),
            )
        }
    }
}

@Composable
private fun SearchField(value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        placeholder = { Text("Kanal, film veya dizi") },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        trailingIcon = {
            if (value.isNotEmpty()) {
                IconButton(onClick = { onValueChange("") }) {
                    Icon(Icons.Default.Clear, contentDescription = "Temizle")
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(28.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        colors = TextFieldDefaults.colors(
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        ),
    )
}

// ---- Results ----

@Composable
private fun ResultsList(
    filter: SearchFilter,
    liveResults: List<LiveStreamWithCategory>,
    movieResults: List<VodStreamWithCategory>,
    seriesResults: List<SeriesWithCategory>,
    onSelectFilter: (SearchFilter) -> Unit,
    onPlayLive: (LiveStreamWithCategory) -> Unit,
    onOpenMovie: (Int) -> Unit,
    onOpenSeries: (Int) -> Unit,
) {
    val showLive = filter == SearchFilter.ALL || filter == SearchFilter.LIVE
    val showMovies = filter == SearchFilter.ALL || filter == SearchFilter.MOVIES
    val showSeries = filter == SearchFilter.ALL || filter == SearchFilter.SERIES
    val collapseLive = filter == SearchFilter.ALL
    val collapseMovies = filter == SearchFilter.ALL
    val collapseSeries = filter == SearchFilter.ALL

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        if (showLive && liveResults.isNotEmpty()) {
            val visible = if (collapseLive) liveResults.take(COLLAPSED_LIMIT) else liveResults
            item(key = "live_header") {
                SectionHeader(title = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.search_type_live), count = liveResults.size, icon = Icons.Default.LiveTv)
            }
            items(visible, key = { "live_${it.id}" }) { row ->
                ResultRow(
                    name = row.stream.name,
                    subtitle = row.categoryName,
                    iconUrl = row.stream.streamIcon,
                    placeholder = Icons.Default.LiveTv,
                    onClick = { onPlayLive(row) },
                )
            }
            if (collapseLive && liveResults.size > COLLAPSED_LIMIT) {
                item(key = "live_more") {
                    MoreLink(remaining = liveResults.size - COLLAPSED_LIMIT) {
                        onSelectFilter(SearchFilter.LIVE)
                    }
                }
            }
        }
        if (showMovies && movieResults.isNotEmpty()) {
            val visible = if (collapseMovies) movieResults.take(COLLAPSED_LIMIT) else movieResults
            item(key = "vod_header") {
                SectionHeader(title = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.screen_movies), count = movieResults.size, icon = Icons.Default.Movie)
            }
            items(visible, key = { "vod_${it.id}" }) { row ->
                ResultRow(
                    name = row.stream.name,
                    subtitle = row.categoryName,
                    iconUrl = row.stream.streamIcon,
                    placeholder = Icons.Default.Movie,
                    onClick = { onOpenMovie(row.stream.streamId) },
                )
            }
            if (collapseMovies && movieResults.size > COLLAPSED_LIMIT) {
                item(key = "vod_more") {
                    MoreLink(remaining = movieResults.size - COLLAPSED_LIMIT) {
                        onSelectFilter(SearchFilter.MOVIES)
                    }
                }
            }
        }
        if (showSeries && seriesResults.isNotEmpty()) {
            val visible = if (collapseSeries) seriesResults.take(COLLAPSED_LIMIT) else seriesResults
            item(key = "series_header") {
                SectionHeader(title = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.screen_series), count = seriesResults.size, icon = Icons.Default.Tv)
            }
            items(visible, key = { "series_${it.id}" }) { row ->
                ResultRow(
                    name = row.series.name,
                    subtitle = row.categoryName,
                    iconUrl = row.series.cover,
                    placeholder = Icons.Default.Tv,
                    onClick = { onOpenSeries(row.series.seriesId) },
                )
            }
            if (collapseSeries && seriesResults.size > COLLAPSED_LIMIT) {
                item(key = "series_more") {
                    MoreLink(remaining = seriesResults.size - COLLAPSED_LIMIT) {
                        onSelectFilter(SearchFilter.SERIES)
                    }
                }
            }
        }
    }
}

private const val COLLAPSED_LIMIT = 4

@Composable
private fun SectionHeader(title: String, count: Int, icon: ImageVector) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = "$title ($count)",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ResultRow(
    name: String,
    subtitle: String,
    iconUrl: String?,
    placeholder: ImageVector,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = placeholder,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
                modifier = Modifier.size(20.dp),
            )
            if (!iconUrl.isNullOrBlank()) {
                AsyncImage(
                    model = iconUrl,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun MoreLink(remaining: Int, onClick: () -> Unit) {
    Text(
        text = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.search_more_results, remaining),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    )
}

@Composable
private fun EmptyHint(icon: ImageVector, message: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(32.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
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

/**
 * iOS-equivalent: every whitespace-split word in the query must appear
 * somewhere in [text], case-insensitive. Cheap and good enough for
 * catalog text; Turkish-locale folding plugs in later.
 */
private fun matchesQuery(query: String, text: String): Boolean {
    val words = query.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    if (words.isEmpty()) return false
    return words.all { word -> text.contains(word, ignoreCase = true) }
}
