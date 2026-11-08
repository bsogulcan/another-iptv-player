import Foundation

/// When the player writes the watch-history row, kept free of view state so it can be
/// unit-tested.
nonisolated enum PlayerWatchHistoryPolicy {
    /// Periodic save while a film or episode plays. A crash or force-quit loses at most
    /// this much of the resume position.
    static let periodicIntervalSeconds: TimeInterval = 10
    /// A playhead move of at least this much between two clock ticks is a seek. Normal
    /// progress is a few hundred milliseconds per tick, also at 2x.
    static let seekJumpThresholdMs: Int64 = 3_000
    /// How long the playhead has to stay put after a jump before the position is saved.
    static let seekSettleSeconds: TimeInterval = 1

    /// False for the first tick of an item (`previousMs == nil`): there is nothing to
    /// compare it with, and a start position is not a seek.
    static func isSeekJump(previousMs: Int64?, currentMs: Int64) -> Bool {
        guard let previousMs else { return false }
        return abs(currentMs - previousMs) >= seekJumpThresholdMs
    }
}
