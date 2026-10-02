import Foundation

/// `get_short_epg` / `get_simple_data_table` response: `{ "epg_listings": [ … ] }`.
/// Per-element decode is failure-tolerant so one malformed row can't drop the batch.
/// `nonisolated`: decoded in `XtreamAPIClient`'s detached pass, like the catalog models.
nonisolated struct XtreamEPGListingsResponse: Decodable, Sendable {
    let epgListings: [XtreamEPGListing]

    enum CodingKeys: String, CodingKey {
        case epgListings = "epg_listings"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container?.decodeIfPresent([FailableDecodable<XtreamEPGListing>].self, forKey: .epgListings)) ?? nil
        epgListings = (raw ?? []).compactMap { $0.base }
    }
}

nonisolated struct XtreamEPGListing: Decodable, Sendable {
    let id: String?
    let title: String?           // usually base64
    let description: String?     // usually base64
    let channelId: String?       // "channel_id"
    let startTimestamp: Int?     // "start_timestamp" — unix UTC, string-or-int
    let stopTimestamp: Int?      // "stop_timestamp"
    let start: String?           // panel-LOCAL "yyyy-MM-dd HH:mm:ss"
    let end: String?
    let hasArchive: Int?         // "has_archive"
    let nowPlaying: Int?         // "now_playing"

    enum CodingKeys: String, CodingKey {
        case id, title, description, start, end
        case channelId = "channel_id"
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
        case hasArchive = "has_archive"
        case nowPlaying = "now_playing"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        id = container?.decodeFlexibleStringIfPresent(forKey: .id)
        title = container?.decodeFlexibleStringIfPresent(forKey: .title)
        description = container?.decodeFlexibleStringIfPresent(forKey: .description)
        channelId = container?.decodeFlexibleStringIfPresent(forKey: .channelId)
        startTimestamp = container?.decodeFlexibleIntIfPresent(forKey: .startTimestamp)
        stopTimestamp = container?.decodeFlexibleIntIfPresent(forKey: .stopTimestamp)
        start = container?.decodeFlexibleStringIfPresent(forKey: .start)
        end = container?.decodeFlexibleStringIfPresent(forKey: .end)
        hasArchive = container?.decodeFlexibleIntIfPresent(forKey: .hasArchive)
        nowPlaying = container?.decodeFlexibleIntIfPresent(forKey: .nowPlaying)
    }

    /// Decoded title, falling back to the raw string when it isn't base64.
    var decodedTitle: String? { title?.epgDecodedBase64OrSelf }
    var decodedDescription: String? { description?.epgDecodedBase64OrSelf }
}

nonisolated extension String {
    /// Xtream EPG `title`/`description` are usually base64-encoded, but some panels
    /// send plain text. Decodes strictly (charset + length + valid UTF-8 without
    /// control bytes) and returns the raw string on any mismatch.
    var epgDecodedBase64OrSelf: String {
        let s = self
        guard !s.isEmpty, s.utf8.count % 4 == 0 else { return s }
        // Reject anything outside the base64 alphabet before allocating.
        for b in s.utf8 {
            let isUpper = b >= 0x41 && b <= 0x5A
            let isLower = b >= 0x61 && b <= 0x7A
            let isDigit = b >= 0x30 && b <= 0x39
            let isSym = b == 0x2B || b == 0x2F || b == 0x3D   // + / =
            if !(isUpper || isLower || isDigit || isSym) { return s }
        }
        guard let data = Data(base64Encoded: s),
              let decoded = String(data: data, encoding: .utf8) else { return s }
        // Reject decodes that produced C0 control bytes (other than tab/newline/cr)
        // — a strong signal the input was plain text that merely looked base64-ish.
        for scalar in decoded.unicodeScalars {
            let v = scalar.value
            if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D { return s }
        }
        return decoded
    }
}
