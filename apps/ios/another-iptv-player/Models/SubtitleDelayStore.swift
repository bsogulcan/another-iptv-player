import Foundation

/// Subtitle time offset per content (`ImportedSubtitleStore.contentKey`).
///
/// The offset used to live inside the global subtitle style, so a value tuned for one
/// badly timed file kept shifting the subtitles of every later film and channel. It is
/// stored here by content instead; anything without an entry plays at 0.
enum SubtitleDelayStore {
    /// Bounds of the offset, the same the offset slider uses.
    static let range: ClosedRange<Double> = -10...10
    /// Entries kept. Beyond this the least recently changed ones are dropped, so the
    /// dictionary cannot grow without limit in UserDefaults.
    static let maxEntries = 300

    private static let key = "playback.subtitleDelayByContent.v1"
    /// Below this an offset is "none": the slider's stepped values are not exact decimals.
    private static let zeroTolerance = 0.0005

    static func clamp(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, range.lowerBound), range.upperBound)
    }

    /// Stored offset for the content, or 0 when there is none.
    static func delaySeconds(for contentKey: String, defaults: UserDefaults = .standard) -> Double {
        guard let seconds = entries(in: defaults)[contentKey]?.first else { return 0 }
        return clamp(seconds)
    }

    /// Remembers the offset for the content. 0 removes the entry.
    static func setDelaySeconds(
        _ seconds: Double,
        for contentKey: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var map = entries(in: defaults)
        let clamped = clamp(seconds)
        if abs(clamped) < zeroTolerance {
            guard map.removeValue(forKey: contentKey) != nil else { return }
        } else {
            map[contentKey] = [clamped, now.timeIntervalSinceReferenceDate]
            let overflow = map.count - maxEntries
            if overflow > 0 {
                let oldest = map
                    .sorted { ($0.value.last ?? 0) < ($1.value.last ?? 0) }
                    .prefix(overflow)
                for entry in oldest { map.removeValue(forKey: entry.key) }
            }
        }
        defaults.set(map, forKey: key)
    }

    /// Playlist deleted: drops the offsets of all its content, the same way
    /// `ImportedSubtitleStore.removeAll(playlistId:)` drops its files. Without this the
    /// entries of a deleted playlist would only leave through the `maxEntries` eviction.
    static func removeAll(playlistId: UUID, defaults: UserDefaults = .standard) {
        let prefix = ImportedSubtitleStore.contentKeyPrefix(playlistId: playlistId)
        var map = entries(in: defaults)
        let orphanKeys = map.keys.filter { $0.hasPrefix(prefix) }
        guard !orphanKeys.isEmpty else { return }
        for orphan in orphanKeys { map.removeValue(forKey: orphan) }
        defaults.set(map, forKey: key)
    }

    /// Number of stored entries (for tests and diagnostics).
    static func entryCount(defaults: UserDefaults = .standard) -> Int {
        entries(in: defaults).count
    }

    /// Content key → [offset seconds, time of the last change]. The timestamp only
    /// orders the entries for eviction.
    private static func entries(in defaults: UserDefaults) -> [String: [Double]] {
        (defaults.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
    }
}
