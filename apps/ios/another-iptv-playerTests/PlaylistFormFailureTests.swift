import Foundation
import Testing
@testable import another_iptv_player

/// `PlaylistFormFailure.describing`: the text and the field an add / edit form
/// shows for each way a save can fail.
@MainActor
@Suite("Playlist form failure")
struct PlaylistFormFailureTests {

    private func failure(_ error: Error) -> PlaylistFormFailure {
        PlaylistFormFailure.describing(error)
    }

    /// The Foundation text the old alerts showed behind a prefix.
    private func rawText(_ code: URLError.Code) -> String {
        URLError(code).localizedDescription
    }

    // MARK: - Xtream

    @Test
    func wrongCredentialsPointAtTheCredentials() {
        let shown = failure(XtreamError.unauthenticated)
        #expect(shown.title == L("onboarding.error.title.sign_in"))
        #expect(shown.message == L("misc.xtream.auth_error"))
        #expect(shown.field == .credentials)
    }

    @Test
    func anAddressThatIsNotAPanelPointsAtTheAddress() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not JSON"))
        let shown = failure(XtreamError.decodingError(decoding))
        #expect(shown.title == L("onboarding.error.title.connection"))
        #expect(shown.message == L("onboarding.error.not_xtream"))
        #expect(shown.field == .address)
    }

    @Test
    func anHTTPErrorKeepsItsCodeInOneSentence() {
        let shown = failure(XtreamError.serverError("HTTP 403"))
        #expect(shown.message == L("onboarding.error.http", "HTTP 403"))
        #expect(shown.field == .address)

        let m3u = failure(M3UServiceError.serverError(884))
        #expect(m3u.message == L("onboarding.error.http", "HTTP 884"))
        #expect(m3u.field == .address)
    }

    @Test
    func anInvalidAddressPointsAtTheAddress() {
        #expect(failure(XtreamError.invalidURL("x")).message == L("onboarding.error.invalid_address"))
        #expect(failure(M3UServiceError.invalidURL("x")).message == L("onboarding.error.invalid_address"))
        #expect(failure(M3UServiceError.invalidURL("x")).field == .address)
    }

    // MARK: - Connection

    @Test(arguments: [URLError.Code.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost])
    func anUnreachableHostPointsAtTheAddress(code: URLError.Code) {
        for error in [XtreamError.networkError(URLError(code)) as Error, M3UServiceError.networkError(URLError(code))] {
            let shown = failure(error)
            #expect(shown.title == L("onboarding.error.title.connection"))
            #expect(shown.message == L("onboarding.error.unreachable"))
            #expect(shown.field == .address)
            #expect(!shown.message.contains(rawText(code)))
        }
    }

    @Test
    func aTimeoutHasItsOwnSentence() {
        let shown = failure(XtreamError.networkError(URLError(.timedOut)))
        #expect(shown.message == L("onboarding.error.timeout"))
        #expect(shown.field == .address)
    }

    /// Nothing in the form is wrong when the device is offline, so no field is focused.
    @Test(arguments: [URLError.Code.notConnectedToInternet, .dataNotAllowed])
    func beingOfflineBlamesNoField(code: URLError.Code) {
        let shown = failure(M3UServiceError.networkError(URLError(code)))
        #expect(shown.title == L("onboarding.error.title.connection"))
        #expect(shown.message == L("onboarding.error.offline"))
        #expect(shown.field == nil)
    }

    @Test
    func anyOtherNetworkErrorGetsTheGeneralSentence() {
        let shown = failure(XtreamError.networkError(URLError(.networkConnectionLost)))
        #expect(shown.message == L("onboarding.error.connection"))
        #expect(shown.field == .address)

        // Not a URLError at all.
        let other = failure(XtreamError.networkError(CocoaError(.fileNoSuchFile)))
        #expect(other.message == L("onboarding.error.connection"))
    }

    // MARK: - M3U content, files and the rest

    @Test
    func aLinkThatIsNotAPlaylistPointsAtTheAddress() {
        let shown = failure(M3UParserError.noChannelsFound)
        #expect(shown.title == L("loading.error.title"))
        #expect(shown.message == L("parser.error.no_channels"))
        #expect(shown.field == .address)
    }

    @Test
    func aFileThatCannotBeReadBlamesNoField() {
        let shown = failure(M3UServiceError.encodingUnsupported)
        #expect(shown.title == L("loading.error.title"))
        #expect(shown.message == L("net.error.encoding_unsupported"))
        #expect(shown.field == nil)
    }

    @Test
    func anUnknownErrorUsesTheAppsLocalizedDescription() {
        let error = CocoaError(.fileWriteOutOfSpace)
        let shown = failure(error)
        #expect(shown.title == L("onboarding.error.title.save"))
        #expect(shown.message == L("kit.error.generic"))
        #expect(shown.field == nil)
    }
}
