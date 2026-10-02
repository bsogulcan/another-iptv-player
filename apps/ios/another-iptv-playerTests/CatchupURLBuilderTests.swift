import Foundation
import Testing
@testable import another_iptv_player

@Suite("CatchupURLBuilder")
struct CatchupURLBuilderTests {

    private func playlist(server: String = "http://host:8080", user: String = "user", pass: String = "pass") -> Playlist {
        Playlist(name: "t", serverURL: server, username: user, password: pass)
    }

    private let refDate = Date(timeIntervalSince1970: 1_784_719_800) // 2026-07-22 11:30:00 UTC

    // MARK: - Start string (timezone)

    @Test
    func startStringInPanelTimeZone() {
        let tz = TimeZone(secondsFromGMT: 3 * 3600)!
        #expect(PlaybackURLBuilder.timeshiftStartString(for: refDate, panelTimeZone: tz) == "2026-07-22:14-30")
    }

    @Test
    func startStringUTC() {
        #expect(PlaybackURLBuilder.timeshiftStartString(for: refDate, panelTimeZone: .gmt) == "2026-07-22:11-30")
    }

    @Test
    func startStringNegativeOffsetRollsDate() {
        // 11:30 UTC in -12h → 23:30 the previous day.
        let tz = TimeZone(secondsFromGMT: -12 * 3600)!
        #expect(PlaybackURLBuilder.timeshiftStartString(for: refDate, panelTimeZone: tz) == "2026-07-21:23-30")
    }

    // MARK: - Path-style URL

    @Test
    func pathURLGrammar() {
        let url = PlaybackURLBuilder(playlist: playlist()).timeshiftPathURL(
            streamId: 5, startUTC: refDate, durationMinutes: 60, panelTimeZone: .gmt, extension: "ts")
        #expect(url?.absoluteString == "http://host:8080/timeshift/user/pass/60/2026-07-22:11-30/5.ts")
    }

    @Test
    func pathURLPrefersM3U8Extension() {
        let url = PlaybackURLBuilder(playlist: playlist()).timeshiftPathURL(
            streamId: 9, startUTC: refDate, durationMinutes: 30, panelTimeZone: .gmt, extension: "m3u8")
        #expect(url?.absoluteString.hasSuffix("/9.m3u8") == true)
    }

    @Test
    func pathURLPercentEncodesCredentials() {
        let url = PlaybackURLBuilder(playlist: playlist(user: "a/b", pass: "p#1")).timeshiftPathURL(
            streamId: 1, startUTC: refDate, durationMinutes: 10, panelTimeZone: .gmt)
        // "/" and "#" in credentials must be percent-encoded within the path.
        #expect(url?.absoluteString.contains("a%2Fb") == true)
        #expect(url?.absoluteString.contains("p%231") == true)
    }

    // MARK: - PHP-style URL

    @Test
    func phpURLGrammar() {
        let url = PlaybackURLBuilder(playlist: playlist()).timeshiftPHPURL(
            streamId: 5, startUTC: refDate, durationMinutes: 60, panelTimeZone: .gmt)
        let s = url?.absoluteString ?? ""
        #expect(s.hasPrefix("http://host:8080/streaming/timeshift.php?"))
        #expect(s.contains("stream=5"))
        #expect(s.contains("duration=60"))
        #expect(s.contains("start=2026-07-22:11-30"))
        #expect(s.contains("username=user"))
    }

    @Test
    func phpURLEncodesPlusInPassword() {
        let url = PlaybackURLBuilder(playlist: playlist(pass: "a+b")).timeshiftPHPURL(
            streamId: 1, startUTC: refDate, durationMinutes: 10, panelTimeZone: .gmt)
        // PHP $_GET turns '+' into space; it must arrive as %2B.
        #expect(url?.absoluteString.contains("password=a%2Bb") == true)
    }

    // MARK: - XMLTV URL

    @Test
    func xmltvURLGrammar() {
        let url = PlaybackURLBuilder(playlist: playlist()).xmltvURL()
        let s = url?.absoluteString ?? ""
        #expect(s.hasPrefix("http://host:8080/xmltv.php?"))
        #expect(s.contains("username=user"))
        #expect(s.contains("password=pass"))
    }

    // MARK: - Resolver candidates

    @Test
    func candidatesCoverEveryShapeInTheGivenOrder() {
        let list = CatchupURLResolver.candidates(
            playlist: playlist(), streamId: 5, startUTC: refDate, durationMinutes: 60,
            panelTimeZone: .gmt, order: [.hls, .path, .php])
        #expect(list.map(\.style) == [.hls, .path, .php])
        #expect(list[0].url.absoluteString == "http://host:8080/timeshift/user/pass/60/2026-07-22:11-30/5.m3u8")
        #expect(list[1].url.absoluteString == "http://host:8080/timeshift/user/pass/60/2026-07-22:11-30/5.ts")
        #expect(list[2].url.absoluteString.hasPrefix("http://host:8080/streaming/timeshift.php?"))
    }

    @Test
    func hlsCandidateRoutesToTheAVPlayerPath() {
        // The engine picks AVPlayer by path extension, so the HLS shape must end in
        // `.m3u8` and the raw path shape must not.
        let list = CatchupURLResolver.candidates(
            playlist: playlist(), streamId: 9, startUTC: refDate, durationMinutes: 30,
            panelTimeZone: .gmt, order: [.path, .hls])
        #expect(list.map(\.url.pathExtension) == ["ts", "m3u8"])
    }
}
