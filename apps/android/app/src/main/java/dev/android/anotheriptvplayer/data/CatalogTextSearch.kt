package dev.android.anotheriptvplayer.data

import java.text.Normalizer
import java.util.Locale

/**
 * Kotlin port of iOS `CatalogTextSearch` (Models/CatalogTextSearch.swift).
 *
 * Why a custom matcher instead of plain `String.contains(query, ignoreCase = true)`:
 *
 *  - iOS uses the Turkish locale for `lowercased(with:)` so that `İ → i`
 *    rather than the default `İ → i̇`. The JDK's `String.lowercase(Locale("tr"))`
 *    matches that behaviour.
 *  - All punctuation, accents, and the dotted-i marks are folded away so that
 *    "kanal-1" and "Kanal 1" match the same query.
 *  - The query is whitespace-split and every token must appear in the
 *    normalized text — `[matches]` returns false if any token is missing.
 *
 * iOS registers `localized_contains` / `localized_starts_with` /
 * `localized_equals` as SQL functions on the GRDB connection. We don't need
 * the SQL hook for the dashboard / detail catalogues — those load into RAM
 * and search runs in-memory — but a future Search screen that hits SQLite
 * directly will want a normalized column to filter on. Until then we expose
 * [normalize] so callers can replicate iOS by writing the normalized form
 * into a Room column at insert time and then filtering with `LIKE`.
 */
object CatalogTextSearch {

    private val TURKISH = Locale.forLanguageTag("tr")
    private val DIACRITICS = Regex("\\p{Mn}+")
    private val NON_ALNUM = Regex("[^\\p{L}\\p{Nd}]+")

    /**
     * Turkish-locale lowercase + Unicode NFD fold + drop everything that
     * isn't a letter or digit. The result has no whitespace, so callers that
     * want token-by-token matching must split the query *before* normalising.
     */
    fun normalize(s: String): String {
        if (s.isEmpty()) return s
        val lowered = s.lowercase(TURKISH)
        val decomposed = Normalizer.normalize(lowered, Normalizer.Form.NFD)
        val folded = DIACRITICS.replace(decomposed, "")
        return NON_ALNUM.replace(folded, "")
    }

    /**
     * True when every whitespace-separated token in [query] appears in the
     * normalised [text]. Matches iOS `CatalogTextSearch.matches(search:text:)`.
     */
    fun matches(query: String, text: String): Boolean {
        val tokens = query
            .split(WHITESPACE)
            .map { normalize(it) }
            .filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return true
        val normalised = normalize(text)
        return tokens.all { it in normalised }
    }

    fun equals(a: String, b: String): Boolean = normalize(a) == normalize(b)

    fun startsWith(text: String, prefix: String): Boolean =
        normalize(text).startsWith(normalize(prefix))

    private val WHITESPACE = Regex("\\s+")
}
