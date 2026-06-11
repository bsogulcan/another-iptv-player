import Foundation

/// Detects Xtream-panel M3U links (`…/get.php?username=X&password=Y…`) and extracts
/// the credentials needed to connect through the Xtream Codes API instead.
///
/// Many panels disable or block the `get.php` M3U download endpoint while keeping
/// `player_api.php` fully functional, so connecting via the API both sidesteps those
/// blocks and unlocks the richer experience (VOD/series metadata, EPG).
enum XtreamLinkDetector {

    struct Credentials: Equatable {
        /// Panel base URL (scheme + host + optional port + optional path prefix before `get.php`).
        let serverURL: String
        let username: String
        let password: String
    }

    /// Returns credentials when the URL is an Xtream-style `get.php` link, `nil` otherwise.
    static func detect(urlString: String) -> Credentials? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.path.lowercased().hasSuffix("/get.php")
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
        base.path = String(components.path.dropLast("/get.php".count))

        guard let serverURL = base.string, !serverURL.isEmpty else { return nil }
        return Credentials(serverURL: serverURL, username: username, password: password)
    }

    private static func firstNonEmptyValue(named name: String, in items: [URLQueryItem]) -> String? {
        guard let value = items.first(where: { $0.name.lowercased() == name })?.value,
              !value.isEmpty else { return nil }
        return value
    }
}
