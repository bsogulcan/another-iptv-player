import Combine
import Foundation
import Testing
@testable import another_iptv_player

/// `NetworkStatus` counts reconnects from the path updates it is fed. These
/// instances watch no real path.
@Suite("Network status")
struct NetworkStatusTests {

    /// Waits for `condition`, for at most two seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test
    func theFirstSatisfiedPathIsNotAReconnect() async throws {
        let status = NetworkStatus(settleDelay: .milliseconds(10))

        status.pathChanged(isSatisfied: true)
        status.pathChanged(isSatisfied: true)
        try await Task.sleep(for: .milliseconds(80))

        #expect(status.reconnectCount == 0)
    }

    @Test
    func aPathThatComesBackCountsOnceAfterTheDelay() async throws {
        let status = NetworkStatus(settleDelay: .milliseconds(30))

        status.pathChanged(isSatisfied: false)
        #expect(status.reconnectCount == 0)
        status.pathChanged(isSatisfied: true)
        // Not at the transition itself: the link is not usable yet.
        #expect(status.reconnectCount == 0)

        #expect(await eventually { status.reconnectCount == 1 })
        // Further reports of the same state change nothing.
        status.pathChanged(isSatisfied: true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(status.reconnectCount == 1)

        status.pathChanged(isSatisfied: false)
        status.pathChanged(isSatisfied: true)
        #expect(await eventually { status.reconnectCount == 2 })
    }

    /// A path that drops again before it settled never was usable.
    @Test
    func aPathThatDropsAgainBeforeItSettlesDoesNotCount() async throws {
        let status = NetworkStatus(settleDelay: .milliseconds(150))

        status.pathChanged(isSatisfied: false)
        status.pathChanged(isSatisfied: true)
        status.pathChanged(isSatisfied: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(status.reconnectCount == 0)

        status.pathChanged(isSatisfied: true)
        #expect(await eventually { status.reconnectCount == 1 })
    }

    @Test
    func subscribersSeeOnlyReconnects() async throws {
        let status = NetworkStatus(settleDelay: .milliseconds(10))
        var received: [Int] = []
        let subscription = status.$reconnectCount.dropFirst().sink { received.append($0) }
        defer { subscription.cancel() }

        status.pathChanged(isSatisfied: true)
        status.pathChanged(isSatisfied: false)
        #expect(received.isEmpty)
        status.pathChanged(isSatisfied: true)

        #expect(await eventually { received == [1] })
    }
}
