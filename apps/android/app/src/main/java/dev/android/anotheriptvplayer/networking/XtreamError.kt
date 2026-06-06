package dev.android.anotheriptvplayer.networking

import android.content.Context
import dev.android.anotheriptvplayer.R

/**
 * Typed failure surface for Xtream calls — Kotlin mirror of iOS
 * `XtreamError`.
 *
 * The exception's [message] is a developer-readable English summary; for the
 * user-facing localised string call [userMessage] with a Context. Keeping
 * `message` ASCII-only avoids leaking untranslated text into UI when a caller
 * forgets to localise.
 */
sealed class XtreamException(message: String, cause: Throwable? = null) :
    Exception(message, cause) {

    abstract fun userMessage(context: Context): String

    /** The composed URL is malformed (bad scheme, empty host, etc.). */
    class InvalidUrl(val url: String) :
        XtreamException("Invalid Xtream URL: $url") {
        override fun userMessage(context: Context): String =
            context.getString(R.string.xtream_error_invalid_url, url)
    }

    /** Underlying transport failure — DNS, timeout, TLS, no internet. */
    class Network(cause: Throwable) :
        XtreamException("Network error: ${cause.message ?: cause.javaClass.simpleName}", cause) {
        override fun userMessage(context: Context): String =
            context.getString(
                R.string.xtream_error_network,
                cause?.message ?: cause?.javaClass?.simpleName.orEmpty(),
            )
    }

    /** `user_info` is missing or `auth == 0`. */
    class Unauthenticated :
        XtreamException("Xtream authentication failed.") {
        override fun userMessage(context: Context): String =
            context.getString(R.string.add_xtream_auth_failed)
    }

    /** JSON didn't decode — payload likely doesn't match the expected shape. */
    class Decoding(cause: Throwable) :
        XtreamException("Could not decode server response: ${cause.message ?: cause.javaClass.simpleName}", cause) {
        override fun userMessage(context: Context): String =
            context.getString(
                R.string.xtream_error_decoding,
                cause?.message ?: cause?.javaClass?.simpleName.orEmpty(),
            )
    }

    /** Non-2xx HTTP response. */
    class Server(val status: String) :
        XtreamException("Server error: $status") {
        override fun userMessage(context: Context): String =
            context.getString(R.string.xtream_error_server, status)
    }
}
