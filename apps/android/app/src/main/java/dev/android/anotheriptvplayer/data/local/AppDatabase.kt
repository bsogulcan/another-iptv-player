package dev.android.anotheriptvplayer.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import dev.android.anotheriptvplayer.model.Playlist

/**
 * The app's SQLite database — the Android counterpart of iOS
 * `AppDatabase.swift`.
 *
 * Schema parity: every entity from the iOS migrations is declared up front
 * at v1 so future changes can be expressed as proper Room migrations rather
 * than retroactively rebuilding the shape. Currently only [PlaylistDao] is
 * exposed; the rest of the DAOs land alongside the features that use them.
 *
 * The `playlist` table is the only one the UI reads today.
 */
@Database(
    entities = [
        Playlist::class,
        CategoryEntity::class,
        LiveStreamEntity::class,
        VodStreamEntity::class,
        SeriesEntity::class,
        SeasonEntity::class,
        EpisodeEntity::class,
        FavoriteEntity::class,
        WatchHistoryEntity::class,
        M3uChannelEntity::class,
        M3uFavoriteEntity::class,
        DownloadedItemEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun playlistDao(): PlaylistDao
    abstract fun categoryDao(): CategoryDao
    abstract fun liveStreamDao(): LiveStreamDao
    abstract fun vodStreamDao(): VodStreamDao
    abstract fun seriesDao(): SeriesDao
    abstract fun seasonDao(): SeasonDao
    abstract fun episodeDao(): EpisodeDao
    abstract fun favoriteDao(): FavoriteDao
    abstract fun watchHistoryDao(): WatchHistoryDao
    abstract fun m3uChannelDao(): M3uChannelDao
    abstract fun m3uFavoriteDao(): M3uFavoriteDao
    abstract fun downloadedItemDao(): DownloadedItemDao

    companion object {
        private const val DB_NAME = "another-iptv.db"

        @Volatile
        private var instance: AppDatabase? = null

        fun get(context: Context): AppDatabase = instance ?: synchronized(this) {
            instance ?: build(context.applicationContext).also { instance = it }
        }

        private fun build(context: Context): AppDatabase =
            Room.databaseBuilder(context, AppDatabase::class.java, DB_NAME).build()
    }
}
