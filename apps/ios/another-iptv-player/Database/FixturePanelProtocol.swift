import Foundation

/// Rich/scale fixtures have deterministic account data and deterministic retry
/// errors. Demo/snapshot traffic and all non-fixture hosts keep the real transport.
nonisolated final class FixturePanelProtocol: URLProtocol {
    static var isEnabled: Bool {
        let args = CommandLine.arguments
        guard args.contains("-UITests") else { return false }
        if let index = args.firstIndex(of: "-UITestsFixture"), args.indices.contains(index + 1), args[index + 1] == "rich" { return true }
        return args.contains("-UITestsCatalogScale")
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
        let isAccount = url.path.hasSuffix("player_api.php") && action == nil
        let body = isAccount
            ? #"{"user_info":{"username":"demo","password":"demo","auth":1,"status":"Active","exp_date":"2051222400","is_trial":"0","active_cons":"0","max_connections":"2","created_at":"1700000000","allowed_output_formats":["m3u8","ts"]},"server_info":{"url":"example.com","port":"80","https_port":"443","server_protocol":"https","timezone":"UTC","timestamp_now":1790980000,"time_now":"2026-10-03 00:00:00"}}"#
            : #"{"error":"Fixture endpoint unavailable"}"#
        let data = Data(body.utf8)
        let response = HTTPURLResponse(url: url, statusCode: isAccount ? 200 : 503, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
