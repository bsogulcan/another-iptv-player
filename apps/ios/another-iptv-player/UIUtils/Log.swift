import Foundation
import os

/// Tüm NSLog çağrıları bu helper üzerinden gitmeli.
///
/// **Neden:** `NSLog("foo \(bar)")` çağrısında interpolate edilmiş tüm string format string
/// olarak yorumlanır. `bar` içinde `%` geçerse (URL'lerdeki `%20`, `%2F` vb.) NSLog
/// va_list'ten çöp pointer okuyup `EXC_BAD_ACCESS` ile crash eder.
///
/// `Log.info/error` her zaman mesajı `"%@"` ile geçirir → format string injection imkânsız.
///
/// The backend is now `os.Logger` (subsystem = bundle identifier, category = tag), so a
/// Console filter on the bundle id shows every line, and there is no format string at all.
/// Each line is also kept in a small in-memory ring buffer (`recentLines(tags:)`) so the
/// app can show and copy its own recent log without a cable. A bounded, sanitized
/// DiagnosticArchive also survives relaunches for user-initiated support reports.
///
/// Every message is passed through `redactURLs(in:)` first: Xtream URLs carry the panel
/// credentials in the path or the query, and these lines end up in bug reports.
nonisolated enum Log {
  static func info(_ tag: String, _ message: @autoclosure () -> String) {
    write(.info, tag, message())
  }

  static func error(_ tag: String, _ message: @autoclosure () -> String) {
    write(.error, tag, message())
  }

  // MARK: - Recent lines (in-memory)

  /// Number of lines `recentLines(tags:)` can return at most.
  static let recentCapacity = 300

  /// The most recent lines, oldest first, formatted as `HH:mm:ss.SSS [tag] message`
  /// (errors as `HH:mm:ss.SSS [tag] ERROR: message`). `nil` returns every tag.
  static func recentLines(tags: [String]? = nil) -> [String] {
    worker.sync { recent.entries(tags: tags.map { Set($0) }).map(\.line) }
  }

  /// Same as above for any other collection of tags (a `Set`, a slice, ...).
  static func recentLines<S: Sequence>(tags: S) -> [String] where S.Element == String {
    worker.sync { recent.entries(tags: Set(tags)).map(\.line) }
  }

  static func clearRecent() {
    worker.sync { recent.removeAll() }
  }

  // MARK: - Persisted lines (survive a relaunch)

  /// Bounds of what `persistRecent` stores under one key, whatever `limit` the
  /// caller passes: the record lives in UserDefaults, which is no place for a log
  /// of any size. 200 lines of 300 characters is about 60 KB at the very most.
  static let persistedLineLimit = 200
  static let persistedLineLength = 300

  /// Stores the newest `limit` recent lines of `tags` under `key`, replacing what was
  /// there, so they can still be read after the app was killed or relaunched (the
  /// ring buffer above lives in memory only). The lines went through `redactURLs`
  /// when they were logged, so nothing is stored that the log does not already
  /// show. With no line to store the previous record is kept: an empty one would
  /// only erase the last useful one. Local only; nothing leaves the device.
  static func persistRecent(
    tags: [String], key: String, limit: Int = 120, defaults: UserDefaults = .standard
  ) {
    let store = ThreadSafeDefaults(value: defaults)
    worker.submit(bytes: 0) { [store] in
      let lines = persistable(recent.entries(tags: Set(tags)).map(\.line), limit: limit)
      guard !lines.isEmpty else { return }
      let record: [String: Any] = [persistedLinesField: lines, persistedDateField: Date()]
      store.value.set(record, forKey: key)
    }
  }

  /// The lines last stored under `key`, oldest first; empty when there are none.
  static func persistedLines(key: String, defaults: UserDefaults = .standard) -> [String] {
    worker.sync { (defaults.dictionary(forKey: key)?[persistedLinesField] as? [String]) ?? [] }
  }

  /// When the lines under `key` were stored. The lines carry a time of day only.
  static func persistedDate(key: String, defaults: UserDefaults = .standard) -> Date? {
    worker.sync { defaults.dictionary(forKey: key)?[persistedDateField] as? Date }
  }

  /// The newest `limit` of `lines` (never more than `persistedLineLimit`), each cut
  /// to `persistedLineLength` characters. Pure function.
  static func persistable(_ lines: [String], limit: Int) -> [String] {
    let count = min(max(limit, 0), persistedLineLimit)
    return lines.suffix(count).map {
      $0.count > persistedLineLength ? String($0.prefix(persistedLineLength)) + "…" : $0
    }
  }

  // MARK: - Redaction

  /// A loggable form of `url`: scheme, host and port are kept; user info, the credential
  /// segments of the path and the whole query are replaced with placeholders.
  ///
  ///     http://host/movie/alice/secret/12.mkv        -> http://host/movie/<user>/<pass>/12.mkv
  ///     http://host/alice/secret/12.ts               -> http://host/<user>/<pass>/12.ts
  ///     http://host/player_api.php?username=a&pass.. -> http://host/player_api.php?<query>
  ///     https://cdn/hls/9f3a77c1/index.m3u8          -> https://cdn/<path>/index.m3u8
  ///
  /// A path that is not a known Xtream shape is collapsed rather than kept, because a
  /// token can sit in any segment and these lines are meant to be pasted into bug reports.
  /// The fragment is dropped for the same reason.
  static func redact(_ url: URL) -> String {
    guard let scheme = url.scheme, !scheme.isEmpty else { return urlPlaceholder }
    var out = scheme + "://"

    let user = url.user(percentEncoded: true) ?? ""
    if !user.isEmpty || url.password(percentEncoded: true) != nil {
      out += "<credentials>@"
    }
    if let host = url.host(percentEncoded: true), !host.isEmpty {
      // URL hands an IPv6 literal back without its brackets.
      out += host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    }
    if let port = url.port {
      out += ":\(port)"
    }

    let path = url.path(percentEncoded: true)
    let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    if segments.isEmpty {
      out += path.hasPrefix("/") ? "/" : ""
    } else {
      out += "/" + redactedPathSegments(segments).joined(separator: "/")
      if path.hasSuffix("/") { out += "/" }
    }

    // An empty query keeps its "?" so that text which was already redacted
    // ("...php?<query>") comes out unchanged when it passes through a second time.
    if let query = url.query(percentEncoded: true) {
      out += query.isEmpty ? "?" : "?<query>"
    }
    return out
  }

  /// `message` with everything that looks like a URL replaced by its redacted form, and
  /// bare `username=` / `password=` / `token=` pairs blanked.
  static func redactURLs(in message: String) -> String {
    var result = message

    if result.contains("://") {
      // The pattern is a constant, so this cannot fail; if it ever did, dropping the
      // message is the only way to be sure no credential gets through.
      guard let regex = urlRegex else { return "<redacted: message contained a URL>" }
      let source = result as NSString
      var out = ""
      var cursor = 0
      for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)) {
        var raw = source.substring(with: match.range)
        // Sentence punctuation right after a URL ("... http://host/a.ts).") is not part of it.
        var trailing = ""
        while let last = raw.last, isTrailingPunctuation(last, in: raw) {
          trailing.insert(last, at: trailing.startIndex)
          raw.removeLast()
        }
        out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        out += URL(string: raw).map { redact($0) } ?? urlPlaceholder
        out += trailing
        cursor = match.range.location + match.range.length
      }
      out += source.substring(from: cursor)
      result = out
    }

    if result.contains("="), let regex = credentialPairRegex {
      let source = result as NSString
      result = regex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: source.length),
        withTemplate: "$1=<redacted>"
      )
    }
    return result
  }

  // MARK: - Types

  nonisolated enum Level: String, Sendable {
    case info
    case error
  }

  nonisolated struct Entry: Sendable, Equatable {
    let date: Date
    let level: Level
    let tag: String
    let message: String

    var line: String {
      let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
      let stamp = String(
        format: "%02d:%02d:%02d.%03d",
        parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, (parts.nanosecond ?? 0) / 1_000_000
      )
      switch level {
      case .info: return "\(stamp) [\(tag)] \(message)"
      case .error: return "\(stamp) [\(tag)] ERROR: \(message)"
      }
    }
  }

  /// Fixed-size, thread-safe store of the newest entries. Logging happens on the main
  /// thread and on the remux worker queues, so every access takes the lock.
  nonisolated final class RingBuffer: @unchecked Sendable {
    let capacity: Int
    private let lock = NSLock()
    private var storage: [Entry] = []
    /// Index of the oldest entry once `storage` is full; 0 until then.
    private var head = 0

    init(capacity: Int) {
      self.capacity = max(1, capacity)
      storage.reserveCapacity(self.capacity)
    }

    func append(_ entry: Entry) {
      lock.lock()
      defer { lock.unlock() }
      if storage.count < capacity {
        storage.append(entry)
      } else {
        storage[head] = entry
        head = (head + 1) % capacity
      }
    }

    /// Oldest first. `nil` returns every tag.
    func entries(tags: Set<String>? = nil) -> [Entry] {
      lock.lock()
      let ordered = Array(storage[head...]) + Array(storage[..<head])
      lock.unlock()
      guard let tags else { return ordered }
      return ordered.filter { tags.contains($0.tag) }
    }

    func removeAll() {
      lock.lock()
      defer { lock.unlock() }
      storage.removeAll(keepingCapacity: true)
      head = 0
    }
  }

  // MARK: - Private

  // Foundation documents UserDefaults as thread-safe; the wrapper crosses this queue only.
  private struct ThreadSafeDefaults: @unchecked Sendable {
    let value: UserDefaults
  }

  private static let subsystem = Bundle.main.bundleIdentifier ?? "another-iptv-player"
  private static let recent = RingBuffer(capacity: recentCapacity)
  private static let worker = DiagnosticWorkQueue(label: "app.diagnostics.events", onDrop: { count in
    emit(.error, "Diagnostics", "Dropped \(count) log records during overload", date: Date())
  })
  // Accessed exclusively on worker.queue.
  private static let timestampFormatter = ISO8601DateFormatter()

  static func flush() { worker.flush() }
  private static let urlPlaceholder = "<url>"
  private static let persistedLinesField = "lines"
  private static let persistedDateField = "savedAt"

  /// `scheme://` followed by everything up to whitespace, a quote or an angle bracket.
  private static let urlRegex = try? NSRegularExpression(
    pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>]+"#
  )
  private static let credentialPairRegex = try? NSRegularExpression(
    pattern: #"\b(username|password|token)=[^&\s"'<>]+"#,
    options: [.caseInsensitive]
  )

  /// Xtream path shapes that put `user/pass` right after this segment.
  private static let xtreamKinds: Set<String> = ["live", "movie", "series", "timeshift"]

  private static func write(_ level: Level, _ tag: String, _ rawMessage: String) {
    let date = Date()
    worker.submit(bytes: rawMessage.utf8.count + tag.utf8.count) {
      emit(level, tag, rawMessage, date: date)
    }
  }

  private static func emit(_ level: Level, _ tag: String, _ rawMessage: String, date: Date) {
    let message = tag == "KSPlayer" ? SupportReport.sanitized(rawMessage) : redactURLs(in: rawMessage)
    // os_log_create hands back the same cached object for a subsystem/category pair,
    // so building a Logger per call is cheap.
    let logger = Logger(subsystem: subsystem, category: tag)
    switch level {
    case .info:
      // .notice, not .info: NSLog wrote at the default level, which is persisted and so
      // still there when a sysdiagnose is taken after the fact. .info is memory-only.
      logger.notice("\(message, privacy: .public)")
    case .error:
      logger.error("\(message, privacy: .public)")
    }
    let entry = Entry(date: date, level: level, tag: tag, message: message)
    recent.append(entry)
    DiagnosticArchive.shared.append("\(timestampFormatter.string(from: entry.date)) [\(tag)] \(level.rawValue): \(message)")
  }

  private static func redactedPathSegments(_ segments: [String]) -> [String] {
    let kind = segments.firstIndex { xtreamKinds.contains($0.lowercased()) }
    // {prefix}/{live|movie|series|timeshift}/{user}/{pass}/.../{id}.{ext}
    if let kind, kind + 3 < segments.count {
      var out = segments
      out[kind + 1] = "<user>"
      out[kind + 2] = "<pass>"
      return out
    }
    // {user}/{pass}/{id}[.ext] — the plain Xtream live shape.
    if segments.count == 3, isNumeric(stem(of: segments[2])) {
      return ["<user>", "<pass>", segments[2]]
    }
    // A kind segment with no stream id behind it: whatever follows is treated as credentials.
    if let kind {
      var out = segments
      for (offset, placeholder) in ["<user>", "<pass>"].enumerated() where kind + 1 + offset < out.count {
        out[kind + 1 + offset] = placeholder
      }
      return out
    }
    // Unknown shape: any directory may be a token, so keep only a harmless file name.
    let file = safeFileName(segments[segments.count - 1])
    return segments.count == 1 ? [file] : ["<path>", file]
  }

  /// Keeps names like `123.ts`, `index.m3u8` or `player_api.php`; anything that could be
  /// an opaque token or a credential (a bare word with no extension included) becomes
  /// `<file>` plus its extension.
  private static func safeFileName(_ segment: String) -> String {
    let name = stem(of: segment)
    let ext = String(segment.dropFirst(name.count))  // "" or ".ext"
    let extBody = ext.dropFirst()
    let extIsPlain = !extBody.isEmpty && extBody.count <= 5
      && extBody.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    if isNumeric(name), ext.isEmpty || extIsPlain { return segment }
    if isPlainWord(name), extIsPlain { return segment }
    return extIsPlain ? "<file>\(ext)" : "<file>"
  }

  private static func stem(of segment: String) -> String {
    guard let dot = segment.lastIndex(of: "."), dot != segment.startIndex else { return segment }
    return String(segment[..<dot])
  }

  private static func isNumeric(_ text: String) -> Bool {
    !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
  }

  private static func isPlainWord(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 24
      && text.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "_" || $0 == "-") }
  }

  private static func isTrailingPunctuation(_ character: Character, in raw: String) -> Bool {
    switch character {
    case ".", ",", ";", ":", "!", "?", ")", "'", "\"":
      return true
    case "]":
      // Part of the URL only when it closes an IPv6 literal ("http://[::1]").
      return raw.filter { $0 == "]" }.count > raw.filter { $0 == "[" }.count
    default:
      return false
    }
  }
}
