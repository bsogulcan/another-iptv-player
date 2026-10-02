import Foundation
import GRDB

/// Resolves the Xtream panel's timezone, needed to format timeshift `start`
/// params in the panel's local wall-clock. Chain: persisted IANA name → live
/// `verify()` (result persisted) → offset derived from `time_now` vs
/// `timestamp_now` → UTC.
enum PanelTimeZoneResolver {

    /// - Parameters:
    ///   - database: Injected by tests; the app writes to the shared database.
    ///   - urlSession: The guide refresh passes the session it downloads with, so
    ///     the whole refresh talks to the panel through one session.
    static func resolve(playlist: Playlist, database: AppDatabase = .shared,
                        urlSession: URLSession = PanelURLSession.shared) async -> TimeZone {
        // 1. Persisted IANA name.
        if let tz = timeZone(fromIANA: playlist.serverTimezone) { return tz }

        // 2. Live verify() — capture and persist server_info.
        guard playlist.kind == .xtream else { return .gmt }
        let client = XtreamAPIClient(playlist: playlist, urlSession: urlSession)
        guard let response = try? await client.verify() else { return .gmt }
        let serverInfo = response.serverInfo

        if let tz = timeZone(fromIANA: serverInfo?.timezone) {
            await persist(timezone: serverInfo?.timezone, playlist: playlist, database: database)
            return tz
        }

        // 3. Derive a fixed offset from time_now vs timestamp_now.
        if let offset = derivedOffsetSeconds(timeNow: serverInfo?.timeNow, timestampNow: serverInfo?.timestampNow),
           let tz = TimeZone(secondsFromGMT: offset) {
            return tz
        }

        // 4. UTC.
        return .gmt
    }

    static func timeZone(fromIANA raw: String?) -> TimeZone? {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return TimeZone(identifier: name)
    }

    /// offset = (time_now parsed as-if-UTC) − timestamp_now, rounded to 15 minutes.
    static func derivedOffsetSeconds(timeNow: String?, timestampNow: Int?) -> Int? {
        guard let timeNow, let timestampNow, timestampNow > 0 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let asUTC = f.date(from: timeNow.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let rawOffset = asUTC.timeIntervalSince1970 - Double(timestampNow)
        // Round to the nearest 15-minute step; ignore absurd values.
        guard abs(rawOffset) <= 15 * 3600 else { return nil }
        let quarter = (rawOffset / 900).rounded() * 900
        return Int(quarter)
    }

    /// Writes the one column. `playlist` is the copy the refresh or the player was
    /// started with; saving that whole value would put back every setting changed
    /// since, and would insert the row again if the playlist was deleted meanwhile.
    private static func persist(timezone: String?, playlist: Playlist, database: AppDatabase) async {
        guard let tz = timezone?.trimmingCharacters(in: .whitespacesAndNewlines), !tz.isEmpty,
              tz != playlist.serverTimezone else { return }
        _ = try? await database.updatePlaylist(id: playlist.id) { $0.serverTimezone = tz }
    }
}
