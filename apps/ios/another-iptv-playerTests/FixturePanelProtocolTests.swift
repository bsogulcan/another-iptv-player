import Foundation
import Testing
@testable import another_iptv_player

@Suite("Deterministic fixture panel")
struct FixturePanelProtocolTests {
    @Test func accountAndFailureUseTheRealClientDecoder() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixturePanelProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = XtreamAPIClient(playlist: Playlist(name: "Fixture", serverURL: "https://example.com"), urlSession: session)
        let account = try await client.verify()
        #expect(account.userInfo?.auth == 1)
        #expect(account.userInfo?.maxConnections == "2")
        do {
            _ = try await client.getSeriesInfo(seriesId: 123)
            Issue.record("Missing fixture endpoint must fail deterministically")
        } catch let error as XtreamError {
            guard case .serverError(let message) = error else { Issue.record("Unexpected fixture failure: \(error)"); return }
            #expect(message == "HTTP 503")
        }
    }
}
