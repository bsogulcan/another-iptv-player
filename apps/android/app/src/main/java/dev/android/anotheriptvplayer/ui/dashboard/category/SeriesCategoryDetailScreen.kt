package dev.android.anotheriptvplayer.ui.dashboard.category

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.android.anotheriptvplayer.ui.LocalPlaylistContentStore
import dev.android.anotheriptvplayer.ui.dashboard.ImageKind
import dev.android.anotheriptvplayer.ui.dashboard.PosterCard

/**
 * Series category detail — adaptive grid of 2:3 poster cards. Tapping a
 * poster opens [SeriesDetailScreen] via [onOpenSeries].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesCategoryDetailScreen(
    playlistId: String,
    categoryId: String,
    onBack: () -> Unit,
    onOpenSeries: (Int) -> Unit,
) {
    val contentStore = LocalPlaylistContentStore.current
    val categories by contentStore.seriesCategories.collectAsStateWithLifecycle()
    val byCategory by contentStore.seriesItemsByCategoryId.collectAsStateWithLifecycle()
    val category = categories.firstOrNull { it.id == categoryId }
    val allItems = byCategory[categoryId].orEmpty()

    var query by remember { mutableStateOf("") }
    val filtered = remember(allItems, query) {
        allItems.filterByQuery(query) { it.series.name }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = category?.name ?: "Kategori",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri")
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            CategorySearchField(
                value = query,
                onValueChange = { query = it },
                placeholder = "Dizi ara",
            )
            CategoryGrid(
                items = filtered,
                minCellSize = 110.dp,
                emptyIcon = if (query.isBlank()) Icons.Default.Tv else Icons.Default.Search,
                emptyMessage = if (query.isBlank()) androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.empty_category_no_series) else androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.empty_category_search_no_series),
                itemKey = { it.id },
            ) { row ->
                PosterCard(
                    name = row.series.name,
                    coverUrl = row.series.cover,
                    kind = ImageKind.Series,
                    onClick = { onOpenSeries(row.series.seriesId) },
                )
            }
        }
    }
}
