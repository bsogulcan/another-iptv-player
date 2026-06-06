package dev.android.anotheriptvplayer.data

import android.content.Context
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.DownloadedItemEntity
import kotlinx.coroutines.flow.Flow
import java.io.File

/**
 * Kotlin port of iOS `DownloadManager`.
 *
 * Surface is intentionally trimmed compared to the iOS class:
 *  - per-item enqueue / cancel / delete / deleteAll,
 *  - localUrl lookup,
 *  - active-download probe per playlist,
 *  - playlist-wide cleanup hook used when a playlist row is deleted.
 *
 * Heavy lifting lives in [DownloadWorker]; this class is just the orchestrator
 * that writes a row and tells WorkManager to start a worker for it. iOS does
 * roughly the same thing via `URLSession.downloadTask(with:)`.
 *
 * The "wifi only" preference is honoured by setting [NetworkType.UNMETERED]
 * on the WorkRequest's constraints. The iOS counterpart toggles
 * `allowsCellularAccess` on the URLSessionConfiguration.
 */
class DownloadManager(
    private val context: Context,
    private val database: AppDatabase,
    private val storage: DownloadStorage,
) {

    private val workManager get() = WorkManager.getInstance(context.applicationContext)

    private val prefs by lazy {
        context.applicationContext.getSharedPreferences("downloads", Context.MODE_PRIVATE)
    }

    var wifiOnly: Boolean
        get() = prefs.getBoolean(KEY_WIFI_ONLY, false)
        set(value) = prefs.edit().putBoolean(KEY_WIFI_ONLY, value).apply()

    fun observeAll(playlistId: String): Flow<List<DownloadedItemEntity>> =
        database.downloadedItemDao().observeByPlaylist(playlistId)

    suspend fun enqueue(
        id: String,
        playlistId: String,
        streamId: String,
        type: String,
        title: String,
        secondaryTitle: String?,
        imageUrl: String?,
        remoteUrl: String,
        containerExtension: String?,
        seriesId: String? = null,
        seasonNumber: Int? = null,
        episodeNumber: Int? = null,
    ) {
        val relative = storage.relativePath(playlistId, id, containerExtension)
        val existing = database.downloadedItemDao().findById(id)
        if (existing != null && existing.status == "completed") return

        val row = (existing ?: DownloadedItemEntity(
            id = id,
            playlistId = playlistId,
            streamId = streamId,
            type = type,
            title = title,
            secondaryTitle = secondaryTitle,
            imageUrl = imageUrl,
            remoteUrl = remoteUrl,
            localPath = relative,
            containerExtension = containerExtension,
            status = "queued",
            seriesId = seriesId,
            seasonNumber = seasonNumber,
            episodeNumber = episodeNumber,
        )).copy(status = "queued", errorMessage = null)
        database.downloadedItemDao().upsert(row)

        startWorker(id)
    }

    private fun startWorker(id: String) {
        DownloadWorker.ensureChannel(context)
        val data = Data.Builder().putString(DownloadWorker.KEY_ID, id).build()
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
            .build()
        val request = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setInputData(data)
            .setConstraints(constraints)
            .addTag(DownloadWorker.WORK_TAG_PREFIX + id)
            .build()
        // REPLACE: if a stale worker for this id is still around (failed +
        // queued from before reboot), kick it out.
        workManager.enqueueUniqueWork(
            DownloadWorker.WORK_TAG_PREFIX + id,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    fun cancel(id: String) {
        workManager.cancelUniqueWork(DownloadWorker.WORK_TAG_PREFIX + id)
    }

    suspend fun delete(id: String) {
        cancel(id)
        val row = database.downloadedItemDao().findById(id) ?: return
        storage.delete(row.localPath)
        database.downloadedItemDao().deleteById(id)
    }

    suspend fun deleteAll(playlistId: String) {
        val rows = database.downloadedItemDao().queuedItems() +
            database.downloadedItemDao().inFlight()
        rows.filter { it.playlistId == playlistId }.forEach { cancel(it.id) }
        // Storage walk: we don't have a "rows by playlist" DAO call yet, so
        // pull via Flow first.
        database.downloadedItemDao().deleteByPlaylist(playlistId)
        File(storage.rootDir, playlistId).deleteRecursively()
    }

    /** iOS `DownloadManager.cleanupPlaylist(playlistId:)` — called from playlist delete. */
    fun cleanupPlaylist(playlistId: String) {
        // Worker tags + DB rows are reaped by the FK cascade on the playlist
        // delete; we still need to nuke the on-disk bytes ourselves.
        File(storage.rootDir, playlistId).deleteRecursively()
    }

    suspend fun localFile(id: String): File? {
        val row = database.downloadedItemDao().findById(id) ?: return null
        val file = storage.absolutePath(row.localPath)
        return file.takeIf { it.exists() }
    }

    suspend fun hasActiveDownload(playlistId: String): Boolean =
        database.downloadedItemDao().activeCountForPlaylist(playlistId) > 0

    companion object {
        private const val KEY_WIFI_ONLY = "wifi_only"
    }
}
