import Foundation

/// Tunables for the EPG subsystem. Centralized so the retention window, TTLs and
/// download guards are discoverable in one place.
///
/// `nonisolated` because the project defaults declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), and these constants/helpers are read by
/// code that is not on it: the guide refresh (`EPGRefreshCoordinator.refresh`
/// is `@concurrent`) and database closures.
nonisolated enum EPGConstants {
    /// A guide is considered fresh for this long after a successful fetch.
    static let refreshTTL: TimeInterval = 6 * 3600

    /// After a failed fetch, don't retry sooner than this.
    static let retryCooldown: TimeInterval = 15 * 60

    /// Programmes are retained from `now - pastWindow` to `now + futureWindow`.
    /// The past window is clamped to the channel archive duration for catch-up.
    static let futureRetention: TimeInterval = 7 * 86_400
    static let m3uPastRetention: TimeInterval = 1 * 86_400
    static let maxCatchupPastDays = 7
    static let minCatchupPastDays = 1

    /// Upper bound on how much longer an on-air programme may still run to be
    /// picked up by the minute now-index. It turns the `stopTs` scan into a closed
    /// range instead of a walk over the whole retained future; 48 h still covers
    /// day-long placeholder entries and multi-day events.
    static let nowIndexMaxRemaining: TimeInterval = 48 * 3600

    /// Rows written per DB transaction while parsing a guide.
    static let parseBatchSize = 2_000

    /// Download guards. XMLTV guides are commonly multi-MB; a compressed feed
    /// exceeding this (or inflating past the inflated cap) is aborted.
    static let maxCompressedBytes: Int64 = 200 * 1_024 * 1_024
    static let maxInflatedBytes: Int64 = 1_024 * 1_024 * 1_024

    /// Streaming chunk size for gzip inflate.
    static let inflateChunkSize = 512 * 1_024

    /// `get_short_epg` listing count for the player now/next fallback.
    static let shortEPGLimit = 12

    /// Normalizes an XMLTV channel id / Xtream `epg_channel_id` / M3U `tvg-id`
    /// into the join key used across the EPG store. Feeds and playlists disagree
    /// on case and surrounding whitespace constantly, so both are stripped.
    static func normalizeChannelKey(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}
