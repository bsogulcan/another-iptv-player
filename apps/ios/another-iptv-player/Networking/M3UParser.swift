import Foundation

// MARK: - Public Types

/// Parse sonucu tek bir kanal.
struct ParsedM3UChannel: Equatable, Sendable {
    var name: String
    var url: String
    var tvgId: String?
    var tvgName: String?
    var tvgLogo: String?
    var tvgCountry: String?
    var groupTitle: String?
    var userAgent: String?
}

struct ParsedM3UPlaylist: Equatable, Sendable {
    var channels: [ParsedM3UChannel]
    /// `#EXTM3U` satırındaki `x-tvg-url` (varsa). v1'de sadece saklanır, EPG için kullanılmaz.
    var epgURL: String?
}

enum M3UParserError: LocalizedError {
    case empty
    case noChannelsFound

    var errorDescription: String? {
        switch self {
        case .empty: return L("parser.error.empty")
        case .noChannelsFound: return L("parser.error.no_channels")
        }
    }
}

// MARK: - Parser

/// IPTV-odaklı M3U / M3U8 parser.
///
/// Mimari videojs/m3u8-parser'dan ilham aldı: `classify` satırı tipli bir `M3ULine`'a çevirir,
/// ana döngü state-machine olarak kanal ekler. HLS (variant stream) değil, kanal-listesi M3U'su hedeflenir.
///
/// Desteklenen tag'ler:
/// - `#EXTM3U [x-tvg-url="..."]`
/// - `#EXTINF:<duration> [tvg-id="..."] [tvg-name="..."] [tvg-logo="..."] [tvg-country="..."] [group-title="..."] [user-agent="..."],Display Name`
/// - `#EXTVLCOPT:http-user-agent=...`
/// - `#KODIPROP:inputstream.adaptive.stream_headers="User-Agent=..."`
/// - `#EXTGRP:GroupName`
///
/// Dayanıklılık:
/// - UTF-8 BOM, `\r\n`/`\r`/U+2028/U+2029 newline'ları normalize eder.
/// - Attr değeri içindeki virgüllere (tvg-logo URL'leri) dayanıklıdır (quote-aware split).
/// - Attr değeri içine sızmış newline'ları birleştirir (`joinEXTINFContinuations`).
/// - EXTINF ve URL aynı satıra yapışık gelmişse (`...,Namehttp://...`) ayırır.
/// - URL percent-encoding fallback'i ile oynatılabilirliği arttırır.
enum M3UParser {

    // MARK: Tag Prefixes

    private enum Tag {
        static let extm3u = "#EXTM3U"
        static let extinf = "#EXTINF:"
        static let extvlcopt = "#EXTVLCOPT:"
        static let kodiProp = "#KODIPROP:"
        static let kodiPropAlt = "#EXT-X-KODI-PROP:"
        static let extgrp = "#EXTGRP:"
    }

    // MARK: Diagnostics

    struct NoGroupSample: Equatable, Sendable {
        var rawExtinf: String
        var name: String
        var url: String
    }

    struct ParseDiagnostics: Equatable, Sendable {
        var totalLines: Int = 0
        var extm3uLines: Int = 0
        var extinfLines: Int = 0
        var uriLines: Int = 0
        var commentLines: Int = 0
        var vlcOptLines: Int = 0
        var kodiPropLines: Int = 0
        var extgrpLines: Int = 0
        var orphanURIs: Int = 0
        var lostPendingChannels: Int = 0
        var channelCount: Int = 0
        var noGroupCount: Int = 0
        var noNameFallbackCount: Int = 0
        /// İlk 20 "Diğer"e düşen kanalın ham EXTINF satırı + parsed özeti (debug için).
        var sampleNoGroup: [NoGroupSample] = []

        var debugSummary: String {
            """
            M3U Parse Diagnostics
            ---
            Satır sayısı:          \(totalLines)
            #EXTM3U:               \(extm3uLines)
            #EXTINF:               \(extinfLines)
            URI satırı:            \(uriLines)
            #EXTVLCOPT:            \(vlcOptLines)
            #KODIPROP:             \(kodiPropLines)
            #EXTGRP:               \(extgrpLines)
            Yorum/bilinmeyen:      \(commentLines)
            Orphan URI (skip):     \(orphanURIs)
            Kayıp pending EXTINF:  \(lostPendingChannels)
            ---
            Toplam kanal:          \(channelCount)
            Group-title'sız:       \(noGroupCount)
            Name fallback tetik:   \(noNameFallbackCount)
            """
        }
    }

    // MARK: Public API

    /// Senkron parse. Büyük dosyalar için `parseAsync`'i tercih et — bu UI thread'i bloklar.
    static func parse(_ rawText: String) throws -> ParsedM3UPlaylist {
        try parseInternal(rawText, collectDiagnostics: false).playlist
    }

    /// Senkron parse + diagnostics. UI thread'i bloklayabilir; büyük dosyada `parseWithDiagnosticsAsync` kullan.
    static func parseWithDiagnostics(_ rawText: String) throws -> (playlist: ParsedM3UPlaylist, diagnostics: ParseDiagnostics) {
        try parseInternal(rawText, collectDiagnostics: true)
    }

    /// Arka plan thread'inde parse — UI akışını korur. 310K kanal için ~3-5 saniye sürebilir; çağıran tarafta progress göster.
    static func parseAsync(_ rawText: String) async throws -> ParsedM3UPlaylist {
        try await Task.detached(priority: .userInitiated) {
            try parse(rawText)
        }.value
    }

    /// Arka plan parse + diagnostics.
    static func parseWithDiagnosticsAsync(_ rawText: String) async throws -> (playlist: ParsedM3UPlaylist, diagnostics: ParseDiagnostics) {
        try await Task.detached(priority: .userInitiated) {
            try parseWithDiagnostics(rawText)
        }.value
    }

    /// URL string'ini `URL`'e çevirir. Doğrudan başarısız olursa boşluk/UTF-8 gibi encode edilmemiş
    /// karakterler için percent-encoding fallback'i dener.
    static func sanitizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: ":/?#[]@!$&'()*+,;=%")
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }

    // MARK: Core

    private static func parseInternal(
        _ rawText: String,
        collectDiagnostics: Bool
    ) throws -> (playlist: ParsedM3UPlaylist, diagnostics: ParseDiagnostics) {
        var text = rawText
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw M3UParserError.empty
        }

        // Newline normalizasyonu: ASCII + Unicode line/paragraph separators.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        // Attr değeri içine sızmış newline'ları birleştir.
        let logicalLines = joinEXTINFContinuations(
            normalized.split(separator: "\n", omittingEmptySubsequences: false)
        )

        var state = ParserState()
        var diag = ParseDiagnostics()

        for rawLine in logicalLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if collectDiagnostics { diag.totalLines += 1 }

            processLine(line, state: &state, diag: &diag, collectDiagnostics: collectDiagnostics)
        }

        guard !state.channels.isEmpty else {
            throw M3UParserError.noChannelsFound
        }

        if collectDiagnostics {
            diag.channelCount = state.channels.count
            diag.noGroupCount = state.channels.filter { ($0.groupTitle?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }.count
        }

        return (
            playlist: ParsedM3UPlaylist(channels: state.channels, epgURL: state.epgURL),
            diagnostics: diag
        )
    }

    /// Ana döngüden çıkarıldı; tek satırı işler ve state'i günceller.
    private static func processLine(
        _ line: String,
        state: inout ParserState,
        diag: inout ParseDiagnostics,
        collectDiagnostics: Bool
    ) {
        switch classify(line) {
        case .comment:
            if collectDiagnostics { diag.commentLines += 1 }

        case .extm3u(let attrs):
            if collectDiagnostics { diag.extm3uLines += 1 }
            state.epgURL = attrs["x-tvg-url"] ?? attrs["url-tvg"]

        case .extinf(_, let attrs, let title, let embeddedURL):
            if collectDiagnostics {
                diag.extinfLines += 1
                if state.pendingChannel != nil { diag.lostPendingChannels += 1 }
            }

            var ch = channel(from: attrs, title: title)
            if ch.userAgent == nil, let ua = state.pendingUserAgent { ch.userAgent = ua }
            if (ch.groupTitle?.isEmpty ?? true), let grp = state.pendingGroupOverride {
                ch.groupTitle = grp
            }

            if let embedded = embeddedURL, !embedded.isEmpty {
                // Yapışık EXTINF+URL — kanalı hemen ekle.
                ch.url = embedded
                let wasEmpty = ch.name.trimmingCharacters(in: .whitespaces).isEmpty
                applyNameFallback(&ch, urlString: embedded, channelsCount: state.channels.count)
                if collectDiagnostics {
                    if wasEmpty { diag.noNameFallbackCount += 1 }
                    collectNoGroupSample(&diag, channel: ch, rawExtinf: line)
                }
                state.channels.append(ch)
                state.resetPending()
            } else {
                state.pendingChannel = ch
                state.pendingUserAgent = nil
                state.pendingGroupOverride = nil
                state.pendingRawExtinf = line
            }

        case .extvlcopt(let key, let value):
            if collectDiagnostics { diag.vlcOptLines += 1 }
            if key.lowercased() == "http-user-agent" {
                state.assignUserAgent(value)
            }

        case .kodiProp(let key, let value):
            if collectDiagnostics { diag.kodiPropLines += 1 }
            if key.lowercased().hasSuffix("stream_headers"),
               let ua = parseHeaderString(value, keyed: "user-agent") {
                state.assignUserAgent(ua)
            }

        case .extgrp(let group):
            if collectDiagnostics { diag.extgrpLines += 1 }
            state.assignGroup(group)

        case .uri(let url):
            if collectDiagnostics { diag.uriLines += 1 }
            guard var ch = state.pendingChannel else {
                if collectDiagnostics { diag.orphanURIs += 1 }
                return
            }
            ch.url = url
            if ch.userAgent == nil, let ua = state.pendingUserAgent { ch.userAgent = ua }
            let wasEmpty = ch.name.trimmingCharacters(in: .whitespaces).isEmpty
            applyNameFallback(&ch, urlString: url, channelsCount: state.channels.count)
            if collectDiagnostics {
                if wasEmpty { diag.noNameFallbackCount += 1 }
                collectNoGroupSample(&diag, channel: ch, rawExtinf: state.pendingRawExtinf ?? "(no pending extinf)")
            }
            state.channels.append(ch)
            state.resetPending()
        }
    }

    // MARK: Parser State

    private struct ParserState {
        var channels: [ParsedM3UChannel] = []
        var epgURL: String? = nil
        var pendingChannel: ParsedM3UChannel? = nil
        var pendingUserAgent: String? = nil
        var pendingGroupOverride: String? = nil
        var pendingRawExtinf: String? = nil

        mutating func resetPending() {
            pendingChannel = nil
            pendingUserAgent = nil
            pendingGroupOverride = nil
            pendingRawExtinf = nil
        }

        /// EXTINF'ten SONRA gelen EXTVLCOPT/KODIPROP için: önce pendingChannel üstüne yaz, yoksa bekletme kovasına al.
        mutating func assignUserAgent(_ ua: String) {
            if var p = pendingChannel {
                if p.userAgent == nil { p.userAgent = ua }
                pendingChannel = p
            } else {
                pendingUserAgent = ua
            }
        }

        mutating func assignGroup(_ group: String) {
            if var p = pendingChannel {
                if p.groupTitle?.isEmpty ?? true { p.groupTitle = group }
                pendingChannel = p
            } else {
                pendingGroupOverride = group
            }
        }
    }

    // MARK: Line Classification

    private enum M3ULine {
        case comment
        case extm3u(attributes: [String: String])
        case extinf(duration: Double?, attributes: [String: String], title: String, embeddedURL: String?)
        case extvlcopt(key: String, value: String)
        case kodiProp(key: String, value: String)
        case extgrp(String)
        case uri(String)
    }

    private static func classify(_ line: String) -> M3ULine {
        // URL satırı: `#` ile başlamayan her şey (http, https, rtmp, rtsp, udp, relative path, vb.)
        guard line.hasPrefix("#") else { return .uri(line) }

        if line.hasPrefix(Tag.extm3u) {
            return .extm3u(attributes: parseAttributes(in: line))
        }
        if line.hasPrefix(Tag.extinf) {
            return parseExtinf(line)
        }
        if line.hasPrefix(Tag.extvlcopt) {
            let (k, v) = splitKeyValue(String(line.dropFirst(Tag.extvlcopt.count)))
            return .extvlcopt(key: k, value: v)
        }
        if line.hasPrefix(Tag.kodiProp) {
            let (k, v) = splitKeyValue(String(line.dropFirst(Tag.kodiProp.count)))
            return .kodiProp(key: k, value: v)
        }
        if line.hasPrefix(Tag.kodiPropAlt) {
            let (k, v) = splitKeyValue(String(line.dropFirst(Tag.kodiPropAlt.count)))
            return .kodiProp(key: k, value: v)
        }
        if line.hasPrefix(Tag.extgrp) {
            let g = String(line.dropFirst(Tag.extgrp.count)).trimmingCharacters(in: .whitespaces)
            return .extgrp(g)
        }
        return .comment
    }

    private static func parseExtinf(_ line: String) -> M3ULine {
        // `#EXTINF:<duration>[ attrs],<Display Name>`
        // Virgül attr değerinde (tvg-logo URL'leri) de geçebilir — tırnak farkında böl.
        let body = String(line.dropFirst(Tag.extinf.count))
        let (header, rawTitle) = splitHeaderAndName(body)

        let duration: Double? = {
            let first = header.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            return Double(first)
        }()

        let attrs = parseAttributes(in: header)

        // Bozuk M3U'da title ve URL aynı satıra yapışmış olabilir.
        var title = rawTitle
        var embedded: String? = nil
        if let range = rawTitle.range(of: "https?://|rtmps?://|rtsps?://", options: .regularExpression) {
            title = String(rawTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            embedded = String(rawTitle[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }

        return .extinf(duration: duration, attributes: attrs, title: title, embeddedURL: embedded)
    }

    // MARK: Continuation Join

    /// EXTINF satırında açık kalmış tırnak varsa (attr değeri içine gerçek newline sızmışsa),
    /// tırnak dengelenene kadar sonraki fiziksel satırları birleştirir.
    ///
    ///     #EXTINF:-1 tvg-name="NL - Venom - 2018
    ///     " tvg-logo="..." group-title="...",NL - Venom - 2018
    ///     http://server/movie.mp4
    ///
    /// İlk iki satır mantıksal olarak tek EXTINF'tir. Yeni `#EXTINF:` görüldüğünde birleştirme durdurulur.
    private static func joinEXTINFContinuations(_ lines: [Substring]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(lines.count)
        var i = 0
        let n = lines.count
        while i < n {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(Tag.extinf), hasOddQuoteCount(trimmed) else {
                result.append(String(raw))
                i += 1
                continue
            }
            var buffer = String(raw)
            var j = i + 1
            let limit = min(n, i + 10) // güvenlik üst limiti — tek EXTINF için 10 fiziksel satır
            while j < limit {
                let nextTrimmed = lines[j].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix(Tag.extinf) { break } // yeni entry — birleştirme
                buffer += String(lines[j])
                j += 1
                if !hasOddQuoteCount(buffer) { break }
            }
            result.append(buffer)
            i = j
        }
        return result
    }

    private static func hasOddQuoteCount<S: StringProtocol>(_ s: S) -> Bool {
        var count = 0
        for c in s where c == "\"" { count += 1 }
        return count % 2 == 1
    }

    // MARK: Attribute Parsing

    /// `key="value"` (tırnaklı) VEYA `key=value` (tırnaksız, whitespace/virgüle kadar).
    /// videojs'un attribute pattern'inden genişletildi: hem HLS (comma-separated) hem IPTV (space-separated) destekler.
    private static let attributeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "([^=\\s,\"]+)=(?:\"([^\"]*)\"|([^\\s,\"]+))",
            options: []
        )
    }()

    private static func parseAttributes(in text: String) -> [String: String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [String: String] = [:]
        attributeRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 4 else { return }
            let keyRange = m.range(at: 1)
            let quotedRange = m.range(at: 2)
            let unquotedRange = m.range(at: 3)

            let key = ns.substring(with: keyRange).lowercased()
            let value: String
            if quotedRange.location != NSNotFound {
                value = ns.substring(with: quotedRange)
            } else if unquotedRange.location != NSNotFound {
                value = ns.substring(with: unquotedRange)
            } else {
                value = ""
            }
            out[key] = value
        }
        return out
    }

    /// `body`'yi, tırnak dışındaki ilk virgülden böler. Header (attr'lar) + Name (display).
    private static func splitHeaderAndName(_ body: String) -> (header: String, name: String) {
        var inQuotes = false
        var splitIndex: String.Index? = nil
        var i = body.startIndex
        while i < body.endIndex {
            let c = body[i]
            if c == "\"" {
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                splitIndex = i
                break
            }
            i = body.index(after: i)
        }
        guard let idx = splitIndex else {
            return (body, "")
        }
        let header = String(body[body.startIndex..<idx])
        let name = String(body[body.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        return (header, name)
    }

    /// `foo=bar` → ("foo", "bar"). `=` yoksa key = trim'lenmiş metin, value boş. Değer tırnaklıysa tırnakları soyar.
    private static func splitKeyValue(_ s: String) -> (key: String, value: String) {
        guard let eq = s.firstIndex(of: "=") else {
            return (s.trimmingCharacters(in: .whitespaces), "")
        }
        let k = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
        var v = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\"") {
            v = String(v.dropFirst().dropLast())
        }
        return (k, v)
    }

    /// KODIPROP stream_headers formatları: `User-Agent=Foo&Referer=Bar` veya `User-Agent: Foo\nReferer: Bar`.
    /// Verilen key'i arar, URL-encoded ise çözüp döner.
    private static func parseHeaderString(_ raw: String, keyed: String) -> String? {
        let lowerKey = keyed.lowercased()
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.split(whereSeparator: { $0 == "&" || $0 == "\n" })
        for p in parts {
            if let v = matchPair(p, separator: "=", key: lowerKey) {
                return v.removingPercentEncoding ?? v
            }
            if let v = matchPair(p, separator: ":", key: lowerKey) {
                return v.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func matchPair(_ part: Substring, separator: Character, key: String) -> String? {
        let pieces = part.split(separator: separator, maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return nil }
        guard pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == key else { return nil }
        return pieces[1]
    }

    // MARK: Channel Assembly

    private static func channel(from attrs: [String: String], title: String) -> ParsedM3UChannel {
        ParsedM3UChannel(
            name: title,
            url: "",
            tvgId: attrs["tvg-id"],
            tvgName: attrs["tvg-name"],
            tvgLogo: attrs["tvg-logo"],
            tvgCountry: attrs["tvg-country"],
            groupTitle: attrs["group-title"],
            userAgent: attrs["user-agent"]
        )
    }

    /// Ad fallback zinciri: display-name → tvg-name → URL.lastPathComponent → URL.host → "Kanal N"
    private static func applyNameFallback(_ channel: inout ParsedM3UChannel, urlString: String, channelsCount: Int) {
        guard channel.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let tvg = channel.tvgName?.trimmingCharacters(in: .whitespaces), !tvg.isEmpty {
            channel.name = tvg
            return
        }
        if let url = sanitizedURL(from: urlString) {
            let last = url.lastPathComponent
            if !last.isEmpty, last != "/" {
                channel.name = last
                return
            }
            if let host = url.host, !host.isEmpty {
                channel.name = host
                return
            }
        }
        channel.name = "Kanal \(channelsCount + 1)"
    }

    private static func collectNoGroupSample(_ diag: inout ParseDiagnostics, channel: ParsedM3UChannel, rawExtinf: String) {
        guard diag.sampleNoGroup.count < 20 else { return }
        let hasGroup = !(channel.groupTitle?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        if hasGroup { return }
        diag.sampleNoGroup.append(NoGroupSample(rawExtinf: rawExtinf, name: channel.name, url: channel.url))
    }
}
