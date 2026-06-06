package dev.android.anotheriptvplayer.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.android.anotheriptvplayer.data.HiddenCategoryStore
import dev.android.anotheriptvplayer.data.local.CategoryEntity
import dev.android.anotheriptvplayer.ui.LocalHiddenCategoryStore
import dev.android.anotheriptvplayer.ui.dashboard.category.CategorySearchField
import dev.android.anotheriptvplayer.ui.dashboard.category.filterByQuery

/**
 * Kotlin port of iOS `CategoryPickerSheet`.
 *
 * Modal bottom sheet that lists every category for the active tab plus
 * the per-category item count. Each row carries a trailing eye / eye-slash
 * icon to toggle hide/show; iOS uses a trailing swipe action, but on
 * Android an inline icon is the cleaner equivalent and works for users on
 * any input modality.
 *
 * Tapping a row dismisses the sheet via [onSelect]; jump-to-category
 * scroll lives at the caller level (left out of this PR — see
 * `PlaylistDashboardScreen`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CategoryPickerSheet(
    title: String,
    playlistId: String,
    contentType: String,
    categories: List<CategoryEntity>,
    itemCountsByCategoryId: Map<String, Int>,
    sheetState: SheetState,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val hiddenStore: HiddenCategoryStore = LocalHiddenCategoryStore.current
    val hiddenIds by hiddenStore.observeHidden(playlistId, contentType)
        .collectAsStateWithLifecycle(initialValue = hiddenStore.hiddenIds(playlistId, contentType))

    var query by remember { mutableStateOf("") }

    val entries = remember(categories, itemCountsByCategoryId) {
        categories.map { Entry(it.id, it.name, itemCountsByCategoryId[it.id] ?: 0) }
    }
    val filtered = remember(entries, query) {
        entries.filterByQuery(query) { it.name }
    }
    val visible = filtered.filter { it.id !in hiddenIds }
    val hidden = filtered.filter { it.id in hiddenIds }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
            CategorySearchField(
                value = query,
                onValueChange = { query = it },
                placeholder = "Kategori ara",
            )

            if (visible.isEmpty() && hidden.isEmpty()) {
                EmptyHint(text = androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.empty_search_no_results))
                return@Column
            }

            // Sheet height isn't infinite — give the LazyColumn a generous
            // cap so users can scroll long category lists without the sheet
            // exploding to full height.
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(560.dp),
                contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                if (visible.isNotEmpty()) {
                    items(visible, key = { "v_${it.id}" }) { entry ->
                        PickerRow(
                            entry = entry,
                            isHidden = false,
                            onSelect = onSelect,
                            onToggle = { hiddenStore.setHidden(true, playlistId, contentType, entry.id) },
                        )
                    }
                }
                if (hidden.isNotEmpty()) {
                    item(key = "hidden_header") {
                        Text(
                            text = "Gizli",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                    items(hidden, key = { "h_${it.id}" }) { entry ->
                        PickerRow(
                            entry = entry,
                            isHidden = true,
                            onSelect = onSelect,
                            onToggle = { hiddenStore.setHidden(false, playlistId, contentType, entry.id) },
                        )
                    }
                }
            }
        }
    }
}

private data class Entry(val id: String, val name: String, val count: Int)

@Composable
private fun PickerRow(
    entry: Entry,
    isHidden: Boolean,
    onSelect: (String) -> Unit,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSelect(entry.id) }
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .alpha(if (isHidden) 0.55f else 1f),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = entry.name,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        // Item-count chip.
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
                .padding(horizontal = 8.dp, vertical = 2.dp),
        ) {
            Text(
                text = entry.count.toString(),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = onToggle, modifier = Modifier.size(36.dp)) {
            Icon(
                imageVector = if (isHidden) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                contentDescription = if (isHidden) androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.common_show) else androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.common_hide),
                tint = if (isHidden) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun EmptyHint(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
    )
}
