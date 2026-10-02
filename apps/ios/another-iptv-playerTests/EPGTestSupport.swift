import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// Shared pieces of the guide tests: a guide served from a stubbed session, and
/// rows for an in-memory database. Nothing built here can reach the network: the
/// session answers the hosts registered with `XtreamStubURLProtocol` and fails
/// every other request like a dead connection.
enum EPGTestSupport {

    static func stubbedSession() -> URLSession {
        XtreamStubURLProtocol.makeSession()
    }

    static func stubbedDownloader() -> EPGDownloader {
        EPGDownloader(urlSession: stubbedSession())
    }

    /// A host no other test uses, so tests running side by side keep their answers apart.
    static func uniqueHost() -> String {
        "guide-\(UUID().uuidString.lowercased()).invalid"
    }

    static func serve(_ body: String, status: Int = 200, onHost host: String) {
        XtreamStubURLProtocol.setAnswer(.init(status: status, body: Data(body.utf8)), forHost: host)
    }

    static func makeStore(database: AppDatabase, defaults: UserDefaults) -> EPGStore {
        EPGStore(database: database, defaults: defaults, downloader: stubbedDownloader())
    }

    // MARK: Playlists

    /// An Xtream playlist on `host`. The time zone is set so a refresh does not
    /// have to ask the panel for it.
    static func xtreamPlaylist(host: String = uniqueHost(), epgEnabled: Bool = true) -> Playlist {
        Playlist(name: "Panel", serverURL: "http://\(host)", username: "u", password: "p",
                 epgEnabled: epgEnabled, serverTimezone: "UTC")
    }

    /// An M3U playlist whose header names a guide on `host`.
    static func m3uPlaylist(host: String = uniqueHost()) -> Playlist {
        Playlist(name: "List", serverURL: "http://\(host)/list.m3u", type: .m3u,
                 m3uEpgURL: "http://\(host)/guide.xml")
    }

    // MARK: XMLTV

    private static func xmltvTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date) + " +0000"
    }

    /// A guide in which every channel has `programmesPerChannel` half-hour
    /// programmes in a row, the first of them on air at `now`.
    static func guideXML(channelIds: [String], title: String = "On air",
                         programmesPerChannel: Int = 1, now: Date = Date()) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<tv>\n"
        for id in channelIds {
            xml += "<channel id=\"\(id)\"><display-name>\(id)</display-name></channel>\n"
        }
        let first = now.addingTimeInterval(-600)
        for id in channelIds {
            for index in 0..<programmesPerChannel {
                let start = first.addingTimeInterval(Double(index) * 1_800)
                let stop = start.addingTimeInterval(1_800)
                xml += "<programme start=\"\(xmltvTime(start))\" stop=\"\(xmltvTime(stop))\" channel=\"\(id)\">"
                xml += "<title>\(title)\(index == 0 ? "" : " \(index)")</title></programme>\n"
            }
        }
        xml += "</tv>\n"
        return xml
    }

    // MARK: Rows

    /// The playlist row, one live channel with the EPG id `channelKey`, and a
    /// stored guide that has that channel with one programme on air.
    static func seedMatchingGuide(in database: AppDatabase, playlist: Playlist,
                                  channelKey: String = "news.tv", title: String = "Bulletin",
                                  source: DBEPGSource? = nil) async throws {
        let now = Int64(Date().timeIntervalSince1970)
        try await database.write { db in
            try playlist.insert(db)
            if playlist.kind == .xtream {
                try DBLiveStream(streamId: 1, name: "News", epgChannelId: channelKey, playlistId: playlist.id).insert(db)
            } else {
                try DBM3UChannel(id: "channel-1", playlistId: playlist.id, name: "News",
                                 url: "http://stream.invalid/1.ts", tvgId: channelKey).insert(db)
            }
            try DBEPGChannel(playlistId: playlist.id, channelKey: channelKey, displayName: "News").insert(db)
            try DBEPGProgramme(playlistId: playlist.id, channelKey: channelKey,
                               startTs: now - 600, stopTs: now + 1_200, title: title).insert(db)
            try (source ?? freshSource(playlist)).insert(db)
        }
    }

    /// A source whose last refresh has just succeeded.
    static func freshSource(_ playlist: Playlist) -> DBEPGSource {
        source(playlist, attempt: 0, success: 0)
    }

    /// A source row with its dates given as "seconds ago".
    static func source(_ playlist: Playlist, attempt: TimeInterval?, success: TimeInterval?,
                       error: String? = nil) -> DBEPGSource {
        let now = Date()
        let type: EPGSourceType = playlist.kind == .xtream ? .xtreamXMLTV : .m3uXMLTV
        return DBEPGSource(playlistId: playlist.id, sourceType: type.rawValue,
                           fetchedAt: attempt.map { now.addingTimeInterval(-$0) },
                           lastSuccessAt: success.map { now.addingTimeInterval(-$0) },
                           lastError: error)
    }

    static func storedSource(_ playlist: Playlist, in database: AppDatabase) async throws -> DBEPGSource? {
        try await database.read { db in try DBEPGSource.fetchOne(db, key: playlist.id) }
    }

    static func storedProgrammeCount(_ playlist: Playlist, in database: AppDatabase) async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM epgProgramme WHERE playlistId = ?",
                             arguments: [playlist.id]) ?? 0
        }
    }
}
