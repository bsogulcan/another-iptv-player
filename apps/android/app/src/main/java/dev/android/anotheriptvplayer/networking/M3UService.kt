package dev.android.anotheriptvplayer.networking

import android.content.ContentResolver
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.nio.charset.Charset
import java.util.concurrent.TimeUnit

/**
 * Kotlin port of iOS `M3UService`.
 *
 * Two entry points:
 *  - [fetchRemote] grabs an `http(s)://…m3u(8)?` document over the network.
 *  - [readLocal] reads an `m3u` / `m3u8` document the user picked from the
 *    Storage Access Framework. Caller passes the `content://` Uri.
 *
 * Encoding fallback chain — UTF-8 → ISO-8859-1 → UTF-16 — matches the iOS
 * implementation. IPTV playlists are usually UTF-8 but a noticeable minority
 * comes from Windows-1254 / Latin-1 sources.
 */
class M3UService(
    private val client: OkHttpClient = defaultClient,
    private val contentResolver: ContentResolver? = null,
) {

    suspend fun fetchRemote(urlString: String): String = withContext(Dispatchers.IO) {
        val trimmed = urlString.trim()
        if (!trimmed.startsWith("http://", ignoreCase = true) &&
            !trimmed.startsWith("https://", ignoreCase = true)
        ) {
            throw M3UServiceException.InvalidUrl(trimmed)
        }

        val request = Request.Builder().url(trimmed).get().build()
        val bytes: ByteArray = try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw M3UServiceException.Server(response.code)
                }
                response.body?.bytes() ?: ByteArray(0)
            }
        } catch (e: IOException) {
            throw M3UServiceException.Network(e)
        }

        decode(bytes)
    }

    /**
     * Reads a SAF-provided document. The caller must hold a persistent URI
     * permission or the URI must be a one-shot transient one; either way the
     * `ContentResolver.openInputStream` call here is what actually pulls the
     * bytes, so we honour the system's lifecycle.
     */
    suspend fun readLocal(uri: Uri): String = withContext(Dispatchers.IO) {
        val resolver = contentResolver
            ?: throw M3UServiceException.FileRead(IOException("No ContentResolver supplied"))
        try {
            resolver.openInputStream(uri).use { stream ->
                if (stream == null) throw M3UServiceException.FileRead(IOException("openInputStream returned null"))
                decode(stream.readBytes())
            }
        } catch (e: IOException) {
            throw M3UServiceException.FileRead(e)
        }
    }

    private fun decode(bytes: ByteArray): String {
        if (bytes.isEmpty()) return ""
        // Order matters — try UTF-8 first (most common) before falling back.
        for (cs in CHARSETS) {
            runCatching {
                val s = String(bytes, cs)
                // A heuristic check — strict UTF-8 will throw on invalid
                // sequences when `decode` is used directly via CharsetDecoder,
                // but `String(bytes, charset)` swallows them silently. So we
                // require the result to contain the `#EXTM3U` marker, which
                // every valid playlist begins with. If it doesn't, fall
                // through to the next encoding.
                if (s.contains("#EXTM3U", ignoreCase = true)) return s
            }
        }
        // Last-ditch: return UTF-8 anyway so the parser can surface a clearer
        // error than "unsupported encoding".
        return String(bytes, Charsets.UTF_8)
    }

    companion object {
        private val CHARSETS: List<Charset> = listOf(
            Charsets.UTF_8,
            Charsets.ISO_8859_1,
            Charsets.UTF_16,
        )

        private val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                // Long readTimeout — some providers stream multi-MB M3U files
                // over slow links.
                .readTimeout(120, TimeUnit.SECONDS)
                .callTimeout(180, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build()
        }
    }
}

sealed class M3UServiceException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause) {

    class InvalidUrl(val url: String) :
        M3UServiceException("Invalid playlist URL: $url")

    class Network(cause: Throwable) :
        M3UServiceException("Network error: ${cause.message}", cause)

    class Server(val code: Int) :
        M3UServiceException("Server returned HTTP $code")

    class FileRead(cause: Throwable) :
        M3UServiceException("File read failed: ${cause.message}", cause)
}
