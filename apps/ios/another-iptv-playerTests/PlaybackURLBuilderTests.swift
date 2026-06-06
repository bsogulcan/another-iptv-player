import Foundation
import Testing
@testable import another_iptv_player

@Suite("PlaybackURLBuilder")
struct PlaybackURLBuilderTests {

    private func builder(
        serverURL: String,
        username: String = "user",
        password: String = "pass"
    ) -> PlaybackURLBuilder {
        let playlist = Playlist(
            id: UUID(),
            name: "T",
            serverURL: serverURL,
            username: username,
            password: password
        )
        return PlaybackURLBuilder(playlist: playlist)
    }

    // MARK: - liveURL

    @Test
    func liveURLBasicFormat() {
        let url = builder(serverURL: "http://srv.com").liveURL(streamId: 42)
        #expect(url?.absoluteString == "http://srv.com/user/pass/42")
    }

    @Test
    func liveURLAppendsExtension() {
        let url = builder(serverURL: "http://srv.com").liveURL(streamId: 42, extension: "ts")
        #expect(url?.absoluteString == "http://srv.com/user/pass/42.ts")
    }

    @Test
    func liveURLIgnoresEmptyExtension() {
        let url = builder(serverURL: "http://srv.com").liveURL(streamId: 42, extension: "")
        #expect(url?.absoluteString == "http://srv.com/user/pass/42")
    }

    // MARK: - movieURL

    @Test
    func movieURLBasicFormat() {
        let url = builder(serverURL: "http://srv.com").movieURL(streamId: 99, containerExtension: "mkv")
        #expect(url?.absoluteString == "http://srv.com/movie/user/pass/99.mkv")
    }

    @Test
    func movieURLDefaultsToMP4WhenExtensionNil() {
        let url = builder(serverURL: "http://srv.com").movieURL(streamId: 99, containerExtension: nil)
        #expect(url?.absoluteString == "http://srv.com/movie/user/pass/99.mp4")
    }

    // MARK: - seriesURL

    @Test
    func seriesURLBasicFormat() {
        let url = builder(serverURL: "http://srv.com").seriesURL(streamId: "abc123", containerExtension: "mp4")
        #expect(url?.absoluteString == "http://srv.com/series/user/pass/abc123.mp4")
    }

    @Test
    func seriesURLDefaultsToMP4WhenExtensionNil() {
        let url = builder(serverURL: "http://srv.com").seriesURL(streamId: "ep1", containerExtension: nil)
        #expect(url?.absoluteString == "http://srv.com/series/user/pass/ep1.mp4")
    }

    // MARK: - Server URL sanitization

    @Test
    func prependsHTTPSchemeWhenMissing() {
        let url = builder(serverURL: "srv.com").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com/user/pass/1")
    }

    @Test
    func preservesHTTPSScheme() {
        let url = builder(serverURL: "https://srv.com").liveURL(streamId: 1)
        #expect(url?.absoluteString == "https://srv.com/user/pass/1")
    }

    @Test
    func stripsTrailingSlash() {
        let url = builder(serverURL: "http://srv.com/").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com/user/pass/1")
    }

    @Test
    func stripsPlayerApiSuffixWithLeadingSlash() {
        let url = builder(serverURL: "http://srv.com/player_api.php").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com/user/pass/1")
    }

    @Test
    func stripsPlayerApiSuffixWithoutLeadingSlash() {
        let url = builder(serverURL: "http://srv.com:8080player_api.php").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com:8080/user/pass/1")
    }

    @Test
    func trimsLeadingAndTrailingWhitespace() {
        let url = builder(serverURL: "  http://srv.com  ").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com/user/pass/1")
    }

    @Test
    func removesInternalSpaces() {
        let url = builder(serverURL: "http://srv .com").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com/user/pass/1")
    }

    @Test
    func includesPortInBase() {
        let url = builder(serverURL: "http://srv.com:8080").liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com:8080/user/pass/1")
    }

    @Test
    func trimsCredentialWhitespace() {
        let url = builder(serverURL: "http://srv.com", username: "  u  ", password: " p ")
            .liveURL(streamId: 1)
        #expect(url?.absoluteString == "http://srv.com/u/p/1")
    }
}
