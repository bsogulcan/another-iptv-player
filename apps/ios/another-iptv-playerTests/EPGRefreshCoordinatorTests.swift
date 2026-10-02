import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// Records on which thread the guide's staging table is written. GRDB runs a
/// synchronous write on the thread that asked for it, so this is the thread the
/// parse runs on.
private nonisolated final class StagingWriteProbe: TransactionObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var writeCount = 0
    private var mainThreadWriteCount = 0

    var writes: Int {
        lock.lock()
        defer { lock.unlock() }
        return writeCount
    }

    var mainThreadWrites: Int {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadWriteCount
    }

    /// Inserts only: publishing the guide empties the table again.
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        if case .insert(let tableName) = eventKind { return tableName == "epgProgrammeStaging" }
        return false
    }

    func databaseDidChange(with event: DatabaseEvent) {
        lock.lock()
        defer { lock.unlock() }
        writeCount += 1
        if Thread.isMainThread { mainThreadWriteCount += 1 }
    }

    func databaseDidCommit(_ db: Database) {}
    func databaseDidRollback(_ db: Database) {}
}

/// The guide refresh end to end, against a stubbed session and an in-memory
/// database: where it runs, and what it leaves behind.
@Suite("EPG refresh coordinator")
struct EPGRefreshCoordinatorTests {

    private nonisolated func isOnMainThread() -> Bool { Thread.isMainThread }

    private func makeCoordinator(_ database: AppDatabase) -> EPGRefreshCoordinator {
        EPGRefreshCoordinator(downloader: EPGTestSupport.stubbedDownloader(), database: database)
    }

    /// An M3U playlist with `channelCount` channels, ids `ch0.tv`, `ch1.tv`, …
    private func makePlaylist(host: String, channelCount: Int, in database: AppDatabase) async throws -> Playlist {
        let playlist = EPGTestSupport.m3uPlaylist(host: host)
        try await database.write { db in
            try playlist.insert(db)
            for index in 0..<channelCount {
                try DBM3UChannel(id: "channel-\(index)", playlistId: playlist.id, name: "Channel \(index)",
                                 url: "http://stream.invalid/\(index).ts", tvgId: "ch\(index).tv",
                                 sortIndex: index).insert(db)
            }
        }
        return playlist
    }

    /// The store that starts a refresh is main-actor isolated, and with this
    /// project's build settings a nonisolated async function runs on its caller's
    /// actor. The parse and its writes take seconds on a large feed, so they have
    /// to leave it. A change that brings them back is also stopped by the
    /// assertion at the top of the parse, before this test gets to report it.
    @Test
    func aRefreshStartedOnTheMainActorParsesAndWritesOffTheMainThread() async throws {
        #expect(isOnMainThread())
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let channelCount = 40
        let playlist = try await makePlaylist(host: host, channelCount: channelCount, in: database)
        let ids = (0..<channelCount).map { "ch\($0).tv" }
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: ids, programmesPerChannel: 6), onHost: host)

        let probe = StagingWriteProbe()
        try await database.write { db in db.add(transactionObserver: probe, extent: .databaseLifetime) }

        var phases: [EPGRefreshPhase] = []
        var progressWasOnMainThread = true
        let result = try await makeCoordinator(database).refresh(playlist: playlist) { phase in
            phases.append(phase)
            if !Thread.isMainThread { progressWasOnMainThread = false }
        }

        #expect(result.channelCount == channelCount)
        #expect(result.programmeCount == channelCount * 6)
        #expect(!result.notModified)
        #expect(probe.writes == channelCount * 6)
        #expect(probe.mainThreadWrites == 0)
        // Progress still arrives on the main actor: it updates published state.
        #expect(phases == [.download, .parse])
        #expect(progressWasOnMainThread)
        #expect(isOnMainThread())

        // Published, and nothing left in staging.
        #expect(try await EPGTestSupport.storedProgrammeCount(playlist, in: database) == channelCount * 6)
        let staged = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM epgProgrammeStaging") ?? 0
        }
        #expect(staged == 0)
        let source = try #require(try await EPGTestSupport.storedSource(playlist, in: database))
        #expect(source.lastSuccessAt != nil)
        #expect(source.lastError == nil)
        #expect(source.programmeCount == channelCount * 6)
        #expect(source.channelCount == channelCount)
    }

    @Test
    func aFailedDownloadRecordsTheErrorAndKeepsTheStoredGuide() async throws {
        let database = AppDatabase.empty()
        // Nothing is served on this host: the request fails like a dead connection.
        let playlist = EPGTestSupport.m3uPlaylist()
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist,
            source: EPGTestSupport.source(playlist, attempt: 8 * 3_600, success: 8 * 3_600)
        )
        let before = try #require(try await EPGTestSupport.storedSource(playlist, in: database))

        await #expect(throws: (any Error).self) {
            _ = try await makeCoordinator(database).refresh(playlist: playlist) { _ in }
        }

        let after = try #require(try await EPGTestSupport.storedSource(playlist, in: database))
        #expect(after.lastError != nil)
        #expect(after.lastSuccessAt == before.lastSuccessAt)
        // The attempt is stamped, which is what the retry cooldown counts from.
        #expect(try #require(after.fetchedAt) > (try #require(before.fetchedAt)))
        #expect(try await EPGTestSupport.storedProgrammeCount(playlist, in: database) == 1)
    }

    @Test
    func aServerErrorIsAFailureToo() async throws {
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let playlist = try await makePlaylist(host: host, channelCount: 1, in: database)
        EPGTestSupport.serve("gone", status: 503, onHost: host)

        await #expect(throws: (any Error).self) {
            _ = try await makeCoordinator(database).refresh(playlist: playlist) { _ in }
        }

        let source = try #require(try await EPGTestSupport.storedSource(playlist, in: database))
        #expect(source.lastError != nil)
        #expect(source.lastSuccessAt == nil)
        #expect(source.fetchedAt != nil)
    }
}
