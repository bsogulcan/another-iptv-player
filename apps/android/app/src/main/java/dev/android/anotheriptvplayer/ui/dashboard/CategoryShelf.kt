package dev.android.anotheriptvplayer.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

/**
 * Vertical-list shelf for a single category — mirrors iOS
 * `LiveCategoryShelfRow` / VOD / Series shelves.
 *
 * The header is tappable (eventually opens the full category-detail view);
 * underneath, a horizontal slot ([content]) shows the actual cards. If the
 * category came back from the API but no items are inside it yet, the
 * shelf either reserves vertical space (during phase 2 of loading) or
 * shows an "empty" hint.
 *
 * [content] is left as a slot so the same shelf renders both
 * [LiveStreamCard] (square logos) and [PosterCard] (2:3 posters).
 */
@Composable
fun CategoryShelf(
    title: String,
    itemCount: Int,
    streamsLoading: Boolean,
    modifier: Modifier = Modifier,
    onHeaderClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = if (onHeaderClick != null) {
                    Modifier
                        .weight(1f)
                        .clickable(onClick = onHeaderClick)
                        .padding(vertical = 2.dp)
                } else {
                    Modifier.weight(1f)
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (onHeaderClick != null) {
                    Spacer(Modifier.width(4.dp))
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        when {
            itemCount == 0 && streamsLoading -> {
                // Reserve roughly a card-height so the layout doesn't jump
                // when phase 2 finishes and the cards land.
                Box(modifier = Modifier.height(165.dp))
            }
            itemCount == 0 -> {
                Text(
                    text = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.empty_shelf_no_content),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
            else -> content()
        }
    }
}

/**
 * Live-channel card — square logo + name underneath. Mirrors iOS
 * `LiveStreamCard`.
 */
@Composable
fun LiveStreamCard(
    name: String,
    iconUrl: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val iconSize = 110.dp
    Column(
        modifier = modifier
            .width(iconSize)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ArtBox(width = iconSize, height = iconSize, cornerRadius = 12.dp, kind = ImageKind.Live) {
            CardImage(url = iconUrl, contentScale = ContentScale.Fit)
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = name,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            // Single-line under the poster — matches iOS as rendered.
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .width(iconSize)
                .padding(horizontal = 4.dp),
        )
    }
}

/**
 * Poster card — 2:3 aspect, used for both VOD and Series. Mirrors iOS
 * `MovieCard` / `SeriesCard`.
 */
@Composable
fun PosterCard(
    name: String,
    coverUrl: String?,
    kind: ImageKind,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val posterWidth = 110.dp
    val posterHeight = 165.dp // 2:3
    Column(
        modifier = modifier
            .width(posterWidth)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ArtBox(width = posterWidth, height = posterHeight, cornerRadius = 12.dp, kind = kind) {
            CardImage(url = coverUrl, contentScale = ContentScale.Crop)
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = name,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            // Single-line under the poster — matches iOS as rendered.
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .width(posterWidth)
                .padding(horizontal = 4.dp),
        )
    }
}

enum class ImageKind { Live, Movie, Series }

/**
 * Common image-or-placeholder backing for both card variants. The
 * placeholder is rendered when the slot composable doesn't draw (i.e. no
 * URL); otherwise [content] paints on top.
 */
@Composable
private fun ArtBox(
    width: Dp,
    height: Dp,
    cornerRadius: Dp,
    kind: ImageKind,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(cornerRadius))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        val placeholder: ImageVector = when (kind) {
            ImageKind.Live -> Icons.Default.Tv
            ImageKind.Movie -> Icons.Default.Movie
            ImageKind.Series -> Icons.Default.PlayCircleOutline
        }
        Icon(
            imageVector = placeholder,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
            modifier = Modifier.size(40.dp),
        )
        // Sits on top of the placeholder once Coil resolves the URL.
        content()
    }
}

@Composable
private fun CardImage(url: String?, contentScale: ContentScale) {
    if (url.isNullOrBlank()) return
    AsyncImage(
        model = url,
        contentDescription = null,
        modifier = Modifier.fillMaxSize(),
        contentScale = contentScale,
    )
}
