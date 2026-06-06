package dev.android.anotheriptvplayer.ui.playlist

import dev.android.anotheriptvplayer.data.PlaylistRepository
import dev.android.anotheriptvplayer.data.local.PlaylistDao
import dev.android.anotheriptvplayer.model.Playlist
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * In-memory [PlaylistRepository] used only by `@Preview` composables.
 *
 * Real previews don't have an Android `Context`, so we can't build a Room
 * database. This swap-in keeps the screens renderable in Android Studio's
 * preview without sneaking mock data into the runtime path.
 */
internal fun PreviewPlaylistRepository(vararg seeded: Playlist): PlaylistRepository {
    val state = MutableStateFlow(seeded.toList())
    val dao = object : PlaylistDao {
        override fun observeAll(): Flow<List<Playlist>> = state
        override suspend fun findById(id: String): Playlist? =
            state.value.firstOrNull { it.id == id }
        override suspend fun insert(playlist: Playlist) {
            state.value = state.value.filterNot { it.id == playlist.id } + playlist
        }
        override suspend fun update(playlist: Playlist) {
            state.value = state.value.map { if (it.id == playlist.id) playlist else it }
        }
        override suspend fun delete(playlist: Playlist) {
            state.value = state.value.filterNot { it.id == playlist.id }
        }
        override suspend fun deleteById(id: String) {
            state.value = state.value.filterNot { it.id == id }
        }
    }
    return PlaylistRepository(dao)
}
