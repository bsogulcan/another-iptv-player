package dev.android.anotheriptvplayer.networking

import dev.android.anotheriptvplayer.data.SyncConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

private val SyncJson: Json = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    isLenient = true
}

private val JsonMediaType = "application/json; charset=utf-8".toMediaType()

/**
 * Talks to a self-hosted sync-server instance (see `services/sync-server`).
 * Kotlin counterpart of the Tizen client's `sync/api.ts`.
 */
class SyncApiClient(
    private val config: SyncConfig,
    private val client: OkHttpClient = defaultClient,
) {

    private fun normalize(url: String): String {
        var base = url.trim()
        if (!base.startsWith("http://", ignoreCase = true) &&
            !base.startsWith("https://", ignoreCase = true)
        ) {
            base = "http://$base"
        }
        if (base.endsWith("/")) base = base.dropLast(1)
        return base
    }

    private suspend fun request(
        path: String,
        method: String,
        body: String? = null,
        auth: Boolean = false,
        baseUrlOverride: String? = null,
    ): String = withContext(Dispatchers.IO) {
        val baseUrl = baseUrlOverride ?: config.serverUrl ?: throw SyncApiException.NotConfigured()
        val url = normalize(baseUrl) + path

        val builder = Request.Builder().url(url)
        if (auth) {
            val token = config.deviceToken ?: throw SyncApiException.NotSignedIn()
            builder.addHeader("authorization", "Bearer $token")
        }
        when (method) {
            "GET" -> builder.get()
            "DELETE" -> builder.delete()
            "POST" -> builder.post((body ?: "{}").toRequestBody(JsonMediaType))
            else -> error("Unsupported method $method")
        }

        val request = builder.build()
        val response = try {
            client.newCall(request).execute()
        } catch (e: IOException) {
            throw SyncApiException.Network(e)
        }
        response.use {
            if (!it.isSuccessful) {
                val raw = it.body?.string()
                val message = raw?.let { body ->
                    runCatching { SyncJson.decodeFromString<SyncErrorResponse>(body).error }.getOrNull()
                }
                throw SyncApiException.Server(it.code, message)
            }
            if (it.code == 204) return@use ""
            it.body?.string().orEmpty()
        }
    }

    suspend fun register(serverUrl: String, username: String, password: String) {
        val body = SyncJson.encodeToString(SyncRegisterRequest(username, password))
        request("/api/auth/register", "POST", body, baseUrlOverride = serverUrl)
    }

    suspend fun requestDeviceToken(
        serverUrl: String,
        username: String,
        password: String,
        deviceName: String,
    ): SyncTokenResponse {
        val body = SyncJson.encodeToString(SyncTokenRequest(username, password, deviceName))
        val raw = request("/api/auth/token", "POST", body, baseUrlOverride = serverUrl)
        return SyncJson.decodeFromString(raw)
    }

    suspend fun listDevices(): List<SyncDeviceInfo> {
        val raw = request("/api/auth/devices", "GET", auth = true)
        return SyncJson.decodeFromString<SyncDevicesResponse>(raw).devices
    }

    suspend fun revokeDevice(deviceId: Long) {
        request("/api/auth/devices/$deviceId", "DELETE", auth = true)
    }

    suspend fun push(items: List<SyncPushItem>): List<SyncPushResultItem> {
        val body = SyncJson.encodeToString(SyncPushRequest(items))
        val raw = request("/api/sync/push", "POST", body, auth = true)
        return SyncJson.decodeFromString<SyncPushResponse>(raw).results
    }

    suspend fun pull(since: Long): SyncPullResponse {
        val raw = request("/api/sync/pull?since=$since&limit=1000", "GET", auth = true)
        return SyncJson.decodeFromString(raw)
    }

    companion object {
        private val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .callTimeout(45, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build()
        }
    }
}
