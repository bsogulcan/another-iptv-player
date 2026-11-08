import Foundation
import GRDB
import Testing

@testable import another_iptv_player

private final class MacTestBundle {}

@Suite("Original macOS library migration")
struct MacUpgradeTests {
  @Test func retainsExistingSourceCatalogFavoriteAndPosition() throws {
    let fixture = try #require(
      Bundle(for: MacTestBundle.self).url(forResource: "legacy-mac", withExtension: "sql"))
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: path) }
    let queue = try DatabaseQueue(path: path.path)
    let sql = try String(contentsOf: fixture, encoding: .utf8)
    try queue.write { try $0.execute(sql: sql) }

    let id = try #require(UUID(uuidString: "76543210-1234-4210-9234-0123456789ab"))
    _ = try AppDatabase(queue)
    try queue.read { db in
      let source = try #require(try Playlist.fetchOne(db, key: id))
      #expect(source.name == "Legacy Mac source")
      #expect(source.epgEnabled)
      let items = try MacCatalogQuery(playlistID: id, kinds: [.vod], favoritesOnly: true).fetch(db)
      #expect(items.map(\.title) == ["Harbor Film"])
      let history = try #require(try DBWatchHistory.fetchOne(db, key: id.uuidString + "_vod_42"))
      #expect(history.resumePositionMs(as: .film) == 42000)
    }

    let reopened = try DatabaseQueue(path: path.path)
    _ = try AppDatabase(reopened)
    #expect(try reopened.read { try DBFavorite.fetchCount($0) } == 1)
  }
}
