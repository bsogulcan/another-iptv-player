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
        case .serverError(let status): return L("misc.xtream.server_error", status)
        }
    }
}

class XtreamAPIClient {
    private let playlist: Playlist
    private let urlSession: URLSession
    
    init(playlist: Playlist, urlSession: URLSession = .shared) {
        self.playlist = playlist
        self.urlSession = urlSession
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
    
    private func fetch<T: Decodable>(action: String? = nil, queryItems: [URLQueryItem] = []) async throws -> T {
        var comps = getBaseURLComponents()
        
        if let action = action {
            comps.queryItems?.append(URLQueryItem(name: "action", value: action))
        }
        
        if !queryItems.isEmpty {
            comps.queryItems?.append(contentsOf: queryItems)
        }
        
        guard let url = comps.url else {
            throw XtreamError.invalidURL(comps.string ?? "Bilinmeyen URL")
        }

        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            // Debug: Log series info for structure comparison
            if url.absoluteString.contains("action=get_series_info") {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("--- [DEBUG] SERIES INFO RAW RESPONSE START ---")
                    print("URL: \(url.absoluteString)")
                    print("JSON: \(jsonString)")
                    print("--- [DEBUG] SERIES INFO RAW RESPONSE END ---")
                }
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                 throw XtreamError.serverError("HTTP \(httpResponse.statusCode)")
            }
            
            // Catch JSON decoding errors safely
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch(let error) {
                print("--- DECODING ERROR ---")
                print("URL: \(url)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("RAW DATA: \(jsonString)")
                }
                print("ERROR: \(error)")
                print("--- END ERROR ---")
                throw XtreamError.decodingError(error)
            }
        } catch let error as XtreamError {
            throw error
        } catch {
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
        let failable: [FailableDecodable<XtreamCategory>] = try await fetch(action: "get_live_categories")
        return failable.compactMap { $0.base }
    }
    
    func getVODCategories() async throws -> [XtreamCategory] {
        let failable: [FailableDecodable<XtreamCategory>] = try await fetch(action: "get_vod_categories")
        return failable.compactMap { $0.base }
    }
    
    func getSeriesCategories() async throws -> [XtreamCategory] {
        let failable: [FailableDecodable<XtreamCategory>] = try await fetch(action: "get_series_categories")
        return failable.compactMap { $0.base }
    }
    
    func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamLiveStream] {
        var queryItems: [URLQueryItem] = []
        if let catId = categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: catId))
        }
        let failable: [FailableDecodable<XtreamLiveStream>] = try await fetch(action: "get_live_streams", queryItems: queryItems)
        return failable.compactMap { $0.base }
    }
    
    func getVODStreams(categoryId: String? = nil) async throws -> [XtreamVODStream] {
        var queryItems: [URLQueryItem] = []
        if let catId = categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: catId))
        }
        let failable: [FailableDecodable<XtreamVODStream>] = try await fetch(action: "get_vod_streams", queryItems: queryItems)
        return failable.compactMap { $0.base }
    }
    
    func getSeries(categoryId: String? = nil) async throws -> [XtreamSeries] {
        var queryItems: [URLQueryItem] = []
        if let catId = categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: catId))
        }
        let failable: [FailableDecodable<XtreamSeries>] = try await fetch(action: "get_series", queryItems: queryItems)
        return failable.compactMap { $0.base }
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

}
