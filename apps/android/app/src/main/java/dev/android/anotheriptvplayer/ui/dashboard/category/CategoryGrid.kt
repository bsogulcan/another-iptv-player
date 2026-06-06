package dev.android.anotheriptvplayer.ui.dashboard.category

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp

/**
 * Generic adaptive grid for the live / vod / series category detail
 * screens. iOS uses `LazyVGrid` with an adaptive minimum size — Compose's
 * [LazyVerticalGrid] + [GridCells.Adaptive] is the direct equivalent.
 *
 * The shape of [content] is left as a slot so callers stay typed on the
 * item type they hold.
 */
@Composable
fun <T> CategoryGrid(
    items: List<T>,
    minCellSize: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
    emptyIcon: ImageVector,
    emptyMessage: String,
    itemKey: (T) -> Any,
    itemContent: @Composable (T) -> Unit,
) {
    if (items.isEmpty()) {
        EmptyState(modifier = modifier, icon = emptyIcon, message = emptyMessage)
        return
    }
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = minCellSize),
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(items.size, key = { idx -> itemKey(items[idx]) }) { idx ->
            itemContent(items[idx])
        }
    }
}

@Composable
private fun EmptyState(modifier: Modifier, icon: ImageVector, message: String) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(48.dp),
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Single-line search field with a leading magnifier and clear icon when
 * non-empty. iOS uses `.searchable(...)` modifier with debounce — for the
 * first cut we filter live with no debounce because typical category
 * sizes (< 500 items) make this trivially fast.
 *
 * [debounceMs] is wired but defaults to 0; pass a positive value once the
 * Turkish-locale normaliser lands and filtering gets more expensive.
 */
@Composable
fun CategorySearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "Ara",
    debounceMs: Long = 0L,
) {
    // `debounced` exposes a delayed version of `value` so callers can
    // remember(debounced) without the filter recomputing on every keystroke
    // once we set debounceMs > 0. The TextField itself stays responsive.
    var debounced by remember { mutableStateOf(value) }
    LaunchedEffect(value, debounceMs) {
        if (debounceMs > 0L) kotlinx.coroutines.delay(debounceMs)
        debounced = value
    }

    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        placeholder = { Text(placeholder) },
        leadingIcon = {
            Icon(Icons.Default.Search, contentDescription = null)
        },
        trailingIcon = {
            if (value.isNotEmpty()) {
                IconButton(onClick = { onValueChange("") }) {
                    Icon(Icons.Default.Clear, contentDescription = "Temizle")
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(28.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        colors = TextFieldDefaults.colors(
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        ),
    )
}

/**
 * Case-insensitive `contains` filter. Replace with a Turkish-locale aware
 * normaliser once that lands (iOS `CatalogTextSearch` equivalent).
 */
fun <T> List<T>.filterByQuery(query: String, nameOf: (T) -> String): List<T> {
    val q = query.trim()
    if (q.isEmpty()) return this
    return filter { nameOf(it).contains(q, ignoreCase = true) }
}
