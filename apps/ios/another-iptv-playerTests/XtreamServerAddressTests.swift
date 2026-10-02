import Foundation
import Testing
@testable import another_iptv_player

/// `XtreamLinkDetector.normalizedServerURL`: what the Xtream form stores for the
/// text in its address field, and the account links `detect` learned next to
/// `get.php`.
@Suite("Xtream server address")
struct XtreamServerAddressTests {

    private func normalized(_ input: String) -> String? {
        XtreamLinkDetector.normalizedServerURL(input)
    }

    // MARK: - Scheme

    @Test
    func aBareHostGetsHTTP() {
        #expect(normalized("host.example:8080") == "http://host.example:8080")
        #expect(normalized("192.168.1.5:25461") == "http://192.168.1.5:25461")
        #expect(normalized("example.com") == "http://example.com")
    }

    @Test
    func anExplicitSchemeIsKept() {
        #expect(normalized("https://host.example") == "https://host.example")
        #expect(normalized("HTTP://host.example:8080") == "http://host.example:8080")
    }

    /// A typed prefix followed by a pasted address. The pasted scheme is the real one.
    @Test
    func aRepeatedSchemeCollapsesToTheLastOne() {
        #expect(normalized("http://http://host.example:8080") == "http://host.example:8080")
        #expect(normalized("http://https://host.example:8443") == "https://host.example:8443")
    }

    @Test
    func otherSchemesAreRefused() {
        #expect(normalized("rtsp://host.example/stream") == nil)
        #expect(normalized("file:///list.m3u") == nil)
    }

    // MARK: - What follows the host

    @Test
    func trailingSlashesAreDropped() {
        #expect(normalized("http://host.example:8080/") == "http://host.example:8080")
        #expect(normalized("host.example/panel//") == "http://host.example/panel")
    }

    /// The client appends `player_api.php` itself; an endpoint or a query left in
    /// the address would end up in the middle of the request.
    @Test
    func endpointQueryAndAccountAreDropped() {
        #expect(normalized("http://host.example:8080/get.php?username=a&password=b&type=m3u_plus&output=ts") == "http://host.example:8080")
        #expect(normalized("http://host.example/panel/player_api.php?username=a&password=b") == "http://host.example/panel")
        #expect(normalized("http://host.example:8080/xmltv.php?username=a&password=b") == "http://host.example:8080")
        #expect(normalized("http://host.example:8080/GET.PHP") == "http://host.example:8080")
        #expect(normalized("http://host.example:8080/?next=http://elsewhere.example") == "http://host.example:8080")
        #expect(normalized("http://someone:secret@host.example:80/c/") == "http://host.example:80/c")
    }

    @Test
    func aPathPrefixIsKept() {
        #expect(normalized("http://host.example/panel") == "http://host.example/panel")
    }

    @Test
    func whitespaceFromAWrappedPasteIsRemoved() {
        #expect(normalized("  http://host.example:8080 \n") == "http://host.example:8080")
        #expect(normalized("http://host.exam\nple:8080") == "http://host.example:8080")
    }

    // MARK: - No address

    @Test
    func textWithoutAHostIsRefused() {
        #expect(normalized("") == nil)
        #expect(normalized("   ") == nil)
        #expect(normalized("http://") == nil)
        #expect(normalized("https://http://") == nil)
        #expect(normalized("http:///path") == nil)
    }

    // MARK: - Account links

    @Test
    func aPlayerAPILinkIsAnAccountLink() {
        let credentials = XtreamLinkDetector.detect(
            urlString: "http://example.com:8080/player_api.php?username=user&password=pass"
        )
        #expect(credentials == XtreamLinkDetector.Credentials(
            serverURL: "http://example.com:8080", username: "user", password: "pass"
        ))
    }

    @Test
    func aPlayerAPIAddressWithoutAnAccountIsNot() {
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/player_api.php") == nil)
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/player_api.php?username=u") == nil)
    }

    @Test
    func anAccountLinkWithoutASchemeIsReadAsHTTP() {
        let credentials = XtreamLinkDetector.detect(
            urlString: "example.com:8080/get.php?username=u&password=p&type=m3u_plus"
        )
        #expect(credentials == XtreamLinkDetector.Credentials(
            serverURL: "http://example.com:8080", username: "u", password: "p"
        ))
    }

    @Test
    func anAccountLinkBehindARepeatedSchemeIsStillRead() {
        let credentials = XtreamLinkDetector.detect(
            urlString: "http://https://example.com/get.php?username=u&password=p"
        )
        #expect(credentials?.serverURL == "https://example.com")
    }

    /// What the form stores for a detected link is already in normal form, so a
    /// second pass (at save time) leaves it alone.
    @Test
    func aDetectedServerAddressIsAlreadyNormal() throws {
        let links = [
            "http://example.com/get.php?username=u&password=p",
            "https://panel.example.com:8443/panel/get.php?username=u&password=p",
            "example.com:8080/player_api.php?username=u&password=p",
        ]
        for link in links {
            let detected = try #require(XtreamLinkDetector.detect(urlString: link))
            #expect(normalized(detected.serverURL) == detected.serverURL)
        }
    }
}
