import Foundation
import Testing
@testable import another_iptv_player

@Suite("XtreamLinkDetector")
struct XtreamLinkDetectorTests {

    // MARK: - Matches

    @Test
    func standardGetPhpLink() {
        let creds = XtreamLinkDetector.detect(
            urlString: "http://example.com/get.php?username=user&password=pass&type=m3u_plus&output=ts"
        )
        #expect(creds == XtreamLinkDetector.Credentials(
            serverURL: "http://example.com", username: "user", password: "pass"
        ))
    }

    @Test
    func httpsWithPort() {
        let creds = XtreamLinkDetector.detect(
            urlString: "https://panel.example.com:8443/get.php?username=u&password=p"
        )
        #expect(creds == XtreamLinkDetector.Credentials(
            serverURL: "https://panel.example.com:8443", username: "u", password: "p"
        ))
    }

    @Test
    func pathPrefixIsKept() {
        let creds = XtreamLinkDetector.detect(
            urlString: "http://example.com/panel/get.php?username=u&password=p"
        )
        #expect(creds?.serverURL == "http://example.com/panel")
    }

    @Test
    func surroundingWhitespaceIsTrimmed() {
        let creds = XtreamLinkDetector.detect(
            urlString: "  http://example.com/get.php?username=u&password=p \n"
        )
        #expect(creds != nil)
    }

    @Test
    func uppercasePathAndParamNames() {
        let creds = XtreamLinkDetector.detect(
            urlString: "http://example.com/GET.PHP?USERNAME=u&PASSWORD=p"
        )
        #expect(creds == XtreamLinkDetector.Credentials(
            serverURL: "http://example.com", username: "u", password: "p"
        ))
    }

    @Test
    func percentEncodedCredentialsAreDecoded() {
        let creds = XtreamLinkDetector.detect(
            urlString: "http://example.com/get.php?username=a%40b&password=p%26q"
        )
        #expect(creds?.username == "a@b")
        #expect(creds?.password == "p&q")
    }

    // MARK: - Non-matches

    @Test
    func plainM3UURLDoesNotMatch() {
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/playlist.m3u8") == nil)
    }

    @Test
    func missingPasswordDoesNotMatch() {
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/get.php?username=u") == nil)
    }

    @Test
    func emptyCredentialsDoNotMatch() {
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/get.php?username=&password=") == nil)
    }

    @Test
    func getPhpAsQueryValueDoesNotMatch() {
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/list.m3u?src=get.php&username=u&password=p") == nil)
    }

    @Test
    func getPhpPrefixedFileDoesNotMatch() {
        // hasSuffix("/get.php") must not match e.g. "forget.php".
        #expect(XtreamLinkDetector.detect(urlString: "http://example.com/forget.php?username=u&password=p") == nil)
    }

    @Test
    func nonHTTPSchemeDoesNotMatch() {
        #expect(XtreamLinkDetector.detect(urlString: "file:///get.php?username=u&password=p") == nil)
        #expect(XtreamLinkDetector.detect(urlString: "rtsp://example.com/get.php?username=u&password=p") == nil)
    }

    @Test
    func garbageDoesNotMatch() {
        #expect(XtreamLinkDetector.detect(urlString: "") == nil)
        #expect(XtreamLinkDetector.detect(urlString: "not a url") == nil)
    }
}
