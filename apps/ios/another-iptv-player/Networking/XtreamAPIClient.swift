import Foundation

enum XtreamError: LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case unauthenticated
    case decodingError(Error)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return L("misc.xtream.invalid_url", url)
        case .networkError(let error): return L("net.error.network", error.localizedDescription)
        case .unauthenticated: return L("misc.xtream.auth_error")
        case .decodingError(let error): return L("misc.xtream.decode_error", error.localizedDescription)
        case .serverError(let status): return L(plainDigits: "misc.xtream.server_error", status)
        }
    }
}

/// IPTV panel/playlist istekleri için sınırlı zaman aşımlı oturum. `URLSession.shared`
/// 60 sn idle + 7 GÜN resource zaman aşımıyla geliyor — yanıt vermeyen bir panel,
/// ekleme/yenileme akışını dakikalarca iptal edilemez şekilde asılı bırakıyordu.
/// `nonisolated`: URLSession is Sendable; used from background contexts (EPG download).
nonisolated enum PanelURLSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 300
        if FixturePanelProtocol.isEnabled {
            config.protocolClasses = [FixturePanelProtocol.self] + (config.protocolClasses ?? [])
        }
        return URLSession(configuration: config)
    }()
}

class XtreamAPIClient {
    private let playlist: Playlist
    private let urlSession: URLSession

    init(playlist: Playlist, urlSession: URLSession = PanelURLSession.shared) {
        self.playlist = playlist
        self.urlSession = urlSession
    }

    /// Log ve hata metinlerine gidecek URL'lerde kimlik bilgisini maskeler — panel URL'leri
    /// username/password taşır ve bunlar alert ekran görüntüleriyle/loglarla sızabilir.
    private static func redacted(_ urlString: String) -> String {
        guard var comps = URLComponents(string: urlString) else { return "<invalid-url>" }
        comps.queryItems = comps.queryItems?.map { item in
            if item.name == "username" || item.name == "password" {
                return URLQueryItem(name: item.name, value: "***")
            }
            return item
        }
        return comps.string ?? "<invalid-url>"
    }
    
    // Auto-formatting the base URL
    private func getBaseURLComponents() -> URLComponents {
        var baseString = playlist.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !baseString.lowercased().hasPrefix("http://") && !baseString.lowercased().hasPrefix("https://") {
            baseString = "http://\(baseString)"
        }
        
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        
        if !baseString.lowercased().hasSuffix("player_api.php") {
             baseString += "/player_api.php"
        }
        
        // Remove spaces inside URL just in case
        baseString = baseString.replacingOccurrences(of: " ", with: "")
        
        var comps = URLComponents(string: baseString) ?? URLComponents()
        
        comps.queryItems = [
            URLQueryItem(name: "username", value: playlist.username.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "password", value: playlist.password.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        
        return comps
    }
    
    /// Single-object endpoints (auth, movie and series details, per-channel EPG tables).
    // final: a subclass in another file (the add-playlist progress client) otherwise
    // references these file-private helpers from its vtable, which does not link.
    private final func fetch<T: Decodable & Sendable>(action: String? = nil, queryItems: [URLQueryItem] = []) async throws -> T {
        let (data, url) = try await load(action: action, queryItems: queryItems)
        return try await Self.decodeDetached(data, from: url, secrets: [playlist.username, playlist.password]) { try JSONDecoder().decode(T.self, from: $0) }
    }

    /// List endpoints. Elements are decoded one by one so a single malformed entry
    /// cannot fail the whole catalog; dropping the failures happens in the same
    /// detached pass as the decode.
    private final func fetchList<Item: Decodable & Sendable>(action: String, queryItems: [URLQueryItem] = []) async throws -> [Item] {
        let (data, url) = try await load(action: action, queryItems: queryItems)
        let secrets = [playlist.username, playlist.password]
        return try await Self.decodeDetached(data, from: url, secrets: secrets) {
            let entries = try JSONDecoder().decode([FailableDecodable<Item>].self, from: $0)
            let failures = entries.enumerated().filter { $0.element.base == nil }
            if !failures.isEmpty {
                Log.error("API", "\(action): skipped \(failures.count)/\(entries.count) entries")
                for entry in failures.prefix(5) {
                    var reason = entry.element.failure ?? "unknown"
                    for secret in secrets where !secret.isEmpty { reason = reason.replacingOccurrences(of: secret, with: "<credential>") }
                    Log.error("APIDecode", "\(action) index=\(entry.offset): \(reason)")
                }
                APIDiagnostics.recordFailedItems(data, indices: failures.prefix(5).map(\.offset), action: action, secrets: secrets)
            }
            return entries.compactMap(\.base)
        }
    }

    /// This class is main-actor isolated and a full movie or series list is tens of
    /// megabytes of JSON, so decoding here would freeze the UI for as long as it takes.
    /// A detached task does not inherit cancellation: a cancelled refresh finishes its
    /// decode and the caller drops the result.
    private static func decodeDetached<T: Sendable>(
        _ data: Data, from url: URL, secrets: [String], _ decode: @escaping @Sendable (Data) throws -> T
    ) async throws -> T {
        let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value ?? "authentication"
        return try await Task.detached(priority: .userInitiated) {
            do { return try decode(data) }
            catch {
                var description = String(describing: error)
                for secret in secrets where !secret.isEmpty { description = description.replacingOccurrences(of: secret, with: "<credential>") }
                Log.error("APIDecode", "\(action): \(SupportReport.sanitized(description))")
                APIDiagnostics.record(data, action: action, context: "decode failed", secrets: secrets)
                throw XtreamError.decodingError(error)
            }
        }.value
    }

    /// Builds the request, runs it and returns the raw body once the status is 2xx.
    private func load(action: String?, queryItems: [URLQueryItem]) async throws -> (data: Data, url: URL) {
        var comps = getBaseURLComponents()
        
        if let action = action {
            comps.queryItems?.append(URLQueryItem(name: "action", value: action))
        }
        
        if !queryItems.isEmpty {
            comps.queryItems?.append(contentsOf: queryItems)
        }
        
        // '+' RFC 3986'da query'de geçerli olduğundan URLComponents kodlamaz, ama PHP
        // tabanlı Xtream panelleri $_GET'te '+'yı boşluğa çevirir — 'ab+12' şifresi
        // 'ab 12' olarak ulaşır ve giriş sessizce reddedilirdi.
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        guard let url = comps.url else {
            // Kullanıcıya gösterilen hata metnine ham (kimlik bilgili) URL koyma.
            throw XtreamError.invalidURL(Self.redacted(comps.string ?? ""))
        }

        Log.info("API", "Request: \(action ?? "authentication")")
        do {
            let (data, response) = try await urlSession.data(from: url)

            let endpoint = action ?? "authentication"
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Log.info("API", "\(endpoint): HTTP \(status), \(data.count) bytes")
            if action == "get_series_info" || action == "get_vod_info" || !(200...299).contains(status) {
                let secrets = [playlist.username, playlist.password]
                APIDiagnostics.record(data, action: endpoint, context: "HTTP \(status)", secrets: secrets)
            }


            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                 throw XtreamError.serverError("HTTP \(httpResponse.statusCode)")
            }

            return (data, url)
        } catch let error as XtreamError {
            Log.error("API", "\(action ?? "authentication"): \(error.localizedDescription)")
            throw error
        } catch {
            Log.error("API", "\(action ?? "authentication"): network error \((error as NSError).code)")
            throw XtreamError.networkError(error)
        }
    }
    
    // MARK: - API Methods
    
    func verify() async throws -> XtreamAuthResponse {
        // Just the base query items, no action for login/verify
        let response: XtreamAuthResponse = try await fetch()
        
        // Check if userInfo is nil, that usually means unauthorized in Xtream
        if response.userInfo == nil || response.userInfo?.auth == 0 {
            throw XtreamError.unauthenticated
        }
        
        return response
    }
    
    func getLiveCategories() async throws -> [XtreamCategory] {
        try await fetchList(action: "get_live_categories")
    }
    
    func getVODCategories() async throws -> [XtreamCategory] {
        try await fetchList(action: "get_vod_categories")
    }
    
    func getSeriesCategories() async throws -> [XtreamCategory] {
        try await fetchList(action: "get_series_categories")
    }
    
    func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamLiveStream] {
        var queryItems: [URLQueryItem] = []
        if let catId = categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: catId))
        }
        return try await fetchList(action: "get_live_streams", queryItems: queryItems)
    }
    
    func getVODStreams(categoryId: String? = nil) async throws -> [XtreamVODStream] {
        var queryItems: [URLQueryItem] = []
        if let catId = categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: catId))
        }
        return try await fetchList(action: "get_vod_streams", queryItems: queryItems)
    }
    
    func getSeries(categoryId: String? = nil) async throws -> [XtreamSeries] {
        var queryItems: [URLQueryItem] = []
        if let catId = categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: catId))
        }
        return try await fetchList(action: "get_series", queryItems: queryItems)
    }
    
    func getSeriesInfo(seriesId: Int) async throws -> XtreamSeriesInfoResponse {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "series_id", value: String(seriesId)))
        return try await fetch(action: "get_series_info", queryItems: queryItems)
    }

    func getVODInfo(vodId: Int) async throws -> XtreamVODInfoResponse {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "vod_id", value: String(vodId)))
        return try await fetch(action: "get_vod_info", queryItems: queryItems)
    }

    // MARK: - EPG

    /// Short now/next EPG for one channel — used as the player overlay fallback
    /// when the XMLTV guide is missing/broken. Never call this per shelf card.
    func getShortEPG(streamId: Int, limit: Int = EPGConstants.shortEPGLimit) async throws -> XtreamEPGListingsResponse {
        let queryItems = [
            URLQueryItem(name: "stream_id", value: String(streamId)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await fetch(action: "get_short_epg", queryItems: queryItems)
    }

    /// Full per-channel EPG table (past + future, includes archive flags) — used
    /// for the channel detail list and catch-up when XMLTV lacks past programmes.
    func getSimpleDataTable(streamId: Int) async throws -> XtreamEPGListingsResponse {
        let queryItems = [URLQueryItem(name: "stream_id", value: String(streamId))]
        return try await fetch(action: "get_simple_data_table", queryItems: queryItems)
    }

}
