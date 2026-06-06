package dev.android.anotheriptvplayer.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import dev.android.anotheriptvplayer.data.local.VodStreamWithCategory

/**
 * "Yeni eklenenler" rail — VODs ordered by `vodStream.added` desc.
 * iOS counterpart: `RecentlyAddedRow`. Hidden when the underlying query
 * returns an empty list (e.g. a freshly-imported catalog without `added`
 * timestamps).
 */
@Composable
fun RecentlyAddedShelf(
    playlistId: String,
    onOpenMovie: (Int) -> Unit,
    modifier: Modifier = Modifier,
    limit: Int = 30,
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    var rows by remember(playlistId) { mutableStateOf<List<VodStreamWithCategory>>(emptyList()) }
    LaunchedEffect(playlistId) {
        rows = runCatching {
            app.appDatabaseForDownloads.vodStreamDao().recentlyAdded(playlistId, limit)
        }.getOrDefault(emptyList())
    }
    if (rows.isEmpty()) return

    Column(modifier = modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text(
            text = stringResource(R.string.shelf_recently_added),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(rows, key = { it.id }) { row ->
                RecentlyAddedCard(row = row, onClick = { onOpenMovie(row.stream.streamId) })
            }
        }
    }
}

@Composable
private fun RecentlyAddedCard(row: VodStreamWithCategory, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .width(110.dp)
            .clickable(onClick = onClick),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(150.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            row.stream.streamIcon?.takeIf { it.isNotBlank() }?.let {
                AsyncImage(model = it, contentDescription = null, modifier = Modifier.fillMaxSize())
            } ?: Icon(
                imageVector = Icons.Default.Movie,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp),
            )
        }
        Text(
            text = row.stream.name,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
