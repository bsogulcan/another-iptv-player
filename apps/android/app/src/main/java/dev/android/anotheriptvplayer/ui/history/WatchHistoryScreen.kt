package dev.android.anotheriptvplayer.ui.history

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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
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
import dev.android.anotheriptvplayer.data.local.WatchHistoryEntity
import kotlinx.coroutines.launch

/**
 * Recently-watched list. Mirrors iOS `WatchHistoryListView`.
 *
 * Rows show the same metadata the dashboard's Continue Watching row uses —
 * title, secondary title, image — plus a linear progress bar driven by
 * `lastTimeMs / durationMs`. Tap a row to resume; long-press swipe deletes.
 *
 * The DAO returns rows ordered by `lastWatchedAt DESC`; we cap the list at
 * 200 because beyond that the user is better served by Search.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchHistoryScreen(
    playlistId: String,
    onBack: () -> Unit,
    onResumeMovie: (streamId: Int) -> Unit,
    onResumeSeries: (episodeId: String) -> Unit,
    onPlayLive: (streamId: Int) -> Unit,
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    val dao = app.appDatabaseForDownloads.watchHistoryDao()
    val scope = rememberCoroutineScope()
    val rows by dao.observeRecent(playlistId, limit = 200).collectAsState(initial = emptyList())

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_watch_history)) },
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
        if (rows.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                Text(
                    stringResource(R.string.empty_no_history),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(rows, key = { it.id }) { row ->
                HistoryRow(
                    row = row,
                    onClick = {
                        when (row.type) {
                            "vod" -> row.streamId.toIntOrNull()?.let(onResumeMovie)
                            "series" -> onResumeSeries(row.streamId)
                            "live" -> row.streamId.toIntOrNull()?.let(onPlayLive)
                        }
                    },
                    onDelete = { scope.launch { dao.deleteById(row.id) } },
                )
            }
        }
    }
}

@Composable
private fun HistoryRow(
    row: WatchHistoryEntity,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val image = row.imageUrl
                if (image.isNullOrBlank()) {
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.surface),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = when (row.type) {
                                "live" -> Icons.Default.LiveTv
                                "series" -> Icons.Default.Tv
                                else -> Icons.Default.Movie
                            },
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
                        text = row.title,
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    row.secondaryTitle?.takeIf { it.isNotBlank() }?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = stringResource(R.string.common_delete),
                    )
                }
            }
            if (row.durationMs > 0L && row.type != "live") {
                val frac = (row.lastTimeMs.toFloat() / row.durationMs.toFloat()).coerceIn(0f, 1f)
                LinearProgressIndicator(progress = { frac }, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}
