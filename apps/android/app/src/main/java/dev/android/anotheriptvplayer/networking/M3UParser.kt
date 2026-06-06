package dev.android.anotheriptvplayer.networking

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Kotlin port of iOS `M3UParser`.
 *
 * Parses extended M3U / M3U8 playlists into [ParsedM3UPlaylist] structures.
 * Supported tags:
 *  - `#EXTM3U <attrs>` — header (extracts `x-tvg-url` / `url-tvg` EPG URL)
 *  - `#EXTINF:<duration> [k="v" …],<Display Name>` — channel metadata
 *  - non-tag line — the URL for the most recent `EXTINF`
 *  - `#EXTVLCOPT:http-user-agent=<value>` — VLC option (user agent)
 *  - `#EXTGRP:<group>` — group override (only used when EXTINF lacks `group-title`)
 *  - `#KODIPROP:…` and `#EXT-X-KODI-PROP:…` — Kodi properties (user agent from `stream_headers`)
 *  - `#EXTBASEURL:<base>` — resolves relative URLs that follow
 *  - any other `#`-prefixed line is treated as a comment
 *
 * The implementation mirrors iOS heuristics: BOM strip, newline normalisation,
 * tolerant attribute regex, fallback name chain, max-10-line continuation join
 * for EXTINFs with unclosed quotes.
 */
object M3UParser {

    suspend fun parseAsync(rawText: String): ParsedM3UPlaylist =
        withContext(Dispatchers.Default) { parse(rawText) }

    @Throws(M3UParserException::class)
    fun parse(rawText: String): ParsedM3UPlaylist {
        if (rawText.isBlank()) throw M3UParserException.Empty

        val normalised = stripBom(rawText)
            .replace("\r\n", "\n")
            .replace("\r", "\n")
            .replace(" ", "\n")
            .replace(" ", "\n")

        val rawLines = normalised.split("\n")
        val lines = joinContinuations(rawLines)

        val channels = mutableListOf<ParsedM3UChannel>()
        var epgUrl: String? = null
        var pending: ChannelBuilder? = null
        var baseUrl: String? = null
        // Tracks the most recent EXTGRP for channels whose EXTINF didn't
        // provide a group-title.
        var pendingExtGroup: String? = null

        for (raw in lines) {
            val line = raw.trim()
            if (line.isEmpty()) continue

            when {
                line.startsWith("#EXTM3U", ignoreCase = true) -> {
                    epgUrl = extractEpgUrl(line)
                }
                line.startsWith("#EXTINF", ignoreCase = true) -> {
                    // Flush any orphan pending channel (no URL line followed).
                    pending = parseExtInf(line, pendingExtGroup)
                    pendingExtGroup = null
                }
                line.startsWith("#EXTVLCOPT:", ignoreCase = true) -> {
                    val kv = line.substring("#EXTVLCOPT:".length)
                    val (k, v) = splitKeyValue(kv) ?: continue
                    if (k.equals("http-user-agent", ignoreCase = true)) {
                        pending?.userAgent = pending?.userAgent ?: v
                    }
                }
                line.startsWith("#EXTGRP:", ignoreCase = true) -> {
                    pendingExtGroup = line.substring("#EXTGRP:".length).trim().takeIf { it.isNotEmpty() }
                    pending?.let { if (it.groupTitle.isNullOrEmpty()) it.groupTitle = pendingExtGroup }
                }
                line.startsWith("#KODIPROP:", ignoreCase = true) ||
                    line.startsWith("#EXT-X-KODI-PROP:", ignoreCase = true) -> {
                    val payload = line.substringAfter(":", "")
                    val ua = extractUserAgentFromKodiProp(payload)
                    if (ua != null) pending?.userAgent = pending?.userAgent ?: ua
                }
                line.startsWith("#EXTBASEURL:", ignoreCase = true) -> {
                    baseUrl = line.substring("#EXTBASEURL:".length).trim().ifEmpty { null }
                }
                line.startsWith("#") -> {
                    // Comment — skipped intentionally.
                }
                else -> {
                    // URL line for the pending EXTINF (or orphan if pending is null).
                    val urlCandidate = resolveUrl(line, baseUrl) ?: continue
                    val builder = pending ?: continue
                    builder.url = urlCandidate
                    channels += builder.toChannel()
                    pending = null
                }
            }
        }

        if (channels.isEmpty()) throw M3UParserException.NoChannelsFound

        return ParsedM3UPlaylist(channels = channels, epgUrl = epgUrl)
    }

    // ---------------- Helpers ----------------

    private fun stripBom(s: String): String =
        if (s.isNotEmpty() && s[0] == '﻿') s.substring(1) else s

    /**
     * EXTINFs sometimes contain `="..."` attribute values that span newlines
     * (provider bugs). iOS heuristic: if a `#EXTINF` line has an odd number of
     * `"` chars, append up to the next 10 physical lines until the quote
     * closes or we hit another tag.
     */
    private fun joinContinuations(raw: List<String>): List<String> {
        val out = ArrayList<String>(raw.size)
        var i = 0
        while (i < raw.size) {
            val line = raw[i]
            if (line.startsWith("#EXTINF", ignoreCase = true) &&
                line.count { it == '"' } % 2 == 1
            ) {
                val sb = StringBuilder(line)
                var j = i + 1
                var joined = 0
                while (j < raw.size && joined < 10) {
                    val next = raw[j]
                    if (next.startsWith("#") || next.isBlank()) break
                    sb.append(' ').append(next)
                    joined++
                    if (sb.count { it == '"' } % 2 == 0) break
                    j++
                }
                out += sb.toString()
                i = j + 1
            } else {
                out += line
                i++
            }
        }
        return out
    }

    private fun extractEpgUrl(extm3uLine: String): String? {
        val attrs = parseAttrs(extm3uLine.substringAfter("#EXTM3U", "").trim())
        return attrs["x-tvg-url"] ?: attrs["url-tvg"]
    }

    private fun parseExtInf(line: String, defaultGroup: String?): ChannelBuilder {
        // Strip the prefix and optional duration.
        // Examples:
        //   #EXTINF:-1 tvg-id="abc" tvg-name="Foo" group-title="News",Foo
        //   #EXTINF:0,Foo
        val withoutTag = line.removePrefix("#EXTINF").removePrefix(":").trimStart()
        val commaIdx = findUnquotedComma(withoutTag)
        val attrSection = if (commaIdx >= 0) withoutTag.substring(0, commaIdx) else withoutTag
        val display = if (commaIdx >= 0) withoutTag.substring(commaIdx + 1).trim() else ""

        // Drop the duration prefix (`-1` etc.) if present at the start.
        val attrsOnly = attrSection.trimStart().let { s ->
            val firstSpace = s.indexOf(' ')
            if (firstSpace > 0 && s.substring(0, firstSpace).toDoubleOrNull() != null) {
                s.substring(firstSpace + 1)
            } else if (s.toDoubleOrNull() != null) {
                ""
            } else s
        }
        val attrs = parseAttrs(attrsOnly)

        val tvgId = attrs["tvg-id"]
        val tvgName = attrs["tvg-name"]
        val tvgLogo = attrs["tvg-logo"]
        val tvgCountry = attrs["tvg-country"]
        val groupTitle = attrs["group-title"] ?: defaultGroup
        val userAgent = attrs["user-agent"]

        // Some broken files paste the URL inside the display-name. Snag it
        // before falling back to the name chain.
        val embeddedUrl = EMBEDDED_URL_REGEX.find(display)?.value

        val name = when {
            display.isNotBlank() && embeddedUrl == null -> display
            !tvgName.isNullOrBlank() -> tvgName
            else -> display.ifBlank { "Channel" }
        }

        return ChannelBuilder(
            name = name,
            url = embeddedUrl,
            tvgId = tvgId,
            tvgName = tvgName,
            tvgLogo = tvgLogo,
            tvgCountry = tvgCountry,
            groupTitle = groupTitle,
            userAgent = userAgent,
        )
    }

    private fun findUnquotedComma(s: String): Int {
        var inQuotes = false
        for (i in s.indices) {
            val ch = s[i]
            if (ch == '"') inQuotes = !inQuotes
            else if (ch == ',' && !inQuotes) return i
        }
        return -1
    }

    private val ATTR_REGEX = Regex("([^=\\s,\"]+)=(?:\"([^\"]*)\"|([^\\s,\"]+))")

    private fun parseAttrs(text: String): Map<String, String> {
        if (text.isBlank()) return emptyMap()
        val out = HashMap<String, String>()
        for (m in ATTR_REGEX.findAll(text)) {
            val key = m.groupValues[1].lowercase()
            val quoted = m.groupValues[2]
            val unquoted = m.groupValues[3]
            val value = if (quoted.isNotEmpty()) quoted else unquoted
            out[key] = value
        }
        return out
    }

    private fun splitKeyValue(kv: String): Pair<String, String>? {
        val eq = kv.indexOf('=')
        if (eq <= 0) return null
        return kv.substring(0, eq).trim() to kv.substring(eq + 1).trim()
    }

    /**
     * Kodi `stream_headers` payload — example:
     *   `inputstream.adaptive.stream_headers="User-Agent=Mozilla%2F5.0&Referer=…"`
     * Sometimes split on newlines / colons instead of `&`. iOS handles both.
     */
    private fun extractUserAgentFromKodiProp(payload: String): String? {
        val unquoted = payload.trim().trim('"')
        // First form: "User-Agent=…" pairs joined by `&`.
        val pairs = unquoted.split('&')
        for (p in pairs) {
            val (k, v) = splitKeyValue(p) ?: continue
            if (k.equals("User-Agent", ignoreCase = true)) {
                return java.net.URLDecoder.decode(v, "UTF-8")
            }
        }
        // Second form: each header on its own line / colon-separated.
        for (line in unquoted.split("\n")) {
            val parts = line.split(":", limit = 2)
            if (parts.size == 2 && parts[0].trim().equals("User-Agent", ignoreCase = true)) {
                return parts[1].trim()
            }
        }
        return null
    }

    private fun resolveUrl(raw: String, base: String?): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        if (trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true) ||
            trimmed.startsWith("rtmp://", ignoreCase = true) ||
            trimmed.startsWith("rtmps://", ignoreCase = true) ||
            trimmed.startsWith("rtsp://", ignoreCase = true) ||
            trimmed.startsWith("rtsps://", ignoreCase = true)
        ) return trimmed
        return base?.let { "$it$trimmed" } ?: trimmed
    }

    private val EMBEDDED_URL_REGEX =
        Regex("(?:https?|rtmps?|rtsps?)://\\S+", RegexOption.IGNORE_CASE)

    private class ChannelBuilder(
        var name: String,
        var url: String? = null,
        var tvgId: String? = null,
        var tvgName: String? = null,
        var tvgLogo: String? = null,
        var tvgCountry: String? = null,
        var groupTitle: String? = null,
        var userAgent: String? = null,
    ) {
        fun toChannel(): ParsedM3UChannel = ParsedM3UChannel(
            name = name,
            url = url.orEmpty(),
            tvgId = tvgId,
            tvgName = tvgName,
            tvgLogo = tvgLogo,
            tvgCountry = tvgCountry,
            groupTitle = groupTitle,
            userAgent = userAgent,
        )
    }
}

data class ParsedM3UChannel(
    val name: String,
    val url: String,
    val tvgId: String? = null,
    val tvgName: String? = null,
    val tvgLogo: String? = null,
    val tvgCountry: String? = null,
    val groupTitle: String? = null,
    val userAgent: String? = null,
)

data class ParsedM3UPlaylist(
    val channels: List<ParsedM3UChannel>,
    val epgUrl: String? = null,
)

sealed class M3UParserException(message: String) : RuntimeException(message) {
    object Empty : M3UParserException("Playlist body is empty.")
    object NoChannelsFound : M3UParserException("Playlist contains no channels.")
}
