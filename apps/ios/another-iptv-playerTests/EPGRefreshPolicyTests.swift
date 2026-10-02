import Foundation
import Testing
@testable import another_iptv_player

/// When an automatic guide refresh is due: the six-hour TTL after a success and
/// the fifteen-minute cooldown after an attempt that did not succeed.
@Suite("EPG refresh policy")
struct EPGRefreshPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let playlistId = UUID()

    /// A source row with its dates given as "seconds before `now`".
    private func source(attempt: TimeInterval?, success: TimeInterval?, error: String? = nil) -> DBEPGSource {
        DBEPGSource(playlistId: playlistId, sourceType: EPGSourceType.xtreamXMLTV.rawValue,
                    fetchedAt: attempt.map { now.addingTimeInterval(-$0) },
                    lastSuccessAt: success.map { now.addingTimeInterval(-$0) },
                    lastError: error)
    }

    private func shouldRefresh(_ source: DBEPGSource?) -> Bool {
        EPGStore.shouldRefresh(source: source, now: now)
    }

    @Test
    func aGuideThatWasNeverFetchedIsDue() {
        #expect(shouldRefresh(nil))
        // A row without any date: created, never attempted.
        #expect(shouldRefresh(source(attempt: nil, success: nil)))
    }

    @Test
    func aFreshSuccessIsNotDue() {
        #expect(!shouldRefresh(source(attempt: 3_600, success: 3_600)))
        #expect(!shouldRefresh(source(attempt: 0, success: 0)))
        #expect(!shouldRefresh(source(attempt: EPGConstants.refreshTTL - 1, success: EPGConstants.refreshTTL - 1)))
    }

    @Test
    func aSuccessOlderThanTheTTLIsDue() {
        #expect(shouldRefresh(source(attempt: 7 * 3_600, success: 7 * 3_600)))
        #expect(shouldRefresh(source(attempt: EPGConstants.refreshTTL, success: EPGConstants.refreshTTL)))
    }

    @Test
    func aFirstAttemptThatFailedWaitsForTheCooldown() {
        #expect(!shouldRefresh(source(attempt: 5 * 60, success: nil, error: "HTTP 502")))
        #expect(!shouldRefresh(source(attempt: EPGConstants.retryCooldown - 1, success: nil, error: "HTTP 502")))
        #expect(shouldRefresh(source(attempt: 20 * 60, success: nil, error: "HTTP 502")))
        #expect(shouldRefresh(source(attempt: EPGConstants.retryCooldown, success: nil, error: "HTTP 502")))
    }

    /// The attempt is stamped when it starts. One that never reported back (the
    /// app was killed during the first download) waits like a failed one.
    @Test
    func aFirstAttemptWithoutAnOutcomeWaitsForTheCooldown() {
        #expect(!shouldRefresh(source(attempt: 5 * 60, success: nil)))
        #expect(shouldRefresh(source(attempt: 20 * 60, success: nil)))
    }

    /// The guide worked once, is past its TTL and now fails. Without the cooldown
    /// every opening of the playlist downloads it again.
    @Test
    func aFailureAfterAnEarlierSuccessWaitsForTheCooldown() {
        #expect(!shouldRefresh(source(attempt: 5 * 60, success: 7 * 3_600, error: "truncated")))
        #expect(shouldRefresh(source(attempt: 20 * 60, success: 7 * 3_600, error: "truncated")))
    }

    /// A stale guide whose last attempt left no error is simply due: there is no
    /// failure to back off from.
    @Test
    func aStaleGuideWithoutAnErrorIsDueWhateverTheLastAttemptTime() {
        #expect(shouldRefresh(source(attempt: 60, success: 7 * 3_600)))
    }

    /// A success clears the error, and the TTL alone decides again.
    @Test
    func theTTLOutranksAnErrorLeftFromBeforeTheLastSuccess() {
        #expect(!shouldRefresh(source(attempt: 60, success: 60, error: "stale text")))
    }
}
