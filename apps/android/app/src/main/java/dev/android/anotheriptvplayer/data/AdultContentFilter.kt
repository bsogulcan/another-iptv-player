package dev.android.anotheriptvplayer.data

import dev.android.anotheriptvplayer.networking.XtreamCategory
import dev.android.anotheriptvplayer.networking.XtreamLiveStream
import dev.android.anotheriptvplayer.networking.XtreamVODStream

/**
 * Kotlin port of iOS `AdultContentFilter`.
 *
 * Decision rules (kept identical so both platforms hide / show the same
 * categories given the same Xtream account):
 *  1. Category name is tokenised on non-alphanumeric boundaries; if any
 *     token matches [adultTokens] (case-insensitive), it's adult.
 *  2. Otherwise the upper-cased name is checked for substrings like `"18+"`.
 *  3. Streams are adult if `is_adult == 1` or their `category_id` is in the
 *     adult-category set produced from rules 1 + 2.
 */
object AdultContentFilter {

    /** Case-insensitive whole-token matches. */
    private val adultTokens: Set<String> = setOf(
        "XXX",
        "ADULT", "ADULTS",
        "PORN", "PORNO",
        "EROTIC", "EROTICA",
        "HENTAI",
        "NUDE", "NUDITY",
        // Token-only check avoids false positives like "Essex".
        "SEX",
        "NSFW",
        "EXPLICIT",
        "X-RATED",
        "HARDCORE",
        "SOFTCORE",
        "PLAYBOY",
    )

    /** Substrings that include non-alphanumeric chars, hence checked literally. */
    private val adultSubstrings: List<String> = listOf(
        "18+",
        "18 +",
        "XVIDEOS",
        "XHAMSTER",
        "PORNHUB",
    )

    /** Splits on anything that isn't [A-Za-z0-9]. */
    private val tokenSplitter = Regex("[^A-Za-z0-9]+")

    fun isAdultCategoryName(name: String): Boolean {
        val upper = name.uppercase()
        val tokens = tokenSplitter.split(upper).filter { it.isNotEmpty() }
        if (tokens.any { it in adultTokens }) return true
        return adultSubstrings.any { upper.contains(it) }
    }

    fun isAdultLiveStream(stream: XtreamLiveStream, adultCategoryIds: Set<String>): Boolean {
        if ((stream.isAdult ?: 0) == 1) return true
        val cid = stream.categoryId
        return cid != null && cid in adultCategoryIds
    }

    fun isAdultVODStream(stream: XtreamVODStream, adultCategoryIds: Set<String>): Boolean {
        if ((stream.isAdult ?: 0) == 1) return true
        val cid = stream.categoryId
        return cid != null && cid in adultCategoryIds
    }

    /** Distils a category list down to the IDs whose names trip the filter. */
    fun adultCategoryIds(categories: List<XtreamCategory>): Set<String> =
        categories.mapNotNullTo(mutableSetOf()) { cat ->
            val name = cat.categoryName ?: return@mapNotNullTo null
            if (isAdultCategoryName(name)) cat.categoryId else null
        }
}
