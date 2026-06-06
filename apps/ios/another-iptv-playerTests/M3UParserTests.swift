import Foundation
import Testing
@testable import another_iptv_player

@Suite("M3UParser")
struct M3UParserTests {

    // MARK: - Errors

    @Test
    func emptyStringThrows() {
        #expect(throws: M3UParserError.empty) {
            _ = try M3UParser.parse("")
        }
    }

    @Test
    func whitespaceOnlyThrows() {
        #expect(throws: M3UParserError.empty) {
            _ = try M3UParser.parse("   \n\t  \n")
        }
    }

    @Test
    func headerWithoutChannelsThrows() {
        #expect(throws: M3UParserError.noChannelsFound) {
            _ = try M3UParser.parse("#EXTM3U\n# just a comment\n")
        }
    }

    // MARK: - Basics

    @Test
    func basicSingleChannel() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channel One
        http://example.com/stream1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.count == 1)
        #expect(result.channels[0].name == "Channel One")
        #expect(result.channels[0].url == "http://example.com/stream1")
    }

    @Test
    func multipleChannels() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,A
        http://a.com/1
        #EXTINF:-1,B
        http://b.com/2
        #EXTINF:-1,C
        http://c.com/3
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.count == 3)
        #expect(result.channels.map(\.name) == ["A", "B", "C"])
    }

    // MARK: - BOM & newline normalization

    @Test
    func stripsUTF8BOM() throws {
        let m3u = "\u{FEFF}#EXTM3U\n#EXTINF:-1,X\nhttp://x.com\n"
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.count == 1)
        #expect(result.channels[0].name == "X")
    }

    @Test(arguments: ["\r\n", "\r", "\u{2028}", "\u{2029}"])
    func normalizesNewlines(separator: String) throws {
        let m3u = ["#EXTM3U", "#EXTINF:-1,X", "http://x.com"].joined(separator: separator)
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.count == 1)
        #expect(result.channels[0].url == "http://x.com")
    }

    // MARK: - EPG URL

    @Test
    func extractsEpgURLFromHeader() throws {
        let m3u = """
        #EXTM3U x-tvg-url="https://epg.example.com/epg.xml"
        #EXTINF:-1,X
        http://x.com
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.epgURL == "https://epg.example.com/epg.xml")
    }

    @Test
    func extractsEpgURLFromUrlTvgAlias() throws {
        let m3u = """
        #EXTM3U url-tvg="https://alt.example.com/guide.xml"
        #EXTINF:-1,X
        http://x.com
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.epgURL == "https://alt.example.com/guide.xml")
    }

    // MARK: - Attributes

    @Test
    func parsesAllStandardAttributes() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="ch.1" tvg-name="One" tvg-logo="http://l.com/1.png" tvg-country="TR" group-title="News",Channel One
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        let ch = try #require(result.channels.first)
        #expect(ch.tvgId == "ch.1")
        #expect(ch.tvgName == "One")
        #expect(ch.tvgLogo == "http://l.com/1.png")
        #expect(ch.tvgCountry == "TR")
        #expect(ch.groupTitle == "News")
    }

    @Test
    func handlesCommasInsideQuotedAttributes() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-logo="http://cdn.com/img.png?a=1,b=2" group-title="Sports",Channel
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        let ch = try #require(result.channels.first)
        #expect(ch.tvgLogo == "http://cdn.com/img.png?a=1,b=2")
        #expect(ch.groupTitle == "Sports")
        #expect(ch.name == "Channel")
    }

    @Test
    func userAgentInExtinfAttribute() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 user-agent="MyPlayer/1.0",Channel
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.userAgent == "MyPlayer/1.0")
    }

    // MARK: - EXTVLCOPT / KODIPROP

    @Test
    func extvlcoptUserAgentAppliesToChannel() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channel
        #EXTVLCOPT:http-user-agent=VLCPlayer/3.0
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.userAgent == "VLCPlayer/3.0")
    }

    @Test
    func kodiPropStreamHeadersUserAgent() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channel
        #KODIPROP:inputstream.adaptive.stream_headers=User-Agent=KodiUA/2.0&Referer=foo
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.userAgent == "KodiUA/2.0")
    }

    @Test
    func kodiPropAltPrefix() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channel
        #EXT-X-KODI-PROP:inputstream.adaptive.stream_headers=User-Agent=AltUA
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.userAgent == "AltUA")
    }

    @Test
    func extinfUserAgentTakesPrecedenceOverExtvlcopt() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 user-agent="ExtinfUA",Channel
        #EXTVLCOPT:http-user-agent=VLCPlayer/3.0
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.userAgent == "ExtinfUA")
    }

    // MARK: - EXTGRP

    @Test
    func extgrpOverridesEmptyGroupTitle() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channel
        #EXTGRP:Movies
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.groupTitle == "Movies")
    }

    @Test
    func extgrpDoesNotOverwriteAttributeGroupTitle() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 group-title="Sports",Channel
        #EXTGRP:Movies
        http://example.com/1
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.groupTitle == "Sports")
    }

    // MARK: - Embedded URL in EXTINF

    @Test
    func embeddedHTTPSURLInExtinfLine() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channelhttps://example.com/stream
        """
        let result = try M3UParser.parse(m3u)
        let ch = try #require(result.channels.first)
        #expect(ch.name == "Channel")
        #expect(ch.url == "https://example.com/stream")
    }

    @Test
    func embeddedRTMPURLInExtinfLine() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channelrtmp://example.com/live
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.url == "rtmp://example.com/live")
    }

    // MARK: - Name fallback

    @Test
    func nameFallbackUsesTvgNameWhenDisplayEmpty() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-name="From TVG",
        http://example.com/file.ts
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.name == "From TVG")
    }

    @Test
    func nameFallbackUsesLastPathComponent() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,
        http://example.com/folder/movie.mp4
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.name == "movie.mp4")
    }

    @Test
    func nameFallbackUsesHostWhenPathEmpty() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,
        http://example.com
        """
        let result = try M3UParser.parse(m3u)
        #expect(result.channels.first?.name == "example.com")
    }

    // MARK: - Continuation join (odd-quote)

    @Test
    func joinsExtinfContinuationWhenAttributeContainsNewline() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-name="NL - Venom - 2018
        " tvg-logo="http://l/x.png" group-title="Movies",NL - Venom - 2018
        http://server/movie.mp4
        """
        let result = try M3UParser.parse(m3u)
        let ch = try #require(result.channels.first)
        #expect(ch.url == "http://server/movie.mp4")
        #expect(ch.groupTitle == "Movies")
        #expect(ch.tvgLogo == "http://l/x.png")
    }

    // MARK: - Diagnostics

    @Test
    func diagnosticsCountLines() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,A
        http://a.com
        #EXTINF:-1,B
        #EXTGRP:News
        http://b.com
        """
        let (_, diag) = try M3UParser.parseWithDiagnostics(m3u)
        #expect(diag.extm3uLines == 1)
        #expect(diag.extinfLines == 2)
        #expect(diag.uriLines == 2)
        #expect(diag.extgrpLines == 1)
        #expect(diag.channelCount == 2)
    }

    @Test
    func diagnosticsCountsOrphanURI() throws {
        let m3u = """
        #EXTM3U
        http://orphan.com
        #EXTINF:-1,Real
        http://real.com
        """
        let (_, diag) = try M3UParser.parseWithDiagnostics(m3u)
        #expect(diag.orphanURIs == 1)
        #expect(diag.channelCount == 1)
    }

    // MARK: - Async API

    @Test
    func asyncParseMatchesSync() async throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,A
        http://a.com
        """
        let sync = try M3UParser.parse(m3u)
        let async = try await M3UParser.parseAsync(m3u)
        #expect(sync == async)
    }

    // MARK: - sanitizedURL

    @Test
    func sanitizedURLAcceptsValidURL() {
        #expect(M3UParser.sanitizedURL(from: "http://example.com/path") != nil)
    }

    @Test
    func sanitizedURLReturnsNilForEmpty() {
        #expect(M3UParser.sanitizedURL(from: "") == nil)
        #expect(M3UParser.sanitizedURL(from: "   ") == nil)
    }

    @Test
    func sanitizedURLEncodesSpaces() {
        let url = M3UParser.sanitizedURL(from: "http://example.com/with space")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("%20") == true)
    }

    @Test
    func sanitizedURLTrimsWhitespace() {
        #expect(M3UParser.sanitizedURL(from: "  http://example.com  ")?.absoluteString == "http://example.com")
    }
}
