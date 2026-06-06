package dev.android.anotheriptvplayer.data.local

import androidx.room.Embedded

/**
 * Join-result projections that pull a stream/series row together with its
 * category's display name. iOS uses GRDB's
 * `LiveStreamWithCategory` / `VODWithCategory` / `SeriesWithCategory` for
 * the same purpose.
 *
 * `categoryName` comes from a left-join in the DAO query — keeping it on the
 * projection means UI doesn't have to look the name up against a parallel
 * category list.
 */
data class LiveStreamWithCategory(
    @Embedded val stream: LiveStreamEntity,
    val categoryName: String,
) {
    val id: String get() = "${stream.streamId}_${stream.playlistId}"
}

data class VodStreamWithCategory(
    @Embedded val stream: VodStreamEntity,
    val categoryName: String,
) {
    val id: String get() = "${stream.streamId}_${stream.playlistId}"
}

data class SeriesWithCategory(
    @Embedded val series: SeriesEntity,
    val categoryName: String,
) {
    val id: String get() = "${series.seriesId}_${series.playlistId}"
}
