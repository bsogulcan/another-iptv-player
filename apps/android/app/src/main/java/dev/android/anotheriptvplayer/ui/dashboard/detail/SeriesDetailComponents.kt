package dev.android.anotheriptvplayer.ui.dashboard.detail

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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import dev.android.anotheriptvplayer.data.local.EpisodeEntity
import dev.android.anotheriptvplayer.data.local.SeasonEntity

/**
 * Series-specific detail-screen components. Kotlin ports of iOS
 * `DetailSeasonTabBar`, `EpisodesPanel`, and `EpisodeDetailRow`.
 */

// ---- Season tab bar ----

@Composable
fun SeasonTabBar(
    seasons: List<SeasonEntity>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(seasons, key = { it.id }) { season ->
            val isSelected = season.id == selectedId
            val container = if (isSelected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            }
            val labelColor = if (isSelected) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurface
            }
            Text(
                text = season.name ?: "Sezon ${season.seasonNumber}",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = labelColor,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(container)
                    .clickable { onSelect(season.id) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

// ---- Episode list ----

/**
 * Stack of episode rows for a single season. Inserts a divider between
 * rows like iOS `EpisodesPanel`.
 */
@Composable
fun EpisodeList(
    episodes: List<EpisodeEntity>,
    onPlay: (EpisodeEntity) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (episodes.isEmpty()) {
        Text(
            text = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.detail_no_episodes),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = modifier.padding(horizontal = 16.dp),
        )
        return
    }
    Column(modifier = modifier.fillMaxWidth()) {
        episodes.forEachIndexed { index, ep ->
            EpisodeRow(
                episode = ep,
                onPlay = { onPlay(ep) },
            )
            if (index < episodes.lastIndex) {
                HorizontalDivider(
                    modifier = Modifier.padding(start = THUMB_WIDTH + 28.dp),
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.18f),
                )
            }
        }
    }
}

private val THUMB_WIDTH = 132.dp
private val THUMB_HEIGHT = 76.dp // ~16:9

@Composable
private fun EpisodeRow(
    episode: EpisodeEntity,
    onPlay: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onPlay)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        EpisodeThumbnail(url = episode.cover)
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = formatEpisodeTitle(
                    episode = episode,
                    fallbackTitle = androidx.compose.ui.res.stringResource(
                        dev.android.anotheriptvplayer.R.string.detail_episode_default,
                    ),
                ),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            EpisodeMetaRow(episode = episode)
            val plot = episode.info?.trim().orEmpty()
            if (plot.isNotEmpty()) {
                Text(
                    text = plot,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 5,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun EpisodeThumbnail(url: String?) {
    Box(
        modifier = Modifier
            .width(THUMB_WIDTH)
            .height(THUMB_HEIGHT)
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Default.PlayCircleOutline,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
            modifier = Modifier.size(32.dp),
        )
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = url,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        }
    }
}

@Composable
private fun EpisodeMetaRow(episode: EpisodeEntity) {
    val duration = episode.duration?.trim().orEmpty()
    val rating = episode.rating?.trim().orEmpty()
    if (duration.isEmpty() && rating.isEmpty()) return
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (duration.isNotEmpty()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = null,
                    modifier = Modifier.size(12.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = duration,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (rating.isNotEmpty()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Star,
                    contentDescription = null,
                    modifier = Modifier.size(12.dp),
                    tint = Color(0xFFFFC107),
                )
                Text(
                    text = rating,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** `"3. Bölüm Adı"` style — matches iOS `episodeTitle`. */
private fun formatEpisodeTitle(
    episode: EpisodeEntity,
    fallbackTitle: String = "Episode",
): String {
    val numPrefix = episode.episodeNum?.let { "$it. " }.orEmpty()
    val raw = episode.title?.trim().orEmpty()
    val title = if (raw.isEmpty()) fallbackTitle else raw
    return "$numPrefix$title"
}
