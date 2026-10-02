import Foundation
import Testing
@testable import another_iptv_player

/// Serialized: several tests read and clear the process-wide recent-lines buffer.
/// Each one logs under its own unique tag, because other suites log in parallel.
@Suite("Log", .serialized)
struct LogTests {

    private func redact(_ string: String) -> String {
        guard let url = URL(string: string) else {
            Issue.record("not a URL: \(string)")
            return ""
        }
        return Log.redact(url)
    }

    private func uniqueTag(_ name: String = #function) -> String {
        "LogTests-\(name)-\(UUID().uuidString)"
    }

    // MARK: - redact(_:) — Xtream path credentials

    @Test
    func movieAndSeriesCredentialsAreReplaced() {
        #expect(redact("http://example.com:8080/movie/alice/s3cret/123.mkv")
            == "http://example.com:8080/movie/<user>/<pass>/123.mkv")
        #expect(redact("http://example.com/series/alice/s3cret/987.mp4")
            == "http://example.com/series/<user>/<pass>/987.mp4")
    }

    @Test
    func liveCredentialsAreReplacedWithAndWithoutKindSegment() {
        #expect(redact("http://example.com/live/alice/s3cret/55.ts")
            == "http://example.com/live/<user>/<pass>/55.ts")
        // PlaybackURLBuilder.liveURL shape: {host}/{user}/{pass}/{id}[.ext]
        #expect(redact("http://example.com/alice/s3cret/55")
            == "http://example.com/<user>/<pass>/55")
        #expect(redact("http://example.com/alice/s3cret/55.m3u8")
            == "http://example.com/<user>/<pass>/55.m3u8")
    }

    @Test
    func timeshiftPathKeepsDurationStartAndId() {
        #expect(redact("http://example.com/timeshift/alice/s3cret/60/2024-01-01:10-00/55.ts")
            == "http://example.com/timeshift/<user>/<pass>/60/2024-01-01:10-00/55.ts")
    }

    @Test
    func basePathPrefixBeforeKindIsKept() {
        #expect(redact("http://example.com/panel/movie/alice/s3cret/1.mkv")
            == "http://example.com/panel/movie/<user>/<pass>/1.mkv")
    }

    @Test
    func userNamedLikeAKindSegmentStillLosesThePassword() {
        // {user}/{pass}/{id} where the user happens to be called "live".
        let out = redact("http://example.com/live/s3cret/55.ts")
        #expect(!out.contains("s3cret"))
    }

    @Test
    func kindWithoutStreamIdStillHidesWhatFollows() {
        #expect(redact("http://example.com/live/alice/s3cret") == "http://example.com/live/<user>/<pass>")
    }

    @Test
    func percentEncodedCredentialsAreReplaced() {
        let out = redact("http://example.com/movie/a%40b/p%26q/7.mkv")
        #expect(out == "http://example.com/movie/<user>/<pass>/7.mkv")
    }

    // MARK: - redact(_:) — query, user info, unknown shapes

    @Test
    func queryIsReplacedWholesale() {
        #expect(redact("http://example.com/player_api.php?username=alice&password=s3cret&action=get_live_streams")
            == "http://example.com/player_api.php?<query>")
        #expect(redact("http://example.com/get.php?username=alice&password=s3cret&type=m3u_plus")
            == "http://example.com/get.php?<query>")
    }

    @Test
    func userInfoIsReplaced() {
        #expect(redact("http://alice:s3cret@example.com/list.m3u8")
            == "http://<credentials>@example.com/list.m3u8")
    }

    @Test
    func unknownPathIsCollapsedToItsFileName() {
        #expect(redact("https://cdn.example.com/hls/abc123def456/index.m3u8?token=zzz#frag")
            == "https://cdn.example.com/<path>/index.m3u8?<query>")
        // A base path in front of the plain live shape is not a known shape either.
        #expect(redact("http://example.com/panel/alice/s3cret/55.ts")
            == "http://example.com/<path>/55.ts")
        #expect(redact("http://example.com/streaming/timeshift.php?username=alice&password=s3cret")
            == "http://example.com/<path>/timeshift.php?<query>")
    }

    @Test
    func opaqueFileNamesAreReplacedButExtensionIsKept() {
        #expect(redact("http://example.com/a1b2c3d4e5.m3u8") == "http://example.com/<file>.m3u8")
        #expect(redact("rtmp://example.com/app/streamkey123abc") == "rtmp://example.com/<path>/<file>")
        // A bare word with no extension could be a credential.
        #expect(redact("http://example.com/alice/s3cret") == "http://example.com/<path>/<file>")
    }

    @Test
    func schemeHostAndPortAreKept() {
        #expect(redact("http://example.com") == "http://example.com")
        #expect(redact("https://example.com:8443/") == "https://example.com:8443/")
        #expect(redact("http://[::1]:8080/live/a/b/1.ts") == "http://[::1]:8080/live/<user>/<pass>/1.ts")
        #expect(redact("udp://@239.0.0.1:1234") == "udp://239.0.0.1:1234")
    }

    @Test
    func urlWithoutSchemeBecomesPlaceholder() {
        #expect(redact("live/alice/s3cret/1.ts") == "<url>")
    }

    // MARK: - redactURLs(in:)

    @Test
    func urlInsideAMessageIsRedacted() {
        let out = Log.redactURLs(in: "open failed for http://example.com/live/alice/s3cret/1.ts (timeout).")
        #expect(out == "open failed for http://example.com/live/<user>/<pass>/1.ts (timeout).")
    }

    @Test
    func surroundingPunctuationIsNotSwallowed() {
        let out = Log.redactURLs(
            in: "a (http://example.com/alice/s3cret/55), b \"http://h.example/x.php?username=a&password=b\" end"
        )
        #expect(out == "a (http://example.com/<user>/<pass>/55), b \"http://h.example/x.php?<query>\" end")
    }

    @Test
    func everyURLInAMessageIsRedacted() {
        let out = Log.redactURLs(
            in: "from http://a.example/movie/alice/s3cret/1.mkv to https://b.example/alice/s3cret/2.ts"
        )
        #expect(!out.contains("alice"))
        #expect(!out.contains("s3cret"))
        #expect(out.contains("http://a.example/movie/<user>/<pass>/1.mkv"))
        #expect(out.contains("https://b.example/<user>/<pass>/2.ts"))
    }

    @Test
    func bareCredentialPairsAreBlanked() {
        #expect(Log.redactURLs(in: "retry with username=alice&password=s3cret&x=1")
            == "retry with username=<redacted>&password=<redacted>&x=1")
        #expect(Log.redactURLs(in: "USERNAME=alice Token=abc") == "USERNAME=<redacted> Token=<redacted>")
    }

    @Test
    func messagesWithoutURLsAreUntouched() {
        // Includes the printf tokens that used to crash a bare NSLog.
        let message = "100% done %@ %s %20 — starting remux at 12s for live content (a=b)"
        #expect(Log.redactURLs(in: message) == message)
    }

    @Test
    func alreadyRedactedURLsPassThroughUnchanged() {
        let inputs = [
            "http://example.com/movie/alice/s3cret/123.mkv?x=1",
            "http://example.com/alice/s3cret/55.ts",
            "http://alice:s3cret@example.com/list.m3u8",
            "https://cdn.example.com/hls/abc123def456/index.m3u8?token=zzz",
            "http://example.com/player_api.php?username=alice&password=s3cret",
        ]
        for input in inputs {
            let once = redact(input)
            #expect(Log.redactURLs(in: once) == once)
        }
    }

    // MARK: - RingBuffer

    private func entry(_ message: String, tag: String = "t", level: Log.Level = .info) -> Log.Entry {
        Log.Entry(date: Date(), level: level, tag: tag, message: message)
    }

    @Test
    func ringBufferKeepsOnlyTheNewestEntriesInOrder() {
        let buffer = Log.RingBuffer(capacity: 3)
        for i in 0..<8 { buffer.append(entry("\(i)")) }
        #expect(buffer.entries().map(\.message) == ["5", "6", "7"])
    }

    @Test
    func ringBufferBelowCapacityReturnsEverything() {
        let buffer = Log.RingBuffer(capacity: 5)
        buffer.append(entry("a"))
        buffer.append(entry("b"))
        #expect(buffer.entries().map(\.message) == ["a", "b"])
    }

    @Test
    func ringBufferFiltersByTag() {
        let buffer = Log.RingBuffer(capacity: 10)
        buffer.append(entry("1", tag: "AirPlayCast"))
        buffer.append(entry("2", tag: "Persistence"))
        buffer.append(entry("3", tag: "AirPlayRemux"))
        #expect(buffer.entries(tags: ["AirPlayCast", "AirPlayRemux"]).map(\.message) == ["1", "3"])
        #expect(buffer.entries(tags: []).isEmpty)
        #expect(buffer.entries(tags: nil).count == 3)
    }

    @Test
    func ringBufferRemoveAllEmptiesAndStaysUsable() {
        let buffer = Log.RingBuffer(capacity: 2)
        for i in 0..<5 { buffer.append(entry("\(i)")) }
        buffer.removeAll()
        #expect(buffer.entries().isEmpty)
        buffer.append(entry("x"))
        buffer.append(entry("y"))
        buffer.append(entry("z"))
        #expect(buffer.entries().map(\.message) == ["y", "z"])
    }

    @Test
    func ringBufferSurvivesConcurrentWriters() {
        let buffer = Log.RingBuffer(capacity: 50)
        // @Sendable: the closure runs off the main actor on the worker threads.
        DispatchQueue.concurrentPerform(iterations: 2_000) { @Sendable i in
            buffer.append(Log.Entry(date: Date(), level: .info, tag: "t", message: "\(i)"))
            if i % 100 == 0 { _ = buffer.entries() }
        }
        #expect(buffer.entries().count == 50)
    }

    @Test
    func entryLineHasTimestampTagAndLevel() {
        let info = entry("hello", tag: "AirPlayCast").line
        let error = entry("boom", tag: "AirPlayCast", level: .error).line
        let stamp = #"^\d{2}:\d{2}:\d{2}\.\d{3} "#
        #expect(info.range(of: stamp + #"\[AirPlayCast\] hello$"#, options: .regularExpression) != nil)
        #expect(error.range(of: stamp + #"\[AirPlayCast\] ERROR: boom$"#, options: .regularExpression) != nil)
    }

    // MARK: - Log.info / Log.error -> recentLines

    @Test
    func infoAndErrorLandInRecentLines() {
        let tag = uniqueTag()
        Log.info(tag, "first")
        Log.error(tag, "second")
        let lines = Log.recentLines(tags: [tag])
        #expect(lines.count == 2)
        #expect(lines.first?.hasSuffix("[\(tag)] first") == true)
        #expect(lines.last?.hasSuffix("[\(tag)] ERROR: second") == true)
    }

    @Test
    func loggedMessagesAreRedactedBeforeTheyAreStored() {
        let tag = uniqueTag()
        Log.info(tag, "playing http://example.com/movie/alice/s3cret/123.mkv?token=zzz")
        let lines = Log.recentLines(tags: [tag])
        #expect(lines.count == 1)
        #expect(lines.first?.contains("alice") == false)
        #expect(lines.first?.contains("s3cret") == false)
        #expect(lines.first?.contains("zzz") == false)
        #expect(lines.first?.hasSuffix("playing http://example.com/movie/<user>/<pass>/123.mkv?<query>") == true)
    }

    @Test
    func recentLinesFiltersByTagAndAcceptsAnySequence() {
        let wanted = uniqueTag()
        let other = uniqueTag()
        Log.info(wanted, "keep")
        Log.info(other, "skip")
        #expect(Log.recentLines(tags: [wanted]).count == 1)
        #expect(Log.recentLines(tags: Set([wanted, other])).count == 2)
        #expect(Log.recentLines(tags: [String]()).isEmpty)
        // No filter returns every tag, so both lines are in there.
        let all = Log.recentLines()
        #expect(all.contains { $0.contains(wanted) })
        #expect(all.contains { $0.contains(other) })
    }

    @Test
    func recentLinesAreCappedAtCapacity() {
        #expect(Log.recentCapacity == 300)
        let tag = uniqueTag()
        for i in 0..<(Log.recentCapacity + 20) { Log.info(tag, "n\(i)") }
        let lines = Log.recentLines(tags: [tag])
        #expect(lines.count <= Log.recentCapacity)
        #expect(Log.recentLines().count <= Log.recentCapacity)
        #expect(lines.last?.hasSuffix("n\(Log.recentCapacity + 19)") == true)
        // The oldest lines of this run were pushed out.
        #expect(!lines.contains { $0.hasSuffix("] n0") })
    }

    @Test
    func clearRecentDropsStoredLines() {
        let tag = uniqueTag()
        Log.info(tag, "gone")
        #expect(Log.recentLines(tags: [tag]).count == 1)
        Log.clearRecent()
        #expect(Log.recentLines(tags: [tag]).isEmpty)
    }

    // MARK: - persistRecent / persistedLines

    /// A defaults suite of its own per test, removed afterwards: the tests must not
    /// write into the app's defaults, where the real AirPlay record lives.
    private func withScratchDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "LogTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("no defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test
    func persistedLinesAreTheRecentLinesOfTheTags() {
        withScratchDefaults { defaults in
            let wanted = uniqueTag()
            let other = uniqueTag()
            let key = "log.test.record"
            #expect(Log.persistedLines(key: key, defaults: defaults).isEmpty)
            #expect(Log.persistedDate(key: key, defaults: defaults) == nil)

            Log.info(wanted, "first")
            Log.info(other, "not mine")
            Log.error(wanted, "second")
            let before = Date()
            Log.persistRecent(tags: [wanted], key: key, defaults: defaults)

            let stored = Log.persistedLines(key: key, defaults: defaults)
            #expect(stored == Log.recentLines(tags: [wanted]))
            #expect(stored.count == 2)
            #expect(stored.first?.hasSuffix("[\(wanted)] first") == true)
            #expect(stored.last?.hasSuffix("[\(wanted)] ERROR: second") == true)
            let savedAt = Log.persistedDate(key: key, defaults: defaults)
            #expect(savedAt != nil)
            #expect((savedAt ?? .distantPast) >= before.addingTimeInterval(-1))
            // Another key is another record.
            #expect(Log.persistedLines(key: "log.test.other", defaults: defaults).isEmpty)
        }
    }

    /// The record is a copy, not a view of the in-memory buffer: it only changes
    /// when it is written again, and a write with nothing to store keeps it. (The
    /// buffer is not cleared here: other suites log into it in parallel.)
    @Test
    func persistedRecordChangesOnlyWhenWrittenAgain() {
        withScratchDefaults { defaults in
            let tag = uniqueTag()
            let silentTag = uniqueTag()
            let key = "log.test.record"
            Log.info(tag, "kept")
            Log.persistRecent(tags: [tag], key: key, defaults: defaults)
            let stored = Log.persistedLines(key: key, defaults: defaults)
            #expect(stored.count == 1)
            #expect(stored.first?.hasSuffix("[\(tag)] kept") == true)

            // Logged after the write: in the buffer, not in the record.
            Log.info(tag, "newer")
            #expect(Log.recentLines(tags: [tag]).count == 2)
            #expect(Log.persistedLines(key: key, defaults: defaults) == stored)

            // Nothing to store: the last useful record is kept, not erased.
            Log.persistRecent(tags: [silentTag], key: key, defaults: defaults)
            #expect(Log.persistedLines(key: key, defaults: defaults) == stored)
            Log.persistRecent(tags: [], key: key, defaults: defaults)
            #expect(Log.persistedLines(key: key, defaults: defaults) == stored)
            Log.persistRecent(tags: [tag], key: key, limit: 0, defaults: defaults)
            #expect(Log.persistedLines(key: key, defaults: defaults) == stored)

            // A later write replaces the record as a whole.
            Log.persistRecent(tags: [tag], key: key, defaults: defaults)
            let replaced = Log.persistedLines(key: key, defaults: defaults)
            #expect(replaced.count == 2)
            #expect(replaced.last?.hasSuffix("[\(tag)] newer") == true)
        }
    }

    @Test
    func persistedLinesAreRedactedLikeTheLog() {
        withScratchDefaults { defaults in
            let tag = uniqueTag()
            let key = "log.test.record"
            Log.info(tag, "starting remux of http://example.com/movie/alice/s3cret/123.mkv?token=zzz")
            Log.persistRecent(tags: [tag], key: key, defaults: defaults)
            let stored = Log.persistedLines(key: key, defaults: defaults).joined(separator: "\n")
            #expect(!stored.isEmpty)
            #expect(!stored.contains("alice"))
            #expect(!stored.contains("s3cret"))
            #expect(!stored.contains("zzz"))
            #expect(stored.contains("http://example.com/movie/<user>/<pass>/123.mkv?<query>"))
        }
    }

    @Test
    func persistRecentKeepsTheNewestLinesUpToTheLimit() {
        withScratchDefaults { defaults in
            let tag = uniqueTag()
            let key = "log.test.record"
            for i in 0..<10 { Log.info(tag, "n\(i)") }
            Log.persistRecent(tags: [tag], key: key, limit: 3, defaults: defaults)
            let stored = Log.persistedLines(key: key, defaults: defaults)
            #expect(stored.count == 3)
            #expect(stored.first?.hasSuffix("] n7") == true)
            #expect(stored.last?.hasSuffix("] n9") == true)
        }
    }

    /// What is stored is bounded whatever the caller asks for: the record sits in
    /// UserDefaults.
    @Test
    func persistableLinesAreCappedInCountAndLength() {
        #expect(Log.persistedLineLimit == 200)
        #expect(Log.persistedLineLength == 300)
        let many = (0..<500).map { "line \($0)" }
        #expect(Log.persistable(many, limit: 120).count == 120)
        #expect(Log.persistable(many, limit: 120).last == "line 499")
        #expect(Log.persistable(many, limit: 120).first == "line 380")
        #expect(Log.persistable(many, limit: 10_000).count == Log.persistedLineLimit)
        #expect(Log.persistable(many, limit: 0).isEmpty)
        #expect(Log.persistable(many, limit: -5).isEmpty)
        #expect(Log.persistable([], limit: 120).isEmpty)

        let long = String(repeating: "x", count: 1_000)
        let cut = Log.persistable([long, "short"], limit: 120)
        #expect(cut.count == 2)
        #expect(cut[0].count == Log.persistedLineLength + 1)
        #expect(cut[0].hasSuffix("…"))
        #expect(cut[1] == "short")
        // A line of exactly the limit is left alone.
        let exact = String(repeating: "y", count: Log.persistedLineLength)
        #expect(Log.persistable([exact], limit: 1) == [exact])
    }

    @Test
    func messageClosureRunsExactlyOnce() {
        let tag = uniqueTag()
        var calls = 0
        func message() -> String {
            calls += 1
            return "once"
        }
        Log.info(tag, message())
        Log.error(tag, message())
        #expect(calls == 2)
    }
}
