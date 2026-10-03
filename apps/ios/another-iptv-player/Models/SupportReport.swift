import Foundation

/// A frozen, user-initiated report. Never uploads or sends anything itself.
nonisolated struct SupportReport: Identifiable {
    static let recipient = "bsogulcan@gmail.com"
    let id = UUID()
    let subject: String
    let body: String
    let diagnostics: String?

    var attachment: Data? { diagnostics.map { Data($0.utf8) } }
    var shareText: String { "To: \(Self.recipient)\nSubject: \(subject)\n\n\(body)" }

    private static let patterns: [(NSRegularExpression?, String)] = [
            (try? NSRegularExpression(pattern: #"(?i)\b(?:Bearer|Basic)\s+[^\s\"',;]+"#), "<authorization>"),
            (try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9+.\-])[A-Za-z][A-Za-z0-9+.\-]*://[^\s\"']+"#), "<url>"),
        ]
    private static let fieldRegex = try? NSRegularExpression(pattern: #"(?i)(["']?\b(?:username|password|passwd|pass|token|access_token|refresh_token|api_key|authorization|cookie|set-cookie|email)\b["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*(?:"|$)|'(?:\\.|[^'\\])*(?:'|$)|[^\s,;}]+)"#)

    /// Export is deliberately stricter than the on-device console: remove whole URLs
    /// (including hosts and stream IDs), plus common structured credential fields.
    static func sanitized(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in patterns {
            guard let regex = pattern else { return "<redacted>" }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        // Preserve quotation marks in JSON while handling escaped or incomplete values.

        if let regex = fieldRegex {
            let source = result as NSString
            var output = ""
            output.reserveCapacity(result.utf8.count)
            var cursor = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)) {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let prefix = source.substring(with: match.range(at: 1))
                let valueStart = NSMaxRange(match.range(at: 1))
                let quote = source.substring(with: NSRange(location: valueStart, length: 1))
                output += prefix + (quote == "\"" || quote == "'" ? quote + "<redacted>" + quote : "<redacted>")
                cursor = NSMaxRange(match.range)
            }
            output += source.substring(from: cursor)
            result = output
        }
        return result
    }

    static func diagnosticsText(current: [String], savedAirPlay: [String], savedAt: Date?, archive: String = "") -> String {
        var sections = archive.isEmpty
            ? ["Current app session:\n" + current.suffix(300).joined(separator: "\n")]
            : ["Application logs and API responses (up to 7 days; size-limited):\n" + archive]
        if archive.isEmpty && !savedAirPlay.isEmpty {
            let date = savedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
            sections.append("Last saved AirPlay session (\(date)):\n" + savedAirPlay.suffix(200).joined(separator: "\n"))
        }
        // Archive rotation bounds the export; do not cut away recent events here.
        return sanitized(sections.joined(separator: "\n\n"))
    }
}
