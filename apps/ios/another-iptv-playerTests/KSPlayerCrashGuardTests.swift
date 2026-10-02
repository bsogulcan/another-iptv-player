import AVFoundation
import Foundation
import KSPlayer
import Libavcodec
import Libavutil
import ObjectiveC
import Testing
@testable import another_iptv_player

/// Guards for the KSPlayer crashes found in the 2.4.0 crash reports. The crashes
/// themselves only reproduce with real media on the player; these lock the decisions
/// that keep playback off those paths.

// MARK: - 10-bit software frames (Metal pipeline abort)

struct SoftwareTenBitFilterTests {
    private func filter(
        _ codec: String, _ format: String?, hardware: Bool = true, chipSupport: Bool = true
    ) -> String? {
        GuardedKSOptions.softwareTenBitFilter(
            codecName: codec, pixelFormat: format, hardwareDecode: hardware,
            isHardwareSupported: { _ in chipSupport }
        )
    }

    /// H.264 Hi10P and AV1 never reach VideoToolbox in this FFmpeg build, whatever
    /// the chip supports: their planar 10-bit frames must be converted.
    @Test func softwareOnlyCodecsAreConverted() {
        #expect(filter("h264 (High 10)", "yuv420p10le") == "format=pix_fmts=p010le")
        #expect(filter("av1 (Main)", "yuv420p10le") == "format=pix_fmts=p010le")
    }

    @Test func chromaSubsamplingIsPreserved() {
        #expect(filter("h264 (High 4:2:2)", "yuv422p10le") == "format=pix_fmts=p210le")
        #expect(filter("h264 (High 4:4:4 Predictive)", "yuv444p10le") == "format=pix_fmts=p410le")
    }

    /// HDR HEVC is the common case and goes through VideoToolbox: no filter may be
    /// added, because a filter graph must not run over VideoToolbox frames.
    @Test func hevcStaysOnVideoToolbox() {
        #expect(filter("hevc (Main 10)", "yuv420p10le") == nil)
        #expect(filter("hevc (Rext)", "yuv422p10le") == nil)
        #expect(filter("hevc (Main 10)", "yuv420p10le", chipSupport: false) == nil)
    }

    /// Playback that hardware decode already handles must not be forced to software.
    @Test func chipDependentCodecsFollowTheChip() {
        #expect(filter("vp9 (Profile 2)", "yuv420p10le", chipSupport: true) == nil)
        #expect(filter("vp9 (Profile 2)", "yuv420p10le", chipSupport: false) == "format=pix_fmts=p010le")
        #expect(filter("prores (HQ)", "yuv422p10le", chipSupport: true) == nil)
        #expect(filter("prores (HQ)", "yuv422p10le", chipSupport: false) == "format=pix_fmts=p210le")
    }

    /// KSPlayer turns hardware decode off for interlaced or rotated video; every codec
    /// then produces planar frames.
    @Test func softwareDecodedHEVCIsConverted() {
        #expect(filter("hevc (Main 10)", "yuv420p10le", hardware: false) == "format=pix_fmts=p010le")
        #expect(filter("vp9 (Profile 2)", "yuv420p10le", hardware: false) == "format=pix_fmts=p010le")
    }

    @Test func otherFormatsAreUnaffected() {
        #expect(filter("h264 (High)", "yuv420p") == nil)
        #expect(filter("hevc (Main)", "yuv420p", hardware: false) == nil)
        #expect(filter("hevc (Rext)", "yuv420p12le", hardware: false) == nil)
        #expect(filter("h264", nil) == nil)
    }
}

// MARK: - Undecodable tracks (NULL codec context flushed on seek)

struct DecoderProbeTests {
    @Test func profileSuffixIsStripped() {
        #expect(DecoderProbe.baseName(of: "h264 (High)") == "h264")
        #expect(DecoderProbe.baseName(of: "AAC") == "aac")
        #expect(DecoderProbe.baseName(of: "") == "")
    }

    @Test func commonIPTVCodecsHaveDecoders() {
        for codec in ["h264 (High)", "hevc (Main 10)", "mpeg2video", "aac (LC)", "ac3", "eac3", "mp2", "dts"] {
            #expect(DecoderProbe.hasDecoder(named: codec), "\(codec) must be decodable")
        }
    }

    /// FFmpegKit demuxes these but ships no decoder for them.
    @Test func codecsOutsideTheAllowListAreReported() {
        #expect(!DecoderProbe.hasDecoder(named: "wavpack"))
        #expect(!DecoderProbe.hasDecoder(named: "theora"))
        #expect(!DecoderProbe.hasDecoder(named: "png"))
        #expect(!DecoderProbe.hasDecoder(named: ""))
        #expect(!DecoderProbe.hasDecoder(named: "not-a-codec"))
    }

    @Test func openingADecoderMatchesAvailability() throws {
        let parameters = try #require(avcodec_parameters_alloc())
        var owned: UnsafeMutablePointer<AVCodecParameters>? = parameters
        defer { avcodec_parameters_free(&owned) }

        parameters.pointee.codec_type = AVMEDIA_TYPE_AUDIO
        parameters.pointee.sample_rate = 48000
        av_channel_layout_default(&parameters.pointee.ch_layout, 2)

        parameters.pointee.codec_id = AV_CODEC_ID_AC3
        #expect(DecoderProbe.canOpenDecoder(&parameters.pointee))

        parameters.pointee.codec_id = AV_CODEC_ID_WAVPACK
        #expect(!DecoderProbe.canOpenDecoder(&parameters.pointee))
    }
}

// MARK: - Audio track chosen while the source opens

struct WantedAudioIndexTests {
    private func index(
        _ languages: [String?],
        decodable: [Bool]? = nil,
        hasAudioFormat: [Bool]? = nil,
        preferred: String?
    ) -> Int? {
        GuardedKSOptions.wantedAudioIndex(
            languageCodes: languages,
            decodable: decodable ?? languages.map { _ in true },
            hasAudioFormat: hasAudioFormat ?? languages.map { _ in true },
            preferredLanguage: preferred
        )
    }

    /// nil leaves the choice to FFmpeg, as before the preference was hooked up.
    @Test func withoutAPreferenceFFmpegChooses() {
        #expect(index(["eng", "tur"], preferred: nil) == nil)
        #expect(index(["eng", "tur"], preferred: "") == nil)
        #expect(index([], preferred: "tur") == nil)
    }

    @Test func preferredLanguageIsChosenBeforePlayback() {
        #expect(index(["eng", "tur", "deu"], preferred: "tur") == 1)
        // Stored as two letters, tagged with three.
        #expect(index(["eng", "ger"], preferred: "de") == 1)
        #expect(index(["eng", nil, "tur"], preferred: "tr") == 2)
    }

    @Test func unknownPreferenceLeavesFFmpegsChoice() {
        #expect(index(["eng", "deu"], preferred: "tur") == nil)
        #expect(index([nil, nil], preferred: "tur") == nil)
    }

    /// A track without a decoder must never be asked for, preferred or not: KSPlayer
    /// would keep its dead decoder and crash on the next seek.
    @Test func undecodablePreferredTrackIsSkipped() {
        #expect(index(["tur", "eng"], decodable: [false, true], preferred: "tur") == 1)
        #expect(index(["tur", "eng", "tur"], decodable: [false, true, true], preferred: "tur") == 2)
    }

    /// The guard that existed before the preference: with an undecodable track in the
    /// list the first decodable one is named, and nothing when none is.
    @Test func undecodableTracksStillSteerTheChoice() {
        #expect(index(["eng", "tur"], decodable: [false, true], preferred: nil) == 1)
        #expect(index(["eng", "tur"], decodable: [false, false], preferred: "tur") == nil)
        #expect(GuardedKSOptions.firstDecodableIndexIfNeeded([true, true]) == nil)
        #expect(GuardedKSOptions.firstDecodableIndexIfNeeded([false, true, true]) == 1)
        #expect(GuardedKSOptions.firstDecodableIndexIfNeeded([]) == nil)
    }

    /// FFmpeg finds nothing when asked for a stream whose parameters are unknown, and
    /// KSPlayer then enables the first audio track instead of FFmpeg's best one.
    @Test func trackWithoutAudioFormatIsNotAskedFor() {
        #expect(index(["eng", "tur"], hasAudioFormat: [true, false], preferred: "tur") == nil)
        #expect(index(["eng", "tur", "tur"], hasAudioFormat: [true, false, true], preferred: "tur") == 2)
        // A shorter list leaves the remaining tracks selectable.
        #expect(index(["eng", "tur"], hasAudioFormat: [], preferred: "tur") == 1)
    }

    @Test func audioFormatNeedsChannelsAndSampleRate() {
        #expect(DecoderProbe.isKnownAudioFormat(sampleRate: 48000, channelCount: 2))
        #expect(!DecoderProbe.isKnownAudioFormat(sampleRate: 0, channelCount: 2))
        #expect(!DecoderProbe.isKnownAudioFormat(sampleRate: 48000, channelCount: 0))
        #expect(!DecoderProbe.isKnownAudioFormat(sampleRate: 0, channelCount: 0))
    }
}

// MARK: - Non-finite AVAssetTrack data rate (trapping Int64 conversion)

private final class DataRateStub: NSObject {
    var rate: Float = 0
    @objc dynamic func estimatedDataRate() -> Float { rate }
}

struct AVAssetTrackDataRateGuardTests {
    @Test func nonFiniteAndNegativeRatesBecomeZero() {
        #expect(AVAssetTrackDataRateGuard.sanitized(.nan) == 0)
        #expect(AVAssetTrackDataRateGuard.sanitized(.infinity) == 0)
        #expect(AVAssetTrackDataRateGuard.sanitized(-.infinity) == 0)
        #expect(AVAssetTrackDataRateGuard.sanitized(-1) == 0)
    }

    @Test func ordinaryRatesPassThrough() {
        #expect(AVAssetTrackDataRateGuard.sanitized(0) == 0)
        #expect(AVAssetTrackDataRateGuard.sanitized(128_000) == 128_000)
    }

    /// Any value the wrapped getter returns must survive `Int64(_:)`, which is what
    /// KSAVPlayer does with it.
    @Test func wrappedGetterNeverReturnsATrappingValue() {
        let selector = #selector(DataRateStub.estimatedDataRate)
        #expect(AVAssetTrackDataRateGuard.wrapFloatGetter(selector, on: DataRateStub.self))
        let stub = DataRateStub()
        for rate in [Float.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            stub.rate = rate
            #expect(stub.estimatedDataRate().isFinite)
            _ = Int64(stub.estimatedDataRate())
        }
        stub.rate = 2_500_000
        #expect(stub.estimatedDataRate() == 2_500_000)
    }

    /// The guard patches the base class only, so no AVAssetTrack subclass may bring
    /// its own getter.
    @Test func noAssetTrackSubclassOverridesTheGetter() {
        let selector = NSSelectorFromString("estimatedDataRate")
        let base = class_getMethodImplementation(AVAssetTrack.self, selector)
        for name in ["AVFragmentedAssetTrack", "AVCompositionTrack", "AVMutableCompositionTrack"] {
            guard let cls = NSClassFromString(name) else { continue }
            #expect(class_getMethodImplementation(cls, selector) == base, "\(name) overrides the getter")
        }
    }
}

// MARK: - Capacity timer in the default run-loop mode (no start while scrolling)

private final class LazyTimerHolder {
    var first = 1
    var second = "two"
    lazy var timer: Timer = Timer(timeInterval: 60, repeats: true) { _ in }
}

private final class TimerlessHolder {
    var first = 1
}

@MainActor
struct KSPlayerRunLoopGuardTests {
    /// Pins the private property names the guard reads at the pinned KSPlayer revision.
    /// Building the item opens nothing: the source is only touched by `prepareToPlay()`.
    @Test func capacityTimerLabelMatchesKSPlayer() {
        let item = MEPlayerItem(url: URL(fileURLWithPath: "/dev/null"), options: GuardedKSOptions())
        defer { item.shutdown() }
        let timer = KSPlayerRunLoopGuard.timer(
            labelled: KSPlayerRunLoopGuard.capacityTimerLabel, of: item
        )
        #expect(timer != nil, "MEPlayerItem no longer stores a lazy `timer`")
        #expect(timer?.timeInterval == 0.05)
        #expect(timer?.isValid == true)
    }

    @Test func playerItemLabelMatchesKSPlayer() {
        let options = GuardedKSOptions()
        // No Metal view: the test only needs the player's stored properties.
        options.videoDisable = true
        let player = KSMEPlayer(url: URL(fileURLWithPath: "/dev/null"), options: options)
        defer { player.shutdown() }
        #expect(KSPlayerRunLoopGuard.child(labelled: KSPlayerRunLoopGuard.playerItemLabel, of: player) is MEPlayerItem)
        #expect(KSPlayerRunLoopGuard.capacityTimer(of: player) != nil)
        #expect(KSPlayerRunLoopGuard.promoteCapacityTimer(of: player))
        // Promoting twice is harmless.
        #expect(KSPlayerRunLoopGuard.promoteCapacityTimer(of: player))
    }

    /// A lazy property that was never used holds no timer yet.
    @Test func unusedLazyTimerIsNotFound() {
        let holder = LazyTimerHolder()
        #expect(KSPlayerRunLoopGuard.timer(labelled: KSPlayerRunLoopGuard.capacityTimerLabel, of: holder) == nil)
        let created = holder.timer
        #expect(KSPlayerRunLoopGuard.timer(labelled: KSPlayerRunLoopGuard.capacityTimerLabel, of: holder) === created)
        // The second read goes through the remembered position.
        #expect(KSPlayerRunLoopGuard.timer(labelled: KSPlayerRunLoopGuard.capacityTimerLabel, of: holder) === created)
    }

    /// A renamed or missing property must degrade to "nothing found", never trap.
    @Test func missingPropertyDegradesSilently() {
        let holder = TimerlessHolder()
        #expect(KSPlayerRunLoopGuard.child(labelled: "playerItem", of: holder) == nil)
        #expect(KSPlayerRunLoopGuard.timer(labelled: KSPlayerRunLoopGuard.capacityTimerLabel, of: holder) == nil)
        #expect(KSPlayerRunLoopGuard.child(labelled: "first", of: holder) as? Int == 1)
    }
}
