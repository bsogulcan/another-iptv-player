import Foundation
import GRDB

enum EPGRefreshPhase: Sendable, Equatable {
    case download
    case parse
    case save
}

/// Orchestrates a single playlist's EPG refresh off the main actor: resolve source
/// URL → download (conditional GET) → stream-parse into the DB → update bookkeeping.
/// `nonisolated` alone does not put it there: with this project's build settings a
/// nonisolated async function runs on its caller's actor, and the caller is the
/// main-actor `EPGStore`. `refresh` is `@concurrent` for that reason; only the
/// `progress` callback hops to the main actor.
nonisolated struct EPGRefreshCoordinator {

    struct RefreshResult: Sendable {
        var programmeCount: Int
        var channelCount: Int
        var notModified: Bool
    }

    private let downloader: EPGDownloader
    private let database: AppDatabase

    /// The app uses the defaults. Tests pass a downloader over a stubbed session
    /// and an in-memory database.
    init(downloader: EPGDownloader = EPGDownloader(), database: AppDatabase = .shared) {
        self.downloader = downloader
        self.database = database
    }

    /// Refreshes `playlist`'s guide. Records `epgSource` bookkeeping (attempt time,
    /// success/error) as a side effect and rethrows on failure.
    ///
    /// `@concurrent`: everything after the download (gunzip, XML parse, staging
    /// batches, publish) is synchronous and takes seconds on a large feed.
    @concurrent
    func refresh(playlist: Playlist,
                 progress: @escaping @MainActor (EPGRefreshPhase) -> Void) async throws -> RefreshResult {
        let candidates = try sourceCandidates(playlist: playlist)
        let sourceType: EPGSourceType = playlist.kind == .xtream ? .xtreamXMLTV : .m3uXMLTV

        // Record the attempt up front (drives the retry cooldown).
        await recordAttempt(playlistId: playlist.id, sourceType: sourceType)

        do {
            let wanted = try await gatherWanted(playlist: playlist)
            let offsetSeconds = await defaultOffsetSeconds(playlist: playlist)
            let now = Date()
            let pastWindow = pastRetention(kind: playlist.kind, maxArchiveDays: wanted.maxArchiveDays)
            let pastCutoff = Int64(now.addingTimeInterval(-pastWindow).timeIntervalSince1970)
            let futureCutoff = Int64(now.addingTimeInterval(EPGConstants.futureRetention).timeIntervalSince1970)

            await progress(.download)
            let prior = try? await database.read { db in
                try DBEPGSource.fetchOne(db, key: playlist.id)
            }

            // Try each candidate URL until one downloads + parses.
            var lastError: Error?
            for url in candidates {
                do {
                    let download = try await downloader.downloadGuide(
                        url: url,
                        etag: prior?.etag,
                        lastModified: prior?.lastModified,
                        username: playlist.username, password: playlist.password
                    )
                    switch download {
                    case .notModified:
                        try await recordSuccess(playlistId: playlist.id, sourceType: sourceType,
                                                url: url, etag: prior?.etag, lastModified: prior?.lastModified,
                                                programmeCount: prior?.programmeCount ?? 0,
                                                channelCount: prior?.channelCount ?? 0)
                        return RefreshResult(programmeCount: prior?.programmeCount ?? 0,
                                             channelCount: prior?.channelCount ?? 0, notModified: true)

                    case .file(let xmlURL, let etag, let lastModified):
                        defer { try? FileManager.default.removeItem(at: xmlURL) }
                        await progress(.parse)
                        let counts = try parseIntoDatabase(
                            fileURL: xmlURL, playlistId: playlist.id,
                            wanted: wanted, pastCutoff: pastCutoff, futureCutoff: futureCutoff,
                            offsetSeconds: offsetSeconds
                        )
                        guard counts.programmes > 0 || counts.channels > 0 else {
                            throw EPGError.emptyGuide
                        }
                        try await recordSuccess(playlistId: playlist.id, sourceType: sourceType,
                                                url: url, etag: etag, lastModified: lastModified,
                                                programmeCount: counts.programmes, channelCount: counts.channels)
                        return RefreshResult(programmeCount: counts.programmes,
                                             channelCount: counts.channels, notModified: false)
                    }
                } catch is CancellationError {
                    throw EPGError.cancelled
                } catch {
                    lastError = error
                    continue
                }
            }
            throw lastError ?? EPGError.noSource
        } catch {
            if !(error is CancellationError) {
                await recordError(playlistId: playlist.id, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            throw error
        }
    }

    // MARK: - Source resolution

    /// Candidate guide URLs in priority order (M3U `url-tvg` may be comma-separated).
    private func sourceCandidates(playlist: Playlist) throws -> [URL] {
        switch playlist.kind {
        case .xtream:
            guard let url = PlaybackURLBuilder(playlist: playlist).xmltvURL() else { throw EPGError.noSource }
            return [url]
        case .m3u:
            guard let raw = playlist.effectiveEPGURL else { throw EPGError.noSource }
            let urls = raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .compactMap { URL(string: $0) }
            guard !urls.isEmpty else { throw EPGError.noSource }
            return urls
        }
    }

    private func pastRetention(kind: PlaylistKind, maxArchiveDays: Int) -> TimeInterval {
        switch kind {
        case .m3u:
            return EPGConstants.m3uPastRetention
        case .xtream:
            let days = min(max(maxArchiveDays, EPGConstants.minCatchupPastDays), EPGConstants.maxCatchupPastDays)
            return Double(days) * 86_400
        }
    }

    private func defaultOffsetSeconds(playlist: Playlist) async -> Int {
        guard playlist.kind == .xtream else { return 0 }   // M3U offset-less → UTC
        let tz = await PanelTimeZoneResolver.resolve(playlist: playlist, database: database,
                                                     urlSession: downloader.urlSession)
        return tz.secondsFromGMT(for: Date())
    }

    // MARK: - Wanted channels

    private struct Wanted {
        var keys: Set<String>
        var names: Set<String>
        var maxArchiveDays: Int
    }

    private func gatherWanted(playlist: Playlist) async throws -> Wanted {
        try await database.read { db in
            var keys = Set<String>()
            var names = Set<String>()
            var maxArchive = 0
            if playlist.kind == .xtream {
                let rows = try DBLiveStream.fetchAll(db, sql: "SELECT * FROM liveStream WHERE playlistId = ?", arguments: [playlist.id])
                for r in rows {
                    if let k = EPGConstants.normalizeChannelKey(r.epgChannelId) { keys.insert(k) }
                    if let n = EPGConstants.normalizeChannelKey(r.name) { names.insert(n) }
                    if r.tvArchive == 1 { maxArchive = max(maxArchive, r.tvArchiveDuration) }
                }
            } else {
                let rows = try DBM3UChannel.fetchAll(db, sql: "SELECT * FROM m3uChannel WHERE playlistId = ?", arguments: [playlist.id])
                for r in rows {
                    if let k = EPGConstants.normalizeChannelKey(r.tvgId) { keys.insert(k) }
                    if let n = EPGConstants.normalizeChannelKey(r.tvgName ?? r.name) { names.insert(n) }
                }
            }
            return Wanted(keys: keys, names: names, maxArchiveDays: maxArchive)
        }
    }

    // MARK: - Parse + write

    private func parseIntoDatabase(fileURL: URL, playlistId: UUID, wanted: Wanted,
                                   pastCutoff: Int64, futureCutoff: Int64, offsetSeconds: Int) throws -> (programmes: Int, channels: Int) {
        // Synchronous from here to the publish, and every batch blocks its thread
        // on the database writer. Debug builds and the unit tests stop a change
        // that brings it back onto the main thread; a release build would stall,
        // not crash.
        assert(!Thread.isMainThread, "the guide parse must not run on the main thread")
        // Build the replacement in staging. The live guide remains readable while
        // XML parsing and batched inserts are in progress.
        try database.writeSync { db in
            try db.execute(sql: "DELETE FROM epgProgrammeStaging WHERE playlistId = ?", arguments: [playlistId])
            try db.execute(sql: "DELETE FROM epgChannelStaging WHERE playlistId = ?", arguments: [playlistId])
        }
        defer { try? discardStagedGuide(playlistId: playlistId) }

        var programmeCount = 0
        var channelCount = 0
        var writeError: Error?

        let options = EPGXMLTVParser.Options(
            wantedChannelIds: wanted.keys,
            wantedDisplayNames: wanted.names,
            pastCutoffTs: pastCutoff,
            futureCutoffTs: futureCutoff,
            defaultUTCOffsetSeconds: offsetSeconds
        )

        let parser = EPGXMLTVParser(
            options: options,
            onChannelBatch: { batch in
                if Task.isCancelled { return false }
                do {
                    try database.writeSync { db in
                        for c in batch {
                            try db.execute(sql: """
                                INSERT OR REPLACE INTO epgChannelStaging
                                    (playlistId, channelKey, displayName, iconURL)
                                VALUES (?, ?, ?, ?)
                                """, arguments: [playlistId, c.id, c.displayNames.first, c.iconURL])
                        }
                    }
                    channelCount += batch.count
                    return true
                } catch { writeError = error; return false }
            },
            onProgrammeBatch: { batch in
                if Task.isCancelled { return false }
                do {
                    try database.writeSync { db in
                        for p in batch {
                            try db.execute(sql: """
                                INSERT OR REPLACE INTO epgProgrammeStaging
                                    (playlistId, channelKey, startTs, stopTs, title,
                                     subtitle, desc, category, iconURL, episodeNum)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                """, arguments: [
                                    playlistId, p.channelKey, p.startTs, p.stopTs, p.title,
                                    p.subtitle, p.desc, p.category, p.iconURL, p.episodeNum
                                ])
                        }
                    }
                    programmeCount += batch.count
                    return true
                } catch { writeError = error; return false }
            }
        )

        _ = try parser.parse(fileURL: fileURL)
        if let writeError { throw writeError }
        try publishStagedGuide(playlistId: playlistId)
        return (programmeCount, channelCount)
    }

    /// Swaps staging into the live tables atomically. Readers on the GRDB pool see
    /// either the complete old guide or the complete new guide, never a partial one.
    private func publishStagedGuide(playlistId: UUID) throws {
        try database.writeSync { db in
            try Self.publishStagedGuide(in: db, playlistId: playlistId)
        }
    }

    /// Kept internal so the transactional replacement can be covered by an
    /// in-memory database test without downloading and parsing a whole feed.
    nonisolated static func publishStagedGuide(in db: Database, playlistId: UUID) throws {
        try db.execute(sql: "DELETE FROM epgProgramme WHERE playlistId = ?", arguments: [playlistId])
        try db.execute(sql: "DELETE FROM epgChannel WHERE playlistId = ?", arguments: [playlistId])

        try db.execute(sql: """
            INSERT INTO epgChannel (playlistId, channelKey, displayName, iconURL)
            SELECT playlistId, channelKey, displayName, iconURL
            FROM epgChannelStaging WHERE playlistId = ?
            """, arguments: [playlistId])
        try db.execute(sql: """
            INSERT INTO epgProgramme
                (playlistId, channelKey, startTs, stopTs, title,
                 subtitle, desc, category, iconURL, episodeNum)
            SELECT playlistId, channelKey, startTs, stopTs, title,
                   subtitle, desc, category, iconURL, episodeNum
            FROM epgProgrammeStaging WHERE playlistId = ?
            """, arguments: [playlistId])

        try db.execute(sql: "DELETE FROM epgProgrammeStaging WHERE playlistId = ?", arguments: [playlistId])
        try db.execute(sql: "DELETE FROM epgChannelStaging WHERE playlistId = ?", arguments: [playlistId])
    }

    private func discardStagedGuide(playlistId: UUID) throws {
        try database.writeSync { db in
            try db.execute(sql: "DELETE FROM epgProgrammeStaging WHERE playlistId = ?", arguments: [playlistId])
            try db.execute(sql: "DELETE FROM epgChannelStaging WHERE playlistId = ?", arguments: [playlistId])
        }
    }

    // MARK: - Bookkeeping

    private func recordAttempt(playlistId: UUID, sourceType: EPGSourceType) async {
        try? await database.write { db in
            var src = try DBEPGSource.fetchOne(db, key: playlistId) ?? DBEPGSource(playlistId: playlistId, sourceType: sourceType.rawValue)
            src.sourceType = sourceType.rawValue
            src.fetchedAt = Date()
            try src.save(db)
        }
    }

    private func recordSuccess(playlistId: UUID, sourceType: EPGSourceType, url: URL,
                               etag: String?, lastModified: String?,
                               programmeCount: Int, channelCount: Int) async throws {
        try await database.write { db in
            var src = try DBEPGSource.fetchOne(db, key: playlistId) ?? DBEPGSource(playlistId: playlistId, sourceType: sourceType.rawValue)
            src.sourceType = sourceType.rawValue
            src.url = url.absoluteString
            src.fetchedAt = Date()
            src.lastSuccessAt = Date()
            src.lastError = nil
            src.etag = etag
            src.lastModified = lastModified
            src.programmeCount = programmeCount
            src.channelCount = channelCount
            try src.save(db)
        }
    }

    private func recordError(playlistId: UUID, message: String) async {
        try? await database.write { db in
            guard var src = try DBEPGSource.fetchOne(db, key: playlistId) else { return }
            src.lastError = message
            try src.save(db)
        }
    }
}
