package dev.android.anotheriptvplayer.player

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Kotlin port of iOS `SubtitleAppearanceSettings` (Models/).
 *
 * Same fields, same value ranges, same persistence key — so backups and
 * cross-platform docs stay accurate. The values are written verbatim into
 * libmpv `sub-*` properties via [applyToPlayer].
 */
@Serializable
data class SubtitleAppearance(
    val fontSize: Int = 36,
    val lineHeight: Double = 1.2,
    val letterSpacing: Double = 0.0,
    val wordSpacing: Double = 0.0,
    val padding: Int = 24,
    /** 24-bit RGB packed integer, e.g. `0xFFFFFF`. */
    val textColorHex6: Long = 0xFFFFFFL,
    val backgroundEnabled: Boolean = false,
    val backgroundColorHex6: Long = 0x000000L,
    val backgroundOpacity: Double = 0.5,
    val fontWeight: FontWeight = FontWeight.NORMAL,
    val textAlignment: TextAlignment = TextAlignment.CENTER,
    val italic: Boolean = false,
    val outlineSize: Double = 2.0,
    val outlineColorHex6: Long = 0x000000L,
    val verticalOffset: Int = 0,
    val delaySeconds: Double = 0.0,
) {
    enum class FontWeight { THIN, NORMAL, MEDIUM, BOLD, EXTRA_BOLD }
    enum class TextAlignment { LEFT, CENTER, RIGHT, JUSTIFY }

    fun clamp(): SubtitleAppearance = copy(
        fontSize = fontSize.coerceIn(24, 96),
        lineHeight = lineHeight.coerceIn(1.0, 2.5),
        letterSpacing = letterSpacing.coerceIn(-2.0, 5.0),
        wordSpacing = wordSpacing.coerceIn(-2.0, 10.0),
        padding = padding.coerceIn(8, 48),
        backgroundOpacity = backgroundOpacity.coerceIn(0.0, 1.0),
        outlineSize = outlineSize.coerceIn(0.0, 6.0),
        verticalOffset = verticalOffset.coerceIn(-120, 120),
        delaySeconds = delaySeconds.coerceIn(-10.0, 10.0),
    )
}

/** UserDefaults equivalent. iOS key: `playback.subtitleAppearance.v2`. */
class SubtitleAppearanceStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("playback", Context.MODE_PRIVATE)

    fun load(): SubtitleAppearance {
        val raw = prefs.getString(KEY, null) ?: return SubtitleAppearance().clamp()
        return runCatching { jsonCodec.decodeFromString<SubtitleAppearance>(raw) }
            .getOrDefault(SubtitleAppearance())
            .clamp()
    }

    fun save(settings: SubtitleAppearance) {
        prefs.edit()
            .putString(KEY, jsonCodec.encodeToString(settings.clamp()))
            .apply()
    }

    companion object {
        private const val KEY = "subtitleAppearance.v2"
        private val jsonCodec = Json { ignoreUnknownKeys = true }
    }
}

/**
 * Translates a [SubtitleAppearance] into libmpv `sub-*` property writes.
 * Public so PlayerScreen can apply settings without reaching into MPVLib
 * directly. iOS does the same translation in `MPVPlayer.applySubtitleAppearance`.
 */
fun MPVPlayer.applySubtitleAppearance(settings: SubtitleAppearance) {
    val s = settings.clamp()
    val rgbText = "#%06X".format(s.textColorHex6 and 0xFFFFFFL)
    val rgbOutline = "#%06X".format(s.outlineColorHex6 and 0xFFFFFFL)
    setSubtitleDelay(s.delaySeconds)
    // We can't expose `MPVLib.setPropertyString` here without leaking that
    // class out of the package, so route writes through helper bindings on
    // MPVPlayer.
    setSubtitleProperty("sub-ass-override", "force")
    setSubtitleProperty("sub-font-size", s.fontSize.toString())
    setSubtitleProperty("sub-scale", "1.0")
    setSubtitleProperty("sub-line-spacing", (s.fontSize * (s.lineHeight - 1.0)).toString())
    setSubtitleProperty("sub-spacing", s.letterSpacing.toString())
    setSubtitleProperty("sub-margin-x", s.padding.toString())
    setSubtitleProperty(
        "sub-margin-y",
        maxOf(s.padding, kotlin.math.abs(s.verticalOffset)).toString(),
    )
    setSubtitleProperty("sub-color", rgbText)
    setSubtitleProperty(
        "sub-bold",
        if (s.fontWeight == SubtitleAppearance.FontWeight.BOLD ||
            s.fontWeight == SubtitleAppearance.FontWeight.EXTRA_BOLD) "yes" else "no",
    )
    setSubtitleProperty("sub-italic", if (s.italic) "yes" else "no")
    setSubtitleProperty(
        "sub-align-x",
        when (s.textAlignment) {
            SubtitleAppearance.TextAlignment.LEFT -> "left"
            SubtitleAppearance.TextAlignment.RIGHT -> "right"
            else -> "center"
        },
    )
    setSubtitleProperty("sub-border-size", s.outlineSize.toString())
    setSubtitleProperty("sub-border-color", rgbOutline)
    if (s.backgroundEnabled) {
        val a = (s.backgroundOpacity * 255.0).toInt().coerceIn(0, 255)
        // sub-back-color expects #AARRGGBB; mpv accepts hash + 8 hex digits.
        val rgb = s.backgroundColorHex6 and 0xFFFFFFL
        setSubtitleProperty("sub-back-color", "#%02X%06X".format(a, rgb))
        setSubtitleProperty("sub-border-style", "opaque-box")
    } else {
        setSubtitleProperty("sub-border-style", "outline-and-shadow")
    }
}
