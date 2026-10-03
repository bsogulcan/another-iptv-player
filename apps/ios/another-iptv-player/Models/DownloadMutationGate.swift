import Foundation

/// Serialises download enqueue/delete/start operations across their suspension points.
/// Waiting suspends the caller without blocking the main thread. Cancelled waiters
/// still acquire the gate and must release it; cancellation never permits overlap.
@MainActor
final class DownloadMutationGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !occupied {
            occupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        precondition(occupied)
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
