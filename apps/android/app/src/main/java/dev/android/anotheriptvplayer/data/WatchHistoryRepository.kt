package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.data.local.WatchHistoryDao
import dev.android.anotheriptvplayer.data.local.WatchHistoryEntity

/**
 * Thin wrapper over [WatchHistoryDao] — the write side only. Reads still go
 * straight through the DAO (`observeRecent`, `progressMap`, ...) since those
 * don't need a sync hook. Mirrors [FavoriteRepository]'s shape.
 */
class WatchHistoryRepository(
    private val dao: WatchHistoryDao,
    private val syncEngine: SyncEngine? = null,
) {

    suspend fun upsert(entity: WatchHistoryEntity) {
        dao.upsert(entity)
        syncEngine?.enqueueProgressChange(entity)
    }

    suspend fun delete(entity: WatchHistoryEntity) {
        dao.deleteById(entity.id)
        syncEngine?.enqueueProgressDelete(entity.playlistId, entity.type, entity.streamId)
    }
}
