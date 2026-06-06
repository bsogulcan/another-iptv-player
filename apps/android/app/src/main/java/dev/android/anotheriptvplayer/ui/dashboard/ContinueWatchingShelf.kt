package dev.android.anotheriptvplayer.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import coil.compose.AsyncImage
import dev.android.anotheriptvplayer.AnotherIptvPlayerApp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.data.local.WatchHistoryEntity

/**
 * Horizontal "Continue Watching" rail. Mirrors iOS `ContinueWatchingRow`.
 *
 * Lives at the top of the Live/VOD dashboards (and the M3U dashboard's
 * header). Hidden when the underlying watchHistory table is empty so the
 * tab body doesn't get pushed down for nothing.
 */
@Composable
fun ContinueWatchingShelf(
    playlistId: String,
    onResumeMovie: (streamId: Int) -> Unit,
    onResumeSeries: (episodeId: String) -> Unit,
    onPlayLive: (streamId: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    val rows by app.appDatabaseForDownloads
        .watchHistoryDao()
        .observeRecent(playlistId, limit = 20)
        .collectAsState(initial = emptyList())

    if (rows.isEmpty()) return

    Column(modifier = modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text(
            text = stringResource(R.string.shelf_continue_watching),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(rows, key = { it.id }) { row ->
                ContinueWatchingCard(row = row, onClick = {
                    when (row.type) {
                        "vod" -> row.streamId.toIntOrNull()?.let(onResumeMovie)
                        "series" -> onResumeSeries(row.streamId)
                        "live" -> row.streamId.toIntOrNull()?.let(onPlayLive)
                    }
                })
            }
        }
    }
}

@Composable
private fun ContinueWatchingCard(row: WatchHistoryEntity, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .width(140.dp)
            .clickable(onClick = onClick),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(80.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            row.imageUrl?.takeIf { it.isNotBlank() }?.let {
                AsyncImage(model = it, contentDescription = null, modifier = Modifier.fillMaxSize())
            } ?: Icon(
                imageVector = when (row.type) {
                    "live" -> Icons.Default.LiveTv
                    "series" -> Icons.Default.Tv
                    else -> Icons.Default.Movie
                },
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp),
            )
            if (row.durationMs > 0L && row.type != "live") {
                val frac = (row.lastTimeMs.toFloat() / row.durationMs.toFloat()).coerceIn(0f, 1f)
                LinearProgressIndicator(
                    progress = { frac },
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .height(3.dp),
                )
            }
        }
        Text(
            text = row.title,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        row.secondaryTitle?.takeIf { it.isNotBlank() }?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
