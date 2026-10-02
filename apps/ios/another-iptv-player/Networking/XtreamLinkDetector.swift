import Foundation

/// Detects Xtream-panel links (`…/get.php?username=X&password=Y…`, or the same on
/// `player_api.php`) and extracts the credentials needed to connect through the
/// Xtream Codes API instead.
///
/// Many panels disable or block the `get.php` M3U download endpoint while keeping
/// `player_api.php` fully functional, so connecting via the API both sidesteps those
/// blocks and unlocks the richer experience (VOD/series metadata, EPG).
enum XtreamLinkDetector {

    struct Credentials: Equatable {
        /// Panel base URL (scheme + host + optional port + optional path prefix before the endpoint).
        let serverURL: String
        let username: String
        let password: String
    }

    /// Panel endpoints that carry the account in their query. Providers hand out
    /// either one as "the link".
    private static let accountEndpoints = ["/get.php", "/player_api.php"]

    /// Returns credentials when the URL is an Xtream-style account link, `nil` otherwise.
    /// A link without a scheme is read as `http://`.
    static func detect(urlString: String) -> Credentials? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = withHTTPScheme(trimmed),
              let components = URLComponents(string: address),
              let host = components.host, !host.isEmpty,
              let endpoint = accountEndpoints.first(where: { components.path.lowercased().hasSuffix($0) })
        else { return nil }

        guard let items = components.queryItems,
              let username = firstNonEmptyValue(named: "username", in: items),
              let password = firstNonEmptyValue(named: "password", in: items)
        else { return nil }

        var base = URLComponents()
        base.scheme = components.scheme
        base.host = components.host
        base.port = components.port
        // Keep any path prefix (e.g. http://host/panel/get.php → http://host/panel).
        base.path = String(components.path.dropLast(endpoint.count))

        guard let serverURL = base.string, !serverURL.isEmpty else { return nil }
        return Credentials(serverURL: serverURL, username: username, password: password)
    }

    /// The panel address as the API client wants it: `scheme://host[:port][/prefix]`.
    /// Returns `nil` when the text has no host or names a scheme other than http(s).
    ///
    /// People paste what their provider sent, which is rarely the bare address:
    /// - no scheme (`host:8080`) is read as `http://`,
    /// - a scheme in front of a scheme (`http://https://host`, typed prefix plus a
    ///   pasted link) keeps the last one, which is the one that was pasted,
    /// - a trailing endpoint (`/get.php`, `/player_api.php`, `/xmltv.php`), query,
    ///   fragment and embedded user info are dropped. The client appends its own
    ///   endpoint and would otherwise request `…/get.php?…/player_api.php`.
    static func normalizedServerURL(_ input: String) -> String? {
        // An address has no spaces; the ones that arrive come from a line-wrapped paste.
        let text = input.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let address = withHTTPScheme(text),
              let components = URLComponents(string: address),
              let host = components.host, !host.isEmpty
        else { return nil }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        let lowercasedPath = path.lowercased()
        if let endpoint = (accountEndpoints + ["/xmltv.php"]).first(where: { lowercasedPath.hasSuffix($0) }) {
            path.removeLast(endpoint.count)
            while path.hasSuffix("/") { path.removeLast() }
        }

        var base = URLComponents()
        base.scheme = components.scheme?.lowercased()
        base.host = host
        base.port = components.port
        base.path = path
        guard let normalized = base.string, !normalized.isEmpty else { return nil }
        return normalized
    }

    /// `text` with exactly one http(s) scheme in front, or `nil` when it is empty or
    /// starts with another scheme.
    private static func withHTTPScheme(_ text: String) -> String? {
        var rest = Substring(text)
        var scheme: String?
        while true {
            let lowercased = rest.prefix(8).lowercased()
            if lowercased.hasPrefix("https://") {
                scheme = "https"
                rest = rest.dropFirst(8)
            } else if lowercased.hasPrefix("http://") {
                scheme = "http"
                rest = rest.dropFirst(7)
            } else {
                break
            }
        }
        guard !rest.isEmpty else { return nil }

        // What is left may still open with a scheme of its own ("rtsp://…", "file://…").
        if let separator = rest.range(of: "://") {
            let candidate = rest[..<separator.lowerBound]
            let isScheme = candidate.first?.isLetter == true
                && candidate.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
            if isScheme { return nil }
        }
        return "\(scheme ?? "http")://\(rest)"
    }

    private static func firstNonEmptyValue(named name: String, in items: [URLQueryItem]) -> String? {
        guard let value = items.first(where: { $0.name.lowercased() == name })?.value,
              !value.isEmpty else { return nil }
        return value
    }
}
