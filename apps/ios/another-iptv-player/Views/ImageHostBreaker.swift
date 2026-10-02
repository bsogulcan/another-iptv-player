import Foundation
import Nuke
import Observation

/// Thrown instead of starting a download for a host the breaker has blocked. It is a type
/// of its own so that these short-circuits are never mistaken for a failure of the host.
nonisolated struct ImageHostBlocked: Error, Equatable {
    let host: String

    /// Whether an image load failed because the breaker refused it, as opposed to the
    /// host or the image being at fault.
    static func isCause(of error: any Error) -> Bool {
        (error as? ImagePipeline.Error)?.dataLoadingError is ImageHostBlocked
    }
}

/// Circuit breaker for image hosts that stopped answering.
///
/// Playlists often point their logos at a server that no longer exists. A host that drops
/// packets keeps one of the pipeline's shared download slots busy until the request times
/// out, and every cell that comes back on screen asks again, so healthy images wait behind
/// requests that can never finish. After `failureThreshold` different URLs of one host
/// have timed out in a row, the host is blocked for `blockWindow` seconds: its requests
/// fail at once and give their slot back.
///
/// Rules that keep it from doing more harm than good:
/// - Only timeouts of a host that sent nothing count. A host that refuses the connection
///   or cannot be resolved fails fast and costs no slot, and a download that was
///   receiving bytes when it ran out of time is a slow link, not a dead host. Hosts are
///   told apart by name and port.
/// - A timeout is counted once per URL, however many image tasks waited on that download
///   (a cell and a prefetch usually share one).
/// - The window is fixed when the host trips. Failures that arrive later do not extend it.
/// - When the window is over, exactly one request is let through as a probe. An answer
///   closes the breaker, and so does a failure that came back fast; another timeout
///   blocks the host for one more window.
/// - Nothing trips while several hosts are timing out together: that is what a weak or
///   captive network looks like, and blocking every host would hide all images for a
///   while after the connection is back.
///
/// A refused request is not queued anywhere, so whoever asked has to ask again. The
/// recording methods say when that is worth doing (`Change.reopened`).
///
/// The caller passes the time in, as seconds on any monotonic clock, so the state machine
/// has no clock of its own. All methods are safe to call from any thread.
nonisolated final class ImageHostBreaker: @unchecked Sendable {
    nonisolated struct Policy: Equatable, Sendable {
        /// Different URLs of one host that must time out in a row before it is blocked.
        var failureThreshold = 3
        /// How long a tripped host stays blocked. Longer than the pipeline's resource
        /// timeout, so requests that were already in flight are over before the probe.
        var blockWindow: TimeInterval = 30
        /// This many hosts with a recent timeout mean the network, not the hosts.
        var outbreakHostCount = 3
        /// How far back a timeout counts as recent for `outbreakHostCount`.
        var outbreakInterval: TimeInterval = 30
    }

    /// What a finished image task says about its host.
    nonisolated enum Outcome: Equatable, Sendable {
        /// The request ran out of time without a single byte from the host.
        case timedOut
        /// Bytes came back: an image, an HTTP error, or data that would not decode.
        case answered
        /// Failed before the host could answer (no route, DNS, TLS, connection refused).
        /// Such a failure comes back at once, so the host is not holding a slot.
        case failedFast
        /// Cancelled, or out of time in the middle of a download. Says nothing either way.
        case inconclusive
        /// Served from a pipeline cache or refused by the breaker itself.
        case ignored
    }

    /// What a recorded result means for the requests the breaker has refused.
    nonisolated enum Change: Equatable, Sendable {
        case none
        /// A block window started for the host.
        case blocked
        /// A request of the host that was refused would get through now: the host is open
        /// again, or the probe ended without a verdict and the next request takes its place.
        case reopened
    }

    let policy: Policy

    private struct HostState {
        /// URLs that timed out since the host last answered. Never grows past the threshold.
        var timedOutURLs: Set<String> = []
        var lastTimeoutAt: TimeInterval = 0
        /// Non-nil while the host is blocked; stays set after expiry until a probe settles it.
        var blockedUntil: TimeInterval?
        var probeURL: String?
        var probeStartedAt: TimeInterval = 0
    }

    private let lock = NSLock()
    private var hosts: [String: HostState] = [:]

    init(policy: Policy = Policy()) {
        self.policy = policy
    }

    // MARK: - State machine

    /// Whether a download of `url` from `host` may start now. Returns `true` for the probe
    /// of an expired block and remembers it, so the next caller is refused until the probe
    /// has finished.
    func allowsLoad(host: String, url: String, now: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var state = hosts[host], let blockedUntil = state.blockedUntil else { return true }
        guard now >= blockedUntil else { return false }
        if let probeURL = state.probeURL, probeURL != url,
           now - state.probeStartedAt < policy.blockWindow {
            return false
        }
        // A probe that never reported back is replaced after one more window, so a lost
        // event cannot keep the host blocked for good.
        state.probeURL = url
        state.probeStartedAt = now
        hosts[host] = state
        return true
    }

    /// Returns `true` when this timeout started a block window for the host.
    @discardableResult
    func recordTimeout(host: String, url: String, now: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var state = hosts[host] ?? HostState()
        if state.blockedUntil != nil {
            // Only the probe can re-block. Anything else is a request that was already in
            // flight when the host tripped, and must not extend the window.
            guard state.probeURL == url else { return false }
            state.blockedUntil = now + policy.blockWindow
            state.probeURL = nil
            state.lastTimeoutAt = now
            hosts[host] = state
            return true
        }
        if state.timedOutURLs.count < policy.failureThreshold {
            state.timedOutURLs.insert(url)
        }
        state.lastTimeoutAt = now
        hosts[host] = state
        guard state.timedOutURLs.count >= policy.failureThreshold else { return false }
        let failingHosts = hosts.values.reduce(into: 0) { count, other in
            if now - other.lastTimeoutAt <= policy.outbreakInterval { count += 1 }
        }
        guard failingHosts < policy.outbreakHostCount else { return false }
        state.blockedUntil = now + policy.blockWindow
        state.timedOutURLs.removeAll()
        hosts[host] = state
        return true
    }

    /// The host produced an answer: forget everything held against it. Returns `true`
    /// when that ended a block.
    @discardableResult
    func recordAnswer(host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hosts.removeValue(forKey: host)?.blockedUntil != nil
    }

    /// A probe that failed fast shows the host no longer keeps requests waiting, which is
    /// all the block was for. Returns `true` when that ended a block. From any other
    /// request it changes nothing: the timeouts before it still stand.
    @discardableResult
    func recordFastFailure(host: String, url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let state = hosts[host], state.blockedUntil != nil, state.probeURL == url else { return false }
        hosts[host] = nil
        return true
    }

    /// A probe that ended without an answer or a timeout proves nothing, so the next
    /// request becomes the probe. Returns `true` when `url` was the probe.
    @discardableResult
    func recordInconclusive(host: String, url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var state = hosts[host], state.probeURL == url else { return false }
        state.probeURL = nil
        hosts[host] = state
        return true
    }

    /// Forgets every host. Called when the app returns to the foreground and when the
    /// network path changes: what was learned on the old connection says nothing about
    /// the new one. Returns `true` when a host was blocked.
    @discardableResult
    func reset() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let hadBlockedHost = hosts.values.contains { $0.blockedUntil != nil }
        hosts.removeAll()
        return hadBlockedHost
    }

    // MARK: - Pipeline events

    /// `receivedBytes` is whether the task saw any part of the download. A request and a
    /// resource timeout are the same error, and only the first kind, with nothing
    /// received, is a host that does not answer.
    static func outcome(
        of result: Result<ImageResponse, ImagePipeline.Error>,
        receivedBytes: Bool = false
    ) -> Outcome {
        switch result {
        case .success(let response):
            // A memory or disk hit never reached the host.
            return response.cacheType == nil ? .answered : .ignored
        case .failure(.cancelled):
            return .inconclusive
        case .failure(.dataLoadingFailed(let error)):
            if error is ImageHostBlocked { return .ignored }
            // Anything that is not a transport error is the loader rejecting a response
            // it received, such as an HTTP status outside 2xx.
            guard let urlError = error as? URLError else { return .answered }
            switch urlError.code {
            case .timedOut: return receivedBytes ? .inconclusive : .timedOut
            case .cancelled: return .inconclusive
            default: return .failedFast
            }
        case .failure(.dataIsEmpty), .failure(.decodingFailed), .failure(.processingFailed),
             .failure(.dataDownloadExceededMaximumSize):
            // Data arrived, so the host is alive even though the image is unusable.
            return .answered
        case .failure:
            return .ignored
        }
    }

    /// Feeds the result of a finished image task for `url` into the state machine and
    /// says what that changed for the host.
    @discardableResult
    func record(
        _ result: Result<ImageResponse, ImagePipeline.Error>,
        receivedBytes: Bool = false,
        for url: URL,
        now: TimeInterval
    ) -> Change {
        guard let host = Self.hostKey(for: url) else { return .none }
        let address = url.absoluteString
        switch Self.outcome(of: result, receivedBytes: receivedBytes) {
        case .timedOut:
            return recordTimeout(host: host, url: address, now: now) ? .blocked : .none
        case .answered:
            return recordAnswer(host: host) ? .reopened : .none
        case .failedFast:
            return recordFastFailure(host: host, url: address) ? .reopened : .none
        case .inconclusive:
            return recordInconclusive(host: host, url: address) ? .reopened : .none
        case .ignored:
            return .none
        }
    }

    /// Lower-cased host plus the port when the URL names one: two ports of one machine are
    /// often two servers. A URL without a host (file, data) is never tracked.
    static func hostKey(for url: URL) -> String? {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        let name = host.lowercased()
        return url.port.map { "\(name):\($0)" } ?? name
    }
}

/// Tells image cells that a request the breaker refused is worth making again.
///
/// A refused request fails at once and is not queued, so without this its cell stays a
/// placeholder until it is scrolled away and back, even though the host may be open
/// again a moment later. Only a cell in that state reads `epoch` in its body, so a change
/// updates those cells and no others.
@Observable
final class ImageHostReopenings {
    static let shared = ImageHostReopenings()

    private(set) var epoch = 0

    func advance() {
        epoch &+= 1
    }

    /// For the pipeline's hooks, which do not run on the main actor.
    nonisolated static func announce() {
        Task { @MainActor in shared.advance() }
    }
}
