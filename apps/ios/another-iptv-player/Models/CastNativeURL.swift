import Foundation

/// Experimental "native live cast" (off by default): on a live channel that plays
/// through the FFmpeg engine, AirPlay is handed the provider's own HLS output instead
/// of a stream remuxed on the phone. Nothing in the code can show that a panel's HLS
/// output plays on an Apple TV, so this stays behind a switch, is tried once per tap,
/// and a host it failed on is remembered so the next tap goes straight to the remux.
///
/// Everything here is a pure decision or a small UserDefaults record; the cast itself
/// is driven by `CastController`.
nonisolated enum CastNativeURL {
    /// UserDefaults switch (Bool, default false) behind the toggle in the developer
    /// section of the track settings sheet.
    static let enabledDefaultsKey = "player.airplayNativeLiveCastEnabled"

    // MARK: - HLS twin of a stream URL

    /// The URL AirPlay can be given instead of `url`, or nil when there is none.
    ///
    /// - A URL FFmpeg already reads as HLS is its own twin (an HLS link without a
    ///   recognised extension), unless it is a local file.
    /// - Xtream live shapes are rewritten to the panel's HLS output:
    ///   `scheme://host[:port]/user/pass/<digits>` (no extension),
    ///   `scheme://host[:port]/user/pass/<digits>.ts` and
    ///   `scheme://host[:port]/live/user/pass/<digits>.ts`
    ///   all become `scheme://host[:port]/live/user/pass/<digits>.m3u8`.
    /// - Anything else has no twin.
    ///
    /// The credentials are moved as they are (still percent-encoded), never decoded
    /// and re-encoded.
    static func hlsTwin(of url: URL, containerFormatName: String?) -> URL? {
        guard !url.isFileURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty
        else { return nil }
        if isHLSContainer(containerFormatName) { return url }
        // A query or fragment means this is not one of the plain Xtream shapes.
        guard components.percentEncodedQuery == nil, components.fragment == nil else { return nil }
        let segments = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        // An absolute path splits into "" followed by its segments; an empty segment
        // anywhere else is a double or trailing slash.
        guard segments.first == "", !segments.dropFirst().contains("") else { return nil }
        let parts = Array(segments.dropFirst())
        // [user, pass, file], optionally behind a leading "live" (then only with ".ts").
        let hasLivePrefix: Bool
        switch parts.count {
        case 3:
            hasLivePrefix = false
        case 4 where parts[0] == "live":
            hasLivePrefix = true
        default:
            return nil
        }
        let credentials = hasLivePrefix ? parts[1...2] : parts[0...1]
        guard let file = parts.last,
              let streamId = liveStreamId(fromFileName: file, extensionRequired: hasLivePrefix)
        else { return nil }
        components.percentEncodedPath =
            "/live/\(credentials.joined(separator: "/"))/\(streamId).m3u8"
        return components.url
    }

    /// FFmpeg's demuxer name for HLS (`KSOptions.formatName`); older builds report it
    /// as a comma-separated list.
    static func isHLSContainer(_ formatName: String?) -> Bool {
        guard let formatName else { return false }
        return formatName.lowercased()
            .split(separator: ",")
            .contains { $0 == "hls" || $0 == "applehttp" }
    }

    /// `<digits>` or `<digits>.ts`; nil for every other file name.
    private static func liveStreamId(fromFileName file: String, extensionRequired: Bool) -> String? {
        let pieces = file.split(separator: ".", omittingEmptySubsequences: false)
        let digits: Substring
        switch pieces.count {
        case 1 where !extensionRequired:
            digits = pieces[0]
        case 2 where pieces[1].lowercased() == "ts":
            digits = pieces[0]
        default:
            return nil
        }
        guard !digits.isEmpty, digits.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return String(digits)
    }

    // MARK: - Codec gate

    /// H.264 video with AAC, MP3, AC-3 or E-AC-3 audio: what an HLS stream may carry
    /// in MPEG-TS segments and an Apple TV decodes. HEVC stays on the remux path (HEVC
    /// in TS segments is outside Apple's HLS rules), and so does a stream whose audio
    /// codec is not known yet. Accepts FFmpeg codec names and the fourCC spellings.
    static func codecsAreNativelyCastable(video: String, audio: String) -> Bool {
        let videoName = baseCodecName(video)
        let audioName = baseCodecName(audio)
        return ["h264", "avc1"].contains(videoName)
            && ["aac", "mp4a", "mp3", ".mp3", "ac3", "ac-3", "eac3", "ec-3"].contains(audioName)
    }

    /// "h264 (High)" → "h264".
    private static func baseCodecName(_ raw: String) -> String {
        raw.lowercased().split(separator: " ").first.map(String.init) ?? ""
    }

    // MARK: - The whole decision

    /// The URL to cast natively for this AirPlay tap, or nil for the normal remux
    /// start. `avPlayerAlreadyTried`: the engine tried AVPlayer on `url` first and fell
    /// back to FFmpeg, so handing the same URL to another AVPlayer would only repeat
    /// that failure.
    static func candidate(
        enabled: Bool,
        isLive: Bool,
        isFFmpegBackendActive: Bool,
        avPlayerAlreadyTried: Bool,
        videoCodec: String,
        audioCodec: String,
        url: URL,
        containerFormatName: String?,
        failureRemembered: Bool
    ) -> URL? {
        guard enabled, isLive, isFFmpegBackendActive, !avPlayerAlreadyTried, !failureRemembered,
              codecsAreNativelyCastable(video: videoCodec, audio: audioCodec)
        else { return nil }
        return hlsTwin(of: url, containerFormatName: containerFormatName)
    }

    // MARK: - Remembered failures (per host)

    /// How long a host on which the native attempt failed is skipped.
    static let failureMemorySeconds: TimeInterval = 7 * 24 * 60 * 60
    /// Hosts kept; beyond this the oldest entries are dropped.
    static let maxRememberedHosts = 50

    private static let failuresDefaultsKey = "player.airplayNativeLiveCastFailures.v1"

    /// What a failure is remembered by: the host (and port, when the URL names one).
    /// Never the path, which carries the account's credentials.
    static func hostKey(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// Is a failure recorded at `failedAt` still remembered at `now`? A timestamp from
    /// the future (the clock was set back) counts as remembered until the window has
    /// passed on either side of it.
    static func isRemembered(failedAt: TimeInterval, now: Date) -> Bool {
        abs(now.timeIntervalSinceReferenceDate - failedAt) < failureMemorySeconds
    }

    /// The stored record after a failure of `hostKey` at `now`: expired entries
    /// dropped, the new one added, the oldest evicted beyond `maxRememberedHosts`.
    static func failures(
        _ stored: [String: Double], rememberingFailureOf hostKey: String, now: Date
    ) -> [String: Double] {
        var record = stored.filter { isRemembered(failedAt: $0.value, now: now) }
        record[hostKey] = now.timeIntervalSinceReferenceDate
        let overflow = record.count - maxRememberedHosts
        if overflow > 0 {
            for entry in record.sorted(by: { $0.value < $1.value }).prefix(overflow) {
                record.removeValue(forKey: entry.key)
            }
        }
        return record
    }

    static func rememberFailure(
        for url: URL, defaults: UserDefaults = .standard, now: Date = Date()
    ) {
        guard let key = hostKey(for: url) else { return }
        defaults.set(
            failures(storedFailures(in: defaults), rememberingFailureOf: key, now: now),
            forKey: failuresDefaultsKey
        )
    }

    static func hasRememberedFailure(
        for url: URL, defaults: UserDefaults = .standard, now: Date = Date()
    ) -> Bool {
        guard let key = hostKey(for: url), let failedAt = storedFailures(in: defaults)[key]
        else { return false }
        return isRemembered(failedAt: failedAt, now: now)
    }

    /// Forgets every remembered failure. The developer toggle calls this when it is
    /// switched on, which is the only way to try a host again before the week is over.
    static func forgetFailures(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: failuresDefaultsKey)
    }

    /// Host key → time of the failure (`timeIntervalSinceReferenceDate`).
    private static func storedFailures(in defaults: UserDefaults) -> [String: Double] {
        (defaults.dictionary(forKey: failuresDefaultsKey) as? [String: Double]) ?? [:]
    }
}
