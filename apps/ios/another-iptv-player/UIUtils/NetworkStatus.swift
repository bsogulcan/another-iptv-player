import Foundation
import Combine
import Network

/// Tells the app when the network has come back, so that something which failed
/// while it was away can be tried again without a tap.
///
/// It publishes a counter and nothing else, on purpose. Whether the path is
/// "satisfied" says little about whether a request will succeed: a panel on the
/// local network answers without internet, and a captive portal reports a usable
/// path that reaches nothing. So there is no `isOnline` to read, and no user action
/// may be refused because of what the path says. The only use is a retry trigger:
///
///     .onReceive(NetworkStatus.shared.$reconnectCount.dropFirst()) { _ in
///         if errorMessage != nil { Task { await load() } }
///     }
///
/// Subscribing this way keeps a view's body independent of the object, so a path
/// change re-renders nothing.
@MainActor
final class NetworkStatus: ObservableObject {
    /// The monitor starts with the first access.
    static let shared: NetworkStatus = {
        let status = NetworkStatus()
        status.startMonitoring()
        return status
    }()

    /// +1 each time the path goes from unsatisfied to satisfied, about a second
    /// after the transition. The first path the monitor reports is the state at
    /// launch, not a reconnect, and does not count.
    @Published private(set) var reconnectCount = 0

    /// How long a path has to stay satisfied before it counts. "Satisfied" arrives
    /// before the link is usable (address, DNS), so a retry fired at once would
    /// often fail again and leave the error on screen.
    private let settleDelay: Duration
    /// The app is assumed to start connected: only a path that was seen
    /// unsatisfied can come back.
    private var isSatisfied = true
    private var pendingReconnect: Task<Void, Never>?
    private var monitor: NWPathMonitor?

    /// The app uses `shared`. Tests build their own instance, which watches no real
    /// path, and feed it through `pathChanged(isSatisfied:)`.
    init(settleDelay: Duration = .seconds(1)) {
        self.settleDelay = settleDelay
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        // Delivered on the main queue: path updates are rare, and it keeps them in
        // the order the system reported them.
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            MainActor.assumeIsolated {
                self?.pathChanged(isSatisfied: satisfied)
            }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    /// One path update. Internal for the unit tests.
    func pathChanged(isSatisfied satisfied: Bool) {
        guard satisfied != isSatisfied else { return }
        isSatisfied = satisfied
        pendingReconnect?.cancel()
        pendingReconnect = nil
        guard satisfied else { return }
        pendingReconnect = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            // Cancelled when the path dropped again while this was waiting.
            guard !Task.isCancelled, let self else { return }
            self.pendingReconnect = nil
            self.reconnectCount += 1
        }
    }
}
