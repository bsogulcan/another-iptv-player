import Foundation
import Testing
@testable import another_iptv_player

/// Answers every request of a session from a table keyed by host, so tests running
/// side by side do not see each other's responses. An unknown host fails like a
/// connection error.
nonisolated final class XtreamStubURLProtocol: URLProtocol {
    struct Answer {
        let status: Int
        let body: Data
        var headers: [String: String] = [:]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var recordedRequests: [String: [URLRequest]] = [:]

    static func requests(forHost host: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests[host.lowercased()] ?? []
    }

    static func setAnswer(_ answer: Answer?, forHost host: String) {
        lock.lock()
        defer { lock.unlock() }
        answers[host.lowercased()] = answer
        recordedRequests[host.lowercased()] = []
    }

    private static func answer(forHost host: String) -> Answer? {
        lock.lock()
        defer { lock.unlock() }
        return answers[host.lowercased()]
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [XtreamStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let host = request.url?.host {
            Self.lock.lock()
            Self.recordedRequests[host.lowercased(), default: []].append(request)
            Self.lock.unlock()
        }
        guard let url = request.url,
              let host = url.host,
              let answer = Self.answer(forHost: host),
              let response = HTTPURLResponse(
                  url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"].merging(answer.headers) { _, new in new }
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The request and decode path of `XtreamAPIClient` against canned HTTP answers.
@MainActor
@Suite("Xtream client decoding")
struct XtreamAPIClientDecodingTests {
    /// A client whose host is unique to the calling test.
    private func makeClient(status: Int = 200, body: String?) -> XtreamAPIClient {
        let host = "panel-\(UUID().uuidString.lowercased()).invalid"
        if let body {
            XtreamStubURLProtocol.setAnswer(.init(status: status, body: Data(body.utf8)), forHost: host)
        }
        let playlist = Playlist(name: "Test", serverURL: "https://\(host)", username: "user", password: "pass")
        return XtreamAPIClient(playlist: playlist, urlSession: XtreamStubURLProtocol.makeSession())
    }

    @Test
    func listEndpointsDecodeLenientlyTypedFields() async throws {
        let client = makeClient(body: #"""
        [
          {"stream_id": 1, "name": "First", "category_id": 7, "added": 1700000000, "is_adult": "0"},
          {"stream_id": "2", "name": "Second", "category_id": "8", "container_extension": "mkv"}
        ]
        """#)

        let movies = try await client.getVODStreams()

        #expect(movies.map(\.id) == [1, 2])
        #expect(movies.map(\.name) == ["First", "Second"])
        #expect(movies.map(\.categoryId) == ["7", "8"])
        #expect(movies.first?.added == "1700000000")
        #expect(movies.first?.isAdult == 0)
        #expect(movies.last?.containerExtension == "mkv")
    }

    @Test
    func categoriesAndSeriesComeBackInPanelOrder() async throws {
        let categories = try await makeClient(body: #"""
        [{"category_id": "3", "category_name": "C", "parent_id": 0}, {"category_id": "1", "category_name": "A"}]
        """#).getLiveCategories()
        let series = try await makeClient(body: #"""
        [{"series_id": 9, "name": "Nine", "last_modified": "1700000500"}, {"series_id": 4, "name": "Four"}]
        """#).getSeries()

        #expect(categories.map(\.id) == ["3", "1"])
        #expect(categories.first?.parentId == 0)
        #expect(series.map(\.id) == [9, 4])
        #expect(series.first?.lastModified == "1700000500")
    }

    @Test
    func detailEndpointsDecode() async throws {
        let client = makeClient(body: #"""
        {"info": {"name": "Film", "duration_secs": "5400", "backdrop_path": ["a", "b"]},
         "movie_data": {"stream_id": 7, "container_extension": "mp4"}}
        """#)

        let info = try await client.getVODInfo(vodId: 7)

        #expect(info.info?.name == "Film")
        #expect(info.info?.durationSecs == 5400)
        #expect(info.info?.backdropPath == ["a", "b"])
        #expect(info.movieData?.streamId == 7)
    }

    @Test
    func aBodyThatIsNotJSONIsADecodingError() async {
        let client = makeClient(body: "<html>Service unavailable</html>")

        do {
            _ = try await client.getVODStreams()
            Issue.record("expected the request to fail")
        } catch XtreamError.decodingError {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func anHTTPErrorStatusIsAServerError() async {
        let client = makeClient(status: 503, body: "[]")

        do {
            _ = try await client.getLiveStreams()
            Issue.record("expected the request to fail")
        } catch XtreamError.serverError(let status) {
            #expect(status == "HTTP 503")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func aTransportFailureIsANetworkError() async {
        let client = makeClient(body: nil)

        do {
            _ = try await client.getSeriesCategories()
            Issue.record("expected the request to fail")
        } catch XtreamError.networkError {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func verifyRejectsAnAccountThePanelDoesNotAuthorise() async {
        let client = makeClient(body: #"{"user_info": {"auth": 0}}"#)

        do {
            _ = try await client.verify()
            Issue.record("expected the request to fail")
        } catch XtreamError.unauthenticated {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
