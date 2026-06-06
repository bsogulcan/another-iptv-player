package dev.android.anotheriptvplayer.ui.player

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.player.MPVPlayer
import dev.android.anotheriptvplayer.player.SubtitleAppearance
import dev.android.anotheriptvplayer.player.SubtitleAppearanceStore
import dev.android.anotheriptvplayer.player.applySubtitleAppearance

/**
 * Compose port of iOS `SubtitleAppearanceSheet`. Same fields, same value
 * ranges. The settings persist via [SubtitleAppearanceStore] and apply
 * immediately to the live `MPVPlayer`.
 *
 * Kept lean — font size, outline, italic, delay — until we have a real
 * design pass for the rest of the settings (line spacing, alignment, custom
 * colors). Those map cleanly onto the same `applySubtitleAppearance`
 * extension once a UI is in place.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubtitleAppearanceSheet(
    player: MPVPlayer,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val store = remember { SubtitleAppearanceStore(context) }
    var settings by remember { mutableStateOf(store.load()) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(text = stringResource(R.string.subtitle_sheet_title), style = MaterialTheme.typography.titleMedium)

            LabeledSlider(
                label = stringResource(R.string.subtitle_font_size),
                value = settings.fontSize.toFloat(),
                valueRange = 24f..96f,
                steps = 0,
                onChange = { settings = settings.copy(fontSize = it.toInt()) },
                onCommit = { commit(player, store, settings) },
                display = "${settings.fontSize}",
            )
            LabeledSlider(
                label = stringResource(R.string.subtitle_outline),
                value = settings.outlineSize.toFloat(),
                valueRange = 0f..6f,
                steps = 11,
                onChange = { settings = settings.copy(outlineSize = it.toDouble()) },
                onCommit = { commit(player, store, settings) },
                display = "%.1f".format(settings.outlineSize),
            )
            LabeledSlider(
                label = stringResource(R.string.subtitle_delay_seconds),
                value = settings.delaySeconds.toFloat(),
                valueRange = -10f..10f,
                steps = 0,
                onChange = { settings = settings.copy(delaySeconds = it.toDouble()) },
                onCommit = { commit(player, store, settings) },
                display = "%.1f".format(settings.delaySeconds),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.subtitle_italic))
                Switch(
                    checked = settings.italic,
                    onCheckedChange = {
                        settings = settings.copy(italic = it)
                        commit(player, store, settings)
                    },
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.subtitle_background))
                Switch(
                    checked = settings.backgroundEnabled,
                    onCheckedChange = {
                        settings = settings.copy(backgroundEnabled = it)
                        commit(player, store, settings)
                    },
                )
            }
        }
    }
}

private fun commit(player: MPVPlayer, store: SubtitleAppearanceStore, settings: SubtitleAppearance) {
    val clamped = settings.clamp()
    store.save(clamped)
    player.applySubtitleAppearance(clamped)
}

@Composable
private fun LabeledSlider(
    label: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    onChange: (Float) -> Unit,
    onCommit: () -> Unit,
    display: String,
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(text = label)
            Text(text = display, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = valueRange,
            steps = steps,
            onValueChangeFinished = onCommit,
        )
    }
}
