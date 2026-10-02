import Foundation

/// Decides whether a saved watch position is still worth resuming from.
/// A finished item is stored at ~100 % of its duration; resuming there replays the last
/// seconds, ends at once and (for series) cascades through auto-advance. Returning nil
/// makes the caller start from the beginning instead.
enum WatchResume {
    enum Kind {
        /// Series episode.
        case episode
        /// Film, or any other non-episodic VOD item.
        case film
    }

    /// Positions at or below this count as "not started" (same bound PlayerView applies).
    static let minimumPositionMs = 5_000
    /// Must stay equal to the "Watched" label threshold of the episode list, otherwise a
    /// row labelled Watched would still resume inside its credits.
    static let episodeFinishedFraction = 0.95
    /// An episode this close to its end has nothing left worth resuming.
    static let episodeTailMs = 30_000
    /// Films keep a tighter bound: 95 % of a two-hour film is still six minutes before the end.
    static let filmFinishedFraction = 0.98

    /// Resume position in milliseconds, or nil when playback should start from the beginning.
    /// `durationMs <= 0` means the duration is unknown; only the lower bound applies then.
    static func positionMs(lastTimeMs: Int, durationMs: Int, kind: Kind) -> Int? {
        guard lastTimeMs > minimumPositionMs else { return nil }
        guard durationMs > 0 else { return lastTimeMs }
        let progress = Double(lastTimeMs) / Double(durationMs)
        switch kind {
        case .episode:
            if progress >= episodeFinishedFraction { return nil }
            if durationMs - lastTimeMs <= episodeTailMs { return nil }
        case .film:
            if progress >= filmFinishedFraction { return nil }
        }
        return lastTimeMs
    }
}

extension DBWatchHistory {
    /// See `WatchResume.positionMs(lastTimeMs:durationMs:kind:)`.
    func resumePositionMs(as kind: WatchResume.Kind) -> Int? {
        WatchResume.positionMs(lastTimeMs: lastTimeMs, durationMs: durationMs, kind: kind)
    }
}
