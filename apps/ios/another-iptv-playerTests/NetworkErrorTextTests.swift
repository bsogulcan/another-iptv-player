import Foundation
import Testing
@testable import another_iptv_player

/// `NetworkErrorText.describe`: every cause it knows has a sentence of the app's own,
/// and no text of the system reaches the result.
///
/// Expected values are looked up through `L()`, so the tests hold in whatever
/// language the test host runs.
@Suite("Network error text")
struct NetworkErrorTextTests {

    private func describe(_ code: URLError.Code) -> String {
        NetworkErrorText.describe(URLError(code))
    }

    /// False when the host has no string tables and `L()` hands the key back; the
    /// checks on the wording of a sentence only make sense with the tables.
    private func isTranslated(_ key: String) -> Bool {
        L(key) != key
    }

    // MARK: URLError codes

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ])
    func noConnection(code: URLError.Code) {
        #expect(describe(code) == L("kit.error.offline"))
    }

    /// A panel that drops the connection in the middle of a response is not the
    /// user being offline.
    @Test
    func lostConnectionHasItsOwnSentence() {
        #expect(describe(.networkConnectionLost) == L("kit.error.connection_lost"))
    }

    @Test
    func timeout() {
        #expect(describe(.timedOut) == L("playback.error.timeout"))
    }

    @Test(arguments: [URLError.Code.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed])
    func unreachableServer(code: URLError.Code) {
        #expect(describe(code) == L("kit.error.unreachable"))
    }

    @Test(arguments: [
        URLError.Code.secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
        .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection,
    ])
    func insecureConnection(code: URLError.Code) {
        #expect(describe(code) == L("kit.error.insecure"))
    }

    @Test(arguments: [
        URLError.Code.badServerResponse, .cannotParseResponse, .cannotDecodeRawData,
        .cannotDecodeContentData, .zeroByteResource,
    ])
    func unreadableResponse(code: URLError.Code) {
        #expect(describe(code) == L("kit.error.unexpected_response"))
    }

    @Test
    func cancelledRequest() {
        #expect(describe(.cancelled) == L("kit.error.cancelled"))
        #expect(NetworkErrorText.describe(CancellationError()) == L("kit.error.cancelled"))
    }

    /// A code without a sentence of its own keeps its number, which is what a bug
    /// report needs.
    @Test(arguments: [URLError.Code.badURL, .httpTooManyRedirects, .resourceUnavailable, .unknown])
    func otherCodesKeepTheirNumber(code: URLError.Code) {
        #expect(describe(code) == L(plainDigits: "kit.error.connection_failed", code.rawValue))
        if isTranslated("kit.error.connection_failed") {
            #expect(describe(code).contains(String(code.rawValue)))
        }
    }

    @Test
    func anNSErrorOfTheURLDomainIsMappedLikeAURLError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(NetworkErrorText.describe(error) == L("kit.error.offline"))
    }

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .secureConnectionFailed, .badServerResponse, .cancelled, .badURL,
    ])
    func theSystemDescriptionIsNeverPartOfTheText(code: URLError.Code) {
        let error = URLError(code)
        let text = NetworkErrorText.describe(error)

        #expect(!text.isEmpty)
        #expect(!text.contains(error.localizedDescription))
    }

    // MARK: The app's wrappers

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .serverCertificateUntrusted, .cannotParseResponse, .cancelled, .badURL,
    ])
    func aWrappedErrorReadsLikeTheErrorItWraps(code: URLError.Code) {
        let cause = URLError(code)
        let expected = NetworkErrorText.describe(cause)

        #expect(NetworkErrorText.describe(XtreamError.networkError(cause)) == expected)
        #expect(NetworkErrorText.describe(M3UServiceError.networkError(cause)) == expected)
        #expect(NetworkErrorText.describe(EPGError.network(cause)) == expected)
        #expect(NetworkErrorText.describe(CatchupURLError.network(cause)) == expected)
    }

    @Test
    func wrappersAreUnwrappedThroughSeveralLayers() {
        let cause = XtreamError.networkError(URLError(.timedOut))
        #expect(NetworkErrorText.describe(EPGError.network(cause)) == L("playback.error.timeout"))
    }

    @Test
    func aResponseThatCannotBeDecodedIsAnUnexpectedResponse() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "broken"))

        #expect(NetworkErrorText.describe(decoding) == L("kit.error.unexpected_response"))
        #expect(NetworkErrorText.describe(XtreamError.decodingError(decoding)) == L("kit.error.unexpected_response"))
        #expect(!NetworkErrorText.describe(XtreamError.decodingError(decoding)).contains(decoding.localizedDescription))
    }

    /// The status code is what tells a blocked endpoint from a missing one.
    @Test
    func serverErrorsKeepTheHTTPStatus() {
        let xtream = NetworkErrorText.describe(XtreamError.serverError("HTTP 404"))
        let m3u = NetworkErrorText.describe(M3UServiceError.serverError(884))
        let guide = NetworkErrorText.describe(EPGError.server(503))

        #expect(xtream == L("misc.xtream.server_error", "HTTP 404"))
        #expect(m3u == L("net.error.server", 884))
        #expect(guide == L("epg.error.server", 503))
        if isTranslated("misc.xtream.server_error") {
            #expect(xtream.contains("404"))
            #expect(m3u.contains("884"))
            #expect(guide.contains("503"))
        }
    }

    @Test
    func casesWithASentenceOfTheirOwnKeepIt() {
        #expect(NetworkErrorText.describe(XtreamError.unauthenticated) == L("misc.xtream.auth_error"))
        #expect(NetworkErrorText.describe(XtreamError.invalidURL("http://host")) == L("misc.xtream.invalid_url", "http://host"))
        #expect(NetworkErrorText.describe(M3UServiceError.encodingUnsupported) == L("net.error.encoding_unsupported"))
        #expect(NetworkErrorText.describe(EPGError.tooLarge) == L("epg.error.too_large"))
        #expect(NetworkErrorText.describe(EPGError.cancelled) == L("epg.error.cancelled"))
        #expect(NetworkErrorText.describe(CatchupURLError.notAvailable) == L("epg.catchup.error.unavailable"))
    }

    @Test
    func aFileThatCannotBeReadDoesNotQuoteTheSystem() {
        let cause = CocoaError(.fileReadNoPermission)
        let text = NetworkErrorText.describe(M3UServiceError.fileReadError(cause))

        #expect(text == L("kit.error.file_unreadable"))
        #expect(!text.contains(cause.localizedDescription))
    }

    // MARK: Everything else

    @Test
    func anUnknownErrorGetsTheGenericSentence() {
        let error = NSError(domain: "test.domain", code: 7, userInfo: [NSLocalizedDescriptionKey: "raw text"])
        let text = NetworkErrorText.describe(error)

        #expect(text == L("kit.error.generic"))
        #expect(!text.contains("raw text"))
    }

    private nonisolated struct Described: LocalizedError {
        var errorDescription: String? { "  described by the app  " }
    }

    private nonisolated struct Undescribed: LocalizedError {
        var errorDescription: String? { nil }
    }

    @Test
    func otherErrorTypesOfTheAppDescribeThemselves() {
        #expect(NetworkErrorText.describe(Described()) == "described by the app")
        #expect(NetworkErrorText.describe(Undescribed()) == L("kit.error.generic"))
    }
}
