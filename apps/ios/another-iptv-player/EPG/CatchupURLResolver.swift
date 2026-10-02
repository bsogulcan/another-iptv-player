import Foundation
import GRDB

/// URL shapes a panel may serve a timeshift under, declared in default probe order.
enum TimeshiftStyle: String, CaseIterable {
    /// Path-style `.m3u8`: a finite HLS playlist, so the programme is seekable and
    /// opens on the AVPlayer path. Raw value differs from `path` on purpose — it is
    /// the cached marker that tells the two path-style shapes apart.
    case hls = "m3u8"
    /// Path-style `.ts`.
    case path
    case php
}

struct ResolvedCatchupStream: Equatable {
    let url: URL
    let style: TimeshiftStyle
}

/// What `Playlist.timeshiftStyle` remembers between catch-up starts: the shape that
/// last won the probe and whether `.m3u8` has already lost on this panel.
///
/// Stored values: `"m3u8"`, `"path"`, `"php"`, `"path-no-m3u8"`, `"php-no-m3u8"`.
/// A bare `"path"`/`"php"` is what releases before the `.m3u8` probe wrote (and
/// what a first miss on a proven-HLS panel leaves behind), so it says nothing final
/// about HLS and `.m3u8` still gets an attempt.
struct TimeshiftStyleCache: Equatable {
    let winner: TimeshiftStyle
    /// `.m3u8` was probed and lost while another shape answered, or won the probe
    /// and then failed to play. It then moves to the back of the order instead of
    /// costing a failed connection (or a failed playback) on every start.
    let hlsRuledOut: Bool

    private static let ruledOutSuffix = "-no-m3u8"

    init(winner: TimeshiftStyle, hlsRuledOut: Bool) {
        self.winner = winner
        self.hlsRuledOut = winner != .hls && hlsRuledOut
    }

    init?(storedValue: String?) {
        guard let raw = storedValue else { return nil }
        if let style = TimeshiftStyle(rawValue: raw) {
            self.init(winner: style, hlsRuledOut: false)
            return
        }
        guard raw.hasSuffix(Self.ruledOutSuffix),
              let style = TimeshiftStyle(rawValue: String(raw.dropLast(Self.ruledOutSuffix.count))),
              style != .hls else { return nil }
        self.init(winner: style, hlsRuledOut: true)
    }

    var storedValue: String {
        hlsRuledOut ? winner.rawValue + Self.ruledOutSuffix : winner.rawValue
    }

    /// Probe order for a cached value. Every shape stays in the list — the cache
    /// only reorders, so a panel that changes behaviour is still found again.
    static func probeOrder(for cache: TimeshiftStyleCache?) -> [TimeshiftStyle] {
        guard let cache else { return TimeshiftStyle.allCases }
        let raw: [TimeshiftStyle] = cache.winner == .php ? [.php, .path] : [.path, .php]
        return cache.hlsRuledOut ? raw + [.hls] : [.hls] + raw
    }
}

/// Decides, line by line, whether a response is a finite HLS media playlist:
/// `#EXTM3U` header, at least one segment and `#EXT-X-ENDLIST`. The header alone is
/// not enough because nothing falls back once the player has the URL — an empty or
/// open-ended playlist must lose the probe so the `.ts` shape is used as before.
struct HLSPlaylistScan {
    enum Verdict { case undecided, accepted, rejected }

    /// Far beyond any real programme; bounds the read if a panel never ends the list.
    static let maxLines = 20_000

    private var lineCount = 0
    private var sawSegment = false

    mutating func feed(_ line: String) -> Verdict {
        lineCount += 1
        if lineCount == 1 {
            return line.hasPrefix("#EXTM3U") ? .undecided : .rejected
        }
        if line.hasPrefix("#EXTINF") { sawSegment = true }
        if line.hasPrefix("#EXT-X-ENDLIST") { return sawSegment ? .accepted : .rejected }
        return lineCount >= Self.maxLines ? .rejected : .undecided
    }
}

enum CatchupURLError: LocalizedError {
    case notAvailable
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable: return L("epg.catchup.error.unavailable")
        case .network(let err): return L("epg.error.network", err.localizedDescription)
        }
    }
}

/// Resolves a working Xtream timeshift URL before playback, so we never tear down
/// and rebuild the player chain on a bad URL. Probes candidate shapes one at a time
/// (path-style `.m3u8`, path-style `.ts`, then legacy PHP) and checks the body — a
/// `200` HTML error page is rejected. The winning shape is cached on the playlist.
enum CatchupURLResolver {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func resolve(playlist: Playlist,
                        streamId: Int,
                        startUTC: Date,
                        durationMinutes: Int,
                        panelTimeZone: TimeZone) async throws -> ResolvedCatchupStream {
        // Views pass a `Playlist` snapshot that can predate the last probe, so the
        // cached shape is read from the row itself.
        let stored = await storedStyle(for: playlist)
        let cached = TimeshiftStyleCache(storedValue: stored)
        let list = candidates(playlist: playlist, streamId: streamId, startUTC: startUTC,
                              durationMinutes: durationMinutes, panelTimeZone: panelTimeZone,
                              order: TimeshiftStyleCache.probeOrder(for: cached))
        let playlistId = playlist.id
        return try await resolve(candidates: list, cached: cached,
                                 probe: { try await probe(url: $0.url, style: $0.style) },
                                 persist: { await persistStyle($0, playlistId: playlistId) })
    }

    /// One candidate URL per shape, in `order`.
    static func candidates(playlist: Playlist,
                           streamId: Int,
                           startUTC: Date,
                           durationMinutes: Int,
                           panelTimeZone: TimeZone,
                           order: [TimeshiftStyle]) -> [ResolvedCatchupStream] {
        let builder = PlaybackURLBuilder(playlist: playlist)
        return order.compactMap { style in
            let url: URL?
            switch style {
            case .hls:
                url = builder.timeshiftPathURL(streamId: streamId, startUTC: startUTC,
                                               durationMinutes: durationMinutes,
                                               panelTimeZone: panelTimeZone, extension: "m3u8")
            case .path:
                url = builder.timeshiftPathURL(streamId: streamId, startUTC: startUTC,
                                               durationMinutes: durationMinutes,
                                               panelTimeZone: panelTimeZone, extension: "ts")
            case .php:
                url = builder.timeshiftPHPURL(streamId: streamId, startUTC: startUTC,
                                              durationMinutes: durationMinutes,
                                              panelTimeZone: panelTimeZone)
            }
            return url.map { ResolvedCatchupStream(url: $0, style: style) }
        }
    }

    /// Probe loop, free of network and database so the order and the cached value
    /// are unit-testable. Candidates are probed strictly one after another: a probe
    /// has released its connection before the next one starts.
    static func resolve(candidates: [ResolvedCatchupStream],
                        cached: TimeshiftStyleCache?,
                        probe: (ResolvedCatchupStream) async throws -> Bool,
                        persist: (TimeshiftStyleCache) async -> Void) async throws -> ResolvedCatchupStream {
        var lastError: Error?
        var hlsLost = false
        for candidate in candidates {
            do {
                if try await probe(candidate) {
                    // A panel whose HLS has worked before is not demoted on a single
                    // miss: the first one only drops the cached winner, the second
                    // (cache no longer says `.hls`) rules it out.
                    let outcome = TimeshiftStyleCache(
                        winner: candidate.style,
                        hlsRuledOut: cached?.hlsRuledOut == true || (hlsLost && cached?.winner != .hls))
                    if outcome != cached { await persist(outcome) }
                    return candidate
                }
            } catch is CancellationError {
                throw CatchupURLError.notAvailable
            } catch {
                lastError = error
            }
            // Counts only if a later shape wins: then the panel answered for this
            // programme, just not as HLS. A timeout counts too, otherwise a panel
            // that hangs on `.m3u8` would stall every catch-up start.
            if candidate.style == .hls { hlsLost = true }
        }
        if let lastError { throw CatchupURLError.network(lastError) }
        throw CatchupURLError.notAvailable
    }

    /// True when the URL returns what its shape promises: a finite HLS playlist for
    /// `.hls`; a TS sync byte 0x47 or an `#EXTM3U` header for the raw shapes. False
    /// for HTML/error bodies.
    private static func probe(url: URL, style: TimeshiftStyle) async throws -> Bool {
        var request = URLRequest(url: url)
        // A playlist is judged on its whole text; only the raw shapes are cut short.
        if style != .hls {
            request.setValue("bytes=0-7", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        // Drop the connection on every exit, including a body the panel keeps
        // streaming, so the next probe or the player never overlaps with it.
        defer { bytes.task.cancel() }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return false
        }

        if style == .hls {
            var scan = HLSPlaylistScan()
            for try await line in bytes.lines {
                switch scan.feed(line) {
                case .accepted: return true
                case .rejected: return false
                case .undecided: continue
                }
            }
            return false
        }

        var head: [UInt8] = []
        for try await b in bytes {
            head.append(b)
            if head.count >= 7 { break }
        }
        guard let first = head.first else { return false }
        if first == 0x47 { return true }                     // MPEG-TS sync byte
        if Array(head.prefix(7)) == Array("#EXTM3U".utf8) { return true }
        return false                                          // HTML / error page
    }

    /// A failed `.m3u8` catch-up that had really played for at least this long is not
    /// held against the shape: the playlist worked, something else (a network drop)
    /// ended it.
    static let hlsProvenPlayedSeconds: TimeInterval = 60

    /// Whether a surfaced playback failure rules `.m3u8` out for the panel. The probe
    /// reads only the playlist text, so segments that do not play are first seen by
    /// the player.
    static func rulesOutHLS(failedURL: URL, playedSeconds: TimeInterval) -> Bool {
        failedURL.pathExtension.lowercased() == TimeshiftStyle.hls.rawValue
            && playedSeconds < hlsProvenPlayedSeconds
    }

    /// Called by the catch-up player when playback of a resolved URL failed. Nothing
    /// is reloaded here (that would be a second connection); the cache is demoted so
    /// the next catch-up start resolves to `.ts` again instead of winning the probe
    /// with the same playlist every time.
    static func reportPlaybackFailure(of url: URL, playedSeconds: TimeInterval, playlistId: UUID,
                                      in database: AppDatabase = .shared) async {
        guard rulesOutHLS(failedURL: url, playedSeconds: playedSeconds) else { return }
        // Stored as "path-no-m3u8": a bare "path" would leave `.m3u8` first in the order.
        await persistStyle(TimeshiftStyleCache(winner: .path, hlsRuledOut: true),
                           playlistId: playlistId, in: database)
    }

    /// The cached shape as stored on the playlist row; the caller's snapshot is the
    /// fallback when the row cannot be read.
    static func storedStyle(for playlist: Playlist, in database: AppDatabase = .shared) async -> String? {
        let playlistId = playlist.id
        guard let row = try? await database.read({ db in try Playlist.fetchOne(db, key: playlistId) }) else {
            return playlist.timeshiftStyle
        }
        return row.timeshiftStyle
    }

    /// Writes only the `timeshiftStyle` column. Saving the caller's snapshot would
    /// write its other, possibly stale columns back and re-insert a playlist that
    /// was deleted while the probe ran.
    static func persistStyle(_ cache: TimeshiftStyleCache, playlistId: UUID,
                             in database: AppDatabase = .shared) async {
        let value = cache.storedValue
        _ = try? await database.write { db in
            try Playlist.filter(key: playlistId)
                .updateAll(db, [Column("timeshiftStyle").set(to: value)])
        }
    }
}
