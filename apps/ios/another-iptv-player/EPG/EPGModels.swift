import Foundation
import GRDB

// MARK: - Persistence records

/// One EPG programme. `channelKey` is the normalized join key (see
/// `EPGConstants.normalizeChannelKey`). Timestamps are unix epoch seconds, UTC.
struct DBEPGProgramme: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable, Hashable, Sendable {
    var playlistId: UUID
    var channelKey: String
    var startTs: Int64
    var stopTs: Int64
    var title: String
    var subtitle: String?
    var desc: String?
    var category: String?
    var iconURL: String?
    var episodeNum: String?

    var id: String { "\(playlistId)_\(channelKey)_\(startTs)" }

    static let databaseTableName = "epgProgramme"
}

/// XMLTV `<channel>` metadata for matched channels — display-name fallback
/// resolution and guide icons.
struct DBEPGChannel: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    var playlistId: UUID
    var channelKey: String
    var displayName: String?
    var iconURL: String?

    static let databaseTableName = "epgChannel"
}

/// Per-playlist EPG bookkeeping: source, TTL anchors, conditional-GET validators,
/// last error, and coverage counts.
struct DBEPGSource: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    var playlistId: UUID
    var sourceType: String          // EPGSourceType.rawValue
    var url: String?
    var fetchedAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    var etag: String?
    var lastModified: String?
    var programmeCount: Int = 0
    var channelCount: Int = 0

    static let databaseTableName = "epgSource"
}

enum EPGSourceType: String {
    case xtreamXMLTV = "xtream_xmltv"
    case m3uXMLTV = "m3u_xmltv"
    case xtreamJSON = "xtream_json"
}

// MARK: - UI value types

/// UI-facing programme value. Built from `DBEPGProgramme`; timestamps become
/// `Date`s and progress/curent helpers are derived.
nonisolated struct EPGProgramme: Identifiable, Equatable, Hashable, Sendable {
    let channelKey: String
    let title: String
    let subtitle: String?
    let desc: String?
    let category: String?
    let iconURL: String?
    let episodeNum: String?
    let start: Date
    let stop: Date

    /// Stable within a channel+start; the same programme across refreshes keeps its id.
    var id: String { "\(channelKey)|\(Int(start.timeIntervalSince1970))" }

    var interval: DateInterval { DateInterval(start: start, end: Swift.max(start, stop)) }
    var duration: TimeInterval { Swift.max(0, stop.timeIntervalSince(start)) }

    func isCurrent(at now: Date) -> Bool { start <= now && now < stop }
    func isPast(at now: Date) -> Bool { stop <= now }

    /// Elapsed fraction in [0, 1] while on air, else nil.
    func progress(at now: Date) -> Double? {
        guard duration > 0, start <= now, now < stop else { return nil }
        return Swift.min(1, Swift.max(0, now.timeIntervalSince(start) / duration))
    }

    init(channelKey: String, title: String, subtitle: String? = nil, desc: String? = nil,
         category: String? = nil, iconURL: String? = nil, episodeNum: String? = nil,
         start: Date, stop: Date) {
        self.channelKey = channelKey
        self.title = title
        self.subtitle = subtitle
        self.desc = desc
        self.category = category
        self.iconURL = iconURL
        self.episodeNum = episodeNum
        self.start = start
        self.stop = stop
    }

    init(from row: DBEPGProgramme) {
        self.init(
            channelKey: row.channelKey,
            title: row.title,
            subtitle: row.subtitle,
            desc: row.desc,
            category: row.category,
            iconURL: row.iconURL,
            episodeNum: row.episodeNum,
            start: Date(timeIntervalSince1970: TimeInterval(row.startTs)),
            stop: Date(timeIntervalSince1970: TimeInterval(row.stopTs))
        )
    }
}

/// Current + next programme for one channel.
///
/// `nonisolated` because `EPGStore` builds the index on GRDB's reader queue.
/// The minute index fills `now` only, from the slim guide columns (title and
/// times): nothing displays `next`, and fetching it for every channel each
/// minute was most of the rebuild's cost.
nonisolated struct EPGNowNext: Equatable, Sendable {
    var now: EPGProgramme?
    var next: EPGProgramme?

    var isEmpty: Bool { now == nil && next == nil }
}

/// Immutable now/next index published once per minute. Equality is a cheap
/// version compare so SwiftUI environment invalidation is O(1) — the dictionary
/// is never diffed. `version` is bumped by `EPGStore` only when contents change.
struct EPGSnapshot: Equatable {
    let version: Int
    let byChannelKey: [String: EPGNowNext]

    static func == (lhs: EPGSnapshot, rhs: EPGSnapshot) -> Bool { lhs.version == rhs.version }

    subscript(_ key: String?) -> EPGNowNext? {
        guard let key else { return nil }
        return byChannelKey[key]
    }

    static let empty = EPGSnapshot(version: 0, byChannelKey: [:])
}
