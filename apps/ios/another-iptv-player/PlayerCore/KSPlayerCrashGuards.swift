import AVFoundation
import Foundation
import KSPlayer
import Libavcodec
import ObjectiveC
import VideoToolbox

/// `KSOptions` that steers playback away from KSPlayer code paths known to crash.
///
/// The failures guarded here are a NULL dereference and a Metal abort inside KSPlayer.
/// Neither is a thrown error, so they cannot be caught — each guard instead avoids the
/// condition that leads there.
///
/// `nonisolated`: KSPlayer calls these hooks on its own open/read threads.
nonisolated final class GuardedKSOptions: KSOptions {
  private let lock = NSLock()
  private var undecodable: Set<Int32> = []

  /// Stream indexes FFmpeg cannot open a decoder for. Filled while the source opens;
  /// such a track must never be selected (see `firstDecodableIndexIfNeeded`).
  var undecodableTrackIDs: Set<Int32> {
    lock.lock()
    defer { lock.unlock() }
    return undecodable
  }

  override func wantedVideo(tracks: [MediaPlayerTrack]) -> Int? {
    firstDecodableIndexIfNeeded(in: tracks)
  }

  override func wantedAudio(tracks: [MediaPlayerTrack]) -> Int? {
    firstDecodableIndexIfNeeded(in: tracks)
  }

  override func process(assetTrack: some MediaPlayerTrack) {
    super.process(assetTrack: assetTrack)
    guard let track = assetTrack as? FFmpegAssetTrack else { return }
    if undecodableTrackIDs.contains(track.trackID) {
      // No decodable alternative existed. Discard the stream's packets so the dead
      // decoder is never created; the load then fails through the regular timeout.
      track.isEnabled = false
      return
    }
    guard track.mediaType == .video,
          let filter = Self.softwareTenBitFilter(
            codecName: track.codecName,
            pixelFormat: track.formatName,
            hardwareDecode: hardwareDecode
          )
    else { return }
    hardwareDecode = false
    // KSPlayer calls this hook again whenever it reopens the source.
    if !videoFilters.contains(filter) {
      videoFilters.append(filter)
    }
  }

  /// KSPlayer keeps an `FFmpegDecode` whose codec context failed to open and later
  /// passes its NULL context to `avcodec_flush_buffers` on the next seek. The hooks are
  /// called with every track of a kind while the format context is still open, which
  /// is the one safe moment to probe them.
  ///
  /// Returns nil (FFmpeg's own pick) unless some track is undecodable.
  private func firstDecodableIndexIfNeeded(in tracks: [MediaPlayerTrack]) -> Int? {
    let decodable = tracks.map { track in
      (track as? FFmpegAssetTrack).map(DecoderProbe.canDecode) ?? true
    }
    guard decodable.contains(false) else { return nil }
    lock.lock()
    for (track, ok) in zip(tracks, decodable) where !ok {
      undecodable.insert(track.trackID)
    }
    lock.unlock()
    return decodable.firstIndex(of: true)
  }

  /// Software-decoded planar 10-bit frames are the only ones KSPlayer draws through its
  /// own Metal pipeline, and the 10-bit variant of that pipeline aborts in Metal
  /// validation. Converting them to the bi-planar layout VideoToolbox emits sends them
  /// down the `AVSampleBufferDisplayLayer` path instead.
  ///
  /// Returns the libavfilter chain to append, or nil when the track is unaffected.
  /// A track VideoToolbox decodes is left alone: its frames are already
  /// `CVPixelBuffer`s, and a filter graph must not run over VideoToolbox frames.
  static func softwareTenBitFilter(
    codecName: String,
    pixelFormat: String?,
    hardwareDecode: Bool,
    isHardwareSupported: (CMVideoCodecType) -> Bool = VTIsHardwareDecodeSupported
  ) -> String? {
    let target: String
    switch pixelFormat {
    case "yuv420p10le": target = "p010le"
    case "yuv422p10le": target = "p210le"
    case "yuv444p10le": target = "p410le"
    default: return nil
    }
    if hardwareDecode,
       videoToolboxDecodesTenBit(DecoderProbe.baseName(of: codecName), isHardwareSupported) {
      return nil
    }
    return "format=pix_fmts=\(target)"
  }

  /// Whether FFmpeg's VideoToolbox hwaccel yields 10-bit frames for `codec` on this
  /// device. H.264 has a hwaccel but VideoToolbox rejects its 10-bit profiles, and this
  /// FFmpeg build has no VideoToolbox hwaccel for AV1 — both always decode in software.
  private static func videoToolboxDecodesTenBit(
    _ codec: String, _ isHardwareSupported: (CMVideoCodecType) -> Bool
  ) -> Bool {
    switch codec {
    case "hevc":
      // The only codec opened with "enable" rather than "require" hardware, so
      // VideoToolbox still decodes it (in software) where the chip cannot.
      return true
    case "vp9": return isHardwareSupported(kCMVideoCodecType_VP9)
    case "prores": return isHardwareSupported(kCMVideoCodecType_AppleProRes422)
    default: return false
    }
  }
}

/// Predicts whether KSPlayer will manage to create a decoder for a track by opening one
/// the same way `AVCodecParameters.createContext` does.
nonisolated enum DecoderProbe {
  static func canDecode(_ track: FFmpegAssetTrack) -> Bool {
    if var parameters = codecParameters(of: track) {
      return canOpenDecoder(&parameters)
    }
    return hasDecoder(named: track.codecName)
  }

  /// FFmpegKit ships a decoder allow-list, so a codec FFmpeg can demux is not
  /// necessarily one it can decode (WavPack, Speex, Theora, PNG cover art…).
  static func hasDecoder(named codecName: String) -> Bool {
    guard let descriptor = avcodec_descriptor_get_by_name(baseName(of: codecName)) else {
      return false
    }
    return avcodec_find_decoder(descriptor.pointee.id) != nil
  }

  /// KSPlayer reports codec names with the profile appended ("h264 (High)").
  static func baseName(of codecName: String) -> String {
    codecName.split(separator: " ").first.map { $0.lowercased() } ?? ""
  }

  static func canOpenDecoder(_ parameters: inout AVCodecParameters) -> Bool {
    guard let codec = avcodec_find_decoder(parameters.codec_id) else { return false }
    var context = avcodec_alloc_context3(nil)
    defer { avcodec_free_context(&context) }
    guard avcodec_parameters_to_context(context, &parameters) == 0 else { return false }
    return avcodec_open2(context, codec, nil) == 0
  }

  /// `FFmpegAssetTrack.codecpar` is internal to KSPlayer. Reflection reads it without a
  /// fork; if the field is ever renamed the probe degrades to the name-based check.
  private static func codecParameters(of track: FFmpegAssetTrack) -> AVCodecParameters? {
    Mirror(reflecting: track).children
      .first { $0.label == "codecpar" }?.value as? AVCodecParameters
  }
}

/// `KSAVPlayer` converts `AVAssetTrack.estimatedDataRate` with a trapping `Int64(_:)`,
/// and AVFoundation reports NaN/infinity for some streams. Wrapping the getter once
/// makes every caller see a finite value.
nonisolated enum AVAssetTrackDataRateGuard {
  static func install() {
    _ = installed
  }

  static func sanitized(_ rate: Float) -> Float {
    rate.isFinite ? min(max(rate, 0), 1e12) : 0
  }

  /// Replaces `selector`'s implementation on `cls` with one that sanitizes its result.
  @discardableResult
  static func wrapFloatGetter(_ selector: Selector, on cls: AnyClass) -> Bool {
    guard let method = class_getInstanceMethod(cls, selector) else { return false }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Float
    let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
    let replacement: @convention(block) (AnyObject) -> Float = { object in
      sanitized(original(object, selector))
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
    return true
  }

  // By name: `#selector` would reference the getter deprecated in iOS 16, which is
  // exactly the one KSPlayer still reads.
  private static let installed: Bool = wrapFloatGetter(
    NSSelectorFromString("estimatedDataRate"), on: AVAssetTrack.self
  )
}
