import AVFoundation
import Foundation
import Testing
import UIKit
@testable import another_iptv_player

@Suite("AirPlayRemux")
struct AirPlayRemuxTests {

    /// Uçtan uca: AVAssetWriter ile 6 sn H.264 mp4 üret → RemuxHLSWriter ile TS-HLS'e
    /// remux et → playlist + segmentler oluşmalı. mpegts muxer'ının FFmpegKit build'inde
    /// gerçekten var olduğunu da kanıtlar (hls muxer yoktu, ondan elle segmentliyoruz).
    @Test
    func remuxesGeneratedMP4IntoTSSegments() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestVideo(to: sourceURL, seconds: 6)

        let writer = RemuxHLSWriter(
            sourceURL: sourceURL,
            outputDirectory: dir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil
        )
        writer.onError = { error in
            Issue.record("remux error: \(error.localizedDescription)")
        }
        writer.start()
        // Yerel dosya remux'u network'süz, tipik <1 sn sürer; 10 sn üst sınır.
        var finished = false
        for _ in 0..<40 {
            if let content = try? String(contentsOf: writer.playlistURL, encoding: .utf8),
               content.contains("#EXT-X-ENDLIST") {
                finished = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        #expect(finished, "remux did not finish within 10s")
        // A local file can seek, and no start seek was refused.
        #expect(writer.sourceCanSeek)

        let playlist = try String(contentsOf: writer.playlistURL, encoding: .utf8)
        #expect(playlist.contains("#EXTM3U"))
        #expect(playlist.contains("#EXTINF"))
        #expect(playlist.contains("#EXT-X-ENDLIST"))
        let segmentNames = playlist.split(separator: "\n").filter { $0.hasSuffix(".ts") }
        #expect(!segmentNames.isEmpty)
        for name in segmentNames {
            let attrs = try FileManager.default.attributesOfItem(
                atPath: dir.appendingPathComponent(String(name)).path
            )
            let size = attrs[.size] as? Int ?? 0
            #expect(size > 1000, "segment \(name) suspiciously small: \(size)B")
        }
    }

    @Test
    func splitsInitFromFirstFragmentBox() {
        func box(_ type: String, payload: Int) -> Data {
            var d = Data()
            let size = UInt32(8 + payload)
            d.append(contentsOf: [
                UInt8(size >> 24 & 0xFF), UInt8(size >> 16 & 0xFF),
                UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF),
            ])
            d.append(contentsOf: Array(type.utf8))
            d.append(Data(repeating: 0xEE, count: payload))
            return d
        }
        let ftyp = box("ftyp", payload: 12)
        let moov = box("moov", payload: 40)
        let moof = box("moof", payload: 24)
        let mdat = box("mdat", payload: 64)

        let (initData, fragment) = RemuxHLSWriter.splitAtFirstFragmentBox(ftyp + moov + moof + mdat)
        #expect(initData == ftyp + moov)
        #expect(fragment == moof + mdat)

        // Fragment yoksa (delay_moov ilk flush'ı yalnız moov üretti): hepsi init, fragment boş.
        let (onlyInit, empty) = RemuxHLSWriter.splitAtFirstFragmentBox(ftyp + moov)
        #expect(onlyInit == ftyp + moov)
        #expect(empty.isEmpty)
    }

    /// fMP4 yolu (HEVC için kullanılan): aynı H.264 kaynak, biçim zorlanarak. Fragment
    /// yakalama makinesini (custom AVIO, init.mp4 + m4s bölme, EXT-X-MAP) doğrular.
    @Test
    func remuxesIntoFMP4SegmentsWhenForced() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-fmp4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestVideo(to: sourceURL, seconds: 6)

        let writer = RemuxHLSWriter(
            sourceURL: sourceURL,
            outputDirectory: dir,
            startSeconds: 0,
            isLive: false,
            userAgent: nil,
            forcedFormat: .fmp4
        )
        writer.onError = { error in
            Issue.record("remux error: \(error.localizedDescription)")
        }
        writer.start()
        var finished = false
        for _ in 0..<40 {
            if let content = try? String(contentsOf: writer.playlistURL, encoding: .utf8),
               content.contains("#EXT-X-ENDLIST") {
                finished = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        #expect(finished, "fmp4 remux did not finish within 10s")

        let playlist = try String(contentsOf: writer.playlistURL, encoding: .utf8)
        #expect(playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""))
        #expect(playlist.contains("#EXT-X-VERSION:7"))
        let initAttrs = try FileManager.default.attributesOfItem(
            atPath: dir.appendingPathComponent("init.mp4").path
        )
        #expect((initAttrs[.size] as? Int ?? 0) > 100)
        let segmentNames = playlist.split(separator: "\n").filter { $0.hasSuffix(".m4s") }
        #expect(!segmentNames.isEmpty)
        for name in segmentNames {
            let attrs = try FileManager.default.attributesOfItem(
                atPath: dir.appendingPathComponent(String(name)).path
            )
            #expect((attrs[.size] as? Int ?? 0) > 500)
        }
    }

    /// Tam zincir: üretilen mp4 → remux (TS) → paylaşılan sunucu → AirPlayCastPlayer.
    /// KSAVPlayer'ın track-yarışı yüzünden cast oynatıcısı bizim AVPlayer sarmalayıcımız;
    /// bu test onun yerel HLS'i gerçekten readyToPlay'e getirdiğini kanıtlar.
    @Test(.timeLimit(.minutes(1)))
    func castPlayerPlaysRemuxedLocalHLS() async throws {
        let server = LocalHTTPServer.shared
        try server.start()
        let dir = server.directory.appendingPathComponent("cast-test", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.mp4")
        try await Self.writeTestVideo(to: sourceURL, seconds: 6)
        let writer = RemuxHLSWriter(
            sourceURL: sourceURL, outputDirectory: dir,
            startSeconds: 0, isLive: false, userAgent: nil
        )
        writer.start()
        var finished = false
        for _ in 0..<40 {
            if let content = try? String(contentsOf: writer.playlistURL, encoding: .utf8),
               content.contains("#EXT-X-ENDLIST") {
                finished = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        #expect(finished)

        let url = URL(string: "http://127.0.0.1:\(server.port)/cast-test/stream.m3u8")!
        let cast = AirPlayCastPlayer()
        cast.load(url: url, startAt: nil, autoPlay: false)
        defer { cast.dispose() }
        var ready = false
        for _ in 0..<20 {
            if cast.isReadyToPlay {
                ready = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        #expect(ready, "AirPlayCastPlayer did not reach readyToPlay on remuxed local HLS")
        #expect(cast.duration > 4, "duration missing: \(cast.duration)")
    }

    /// Simülatörde H.264 encode: tek renkli kareler, 30fps, saniyede bir keyframe.
    private static func writeTestVideo(to url: URL, seconds: Int) async throws {
        let width = 320
        let height = 240
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
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
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        assetWriter.add(input)
        #expect(assetWriter.startWriting())
        assetWriter.startSession(atSourceTime: .zero)

        let frameCount = seconds * 30
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(
                nil, adaptor.pixelBufferPool!, &pixelBuffer
            )
            guard let buffer = pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32((frame * 3) % 255), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
        }
        input.markAsFinished()
        await assetWriter.finishWriting()
        #expect(assetWriter.status == .completed)
    }

    @Test
    func codecCompatibilityWhitelist() {
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "avc1", audioFourCC: "mp4a"))
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "h264", audioFourCC: "eac3"))
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "avc1", audioFourCC: nil))
        // HEVC fMP4 segmenter ile destekleniyor.
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "hvc1", audioFourCC: "ac-3"))
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "hevc", audioFourCC: "aac"))
        // FFmpeg codecName profil ekiyle gelir — normalize edilmeli (canlı/film butonunun
        // topluca kaybolmasına yol açan gerçek regresyon).
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "h264 (High)", audioFourCC: "aac (LC)"))
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "hevc (Main)", audioFourCC: "eac3"))
        #expect(RemuxHLSWriter.normalizeCodec("h264 (High)") == "h264")
        // Ses artık adaylığı etkilemez: uyumsuz ses (DTS/MP2…) AAC'ye transcode edilir.
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "avc1", audioFourCC: "dts "))
        #expect(RemuxHLSWriter.isCompatible(videoFourCC: "h264", audioFourCC: "mp2"))
        // Video hâlâ katı: AV1/MPEG-2 decode gerektirir, passthrough imkânsız.
        #expect(!RemuxHLSWriter.isCompatible(videoFourCC: "av01", audioFourCC: "mp4a"))
        #expect(!RemuxHLSWriter.isCompatible(videoFourCC: "mp2v", audioFourCC: "mp4a"))
    }

    @Test(.timeLimit(.minutes(1)))
    func httpServerServesFilesAndRejectsTraversal() async throws {
        // The server's root is a subdirectory, so there is something outside it to
        // reach for.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-test-\(UUID().uuidString)", isDirectory: true)
        let root = dir.appendingPathComponent("root", isDirectory: true)
        let sessionDir = root.appendingPathComponent("s1", isDirectory: true)
        let deepDir = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let playlist = "#EXTM3U\n#EXT-X-VERSION:7\nseg00001.m4s\n"
        try playlist.write(
            to: root.appendingPathComponent("stream.m3u8"), atomically: true, encoding: .utf8
        )
        let segment = Data(repeating: 0xAB, count: 4096)
        try segment.write(to: root.appendingPathComponent("seg00001.m4s"))
        // Every file the refused requests below ask for exists, so a 404 comes from
        // the path rules and not from a missing file.
        try playlist.write(
            to: sessionDir.appendingPathComponent("stream.m3u8"), atomically: true, encoding: .utf8
        )
        try playlist.write(
            to: deepDir.appendingPathComponent("stream.m3u8"), atomically: true, encoding: .utf8
        )
        try Data("outside".utf8).write(to: dir.appendingPathComponent("outside.txt"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))

        let server = LocalHTTPServer(directory: root)
        try server.start()
        defer { server.stop() }
        #expect(server.port > 0)

        let base = "http://127.0.0.1:\(server.port)"

        let (playlistData, playlistResponse) = try await URLSession.shared.data(
            from: URL(string: "\(base)/stream.m3u8")!
        )
        let httpPlaylist = try #require(playlistResponse as? HTTPURLResponse)
        #expect(httpPlaylist.statusCode == 200)
        #expect(httpPlaylist.value(forHTTPHeaderField: "Content-Type") == "application/vnd.apple.mpegurl")
        #expect(String(decoding: playlistData, as: UTF8.self) == playlist)

        let (segmentData, segmentResponse) = try await URLSession.shared.data(
            from: URL(string: "\(base)/seg00001.m4s")!
        )
        #expect((segmentResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(segmentData == segment)

        var rangeRequest = URLRequest(url: URL(string: "\(base)/seg00001.m4s")!)
        rangeRequest.setValue("bytes=100-199", forHTTPHeaderField: "Range")
        let (rangeData, rangeResponse) = try await URLSession.shared.data(for: rangeRequest)
        let httpRange = try #require(rangeResponse as? HTTPURLResponse)
        #expect(httpRange.statusCode == 206)
        #expect(httpRange.value(forHTTPHeaderField: "Content-Range") == "bytes 100-199/4096")
        #expect(httpRange.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(rangeData == Data(repeating: 0xAB, count: 100))

        var suffixRequest = URLRequest(url: URL(string: "\(base)/seg00001.m4s")!)
        suffixRequest.setValue("bytes=-64", forHTTPHeaderField: "Range")
        let (suffixData, suffixResponse) = try await URLSession.shared.data(for: suffixRequest)
        #expect((suffixResponse as? HTTPURLResponse)?.statusCode == 206)
        #expect(suffixData == Data(repeating: 0xAB, count: 64))

        let (_, missingResponse) = try await URLSession.shared.data(
            from: URL(string: "\(base)/missing.m4s")!
        )
        #expect((missingResponse as? HTTPURLResponse)?.statusCode == 404)

        // One session level below the root is served.
        let (_, sessionResponse) = try await URLSession.shared.data(
            from: URL(string: "\(base)/s1/stream.m3u8")!
        )
        #expect((sessionResponse as? HTTPURLResponse)?.statusCode == 200)

        // A dot name (the sweep's trash directory is one) and anything deeper than
        // session/file are refused although the files exist.
        let (hiddenData, hiddenResponse) = try await URLSession.shared.data(
            from: URL(string: "\(base)/.hidden")!
        )
        #expect((hiddenResponse as? HTTPURLResponse)?.statusCode == 404)
        #expect(hiddenData.isEmpty)
        let (_, deepResponse) = try await URLSession.shared.data(
            from: URL(string: "\(base)/a/b/stream.m3u8")!
        )
        #expect((deepResponse as? HTTPURLResponse)?.statusCode == 404)

        // ".." has to be sent over a raw connection: URLSession resolves dot segments
        // before the request leaves. The first request is the control for the helper.
        let notFound = "HTTP/1.1 404 Not Found"
        let port = server.port
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/stream.m3u8") == "HTTP/1.1 200 OK")
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/../outside.txt") == notFound)
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/s1/../../outside.txt") == notFound)
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/a/../../outside.txt") == notFound)
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/..") == notFound)
        // The server does not percent-decode, so an encoded ".." is only a name.
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/%2e%2e/outside.txt") == notFound)
        #expect(await Self.rawStatusLine(port: port, requestTarget: "/s1/.hidden") == notFound)
    }

    /// Status line of the answer to `GET <requestTarget>` sent byte for byte over a
    /// plain TCP socket to 127.0.0.1; nil when the exchange failed.
    private static func rawStatusLine(port: UInt16, requestTarget: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: blockingRawStatusLine(port: port, requestTarget: requestTarget)
                )
            }
        }
    }

    /// Blocking; every socket call is bounded by a 5 s timeout.
    nonisolated private static func blockingRawStatusLine(
        port: UInt16, requestTarget: String
    ) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize)
        // The server closes after its answer; a late write must not raise SIGPIPE.
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        let request = Array(
            "GET \(requestTarget) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".utf8
        )
        guard send(fd, request, request.count, 0) == request.count else { return nil }

        var response = [UInt8]()
        let capacity = 4096
        var buffer = [UInt8](repeating: 0, count: capacity)
        while response.count < 64 * 1024 {
            let count = recv(fd, &buffer, capacity, 0)
            if count <= 0 { break }
            response.append(contentsOf: buffer[0..<count])
        }
        guard !response.isEmpty else { return nil }
        return String(decoding: response, as: UTF8.self).components(separatedBy: "\r\n").first
    }

    // MARK: - Which LAN address a receiver can reach (local-server-network-env-4)

    @Test
    func linkLocalAndCLATAddressesAreNotReceiverReachable() {
        // No DHCP lease.
        #expect(!LocalHTTPServer.isReceiverReachableIPv4("169.254.3.4"))
        #expect(!LocalHTTPServer.isReceiverReachableIPv4("169.254.0.1"))
        // 192.0.0.0/29: the phone's own IPv4 translation address on an IPv6-only
        // network (RFC 7335). Nothing else on the LAN can route to it.
        #expect(!LocalHTTPServer.isReceiverReachableIPv4("192.0.0.0"))
        #expect(!LocalHTTPServer.isReceiverReachableIPv4("192.0.0.2"))
        #expect(!LocalHTTPServer.isReceiverReachableIPv4("192.0.0.7"))
        // The /29 ends there; the rest of 192.0.0.0/24 and its neighbours are not it.
        #expect(LocalHTTPServer.isReceiverReachableIPv4("192.0.0.8"))
        #expect(LocalHTTPServer.isReceiverReachableIPv4("192.0.0.170"))
        #expect(LocalHTTPServer.isReceiverReachableIPv4("192.0.2.2"))
        #expect(LocalHTTPServer.isReceiverReachableIPv4("192.168.0.2"))
        // Ordinary private ranges, the hotspot range included.
        #expect(LocalHTTPServer.isReceiverReachableIPv4("192.168.1.20"))
        #expect(LocalHTTPServer.isReceiverReachableIPv4("10.0.0.5"))
        #expect(LocalHTTPServer.isReceiverReachableIPv4("172.20.10.1"))
        #expect(LocalHTTPServer.isReceiverReachableIPv4("169.253.1.1"))
    }

    // MARK: - Storage budget (a VOD cast keeps every segment on disk)

    @Test
    func storageBudgetIsAQuarterOfFreeSpaceWithinBounds() {
        let mb: Int64 = 1024 * 1024
        let gb: Int64 = 1024 * mb
        #expect(AirPlayRemuxSession.maximumStorageBudgetBytes == 4 * gb)
        #expect(AirPlayRemuxSession.minimumStorageBudgetBytes == 512 * mb)
        // Plenty of room: capped at 4 GB.
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 100 * gb) == 4 * gb)
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 16 * gb) == 4 * gb)
        // In between: a quarter of what is free.
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 8 * gb) == 2 * gb)
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 2 * gb) == 512 * mb)
        // Nearly full: never below the floor (a smaller budget would be passed
        // before playback settles, and every rebuild would trigger the next).
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 1 * gb) == 512 * mb)
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 1) == 512 * mb)
        // Unknown free space (nil, or the 0 the system reports when it cannot tell).
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: nil) == 4 * gb)
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: 0) == 4 * gb)
        #expect(AirPlayRemuxSession.storageBudgetBytes(availableCapacity: -1) == 4 * gb)
    }

    @Test
    func storageBudgetIsPassedAtTheBudgetNotBefore() {
        #expect(!AirPlayRemuxSession.storageBudgetExceeded(bytesWritten: 0, budgetBytes: 1000))
        #expect(!AirPlayRemuxSession.storageBudgetExceeded(bytesWritten: 999, budgetBytes: 1000))
        #expect(AirPlayRemuxSession.storageBudgetExceeded(bytesWritten: 1000, budgetBytes: 1000))
        #expect(AirPlayRemuxSession.storageBudgetExceeded(bytesWritten: 5000, budgetBytes: 1000))
        // No budget is not a budget of zero.
        #expect(!AirPlayRemuxSession.storageBudgetExceeded(bytesWritten: 5000, budgetBytes: 0))
    }

    /// A rebuild is asked for on low free space only, never on a routine byte count.
    @Test
    func storageRebuildIsAskedOnlyWhenFreeSpaceIsLow() {
        let mb: Int64 = 1024 * 1024
        let gb: Int64 = 1024 * mb
        #expect(AirPlayRemuxSession.lowFreeSpaceBytes == 1536 * mb)
        // Plenty of room: never, however much the session has written.
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 600 * mb, availableCapacity: 100 * gb))
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 40 * gb, availableCapacity: 100 * gb))
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 40 * gb, availableCapacity: 1536 * mb))
        // Low, and the session holds enough for a rebuild to free something.
        #expect(AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 600 * mb, availableCapacity: 1 * gb))
        #expect(AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 512 * mb, availableCapacity: 1535 * mb))
        // Low, but a rebuild would free too little to help.
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 100 * mb, availableCapacity: 1 * gb))
        // Unknown free space (nil, or the 0 the system reports when it cannot tell).
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 40 * gb, availableCapacity: nil))
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 40 * gb, availableCapacity: 0))
        #expect(!AirPlayRemuxSession.storageRunningLow(
            bytesWritten: 40 * gb, availableCapacity: -1))
    }

    /// Only a full disk makes `stop()` delete the session directory at once; any
    /// other error keeps the delay that protects the handover.
    @Test
    func outOfSpaceIsRecognisedFromFFmpegAndFoundationErrors() {
        #expect(AirPlayRemuxSession.isOutOfSpace(RemuxHLSWriter.RemuxError.writeFailed(-ENOSPC)))
        #expect(AirPlayRemuxSession.isOutOfSpace(RemuxHLSWriter.RemuxError.writeFailed(-EDQUOT)))
        #expect(AirPlayRemuxSession.isOutOfSpace(RemuxHLSWriter.RemuxError.openOutputFailed(-ENOSPC)))
        #expect(AirPlayRemuxSession.isOutOfSpace(CocoaError(.fileWriteOutOfSpace)))
        #expect(AirPlayRemuxSession.isOutOfSpace(
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        ))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))]
        )
        #expect(AirPlayRemuxSession.isOutOfSpace(wrapped))

        // The muxer rejecting the stream (EINVAL), a source error, other file errors.
        #expect(!AirPlayRemuxSession.isOutOfSpace(RemuxHLSWriter.RemuxError.writeFailed(-EINVAL)))
        #expect(!AirPlayRemuxSession.isOutOfSpace(RemuxHLSWriter.RemuxError.readFailed(-ENOSPC)))
        #expect(!AirPlayRemuxSession.isOutOfSpace(RemuxHLSWriter.RemuxError.noCompatibleStreams))
        #expect(!AirPlayRemuxSession.isOutOfSpace(CocoaError(.fileWriteNoPermission)))
        #expect(!AirPlayRemuxSession.isOutOfSpace(URLError(.timedOut)))
    }

    // MARK: - Who fetched (receiver reachability evidence)

    @Test
    func peerAddressesAreNormalised() {
        // The dual-stack listener reports IPv4 peers as IPv4-mapped IPv6.
        #expect(LocalHTTPServer.normalizedAddress("::ffff:192.168.1.20") == "192.168.1.20")
        #expect(LocalHTTPServer.normalizedAddress("::FFFF:C0A8:0114") == "192.168.1.20")
        #expect(LocalHTTPServer.normalizedAddress("192.168.1.20") == "192.168.1.20")
        // The zone names the interface, not the host; spelling is canonicalised.
        #expect(LocalHTTPServer.normalizedAddress("fe80::1%en0") == "fe80::1")
        #expect(LocalHTTPServer.normalizedAddress("FE80:0000:0000:0000:0000:0000:0000:0001") == "fe80::1")
        #expect(LocalHTTPServer.normalizedAddress("2001:0DB8::0001") == "2001:db8::1")
        #expect(LocalHTTPServer.normalizedAddress(" Apple-TV.local ") == "apple-tv.local")
    }

    @Test
    func onlyPeersThatAreNotThisPhoneCountAsTheReceiver() {
        let own: Set<String> = ["127.0.0.1", "::1", "192.168.1.5", "fe80::1c2b:3aff:fe4d:5e6f%en0"]

        // The phone's own probes and the phone-side player.
        #expect(!LocalHTTPServer.isReceiverPeer("127.0.0.1", ownAddresses: own))
        #expect(!LocalHTTPServer.isReceiverPeer("127.0.0.53", ownAddresses: []))
        #expect(!LocalHTTPServer.isReceiverPeer("::1", ownAddresses: []))
        #expect(!LocalHTTPServer.isReceiverPeer("::ffff:127.0.0.1", ownAddresses: []))
        #expect(!LocalHTTPServer.isReceiverPeer("192.168.1.5", ownAddresses: own))
        #expect(!LocalHTTPServer.isReceiverPeer("::ffff:192.168.1.5", ownAddresses: own))
        #expect(!LocalHTTPServer.isReceiverPeer("FE80::1C2B:3AFF:FE4D:5E6F", ownAddresses: own))
        #expect(!LocalHTTPServer.isReceiverPeer("fe80::1c2b:3aff:fe4d:5e6f%en2", ownAddresses: own))

        // Anything else on the network is the receiver.
        #expect(LocalHTTPServer.isReceiverPeer("192.168.1.20", ownAddresses: own))
        #expect(LocalHTTPServer.isReceiverPeer("::ffff:192.168.1.20", ownAddresses: own))
        #expect(LocalHTTPServer.isReceiverPeer("fe80::aa:bbff:fecc:ddee%en0", ownAddresses: own))
        // Without the interface list the phone's LAN address cannot be told apart.
        #expect(LocalHTTPServer.isReceiverPeer("192.168.1.5", ownAddresses: []))
        // Unidentifiable: counted, because a missing stamp may end a cast.
        #expect(LocalHTTPServer.isReceiverPeer("", ownAddresses: own))
    }

    @Test
    func ownInterfaceAddressesIncludeLoopback() {
        let own = LocalHTTPServer.ownInterfaceAddresses()
        #expect(own.contains("127.0.0.1"))
        #expect(own.allSatisfy { !$0.contains("%") })
    }

    /// The per-session request record: what the receiver was served and refused,
    /// what the phone asked itself, and the stamp the receiver watchdog reads.
    @Test
    func fetchCountersKeepReceiverAndPhoneRequestsApart() {
        let server = LocalHTTPServer(directory: FileManager.default.temporaryDirectory)
        // Nothing is recorded for a session that is not tracked.
        server.noteRequest(session: "stray", fromReceiver: true, peer: "192.168.1.20")
        server.noteReceiverResponse(session: "stray", served: true)
        #expect(server.fetchCounters(session: "stray") == nil)
        #expect(server.lastReceiverFetch(session: "stray") == nil)

        server.beginTrackingReceiverFetches(session: "s1")
        #expect(server.fetchCounters(session: "s1") == LocalHTTPServer.FetchCounters())

        // The phone's own player: counted, never a receiver stamp.
        server.noteRequest(session: "s1", fromReceiver: false, peer: "127.0.0.1")
        server.noteRequest(session: "s1", fromReceiver: false, peer: nil)
        #expect(server.lastReceiverFetch(session: "s1") == nil)
        #expect(server.fetchCounters(session: "s1")?.phoneRequests == 2)

        // The receiver: stamped when the request arrives, whatever the answer.
        let before = Date()
        server.noteRequest(session: "s1", fromReceiver: true, peer: "192.168.1.20")
        let stamp = server.lastReceiverFetch(session: "s1")
        #expect(stamp != nil)
        #expect((stamp ?? .distantPast) >= before)
        server.noteReceiverResponse(session: "s1", served: false)
        server.noteRequest(session: "s1", fromReceiver: true, peer: "192.168.1.20")
        server.noteReceiverResponse(session: "s1", served: true)
        server.noteRequest(session: "s1", fromReceiver: true, peer: "192.168.1.20")
        server.noteReceiverResponse(session: "s1", served: true)

        let counters = server.fetchCounters(session: "s1")
        #expect(counters?.receiverServed == 2)
        #expect(counters?.receiverRefused == 1)
        #expect(counters?.phoneRequests == 2)
        #expect(counters?.lastReceiverFetch == server.lastReceiverFetch(session: "s1"))

        // Another session has its own record; ending the tracking drops it.
        server.beginTrackingReceiverFetches(session: "s2")
        #expect(server.fetchCounters(session: "s2") == LocalHTTPServer.FetchCounters())
        server.endTrackingReceiverFetches(session: "s1")
        #expect(server.fetchCounters(session: "s1") == nil)
        #expect(server.lastReceiverFetch(session: "s1") == nil)
    }

    /// The log line built from the record: counts and an age, never an address.
    @Test
    func fetchCounterSummaryIsOneLineWithoutAddresses() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let never = LocalHTTPServer.FetchCounters(phoneRequests: 7)
        #expect(never.summary(now: now) == "receiver never fetched; phone requests 7")

        let fetched = LocalHTTPServer.FetchCounters(
            receiverServed: 12, receiverRefused: 3, phoneRequests: 40,
            lastReceiverFetch: now.addingTimeInterval(-8.6)
        )
        #expect(fetched.summary(now: now)
            == "receiver served 12, refused 3, last fetch 8s ago; phone requests 40")
        // A stamp taken after `now` (the two clocks are read separately) is not negative.
        let ahead = LocalHTTPServer.FetchCounters(lastReceiverFetch: now.addingTimeInterval(0.4))
        #expect(ahead.summary(now: now)
            == "receiver served 0, refused 0, last fetch 0s ago; phone requests 0")
        for summary in [never.summary(now: now), fetched.summary(now: now)] {
            #expect(!summary.contains("\n"))
            #expect(!summary.contains("://"))
            #expect(!summary.contains("192."))
        }
    }

    /// What goes into the log from an AVPlayerItem error-log entry: domain, status
    /// code and comment. The entry's URI and server address are never passed in.
    @Test
    func errorLogEntryDescriptionCarriesDomainCodeAndComment() {
        #expect(
            AirPlayCastPlayer.describeErrorLogEvent(
                statusCode: -12938, domain: "CoreMediaErrorDomain", comment: "HTTP 404: File Not Found"
            ) == "CoreMediaErrorDomain -12938 (HTTP 404: File Not Found)"
        )
        #expect(
            AirPlayCastPlayer.describeErrorLogEvent(
                statusCode: -1001, domain: "NSURLErrorDomain", comment: nil
            ) == "NSURLErrorDomain -1001"
        )
        #expect(
            AirPlayCastPlayer.describeErrorLogEvent(
                statusCode: 0, domain: "CoreMediaErrorDomain", comment: "  \n"
            ) == "CoreMediaErrorDomain 0"
        )
        #expect(AirPlayCastPlayer.maximumRecordedEventsPerItem > 0)
    }

    /// The listener's health over loopback, a restart after it is gone, and that
    /// the phone's own requests never count as a receiver fetch.
    @Test(.timeLimit(.minutes(1)))
    func listenerHealthRestartAndLoopbackAttribution() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-health-\(UUID().uuidString)", isDirectory: true)
        let sessionDir = dir.appendingPathComponent("s1", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("#EXTM3U\n".utf8).write(to: sessionDir.appendingPathComponent("stream.m3u8"))

        let server = LocalHTTPServer(directory: dir)
        defer { server.stop() }
        func isHealthy() async -> Bool {
            await withCheckedContinuation { continuation in
                server.checkHealth { continuation.resume(returning: $0) }
            }
        }

        // Never started: nothing answers.
        let healthyBeforeStart = await isHealthy()
        #expect(!healthyBeforeStart)
        try server.start()
        let firstPort = server.port
        #expect(firstPort > 0)
        #expect(await isHealthy())
        // A serving listener is left alone.
        #expect(server.ensureRunning() == false)
        #expect(server.port == firstPort)

        server.beginTrackingReceiverFetches(session: "s1")
        let (_, response) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(firstPort)/s1/stream.m3u8")!
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.lastReceiverFetch(session: "s1") == nil)
        // It is counted as the phone's own request, and as nothing else.
        #expect(
            server.fetchCounters(session: "s1")
                == LocalHTTPServer.FetchCounters(phoneRequests: 1)
        )

        // Listener gone (what a suspension does): it comes back, and the result
        // says whether the URLs handed out before still point at it.
        server.stop()
        #expect(server.port == 0)
        let healthyWhileStopped = await isHealthy()
        #expect(!healthyWhileStopped)
        let moved = server.ensureRunning()
        #expect(server.port > 0)
        #expect(moved == (server.port != firstPort))
        #expect(await isHealthy())
    }
}
