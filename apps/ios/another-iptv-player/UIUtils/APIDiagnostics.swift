import Foundation

nonisolated enum APIDiagnostics {
    static let bodyLimit = 64 * 1024
    private static let worker = DiagnosticWorkQueue(label: "app.diagnostics.api", countLimit: 4, byteLimit: 8 * 1024 * 1024, onDrop: { count in
        Log.error("Diagnostics", "Skipped \(count) API diagnostic jobs during overload or because of size limits")
    })
    private static let timestampFormatter = ISO8601DateFormatter()

    static func flush() { worker.flush() }
    private static let sensitiveKeys: Set<String> = [
        "username", "password", "passwd", "pass", "token", "accesstoken", "refreshtoken",
        "apikey", "authorization", "cookie", "setcookie", "email", "phone", "ip", "userip"
    ]

    /// Keep JSON types/shape for decoder debugging, removing secrets before persistence.
    static func body(_ data: Data, secrets: [String] = []) -> String {
        let text: String
        var inputTruncated = false
        var structured = false
        if data.count <= 2 * 1024 * 1024,
           let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let cleaned = try? JSONSerialization.data(withJSONObject: scrub(value, secrets: secrets), options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys]) {
            structured = true
            text = String(decoding: cleaned, as: UTF8.self)
        } else {
            // Preserve malformed JSON too. Normalize JSON-escaped URLs before masking.
            inputTruncated = data.count > bodyLimit
            text = String(decoding: data.prefix(bodyLimit), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        }
        var safe = text
        if !structured {
            for secret in secrets where !secret.isEmpty { safe = safe.replacingOccurrences(of: secret, with: "<credential>") }
        }
        safe = SupportReport.sanitized(safe)
        let truncated = safe.utf8.count > bodyLimit || inputTruncated
        return String(decoding: safe.utf8.prefix(bodyLimit), as: UTF8.self)
            + (truncated ? "\n[response truncated; original bytes: \(data.count)]" : "")
    }

    private static func scrub(_ value: Any, secrets: [String]) -> Any {
        if let object = value as? [String: Any] {
            return object.mapValues { scrub($0, secrets: secrets) }.merging(
                object.filter { sensitiveKeys.contains($0.key.lowercased().filter { $0.isLetter || $0.isNumber }) }
                    .mapValues { _ in "<redacted>" as Any }, uniquingKeysWith: { _, redacted in redacted })
        }
        if let array = value as? [Any] { return array.map { scrub($0, secrets: secrets) } }
        if var string = value as? String {
            for secret in secrets where !secret.isEmpty { string = string.replacingOccurrences(of: secret, with: "<credential>") }
            return SupportReport.sanitized(string)
        }
        return value
    }

    static func record(_ data: Data, action: String, context: String, secrets: [String] = []) {
        guard action != "authentication" else {
            Log.error("API", "Authentication response could not be decoded; body omitted")
            return
        }
        let date = Date()
        // Large responses retain only a bounded prefix; no unbounded Data in queued closures.
        let captured = data.count <= 2 * 1024 * 1024 ? data : Data(data.prefix(bodyLimit))
        let originalCount = data.count
        worker.submit(bytes: captured.count) {
            let safe = body(captured, secrets: secrets)
            let suffix = originalCount > captured.count ? "\n[response truncated; original bytes: \(originalCount)]" : ""
            DiagnosticArchive.shared.append("\(timestampFormatter.string(from: date)) [APIResponse] \(action) — \(context)\n\(safe)\(suffix)")
        }
    }

    static func recordFailedItems(_ data: Data, indices: [Int], action: String, secrets: [String]) {
        worker.submit(bytes: data.count) {
            guard let objects = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return }
            for index in indices.prefix(5) where objects.indices.contains(index) {
                guard let raw = try? JSONSerialization.data(withJSONObject: objects[index], options: [.fragmentsAllowed]) else { continue }
                let safe = body(raw, secrets: secrets)
                DiagnosticArchive.shared.append("\(timestampFormatter.string(from: Date())) [APIResponse] \(action) — skipped index=\(index)\n\(safe)")
            }
        }
    }
}
