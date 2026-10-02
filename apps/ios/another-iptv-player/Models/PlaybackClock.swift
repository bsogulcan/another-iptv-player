import Combine
import Foundation

/// Playback time of whatever is being presented (the engine, or the cast while one
/// presents). Owned by `VideoPlayerController` as a plain `let`, so the controller's own
/// observers (the player body, the mini card, the settings sheets) are not re-run by a
/// time tick: only a view that shows the time observes this object.
///
/// Main-thread state, like the controller that writes it.
final class PlaybackClock: ObservableObject {
    @Published private(set) var timeMs: Int64 = 0
    @Published private(set) var durationMs: Int64 = 0
    /// Played fraction, 0...1 (0 while the duration is unknown).
    @Published private(set) var position: Float = 0
    /// Buffered media ahead of the playhead, in seconds; 0 when unknown or when the
    /// picture is not played by the phone engine (a cast).
    @Published private(set) var cacheAheadSeconds: Double = 0

    /// One tick of the playhead. Every assignment is guarded: `@Published` announces
    /// a change even when the value is the same.
    func setPlayhead(timeMs newTimeMs: Int64, position newPosition: Float) {
        if timeMs != newTimeMs { timeMs = newTimeMs }
        if position != newPosition { position = newPosition }
    }

    func setDuration(_ newDurationMs: Int64) {
        if durationMs != newDurationMs { durationMs = newDurationMs }
    }

    /// Rounded to a tenth of a second: the scrubber draws it on a bar a few hundred
    /// points wide, and the raw value moves on every tick.
    func setCacheAhead(seconds: Double) {
        let rounded = Self.roundedCacheAhead(seconds)
        if cacheAheadSeconds != rounded { cacheAheadSeconds = rounded }
    }

    nonisolated static func roundedCacheAhead(_ seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return (seconds * 10).rounded() / 10
    }
}
