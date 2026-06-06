package dev.android.anotheriptvplayer.ui.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.Toast
import dev.android.anotheriptvplayer.R

/**
 * Hands a playback URL off to whichever installed app declares it can play
 * video MIME types — VLC, MX Player, the system video player on devices
 * that ship one, etc. Used until we ship our own Media3 player.
 *
 * Surfaces a Toast if nothing on the device handles the intent, so the
 * caller never has to silently fail.
 */
fun launchExternalPlayer(context: Context, url: String) {
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(Uri.parse(url), "video/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    val resolved = context.packageManager.resolveActivity(intent, 0)
    if (resolved != null) {
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.common_play)))
    } else {
        Toast.makeText(
            context,
            context.getString(R.string.external_player_not_found),
            Toast.LENGTH_LONG,
        ).show()
        Log.i("ExternalPlayer", "No video handler for $url")
    }
}
