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

    enum CodingKeys: String, CodingKey {
        case id, name, serverURL, username, password, createdAt, filterAdultContent, type, m3uEpgURL
    }

    init(
        id: UUID = UUID(),
        name: String,
        serverURL: String,
        username: String = "",
        password: String = "",
        filterAdultContent: Bool = false,
        type: PlaylistKind = .xtream,
        m3uEpgURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.filterAdultContent = filterAdultContent
        self.type = type.rawValue
        self.m3uEpgURL = m3uEpgURL
    }

    var kind: PlaylistKind {
        PlaylistKind(rawValue: type) ?? .xtream
    }
}

// MARK: - Persistence
extension Playlist {
    static let databaseTableName = "playlist"
}
