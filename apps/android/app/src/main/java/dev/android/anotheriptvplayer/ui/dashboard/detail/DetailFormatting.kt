package dev.android.anotheriptvplayer.ui.dashboard.detail

/**
 * Kotlin port of iOS `DetailFormatting`.
 *
 * Pure formatters used by [MovieDetailScreen] (and later the series detail
 * screen). Keeping them detached from Composables makes them straight to
 * unit-test if we ever need to.
 */
internal object DetailFormatting {

    /**
     * Pulls the year out of an Xtream release-date string. Inputs are
     * usually `"2014-03-21"` but occasionally just `"2014"` or freeform
     * text. Returns null if the input is blank.
     */
    fun year(releaseDate: String?): String? {
        val raw = releaseDate?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val prefix = raw.take(4)
        return if (prefix.length == 4 && prefix.all { it.isDigit() }) prefix else raw
    }

    /** `1:23:45` for ≥1h, `23:45` otherwise. iOS uses the same format. */
    fun formatMs(ms: Long): String {
        val totalSeconds = (ms.coerceAtLeast(0L)) / 1000L
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) {
            "%d:%02d:%02d".format(h, m, s)
        } else {
            "%d:%02d".format(m, s)
        }
    }

    /**
     * Series-runtime input is messy: `"45"` minutes, `"45m"`, `"1h 30m"`,
     * or `"0"` meaning unknown. iOS normalises into `"45 dk"` / `"1s 30dk"`
     * style; we keep that pattern.
     */
    fun seriesRuntime(raw: String?): String? {
        val r = raw?.trim().orEmpty()
        if (r.isEmpty() || r == "0") return null
        if (r.contains('m') || r.contains('h')) return r
        val minutes = r.toIntOrNull() ?: return r
        return if (minutes >= 60) {
            val h = minutes / 60
            val m = minutes % 60
            if (m > 0) "${h}s ${m}dk" else "${h}s"
        } else {
            "$minutes dk"
        }
    }

    /**
     * Splits a comma / slash / pipe-separated genre string. Xtream
     * providers vary wildly here.
     */
    fun genreList(raw: String?): List<String> {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return emptyList()
        return text.split(',', '/', '|')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }
}
