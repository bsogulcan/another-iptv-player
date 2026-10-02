import Foundation
import Testing
@testable import another_iptv_player

/// `Playlist.displaySource`: what a playlist row shows as its source. The stored
/// link of an M3U playlist can hold the account, so nothing but the host and port
/// may come out.
@Suite("Playlist display source")
struct PlaylistDisplaySourceTests {

    private func source(_ serverURL: String) -> String {
        Playlist(name: "p", serverURL: serverURL, type: .m3u).displaySource
    }

    /// Fragments that must never reach the screen, whatever the link looks like.
    private static let secrets = ["ali", "s3cret", "tok3n", "username", "password", "get.php", "?", "@", "/"]

    private func expectNoSecrets(in shown: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for secret in Self.secrets {
            #expect(!shown.contains(secret), "\"\(shown)\" contains \"\(secret)\"", sourceLocation: sourceLocation)
        }
    }

    // MARK: Credentials

    @Test
    func credentialsInTheQueryAreDropped() {
        let shown = source("http://tv.example.com:8080/get.php?username=ali&password=s3cret&type=m3u_plus&output=ts")
        #expect(shown == "tv.example.com:8080")
        expectNoSecrets(in: shown)

        let token = source("https://cdn.example.net/playlist.m3u8?token=tok3n")
        #expect(token == "cdn.example.net")
        expectNoSecrets(in: token)
    }

    @Test
    func credentialsInThePathAreDropped() {
        let shown = source("http://tv.example.com:8080/live/ali/s3cret/playlist.m3u")
        #expect(shown == "tv.example.com:8080")
        expectNoSecrets(in: shown)

        let noPort = source("https://tv.example.com/ali/s3cret/tv_channels.m3u")
        #expect(noPort == "tv.example.com")
        expectNoSecrets(in: noPort)
    }

    @Test
    func credentialsInTheUserInfoAreDropped() {
        let shown = source("http://ali:s3cret@tv.example.com:8080/list.m3u")
        #expect(shown == "tv.example.com:8080")
        expectNoSecrets(in: shown)
    }

    /// Typed without a scheme, "host:8080/…" parses as a URL whose scheme is the
    /// host. The account must not slip through that path either.
    @Test
    func linksWithoutASchemeKeepOnlyTheAuthority() {
        let query = source("tv.example.com:8080/get.php?username=ali&password=s3cret")
        #expect(query == "tv.example.com:8080")
        expectNoSecrets(in: query)

        let path = source("tv.example.com/live/ali/s3cret/1.m3u")
        #expect(path == "tv.example.com")
        expectNoSecrets(in: path)

        let userInfo = source("ali:s3cret@tv.example.com:8080/list.m3u")
        #expect(userInfo == "tv.example.com:8080")
        expectNoSecrets(in: userInfo)

        let bareQuery = source("tv.example.com?token=tok3n")
        #expect(bareQuery == "tv.example.com")
        expectNoSecrets(in: bareQuery)
    }

    // MARK: Plain sources

    @Test
    func hostAndPortAreShownAsTheyAre() {
        #expect(source("http://tv.example.com") == "tv.example.com")
        #expect(source("http://tv.example.com/") == "tv.example.com")
        #expect(source("https://tv.example.com:443") == "tv.example.com:443")
        #expect(source("http://192.168.1.20:8080") == "192.168.1.20:8080")
        #expect(source("  http://tv.example.com:8080  ") == "tv.example.com:8080")
        #expect(source("tv.example.com") == "tv.example.com")
        #expect(source("localhost:8080") == "localhost:8080")
    }

    @Test
    func ipv6HostKeepsItsBracketsBeforeAPort() {
        #expect(source("http://[2001:db8::1]:8080/get.php?username=ali&password=s3cret") == "[2001:db8::1]:8080")
        #expect(source("http://[2001:db8::1]/list.m3u") == "[2001:db8::1]")
    }

    @Test
    func xtreamPlaylistShowsItsServer() {
        let playlist = Playlist(name: "Panel", serverURL: "http://panel.example.com:2095",
                                username: "ali", password: "s3cret")
        #expect(playlist.displaySource == "panel.example.com:2095")
    }

    @Test
    func playlistWithoutAURLIsALocalFile() {
        #expect(source("") == L("playlists.local_file"))
        #expect(source("   \n") == L("playlists.local_file"))
    }
}
