import Foundation
import Testing
@testable import another_iptv_player

/// Regresyon kilitleri: 18 tur cihaz-testi düzeltmelerinin saf-fonksiyon çekirdekleri.
/// (Kaynak: ios-ksplayer-stability-review.md — test-gap bulguları.)

// MARK: - Deterministik video DTS sentezi (18. tur A/V kayma düzeltmesi)

struct TimestampRepairTests {
    typealias Repair = RemuxHLSWriter.TimestampRepair

    /// Friends-MKV izi: konteyner dts'i hiç verilmez, pts monoton, sabit kare süresi.
    /// dts kare hızında monoton artmalı ve pts'leri asla aşmamalı.
    @Test func videoSynthesizesMonotonicDTSFromMissingContainerDTS() throws {
        var repair = Repair()
        let frameDur: Int64 = 3600  // 25fps @ 90kHz
        var lastDTS = Int64.min
        for i in 0..<120 {
            let pts = Int64(i) * frameDur
            let out = repair.repairVideo(pts: pts, duration: frameDur)
            let repaired = try #require(out)
            #expect(repaired.dts > lastDTS, "dts must be strictly monotonic at frame \(i)")
            #expect(repaired.dts <= repaired.pts, "dts must never exceed pts at frame \(i)")
            if lastDTS != Int64.min {
                #expect(repaired.dts - lastDTS == frameDur, "dts must tick at frame rate")
            }
            lastDTS = repaired.dts
        }
    }

    /// İlk kare pts'siz gelirse atlanır; pts'li ilk karede decode saati pts-4×süre kurulur.
    @Test func firstFrameWithoutPTSIsSkipped() throws {
        var repair = Repair()
        #expect(repair.repairVideo(pts: Int64.min, duration: 3600) == nil)
        let outRaw = repair.repairVideo(pts: 14400, duration: 3600)

        let out = try #require(outRaw)
        #expect(out.pts == 14400)
        #expect(out.dts == 14400 - 4 * 3600)
    }

    /// B-frame reorder: pts'ler decode sırasında (I P B B → pts 0,3,1,2 gibi) karışık
    /// gelir; sentezlenen dts yine monoton kalmalı ve hiçbir karede pts'i aşmamalı.
    @Test func bFrameReorderKeepsInvariant() throws {
        var repair = Repair()
        let dur: Int64 = 3600
        // Decode sırası pts'leri: keyframe 3, sonra 1, 2, 6, 4, 5 (×dur).
        let ptsSequence: [Int64] = [3, 1, 2, 6, 4, 5].map { $0 * dur }
        var lastDTS = Int64.min
        for pts in ptsSequence {
            let outRaw = repair.repairVideo(pts: pts, duration: dur)

            let out = try #require(outRaw)
            #expect(out.dts > lastDTS)
            #expect(out.dts <= out.pts)
            lastDTS = out.dts
        }
    }

    /// Geriye zaman sıçraması (panel reconnect/splice): monotonluk bump'ı dts'i ham
    /// pts'in üstüne iter — pts kaldırılmalı ki muxer EINVAL ile ölmesin (Faz B).
    @Test func backwardJumpLiftsPTSInsteadOfViolatingInvariant() throws {
        var repair = Repair()
        let dur: Int64 = 3600
        for i in 0..<10 {
            _ = repair.repairVideo(pts: Int64(i) * dur, duration: dur)
        }
        // Kaynak 10 kare sonra 0'a geri sıçradı.
        let outRaw = repair.repairVideo(pts: 0, duration: dur)

        let out = try #require(outRaw)
        #expect(out.dts <= out.pts, "invariant must hold after a backward jump")
        // Sonraki kareler de monoton sürmeli.
        var lastDTS = out.dts
        for i in 1..<5 {
            let nextRaw = repair.repairVideo(pts: Int64(i) * dur, duration: dur)

            let next = try #require(nextRaw)
            #expect(next.dts > lastDTS)
            #expect(next.dts <= next.pts)
            lastDTS = next.dts
        }
    }

    /// Süre alanı 0 gelen karelerde son bilinen süre kullanılır; saat kilitlenmez.
    @Test func zeroDurationFallsBackToLastKnown() throws {
        var repair = Repair()
        let dur: Int64 = 3600
        _ = repair.repairVideo(pts: 0, duration: dur)
        let aRaw = repair.repairVideo(pts: dur, duration: 0)

        let a = try #require(aRaw)
        let bRaw = repair.repairVideo(pts: 2 * dur, duration: 0)
        let b = try #require(bRaw)
        #expect(a.dts - (0 - 4 * dur) == dur, "0-duration frame must advance by last known duration")
        #expect(b.dts - a.dts == dur)
    }

    /// Ses: her iki damga da eksikse referans doğana kadar paket atlanır; sonra
    /// son dts + süre ile sentezlenir.
    @Test func audioMissingTimestampsSynthesizedFromClock() throws {
        var repair = Repair()
        #expect(repair.repairAudio(pts: Int64.min, dts: Int64.min, duration: 1920) == nil)
        let firstRaw = repair.repairAudio(pts: 0, dts: 0, duration: 1920)

        let first = try #require(firstRaw)
        #expect(first.dts == 0)
        let synthRaw = repair.repairAudio(pts: Int64.min, dts: Int64.min, duration: 1920)

        let synth = try #require(synthRaw)
        #expect(synth.dts == 1920)
        #expect(synth.pts == 1920)
    }

    /// Ses: geri giden dts bump'lanır, pts en az dts'e çekilir.
    @Test func audioBackwardDTSBumped() throws {
        var repair = Repair()
        _ = repair.repairAudio(pts: 5000, dts: 5000, duration: 1920)
        let outRaw = repair.repairAudio(pts: 4000, dts: 4000, duration: 1920)

        let out = try #require(outRaw)
        #expect(out.dts == 5001)
        #expect(out.pts >= out.dts)
    }
}

// MARK: - Cast başlama eşiği (13-14. tur tampon kapıları)

struct PlaylistReadinessTests {
    private func playlist(extinf: [Double], endlist: Bool = false) -> String {
        var lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:4"]
        for d in extinf {
            lines.append(String(format: "#EXTINF:%.3f,", d))
            lines.append("seg.ts")
        }
        if endlist { lines.append("#EXT-X-ENDLIST") }
        return lines.joined(separator: "\n")
    }

    @Test func endlistAlwaysWins() {
        #expect(AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [1.0], endlist: true),
            isLive: false, minimumBufferSeconds: 12
        ))
        #expect(AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [], endlist: true),
            isLive: true, minimumBufferSeconds: 12
        ))
    }

    @Test func liveNeedsThreeSegments() {
        #expect(!AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [1.5, 1.5]),
            isLive: true, minimumBufferSeconds: 12
        ))
        #expect(AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [1.5, 1.5, 1.5]),
            isLive: true, minimumBufferSeconds: 12
        ))
    }

    @Test func vodNeedsBufferSum() {
        #expect(!AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [4, 4, 3.9]),
            isLive: false, minimumBufferSeconds: 12
        ))
        #expect(AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [4, 4, 4]),
            isLive: false, minimumBufferSeconds: 12
        ))
        // Seek yenilemesi düşük eşikle bekler.
        #expect(AirPlayRemuxSession.playlistReady(
            content: playlist(extinf: [4, 1.5]),
            isLive: false, minimumBufferSeconds: 5
        ))
    }

    @Test func malformedEXTINFLinesAreIgnored() {
        let content = """
        #EXTM3U
        #EXTINF:abc,
        seg0.ts
        #EXTINF:4.000,
        seg1.ts
        """
        #expect(!AirPlayRemuxSession.playlistReady(
            content: content, isLive: false, minimumBufferSeconds: 12
        ))
        #expect(AirPlayRemuxSession.playlistReady(
            content: content, isLive: false, minimumBufferSeconds: 4
        ))
    }
}

// MARK: - Motor sırası seçimi (1. tur açılış-süresi düzeltmesi)

struct EngineOrderSelectionTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func avPlayerFamilyGoesAVPlayerFirst() {
        #expect(!KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/movie.mp4")))
        #expect(!KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/live/stream.m3u8")))
        #expect(!KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/clip.MOV")))
        #expect(!KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/movie.m4v")))
    }

    /// KSAVPlayer fails every item without a playable video track, so an audio-only
    /// URL sent there first was opened twice and ended on FFmpeg anyway.
    @Test func audioOnlyFilesGoFFmpegFirst() {
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/radio.mp3")))
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/song.m4a")))
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/stream.AAC")))
    }

    /// The engine's open order is not the same question as "can a plain AVPlayer play
    /// it": the cast player has no video-track check and plays audio files natively.
    @Test func audioOnlyFilesStayAVFoundationPlayable() {
        for name in ["radio.mp3", "song.m4a", "stream.AAC", "movie.mp4", "live/stream.m3u8", "clip.MOV"] {
            #expect(KSPlayerEngine.isAVFoundationPlayable(url("http://host/\(name)")), "\(name)")
        }
        #expect(!KSPlayerEngine.isAVFoundationPlayable(url("http://host/movie.mkv")))
        #expect(!KSPlayerEngine.isAVFoundationPlayable(url("http://host/channel.ts")))
        #expect(!KSPlayerEngine.isAVFoundationPlayable(url("http://host:8080/user/pass/12345")))
    }

    @Test func ffmpegContainersGoFFmpegFirst() {
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/movie.mkv")))
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/movie.avi")))
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host/channel.ts")))
    }

    /// Uzantısız Xtream canlı URL'leri (http://host/user/pass/12345) FFmpeg'e gitmeli.
    @Test func extensionlessXtreamLiveGoesFFmpegFirst() {
        #expect(KSPlayerEngine.prefersFFmpegFirst(for: url("http://host:8080/user/pass/12345")))
    }
}

// MARK: - Cast player item swap (the paused state must survive a load)

struct AirPlayCastPlayerLoadTests {
    /// `replaceCurrentItem` keeps the player's rate, so an item loaded with
    /// `autoPlay: false` behind a playing one used to start by itself (a cast paused
    /// on the TV resumed after a seek rebuild). Only the requested rate is checked,
    /// synchronously; the URLs are never played.
    @Test func loadWithoutAutoPlayPausesAPlayingPlayer() {
        let player = AirPlayCastPlayer()
        defer { player.dispose() }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        player.load(
            url: directory.appendingPathComponent("cast-swap-a.m3u8"),
            startAt: nil, autoPlay: true
        )
        player.load(
            url: directory.appendingPathComponent("cast-swap-b.m3u8"),
            startAt: nil, autoPlay: false, userAgent: "TestAgent/1.0"
        )
        #expect(player.isPaused)
    }
}

// MARK: - Info.plist güvenceleri (2. tur: eksik yerel-ağ izni bir cihaz turu yaktı)

struct InfoPlistGuardTests {
    @Test func localNetworkUsageDescriptionPresent() {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription")
            as? String
        #expect(!(value ?? "").isEmpty, "NSLocalNetworkUsageDescription must exist — its absence cost a device-test round (AirPlay cast could not reach the phone's HTTP server)")
    }

    @Test func backgroundAudioModeDeclared() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("audio") == true, "background audio keeps playback alive when the screen locks")
    }
}
