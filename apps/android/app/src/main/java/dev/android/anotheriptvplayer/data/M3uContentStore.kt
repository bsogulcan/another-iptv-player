package dev.android.anotheriptvplayer.data

import android.util.Log
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.M3uChannelEntity
import dev.android.anotheriptvplayer.model.Playlist
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Kotlin port of iOS `M3UContentStore`.
 *
 * Holds the channel list + grouping for the currently-active M3U playlist.
 * Reads from SQLite (populated by `M3uImporter`), groups by `groupTitle` on
 * `Dispatchers.Default` so 310K-channel playlists don't block the UI.
 *
 * `loadToken` guards against late publishes from a previous `loadPlaylist`
 * — iOS uses the same pattern.
 */
class M3uContentStore(private val database: AppDatabase) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    @Volatile private var loadToken: UUID? = null

    private val _activePlaylistId = MutableStateFlow<String?>(null)
    val activePlaylistId: StateFlow<String?> = _activePlaylistId.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError: StateFlow<String?> = _loadError.asStateFlow()

    private val _channels = MutableStateFlow<List<M3uChannelEntity>>(emptyList())
    val channels: StateFlow<List<M3uChannelEntity>> = _channels.asStateFlow()

    private val _channelsByGroup = MutableStateFlow<Map<String, List<M3uChannelEntity>>>(emptyMap())
    val channelsByGroup: StateFlow<Map<String, List<M3uChannelEntity>>> = _channelsByGroup.asStateFlow()

    private val _groupNames = MutableStateFlow<List<String>>(emptyList())
    val groupNames: StateFlow<List<String>> = _groupNames.asStateFlow()

    /**
     * Where channels with no `group-title` land. Defaulted in the constructor
     * from the localised string resource ("Other" / "Diğer"). Caller may
     * override pre-load if a screen needs a different label.
     */
    var ungroupedLabel: String = "Other"

    /**
     * Runtime-only adult-content filter; iOS keeps it volatile-not-persisted
     * because Xtream sync respects [Playlist.filterAdultContent] at write
     * time, while the M3U importer doesn't see the channel list yet.
     */
    var filterAdultContent: Boolean = false
        set(value) {
            field = value
            recomputeGroupingFromCurrent()
        }

    fun loadPlaylist(playlist: Playlist) {
        scope.launch { loadPlaylistSuspending(playlist) }
    }

    suspend fun loadPlaylistSuspending(playlist: Playlist) {
        val token = UUID.randomUUID()
        loadToken = token

        _loadError.value = null
        if (_activePlaylistId.value != playlist.id) {
            _channels.value = emptyList()
            _channelsByGroup.value = emptyMap()
            _groupNames.value = emptyList()
            _activePlaylistId.value = playlist.id
        }
        _isLoading.value = true

        try {
            val rows = database.m3uChannelDao().getByPlaylist(playlist.id)
            if (loadToken != token) return
            applyChannels(rows)
        } catch (t: Throwable) {
            if (loadToken != token) return
            Log.w(TAG, "M3U load failed", t)
            _loadError.value = t.message ?: t.javaClass.simpleName
        } finally {
            if (loadToken == token) _isLoading.value = false
        }
    }

    fun search(query: String): List<M3uChannelEntity> {
        if (query.isBlank()) return _channels.value
        return _channels.value.filter { CatalogTextSearch.matches(query, it.name) }
    }

    private fun applyChannels(rows: List<M3uChannelEntity>) {
        val filtered = if (filterAdultContent) {
            rows.filterNot {
                AdultContentFilter.isAdultCategoryName(it.groupTitle.orEmpty()) ||
                    AdultContentFilter.isAdultCategoryName(it.name)
            }
        } else rows

        val orderedGroups = LinkedHashMap<String, MutableList<M3uChannelEntity>>()
        for (row in filtered) {
            val key = row.groupTitle?.takeIf { it.isNotBlank() } ?: ungroupedLabel
            orderedGroups.getOrPut(key) { mutableListOf() }.add(row)
        }
        _channels.value = filtered
        _channelsByGroup.value = orderedGroups
        _groupNames.value = orderedGroups.keys.toList()
    }

    private fun recomputeGroupingFromCurrent() {
        // Re-derive from the current `_channels` so toggling the filter at
        // runtime doesn't require another DB hit.
        applyChannels(_channels.value)
    }

    companion object {
        private const val TAG = "M3uContentStore"
    }
}
