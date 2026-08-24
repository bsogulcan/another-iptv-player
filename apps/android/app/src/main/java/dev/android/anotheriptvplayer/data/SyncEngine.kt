package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.FavoriteEntity
import dev.android.anotheriptvplayer.data.local.M3uFavoriteEntity
import dev.android.anotheriptvplayer.data.local.SyncOutboxEntity
import dev.android.anotheriptvplayer.data.local.WatchHistoryEntity
import dev.android.anotheriptvplayer.model.Playlist
import dev.android.anotheriptvplayer.networking.SyncApiClient
import dev.android.anotheriptvplayer.networking.SyncDeviceInfo
import dev.android.anotheriptvplayer.networking.SyncProgressPayload
import dev.android.anotheriptvplayer.networking.SyncPullItem
import dev.android.anotheriptvplayer.networking.SyncPushItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement

private val EmptyPayload: JsonElement = JsonObject(emptyMap())

private val SyncEngineJson: Json = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
}

/**
 * Drives the self-hosted sync feature: queues local favorite / watch-progress
 * / hidden-category changes to an on-device outbox, flushes them to the
 * configured sync-server, and applies what other devices pushed. Kotlin
 * counterpart of the Tizen client's `sync/syncEngine.ts`.
 *
 * Entirely opt-in — every enqueue method is a no-op until [SyncConfig] has a
 * server URL and device token, so nothing here runs for users who never turn
 * sync on. [HiddenCategoryStore] is wired in lazily via [attachHiddenCategoryStore]
 * to avoid a circular constructor dependency (it also needs a [SyncEngine]).
 */
class SyncEngine(
    private val database: AppDatabase,
    private val playlistRepository: PlaylistRepository,
    private val config: SyncConfig,
    private val apiClient: SyncApiClient,
) {

    enum class Status { IDLE, SYNCING, ERROR }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _status = MutableStateFlow(Status.IDLE)
    val status: StateFlow<Status> = _status.asStateFlow()

    private var hiddenCategoryStore: HiddenCategoryStore? = null

    /** Breaks the [HiddenCategoryStore] <-> [SyncEngine] constructor cycle. */
    fun attachHiddenCategoryStore(store: HiddenCategoryStore) {
        hiddenCategoryStore = store
    }

    private var syncJob: Job? = null

    /** Push pending local changes, then pull and apply remote changes. Concurrent callers share one in-flight run. */
    fun runSync(): Job {
        syncJob?.let { if (it.isActive) return it }
        val job = scope.launch {
            if (!config.isConfigured) return@launch
            _status.value = Status.SYNCING
            try {
                flushOutbox()
                pullAndApply()
                config.lastSyncedAt = System.currentTimeMillis()
                config.lastSyncError = null
                _status.value = Status.IDLE
            } catch (e: Throwable) {
                config.lastSyncError = e.message ?: "Sync failed"
                _status.value = Status.ERROR
            }
        }
        syncJob = job
        return job
    }

    private var pushDebounceJob: Job? = null

    /** Call after queuing a local change: pushes soon without waiting for the full periodic interval. */
    fun schedulePush() {
        if (!config.isConfigured) return
        pushDebounceJob?.cancel()
        pushDebounceJob = scope.launch {
            delay(PUSH_DEBOUNCE_MS)
            runSync()
        }
    }

    private var periodicJob: Job? = null

    fun startPeriodicSync() {
        periodicJob?.cancel()
        periodicJob = null
        if (!config.isConfigured || !config.autoSyncEnabled) return
        val minutes = config.intervalMinutes
        if (minutes <= 0) return
        periodicJob = scope.launch {
            while (isActive) {
                delay(minutes * 60_000L)
                runSync().join()
            }
        }
    }

    fun stopPeriodicSync() {
        periodicJob?.cancel()
        periodicJob = null
    }

    /** Called once at app launch. */
    fun bootSync() {
        if (config.isConfigured) runSync()
        startPeriodicSync()
    }

    suspend fun outboxSize(): Int = database.syncOutboxDao().count()

    // ---- account (proxied through here so the UI never needs its own SyncApiClient) ----

    suspend fun register(serverUrl: String, username: String, password: String) {
        apiClient.register(serverUrl, username, password)
    }

    /** Signs in, persists the resulting device token, and (re)starts periodic sync. */
    suspend fun signIn(serverUrl: String, username: String, password: String, deviceName: String) {
        val response = apiClient.requestDeviceToken(serverUrl, username, password, deviceName)
        config.serverUrl = serverUrl
        config.deviceToken = response.token
        config.deviceId = response.deviceId
        config.accountUsername = username
        config.cursor = 0L
        startPeriodicSync()
        runSync()
    }

    /** Revokes this device's token server-side (best-effort) and forgets local sync state. */
    suspend fun signOut() {
        val deviceId = config.deviceId
        if (deviceId != null) {
            runCatching { apiClient.revokeDevice(deviceId) }
        }
        config.clearAccount()
        stopPeriodicSync()
    }

    suspend fun listDevices(): List<SyncDeviceInfo> = apiClient.listDevices()

    suspend fun revokeDevice(deviceId: Long) {
        apiClient.revokeDevice(deviceId)
        if (deviceId == config.deviceId) {
            config.clearAccount()
            stopPeriodicSync()
        }
    }

    // ---- enqueue (best-effort: never throws, sync must not break local writes) ----

    suspend fun enqueueFavoriteChange(
        playlistId: String,
        contentType: String,
        itemId: String,
        favorited: Boolean,
    ) {
        if (!config.isConfigured) return
        runCatching {
            val playlist = playlistRepository.find(playlistId) ?: return
            val sourceKey = playlistSourceKey(playlist)
            enqueue(
                SyncOutboxEntity(
                    kind = "favorite",
                    key = "$sourceKey:$contentType:$itemId",
                    payload = "{}",
                    updatedAt = System.currentTimeMillis(),
                    deleted = !favorited,
                ),
            )
        }
        schedulePush()
    }

    suspend fun enqueueProgressChange(entity: WatchHistoryEntity) {
        if (!config.isConfigured) return
        runCatching {
            val playlist = playlistRepository.find(entity.playlistId) ?: return
            val sourceKey = playlistSourceKey(playlist)
            val payload = SyncProgressPayload(
                positionSeconds = entity.lastTimeMs / 1000.0,
                durationSeconds = entity.durationMs / 1000.0,
                title = entity.title,
                secondaryTitle = entity.secondaryTitle,
                imageUrl = entity.imageUrl,
                containerExtension = entity.containerExtension,
                seriesId = entity.seriesId,
            )
            enqueue(
                SyncOutboxEntity(
                    kind = "progress",
                    key = "$sourceKey:${entity.type}:${entity.streamId}",
                    payload = SyncEngineJson.encodeToString(payload),
                    updatedAt = entity.lastWatchedAt,
                    deleted = false,
                ),
            )
        }
        schedulePush()
    }

    suspend fun enqueueProgressDelete(playlistId: String, type: String, streamId: String) {
        if (!config.isConfigured) return
        runCatching {
            val playlist = playlistRepository.find(playlistId) ?: return
            val sourceKey = playlistSourceKey(playlist)
            enqueue(
                SyncOutboxEntity(
                    kind = "progress",
                    key = "$sourceKey:$type:$streamId",
                    payload = "{}",
                    updatedAt = System.currentTimeMillis(),
                    deleted = true,
                ),
            )
        }
        schedulePush()
    }

    suspend fun enqueueHiddenCategoryChange(
        playlistId: String,
        categoryType: String,
        categoryId: String,
        hidden: Boolean,
    ) {
        if (!config.isConfigured) return
        runCatching {
            val playlist = playlistRepository.find(playlistId) ?: return
            val sourceKey = playlistSourceKey(playlist)
            enqueue(
                SyncOutboxEntity(
                    kind = "hidden_category",
                    key = "$sourceKey:$categoryType:$categoryId",
                    payload = "{}",
                    updatedAt = System.currentTimeMillis(),
                    deleted = !hidden,
                ),
            )
        }
        schedulePush()
    }

    /** Non-suspend fire-and-forget variant for callers that can't be suspend (e.g. [HiddenCategoryStore]'s synchronous API). */
    fun enqueueHiddenCategoryChangeAsync(
        playlistId: String,
        categoryType: String,
        categoryId: String,
        hidden: Boolean,
    ) {
        scope.launch { enqueueHiddenCategoryChange(playlistId, categoryType, categoryId, hidden) }
    }

    private suspend fun enqueue(row: SyncOutboxEntity) {
        database.syncOutboxDao().insert(row)
    }

    // ---- push ----

    private suspend fun flushOutbox() {
        while (true) {
            val batch = database.syncOutboxDao().batch(PUSH_BATCH_SIZE)
            if (batch.isEmpty()) return
            val items = batch.map { row ->
                SyncPushItem(
                    kind = row.kind,
                    key = row.key,
                    payload = runCatching { SyncEngineJson.parseToJsonElement(row.payload) }
                        .getOrDefault(EmptyPayload),
                    updatedAt = row.updatedAt,
                    deleted = row.deleted,
                )
            }
            // Both "applied" and "stale" mean the server accepted the request
            // and processed it (stale just means a newer write already won)
            // — either way this device's copy of that item is no longer pending.
            apiClient.push(items)
            database.syncOutboxDao().deleteByIds(batch.map { it.id })
        }
    }

    // ---- pull ----

    private suspend fun pullAndApply() {
        while (true) {
            val response = apiClient.pull(config.cursor)
            if (response.items.isNotEmpty()) {
                val playlists = playlistRepository.observeAll().first()
                val bySourceKey = playlists.associateBy { playlistSourceKey(it) }
                for (item in response.items) {
                    applyPulledItem(item, bySourceKey)
                }
            }
            config.cursor = response.cursor
            if (!response.hasMore) return
        }
    }

    private suspend fun applyPulledItem(item: SyncPullItem, playlistsBySourceKey: Map<String, Playlist>) {
        val parts = item.key.split(":")
        if (parts.size < 3) return
        val sourceKey = parts[0]
        val contentType = parts[1]
        val contentId = parts.drop(2).joinToString(":")
        val playlist = playlistsBySourceKey[sourceKey] ?: return

        when (item.kind) {
            "favorite" -> applyFavorite(playlist.id, contentType, contentId, item.deleted)
            "progress" -> applyProgress(playlist.id, contentType, contentId, item)
            "hidden_category" -> applyHiddenCategory(playlist.id, contentType, contentId, item.deleted)
        }
    }

    private suspend fun applyFavorite(playlistId: String, contentType: String, itemId: String, deleted: Boolean) {
        if (contentType == "m3u") {
            if (deleted) {
                database.m3uFavoriteDao().delete(itemId, playlistId)
            } else {
                database.m3uFavoriteDao().insert(M3uFavoriteEntity(channelId = itemId, playlistId = playlistId))
            }
            return
        }
        val streamId = itemId.toIntOrNull() ?: return
        if (deleted) {
            database.favoriteDao().delete(streamId, playlistId, contentType)
        } else {
            database.favoriteDao().insert(FavoriteEntity(streamId = streamId, playlistId = playlistId, type = contentType))
        }
    }

    private suspend fun applyProgress(playlistId: String, type: String, streamId: String, item: SyncPullItem) {
        val id = "${playlistId}_${type}_$streamId"
        if (item.deleted) {
            database.watchHistoryDao().deleteById(id)
            return
        }
        val payload = runCatching { SyncEngineJson.decodeFromJsonElement<SyncProgressPayload>(item.payload) }
            .getOrNull() ?: return
        database.watchHistoryDao().upsert(
            WatchHistoryEntity(
                id = id,
                playlistId = playlistId,
                streamId = streamId,
                type = type,
                lastTimeMs = (payload.positionSeconds * 1000).toLong(),
                durationMs = (payload.durationSeconds * 1000).toLong(),
                lastWatchedAt = item.updatedAt,
                title = payload.title ?: streamId,
                secondaryTitle = payload.secondaryTitle,
                imageUrl = payload.imageUrl,
                seriesId = payload.seriesId,
                containerExtension = payload.containerExtension,
            ),
        )
    }

    private fun applyHiddenCategory(playlistId: String, categoryType: String, categoryId: String, deleted: Boolean) {
        hiddenCategoryStore?.applyFromSync(hide = !deleted, playlistId = playlistId, type = categoryType, categoryId = categoryId)
    }

    companion object {
        private const val PUSH_DEBOUNCE_MS = 4000L
        private const val PUSH_BATCH_SIZE = 500
    }
}
