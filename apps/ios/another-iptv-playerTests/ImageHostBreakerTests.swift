import Foundation
import Nuke
import Testing
import UIKit
@testable import another_iptv_player

/// The breaker's state machine. Time is passed in, so nothing here waits or reads a clock.
@Suite("ImageHostBreaker")
struct ImageHostBreakerTests {
    private let host = "logos.example.com"
    private let policy = ImageHostBreaker.Policy(
        failureThreshold: 3, blockWindow: 30, outbreakHostCount: 3, outbreakInterval: 30
    )

    private func url(_ index: Int, host: String = "logos.example.com") -> String {
        "http://\(host)/logo-\(index).png"
    }

    /// A breaker whose host tripped at `now`, on URLs 0, 1 and 2.
    private func trippedBreaker(at now: TimeInterval) -> ImageHostBreaker {
        let breaker = ImageHostBreaker(policy: policy)
        for index in 0..<policy.failureThreshold {
            breaker.recordTimeout(host: host, url: url(index), now: now)
        }
        return breaker
    }

    // MARK: - Threshold

    @Test
    func staysClosedBelowTheThreshold() {
        let breaker = ImageHostBreaker(policy: policy)
        #expect(breaker.allowsLoad(host: host, url: url(0), now: 0))
        breaker.recordTimeout(host: host, url: url(0), now: 1)
        breaker.recordTimeout(host: host, url: url(1), now: 2)
        #expect(breaker.allowsLoad(host: host, url: url(2), now: 3))
    }

    @Test
    func reportsTheTimeoutThatTripsTheHost() {
        let breaker = ImageHostBreaker(policy: policy)
        #expect(!breaker.recordTimeout(host: host, url: url(0), now: 0))
        #expect(!breaker.recordTimeout(host: host, url: url(1), now: 0))
        #expect(breaker.recordTimeout(host: host, url: url(2), now: 0))
        // Stragglers of a blocked host report nothing new; a failed probe does.
        #expect(!breaker.recordTimeout(host: host, url: url(3), now: 5))
        #expect(breaker.allowsLoad(host: host, url: url(4), now: 30))
        #expect(breaker.recordTimeout(host: host, url: url(4), now: 40))
    }

    @Test
    func blocksOnceTheThresholdIsReached() {
        let breaker = trippedBreaker(at: 10)
        #expect(!breaker.allowsLoad(host: host, url: url(5), now: 10))
        #expect(!breaker.allowsLoad(host: host, url: url(0), now: 25))
        // Other hosts are not affected.
        #expect(breaker.allowsLoad(host: "posters.example.com", url: url(5, host: "posters.example.com"), now: 10))
    }

    @Test
    func aURLCountsOnceHoweverManyTasksWaitedOnIt() {
        // A cell and a prefetch share one download and both report its failure.
        let breaker = ImageHostBreaker(policy: policy)
        for step in 0..<6 {
            breaker.recordTimeout(host: host, url: url(0), now: TimeInterval(step))
        }
        breaker.recordTimeout(host: host, url: url(1), now: 6)
        breaker.recordTimeout(host: host, url: url(1), now: 7)
        #expect(breaker.allowsLoad(host: host, url: url(2), now: 8))
        breaker.recordTimeout(host: host, url: url(2), now: 9)
        #expect(!breaker.allowsLoad(host: host, url: url(3), now: 9))
    }

    @Test
    func anAnswerStartsTheCountAgain() {
        let breaker = ImageHostBreaker(policy: policy)
        breaker.recordTimeout(host: host, url: url(0), now: 0)
        breaker.recordTimeout(host: host, url: url(1), now: 1)
        breaker.recordAnswer(host: host)
        breaker.recordTimeout(host: host, url: url(2), now: 2)
        breaker.recordTimeout(host: host, url: url(3), now: 3)
        #expect(breaker.allowsLoad(host: host, url: url(4), now: 4))
        breaker.recordTimeout(host: host, url: url(4), now: 5)
        #expect(!breaker.allowsLoad(host: host, url: url(5), now: 5))
    }

    // MARK: - Fixed window

    @Test
    func laterFailuresDoNotExtendTheWindow() {
        let breaker = trippedBreaker(at: 10)
        // Requests that were already in flight when the host tripped time out afterwards.
        breaker.recordTimeout(host: host, url: url(7), now: 20)
        breaker.recordTimeout(host: host, url: url(8), now: 30)
        breaker.recordTimeout(host: host, url: url(9), now: 39)
        #expect(!breaker.allowsLoad(host: host, url: url(20), now: 39.9))
        #expect(breaker.allowsLoad(host: host, url: url(20), now: 40))
    }

    @Test
    func refusedRequestsDoNotExtendTheWindow() {
        let breaker = trippedBreaker(at: 0)
        for step in 1..<30 {
            #expect(!breaker.allowsLoad(host: host, url: url(100 + step), now: TimeInterval(step)))
        }
        #expect(breaker.allowsLoad(host: host, url: url(200), now: 30))
    }

    // MARK: - Probe

    @Test
    func oneProbeIsLetThroughAfterTheWindow() {
        let breaker = trippedBreaker(at: 0)
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 30))
        #expect(!breaker.allowsLoad(host: host, url: url(12), now: 45))
        // The probe itself may be asked for again.
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 31))
    }

    @Test
    func anAnsweringProbeClosesTheBreaker() {
        let breaker = trippedBreaker(at: 0)
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        breaker.recordAnswer(host: host)
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 31))
        #expect(breaker.allowsLoad(host: host, url: url(12), now: 31))
        // And the count starts from nothing.
        breaker.recordTimeout(host: host, url: url(11), now: 32)
        breaker.recordTimeout(host: host, url: url(12), now: 32)
        #expect(breaker.allowsLoad(host: host, url: url(13), now: 33))
    }

    @Test
    func aProbeThatTimesOutBlocksForOneMoreWindow() {
        let breaker = trippedBreaker(at: 0)
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        breaker.recordTimeout(host: host, url: url(10), now: 40)
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 41))
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 69.9))
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 70))
        #expect(!breaker.allowsLoad(host: host, url: url(12), now: 70))
    }

    @Test
    func aLateFailureDuringTheProbeIsNotTheProbeFailing() {
        let breaker = trippedBreaker(at: 0)
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        breaker.recordTimeout(host: host, url: url(7), now: 31)
        // Still waiting for the probe, and no new window was started: once the probe ends
        // without a verdict the next request goes through right away.
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 32))
        breaker.recordInconclusive(host: host, url: url(10))
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 33))
    }

    @Test
    func anInconclusiveProbeHandsOverToTheNextRequest() {
        let breaker = trippedBreaker(at: 0)
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        // Someone else's cancellation changes nothing.
        breaker.recordInconclusive(host: host, url: url(99))
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 31))
        breaker.recordInconclusive(host: host, url: url(10))
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 31))
        #expect(!breaker.allowsLoad(host: host, url: url(12), now: 31))
    }

    @Test
    func aProbeThatNeverReportsIsReplacedAfterOneWindow() {
        let breaker = trippedBreaker(at: 0)
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 59.9))
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 60))
        #expect(!breaker.allowsLoad(host: host, url: url(12), now: 60))
    }

    // MARK: - Reopening

    @Test
    func requestsRefusedDuringAProbeGoThroughOnceItAnswers() throws {
        let breaker = trippedBreaker(at: 0)
        let probe = try #require(URL(string: url(10)))
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 31))
        // The rest of the screen asks while the probe is still in flight.
        for index in 11..<30 {
            #expect(!breaker.allowsLoad(host: host, url: url(index), now: 31))
        }
        // The answer is reported, which is the cue to ask again, and then all get through.
        #expect(breaker.record(.success(response(cacheType: nil)), for: probe, now: 31.2) == .reopened)
        for index in 11..<30 {
            #expect(breaker.allowsLoad(host: host, url: url(index), now: 31.2))
        }
    }

    @Test
    func onlyTheEndOfABlockIsReportedAsReopening() throws {
        let breaker = ImageHostBreaker(policy: policy)
        let addresses = try (0..<5).map { try #require(URL(string: url($0))) }
        let downloaded: TaskResult = .success(response(cacheType: nil))
        let timedOut: TaskResult = .failure(.dataLoadingFailed(error: URLError(.timedOut)))

        // Nobody was refused, so an answer changes nothing for anyone.
        #expect(breaker.record(downloaded, for: addresses[0], now: 0) == .none)
        #expect(!breaker.recordAnswer(host: host))

        #expect(breaker.record(timedOut, for: addresses[0], now: 1) == .none)
        #expect(breaker.record(timedOut, for: addresses[1], now: 1) == .none)
        #expect(breaker.record(timedOut, for: addresses[2], now: 1) == .blocked)
        // A straggler timing out inside the window is neither a new block nor an opening.
        #expect(breaker.record(timedOut, for: addresses[3], now: 5) == .none)
        // One that still got its image shows the host is alive.
        #expect(breaker.record(downloaded, for: addresses[4], now: 6) == .reopened)
        #expect(breaker.allowsLoad(host: host, url: url(20), now: 6))
        #expect(breaker.allowsLoad(host: host, url: url(21), now: 6))
    }

    @Test
    func aProbeThatFailsFastClosesTheBreaker() throws {
        let breaker = trippedBreaker(at: 0)
        let connectionRefused: TaskResult = .failure(.dataLoadingFailed(error: URLError(.cannotConnectToHost)))
        let straggler = try #require(URL(string: url(7)))
        let probe = try #require(URL(string: url(10)))

        // From a request that is not the probe it says nothing about the block.
        #expect(breaker.record(connectionRefused, for: straggler, now: 10) == .none)
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 29))

        // The probe came back at once: the host no longer keeps a slot waiting.
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        #expect(breaker.record(connectionRefused, for: probe, now: 30.1) == .reopened)
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 30.1))
        #expect(breaker.allowsLoad(host: host, url: url(12), now: 30.1))
    }

    @Test
    func aFastFailureDoesNotClearTimeoutsOfAnOpenHost() {
        let breaker = ImageHostBreaker(policy: policy)
        breaker.recordTimeout(host: host, url: url(0), now: 0)
        breaker.recordTimeout(host: host, url: url(1), now: 1)
        #expect(!breaker.recordFastFailure(host: host, url: url(2)))
        breaker.recordTimeout(host: host, url: url(3), now: 2)
        #expect(!breaker.allowsLoad(host: host, url: url(4), now: 2))
    }

    @Test
    func aCancelledProbeIsReportedSoAnotherRequestTakesOver() throws {
        let breaker = trippedBreaker(at: 0)
        let cancelled: TaskResult = .failure(.cancelled)
        let probe = try #require(URL(string: url(10)))
        let other = try #require(URL(string: url(11)))
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        #expect(breaker.record(cancelled, for: other, now: 30) == .none)
        #expect(breaker.record(cancelled, for: probe, now: 30) == .reopened)
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 30))
        #expect(!breaker.allowsLoad(host: host, url: url(12), now: 30))
    }

    @Test
    func aProbeThatTimesOutIsReportedAsANewBlock() throws {
        let breaker = trippedBreaker(at: 0)
        let timedOut: TaskResult = .failure(.dataLoadingFailed(error: URLError(.timedOut)))
        let probe = try #require(URL(string: url(10)))
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 30))
        #expect(breaker.record(timedOut, for: probe, now: 40) == .blocked)
        #expect(!breaker.allowsLoad(host: host, url: url(11), now: 69.9))
    }

    @Test
    func resetReportsWhetherAHostWasBlocked() {
        let breaker = ImageHostBreaker(policy: policy)
        #expect(!breaker.reset())
        breaker.recordTimeout(host: host, url: url(0), now: 0)
        #expect(!breaker.reset())

        let tripped = trippedBreaker(at: 0)
        #expect(tripped.reset())
        #expect(!tripped.reset())
    }

    @Test
    func aRefusalIsToldApartFromOtherFailures() {
        let refused = ImagePipeline.Error.dataLoadingFailed(error: ImageHostBlocked(host: host))
        let timedOut = ImagePipeline.Error.dataLoadingFailed(error: URLError(.timedOut))
        #expect(ImageHostBlocked.isCause(of: refused))
        #expect(!ImageHostBlocked.isCause(of: timedOut))
        #expect(!ImageHostBlocked.isCause(of: ImagePipeline.Error.cancelled))
        #expect(!ImageHostBlocked.isCause(of: URLError(.timedOut)))
    }

    // MARK: - Connectivity guards

    @Test
    func nothingTripsWhileSeveralHostsTimeOutTogether() {
        let breaker = ImageHostBreaker(policy: policy)
        let hosts = ["a.example.com", "b.example.com", "c.example.com"]
        var now: TimeInterval = 0
        for index in 0..<4 {
            for name in hosts {
                breaker.recordTimeout(host: name, url: url(index, host: name), now: now)
                now += 1
            }
        }
        for name in hosts {
            #expect(breaker.allowsLoad(host: name, url: url(50, host: name), now: now), "\(name)")
        }
        // Once the others went quiet, the host that is still timing out trips at once.
        breaker.recordTimeout(host: "a.example.com", url: url(60, host: "a.example.com"), now: 100)
        #expect(!breaker.allowsLoad(host: "a.example.com", url: url(61, host: "a.example.com"), now: 100))
        #expect(breaker.allowsLoad(host: "b.example.com", url: url(61, host: "b.example.com"), now: 100))
    }

    @Test
    func twoDeadHostsAreStillBlocked() {
        let breaker = ImageHostBreaker(policy: policy)
        for index in 0..<3 {
            breaker.recordTimeout(host: "a.example.com", url: url(index, host: "a.example.com"), now: 0)
            breaker.recordTimeout(host: "b.example.com", url: url(index, host: "b.example.com"), now: 0)
        }
        #expect(!breaker.allowsLoad(host: "a.example.com", url: url(9, host: "a.example.com"), now: 1))
        #expect(!breaker.allowsLoad(host: "b.example.com", url: url(9, host: "b.example.com"), now: 1))
    }

    @Test
    func resetForgetsEveryHost() {
        let breaker = trippedBreaker(at: 0)
        #expect(!breaker.allowsLoad(host: host, url: url(10), now: 1))
        breaker.reset()
        #expect(breaker.allowsLoad(host: host, url: url(10), now: 1))
        #expect(breaker.allowsLoad(host: host, url: url(11), now: 1))
        // Nothing of the old streak is left either.
        breaker.recordTimeout(host: host, url: url(10), now: 2)
        #expect(breaker.allowsLoad(host: host, url: url(12), now: 3))
    }

    // MARK: - Pipeline results

    private typealias TaskResult = Result<ImageResponse, ImagePipeline.Error>

    private func response(cacheType: ImageResponse.CacheType?) -> ImageResponse {
        ImageResponse(
            container: ImageContainer(image: UIImage()),
            request: ImageRequest(url: URL(string: url(0))),
            cacheType: cacheType
        )
    }

    @Test
    func onlyATimeoutCountsAgainstAHost() {
        let timedOut: TaskResult = .failure(.dataLoadingFailed(error: URLError(.timedOut)))
        // URLSession hands the same error over as an NSError.
        let bridged: TaskResult = .failure(
            .dataLoadingFailed(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        )
        #expect(ImageHostBreaker.outcome(of: timedOut) == .timedOut)
        #expect(ImageHostBreaker.outcome(of: bridged) == .timedOut)

        // Failures that come back at once hold no slot.
        let unresolved: TaskResult = .failure(.dataLoadingFailed(error: URLError(.cannotFindHost)))
        let refused: TaskResult = .failure(.dataLoadingFailed(error: URLError(.cannotConnectToHost)))
        let offline: TaskResult = .failure(.dataLoadingFailed(error: URLError(.notConnectedToInternet)))
        for result in [unresolved, refused, offline] {
            #expect(ImageHostBreaker.outcome(of: result) == .failedFast)
        }

        let cancelledLoad: TaskResult = .failure(.dataLoadingFailed(error: URLError(.cancelled)))
        let cancelledTask: TaskResult = .failure(.cancelled)
        for result in [cancelledLoad, cancelledTask] {
            #expect(ImageHostBreaker.outcome(of: result) == .inconclusive)
        }
    }

    @Test
    func aTimeoutAfterBytesArrivedIsNotHeldAgainstTheHost() throws {
        // The resource timeout of a download that was under way is the same error.
        let timedOut: TaskResult = .failure(.dataLoadingFailed(error: URLError(.timedOut)))
        #expect(ImageHostBreaker.outcome(of: timedOut, receivedBytes: false) == .timedOut)
        #expect(ImageHostBreaker.outcome(of: timedOut, receivedBytes: true) == .inconclusive)

        let breaker = ImageHostBreaker(policy: policy)
        for index in 0..<10 {
            let address = try #require(URL(string: url(index)))
            #expect(breaker.record(timedOut, receivedBytes: true, for: address, now: TimeInterval(index)) == .none)
        }
        #expect(breaker.allowsLoad(host: host, url: url(50), now: 10))

        // As a probe it neither closes the breaker nor starts another window: the next
        // request takes over.
        let tripped = trippedBreaker(at: 0)
        let probe = try #require(URL(string: url(10)))
        #expect(tripped.allowsLoad(host: host, url: url(10), now: 30))
        #expect(tripped.record(timedOut, receivedBytes: true, for: probe, now: 50) == .reopened)
        #expect(tripped.allowsLoad(host: host, url: url(11), now: 50))
        #expect(!tripped.allowsLoad(host: host, url: url(12), now: 50))
    }

    @Test
    func aResponseOfAnyKindIsAnAnswer() {
        let notFound: TaskResult = .failure(
            .dataLoadingFailed(error: DataLoader.Error.statusCodeUnacceptable(404))
        )
        let empty: TaskResult = .failure(.dataIsEmpty)
        let downloaded: TaskResult = .success(response(cacheType: nil))
        #expect(ImageHostBreaker.outcome(of: notFound) == .answered)
        #expect(ImageHostBreaker.outcome(of: empty) == .answered)
        #expect(ImageHostBreaker.outcome(of: downloaded) == .answered)
    }

    @Test
    func cacheHitsAndTheBreakersOwnRefusalsSayNothing() {
        let refused: TaskResult = .failure(.dataLoadingFailed(error: ImageHostBlocked(host: host)))
        let fromMemory: TaskResult = .success(response(cacheType: .memory))
        let fromDisk: TaskResult = .success(response(cacheType: .disk))
        let notCached: TaskResult = .failure(.dataMissingInCache)
        for result in [refused, fromMemory, fromDisk, notCached] {
            #expect(ImageHostBreaker.outcome(of: result) == .ignored)
        }
    }

    @Test
    func refusedRequestsAreNotCountedAsFailures() throws {
        let breaker = ImageHostBreaker(policy: policy)
        let refused: TaskResult = .failure(.dataLoadingFailed(error: ImageHostBlocked(host: host)))
        for index in 0..<10 {
            let address = try #require(URL(string: url(index)))
            breaker.record(refused, for: address, now: TimeInterval(index))
        }
        #expect(breaker.allowsLoad(host: host, url: url(50), now: 10))

        // Nor do they keep a tripped host blocked: the window still ends when it was set to.
        let tripped = trippedBreaker(at: 0)
        for index in 0..<10 {
            let address = try #require(URL(string: url(20 + index)))
            tripped.record(refused, for: address, now: 5 + TimeInterval(index))
        }
        #expect(!tripped.allowsLoad(host: host, url: url(50), now: 29.9))
        #expect(tripped.allowsLoad(host: host, url: url(50), now: 30))
    }

    @Test
    func resultsAreFiledUnderHostAndPort() throws {
        let breaker = ImageHostBreaker(policy: policy)
        let timedOut: TaskResult = .failure(.dataLoadingFailed(error: URLError(.timedOut)))
        for index in 0..<3 {
            let address = try #require(URL(string: "http://Panel.Example.com:8080/logos/\(index).png"))
            breaker.record(timedOut, for: address, now: TimeInterval(index))
        }
        #expect(!breaker.allowsLoad(host: "panel.example.com:8080", url: "http://panel.example.com:8080/x.png", now: 3))
        #expect(breaker.allowsLoad(host: "panel.example.com", url: "http://panel.example.com/x.png", now: 3))

        // A cached copy served while the host is blocked does not reopen it; a download does.
        let address = try #require(URL(string: "http://panel.example.com:8080/logos/9.png"))
        breaker.record(.success(response(cacheType: .disk)), for: address, now: 4)
        #expect(!breaker.allowsLoad(host: "panel.example.com:8080", url: "http://panel.example.com:8080/x.png", now: 4))
        breaker.record(.success(response(cacheType: nil)), for: address, now: 5)
        #expect(breaker.allowsLoad(host: "panel.example.com:8080", url: "http://panel.example.com:8080/x.png", now: 5))
    }

    @Test
    func theHostKeyIgnoresCaseAndKeepsThePort() throws {
        let plain = try #require(URL(string: "HTTPS://Logos.Example.com/a.png"))
        let withPort = try #require(URL(string: "http://logos.example.com:8080/a.png"))
        let file = URL(fileURLWithPath: "/tmp/a.png")
        #expect(ImageHostBreaker.hostKey(for: plain) == "logos.example.com")
        #expect(ImageHostBreaker.hostKey(for: withPort) == "logos.example.com:8080")
        #expect(ImageHostBreaker.hostKey(for: file) == nil)
    }
}

// MARK: - Through the pipeline

/// What a stubbed host does with one request.
private nonisolated enum StubReply: Sendable {
    case image(Data)
    case failure(URLError.Code)
    /// The first bytes of the image arrive, then the download fails.
    case stalled(Data, URLError.Code)
    /// The image arrives once the test calls `StubDataLoader.releaseHeld()`.
    case held(Data)
}

/// Answers image requests from a closure and remembers what it was asked for.
private nonisolated final class StubDataLoader: DataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var held: [@Sendable () -> Void] = []
    private let reply: @Sendable (URL) -> StubReply

    init(reply: @escaping @Sendable (URL) -> StubReply) {
        self.reply = reply
    }

    convenience init(respond: @escaping @Sendable (URL) -> Result<Data, any Error>) {
        self.init { url in
            switch respond(url) {
            case .success(let data): return .image(data)
            case .failure(let error): return .failure((error as? URLError)?.code ?? .unknown)
            }
        }
    }

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    var heldCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return held.count
    }

    /// Lets every held request finish with its image.
    func releaseHeld() {
        lock.lock()
        let pending = held
        held.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable ((any Error)?) -> Void
    ) -> any Cancellable {
        let url = request.url ?? URL(fileURLWithPath: "/")
        lock.lock()
        urls.append(url)
        lock.unlock()
        func response(for data: Data) -> URLResponse {
            URLResponse(url: url, mimeType: "image/png", expectedContentLength: data.count, textEncodingName: nil)
        }
        switch reply(url) {
        case .image(let data):
            didReceiveData(data, response(for: data))
            completion(nil)
        case .failure(let code):
            completion(URLError(code))
        case .stalled(let data, let code):
            didReceiveData(data.prefix(64), response(for: data))
            completion(URLError(code))
        case .held(let data):
            let urlResponse = response(for: data)
            lock.lock()
            held.append {
                didReceiveData(data, urlResponse)
                completion(nil)
            }
            lock.unlock()
        }
        return StubCancellable()
    }
}

/// A clock and a counter the pipeline's hooks may touch from any thread.
private nonisolated final class HookProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var count = 0

    var now: TimeInterval {
        get { lock.withLock { time } }
        set { lock.withLock { time = newValue } }
    }

    var reopenings: Int { lock.withLock { count } }

    func noteReopening() {
        lock.withLock { count += 1 }
    }
}

private nonisolated struct StubCancellable: Cancellable {
    func cancel() {}
}

/// The pipeline the app installs, around a stub loader: no network, no shared state.
@Suite("Image pipeline hooks")
struct ImagePipelineHookTests {
    private static func makePNG(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func request(_ string: String) throws -> ImageRequest {
        CachedImage.request(
            url: try #require(URL(string: string)),
            width: 50, height: 75, contentMode: .fill, loadProfile: .grid
        )
    }

    /// The error a load ends with, or nil when it produced an image.
    private func failure(of request: ImageRequest, in pipeline: ImagePipeline) async -> ImagePipeline.Error? {
        do {
            _ = try await pipeline.imageTask(with: request).response
            return nil
        } catch {
            return error
        }
    }

    /// Polls a condition that becomes true off the main actor, for at most three seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test
    func aHostThatKeepsTimingOutIsRefusedBeforeTheLoader() async throws {
        let png = Self.makePNG(width: 400, height: 600)
        let loader = StubDataLoader { url in
            url.host() == "dead.example.com" ? .failure(URLError(.timedOut)) : .success(png)
        }
        let pipeline = IPTVRemoteImagePipeline.makePipeline(
            dataLoader: loader,
            imageCache: nil,
            thumbnailCache: nil,
            hostBreaker: ImageHostBreaker(
                policy: .init(failureThreshold: 3, blockWindow: 30, outbreakHostCount: 3, outbreakInterval: 30)
            )
        )

        for index in 0..<3 {
            let error = await failure(of: try request("http://dead.example.com/\(index).png"), in: pipeline)
            #expect(error?.dataLoadingError is URLError)
        }
        #expect(loader.requestedURLs.count == 3)

        // The fourth request never reaches the loader, so it cannot hold a download slot.
        let refused = await failure(of: try request("http://dead.example.com/3.png"), in: pipeline)
        #expect(refused?.dataLoadingError is ImageHostBlocked)
        #expect(loader.requestedURLs.count == 3)

        // A healthy host on the same pipeline is untouched.
        let healthy = await failure(of: try request("http://live.example.com/0.png"), in: pipeline)
        #expect(healthy == nil)
        #expect(loader.requestedURLs.count == 4)
    }

    @Test
    func requestsRefusedDuringAProbeLoadOnceTheHostReopens() async throws {
        let png = Self.makePNG(width: 400, height: 600)
        let hook = HookProbe()
        // The host is dead until the clock passes 30 and holds its first answer after
        // that, the way a probe is in flight while the rest of a screen asks.
        let loader = StubDataLoader { url in
            if hook.now < 30 { return .failure(.timedOut) }
            return url.lastPathComponent == "probe.png" ? .held(png) : .image(png)
        }
        let pipeline = IPTVRemoteImagePipeline.makePipeline(
            dataLoader: loader,
            imageCache: nil,
            thumbnailCache: nil,
            hostBreaker: ImageHostBreaker(
                policy: .init(failureThreshold: 3, blockWindow: 30, outbreakHostCount: 3, outbreakInterval: 30)
            ),
            hostReopened: { hook.noteReopening() },
            uptime: { hook.now }
        )

        for index in 0..<3 {
            _ = await failure(of: try request("http://slow.example.com/\(index).png"), in: pipeline)
        }
        let duringTheWindow = await failure(of: try request("http://slow.example.com/3.png"), in: pipeline)
        #expect(duringTheWindow?.dataLoadingError is ImageHostBlocked)
        #expect(loader.requestedURLs.count == 3)

        // The window is over. The first request is the probe and is still in flight
        // when the next one arrives.
        hook.now = 31
        let probeRequest = try request("http://slow.example.com/probe.png")
        let cellRequest = try request("http://slow.example.com/4.png")
        let probe = Task { await failure(of: probeRequest, in: pipeline) }
        let probeIsInFlight = await eventually { loader.heldCount == 1 }
        #expect(probeIsInFlight)

        let duringTheProbe = await failure(of: cellRequest, in: pipeline)
        #expect(duringTheProbe?.dataLoadingError is ImageHostBlocked)
        #expect(hook.reopenings == 0)

        // The probe answers: that is announced exactly once, and the request that was
        // refused loads when it is made again.
        loader.releaseHeld()
        let probeError = await probe.value
        #expect(probeError == nil)
        #expect(hook.reopenings == 1)
        let afterReopening = await failure(of: cellRequest, in: pipeline)
        #expect(afterReopening == nil)
        #expect(loader.requestedURLs.count == 5)
        #expect(hook.reopenings == 1)
    }

    @Test
    func aDownloadThatStallsHalfwayIsNotHeldAgainstTheHost() async throws {
        let png = Self.makePNG(width: 400, height: 600)
        let loader = StubDataLoader { url in
            url.lastPathComponent == "ok.png" ? .image(png) : .stalled(png, .timedOut)
        }
        let pipeline = IPTVRemoteImagePipeline.makePipeline(
            dataLoader: loader,
            imageCache: nil,
            thumbnailCache: nil,
            hostBreaker: ImageHostBreaker(
                policy: .init(failureThreshold: 3, blockWindow: 30, outbreakHostCount: 3, outbreakInterval: 30)
            )
        )

        // Bytes were arriving each time: a slow link, not a host that does not answer.
        for index in 0..<5 {
            let error = await failure(of: try request("http://slow.example.com/\(index).png"), in: pipeline)
            #expect((error?.dataLoadingError as? URLError)?.code == .timedOut)
        }
        #expect(loader.requestedURLs.count == 5)
        let sixth = await failure(of: try request("http://slow.example.com/ok.png"), in: pipeline)
        #expect(sixth == nil)
        #expect(loader.requestedURLs.count == 6)
    }

    @Test
    func thumbnailsGoToDiskAndOriginalsDoNot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-thumbnails-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let png = Self.makePNG(width: 400, height: 600)
        let loader = StubDataLoader { _ in .success(png) }
        let disk = try DataCache(path: directory)
        let pipeline = IPTVRemoteImagePipeline.makePipeline(
            dataLoader: loader, imageCache: nil, thumbnailCache: disk, hostBreaker: ImageHostBreaker()
        )
        let address = "http://img.example.com/poster.png"
        let thumbnailRequest = try request(address)

        let image = try await pipeline.imageTask(with: thumbnailRequest).response.image
        // Decoded at the requested size, not at 400 x 600.
        let scale = CachedImage.decodeScale(for: .grid)
        let pixelWidth = CGFloat(image.cgImage?.width ?? 0)
        let pixelHeight = CGFloat(image.cgImage?.height ?? 0)
        #expect(abs(pixelWidth - 50 * scale) <= 1)
        #expect(abs(pixelHeight - 75 * scale) <= 1)

        // The thumbnail is encoded after the image was delivered.
        let stored = await eventually { pipeline.cache.containsData(for: thumbnailRequest) }
        #expect(stored)
        #expect(!pipeline.cache.containsData(for: ImageRequest(url: URL(string: address))))
        disk.flush()

        // A relaunch with nothing in memory and no network still shows the image.
        let offline = StubDataLoader { _ in .failure(URLError(.notConnectedToInternet)) }
        let relaunched = IPTVRemoteImagePipeline.makePipeline(
            dataLoader: offline,
            imageCache: nil,
            thumbnailCache: try DataCache(path: directory),
            hostBreaker: ImageHostBreaker()
        )
        let cached = try await relaunched.imageTask(with: thumbnailRequest).response.image
        #expect(cached.cgImage?.width == image.cgImage?.width)
        #expect(cached.cgImage?.height == image.cgImage?.height)
        #expect(offline.requestedURLs.isEmpty)
    }
}
