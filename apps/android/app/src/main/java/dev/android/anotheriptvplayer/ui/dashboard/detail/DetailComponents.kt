package dev.android.anotheriptvplayer.ui.dashboard.detail

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

/**
 * Kotlin ports of the iOS detail-screen building blocks in
 * `Views/Components/DetailComponents.swift`.
 *
 * Each block is self-contained so [MovieDetailScreen] (and future
 * SeriesDetail / EpisodeDetail screens) compose them like Lego.
 */

// ---- Hero ----

data class DetailHeroConfig(
    val title: String,
    val backdropUrl: String?,
    val posterUrl: String?,
    val year: String?,
    val runtime: String?,
    val rating10: Double?,
    val ratingText: String?,
    val placeholderIcon: ImageVector = Icons.Default.Movie,
)

/**
 * Cinematic top of the detail screen. A backdrop fills the full width,
 * fades to the surface colour at the bottom, and the poster + title sit on
 * top — same composition as iOS `DetailHero`.
 *
 * Falls back to a tinted gradient when there's no backdrop URL at all
 * (typical for newly-listed movies whose metadata hasn't loaded yet).
 */
@Composable
fun DetailHero(
    config: DetailHeroConfig,
    modifier: Modifier = Modifier,
    heroHeight: androidx.compose.ui.unit.Dp = 340.dp,
) {
    val resolvedBackdrop = config.backdropUrl ?: config.posterUrl
    val backdropIsFallback = config.backdropUrl == null

    Box(modifier = modifier.fillMaxWidth().height(heroHeight)) {
        // Backdrop or fallback gradient.
        if (resolvedBackdrop != null) {
            AsyncImage(
                model = resolvedBackdrop,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxSize()
                    .let {
                        // Slight darken + blur-ish fade for the fallback
                        // path. Compose's runtime blur is API 31+; below we
                        // settle for a darkening overlay.
                        if (backdropIsFallback) it else it
                    },
                contentScale = ContentScale.Crop,
            )
            if (backdropIsFallback) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f)),
                )
            }
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                MaterialTheme.colorScheme.primary.copy(alpha = 0.28f),
                                MaterialTheme.colorScheme.surface,
                            ),
                        ),
                    ),
            )
        }

        // Bottom gradient so the title sits readable on any image.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        // 0% transparent → 50% transparent → 85% semi → 100% surface
                        colors = listOf(
                            Color.Transparent,
                            Color.Transparent,
                            MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
                            MaterialTheme.colorScheme.surface,
                        ),
                    ),
                ),
        )

        // Poster + title row at the bottom.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomStart)
                .padding(horizontal = 16.dp, vertical = 20.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            HeroPoster(url = config.posterUrl, placeholder = config.placeholderIcon)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = config.title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                HeroMetaRow(
                    year = config.year,
                    runtime = config.runtime,
                    rating10 = config.rating10,
                    ratingText = config.ratingText,
                )
            }
        }
    }
}

@Composable
private fun HeroPoster(url: String?, placeholder: ImageVector) {
    val posterWidth = 110.dp
    val posterHeight = 165.dp
    Box(
        modifier = Modifier
            .width(posterWidth)
            .height(posterHeight)
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = placeholder,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
            modifier = Modifier.size(40.dp),
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
private fun HeroMetaRow(
    year: String?,
    runtime: String?,
    rating10: Double?,
    ratingText: String?,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (rating10 != null && rating10 > 0) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.6f))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Star,
                    contentDescription = null,
                    tint = Color(0xFFFFC107),
                    modifier = Modifier.size(12.dp),
                )
                Text(
                    text = "%.1f".format(rating10),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
        } else if (!ratingText.isNullOrBlank()) {
            Text(
                text = ratingText,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }

        if (!year.isNullOrBlank()) {
            Text(
                text = year,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (!runtime.isNullOrBlank()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = null,
                    modifier = Modifier.size(12.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = runtime,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---- Genre chips ----

@Composable
fun GenreChipRow(genres: List<String>, modifier: Modifier = Modifier) {
    if (genres.isEmpty()) return
    LazyRow(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(genres, key = { it }) { genre ->
            Text(
                text = genre,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
    }
}

// ---- Action bar ----

/**
 * Primary CTA (Watch Now / Resume) + optional Restart and Trailer
 * buttons. Progress bar lights up under the primary button when [progress]
 * is non-null — iOS surfaces resume position as a thin line in the same
 * spot.
 */
@Composable
fun DetailActionBar(
    primaryTitle: String,
    onPrimary: () -> Unit,
    modifier: Modifier = Modifier,
    primarySubtitle: String? = null,
    primaryIcon: ImageVector = Icons.Default.PlayArrow,
    progress: Float? = null,
    restartTitle: String? = null,
    onRestart: (() -> Unit)? = null,
    trailerTitle: String? = null,
    onTrailer: (() -> Unit)? = null,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Button(
            onClick = onPrimary,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            contentPadding = PaddingValues(horizontal = 18.dp, vertical = 14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = primaryIcon,
                    contentDescription = null,
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = primaryTitle,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    if (!primarySubtitle.isNullOrEmpty()) {
                        Text(
                            text = primarySubtitle,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.82f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                )
            }
        }

        if (progress != null) {
            LinearProgressIndicator(
                progress = { progress.coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(3.dp)
                    .clip(RoundedCornerShape(2.dp)),
            )
        }

        val hasRestart = onRestart != null && !restartTitle.isNullOrEmpty()
        val hasTrailer = onTrailer != null && !trailerTitle.isNullOrEmpty()
        if (hasRestart || hasTrailer) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (hasRestart) {
                    SecondaryActionButton(
                        modifier = Modifier.weight(1f),
                        icon = Icons.Default.Refresh,
                        title = restartTitle!!,
                        onClick = onRestart!!,
                    )
                }
                if (hasTrailer) {
                    SecondaryActionButton(
                        modifier = Modifier.weight(1f),
                        icon = Icons.Default.PlayArrow,
                        title = trailerTitle!!,
                        onClick = onTrailer!!,
                    )
                }
            }
        }
    }
}

@Composable
private fun SecondaryActionButton(
    modifier: Modifier,
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 11.dp),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.onSurface,
        ),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(6.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// ---- Plot block ----

/**
 * Plot text that collapses to 5 lines by default, with a "Daha fazla" /
 * "Daha az" toggle when truncated. iOS measures both states' heights to
 * decide whether to even show the toggle; on Android we settle for the
 * simpler heuristic of "text is longer than ~250 chars" — it's good
 * enough for movie plots and avoids the two-pass layout.
 */
@Composable
fun DetailPlotBlock(plot: String, modifier: Modifier = Modifier) {
    val canExpand = plot.length > PLOT_TRUNCATION_HEURISTIC_CHARS
    var expanded by remember(plot) { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = "Konu",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = plot,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f),
            maxLines = if (expanded || !canExpand) Int.MAX_VALUE else 5,
            overflow = TextOverflow.Ellipsis,
        )
        AnimatedVisibility(visible = canExpand) {
            Text(
                text = if (expanded) "Daha az" else "Daha fazla",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .clickable { expanded = !expanded }
                    .padding(vertical = 2.dp),
            )
        }
    }
}

private const val PLOT_TRUNCATION_HEURISTIC_CHARS = 250

// ---- Info text block (director / cast / etc.) ----

@Composable
fun DetailInfoTextBlock(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    maxLines: Int = Int.MAX_VALUE,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.9f),
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
