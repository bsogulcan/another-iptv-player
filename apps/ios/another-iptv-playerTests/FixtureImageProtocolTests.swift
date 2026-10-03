import Foundation
import Nuke
import Testing
@testable import another_iptv_player

@Suite("Offline fixture artwork")
struct FixtureImageProtocolTests {
    @Test func decodesThroughProductionPipelineWithoutNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureImageProtocol.self]
        let pipeline = IPTVRemoteImagePipeline.makePipeline(
            dataLoader: DataLoader(configuration: configuration), imageCache: nil,
            thumbnailCache: nil, hostBreaker: ImageHostBreaker())
        let image = try await pipeline.image(for: URL(string: "https://browse-fixture.invalid/seed/test/400/600")!)
        #expect(image.size.width == 400)
        #expect(image.size.height == 600)
    }

    @Test func textureIsDeterministicAndHasNontrivialPayload() throws {
        let first = try #require(FixtureImageProtocol.artwork(seed: "poster", width: 400, height: 600))
        #expect(first == FixtureImageProtocol.artwork(seed: "poster", width: 400, height: 600))
        #expect(first != FixtureImageProtocol.artwork(seed: "other", width: 400, height: 600))
        #expect(first.count > 10_000)
        #expect(!FixtureImageProtocol.canInit(with: URLRequest(url: URL(string: "https://picsum.photos/seed/test/400/600")!)))
    }
}
