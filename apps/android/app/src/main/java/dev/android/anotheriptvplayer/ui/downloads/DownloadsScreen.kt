package dev.android.anotheriptvplayer.ui.downloads

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DownloadDone
import androidx.compose.material.icons.filled.Downloading
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Schedule
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
import dev.android.anotheriptvplayer.data.local.DownloadedItemEntity
import kotlinx.coroutines.launch

/**
 * Lists every download row for a single playlist. iOS counterpart:
 * `DownloadsView`.
 *
 * Status mapping:
 *  - `queued` → clock icon (waiting on WorkManager constraints / queue slot)
 *  - `downloading` → spinner + progress bar
 *  - `completed` → check mark + cloud-done
 *  - `failed` → error icon + tap-to-retry
 *
 * Delete swipes the row out and removes the file via [DownloadManager.delete].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadsScreen(
    playlistId: String,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    val manager = app.downloadManager
    val scope = rememberCoroutineScope()

    val rows by manager.observeAll(playlistId).collectAsState(initial = emptyList())

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_downloads)) },
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
            Box(
                modifier = Modifier.fillMaxSize().padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = stringResource(R.string.empty_no_downloads),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                horizontal = 16.dp,
                vertical = 8.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(rows, key = { it.id }) { row ->
                DownloadRow(
                    row = row,
                    onCancel = { manager.cancel(row.id) },
                    onDelete = { scope.launch { manager.delete(row.id) } },
                )
            }
        }
    }
}

@Composable
private fun DownloadRow(
    row: DownloadedItemEntity,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                row.imageUrl?.takeIf { it.isNotBlank() }?.let {
                    AsyncImage(
                        model = it,
                        contentDescription = null,
                        modifier = Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.surface),
                    )
                    Spacer(Modifier.width(12.dp))
                }
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
                StatusIcon(row.status)
            }
            if (row.status == "downloading") {
                val fraction = if (row.totalBytes > 0) {
                    (row.downloadedBytes.toFloat() / row.totalBytes.toFloat()).coerceIn(0f, 1f)
                } else 0f
                LinearProgressIndicator(
                    progress = { if (row.totalBytes > 0) fraction else 0f },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (row.status == "failed") {
                row.errorMessage?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
            Row(
                horizontalArrangement = Arrangement.End,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (row.status == "downloading" || row.status == "queued") {
                    IconButton(onClick = onCancel) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = stringResource(R.string.download_cancel),
                        )
                    }
                } else {
                    IconButton(onClick = onDelete) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = stringResource(R.string.common_delete),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusIcon(status: String) {
    val (icon, tint, labelRes) = when (status) {
        "queued" -> Triple(Icons.Default.Schedule, MaterialTheme.colorScheme.onSurfaceVariant, R.string.download_status_queued)
        "downloading" -> Triple(Icons.Default.Downloading, MaterialTheme.colorScheme.primary, R.string.download_status_downloading)
        "completed" -> Triple(Icons.Default.DownloadDone, MaterialTheme.colorScheme.primary, R.string.download_status_completed)
        "failed" -> Triple(Icons.Default.ErrorOutline, MaterialTheme.colorScheme.error, R.string.download_status_failed)
        else -> Triple(Icons.Default.CloudDone, MaterialTheme.colorScheme.onSurfaceVariant, R.string.common_loading)
    }
    Icon(icon, contentDescription = stringResource(labelRes), tint = tint)
}
