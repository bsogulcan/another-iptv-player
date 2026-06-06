package dev.android.anotheriptvplayer.ui.settings

import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.data.PlaylistContentStore
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.networking.XtreamApiClient
import dev.android.anotheriptvplayer.networking.XtreamAuthResponse
import dev.android.anotheriptvplayer.ui.LocalPlaylistContentStore
import dev.android.anotheriptvplayer.ui.LocalPlaylistRepository
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Settings tab body — Kotlin port of iOS `PlaylistSettingsView`, scoped to
 * what the Android app already has wired:
 *  - Playlist info (read-only, password reveal toggle)
 *  - Subscription details (live `verify()` call)
 *  - Catalog row counts
 *  - Server timezone / message
 *  - Adult-content filter toggle (saves + re-syncs)
 *  - About / GitHub link
 *
 * Designed to render inside the dashboard's HorizontalPager — therefore
 * has no top bar / Scaffold of its own; padding is owned by the caller.
 *
 * Downloads, watch-history clear, language picker, and player settings are
 * omitted because the underlying features haven't landed on Android yet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistSettingsBody(
    playlistId: String,
    appVersion: String,
    onOpenDownloads: () -> Unit = {},
    onOpenHistory: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val playlistRepository = LocalPlaylistRepository.current
    val contentStore = LocalPlaylistContentStore.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var playlist by remember(playlistId) { mutableStateOf<Playlist?>(null) }
    LaunchedEffect(playlistId) {
        playlist = playlistRepository.find(playlistId)
    }

    var authResponse by remember(playlistId) { mutableStateOf<XtreamAuthResponse?>(null) }
    var isLoadingAuth by remember(playlistId) { mutableStateOf(true) }
    var authError by remember(playlistId) { mutableStateOf<String?>(null) }

    var stats by remember(playlistId) { mutableStateOf<PlaylistContentStore.CatalogStats?>(null) }

    var isSyncing by remember { mutableStateOf(false) }
    var syncMessage by remember { mutableStateOf<String?>(null) }
    var syncError by remember { mutableStateOf<String?>(null) }

    var passwordRevealed by remember { mutableStateOf(false) }

    suspend fun reloadStats() {
        stats = contentStore.fetchStats(playlistId)
    }

    suspend fun reloadAuth() {
        val pl = playlist ?: return
        isLoadingAuth = true
        authError = null
        runCatching { XtreamApiClient(pl).verify() }
            .onSuccess { authResponse = it }
            .onFailure { authError = it.message }
        isLoadingAuth = false
    }

    // Initial load: stats + auth.
    LaunchedEffect(playlistId, playlist?.id) {
        if (playlist == null) return@LaunchedEffect
        reloadStats()
        reloadAuth()
    }

    if (playlist == null) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) { CircularProgressIndicator() }
        return
    }
    val pl = playlist!!

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
            // Sync section.
            SettingsCard {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_re_download)) },
                    supportingContent = {
                        if (isSyncing && syncMessage != null) {
                            Text(
                                text = syncMessage!!,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else if (syncError != null) {
                            Text(
                                text = syncError!!,
                                color = MaterialTheme.colorScheme.error,
                            )
                        } else {
                            Text("Kategoriler, filmler ve dizileri sunucudan yeniden indir.")
                        }
                    },
                    trailingContent = {
                        if (isSyncing) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Default.Refresh, contentDescription = null)
                        }
                    },
                    colors = clickableListItemColors(),
                    modifier = Modifier.clickableEnabled(!isSyncing) {
                        scope.launch {
                            isSyncing = true
                            syncError = null
                            try {
                                contentStore.syncFromNetworkReplacingLocal(pl) { msg ->
                                    syncMessage = msg
                                }
                                reloadStats()
                                contentStore.reloadFromDatabaseIfActive(pl.id)
                            } catch (e: Throwable) {
                                syncError = e.message
                            } finally {
                                isSyncing = false
                                syncMessage = null
                            }
                        }
                    },
                )
            }

            // Playlist info section.
            SettingsCard(title = stringResource(R.string.settings_card_playlist_info)) {
                InfoRow(label = stringResource(R.string.settings_name), value = pl.name)
                Divider()
                InfoRow(label = stringResource(R.string.settings_server), value = pl.serverUrl)
                Divider()
                InfoRow(label = stringResource(R.string.settings_user), value = pl.username)
                Divider()
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.settings_password),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = if (passwordRevealed) pl.password else "•".repeat(pl.password.length.coerceAtMost(20)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(end = 8.dp),
                    )
                    IconButton(onClick = { passwordRevealed = !passwordRevealed }) {
                        Icon(
                            imageVector = if (passwordRevealed) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (passwordRevealed) stringResource(R.string.common_hide) else stringResource(R.string.common_show),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }

            // Subscription section.
            SettingsCard(title = stringResource(R.string.settings_card_subscription)) {
                when {
                    isLoadingAuth -> CenteredHint(stringResource(R.string.settings_loading_info))
                    authError != null -> CenteredHint(
                        text = authError ?: stringResource(R.string.settings_unknown_error),
                        color = MaterialTheme.colorScheme.error,
                    )
                    authResponse?.userInfo != null -> {
                        val user = authResponse!!.userInfo!!
                        InfoRow(label = stringResource(R.string.settings_subscription_status), value = remainingDaysText(LocalContext.current, user.expDate))
                        Divider()
                        InfoRow(
                            label = stringResource(R.string.settings_active_connection),
                            value = user.activeCons ?: "—",
                        )
                        Divider()
                        InfoRow(
                            label = stringResource(R.string.settings_max_connection),
                            value = user.maxConnections.takeUnless { it.isNullOrEmpty() } ?: stringResource(R.string.settings_unlimited),
                        )
                    }
                    else -> CenteredHint(stringResource(R.string.settings_subscription_unknown))
                }
            }

            // Stats section.
            SettingsCard(title = stringResource(R.string.settings_card_stats)) {
                val s = stats
                if (s == null) {
                    CenteredHint(stringResource(R.string.common_loading))
                } else {
                    InfoRow(label = stringResource(R.string.settings_live_count), value = s.liveCount.toString())
                    Divider()
                    InfoRow(label = stringResource(R.string.settings_vod_count), value = s.vodCount.toString())
                    Divider()
                    InfoRow(label = stringResource(R.string.settings_series_count), value = s.seriesCount.toString())
                }
            }

            // Server info (timezone + message), only when present.
            val server = authResponse?.serverInfo
            val rawMessage = authResponse?.userInfo?.message?.trim().orEmpty()
            if (server?.timezone?.isNotBlank() == true || rawMessage.isNotEmpty()) {
                SettingsCard(title = stringResource(R.string.settings_card_server)) {
                    server?.timezone?.takeIf { it.isNotBlank() }?.let {
                        InfoRow(label = "Zaman dilimi", value = it)
                    }
                    if (rawMessage.isNotEmpty()) {
                        if (server?.timezone?.isNotBlank() == true) Divider()
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(
                                text = "Mesaj",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                text = rawMessage,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // Content management.
            SettingsCard(title = stringResource(R.string.settings_card_content)) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_adult_filter)) },
                    supportingContent = {
                        Text(
                            stringResource(R.string.settings_adult_filter_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    trailingContent = {
                        Switch(
                            enabled = !isSyncing,
                            checked = pl.filterAdultContent,
                            onCheckedChange = { newValue ->
                                scope.launch {
                                    // Persist the flag first, then re-sync so
                                    // categories/streams reflect the new filter.
                                    val updated = pl.copy(filterAdultContent = newValue)
                                    playlistRepository.update(updated)
                                    playlist = updated
                                    isSyncing = true
                                    syncError = null
                                    try {
                                        contentStore.syncFromNetworkReplacingLocal(updated) { msg ->
                                            syncMessage = msg
                                        }
                                        reloadStats()
                                        contentStore.reloadFromDatabaseIfActive(updated.id)
                                    } catch (e: Throwable) {
                                        syncError = e.message
                                    } finally {
                                        isSyncing = false
                                        syncMessage = null
                                    }
                                }
                            },
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                )
            }

            // Player preferences — PiP, background playback, 2× long-press.
            // iOS registers these as defaults at app init; we mirror them
            // here with one source-of-truth `PlayerPreferences`.
            SettingsCard(title = stringResource(R.string.settings_card_player)) {
                val playerPrefs = dev.android.anotheriptvplayer.ui.LocalPlayerPreferences.current
                val pip by playerPrefs.pipEnabled.collectAsState()
                val bg by playerPrefs.continuePlayingInBackground.collectAsState()
                val longPress by playerPrefs.speedUpOnLongPress.collectAsState()

                SwitchRow(
                    title = stringResource(R.string.settings_player_pip),
                    subtitle = stringResource(R.string.settings_player_pip_subtitle),
                    checked = pip,
                    onChange = { playerPrefs.setPipEnabled(it) },
                )
                Divider()
                SwitchRow(
                    title = stringResource(R.string.settings_player_bg),
                    subtitle = stringResource(R.string.settings_player_bg_subtitle),
                    checked = bg,
                    onChange = { playerPrefs.setContinuePlayingInBackground(it) },
                )
                Divider()
                SwitchRow(
                    title = stringResource(R.string.settings_player_long_press),
                    subtitle = stringResource(R.string.settings_player_long_press_subtitle),
                    checked = longPress,
                    onChange = { playerPrefs.setSpeedUpOnLongPress(it) },
                )
            }

            // Library — Downloads + Watch History entry points. iOS surfaces
            // these on the dashboard side bar; the Android dashboard funnels
            // them through Settings so the top app bar stays uncluttered.
            SettingsCard(title = stringResource(R.string.settings_card_library)) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_library_downloads)) },
                    supportingContent = {
                        Text(
                            stringResource(R.string.settings_library_downloads_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    trailingContent = {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                    },
                    colors = clickableListItemColors(),
                    modifier = Modifier.clickableEnabled(true) { onOpenDownloads() },
                )
                Divider()
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_library_history)) },
                    supportingContent = {
                        Text(
                            stringResource(R.string.settings_library_history_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    trailingContent = {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                    },
                    colors = clickableListItemColors(),
                    modifier = Modifier.clickableEnabled(true) { onOpenHistory() },
                )
            }

            // About.
            SettingsCard(title = stringResource(R.string.settings_card_about)) {
                InfoRow(label = stringResource(R.string.settings_version), value = appVersion)
                Divider()
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_github_label)) },
                    supportingContent = {
                        Text(
                            stringResource(R.string.settings_github_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    trailingContent = {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                    },
                    colors = clickableListItemColors(),
                    modifier = Modifier.clickableEnabled(true) {
                        runCatching {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://github.com/bsogulcan/another-iptv-player"),
                                ),
                            )
                        }
                    },
                )
            }

        Spacer(Modifier.height(24.dp))
    }
}

/** Calculates remaining-days text from a UNIX-seconds string. iOS parity. */
private fun remainingDaysText(context: android.content.Context, expDateRaw: String?): String {
    val ts = expDateRaw?.toLongOrNull()
        ?: return context.getString(R.string.settings_unlimited_or_unknown)
    if (ts == 0L) return context.getString(R.string.settings_unlimited)
    val expiry = Instant.ofEpochSecond(ts).atZone(ZoneId.systemDefault()).toLocalDate()
    val today = LocalDate.now()
    val days = ChronoUnit.DAYS.between(today, expiry).toInt()
    return when {
        days < 0 -> context.getString(R.string.settings_expired)
        days == 0 -> context.getString(R.string.settings_expires_today)
        else -> context.getString(R.string.settings_days_left, days)
    }
}

// ---- Small layout helpers ----

@Composable
private fun SettingsCard(
    title: String? = null,
    content: @Composable () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (title != null) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
            ),
        ) {
            Column { content() }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 12.dp),
        )
    }
}

@Composable
private fun Divider() {
    HorizontalDivider(
        modifier = Modifier.padding(horizontal = 16.dp),
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.18f),
    )
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = {
            Text(
                text = subtitle,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        trailingContent = {
            Switch(checked = checked, onCheckedChange = onChange)
        },
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onChange(!checked) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
    )
}

@Composable
private fun CenteredHint(text: String, color: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = color,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    )
}

@Composable
private fun clickableListItemColors() = ListItemDefaults.colors(
    containerColor = MaterialTheme.colorScheme.surface,
)

private fun Modifier.clickableEnabled(enabled: Boolean, onClick: () -> Unit): Modifier =
    if (enabled) this.clickable(onClick = onClick) else this
