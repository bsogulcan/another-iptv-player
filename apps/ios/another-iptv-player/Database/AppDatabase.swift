import Foundation
import GRDB

/// `nonisolated`: GRDB's DatabaseQueue/DatabasePool are Sendable and internally
/// synchronized, and reads/writes are issued from background contexts (EPG
/// refresh, UITest fixtures) as well as the main actor.
nonisolated struct AppDatabase {
    private let dbWriter: any DatabaseWriter
    
    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("initial") { db in
            // Playlists
            try db.create(table: "playlist") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("serverURL", .text).notNull()
                t.column("username", .text).notNull()
                t.column("password", .text).notNull()
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
            }
            
            // Categories
            try db.create(table: "category") { t in
                t.column("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("parentId", .integer)
                t.column("type", .text).notNull() // live, vod, series
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.primaryKey(["id", "playlistId", "type"])
            }
            
            // Live Streams
            try db.create(table: "liveStream") { t in
                t.column("streamId", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("streamIcon", .text)
                t.column("epgChannelId", .text)
                t.column("categoryId", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.primaryKey(["streamId", "playlistId"])
            }
            
            // VOD Streams
            try db.create(table: "vodStream") { t in
                t.column("streamId", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("streamIcon", .text)
                t.column("categoryId", .text)
                t.column("rating", .text)
                t.column("containerExtension", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.primaryKey(["streamId", "playlistId"])
            }
            
            // Series
            try db.create(table: "series") { t in
                t.column("seriesId", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("cover", .text)
                t.column("plot", .text)
                t.column("genre", .text)
                t.column("rating", .text)
                t.column("categoryId", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("seasonsLoaded", .boolean).notNull().defaults(to: false)
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.primaryKey(["seriesId", "playlistId"])
            }
            
            // Seasons
            try db.create(table: "season") { t in
                t.column("id", .text).primaryKey()
                t.column("seasonNumber", .integer).notNull()
                t.column("name", .text)
                t.column("overview", .text)
                t.column("cover", .text)
                t.column("seriesId", .integer).notNull()
                t.column("playlistId", .text).notNull()
                t.foreignKey(["seriesId", "playlistId"], references: "series", columns: ["seriesId", "playlistId"], onDelete: .cascade)
            }
            
            // Episodes
            try db.create(table: "episode") { t in
                t.column("id", .text).primaryKey()
                t.column("episodeId", .text)
                t.column("episodeNum", .integer)
                t.column("title", .text)
                t.column("containerExtension", .text)
                t.column("info", .text)
                t.column("cover", .text)
                t.column("duration", .text)
                t.column("rating", .text)
                t.column("seasonId", .text).notNull()
                    .references("season", column: "id", onDelete: .cascade)
            }
        }

        migrator.registerMigration("addComprehensiveSeriesMetadata") { db in
            try db.alter(table: "series") { t in
                t.add(column: "cast", .text)
                t.add(column: "director", .text)
                t.add(column: "releaseDate", .text)
                t.add(column: "lastModified", .text)
                t.add(column: "rating5Based", .double)
                t.add(column: "backdropPath", .text)
                t.add(column: "youtubeTrailer", .text)
                t.add(column: "episodeRunTime", .text)
            }
            try db.alter(table: "season") { t in
                t.add(column: "airDate", .text)
                t.add(column: "episodeCount", .integer)
                t.add(column: "voteAverage", .double)
            }
        }

        migrator.registerMigration("addVODMetadata") { db in
            try db.alter(table: "vodStream") { t in
                t.add(column: "director", .text)
                t.add(column: "cast", .text)
                t.add(column: "plot", .text)
                t.add(column: "genre", .text)
                t.add(column: "releaseDate", .text)
                t.add(column: "rating5Based", .double)
                t.add(column: "backdropPath", .text)
                t.add(column: "youtubeTrailer", .text)
                t.add(column: "duration", .text)
                t.add(column: "tmdbId", .text)
                t.add(column: "kinopoiskURL", .text)
                t.add(column: "metadataLoaded", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("addFavoritesTable") { db in
            try db.create(table: "favorite") { t in
                t.column("streamId", .integer).notNull()
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("type", .text).notNull() // live, vod, series
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
                t.primaryKey(["streamId", "playlistId", "type"])
            }
        }

        migrator.registerMigration("addWatchHistoryTable") { db in
            try db.create(table: "watchHistory") { t in
                t.column("id", .text).primaryKey()
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("streamId", .text).notNull()
                t.column("type", .text).notNull() // live, vod, series
                t.column("lastTimeMs", .integer).notNull().defaults(to: 0)
                t.column("durationMs", .integer).notNull().defaults(to: 0)
                t.column("lastWatchedAt", .datetime).notNull().defaults(to: Date())
                t.column("title", .text).notNull()
                t.column("secondaryTitle", .text)
                t.column("imageURL", .text)
                t.column("seriesId", .text)
            }
            try db.create(index: "index_watchHistory_lastWatchedAt", on: "watchHistory", columns: ["lastWatchedAt"])
        }

        migrator.registerMigration("addExtensionToWatchHistory") { db in
            try db.alter(table: "watchHistory") { t in
                t.add(column: "containerExtension", .text)
            }
        }

        migrator.registerMigration("epgShortCache") { db in
            try db.create(table: "epgShortCache") { t in
                t.column("playlistId", .text).notNull()
                t.column("streamId", .integer).notNull()
                t.column("payload", .blob).notNull()
                t.column("fetchedAt", .datetime).notNull()
                t.primaryKey(["playlistId", "streamId"])
            }
        }

        migrator.registerMigration("xmltvGuideCache") { db in
            try db.create(table: "xmltvGuideCache") { t in
                t.column("playlistId", .text).primaryKey()
                t.column("xmlData", .blob).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("xmltvGuideParsedIndex") { db in
            try db.alter(table: "xmltvGuideCache") { t in
                t.add(column: "parsedIndexData", .blob)
            }
        }

        migrator.registerMigration("addFilterAdultContentToPlaylist") { db in
            try db.alter(table: "playlist") { t in
                t.add(column: "filterAdultContent", .boolean).notNull().defaults(to: false)
            }
        }

        // Composite indexes: playlistId filter + sortIndex ordering → full table scan yerine index range scan
        migrator.registerMigration("addStreamIndexes") { db in
            try db.create(index: "idx_liveStream_playlist_sort",   on: "liveStream", columns: ["playlistId", "sortIndex"], ifNotExists: true)
            try db.create(index: "idx_vodStream_playlist_sort",    on: "vodStream",  columns: ["playlistId", "sortIndex"], ifNotExists: true)
            try db.create(index: "idx_series_playlist_sort",       on: "series",     columns: ["playlistId", "sortIndex"], ifNotExists: true)
            try db.create(index: "idx_category_playlist_type_sort", on: "category",  columns: ["playlistId", "type", "sortIndex"], ifNotExists: true)
        }

        // EPG kaldırıldı: eski kurulumlarda disk'i ve index referanslarını temizle.
        migrator.registerMigration("dropLegacyEPGTables") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS xmltvGuideCache")
            try db.execute(sql: "DROP TABLE IF EXISTS epgShortCache")
        }

        // M3U / M3U8 playlist desteği: Xtream şeması dışına dokunmadan
        // playlist türü ayrımı ve m3uChannel tablosu eklenir.
        migrator.registerMigration("addM3USupport") { db in
            try db.alter(table: "playlist") { t in
                t.add(column: "type", .text).notNull().defaults(to: "xtream")
                t.add(column: "m3uEpgURL", .text)
            }

            try db.create(table: "m3uChannel") { t in
                t.column("id", .text).primaryKey()
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("tvgId", .text)
                t.column("tvgName", .text)
                t.column("tvgLogo", .text)
                t.column("tvgCountry", .text)
                t.column("groupTitle", .text)
                t.column("userAgent", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
            }
            try db.create(
                index: "idx_m3uChannel_playlist_group",
                on: "m3uChannel",
                columns: ["playlistId", "groupTitle", "sortIndex"],
                ifNotExists: true
            )
        }

        // M3U favoriler: mevcut `favorite` tablosu INTEGER streamId kullandığı için M3U UUID'leri
        // için uygun değil. Ayrı tablo.
        migrator.registerMigration("addM3UFavorites") { db in
            try db.create(table: "m3uFavorite") { t in
                t.column("channelId", .text).notNull()
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
                t.primaryKey(["channelId", "playlistId"])
            }
            try db.create(
                index: "idx_m3uFavorite_playlist",
                on: "m3uFavorite",
                columns: ["playlistId", "createdAt"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("addDownloadedItemTable") { db in
            try db.create(table: "downloadedItem") { t in
                t.column("id", .text).primaryKey()
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("streamId", .text).notNull()
                t.column("type", .text).notNull() // "vod" or "episode"
                t.column("title", .text).notNull()
                t.column("secondaryTitle", .text)
                t.column("imageURL", .text)
                t.column("remoteURL", .text).notNull()
                t.column("localPath", .text).notNull()
                t.column("containerExtension", .text)
                t.column("totalBytes", .integer).notNull().defaults(to: 0)
                t.column("downloadedBytes", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull() // downloading, completed, failed
                t.column("errorMessage", .text)
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
                t.column("completedAt", .datetime)
                t.column("seriesId", .text)
                t.column("seasonNumber", .integer)
                t.column("episodeNumber", .integer)
            }
            try db.create(
                index: "idx_downloadedItem_playlist",
                on: "downloadedItem",
                columns: ["playlistId", "createdAt"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("addVODAddedTimestamp") { db in
            try db.alter(table: "vodStream") { t in
                t.add(column: "added", .text)
            }
            try db.create(
                index: "idx_vodStream_playlist_added",
                on: "vodStream",
                columns: ["playlistId", "added"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_series_playlist_lastModified",
                on: "series",
                columns: ["playlistId", "lastModified"],
                ifNotExists: true
            )
        }

        // Sezon/bölüm PK'ları playlist kapsamına alındı (bkz. DBSeason.scopedId): eski
        // çıplak "\(seriesId)_\(seasonNum)" anahtarlı satırlar playlist'ler arası REPLACE
        // çakışması taşıyor. Temizle ve seasonsLoaded'ı sıfırla — sezonlar ilk açılışta
        // panelden yeniden çekilir; izleme geçmişi (panel episodeId ile) etkilenmez.
        migrator.registerMigration("scopeSeasonEpisodeIdsByPlaylist") { db in
            try db.execute(sql: "DELETE FROM episode")
            try db.execute(sql: "DELETE FROM season")
            try db.execute(sql: "UPDATE series SET seasonsLoaded = 0")
        }

        // SQLite FK child kolonlarını otomatik indekslemez. season/episode cascade FK'leri
        // indekssiz kalınca her series silmesi tüm season tablosunu, her season silmesi tüm
        // episode tablosunu tarıyordu (refresh ve playlist silme O(n²)). EpisodesRequest'in
        // seasonId filtresi de aynı indeksi kullanır.
        migrator.registerMigration("addSeasonEpisodeFKIndexes") { db in
            try db.create(
                index: "idx_season_series_playlist",
                on: "season",
                columns: ["seriesId", "playlistId"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_episode_seasonId",
                on: "episode",
                columns: ["seasonId"],
                ifNotExists: true
            )
        }

        // EPG (Electronic Programme Guide). A previous EPG attempt used blob caches
        // (epgShortCache/xmltvGuideCache) that were later dropped; those migration
        // names are burned, so a fresh normalized schema is added here. Programme
        // rows are keyed by a normalized channelKey (trimmed+lowercased XMLTV id /
        // Xtream epg_channel_id / M3U tvg-id) so lookups survive the case mismatches
        // feeds and playlists routinely disagree on.
        migrator.registerMigration("addEPGSupport") { db in
            try db.create(table: "epgProgramme") { t in
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("channelKey", .text).notNull()
                t.column("startTs", .integer).notNull()   // unix epoch seconds, UTC
                t.column("stopTs", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("desc", .text)
                t.column("category", .text)
                t.column("iconURL", .text)
                t.column("episodeNum", .text)
                t.primaryKey(["playlistId", "channelKey", "startTs"], onConflict: .replace)
            }
            // Retention pruning (DELETE WHERE stopTs < cutoff) + "on air now" range scans.
            try db.create(
                index: "idx_epgProgramme_playlist_stop",
                on: "epgProgramme",
                columns: ["playlistId", "stopTs"],
                ifNotExists: true
            )

            try db.create(table: "epgChannel") { t in
                t.column("playlistId", .text).notNull()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("channelKey", .text).notNull()
                t.column("displayName", .text)            // first display-name, original case
                t.column("iconURL", .text)
                t.primaryKey(["playlistId", "channelKey"], onConflict: .replace)
            }

            // TTL / bookkeeping, one row per playlist (single EPG source in v1).
            try db.create(table: "epgSource") { t in
                t.column("playlistId", .text).primaryKey()
                    .references("playlist", column: "id", onDelete: .cascade)
                t.column("sourceType", .text).notNull()   // "xtream_xmltv" | "m3u_xmltv" | "xtream_json"
                t.column("url", .text)                    // resolved URL actually fetched
                t.column("fetchedAt", .datetime)          // last attempt
                t.column("lastSuccessAt", .datetime)      // TTL anchor
                t.column("lastError", .text)              // localized, for settings UI
                t.column("etag", .text)                   // conditional GET
                t.column("lastModified", .text)
                t.column("programmeCount", .integer).notNull().defaults(to: 0)
                t.column("channelCount", .integer).notNull().defaults(to: 0)
            }

            try db.alter(table: "playlist") { t in
                // Manual EPG URL override for M3U playlists. effectiveEPGURL =
                // epgURLOverride ?? m3uEpgURL, so re-imports keep refreshing the
                // header value without clobbering a user-entered URL.
                t.add(column: "epgURLOverride", .text)
                t.add(column: "epgEnabled", .boolean).notNull().defaults(to: true)
            }
        }

        // Catch-up (timeshift) support: archive flags from get_live_streams (raw
        // panel JSON has them but they were never decoded) plus the panel timezone
        // and probed timeshift URL style needed to build valid timeshift requests.
        migrator.registerMigration("addCatchupSupport") { db in
            try db.alter(table: "liveStream") { t in
                t.add(column: "tvArchive", .integer).notNull().defaults(to: 0)
                t.add(column: "tvArchiveDuration", .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "playlist") { t in
                t.add(column: "serverTimezone", .text)   // IANA name from server_info
                // Probe result cache. Written by TimeshiftStyleCache: "m3u8" | "path" | "php",
                // or "path-no-m3u8" | "php-no-m3u8" (same column, no migration needed).
                t.add(column: "timeshiftStyle", .text)
            }
            try db.alter(table: "m3uChannel") { t in
                t.add(column: "catchup", .text)
                t.add(column: "catchupSource", .text)
                t.add(column: "catchupDays", .integer)
            }
        }

        // Parse refreshed XMLTV data into staging tables first. Publishing then
        // becomes one short transaction, so guide readers never observe the gap
        // between deleting the old guide and filling the new one batch by batch.
        migrator.registerMigration("addEPGRefreshStaging") { db in
            try db.create(table: "epgProgrammeStaging") { t in
                t.column("playlistId", .text).notNull()
                t.column("channelKey", .text).notNull()
                t.column("startTs", .integer).notNull()
                t.column("stopTs", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("desc", .text)
                t.column("category", .text)
                t.column("iconURL", .text)
                t.column("episodeNum", .text)
                t.primaryKey(["playlistId", "channelKey", "startTs"], onConflict: .replace)
            }

            try db.create(table: "epgChannelStaging") { t in
                t.column("playlistId", .text).notNull()
                t.column("channelKey", .text).notNull()
                t.column("displayName", .text)
                t.column("iconURL", .text)
                t.primaryKey(["playlistId", "channelKey"], onConflict: .replace)
            }
        }

        return migrator
    }
}

// MARK: - Database Access
nonisolated extension AppDatabase {
    var reader: any DatabaseReader { dbWriter }

    /// Synchronous write — used by UITest-only fixtures during App.init,
    /// where we must finish seeding before the SwiftUI view tree appears
    /// (semaphores would block the main thread and hang XCUITest's idle check).
    func writeSync<T>(_ updates: (Database) throws -> T) throws -> T {
        try dbWriter.write(updates)
    }
}

nonisolated extension AppDatabase {
    func write<T>(_ updates: @escaping (Database) throws -> T) async throws -> T {
        try await dbWriter.write { db in
            try updates(db)
        }
    }
    
    func read<T>(_ value: @escaping (Database) throws -> T) async throws -> T {
        try await dbWriter.read { db in
            try value(db)
        }
    }
}
