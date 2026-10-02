import Foundation
import Testing
@testable import another_iptv_player

@Suite("CatchupURLResolver")
struct CatchupURLResolverTests {

    private struct ProbeFailure: Error {}

    private enum Answer {
        case media, rejected, failed
    }

    private final class Recorder {
        var probed: [TimeshiftStyle] = []
        var persisted: [String] = []
        var inFlight = 0
        var maxInFlight = 0
    }

    private func candidates(_ order: [TimeshiftStyle]) -> [ResolvedCatchupStream] {
        order.map { ResolvedCatchupStream(url: URL(string: "http://host/\($0.rawValue)")!, style: $0) }
    }

    /// Runs the probe loop the way `resolve(playlist:)` does: order derived from
    /// the stored value, scripted probe answers, persisted values captured.
    private func run(stored: String?,
                     answers: [TimeshiftStyle: Answer],
                     recorder: Recorder) async throws -> ResolvedCatchupStream {
        let cached = TimeshiftStyleCache(storedValue: stored)
        return try await CatchupURLResolver.resolve(
            candidates: candidates(TimeshiftStyleCache.probeOrder(for: cached)),
            cached: cached,
            probe: { candidate in
                recorder.probed.append(candidate.style)
                recorder.inFlight += 1
                recorder.maxInFlight = max(recorder.maxInFlight, recorder.inFlight)
                await Task.yield()
                recorder.inFlight -= 1
                switch answers[candidate.style] ?? .rejected {
                case .media: return true
                case .rejected: return false
                case .failed: throw ProbeFailure()
                }
            },
            persist: { recorder.persisted.append($0.storedValue) })
    }

    // MARK: - Probe order

    @Test
    func orderWithoutCacheIsHLSThenPathThenPHP() {
        #expect(TimeshiftStyleCache.probeOrder(for: nil) == [.hls, .path, .php])
    }

    @Test
    func legacyCachedShapesStillTryHLSFirst() {
        // "path"/"php" were written before the `.m3u8` probe existed.
        #expect(TimeshiftStyleCache.probeOrder(for: TimeshiftStyleCache(storedValue: "path")) == [.hls, .path, .php])
        #expect(TimeshiftStyleCache.probeOrder(for: TimeshiftStyleCache(storedValue: "php")) == [.hls, .php, .path])
    }

    @Test
    func cachedHLSKeepsDefaultOrder() {
        #expect(TimeshiftStyleCache.probeOrder(for: TimeshiftStyleCache(storedValue: "m3u8")) == [.hls, .path, .php])
    }

    @Test
    func ruledOutHLSMovesToTheBack() {
        #expect(TimeshiftStyleCache.probeOrder(for: TimeshiftStyleCache(storedValue: "path-no-m3u8")) == [.path, .php, .hls])
        #expect(TimeshiftStyleCache.probeOrder(for: TimeshiftStyleCache(storedValue: "php-no-m3u8")) == [.php, .path, .hls])
    }

    // MARK: - Cached value

    @Test
    func storedValueRoundTrips() {
        for raw in ["m3u8", "path", "php", "path-no-m3u8", "php-no-m3u8"] {
            #expect(TimeshiftStyleCache(storedValue: raw)?.storedValue == raw)
        }
        #expect(TimeshiftStyleCache(storedValue: "php-no-m3u8") == TimeshiftStyleCache(winner: .php, hlsRuledOut: true))
        #expect(TimeshiftStyleCache(storedValue: "path") == TimeshiftStyleCache(winner: .path, hlsRuledOut: false))
    }

    @Test
    func unknownStoredValuesAreIgnored() {
        #expect(TimeshiftStyleCache(storedValue: nil) == nil)
        #expect(TimeshiftStyleCache(storedValue: "") == nil)
        #expect(TimeshiftStyleCache(storedValue: "rtmp") == nil)
        #expect(TimeshiftStyleCache(storedValue: "m3u8-no-m3u8") == nil)
    }

    @Test
    func hlsWinnerNeverCarriesTheRuledOutMark() {
        let cache = TimeshiftStyleCache(winner: .hls, hlsRuledOut: true)
        #expect(!cache.hlsRuledOut)
        #expect(cache.storedValue == "m3u8")
    }

    // MARK: - Resolution

    @Test
    func hlsWinsFirstAndIsCachedAsM3U8() async throws {
        let recorder = Recorder()
        let resolved = try await run(stored: nil, answers: [.hls: .media, .path: .media, .php: .media], recorder: recorder)
        #expect(resolved.style == .hls)
        #expect(recorder.probed == [.hls])
        #expect(recorder.persisted == ["m3u8"])
    }

    @Test
    func fallsBackToPathTSAndRulesHLSOut() async throws {
        let recorder = Recorder()
        let resolved = try await run(stored: nil, answers: [.path: .media, .php: .media], recorder: recorder)
        #expect(resolved.style == .path)
        #expect(recorder.probed == [.hls, .path])
        #expect(recorder.persisted == ["path-no-m3u8"])
    }

    @Test
    func fallsBackToPHPLast() async throws {
        let recorder = Recorder()
        let resolved = try await run(stored: nil, answers: [.php: .media], recorder: recorder)
        #expect(resolved.style == .php)
        #expect(recorder.probed == [.hls, .path, .php])
        #expect(recorder.persisted == ["php-no-m3u8"])
    }

    @Test
    func playlistCachedAsPHPGetsHLSTriedOnce() async throws {
        // First start after the update: HLS is probed ahead of the cached PHP shape.
        let first = Recorder()
        let resolved = try await run(stored: "php", answers: [.php: .media], recorder: first)
        #expect(resolved.style == .php)
        #expect(first.probed == [.hls, .php])
        #expect(first.persisted == ["php-no-m3u8"])

        // Later starts go straight to PHP: no second failed HLS connection.
        let second = Recorder()
        _ = try await run(stored: "php-no-m3u8", answers: [.php: .media], recorder: second)
        #expect(second.probed == [.php])
        #expect(second.persisted.isEmpty)
    }

    @Test
    func playlistCachedAsPHPUpgradesToHLS() async throws {
        let recorder = Recorder()
        let resolved = try await run(stored: "php", answers: [.hls: .media, .php: .media], recorder: recorder)
        #expect(resolved.style == .hls)
        #expect(recorder.probed == [.hls])
        #expect(recorder.persisted == ["m3u8"])
    }

    @Test
    func unchangedWinnerIsNotWrittenAgain() async throws {
        let recorder = Recorder()
        _ = try await run(stored: "m3u8", answers: [.hls: .media], recorder: recorder)
        #expect(recorder.probed == [.hls])
        #expect(recorder.persisted.isEmpty)
    }

    @Test
    func provenHLSIsRuledOutOnlyAfterTwoMisses() async throws {
        // First miss on a panel where HLS has worked: fall back, keep HLS on trial.
        let first = Recorder()
        let resolved = try await run(stored: "m3u8", answers: [.path: .media], recorder: first)
        #expect(resolved.style == .path)
        #expect(first.probed == [.hls, .path])
        #expect(first.persisted == ["path"])

        // Second miss in a row rules it out.
        let second = Recorder()
        _ = try await run(stored: "path", answers: [.path: .media], recorder: second)
        #expect(second.probed == [.hls, .path])
        #expect(second.persisted == ["path-no-m3u8"])
    }

    @Test
    func ruledOutHLSIsTheLastResortAndCanWinBack() async throws {
        let recorder = Recorder()
        let resolved = try await run(stored: "path-no-m3u8", answers: [.hls: .media], recorder: recorder)
        #expect(resolved.style == .hls)
        #expect(recorder.probed == [.path, .php, .hls])
        #expect(recorder.persisted == ["m3u8"])
    }

    @Test
    func ruledOutMarkSurvivesAWinnerChange() async throws {
        let recorder = Recorder()
        let resolved = try await run(stored: "path-no-m3u8", answers: [.php: .media], recorder: recorder)
        #expect(resolved.style == .php)
        #expect(recorder.probed == [.path, .php])
        #expect(recorder.persisted == ["php-no-m3u8"])
    }

    @Test
    func hlsProbeErrorStillFallsBackAndRulesHLSOut() async throws {
        // A panel that hangs on `.m3u8` must not cost a timeout on every start.
        let recorder = Recorder()
        let resolved = try await run(stored: nil, answers: [.hls: .failed, .path: .media], recorder: recorder)
        #expect(resolved.style == .path)
        #expect(recorder.persisted == ["path-no-m3u8"])
    }

    @Test
    func nothingIsCachedWhenNoShapeAnswers() async {
        let recorder = Recorder()
        do {
            _ = try await run(stored: nil, answers: [:], recorder: recorder)
            Issue.record("expected the resolve to fail")
        } catch CatchupURLError.notAvailable {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(recorder.probed == [.hls, .path, .php])
        #expect(recorder.persisted.isEmpty)
    }

    @Test
    func probeErrorSurfacesAsNetworkErrorWhenNothingWins() async {
        let recorder = Recorder()
        do {
            _ = try await run(stored: nil, answers: [.path: .failed], recorder: recorder)
            Issue.record("expected the resolve to fail")
        } catch CatchupURLError.network(let underlying) {
            #expect(underlying is ProbeFailure)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(recorder.persisted.isEmpty)
    }

    @Test
    func probesNeverOverlap() async throws {
        // One connection at a time: a probe has finished before the next begins.
        let recorder = Recorder()
        _ = try await run(stored: nil, answers: [.php: .media], recorder: recorder)
        #expect(recorder.probed.count == 3)
        #expect(recorder.maxInFlight == 1)
    }

    // MARK: - HLS playlist scan

    private func scan(_ text: String) -> HLSPlaylistScan.Verdict {
        var scan = HLSPlaylistScan()
        for line in text.split(whereSeparator: \.isNewline) {
            let verdict = scan.feed(String(line))
            if verdict != .undecided { return verdict }
        }
        return .undecided
    }

    @Test
    func finitePlaylistWithSegmentsIsAccepted() {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:60
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:60.0,
        /timeshift/user/pass/1/2026-07-22:11-30/5.ts
        #EXTINF:60.0,
        /timeshift/user/pass/1/2026-07-22:11-31/5.ts
        #EXT-X-ENDLIST
        """
        #expect(scan(playlist) == .accepted)
    }

    @Test
    func headerOnlyPlaylistIsNotAccepted() {
        #expect(scan("#EXTM3U\n") == .undecided)
        #expect(scan("#EXTM3U\n#EXT-X-ENDLIST\n") == .rejected)
    }

    @Test
    func openEndedPlaylistIsNotAccepted() {
        // No `#EXT-X-ENDLIST`: a live-style list would start at its end, not at the
        // programme start.
        #expect(scan("#EXTM3U\n#EXTINF:10.0,\nseg0.ts\n#EXTINF:10.0,\nseg1.ts\n") == .undecided)
    }

    @Test
    func nonPlaylistBodiesAreRejectedOnTheFirstLine() {
        #expect(scan("<html><body>Not found</body></html>") == .rejected)
        #expect(scan("G@\u{0}\u{10}\n#EXTINF:1,\n#EXT-X-ENDLIST") == .rejected)
    }

    @Test
    func endlessPlaylistIsCutOff() {
        var scan = HLSPlaylistScan()
        #expect(scan.feed("#EXTM3U") == .undecided)
        var verdict = HLSPlaylistScan.Verdict.undecided
        for _ in 0..<HLSPlaylistScan.maxLines where verdict == .undecided {
            verdict = scan.feed("#EXTINF:1.0,")
        }
        #expect(verdict == .rejected)
    }

    // MARK: - Cache persistence

    @Test
    func persistWritesOnlyTheTimeshiftColumn() async throws {
        let database = AppDatabase.empty()
        let stored = Playlist(name: "current", serverURL: "http://host:8080", username: "u", password: "p",
                              serverTimezone: "Europe/Istanbul", timeshiftStyle: "php")
        try await database.write { db in try stored.insert(db) }

        await CatchupURLResolver.persistStyle(TimeshiftStyleCache(winner: .hls, hlsRuledOut: false),
                                              playlistId: stored.id, in: database)

        let row = try await database.read { db in try Playlist.fetchOne(db, key: stored.id) }
        #expect(row?.timeshiftStyle == "m3u8")
        #expect(row?.name == "current")
        #expect(row?.serverTimezone == "Europe/Istanbul")
    }

    @Test
    func persistDoesNotRecreateADeletedPlaylist() async throws {
        let database = AppDatabase.empty()
        await CatchupURLResolver.persistStyle(TimeshiftStyleCache(winner: .path, hlsRuledOut: true),
                                              playlistId: UUID(), in: database)
        let count = try await database.read { db in try Playlist.fetchCount(db) }
        #expect(count == 0)
    }

    @Test
    func storedStylePrefersTheRowOverAStaleSnapshot() async throws {
        let database = AppDatabase.empty()
        var playlist = Playlist(name: "p", serverURL: "http://host:8080", timeshiftStyle: "php")
        try await database.write { [playlist] db in try playlist.insert(db) }
        await CatchupURLResolver.persistStyle(TimeshiftStyleCache(winner: .php, hlsRuledOut: true),
                                              playlistId: playlist.id, in: database)

        // The view still holds the snapshot from before the probe.
        #expect(playlist.timeshiftStyle == "php")
        let fresh = await CatchupURLResolver.storedStyle(for: playlist, in: database)
        #expect(fresh == "php-no-m3u8")

        // A playlist that is not in the database falls back to the snapshot.
        playlist.id = UUID()
        let fallback = await CatchupURLResolver.storedStyle(for: playlist, in: database)
        #expect(fallback == "php")
    }
}
