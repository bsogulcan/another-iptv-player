package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.data.local.PlaylistDao
import dev.android.anotheriptvplayer.model.Playlist
import kotlinx.coroutines.flow.Flow

/**
 * Repository over the SQLite-backed `playlist` table.
 *
 * UI reads [observeAll] as a Flow (one source of truth, auto-refreshed by
 * Room) and goes through the suspend mutators for inserts / updates / deletes.
 * Wraps [PlaylistDao] so the rest of the app stays free of Room types.
 */
class PlaylistRepository(private val dao: PlaylistDao) {

    fun observeAll(): Flow<List<Playlist>> = dao.observeAll()

    suspend fun find(id: String): Playlist? = dao.findById(id)

    suspend fun add(playlist: Playlist) = dao.insert(playlist)

    suspend fun update(playlist: Playlist) = dao.update(playlist)

    suspend fun remove(id: String) = dao.deleteById(id)
}
