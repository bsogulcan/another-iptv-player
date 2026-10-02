import Foundation
import GRDB

enum PlaylistKind: String, Codable {
    case xtream
    case m3u
}

struct Playlist: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable {
    var id: UUID
    var name: String
    var serverURL: String
    var username: String
    var password: String
    var createdAt: Date = Date()
    var filterAdultContent: Bool = false
    var type: String = PlaylistKind.xtream.rawValue
    var m3uEpgURL: String? = nil
    /// User-entered EPG (XMLTV) URL override for M3U playlists. Takes precedence
    /// over the `x-tvg-url` header captured in `m3uEpgURL`.
    var epgURLOverride: String? = nil
    /// Whether EPG fetch/display is enabled for this playlist.
    var epgEnabled: Bool = true
    /// IANA timezone name from Xtream `server_info` — timeshift `start` params are
    /// interpreted in the panel's local time, not the device's.
    var serverTimezone: String? = nil
    /// Cached catch-up probe result (`TimeshiftStyleCache.storedValue`): the timeshift URL
    /// shape that last won, "m3u8" | "path" | "php", or "path-no-m3u8" | "php-no-m3u8" once
    /// the `.m3u8` shape was probed and lost on this panel. It only reorders the probe;
    /// nil means never probed.
    var timeshiftStyle: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, serverURL, username, password, createdAt, filterAdultContent, type, m3uEpgURL
        case epgURLOverride, epgEnabled, serverTimezone, timeshiftStyle
    }

    init(
        id: UUID = UUID(),
        name: String,
        serverURL: String,
        username: String = "",
        password: String = "",
        filterAdultContent: Bool = false,
        type: PlaylistKind = .xtream,
        m3uEpgURL: String? = nil,
        epgURLOverride: String? = nil,
        epgEnabled: Bool = true,
        serverTimezone: String? = nil,
        timeshiftStyle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.filterAdultContent = filterAdultContent
        self.type = type.rawValue
        self.m3uEpgURL = m3uEpgURL
        self.epgURLOverride = epgURLOverride
        self.epgEnabled = epgEnabled
        self.serverTimezone = serverTimezone
        self.timeshiftStyle = timeshiftStyle
    }

    nonisolated var kind: PlaylistKind {
        PlaylistKind(rawValue: type) ?? .xtream
    }

    /// Effective EPG source URL for M3U playlists: a user override wins over the
    /// `x-tvg-url` header value so re-imports don't clobber a manual URL.
    nonisolated var effectiveEPGURL: String? {
        if let o = epgURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty {
            return o
        }
        return m3uEpgURL
    }
}

// MARK: - Persistence
extension Playlist {
    static let databaseTableName = "playlist"
}
