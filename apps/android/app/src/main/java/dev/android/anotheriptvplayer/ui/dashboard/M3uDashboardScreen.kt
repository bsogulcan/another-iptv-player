package dev.android.anotheriptvplayer.ui.dashboard

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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
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
import dev.android.anotheriptvplayer.data.local.M3uChannelEntity
import dev.android.anotheriptvplayer.ui.LocalPlaylistRepository
import kotlinx.coroutines.launch

/**
 * M3U playlist dashboard — single scroll of channels grouped by EXTGRP /
 * `group-title`. iOS counterpart: `M3UDashboardView` + `M3UChannelsView`.
 *
 * Differs from the Xtream dashboard ([PlaylistDashboardScreen]) in two ways:
 *  - M3U has no VOD/series split, just a flat channels list.
 *  - Favourites live in a separate Room table (`m3uFavorite`) keyed by the
 *    channel's deterministic SHA-256 id.
 *
 * Search filters in-memory through [CatalogTextSearch.matches]; a 310K-channel
 * playlist with a `loadPlaylistSuspending` already in `_channels` filters in
 * a single frame.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun M3uDashboardScreen(
    playlistId: String,
    onBack: () -> Unit,
    onPlayChannel: (channelId: String, url: String, title: String) -> Unit,
) {
    val context = LocalContext.current
    val app = context.applicationContext as AnotherIptvPlayerApp
    val repository = LocalPlaylistRepository.current
    val store = app.m3uContentStore
    val favorites = app.m3uFavoriteStore
    val scope = rememberCoroutineScope()

    val otherGroupLabel = stringResource(R.string.m3u_other_group)
    LaunchedEffect(playlistId) {
        val playlist = repository.find(playlistId) ?: return@LaunchedEffect
        // Apply the localised "Other" group label before loading so the first
        // grouping pass uses the right bucket name.
        store.ungroupedLabel = otherGroupLabel
        favorites.track(playlistId)
        store.loadPlaylistSuspending(playlist)
    }

    val isLoading by store.isLoading.collectAsState()
    val channels by store.channels.collectAsState()
    val groupNames by store.groupNames.collectAsState()
    val channelsByGroup by store.channelsByGroup.collectAsState()
    val favoriteIds by favorites.favoriteIds.collectAsState()
    val loadError by store.loadError.collectAsState()

    var query by remember { mutableStateOf("") }
    val filtered by remember(channels) {
        derivedStateOf {
            if (query.isBlank()) channels
            else channels.filter { CatalogTextSearch.matches(query, it.name) }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.screen_m3u_channels)) },
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
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )

            when {
                isLoading && channels.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                loadError != null && channels.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                        Text(loadError ?: stringResource(R.string.m3u_load_error_generic), style = MaterialTheme.typography.bodyMedium)
                    }
                }
                query.isNotBlank() -> {
                    // Flat search results — skip grouping.
                    val state = rememberLazyListState()
                    LazyColumn(
                        state = state,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        items(filtered, key = { it.id }) { channel ->
                            M3uChannelRow(
                                channel = channel,
                                isFavorite = channel.id in favoriteIds,
                                onPlay = { onPlayChannel(channel.id, channel.url, channel.name) },
                                onToggleFavorite = { scope.launch { favorites.toggle(channel) } },
                            )
                        }
                    }
                }
                else -> {
                    val state = rememberLazyListState()
                    LazyColumn(
                        state = state,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        groupNames.forEach { group ->
                            val list = channelsByGroup[group].orEmpty()
                            if (list.isEmpty()) return@forEach
                            item(key = "header:$group") {
                                Text(
                                    text = "$group  •  ${list.size}",
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.padding(top = 12.dp, bottom = 4.dp),
                                )
                            }
                            items(list, key = { it.id }) { channel ->
                                M3uChannelRow(
                                    channel = channel,
                                    isFavorite = channel.id in favoriteIds,
                                    onPlay = {
                                        onPlayChannel(channel.id, channel.url, channel.name)
                                    },
                                    onToggleFavorite = { scope.launch { favorites.toggle(channel) } },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun M3uChannelRow(
    channel: M3uChannelEntity,
    isFavorite: Boolean,
    onPlay: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clickable(onClick = onPlay),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 12.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val logo = channel.tvgLogo
            if (!logo.isNullOrBlank()) {
                AsyncImage(
                    model = logo,
                    contentDescription = null,
                    modifier = Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surface),
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surface),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Default.LiveTv,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = channel.name,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                channel.groupTitle?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            IconButton(onClick = onToggleFavorite) {
                Icon(
                    imageVector = if (isFavorite) Icons.Default.Star else Icons.Default.StarBorder,
                    contentDescription = if (isFavorite) stringResource(R.string.detail_favorite_remove) else stringResource(R.string.detail_favorite_add),
                    tint = if (isFavorite) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
