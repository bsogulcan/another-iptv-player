import AVFoundation
import Foundation
import Testing
@testable import another_iptv_player

/// Regression locks for the remux findings of the AirPlay review
/// (ios-player-airplay-review.md, remux-hls-authoring-1/-2/-3/-7).
@Suite("AirPlayRemuxRegression")
struct AirPlayRemuxRegressionTests {

    @Test
    func vodPublicationKeepsMovingWhenReceiverClockStops() {
        var clock = RemuxHLSWriter.VODPacingClock()
        #expect(clock.limit(mediaSeconds: 0, playbackFloor: 0, uptime: 0) == 25)
        // Slow opening does not enlarge the initial burst.
        #expect(clock.limit(mediaSeconds: 25.1, playbackFloor: 0, uptime: 100) == 25)
        #expect(clock.limit(mediaSeconds: 27, playbackFloor: 0, uptime: 102) == 27)
        // Polling without elapsed time does not grant additional download credit.
        #expect(clock.limit(mediaSeconds: 28, playbackFloor: 0, uptime: 102) == 27)
        #expect(clock.limit(mediaSeconds: 40, playbackFloor: 0, uptime: 115) == 40)
    }

    @Test
    func vodPublicationUsesSeekOriginAndCatchesUpWithPlayback() {
        var clock = RemuxHLSWriter.VODPacingClock()
        #expect(clock.limit(mediaSeconds: 625.1, playbackFloor: 600, uptime: 10) == 625)
        #expect(clock.limit(mediaSeconds: 627, playbackFloor: 600, uptime: 12) == 627)
        #expect(clock.limit(mediaSeconds: 640, playbackFloor: 620, uptime: 13) == 645)
        // A delayed/backward player callback must not freeze publication again.
        #expect(clock.limit(mediaSeconds: 646, playbackFloor: 600, uptime: 14) == 646)
    }

    /// An AirPlay receiver can reload an EVENT playlist before advancing its
    /// playback clock. Both muxers must keep publishing beyond the initial 25 s
    /// buffer, otherwise the receiver rejects the stale playlist with -12888.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func eventPlaylistAdvancesWithoutPlaybackFeedback(fmp4: Bool) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-event-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let movieURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestMovie(to: movieURL, seconds: 40)
        let writer = RemuxHLSWriter(
            sourceURL: movieURL, outputDirectory: dir, startSeconds: 0,
            isLive: false, userAgent: nil, forcedFormat: fmp4 ? .fmp4 : .mpegTS
        )
        defer { writer.cancel() }
        writer.onError = { Issue.record("remux error: \($0.localizedDescription)") }
        writer.start()
        var publishedSeconds = 0.0
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let playlist = try? String(contentsOf: writer.playlistURL, encoding: .utf8) {
                publishedSeconds = playlist.split(separator: "\n")
                    .filter { $0.hasPrefix("#EXTINF:") }
                    .compactMap { Double($0.dropFirst(8).split(separator: ",")[0]) }
                    .reduce(0, +)
                if publishedSeconds > 26 { break }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        writer.cancel()
        for _ in 0..<50 where !writer.isClosed {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(writer.isClosed)
        if writer.isClosed { try? FileManager.default.removeItem(at: dir) }
        #expect(publishedSeconds > 26, "EVENT playlist stopped at \(publishedSeconds)s without playback feedback")
    }

    // MARK: - ADTS AAC into fMP4 (remux-hls-authoring-1)

    /// MPEG-TS carries AAC as ADTS frames without extradata. The fMP4 path (HEVC
    /// channels) used to die on the first audio packet with writeFailed(-1)
    /// ("Malformed AAC bitstream"); it now runs the audio through aac_adtstoasc.
    /// The fixture is made by the writer itself: an H.264 + AAC mp4 goes through the
    /// TS path, and one of the resulting .ts segments is the ADTS source.
    @Test(.timeLimit(.minutes(1)))
    func remuxesADTSAACFromMPEGTSIntoFMP4() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-adts-\(UUID().uuidString)", isDirectory: true)
        let tsDir = dir.appendingPathComponent("ts", isDirectory: true)
        let fmp4Dir = dir.appendingPathComponent("fmp4", isDirectory: true)
        try FileManager.default.createDirectory(at: tsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fmp4Dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let movieURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestMovie(to: movieURL, seconds: 8)

        let tsWriter = RemuxHLSWriter(
            sourceURL: movieURL,
            outputDirectory: tsDir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil
        )
        tsWriter.onError = { error in
            Issue.record("fixture remux error: \(error.localizedDescription)")
        }
        tsWriter.start()
        #expect(await Self.waitForEndList(tsWriter), "TS fixture remux did not finish within 10s")

        // The largest segment: the first one is cut short on purpose.
        let tsPlaylist = try String(contentsOf: tsWriter.playlistURL, encoding: .utf8)
        let tsSegments = tsPlaylist.split(separator: "\n")
            .filter { $0.hasSuffix(".ts") }
            .map { tsDir.appendingPathComponent(String($0)) }
        let sourceURL = try #require(
            tsSegments.max { Self.fileSize($0) < Self.fileSize($1) }
        )

        let writer = RemuxHLSWriter(
            sourceURL: sourceURL,
            outputDirectory: fmp4Dir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil,
            forcedFormat: .fmp4
        )
        writer.onError = { error in
            Issue.record("remux error: \(error.localizedDescription)")
        }
        writer.start()
        #expect(await Self.waitForEndList(writer), "fmp4 remux of ADTS AAC did not finish within 10s")
        #expect(writer.readProgress.packetsRead > 0)

        let playlist = (try? String(contentsOf: writer.playlistURL, encoding: .utf8)) ?? ""
        #expect(playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""))
        let segmentNames = playlist.split(separator: "\n").filter { $0.hasSuffix(".m4s") }
        #expect(!segmentNames.isEmpty)
        for name in segmentNames {
            #expect(Self.fileSize(fmp4Dir.appendingPathComponent(String(name))) > 500)
        }
        // The audio track must be in the init segment, with its AudioSpecificConfig
        // (the filter hands it over as side data on the first packet). This also
        // guards the fixture: without audio in the .ts there would be no 'mp4a'.
        let initData = (try? Data(contentsOf: fmp4Dir.appendingPathComponent("init.mp4"))) ?? Data()
        #expect(initData.range(of: Data("mp4a".utf8)) != nil, "init.mp4 has no AAC sample entry")
        // esds DecoderSpecificInfo: tag 0x05, length 2 (the two-byte AAC-LC config).
        #expect(
            initData.range(of: Data([0x05, 0x80, 0x80, 0x80, 0x02])) != nil,
            "init.mp4 has no AAC decoder config"
        )
    }

    // MARK: - Content-time pacing clock (remux-hls-authoring-3)

    /// A catch-up .ts whose first PTS is an hour in must pace as content time 0:
    /// with the raw value the writer sat past the 25 s pacing window forever.
    @Test
    func contentTimeSubtractsTheInputStartTime() {
        let hour: Int64 = 3600 * 1_000_000  // AVFormatContext.start_time, AV_TIME_BASE units
        #expect(RemuxHLSWriter.contentSeconds(containerSeconds: 3600, inputStartTime: hour) == 0)
        #expect(RemuxHLSWriter.contentSeconds(containerSeconds: 3612.5, inputStartTime: hour) == 12.5)
        // A seek to 10:00 lands on packets stamped start_time + 600.
        #expect(RemuxHLSWriter.contentSeconds(containerSeconds: 4200, inputStartTime: hour) == 600)
        // Fractional start (TS muxers start at ~1.4 s).
        let fractional = RemuxHLSWriter.contentSeconds(
            containerSeconds: 11.4, inputStartTime: 1_400_000
        )
        #expect(abs(fractional - 10) < 0.000_001)
    }

    /// Zero-based containers (MKV/MP4) and an unknown start time behave as before.
    @Test
    func contentTimeLeavesZeroBasedAndUnknownStartUntouched() {
        #expect(RemuxHLSWriter.contentSeconds(containerSeconds: 42, inputStartTime: 0) == 42)
        // AV_NOPTS_VALUE
        #expect(RemuxHLSWriter.contentSeconds(containerSeconds: 42, inputStartTime: Int64.min) == 42)
    }

    // MARK: - Progress-based start deadline (remux-hls-authoring-2)

    private func expired(_ elapsed: Double, packets: Int, stalled: Double) -> Bool {
        AirPlayRemuxSession.startWaitExpired(
            elapsedSeconds: elapsed, packetsRead: packets, stalledSeconds: stalled
        )
    }

    /// Nothing read at all: the old fixed 25 s limit, unchanged.
    @Test
    func startWaitFailsAt25sWhenNoPacketWasRead() {
        #expect(!expired(1, packets: 0, stalled: 0))
        #expect(!expired(24.9, packets: 0, stalled: 0))
        #expect(expired(25, packets: 0, stalled: 0))
        // A blocked open is not judged by the stall clock, only by the 25 s limit.
        #expect(!expired(20, packets: 0, stalled: 19))
    }

    /// A long-GOP live channel needs more than 25 s for three segments: while packets
    /// keep coming the wait goes on.
    @Test
    func startWaitContinuesWhilePacketsFlow() {
        #expect(!expired(25, packets: 500, stalled: 0.1))
        #expect(!expired(45, packets: 9000, stalled: 2))
        #expect(!expired(59.9, packets: 20000, stalled: 11.9))
    }

    /// Packets stopped: 12 s without one ends the wait, also before the 25 s mark.
    @Test
    func startWaitFailsOnceTheSourceStalls() {
        #expect(!expired(30, packets: 10, stalled: 11.9))
        #expect(expired(30, packets: 10, stalled: 12))
        #expect(expired(14, packets: 10, stalled: 12.5))
    }

    /// Pacing sleeps and the pre-open wait report a stall of 0, so they never end the
    /// wait by themselves; only the hard cap does.
    @Test
    func startWaitIsCappedAt60s() {
        #expect(!expired(59, packets: 4000, stalled: 0))
        #expect(expired(60, packets: 4000, stalled: 0))
        #expect(expired(60, packets: 0, stalled: 0))
        #expect(expired(75, packets: 4000, stalled: 0.2))
    }

    /// A writer that has not been started is on hold (pre-open): no packets, no stall.
    @Test
    func idleWriterReportsNoStall() {
        let writer = RemuxHLSWriter(
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            outputDirectory: FileManager.default.temporaryDirectory,
            startSeconds: 0,
            isLive: true,
            userAgent: nil
        )
        #expect(writer.readProgress == RemuxHLSWriter.ReadProgress(packetsRead: 0, stalledSeconds: 0))
    }

    // MARK: - Named errors (remux-hls-authoring-7, session error constants)

    @Test
    func sessionErrorConstantsKeepTheirValues() {
        #expect(AirPlayRemuxSession.errorDomain == "AirPlayRemux")
        #expect(AirPlayRemuxSession.ErrorCode.noLANAddress.rawValue == 1)
        #expect(AirPlayRemuxSession.ErrorCode.playlistTimeout.rawValue == 2)
        #expect(AirPlayRemuxSession.ErrorCode.localServerUnreachable.rawValue == 3)
        // A listener without a port is not "no LAN address" (that one asks for Wi-Fi).
        #expect(AirPlayRemuxSession.ErrorCode.listenerNotReady.rawValue == 4)
    }

    @Test
    func unknownVideoParametersIsItsOwnError() {
        let error: Error = RemuxHLSWriter.RemuxError.videoParametersUnknown
        #expect(!error.localizedDescription.isEmpty)
        if case .openOutputFailed = RemuxHLSWriter.RemuxError.videoParametersUnknown {
            Issue.record("videoParametersUnknown must not collapse into openOutputFailed")
        }
    }

    /// The audio half of the same finding: a copied audio stream whose sample rate
    /// probing did not find used to end as openOutputFailed(-22), "incompatible".
    @Test
    func unknownAudioParametersIsItsOwnError() {
        let error: Error = RemuxHLSWriter.RemuxError.audioParametersUnknown
        #expect(!error.localizedDescription.isEmpty)
        #expect(error.localizedDescription
            != RemuxHLSWriter.RemuxError.videoParametersUnknown.localizedDescription)
        if case .openOutputFailed = RemuxHLSWriter.RemuxError.audioParametersUnknown {
            Issue.record("audioParametersUnknown must not collapse into openOutputFailed")
        }
        // Not a full disk either: `stop()` keeps its delayed delete.
        #expect(!AirPlayRemuxSession.isOutOfSpace(error))
    }

    /// The first audio stream is used unless its sample rate is unknown and a later
    /// stream has one.
    @Test
    func audioStreamWithAKnownSampleRateIsPreferred() {
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: []) == nil)
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [48_000]) == 0)
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [48_000, 44_100]) == 0)
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [0, 44_100]) == 1)
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [0, 0, 48_000, 44_100]) == 2)
        // None is known: the first one, which then fails by name if it would be copied.
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [0]) == 0)
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [0, 0]) == 0)
        #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [-1, 0]) == 0)
    }

    // MARK: - What a failed start says about itself (airplay-diagnosability-tests-2/-10)

    /// The playlist-timeout error keeps its domain and code and carries the writer's
    /// progress, so a dead, a stalled and a slow source no longer read the same.
    @Test
    func playlistTimeoutErrorCarriesTheWritersProgress() {
        let progress = AirPlayRemuxSession.StartWaitProgress(
            packetsRead: 412, closedSegments: 1, stalledSeconds: 12.4, elapsedSeconds: 15.9
        )
        let error = AirPlayRemuxSession.playlistTimeoutError(progress)
        #expect(error.domain == AirPlayRemuxSession.errorDomain)
        #expect(error.code == AirPlayRemuxSession.ErrorCode.playlistTimeout.rawValue)
        #expect(error.localizedDescription
            == "Remux playlist not produced in time (packets=412, segments=1, stalled=12s, elapsed=15s)")
        #expect(error.userInfo[AirPlayRemuxSession.packetsReadErrorKey] as? Int == 412)
        #expect(error.userInfo[AirPlayRemuxSession.closedSegmentsErrorKey] as? Int == 1)
        #expect(error.userInfo[AirPlayRemuxSession.stalledSecondsErrorKey] as? TimeInterval == 12.4)
        #expect(error.userInfo[AirPlayRemuxSession.elapsedSecondsErrorKey] as? TimeInterval == 15.9)

        let dead = AirPlayRemuxSession.playlistTimeoutError(
            AirPlayRemuxSession.StartWaitProgress(
                packetsRead: 0, closedSegments: 0, stalledSeconds: 0, elapsedSeconds: 25.2
            )
        )
        #expect(dead.localizedDescription
            == "Remux playlist not produced in time (packets=0, segments=0, stalled=0s, elapsed=25s)")
    }

    @Test
    func closedSegmentsAreCountedFromThePlaylist() {
        #expect(AirPlayRemuxSession.closedSegmentCount(inPlaylist: "") == 0)
        #expect(AirPlayRemuxSession.closedSegmentCount(inPlaylist: "#EXTM3U\n#EXT-X-VERSION:3\n") == 0)
        let playlist = """
        #EXTM3U
        #EXT-X-TARGETDURATION:2
        #EXT-X-DISCONTINUITY
        #EXTINF:1.500,
        seg00000.ts
        #EXTINF:2.000,
        seg00001.ts

        """
        #expect(AirPlayRemuxSession.closedSegmentCount(inPlaylist: playlist) == 2)
    }

    /// The LAN /ping probe's last failure, which used to be thrown away.
    @Test
    func probeFailureNamesTheErrorOrTheStatus() {
        let timedOut = AirPlayRemuxSession.probeFailureDescription(
            error: URLError(.timedOut), statusCode: nil
        )
        #expect(timedOut.hasPrefix("NSURLErrorDomain -1001 ("))
        let refused = AirPlayRemuxSession.probeFailureDescription(
            error: URLError(.cannotConnectToHost), statusCode: nil
        )
        #expect(refused.hasPrefix("NSURLErrorDomain -1004 ("))
        // The server answered, with something other than 200.
        #expect(AirPlayRemuxSession.probeFailureDescription(error: nil, statusCode: 404) == "HTTP 404")
        #expect(AirPlayRemuxSession.probeFailureDescription(error: nil, statusCode: nil) == "no response")
        // An error wins over a status that came with it.
        #expect(
            AirPlayRemuxSession.probeFailureDescription(error: URLError(.timedOut), statusCode: 200)
                .hasPrefix("NSURLErrorDomain")
        )
    }

    /// Before the source is open nothing is known about seeking, and "unknown" must
    /// read as "cannot": the low-space rebuild is only safe on a source that can.
    @Test
    func writerThatHasNotOpenedItsSourceCannotSeek() {
        let writer = RemuxHLSWriter(
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            outputDirectory: FileManager.default.temporaryDirectory,
            startSeconds: 600,
            isLive: false,
            userAgent: nil
        )
        #expect(!writer.sourceCanSeek)
    }

    // MARK: - Source timestamp jumps (remux-hls-authoring-4, airplay-external-research-9)

    typealias Continuity = RemuxHLSWriter.KeyframeContinuity

    /// The rule itself: backward by more than 1 s against the previous keyframe,
    /// forward by more than 10 s against the latest media time.
    @Test
    func keyframeJumpRule() {
        // Nothing to compare the first keyframe with.
        #expect(Continuity.jump(
            keyframeSeconds: 3600, previousKeyframeSeconds: nil, lastMediaSeconds: nil
        ) == nil)
        // An ordinary 2 s GOP.
        #expect(Continuity.jump(
            keyframeSeconds: 12, previousKeyframeSeconds: 10, lastMediaSeconds: 11.96
        ) == nil)
        // A replayed second is tolerated; more than that is a reset.
        #expect(Continuity.jump(
            keyframeSeconds: 9, previousKeyframeSeconds: 10, lastMediaSeconds: 11.96
        ) == nil)
        let backward = Continuity.jump(
            keyframeSeconds: 8.5, previousKeyframeSeconds: 10, lastMediaSeconds: 11.96
        )
        #expect(backward?.isBackward == true)
        #expect(abs((backward?.seconds ?? 0) + 1.5) < 0.000_001)
        // Forward: measured from the latest packet, not from the previous keyframe.
        #expect(Continuity.jump(
            keyframeSeconds: 21.9, previousKeyframeSeconds: 10, lastMediaSeconds: 11.96
        ) == nil)
        let forward = Continuity.jump(
            keyframeSeconds: 52, previousKeyframeSeconds: 10, lastMediaSeconds: 11.96
        )
        #expect(forward?.isBackward == false)
        #expect(abs((forward?.seconds ?? 0) - 40.04) < 0.000_001)
    }

    /// 60 s of 25 fps video with B-frames, timestamps in decode order as MKV hands
    /// them over (pts only: I, P, B, B ...). Reordering must never read as a jump.
    @Test
    func reorderedFramesAreNotAJump() {
        var continuity = Continuity()
        let frame = 1.0 / 25
        for gop in 0..<30 {
            let start = Double(gop) * 2
            #expect(continuity.observe(videoSeconds: start, isKeyframe: true) == nil)
            var index = 1
            while index + 2 < 50 {
                // P first, then the two B-frames that are shown before it.
                for offset in [2, 0, 1] {
                    let seconds = start + Double(index + offset) * frame
                    #expect(continuity.observe(videoSeconds: seconds, isKeyframe: false) == nil)
                    #expect(!continuity.isOffTimeline(seconds))
                }
                index += 3
            }
            continuity.observe(audioSeconds: start + 1.9)
        }
        #expect(continuity.lastKeyframeSeconds == 58)
        #expect((continuity.lastVideoSeconds ?? 0) > 59.8)
    }

    /// x264 and x265 default to keyint 250, which is 10.4 s at 24 fps: against the
    /// previous keyframe that would be "forward by more than 10 s" on every GOP.
    @Test
    func longGOPIsNotAJump() {
        var continuity = Continuity()
        let frame = 1.0 / 24
        for gop in 0..<4 {
            let start = Double(gop) * 12.5
            #expect(continuity.observe(videoSeconds: start, isKeyframe: true) == nil)
            for index in 1..<300 {
                #expect(continuity.observe(
                    videoSeconds: start + Double(index) * frame, isKeyframe: false
                ) == nil)
            }
        }
    }

    /// A slideshow channel: one picture every 15 s while the audio runs on. The
    /// audio carries the clock, so the next picture is not a jump. MPEG-TS hands a
    /// lone picture over late, after audio that is stamped well past it.
    @Test
    func sparseVideoWithRunningAudioIsNotAJump() {
        var continuity = Continuity()
        var audio = 0.0
        func runAudio(until end: Double) {
            while audio < end {
                continuity.observe(audioSeconds: audio)
                #expect(!continuity.isOffTimeline(audio))
                audio += 0.021
            }
        }
        runAudio(until: 15)
        #expect(continuity.observe(videoSeconds: 0, isKeyframe: true) == nil)
        runAudio(until: 30)
        #expect(continuity.observe(videoSeconds: 15, isKeyframe: true) == nil)
        runAudio(until: 45)
        #expect(continuity.observe(videoSeconds: 30, isKeyframe: true) == nil)
    }

    /// Without audio there is nothing to vouch for the gap: pictures more than 10 s
    /// apart read as a forward jump. Pinned so the limit is a known one.
    @Test
    func sparseVideoWithoutAudioReadsAsAForwardJump() {
        var continuity = Continuity()
        #expect(continuity.observe(videoSeconds: 0, isKeyframe: true) == nil)
        #expect(continuity.observe(videoSeconds: 15, isKeyframe: true)?.isBackward == false)
    }

    /// Provider restart: the clock goes back to zero. Reported once, at the keyframe,
    /// and the detector carries on from there.
    @Test
    func backwardResetIsReportedOnceAtTheKeyframe() {
        var continuity = Continuity()
        for second in 0..<20 {
            #expect(continuity.observe(videoSeconds: Double(second), isKeyframe: true) == nil)
            #expect(continuity.observe(videoSeconds: Double(second) + 0.96, isKeyframe: false) == nil)
            continuity.observe(audioSeconds: Double(second) + 0.9)
        }
        // New-timeline audio and frames arrive before their keyframe: more than 10 s
        // behind, so they are marked for dropping and move nothing.
        continuity.observe(audioSeconds: 0.2)
        #expect(continuity.isOffTimeline(0.2))
        #expect(continuity.observe(videoSeconds: 0.5, isKeyframe: false) == nil)
        #expect(continuity.isOffTimeline(0.5))
        #expect(continuity.lastKeyframeSeconds == 19)

        let jump = continuity.observe(videoSeconds: 1, isKeyframe: true)
        #expect(jump?.isBackward == true)
        #expect(abs((jump?.seconds ?? 0) + 18) < 0.000_001)
        #expect(continuity.lastKeyframeSeconds == 1)
        #expect(continuity.lastVideoSeconds == 1)

        // The new timeline is the clock from here on.
        continuity.observe(audioSeconds: 1.1)
        #expect(!continuity.isOffTimeline(1.1))
        #expect(continuity.observe(videoSeconds: 1.96, isKeyframe: false) == nil)
        #expect(continuity.observe(videoSeconds: 2, isKeyframe: true) == nil)
    }

    /// A reconnect that replays less than a second is left to the timestamp repair.
    @Test
    func shortReplayIsNotAJump() {
        var continuity = Continuity()
        #expect(continuity.observe(videoSeconds: 10, isKeyframe: true) == nil)
        #expect(continuity.observe(videoSeconds: 11.9, isKeyframe: false) == nil)
        #expect(continuity.observe(videoSeconds: 9.2, isKeyframe: true) == nil)
        #expect(!continuity.isOffTimeline(9.3))
    }

    /// A leap in the middle of a GOP: the leaping packets must not move the
    /// reference, or the keyframe that follows would look continuous.
    @Test
    func forwardLeapInsideAGOPIsCaughtAtTheNextKeyframe() {
        var continuity = Continuity()
        #expect(continuity.observe(videoSeconds: 100, isKeyframe: true) == nil)
        #expect(continuity.observe(videoSeconds: 100.5, isKeyframe: false) == nil)
        continuity.observe(audioSeconds: 100.4)

        // +40 s from here on, audio first.
        continuity.observe(audioSeconds: 140.5)
        continuity.observe(audioSeconds: 140.52)
        #expect(continuity.isOffTimeline(140.52))
        #expect(continuity.observe(videoSeconds: 140.6, isKeyframe: false) == nil)
        #expect(continuity.isOffTimeline(140.6))
        #expect(continuity.lastVideoSeconds == 100.5)
        #expect(continuity.lastMediaSeconds == 100.5)

        let jump = continuity.observe(videoSeconds: 141, isKeyframe: true)
        #expect(jump?.isBackward == false)
        #expect(abs((jump?.seconds ?? 0) - 40.5) < 0.000_001)
        #expect(!continuity.isOffTimeline(141.02))
        #expect(continuity.observe(videoSeconds: 143, isKeyframe: true) == nil)
    }

    /// fMP4 cannot splice in place. A rebuild is asked for only where it helps: any
    /// large jump on live, and a large backward jump on VOD that can seek.
    @Test
    func fmp4RebuildPolicy() {
        typealias Jump = Continuity.Jump
        func rebuilds(_ seconds: Double, live: Bool, seekable: Bool = true) -> Bool {
            RemuxHLSWriter.fmp4NeedsRebuild(
                after: Jump(seconds: seconds), isLive: live, sourceSeekable: seekable
            )
        }
        #expect(rebuilds(-3600, live: true, seekable: false))
        #expect(rebuilds(40, live: true, seekable: false))
        // A replayed burst catches up by itself in less time than a rebuild takes.
        #expect(!rebuilds(-4, live: true))
        #expect(rebuilds(-13, live: false))
        // A source that cannot seek would restart at 0:00 and meet the jump again.
        #expect(!rebuilds(-13, live: false, seekable: false))
        // A forward gap in a file still cuts segments and plays through.
        #expect(!rebuilds(40, live: false))
        #expect(!rebuilds(-4, live: false))
    }

    // MARK: - Playlist authoring (remux-hls-authoring-10, airplay-external-research-8)

    typealias Segment = RemuxHLSWriter.SegmentRecord

    private func lines(_ playlist: String) -> [String] {
        playlist.split(separator: "\n").map(String.init)
    }

    /// EXTINF is the measured duration: a 9.6 s GOP is no longer listed as 6.000.
    @Test
    func publishedDurationIsTheMeasuredOne() {
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: 4.004) == 4.004)
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: 9.6) == 9.6)
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: 0.2) == 0.2)
        // No usable measurement: the previous 0.5 s floor.
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: 0) == 0.5)
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: -3) == 0.5)
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: .nan) == 0.5)
        #expect(RemuxHLSWriter.publishedSegmentDuration(measuredSeconds: 500)
            == RemuxHLSWriter.maximumSegmentSeconds)
    }

    @Test
    func targetDurationCoversTheLongestSegment() {
        func target(_ durations: [Double], nominal: Double) -> Int {
            let segments = durations.enumerated().map {
                Segment(index: $0.offset, fileName: "seg.ts", duration: $0.element)
            }
            return RemuxHLSWriter.targetDuration(for: segments, nominalSeconds: nominal)
        }
        #expect(target([1.5, 1.9, 2.0], nominal: 1.5) == 2)
        // The short first segment does not pull a VOD session below its 4 s target.
        #expect(target([2.0], nominal: 4) == 4)
        #expect(target([3.0, 6.0], nominal: 4) == 6)
        #expect(target([12.417, 12.5], nominal: 4) == 13)
        #expect(target([], nominal: 1.5) == 2)
        // Exact durations carry float noise; that must not add a whole second (and
        // with it a target duration of hold-back on the receiver).
        #expect(target([12.4 - 10.4], nominal: 1.5) == 2)
        #expect(target([15.000_000_001], nominal: 4) == 15)
        #expect(target([4.04], nominal: 4) == 4)
        #expect(target([4.06], nominal: 4) == 5)
    }

    /// A session without a jump writes the same playlist as before: no
    /// discontinuity tag of either kind.
    @Test
    func ordinaryPlaylistsCarryNoDiscontinuityTags() {
        let segments = (7..<10).map {
            Segment(index: $0, fileName: String(format: "seg%05d.ts", $0), duration: 2)
        }
        let live = RemuxHLSWriter.mediaPlaylist(
            segments: segments, isLive: true, targetDuration: 2,
            discontinuitySequence: 0, final: false
        )
        #expect(!live.contains("DISCONTINUITY"))
        #expect(lines(live) == [
            "#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:7",
            "#EXTINF:2.000,", "seg00007.ts",
            "#EXTINF:2.000,", "seg00008.ts",
            "#EXTINF:2.000,", "seg00009.ts",
        ])

        let fmp4 = RemuxHLSWriter.mediaPlaylist(
            segments: [Segment(index: 0, fileName: "seg00000.m4s", duration: 4)],
            isLive: false, targetDuration: 4, discontinuitySequence: 0, final: true
        )
        #expect(lines(fmp4) == [
            "#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-TARGETDURATION:4", "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:EVENT", "#EXT-X-START:TIME-OFFSET=0,PRECISE=YES",
            "#EXT-X-MAP:URI=\"init.mp4\"",
            "#EXTINF:4.000,", "seg00000.m4s", "#EXT-X-ENDLIST",
        ])
    }

    /// The tag sits directly before the segment that starts the new timeline. An
    /// event playlist never drops segments, so it needs no sequence tag.
    @Test
    func discontinuityTagPrecedesItsSegment() {
        let segments = [
            Segment(index: 0, fileName: "seg00000.ts", duration: 2),
            Segment(index: 1, fileName: "seg00001.ts", duration: 4),
            Segment(index: 2, fileName: "seg00002.ts", duration: 4, discontinuity: true),
            Segment(index: 3, fileName: "seg00003.ts", duration: 4),
        ]
        let playlist = lines(RemuxHLSWriter.mediaPlaylist(
            segments: segments, isLive: false, targetDuration: 4,
            discontinuitySequence: 0, final: false
        ))
        #expect(playlist.filter { $0 == "#EXT-X-DISCONTINUITY" }.count == 1)
        if let tag = playlist.firstIndex(of: "#EXT-X-DISCONTINUITY"),
           tag >= 1, tag + 2 < playlist.count
        {
            #expect(playlist[tag + 1] == "#EXTINF:4.000,")
            #expect(playlist[tag + 2] == "seg00002.ts")
            #expect(playlist[tag - 1] == "seg00001.ts")
        } else {
            Issue.record("no EXT-X-DISCONTINUITY tag in \(playlist)")
        }
        #expect(!playlist.contains { $0.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") })
    }

    /// Live window: the sequence tag appears with the first jump, comes before every
    /// segment, and counts the tags that have left the window. A tagged segment that
    /// is first in the window keeps its tag.
    @Test
    func liveWindowNumbersItsDiscontinuities() {
        let segments = [
            Segment(index: 40, fileName: "seg00040.ts", duration: 2, discontinuity: true),
            Segment(index: 41, fileName: "seg00041.ts", duration: 2),
            Segment(index: 42, fileName: "seg00042.ts", duration: 2, discontinuity: true),
        ]
        let playlist = lines(RemuxHLSWriter.mediaPlaylist(
            segments: segments, isLive: true, targetDuration: 2,
            discontinuitySequence: 3, final: false
        ))
        #expect(playlist == [
            "#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:40",
            "#EXT-X-DISCONTINUITY-SEQUENCE:3",
            "#EXT-X-DISCONTINUITY", "#EXTINF:2.000,", "seg00040.ts",
            "#EXTINF:2.000,", "seg00041.ts",
            "#EXT-X-DISCONTINUITY", "#EXTINF:2.000,", "seg00042.ts",
        ])

        // First jump still inside the window: the tag is there from the start, at 0.
        let first = lines(RemuxHLSWriter.mediaPlaylist(
            segments: [segments[1], segments[2]], isLive: true, targetDuration: 2,
            discontinuitySequence: 0, final: false
        ))
        #expect(first.contains("#EXT-X-DISCONTINUITY-SEQUENCE:0"))

        // Every tagged segment has left: only the count remains.
        let after = lines(RemuxHLSWriter.mediaPlaylist(
            segments: [segments[1]], isLive: true, targetDuration: 2,
            discontinuitySequence: 4, final: false
        ))
        #expect(after.contains("#EXT-X-DISCONTINUITY-SEQUENCE:4"))
        #expect(!after.contains("#EXT-X-DISCONTINUITY"))
    }

    /// The TS path adds one constant base to every timestamp; the subtitle map has to
    /// name the same base or every cue shows 10 s early.
    @Test
    func subtitleMapCarriesTheTimestampBase() {
        #expect(RemuxHLSWriter.tsTimestampBase90k == 900_000)
        let built = AirPlaySubtitleRendition.build(
            from: [SubtitleEntry(startTime: 1, endTime: 3, text: "Hello")],
            mpegtsClock: RemuxHLSWriter.tsTimestampBase90k
        )
        #expect(built.webVTT.hasPrefix(
            "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000\n\n00:00:01.000 --> 00:00:03.000\nHello"
        ))
    }

    // MARK: - Stall watchdog limits (remux-hls-authoring-5)

    /// The watchdog must outlast FFmpeg's own 15 s read timeout (rw_timeout), or it
    /// would cut a read that the protocol layer is about to recover.
    @Test
    func readStallLimitsOutlastTheProtocolTimeout() {
        #expect(RemuxHLSWriter.liveReadStallLimitSeconds == 20)
        #expect(RemuxHLSWriter.vodReadStallLimitSeconds == 30)
        #expect(RemuxHLSWriter.liveReadStallLimitSeconds > 15)
    }

    // MARK: - End to end (bytes written, real durations, timestamp reset)

    /// TS and fMP4: `bytesWritten` is exactly what the segments (and the init
    /// segment) occupy, EXTINF adds up to the real length, and no EXTINF exceeds
    /// the single TARGETDURATION.
    @Test(.timeLimit(.minutes(1)))
    func accountsBytesAndPublishesRealDurations() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-bytes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let movieURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestMovie(to: movieURL, seconds: 8)

        for format in [RemuxHLSWriter.SegmentFormat.mpegTS, .fmp4] {
            let outDir = dir.appendingPathComponent(format == .fmp4 ? "fmp4" : "ts", isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let writer = RemuxHLSWriter(
                sourceURL: movieURL,
                outputDirectory: outDir,
                startSeconds: 0,
                isLive: false,
                userAgent: nil,
                forcedFormat: format
            )
            #expect(writer.bytesWritten == 0)
            writer.onError = { error in
                Issue.record("remux error: \(error.localizedDescription)")
            }
            writer.start()
            #expect(await Self.waitForEndList(writer), "remux did not finish within 10s")

            let playlist = lines(try String(contentsOf: writer.playlistURL, encoding: .utf8))
            var onDisk = playlist
                .filter { $0.hasSuffix(".ts") || $0.hasSuffix(".m4s") }
                .reduce(0) { $0 + Self.fileSize(outDir.appendingPathComponent($1)) }
            if format == .fmp4 {
                onDisk += Self.fileSize(outDir.appendingPathComponent("init.mp4"))
            }
            #expect(onDisk > 0)
            #expect(writer.bytesWritten == Int64(onDisk))

            let durations = playlist
                .filter { $0.hasPrefix("#EXTINF:") }
                .compactMap { Double($0.dropFirst("#EXTINF:".count).dropLast()) }
            // 240 frames at 30 fps. Last packet minus first packet lost a frame
            // per segment.
            #expect(abs(durations.reduce(0, +) - 8) < 0.07, "EXTINF sum \(durations)")
            let targets = playlist.filter { $0.hasPrefix("#EXT-X-TARGETDURATION:") }
            #expect(targets.count == 1)
            let target = Double(targets.first?.dropFirst("#EXT-X-TARGETDURATION:".count) ?? "") ?? 0
            #expect(durations.allSatisfy { $0.rounded() <= target })
        }
    }

    /// A source whose timestamps restart (the writer's own TS output, played twice
    /// in a row). The TS path used to stop cutting segments and squash every packet
    /// one tick apart, with no error; it now closes the segment, restarts the
    /// timeline and marks it. fMP4 cannot do that in place and asks for a rebuild.
    @Test(.timeLimit(.minutes(1)))
    func timestampResetSplicesOnTSAndAsksForARebuildOnFMP4() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-reset-\(UUID().uuidString)", isDirectory: true)
        let fixtureDir = dir.appendingPathComponent("fixture", isDirectory: true)
        let tsDir = dir.appendingPathComponent("ts", isDirectory: true)
        let fmp4Dir = dir.appendingPathComponent("fmp4", isDirectory: true)
        for directory in [fixtureDir, tsDir, fmp4Dir] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let movieURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestMovie(to: movieURL, seconds: 14)
        let fixtureWriter = RemuxHLSWriter(
            sourceURL: movieURL,
            outputDirectory: fixtureDir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil
        )
        fixtureWriter.onError = { error in
            Issue.record("fixture remux error: \(error.localizedDescription)")
        }
        fixtureWriter.start()
        #expect(await Self.waitForEndList(fixtureWriter), "TS fixture remux did not finish within 10s")
        let fixturePlaylist = try String(contentsOf: fixtureWriter.playlistURL, encoding: .utf8)
        #expect(!fixturePlaylist.contains("DISCONTINUITY"))
        var once = Data()
        for name in lines(fixturePlaylist) where name.hasSuffix(".ts") {
            once.append(try Data(contentsOf: fixtureDir.appendingPathComponent(name)))
        }
        // 14 s, then the same 14 s again: the clock jumps back by about 13 s.
        let sourceURL = dir.appendingPathComponent("twice.ts")
        try (once + once).write(to: sourceURL)

        let tsWriter = RemuxHLSWriter(
            sourceURL: sourceURL,
            outputDirectory: tsDir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil,
            forcedFormat: .mpegTS
        )
        tsWriter.onError = { error in
            Issue.record("remux error: \(error.localizedDescription)")
        }
        // 28 s of content and nobody playing: the pacing gate, which now counts
        // across the reset, would hold the writer 25 s in.
        tsWriter.updatePlaybackPosition(28)
        tsWriter.start()
        #expect(await Self.waitForEndList(tsWriter), "TS remux of the reset source did not finish within 10s")
        let playlist = lines(try String(contentsOf: tsWriter.playlistURL, encoding: .utf8))
        #expect(playlist.filter { $0 == "#EXT-X-DISCONTINUITY" }.count == 1)
        let durations = playlist
            .filter { $0.hasPrefix("#EXTINF:") }
            .compactMap { Double($0.dropFirst("#EXTINF:".count).dropLast()) }
        // Both passes are there in full: segment cuts did not stop at the reset.
        #expect(abs(durations.reduce(0, +) - 28) < 0.5, "EXTINF sum \(durations)")
        #expect(durations.allSatisfy { $0 <= 5.5 }, "a squashed stretch shows as one long segment")

        let fmp4Writer = RemuxHLSWriter(
            sourceURL: sourceURL,
            outputDirectory: fmp4Dir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil,
            forcedFormat: .fmp4
        )
        let reported = ErrorBox()
        fmp4Writer.onError = { error in reported.error = error }
        fmp4Writer.start()
        for _ in 0..<40 where reported.error == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if case .timestampDiscontinuity? = reported.error as? RemuxHLSWriter.RemuxError {
            // expected
        } else {
            Issue.record("expected timestampDiscontinuity, got \(String(describing: reported.error))")
        }
    }

    private final class ErrorBox {
        var error: Error?
    }

    // MARK: - Helpers

    private static func fileSize(_ url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int ?? 0
    }

    /// Polls the writer's playlist for ENDLIST; local remuxes finish well under 10 s.
    private static func waitForEndList(_ writer: RemuxHLSWriter) async -> Bool {
        for _ in 0..<40 {
            if let content = try? String(contentsOf: writer.playlistURL, encoding: .utf8),
               content.contains("#EXT-X-ENDLIST") {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    /// H.264 video (30 fps, one keyframe per second) plus AAC audio (44.1 kHz mono
    /// tone) in an mp4. Audio is appended frame by frame alongside the video so the
    /// asset writer's interleaving never starves one input.
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

        // Each input is fed whenever it is ready and finished as soon as it is done:
        // waiting for both at once deadlocks, because the writer holds one input back
        // until the other has caught up.
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

/// Live probe window (remux-hls-authoring-7, measured follow-up): the caps the
/// writer hands to libavformat for a live input.
@Suite("AirPlayRemuxLiveProbe")
struct AirPlayRemuxLiveProbeTests {

    /// The measured failure: a real-time HEVC source with a 6 s GOP at 9 Mbit/s,
    /// joined 5 s before its next keyframe. 4.5 s / 8 MB ended before that keyframe
    /// (5.6 MB of stream is under 8 MB; the 4.5 s cap is the one that was reached).
    /// Both caps have to clear the join with room for the keyframe itself.
    @Test
    func liveProbeWindowReachesTheKeyframeOfTheMeasuredJoin() {
        let secondsToKeyframe = 5.0
        let bitsPerSecond = 9_000_000.0
        let bytesToKeyframe = secondsToKeyframe * bitsPerSecond / 8
        let windowSeconds = Double(RemuxHLSWriter.liveProbeDurationMicroseconds) / 1_000_000
        #expect(windowSeconds >= secondsToKeyframe + 1)
        #expect(Double(RemuxHLSWriter.liveProbeSizeBytes) >= bytesToKeyframe * 1.5)
        // A whole 6 s GOP fits, wherever in it the channel was joined.
        #expect(windowSeconds > 6)
        #expect(Double(RemuxHLSWriter.liveProbeSizeBytes) > 6 * bitsPerSecond / 8)
    }

    /// The values themselves, in the units libavformat takes (`analyzeduration` is
    /// microseconds, `probesize` is bytes): a slip in either unit would shrink the
    /// window back below a GOP without any error.
    @Test
    func liveProbeCapsKeepTheirValues() {
        #expect(RemuxHLSWriter.liveProbeDurationMicroseconds == 10_000_000)
        #expect(RemuxHLSWriter.liveProbeSizeBytes == 24_000_000)
        // The byte cap must not end the probe long before the duration cap does at
        // ordinary HEVC channel bitrates (up to about 16 Mbit/s).
        let secondsAt16Mbit = Double(RemuxHLSWriter.liveProbeSizeBytes) * 8 / 16_000_000
        #expect(secondsAt16Mbit >= 10)
    }

    /// No packet counts as read while libavformat probes, so the session judges that
    /// time by its first-packet deadline. A probe that runs to its cap, after the
    /// longest pre-open drain wait the cast controller asks for (3 s), has to leave
    /// room for the connection itself, or a long-GOP channel would end as a playlist
    /// timeout instead of `videoParametersUnknown` (which is retried).
    @Test
    func fullLiveProbeFitsInsideTheFirstPacketDeadline() {
        let windowSeconds = Double(RemuxHLSWriter.liveProbeDurationMicroseconds) / 1_000_000
        let longestDrainWait = 3.0
        let connectAllowance = 10.0
        #expect(
            windowSeconds + longestDrainWait + connectAllowance
                <= AirPlayRemuxSession.firstPacketDeadlineSeconds
        )
        #expect(AirPlayRemuxSession.firstPacketDeadlineSeconds < AirPlayRemuxSession.maximumStartWaitSeconds)
    }

    /// A window with no keyframe at all still surfaces as its own error, which the
    /// cast controller treats as transient.
    @Test
    func noKeyframeInTheWindowStaysANamedError() {
        let error = RemuxHLSWriter.RemuxError.videoParametersUnknown
        #expect(error.errorDescription?.contains("no keyframe in the probe window") == true)
        #expect(!AirPlayRemuxSession.isOutOfSpace(error))
    }
}
