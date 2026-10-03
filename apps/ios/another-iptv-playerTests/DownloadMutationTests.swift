import Foundation
import GRDB
import Testing
@testable import another_iptv_player

private nonisolated final class HoldingDownloadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

@Suite("Download mutation ordering")
struct DownloadMutationTests {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private func item(id: String, playlist: Playlist) -> DBDownloadedItem {
        DBDownloadedItem(id: id, playlistId: playlist.id, streamId: id, type: "vod",
                         title: "Old", secondaryTitle: nil, imageURL: nil,
                         remoteURL: "https://download.invalid/old.mp4", localPath: "test-\(id).mp4",
                         containerExtension: "mp4", totalBytes: 0, downloadedBytes: 0,
                         status: DownloadStatus.queued.rawValue, errorMessage: nil,
                         createdAt: Date(), completedAt: nil, seriesId: nil,
                         seasonNumber: nil, episodeNumber: nil)
    }

    private func enqueue(_ manager: DownloadManager, id: String, playlist: Playlist) async {
        await manager.enqueue(id: id, playlistId: playlist.id, streamId: id, type: "vod",
                              title: "New", secondaryTitle: nil, imageURL: nil,
                              remoteURL: URL(string: "https://download.invalid/new.mp4")!,
                              containerExtension: "mp4")
    }

    /// Holds file removal open, then submits another download for the same item.
    /// The old deletion must finish before the new row/file can be created.
    @Test(arguments: ["single", "playlist", "all"])
    func reenqueueWaitsForDeletion(scope: String) async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "Downloads", serverURL: "https://download.invalid")
        let id = UUID().uuidString
        let old = item(id: id, playlist: playlist)
        try await database.write { db in
            try playlist.insert(db)
            try old.insert(db)
        }
        let release = DispatchSemaphore(value: 0)
        let (entered, signal) = AsyncStream<Void>.makeStream()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HoldingDownloadProtocol.self]
        let manager = DownloadManager(database: database, configuration: configuration,
                                      restoresOutstandingTasks: false, removeFiles: { _ in
            signal.yield()
            release.wait()
        })
        defer { manager.session.invalidateAndCancel() }
        let deletion = Task {
            switch scope {
            case "playlist": await manager.deleteAll(playlistId: playlist.id)
            case "all": await manager.deleteAll()
            default: await manager.delete(id: id)
            }
        }
        for await _ in entered { break }
        defer { release.signal() }
        let adding = Task { await enqueue(manager, id: id, playlist: playlist) }
        let pending = await eventually { manager.pendingEnqueueIds.contains(id) }
        let during = try await database.read { db in try DBDownloadedItem.fetchOne(db, key: id) }
        let startedDuringDeletion = manager.hasActiveDownload(playlistId: playlist.id)
        release.signal()
        await deletion.value
        await adding.value
        let after = try await database.read { db in try DBDownloadedItem.fetchOne(db, key: id) }
        #expect(pending)
        #expect(during?.title == "Old")
        #expect(!startedDuringDeletion)
        #expect(after?.title == "New")
        #expect(await eventually { manager.hasActiveDownload(playlistId: playlist.id) })
    }

    @Test(arguments: [false, true])
    func failedQueueClaimDoesNotStartANetworkTask(deletesRow: Bool) async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "Downloads", serverURL: "https://download.invalid")
        let action = deletesRow
            ? "DELETE FROM downloadedItem WHERE id = OLD.id; SELECT RAISE(IGNORE);"
            : "SELECT RAISE(ABORT, 'injected queue claim failure');"
        try await database.write { db in
            try playlist.insert(db)
            try db.execute(sql: """
                CREATE TRIGGER reject_download_start BEFORE UPDATE ON downloadedItem
                WHEN NEW.status = 'downloading'
                BEGIN \(action) END
                """)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HoldingDownloadProtocol.self]
        let manager = DownloadManager(database: database, configuration: configuration,
                                      restoresOutstandingTasks: false)
        defer { manager.session.invalidateAndCancel() }
        let id = UUID().uuidString
        await enqueue(manager, id: id, playlist: playlist)
        await manager.pumpQueue()
        #expect(!manager.hasActiveDownload(playlistId: playlist.id))
        let row = try await database.read { db in try DBDownloadedItem.fetchOne(db, key: id) }
        // GRDB rolls back the trigger's deletion when the update reports that its
        // row disappeared. Both failures leave the original queued row intact.
        #expect(row?.downloadStatus == .queued)
    }
}
