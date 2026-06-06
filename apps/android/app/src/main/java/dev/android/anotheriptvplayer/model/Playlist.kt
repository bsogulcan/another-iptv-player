package dev.android.anotheriptvplayer.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Ignore
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Playlist source type, mirroring the iOS `PlaylistKind` enum.
 *
 * The raw value matches the iOS DB string ("xtream" / "m3u") so the schema
 * stays portable as a reference even though each platform has its own SQLite
 * file.
 */
enum class PlaylistKind(val dbValue: String) {
    XTREAM("xtream"),
    M3U("m3u");

    companion object {
        fun fromDbValue(value: String?): PlaylistKind =
            entries.firstOrNull { it.dbValue == value } ?: XTREAM
    }
}

/**
 * A user-configured IPTV playlist — also the Room entity for the `playlist`
 * table.
 *
 * Doubles as the UI model and the persisted row, matching the iOS pattern
 * where `Playlist` is both `Codable` and `PersistableRecord`.
 */
@Entity(tableName = "playlist")
data class Playlist(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val serverUrl: String,
    val username: String = "",
    val password: String = "",
    val createdAt: Long = System.currentTimeMillis(),
    val filterAdultContent: Boolean = false,
    /** Stored as the raw string ("xtream" / "m3u") — see [PlaylistKind.dbValue]. */
    @ColumnInfo(name = "type")
    val typeRaw: String = PlaylistKind.XTREAM.dbValue,
    val m3uEpgUrl: String? = null,
) {
    /** Convenience accessor over the persisted [typeRaw] column. */
    @get:Ignore
    val kind: PlaylistKind
        get() = PlaylistKind.fromDbValue(typeRaw)

    companion object {
        /** Constructor mirroring iOS — accepts [PlaylistKind] directly. */
        fun create(
            id: String = UUID.randomUUID().toString(),
            name: String,
            serverUrl: String,
            username: String = "",
            password: String = "",
            kind: PlaylistKind = PlaylistKind.XTREAM,
            filterAdultContent: Boolean = false,
            m3uEpgUrl: String? = null,
            createdAt: Long = System.currentTimeMillis(),
        ): Playlist = Playlist(
            id = id,
            name = name,
            serverUrl = serverUrl,
            username = username,
            password = password,
            createdAt = createdAt,
            filterAdultContent = filterAdultContent,
            typeRaw = kind.dbValue,
            m3uEpgUrl = m3uEpgUrl,
        )
    }
}
