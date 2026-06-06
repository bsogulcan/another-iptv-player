package dev.android.anotheriptvplayer.networking

import android.util.Log
import dev.android.anotheriptvplayer.model.Playlist
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.serializer
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Shared lenient JSON instance.
 *
 * `ignoreUnknownKeys` — Xtream payloads carry extra fields we don't model;
 *   we silently drop them.
 * `coerceInputValues` — when a non-null property gets JSON null, fall back
 *   to its default rather than throwing.
 * `isLenient` — accept slightly malformed JSON (unquoted numbers, etc.) that
 *   some providers emit.
 */
internal val XtreamJson: Json = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    isLenient = true
}

/**
 * Kotlin port of iOS `XtreamAPIClient`.
 *
 * Responsibilities mirror the Swift class one-to-one:
 *  - Build/normalise the base `player_api.php` URL with `username`+`password`
 *  - Dispatch the action endpoints and decode through [XtreamJson]
 *  - Lift per-item decoding failures (one bad row shouldn't fail the whole
 *    response) via [decodeFailableList]
 */
class XtreamApiClient(
    private val playlist: Playlist,
    private val client: OkHttpClient = defaultClient,
) {

    /**
     * Reproduces `getBaseURLComponents()` from iOS:
     *  - prepend `http://` if scheme missing
     *  - strip trailing `/`
     *  - append `/player_api.php` if not already there
     *  - strip embedded whitespace
     *  - attach `username` and `password` query parameters
     */
    private fun buildBaseUrlBuilder(): okhttp3.HttpUrl.Builder {
        var base = playlist.serverUrl.trim()
        if (!base.startsWith("http://", ignoreCase = true) &&
            !base.startsWith("https://", ignoreCase = true)
        ) {
            base = "http://$base"
        }
        if (base.endsWith("/")) base = base.dropLast(1)
        if (!base.lowercase().endsWith("player_api.php")) {
            base += "/player_api.php"
        }
        base = base.replace(" ", "")

        val parsed = base.toHttpUrlOrNull() ?: throw XtreamException.InvalidUrl(base)
        return parsed.newBuilder()
            .addQueryParameter("username", playlist.username.trim())
            .addQueryParameter("password", playlist.password.trim())
    }

    private suspend inline fun <reified T> fetch(
        action: String? = null,
        queryItems: Map<String, String> = emptyMap(),
        serializer: KSerializer<T> = serializer(),
    ): T = withContext(Dispatchers.IO) {
        val builder = buildBaseUrlBuilder()
        action?.let { builder.addQueryParameter("action", it) }
        queryItems.forEach { (k, v) -> builder.addQueryParameter(k, v) }
        val url = builder.build()

        val request = Request.Builder().url(url).get().build()
        val raw: String = try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw XtreamException.Server("HTTP ${response.code}")
                }
                response.body?.string().orEmpty()
            }
        } catch (e: XtreamException) {
            throw e
        } catch (e: IOException) {
            throw XtreamException.Network(e)
        }

        try {
            XtreamJson.decodeFromString(serializer, raw)
        } catch (e: Throwable) {
            Log.w(TAG, "Decoding error for $url\nBody: $raw", e)
            throw XtreamException.Decoding(e)
        }
    }

    /**
     * Decodes a JSON array element-by-element, dropping rows whose individual
     * decode throws. Kotlin counterpart of iOS `[FailableDecodable<T>]` then
     * `.compactMap { $0.base }`.
     */
    private suspend inline fun <reified T> decodeFailableList(
        action: String,
        queryItems: Map<String, String> = emptyMap(),
        itemSerializer: KSerializer<T> = serializer(),
    ): List<T> {
        val tree: JsonElement = fetch(
            action = action,
            queryItems = queryItems,
            serializer = JsonElement.serializer(),
        )
        val array = tree as? JsonArray ?: return emptyList()
        return array.mapNotNull { element ->
            if (element is JsonNull) return@mapNotNull null
            runCatching { XtreamJson.decodeFromJsonElement(itemSerializer, element) }
                .onFailure { Log.w(TAG, "Skipping bad item in $action: ${it.message}") }
                .getOrNull()
        }
    }

    // ---- API methods ----

    /** Login / verify. Throws [XtreamException.Unauthenticated] if `auth != 1`. */
    suspend fun verify(): XtreamAuthResponse {
        val response: XtreamAuthResponse = fetch()
        if (response.userInfo == null || response.userInfo.auth == 0) {
            throw XtreamException.Unauthenticated()
        }
        return response
    }

    suspend fun getLiveCategories(): List<XtreamCategory> =
        decodeFailableList(action = "get_live_categories")

    suspend fun getVODCategories(): List<XtreamCategory> =
        decodeFailableList(action = "get_vod_categories")

    suspend fun getSeriesCategories(): List<XtreamCategory> =
        decodeFailableList(action = "get_series_categories")

    suspend fun getLiveStreams(categoryId: String? = null): List<XtreamLiveStream> =
        decodeFailableList(
            action = "get_live_streams",
            queryItems = categoryId?.let { mapOf("category_id" to it) } ?: emptyMap(),
        )

    suspend fun getVODStreams(categoryId: String? = null): List<XtreamVODStream> =
        decodeFailableList(
            action = "get_vod_streams",
            queryItems = categoryId?.let { mapOf("category_id" to it) } ?: emptyMap(),
        )

    suspend fun getSeries(categoryId: String? = null): List<XtreamSeries> =
        decodeFailableList(
            action = "get_series",
            queryItems = categoryId?.let { mapOf("category_id" to it) } ?: emptyMap(),
        )

    suspend fun getSeriesInfo(seriesId: Int): XtreamSeriesInfoResponse = fetch(
        action = "get_series_info",
        queryItems = mapOf("series_id" to seriesId.toString()),
    )

    suspend fun getVODInfo(vodId: Int): XtreamVODInfoResponse = fetch(
        action = "get_vod_info",
        queryItems = mapOf("vod_id" to vodId.toString()),
    )

    companion object {
        private const val TAG = "XtreamApiClient"

        /**
         * Process-wide OkHttp client. OkHttp encourages reuse so the
         * connection pool and dispatcher are shared. Read timeout is on the
         * higher side because some Xtream servers stream multi-thousand-item
         * JSON arrays before responding.
         */
        private val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .callTimeout(120, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build()
        }
    }
}

// Unused but kept for parity with the iOS `[String: String]` form when callers
// want a fluent shape rather than a one-off map literal.
@Suppress("unused")
internal fun queryItems(vararg pairs: Pair<String, String?>): Map<String, String> =
    pairs.mapNotNull { (k, v) -> v?.let { k to it } }.toMap()

// Convenience to keep `serializer<T>()` callers working in inline functions
// without needing each call site to import `kotlinx.serialization.builtins`.
private fun stringSerializer(): KSerializer<String> = String.serializer()
private fun stringListSerializer(): KSerializer<List<String>> = ListSerializer(String.serializer())
