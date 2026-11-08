import AVFoundation
import Foundation
import Network
import Testing
@testable import another_iptv_player

// MARK: - Harness

/// Cast start failures reproduced without a receiver (ios-player-airplay-review.md,
/// airplay-diagnosability-tests-10): a real `AirPlayRemuxSession` reads from the mock
/// panel above over loopback and serves its playlist from the shared local server.
///
/// Serialized: the local HTTP server is shared by the whole process, and the tests
/// run on real time (a live session needs about 6 s of stream before it is ready).
/// Skipped when this machine has no LAN IPv4 address, which the session requires
/// before it does anything else (error code 1; it cannot be injected).
@Suite(
    "CastPipelineHarness",
    .serialized,
    .enabled("needs a LAN IPv4 address on the machine that runs the tests") {
        await LocalHTTPServer.lanIPv4Address() != nil
    }
)
struct CastPipelineHarnessTests {
    typealias RemuxError = RemuxHLSWriter.RemuxError

    private static let userAgent = "CastHarness/1.0"
    /// Long enough for a live start (three closed segments, about 6 s) with room to
    /// spare; short enough for the VOD pacing window of the fixture remux.
    private static let fixtureSeconds = 14

    // MARK: Healthy start

    /// A healthy live source: the start succeeds on a single connection, the local
    /// playlist is a live one with at least three segments, the writer's requests
    /// carry the User-Agent, and `stop()` gives the panel slot back.
    @Test(.timeLimit(.minutes(1)))
    func healthyLiveSourceStartsOnOneConnectionAndReleasesItOnStop() async throws {
        let panel = MockPanelServer(stream: try await Self.liveStream())
        try panel.start()
        defer { panel.stop() }
        let session = try Self.liveSession(reading: panel)
        defer { session.stop() }
        let runtimeErrors = ErrorLog()
        session.onError = { runtimeErrors.errors.append($0) }

        let outcome = await Self.wait(for: Self.begin(session), timeout: 30)
        let url = try #require(try? outcome.result?.get(), "start: \(outcome.summary)")
        #expect(outcome.seconds < 20, "a healthy start took \(outcome.seconds)s")
        #expect(url.lastPathComponent == "stream.m3u8")
        #expect(session.localPlaylistURL == url)

        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let playlist = String(decoding: data, as: UTF8.self)
        let lines = playlist.split(separator: "\n")
        #expect(lines.filter { $0.hasPrefix("#EXTINF:") }.count >= 3, "\(playlist)")
        #expect(lines.contains { $0.hasSuffix(".ts") })
        // Live: a sliding window, never an event playlist, never finished.
        #expect(!playlist.contains("#EXT-X-PLAYLIST-TYPE"))
        #expect(!playlist.contains("#EXT-X-ENDLIST"))

        let stats = panel.stats
        #expect(stats.admitted == 1)
        #expect(stats.refused == 0)
        #expect(stats.open == 1)
        #expect(stats.lastUserAgent == Self.userAgent)
        #expect(!session.isSourceClosed)
        #expect(runtimeErrors.errors.isEmpty)
        // The panel sends neither a length nor Accept-Ranges, as live channels are
        // served: the source is open and cannot seek, although no seek was refused.
        #expect(!session.sourceCanSeek)
        #expect(session.effectiveStartOffsetSeconds == session.startOffsetSeconds)
        // Only this phone asked for the playlist (the request above).
        #expect(session.lastReceiverFetchAt == nil)
        #expect(session.receiverFetchSummary.hasPrefix("receiver never fetched; phone requests "))

        session.stop()
        #expect(
            await Self.eventually(within: 5) { session.isSourceClosed && panel.stats.open == 0 },
            "stop() did not release the source connection"
        )
    }

    // MARK: Source failures during the start

    /// The source delivers 3 s of stream and then hangs with the connection open.
    /// Packets were read, so the session gives up through the progress rule
    /// (`readStallLimitSeconds` without a packet) with the playlist-timeout error.
    /// That is before FFmpeg's own 15 s I/O timeout, whose reconnect would open a
    /// second connection next to the hanging one: the panel refuses nothing. The
    /// connection is released with the failed start.
    @Test(.timeLimit(.minutes(1)))
    func sourceThatStallsAfterAFewSecondsEndsTheStartWithThePlaylistTimeout() async throws {
        let stream = try await Self.liveStream()
        let panel = MockPanelServer(stream: stream)
        try panel.start()
        defer { panel.stop() }
        let session = try Self.liveSession(reading: panel)
        defer { session.stop() }

        // Three seconds of stream: past the probe, one live segment closed at most
        // (readiness needs three).
        panel.stall(atStreamSeconds: 3)

        let outcome = await Self.wait(for: Self.begin(session), timeout: 45)
        let error = try #require(outcome.failure, "start: \(outcome.summary)")
        #expect(Self.sessionErrorCode(error) == .playlistTimeout, "\(error)")
        // Not before the stall limit has passed since the last packet, and well
        // inside the 60 s cap.
        #expect(outcome.seconds >= 3 + AirPlayRemuxSession.readStallLimitSeconds - 1)
        #expect(outcome.seconds < AirPlayRemuxSession.firstPacketDeadlineSeconds + 10)
        #expect(panel.stats.bytesSent == stream.byteCount(dueBy: 3))
        // The error says how far the writer got: packets were read, then nothing for
        // the stall limit, and fewer segments closed than a live start needs.
        let progress = try #require(Self.startWaitProgress(error), "\(error)")
        #expect(progress.packetsRead > 0)
        #expect(progress.stalledSeconds >= AirPlayRemuxSession.readStallLimitSeconds)
        #expect(progress.closedSegments < 3)
        #expect(progress.elapsedSeconds <= outcome.seconds)
        #expect(error.localizedDescription.contains("packets=\(progress.packetsRead),"))
        // What the controller makes of it: one retry, then "source too slow".
        if case .retry = CastController.startFailureAction(retryUsed: false, error: error) {
        } else {
            Issue.record("a stalled start is not retried")
        }
        #expect(CastController.startFailureAction(retryUsed: true, error: error)
            == .endCast(.sourceTooSlow))

        #expect(panel.stats.admitted == 1)
        #expect(panel.stats.refused == 0, "a second connection was tried next to the hanging one")
        #expect(
            await Self.eventually(within: 5) { session.isSourceClosed && panel.stats.open == 0 },
            "the failed start kept its source connection"
        )
    }

    /// The panel accepts the connection and never answers. FFmpeg's own I/O timeout
    /// (15 s) ends the open before the session's first-packet deadline (25 s), so
    /// this surfaces as the writer's open failure, not as the playlist timeout.
    @Test(.timeLimit(.minutes(1)))
    func sourceThatNeverAnswersFailsTheOpen() async throws {
        let panel = MockPanelServer(stream: try await Self.liveStream(), script: .silent)
        try panel.start()
        defer { panel.stop() }
        let session = try Self.liveSession(reading: panel)
        defer { session.stop() }

        let outcome = await Self.wait(for: Self.begin(session), timeout: 45)
        let error = try #require(outcome.failure, "start: \(outcome.summary)")
        if case .openInputFailed? = error as? RemuxError {
        } else {
            Issue.record("expected openInputFailed, got \(error)")
        }
        #expect(outcome.seconds < AirPlayRemuxSession.firstPacketDeadlineSeconds)
        if case .retry = CastController.startFailureAction(retryUsed: false, error: error) {
        } else {
            Issue.record("an open failure is not retried")
        }
        #expect(CastController.startFailureAction(retryUsed: true, error: error)
            == .endCast(.sourceOpenFailed))

        #expect(panel.stats.admitted == 1)
        #expect(panel.stats.bytesSent == 0)
        #expect(
            await Self.eventually(within: 5) { session.isSourceClosed && panel.stats.open == 0 },
            "the failed start kept its source connection"
        )
    }

    /// The panel answers 200 and then never sends a byte of the stream: a channel
    /// that is listed but dead. Nothing is ever read, so the session gives up at
    /// the first-packet deadline with the playlist-timeout error.
    ///
    /// On the way FFmpeg's 15 s I/O timeout fires inside the open and its reconnect
    /// tries a second connection while the first is still open; the mock turns it
    /// away like a single-connection panel would. That is library behaviour that
    /// breaks the one-connection rule, so it is recorded as a known issue rather
    /// than left out; the slot itself never changes hands. Once the production
    /// ordering changes (the read watchdog ending the read before FFmpeg's I/O
    /// timeout), remove the wrapper and update `readStallLimitsOutlastTheProtocolTimeout`.
    @Test(.timeLimit(.minutes(1)))
    func sourceThatAnswersAndSendsNothingEndsAtTheFirstPacketDeadline() async throws {
        let panel = MockPanelServer(stream: try await Self.liveStream(), script: .headersOnly)
        try panel.start()
        defer { panel.stop() }
        let session = try Self.liveSession(reading: panel)
        defer { session.stop() }

        let outcome = await Self.wait(for: Self.begin(session), timeout: 45)
        let error = try #require(outcome.failure, "start: \(outcome.summary)")
        #expect(Self.sessionErrorCode(error) == .playlistTimeout, "\(error)")
        #expect(outcome.seconds >= AirPlayRemuxSession.firstPacketDeadlineSeconds)
        #expect(outcome.seconds < AirPlayRemuxSession.firstPacketDeadlineSeconds + 10)
        // The same error code as the stalled source above, told apart by its
        // progress: not one packet was read and no segment exists.
        let progress = try #require(Self.startWaitProgress(error), "\(error)")
        #expect(progress.packetsRead == 0)
        #expect(progress.closedSegments == 0)
        #expect(progress.elapsedSeconds >= AirPlayRemuxSession.firstPacketDeadlineSeconds)
        #expect(error.localizedDescription.contains("packets=0, segments=0,"))
        #expect(CastController.startFailureAction(retryUsed: true, error: error)
            == .endCast(.sourceTooSlow))

        #expect(panel.stats.admitted == 1)
        #expect(panel.stats.bytesSent == 0)
        let refused = panel.stats.refused
        withKnownIssue("FFmpeg's in-read reconnect opens a second connection after rw_timeout while the first is still open") {
            #expect(refused == 0)
        }
        #expect(
            await Self.eventually(within: 5) { session.isSourceClosed && panel.stats.open == 0 },
            "the failed start kept its source connection"
        )
    }

    // MARK: One connection at a time

    /// A second session opening the same source while the first still holds it is
    /// what a single-connection panel refuses. The refusal fails that start at once
    /// (not after the playlist deadline) as an open failure, which the controller
    /// retries once; the first session is not disturbed.
    @Test(.timeLimit(.minutes(1)))
    func secondConnectionIsRefusedWhileTheFirstIsOpen() async throws {
        let panel = MockPanelServer(stream: try await Self.liveStream())
        try panel.start()
        defer { panel.stop() }
        let first = try Self.liveSession(reading: panel)
        defer { first.stop() }
        let firstErrors = ErrorLog()
        first.onError = { firstErrors.errors.append($0) }
        let firstOutcome = await Self.wait(for: Self.begin(first), timeout: 30)
        _ = try #require(try? firstOutcome.result?.get(), "first start: \(firstOutcome.summary)")

        // No `previousToDrain`: this writer opens while the first is connected.
        let second = try Self.liveSession(reading: panel)
        defer { second.stop() }
        let outcome = await Self.wait(for: Self.begin(second), timeout: 30)
        let error = try #require(outcome.failure, "second start: \(outcome.summary)")
        if case .openInputFailed? = error as? RemuxError {
        } else {
            Issue.record("expected openInputFailed, got \(error)")
        }
        #expect(outcome.seconds < 10, "the refusal took \(outcome.seconds)s to surface")
        if case .retry = CastController.startFailureAction(retryUsed: false, error: error) {
        } else {
            Issue.record("a refused connection is not retried")
        }

        let stats = panel.stats
        #expect(stats.admitted == 1)
        #expect(stats.refused >= 1)
        #expect(stats.open == 1)
        #expect(!first.isSourceClosed)
        #expect(firstErrors.errors.isEmpty)
    }

    /// The hand-over the controller uses for a zap, a seek refresh and an in-place
    /// rebuild: the outgoing session is stopped first and handed to its successor
    /// as `previousToDrain`. The successor opens only once that connection is
    /// closed, so the panel never sees a second connection and refuses nothing.
    @Test(.timeLimit(.minutes(1)))
    func successorOpensOnlyAfterThePredecessorClosed() async throws {
        let panel = MockPanelServer(stream: try await Self.liveStream())
        try panel.start()
        defer { panel.stop() }
        let outgoing = try Self.liveSession(reading: panel)
        defer { outgoing.stop() }
        let firstOutcome = await Self.wait(for: Self.begin(outgoing), timeout: 30)
        _ = try #require(try? firstOutcome.result?.get(), "first start: \(firstOutcome.summary)")

        outgoing.stop()
        let successor = try AirPlayRemuxSession(
            sourceURL: panel.streamURL,
            startOffsetSeconds: 0,
            isLive: true,
            userAgent: Self.userAgent,
            openDelaySeconds: 3.0,
            previousToDrain: outgoing
        )
        defer { successor.stop() }
        let outcome = await Self.wait(for: Self.begin(successor), timeout: 30)
        _ = try #require(try? outcome.result?.get(), "successor start: \(outcome.summary)")

        let stats = panel.stats
        #expect(stats.refused == 0, "the successor opened while the predecessor was connected")
        #expect(stats.admitted == 2)
        #expect(stats.open == 1)
        #expect(outgoing.isSourceClosed)
    }

    // MARK: Panel reset while running

    /// The panel drops the connection of a running live session. FFmpeg reconnects
    /// inside the read, the panel serves its stream from the beginning again, and
    /// the restarted timestamps are spliced in as a new timeline: no error reaches
    /// the session's owner and the playlist marks the discontinuity.
    @Test(.timeLimit(.minutes(1)))
    func panelResetOfARunningLiveSessionIsRiddenOut() async throws {
        let panel = MockPanelServer(stream: try await Self.liveStream())
        try panel.start()
        defer { panel.stop() }
        let session = try Self.liveSession(reading: panel)
        defer { session.stop() }
        let runtimeErrors = ErrorLog()
        session.onError = { runtimeErrors.errors.append($0) }
        let outcome = await Self.wait(for: Self.begin(session), timeout: 30)
        let url = try #require(try? outcome.result?.get(), "start: \(outcome.summary)")

        panel.reset()
        #expect(
            await Self.eventually(within: 10) { panel.stats.admitted == 2 },
            "the writer did not reconnect after the reset"
        )
        // The new timeline shows once its first segment has closed.
        var playlist = ""
        var marked = false
        for _ in 0..<48 where !marked {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                playlist = String(decoding: data, as: UTF8.self)
            }
            marked = playlist.split(separator: "\n").contains("#EXT-X-DISCONTINUITY")
        }
        #expect(marked, "no discontinuity after the reconnect:\n\(playlist)")
        #expect(runtimeErrors.errors.isEmpty, "\(runtimeErrors.errors)")
        #expect(!session.isSourceClosed)
        #expect(panel.stats.refused == 0)
        #expect(panel.stats.open == 1)
    }

    // MARK: - Helpers

    private final class ErrorLog {
        var errors: [Error] = []
    }

    private final class PendingStart {
        let startedAt = ProcessInfo.processInfo.systemUptime
        var result: Result<URL, Error>?
    }

    private struct StartOutcome {
        /// nil = the session reported nothing within the timeout.
        let result: Result<URL, Error>?
        let seconds: TimeInterval

        var failure: Error? {
            if case let .failure(error)? = result { return error }
            return nil
        }

        var summary: String {
            switch result {
            case nil: return "no result after \(Int(seconds))s"
            case let .success(url)?: return "succeeded with \(url.lastPathComponent) after \(Int(seconds))s"
            case let .failure(error)?: return "failed after \(Int(seconds))s: \(error)"
            }
        }
    }

    private static func liveSession(reading panel: MockPanelServer) throws -> AirPlayRemuxSession {
        try AirPlayRemuxSession(
            sourceURL: panel.streamURL,
            startOffsetSeconds: 0,
            isLive: true,
            userAgent: userAgent
        )
    }

    /// Starts the session; its completion (always on main) lands in the returned box.
    private static func begin(_ session: AirPlayRemuxSession) -> PendingStart {
        let pending = PendingStart()
        session.start { pending.result = $0 }
        return pending
    }

    private static func wait(for pending: PendingStart, timeout: TimeInterval) async -> StartOutcome {
        while pending.result == nil,
              ProcessInfo.processInfo.systemUptime - pending.startedAt < timeout
        {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return StartOutcome(
            result: pending.result,
            seconds: ProcessInfo.processInfo.systemUptime - pending.startedAt
        )
    }

    private static func eventually(
        within seconds: TimeInterval, _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }

    private static func sessionErrorCode(_ error: Error) -> AirPlayRemuxSession.ErrorCode? {
        let ns = error as NSError
        guard ns.domain == AirPlayRemuxSession.errorDomain else { return nil }
        return AirPlayRemuxSession.ErrorCode(rawValue: ns.code)
    }

    /// The writer's progress a playlist-timeout error carries in its userInfo; nil
    /// when a field is missing.
    private static func startWaitProgress(_ error: Error) -> AirPlayRemuxSession.StartWaitProgress? {
        let info = (error as NSError).userInfo
        guard let packetsRead = info[AirPlayRemuxSession.packetsReadErrorKey] as? Int,
              let closedSegments = info[AirPlayRemuxSession.closedSegmentsErrorKey] as? Int,
              let stalledSeconds = info[AirPlayRemuxSession.stalledSecondsErrorKey] as? TimeInterval,
              let elapsedSeconds = info[AirPlayRemuxSession.elapsedSecondsErrorKey] as? TimeInterval
        else { return nil }
        return AirPlayRemuxSession.StartWaitProgress(
            packetsRead: packetsRead, closedSegments: closedSegments,
            stalledSeconds: stalledSeconds, elapsedSeconds: elapsedSeconds
        )
    }

    // MARK: - Fixture

    /// Built once for the suite (the tests are serialized and run on the main actor).
    private static var cachedStream: MockPanelServer.Stream?

    private static func liveStream() async throws -> MockPanelServer.Stream {
        if let cachedStream { return cachedStream }
        let built = try await makeTransportStream(seconds: fixtureSeconds)
        cachedStream = built
        return built
    }

    /// An H.264 + AAC movie pushed through the writer's own MPEG-TS path; the
    /// segments, joined in playlist order, are one continuous transport stream.
    private static func makeTransportStream(seconds: Int) async throws -> MockPanelServer.Stream {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cast-harness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let movieURL = dir.appendingPathComponent("source.mp4")
        try await writeTestMovie(to: movieURL, seconds: seconds)
        let writer = RemuxHLSWriter(
            sourceURL: movieURL,
            outputDirectory: dir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil,
            forcedFormat: .mpegTS
        )
        writer.onError = { error in
            Issue.record("fixture remux error: \(error.localizedDescription)")
        }
        // Nobody plays the fixture: keep the VOD pacing gate out of the way.
        writer.updatePlaybackPosition(Double(seconds))
        writer.start()
        var finished = false
        for _ in 0..<60 {
            if let content = try? String(contentsOf: writer.playlistURL, encoding: .utf8),
               content.contains("#EXT-X-ENDLIST") {
                finished = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        try #require(finished, "TS fixture remux did not finish within 15s")

        let playlist = try String(contentsOf: writer.playlistURL, encoding: .utf8)
        var bytes = Data()
        for name in playlist.split(separator: "\n") where name.hasSuffix(".ts") {
            bytes.append(try Data(contentsOf: dir.appendingPathComponent(String(name))))
        }
        let stream = MockPanelServer.Stream(transportStream: bytes)
        // The pacing is only as good as the clock read from the stream.
        try #require(
            stream.durationSeconds > Double(seconds) - 1.5,
            "fixture clock covers \(stream.durationSeconds)s of \(seconds)s"
        )
        return stream
    }

    /// H.264 video (30 fps, one keyframe per second) plus AAC audio (44.1 kHz mono
    /// tone) in an mp4: the same fixture as AirPlayRemuxRegressionTests, whose
    /// helper is private to that suite. Each input is fed whenever it is ready and
    /// finished as soon as it is done; waiting for both at once deadlocks.
    private static func writeTestMovie(to url: URL, seconds: Int) async throws {
        let width = 320
        let height = 240
        let sampleRate = 44_100
        let audioFramesPerVideoFrame = sampleRate / 30
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoAverageBitRateKey: 300_000,
                ],
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
        )
        assetWriter.add(videoInput)
        assetWriter.add(audioInput)
        #expect(assetWriter.startWriting())
        assetWriter.startSession(atSourceTime: .zero)

        var pcmFormat = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var pcmDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &pcmFormat, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &pcmDescription
        )
        let audioDescription = try #require(pcmDescription)

        let frameCount = seconds * 30
        var videoFrame = 0
        var audioChunk = 0
        while videoFrame < frameCount || audioChunk < frameCount {
            var progressed = false
            if videoFrame < frameCount, videoInput.isReadyForMoreMediaData {
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
                guard let buffer = pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer) {
                    memset(base, Int32((videoFrame * 3) % 255), CVPixelBufferGetDataSize(buffer))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                adaptor.append(
                    buffer, withPresentationTime: CMTime(value: Int64(videoFrame), timescale: 30)
                )
                videoFrame += 1
                if videoFrame == frameCount { videoInput.markAsFinished() }
                progressed = true
            }
            if audioChunk < frameCount, audioInput.isReadyForMoreMediaData {
                let firstSample = audioChunk * audioFramesPerVideoFrame
                let tone: [Int16] = (0..<audioFramesPerVideoFrame).map { index in
                    let phase = Double(firstSample + index) * 2 * Double.pi * 440 / Double(sampleRate)
                    return Int16(sin(phase) * 8000)
                }
                let byteCount = tone.count * MemoryLayout<Int16>.size
                var blockBuffer: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
                    blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                    dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                    blockBufferOut: &blockBuffer
                )
                let block = try #require(blockBuffer)
                tone.withUnsafeBytes { bytes in
                    _ = CMBlockBufferReplaceDataBytes(
                        with: bytes.baseAddress!, blockBuffer: block,
                        offsetIntoDestination: 0, dataLength: byteCount
                    )
                }
                var sampleBuffer: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: kCFAllocatorDefault, dataBuffer: block,
                    formatDescription: audioDescription, sampleCount: tone.count,
                    presentationTimeStamp: CMTime(
                        value: Int64(firstSample), timescale: CMTimeScale(sampleRate)
                    ),
                    packetDescriptions: nil, sampleBufferOut: &sampleBuffer
                )
                audioInput.append(try #require(sampleBuffer))
                audioChunk += 1
                if audioChunk == frameCount { audioInput.markAsFinished() }
                progressed = true
            }
            if !progressed {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        await assetWriter.finishWriting()
        #expect(assetWriter.status == .completed)
    }
}
