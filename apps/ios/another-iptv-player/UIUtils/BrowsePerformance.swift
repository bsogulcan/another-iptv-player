import os

/// Async intervals measure time to result, not time spent on the main thread.
/// Names contain no playlist, account, query or programme data.
nonisolated enum BrowsePerformance {
    private static let signposter = OSSignposter(subsystem: "dev.ogos.another-iptv-player", category: .pointsOfInterest)

    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
