package dev.android.anotheriptvplayer.ui.playlist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.model.PlaylistKind
import dev.android.anotheriptvplayer.networking.XtreamApiClient
import dev.android.anotheriptvplayer.ui.LocalPlaylistContentStore
import dev.android.anotheriptvplayer.ui.LocalPlaylistRepository
import dev.android.anotheriptvplayer.ui.components.ModalSlideContainer
import dev.android.anotheriptvplayer.ui.components.SavingOverlay
import dev.android.anotheriptvplayer.ui.components.SectionHeader
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Form for adding or editing an Xtream Codes playlist — the Android counterpart
 * of the iOS `AddPlaylistView`. Verification is mocked for now (no network call).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddXtreamPlaylistScreen(
    onCancel: () -> Unit,
    onSaved: (String) -> Unit,
    editingPlaylistId: String? = null,
) {
    val repository = LocalPlaylistRepository.current
    val contentStore = LocalPlaylistContentStore.current
    // `editing` is loaded asynchronously from SQLite when an id is provided;
    // the form fields populate as soon as the row arrives.
    var editing by remember(editingPlaylistId) { mutableStateOf<Playlist?>(null) }
    LaunchedEffect(editingPlaylistId) {
        editing = editingPlaylistId?.let { repository.find(it) }
    }

    var name by remember(editing?.id) { mutableStateOf(editing?.name ?: "") }
    var serverUrl by remember(editing?.id) { mutableStateOf(editing?.serverUrl ?: "http://") }
    var username by remember(editing?.id) { mutableStateOf(editing?.username ?: "") }
    var password by remember(editing?.id) { mutableStateOf(editing?.password ?: "") }
    var filterAdultContent by remember(editing?.id) { mutableStateOf(editing?.filterAdultContent ?: false) }

    var passwordVisible by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    // Progress text shown inside the blocking overlay while verify/sync runs.
    // Mirrors iOS `progressMessage` on `AddPlaylistView`.
    var progressMessage by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()

    val isValid = name.isNotBlank() &&
        serverUrl.isNotBlank() && serverUrl != "http://" &&
        username.isNotBlank() &&
        password.isNotBlank()

    val verifyingMessage = androidx.compose.ui.res.stringResource(
        dev.android.anotheriptvplayer.R.string.add_xtream_verifying,
    )
    val authFailedMessage = androidx.compose.ui.res.stringResource(
        dev.android.anotheriptvplayer.R.string.add_xtream_auth_failed,
    )
    val saveFailedMessage = androidx.compose.ui.res.stringResource(
        dev.android.anotheriptvplayer.R.string.add_xtream_save_failed,
    )
    fun save() {
        if (!isValid || isSaving) return
        focusManager.clearFocus()
        errorMessage = null
        isSaving = true
        progressMessage = verifyingMessage

        scope.launch {
            val current = editing
            val newPlaylist = Playlist.create(
                id = current?.id ?: UUID.randomUUID().toString(),
                name = name.trim(),
                serverUrl = serverUrl.trim(),
                username = username.trim(),
                password = password.trim(),
                kind = PlaylistKind.XTREAM,
                filterAdultContent = filterAdultContent,
                createdAt = current?.createdAt ?: System.currentTimeMillis(),
            )

            // iOS `detailsChanged` check — if only the display name moved we
            // can skip the round-trip + sync. URL/username/password/filter
            // all affect what gets fetched so any of them flips the bit.
            val detailsChanged = current == null ||
                newPlaylist.serverUrl != current.serverUrl ||
                newPlaylist.username != current.username ||
                newPlaylist.password != current.password ||
                newPlaylist.filterAdultContent != current.filterAdultContent

            if (!detailsChanged) {
                try {
                    repository.update(newPlaylist)
                    isSaving = false
                    progressMessage = null
                    onSaved(newPlaylist.id)
                } catch (e: Throwable) {
                    errorMessage = e.message ?: saveFailedMessage
                    isSaving = false
                    progressMessage = null
                }
                return@launch
            }

            try {
                val client = XtreamApiClient(newPlaylist)
                val response = client.verify()
                if (response.userInfo?.auth != 1) {
                    errorMessage = authFailedMessage
                    isSaving = false
                    progressMessage = null
                    return@launch
                }

                // Persist the playlist BEFORE the sync — iOS does the same so
                // that if sync fails partway, the row is still listed and the
                // user can re-trigger from the dashboard's Re-sync action.
                if (current != null) {
                    repository.update(newPlaylist)
                } else {
                    repository.add(newPlaylist)
                }

                contentStore.syncFromNetworkReplacingLocal(newPlaylist) { msg ->
                    progressMessage = msg
                }

                isSaving = false
                progressMessage = null
                onSaved(newPlaylist.id)
            } catch (e: Throwable) {
                errorMessage = e.message ?: e.javaClass.simpleName
                isSaving = false
                progressMessage = null
            }
        }
    }

    ModalSlideContainer {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(if (editing != null) "Edit Xtream Playlist" else "New Xtream Playlist")
                    },
                    navigationIcon = {
                        IconButton(onClick = onCancel, enabled = !isSaving) {
                            Icon(Icons.Default.Close, contentDescription = "Cancel")
                        }
                    },
                    actions = {
                        TextButton(onClick = ::save, enabled = isValid && !isSaving) {
                            Text("Save")
                        }
                    },
                )
            },
        ) { innerPadding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SectionHeader("Playlist Info")
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        imeAction = ImeAction.Next,
                    ),
                    keyboardActions = KeyboardActions(
                        onNext = { focusManager.moveFocus(FocusDirection.Down) },
                    ),
                )
                OutlinedTextField(
                    value = serverUrl,
                    onValueChange = { serverUrl = it },
                    label = { Text("Server URL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Next,
                    ),
                    keyboardActions = KeyboardActions(
                        onNext = { focusManager.moveFocus(FocusDirection.Down) },
                    ),
                )

                Spacer(Modifier.height(4.dp))
                SectionHeader("Credentials")
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("Username") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(
                        onNext = { focusManager.moveFocus(FocusDirection.Down) },
                    ),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (passwordVisible) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { save() }),
                    trailingIcon = {
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(
                                imageVector = if (passwordVisible) {
                                    Icons.Default.VisibilityOff
                                } else {
                                    Icons.Default.Visibility
                                },
                                contentDescription = if (passwordVisible) {
                                    "Hide password"
                                } else {
                                    "Show password"
                                },
                            )
                        }
                    },
                )

                Spacer(Modifier.height(4.dp))
                SectionHeader("Content Settings")
                AdultContentToggle(
                    checked = filterAdultContent,
                    onCheckedChange = { filterAdultContent = it },
                )
            }
        }

        if (isSaving) {
            SavingOverlay(progressMessage ?: verifyingMessage)
        }

        errorMessage?.let { msg ->
            AlertDialog(
                onDismissRequest = { errorMessage = null },
                title = { Text(androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.add_xtream_connection_failed)) },
                text = { Text(msg) },
                confirmButton = {
                    TextButton(onClick = { errorMessage = null }) {
                        Text(androidx.compose.ui.res.stringResource(dev.android.anotheriptvplayer.R.string.common_ok))
                    }
                },
            )
        }
    }
}

@Composable
private fun AdultContentToggle(checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Filter adult content",
                    style = MaterialTheme.typography.bodyLarge,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "Hide channels and categories flagged as adult.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        }
    }
}

// `@Preview` is intentionally omitted: the save path requires
// `LocalPlaylistContentStore`, which can't be faked without an in-memory
// Room database. Verify the screen by running the app.
