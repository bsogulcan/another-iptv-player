package dev.android.anotheriptvplayer.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import dev.android.anotheriptvplayer.AnotherIptvPlayerApp
import dev.android.anotheriptvplayer.R
import dev.android.anotheriptvplayer.data.local.AppDatabase
import dev.android.anotheriptvplayer.data.local.DownloadedItemEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Resumable HTTP download powered by `CoroutineWorker`.
 *
 * iOS counterpart: `URLSessionConfiguration.background(withIdentifier:)`
 * driven by `URLSessionDownloadDelegate` callbacks. Android's blessed way to
 * keep a long-running HTTP request alive across process death is a
 * foreground worker + persistent notification — that's what this class is.
 *
 * Each item has a 1:1 `WorkRequest` tagged with the iOS-shaped download id
 * so `DownloadManager.cancel(id)` can find and stop it.
 */
class DownloadWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val downloadId = inputData.getString(KEY_ID) ?: return@withContext Result.failure()
        val app = applicationContext as AnotherIptvPlayerApp
        val database: AppDatabase = app.appDatabaseForDownloads
        val storage: DownloadStorage = app.downloadStorageForWorker

        val row = database.downloadedItemDao().findById(downloadId)
            ?: return@withContext Result.failure()

        setForeground(makeForegroundInfo(row, indeterminate = true))
        database.downloadedItemDao().setStatus(downloadId, status = "downloading")

        val destFile = storage.absolutePath(row.localPath)
        destFile.parentFile?.mkdirs()
        // Resume support — if we already have N bytes on disk, send a Range
        // header so the server can pick up where we left off. This is the
        // moral equivalent of iOS background URLSession's automatic resume
        // (which uses its own resumeData blob).
        val startOffset = if (destFile.exists()) destFile.length() else 0L
        val requestBuilder = Request.Builder().url(row.remoteUrl)
        if (startOffset > 0) {
            requestBuilder.addHeader("Range", "bytes=$startOffset-")
        }

        return@withContext try {
            httpClient.newCall(requestBuilder.build()).execute().use { response ->
                if (!response.isSuccessful && response.code != 206) {
                    fail(database, downloadId, "HTTP ${response.code}")
                    return@withContext Result.failure()
                }

                val body = response.body ?: run {
                    fail(database, downloadId, "Empty body")
                    return@withContext Result.failure()
                }

                val contentLengthHeader = body.contentLength()
                val totalBytes = if (contentLengthHeader > 0) {
                    contentLengthHeader + startOffset
                } else row.totalBytes
                if (totalBytes > 0 && totalBytes != row.totalBytes) {
                    database.downloadedItemDao().setProgress(
                        downloadId,
                        downloaded = startOffset,
                        total = totalBytes,
                    )
                }

                val appendMode = startOffset > 0
                FileOutputStream(destFile, appendMode).use { out ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var downloaded = startOffset
                    var lastUpdateMs = 0L
                    body.byteStream().use { input ->
                        while (true) {
                            if (isStopped) {
                                // Cooperative cancellation — bail without
                                // touching the DB row. The cancellation path
                                // in `DownloadManager.cancel(id)` is what
                                // updates state.
                                return@withContext Result.failure()
                            }
                            val read = input.read(buffer)
                            if (read == -1) break
                            out.write(buffer, 0, read)
                            downloaded += read
                            val now = System.currentTimeMillis()
                            if (now - lastUpdateMs > 750L) {
                                lastUpdateMs = now
                                database.downloadedItemDao().setProgress(
                                    downloadId,
                                    downloaded = downloaded,
                                    total = if (totalBytes > 0) totalBytes else downloaded,
                                )
                                setForeground(
                                    makeForegroundInfo(
                                        row.copy(downloadedBytes = downloaded, totalBytes = totalBytes),
                                        indeterminate = totalBytes <= 0,
                                    ),
                                )
                            }
                        }
                    }
                    out.fd.sync()
                }

                database.downloadedItemDao().markComplete(downloadId, System.currentTimeMillis())
                Result.success()
            }
        } catch (e: IOException) {
            fail(database, downloadId, e.message ?: e.javaClass.simpleName)
            Result.retry()
        } catch (t: Throwable) {
            Log.e(TAG, "Download failed", t)
            fail(database, downloadId, t.message ?: t.javaClass.simpleName)
            Result.failure()
        }
    }

    private suspend fun fail(
        database: AppDatabase,
        id: String,
        message: String,
    ) {
        database.downloadedItemDao().setStatus(id, status = "failed", errorMessage = message)
    }

    private fun makeForegroundInfo(
        row: DownloadedItemEntity,
        indeterminate: Boolean,
    ): ForegroundInfo {
        ensureChannel(applicationContext)
        val percent = if (!indeterminate && row.totalBytes > 0) {
            ((row.downloadedBytes * 100f) / row.totalBytes).toInt().coerceIn(0, 100)
        } else 0
        val ctx = applicationContext
        val notification = NotificationCompat.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(row.title)
            .setContentText(
                if (indeterminate) ctx.getString(R.string.download_status_downloading_pending)
                else ctx.getString(R.string.download_status_downloading_progress, percent),
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, indeterminate)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(
                row.id.hashCode(),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(row.id.hashCode(), notification)
        }
    }

    companion object {
        private const val TAG = "DownloadWorker"
        const val KEY_ID = "downloadId"
        const val NOTIFICATION_CHANNEL_ID = "downloads"
        const val WORK_TAG_PREFIX = "download:"
        private const val BUFFER_SIZE = 64 * 1024

        private val httpClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build()
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                context.getString(R.string.download_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = context.getString(R.string.download_channel_description)
            }
            nm.createNotificationChannel(channel)
        }
    }
}
