import Foundation

enum EPGError: LocalizedError {
    case noSource
    case invalidURL(String)
    case network(Error)
    case server(Int)
    case tooLarge
    case decompression
    case parse(String)
    case emptyGuide
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noSource: return L("epg.error.no_source")
        case .invalidURL(let url): return L("epg.error.invalid_url", url)
        case .network(let err): return L("epg.error.network", err.localizedDescription)
        case .server(let code): return L(plainDigits: "epg.error.server", code)
        case .tooLarge: return L("epg.error.too_large")
        case .decompression: return L("epg.error.decompress")
        case .parse(let detail): return L("epg.error.parse", detail)
        case .emptyGuide: return L("epg.error.empty_guide")
        case .cancelled: return L("epg.error.cancelled")
        }
    }
}

/// Strips credentials from URLs before they reach logs or user-facing error text.
///
/// Xtream URLs carry credentials two ways — as query items (`?username=&password=`,
/// e.g. xmltv.php) and as path segments (`/timeshift/USER/PASS/...`, e.g. path-style
/// timeshift). `XtreamAPIClient.redacted` only handles the query form, so this
/// redactor additionally masks the literal credential substrings when they are known.
enum EPGURLRedactor {
    static func redact(_ urlString: String, username: String? = nil, password: String? = nil) -> String {
        var result = urlString

        // Query-item form.
        if var comps = URLComponents(string: urlString), comps.queryItems != nil {
            comps.queryItems = comps.queryItems?.map { item in
                if item.name.lowercased() == "username" || item.name.lowercased() == "password" {
                    return URLQueryItem(name: item.name, value: "***")
                }
                return item
            }
            result = comps.string ?? result
        }

        // Path-segment form: replace the literal credential substrings.
        for cred in [username, password] {
            guard let cred = cred?.trimmingCharacters(in: .whitespacesAndNewlines), cred.count >= 2 else { continue }
            result = result.replacingOccurrences(of: cred, with: "***")
            if let encoded = cred.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), encoded != cred {
                result = result.replacingOccurrences(of: encoded, with: "***")
            }
        }
        return result
    }
}
