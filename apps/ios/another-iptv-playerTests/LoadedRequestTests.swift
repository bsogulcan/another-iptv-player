import Combine
import Foundation
import GRDB
import GRDBQuery
import Testing
@testable import another_iptv_player

/// `LoadedRequest` exists so a list screen can tell "the database has not answered
/// yet" from "the list is empty": the first must draw nothing, the second the
/// empty state.
@Suite("LoadedRequest")
struct LoadedRequestTests {

    private let playlist = Playlist(name: "Loaded", serverURL: "http://host:8080")

    private func history(_ streamId: String, watchedAt: TimeInterval) -> DBWatchHistory {
        DBWatchHistory(
            id: "\(playlist.id)_vod_\(streamId)", playlistId: playlist.id, streamId: streamId, type: "vod",
            lastTimeMs: 60_000, durationMs: 600_000,
            lastWatchedAt: Date(timeIntervalSince1970: 1_000_000 + watchedAt),
            seriesId: nil, title: "Film \(streamId)", secondaryTitle: nil, imageURL: nil, containerExtension: nil
        )
    }

    private func database(with rows: [DBWatchHistory]) throws -> AppDatabase {
        let database = AppDatabase.empty()
        try database.writeSync { db in
            try playlist.insert(db)
            for row in rows { try row.insert(db) }
        }
        return database
    }

    /// Subscribes, then waits until `count` values have arrived (or gives up).
    private func values<Request: Queryable>(
        of request: Request, in database: AppDatabase, count: Int = 1
    ) async throws -> (onSubscription: [Request.Value], delivered: [Request.Value])
    where Request.Context == AppDatabase {
        var received: [Request.Value] = []
        let cancellable = try request.publisher(in: database)
            .sink(receiveCompletion: { _ in }, receiveValue: { received.append($0) })
        defer { cancellable.cancel() }
        let onSubscription = received

        var waits = 0
        while received.count < count, waits < 1_000 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waits += 1
        }
        return (onSubscription, received)
    }

    @Test
    func defaultValueIsNotDeliveredYet() {
        #expect(LoadedRequest<RecentWatchHistoryRequest>.defaultValue == nil)
        #expect(LoadedRequest<AllDownloadsRequest>.defaultValue == nil)
        // The wrapped requests keep their own default.
        #expect(RecentWatchHistoryRequest.defaultValue == [])
    }

    @Test
    func anEmptyTableIsDeliveredAsAnEmptyListNotAsNil() async throws {
        let database = try database(with: [])
        let request = LoadedRequest(RecentWatchHistoryRequest(playlistId: playlist.id, limit: 500))

        let result = try await values(of: request, in: database)

        // Asynchronous scheduling is kept: nothing has arrived when `sink` returns,
        // which is the window in which the view sees `nil`.
        #expect(result.onSubscription.isEmpty)
        #expect(result.delivered.count == 1)
        #expect(result.delivered.first.map { $0 == [] } == true)
    }

    @Test
    func storedRowsAreDeliveredUnchanged() async throws {
        let rows = [history("1", watchedAt: 0), history("2", watchedAt: 60)]
        let database = try database(with: rows)
        let request = LoadedRequest(RecentWatchHistoryRequest(playlistId: playlist.id, limit: 500))

        let result = try await values(of: request, in: database)

        #expect(result.onSubscription.isEmpty)
        // Newest first, as the wrapped request orders them.
        #expect(result.delivered.map { $0?.map(\.streamId) } == [["2", "1"]])
    }

    @Test
    func anImmediateBaseStillDeliversOnSubscription() async throws {
        let database = try database(with: [history("1", watchedAt: 0)])
        let request = LoadedRequest(
            RecentWatchHistoryRequest(playlistId: playlist.id, limit: 10, immediate: true))

        let result = try await values(of: request, in: database)

        #expect(result.onSubscription.map { $0?.map(\.streamId) } == [["1"]])
    }

    @Test
    func equalityFollowsTheWrappedRequest() {
        let pid = playlist.id
        // `@Query` restarts its observation when the request changes.
        #expect(LoadedRequest(RecentWatchHistoryRequest(playlistId: pid, limit: 500))
                == LoadedRequest(RecentWatchHistoryRequest(playlistId: pid, limit: 500)))
        #expect(LoadedRequest(RecentWatchHistoryRequest(playlistId: pid, limit: 500))
                != LoadedRequest(RecentWatchHistoryRequest(playlistId: pid, limit: 500, type: "vod")))
    }

    // MARK: Removing one history item

    @Test
    func removingOneHistoryItemLeavesTheOthers() async throws {
        let rows = [history("1", watchedAt: 0), history("2", watchedAt: 60), history("3", watchedAt: 120)]
        let database = try database(with: rows)

        await DBWatchHistory.remove(id: rows[1].id, from: database)

        let remaining = try await database.read { db in
            try DBWatchHistory.order(Column("lastWatchedAt").desc).fetchAll(db).map(\.streamId)
        }
        #expect(remaining == ["3", "1"])
    }

    @Test
    func removingAnUnknownHistoryItemChangesNothing() async throws {
        let rows = [history("1", watchedAt: 0)]
        let database = try database(with: rows)

        await DBWatchHistory.remove(id: "no-such-row", from: database)

        let count = try await database.read { db in try DBWatchHistory.fetchCount(db) }
        #expect(count == 1)
    }

    /// The shelf and the history grid drop the card through their observation.
    @Test
    func theObservedListFollowsARemoval() async throws {
        let rows = [history("1", watchedAt: 0), history("2", watchedAt: 60)]
        let database = try database(with: rows)
        let request = LoadedRequest(RecentWatchHistoryRequest(playlistId: playlist.id, limit: 500))

        var received: [[String]?] = []
        let cancellable = try request.publisher(in: database)
            .sink(receiveCompletion: { _ in }, receiveValue: { received.append($0?.map(\.streamId)) })
        defer { cancellable.cancel() }

        await DBWatchHistory.remove(id: rows[1].id, from: database)

        var waits = 0
        while received.last != ["1"], waits < 1_000 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waits += 1
        }
        #expect(received.last == ["1"])
    }
}
