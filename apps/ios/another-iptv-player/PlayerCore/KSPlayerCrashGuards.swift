import AVFoundation
import Foundation
import KSPlayer
import Libavcodec
import Libavformat
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
  private var videoSuspended = false
  /// Last result of the end check in `playable(capacitys:isFirst:isSeek:)`; only
  /// meaningful while `videoSuspended` is set.
  private var audioEndedWhileSuspended = false
  /// The audio language saved from the user's last choice. Read once, when the load is
  /// set up: `wantedAudio(tracks:)` runs on KSPlayer's open thread.
  private let preferredAudioLanguage = PlaybackTrackPreferences.savedAudioLanguage()

  /// Stream indexes FFmpeg cannot open a decoder for. Filled while the source opens;
  /// such a track must never be selected (see `firstDecodableIndexIfNeeded`).
  var undecodableTrackIDs: Set<Int32> {
    lock.lock()
    defer { lock.unlock() }
    return undecodable
  }

  /// Set by the engine while it has switched the video track off in the background
  /// (see `playable(capacitys:isFirst:isSeek:)`).
  var isVideoSuspended: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return videoSuspended
    }
    set {
      lock.lock()
      videoSuspended = newValue
      audioEndedWhileSuspended = false
      lock.unlock()
    }
  }

  /// With the video track switched off, every audio queue reached the end of the
  /// source and is empty. KSPlayer never reports that end: the suspended video
  /// track's stale frames do not drain.
  var hasAudioEndedWhileVideoSuspended: Bool {
    lock.lock()
    defer { lock.unlock() }
    return videoSuspended && audioEndedWhileSuspended
  }

  /// KSPlayer throttles reading and decides "buffering or playable" from the least
  /// filled track. A video track that is switched off gets no more packets: once its
  /// queues are flushed (a skip from the lock screen) it stays empty, and with it in
  /// the list the player would report buffering forever and stop the audio.
  /// `LoadingState` has no public initializer, hence the call to `super` with the
  /// audio capacities only.
  override func playable(
    capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool
  ) -> LoadingState {
    guard isVideoSuspended else {
      return super.playable(capacitys: capacitys, isFirst: isFirst, isSeek: isSeek)
    }
    let audio = Self.audioCapacities(of: capacitys)
    // KSPlayer keeps calling this from its capacity timer until it reports the end of
    // the source itself, so the value follows the queues (a seek clears it again).
    let ended = Self.hasAudioEnded(audio)
    lock.lock()
    audioEndedWhileSuspended = ended
    lock.unlock()
    return super.playable(capacitys: audio, isFirst: isFirst, isSeek: isSeek)
  }

  /// Whether `capacitys` holds audio and every entry is at the end of the source with
  /// nothing left to decode or to play.
  static func hasAudioEnded(_ capacitys: [CapacityProtocol]) -> Bool {
    capacitys.contains { $0.mediaType == .audio }
      && capacitys.allSatisfy { $0.isEndOfFile && $0.frameCount == 0 && $0.packetCount == 0 }
  }

  /// The audio entries of `capacitys`, or all of them when there is no audio: an empty
  /// list would read as "end of file, playable" to KSPlayer.
  static func audioCapacities(of capacitys: [CapacityProtocol]) -> [CapacityProtocol] {
    let audio = capacitys.filter { $0.mediaType == .audio }
    return audio.isEmpty ? capacitys : audio
  }

  override func wantedVideo(tracks: [MediaPlayerTrack]) -> Int? {
    firstDecodableIndexIfNeeded(in: tracks)
  }

  /// Besides steering away from undecodable tracks, this is where the saved audio
  /// language is applied: the track chosen here is the one playback starts with.
  /// Switching to it after the first frame instead costs a seek and an audio flush.
  override func wantedAudio(tracks: [MediaPlayerTrack]) -> Int? {
    let decodable = recordDecodability(of: tracks)
    return Self.wantedAudioIndex(
      languageCodes: tracks.map(\.languageCode),
      decodable: decodable,
      hasAudioFormat: tracks.map { track in
        (track as? FFmpegAssetTrack).map(DecoderProbe.hasAudioFormat) ?? true
      },
      preferredLanguage: preferredAudioLanguage
    )
  }

  /// The audio track to start with, as an index into the track list, or nil for
  /// FFmpeg's own pick.
  ///
  /// - Parameters:
  ///   - languageCodes: Language tag of every audio track, in track order.
  ///   - decodable: Whether FFmpeg can open a decoder for the track at the same index.
  ///   - hasAudioFormat: Whether that track's channel count and sample rate are known
  ///     (see `DecoderProbe.hasAudioFormat`).
  static func wantedAudioIndex(
    languageCodes: [String?],
    decodable: [Bool],
    hasAudioFormat: [Bool],
    preferredLanguage: String?
  ) -> Int? {
    let selectable = decodable.indices.map { index in
      decodable[index] && (index < hasAudioFormat.count ? hasAudioFormat[index] : true)
    }
    return PlaybackTrackPreferences.preferredAudioIndex(
      languageCodes: languageCodes,
      selectable: selectable,
      preferredLanguage: preferredLanguage
    ) ?? firstDecodableIndexIfNeeded(decodable)
  }

  override func process(assetTrack: some MediaPlayerTrack) {
    super.process(assetTrack: assetTrack)
    guard let track = assetTrack as? FFmpegAssetTrack else { return }
    if undecodableTrackIDs.contains(track.trackID) {
      // No decodable alternative existed. Discard the stream's packets so the dead
      // decoder is never created; the engine fails the load when the source reports
      // ready (`KSPlayerLoadPolicy.hasUndecodableMediaType`).
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
    Self.firstDecodableIndexIfNeeded(recordDecodability(of: tracks))
  }

  static func firstDecodableIndexIfNeeded(_ decodable: [Bool]) -> Int? {
    guard decodable.contains(false) else { return nil }
    return decodable.firstIndex(of: true)
  }

  /// Probes every track and remembers the ones without a working decoder.
  private func recordDecodability(of tracks: [MediaPlayerTrack]) -> [Bool] {
    let decodable = tracks.map { track in
      (track as? FFmpegAssetTrack).map(DecoderProbe.canDecode) ?? true
    }
    guard decodable.contains(false) else { return decodable }
    lock.lock()
    for (track, ok) in zip(tracks, decodable) where !ok {
      undecodable.insert(track.trackID)
    }
    lock.unlock()
    return decodable
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

  /// `av_find_best_stream` passes over an audio stream whose channel count or sample
  /// rate is still unknown (probing ended before its first frame arrived). Asked for
  /// such a stream by index it finds nothing, and KSPlayer then enables the first
  /// audio track whatever it is. A track like that must not be asked for.
  ///
  /// True when the parameters cannot be read: the pick then works as it would for any
  /// other track.
  static func hasAudioFormat(_ track: FFmpegAssetTrack) -> Bool {
    guard let parameters = codecParameters(of: track) else { return true }
    return isKnownAudioFormat(
      sampleRate: parameters.sample_rate, channelCount: parameters.ch_layout.nb_channels
    )
  }

  static func isKnownAudioFormat(sampleRate: Int32, channelCount: Int32) -> Bool {
    sampleRate > 0 && channelCount > 0
  }

  /// `FFmpegAssetTrack.codecpar` is internal to KSPlayer. Reflection reads it without a
  /// fork; if the field is ever renamed the probe degrades to the name-based check.
  private static func codecParameters(of track: FFmpegAssetTrack) -> AVCodecParameters? {
    Mirror(reflecting: track).children
      .first { $0.label == "codecpar" }?.value as? AVCodecParameters
  }
}

/// Facts about a demuxer that KSPlayer keeps internal.
nonisolated enum DemuxerProbe {
  /// Whether KSPlayer seeks this container by byte position instead of by time (the
  /// same rule as `MEPlayerItem.seekByBytes`: MPEG-TS and MPEG-PS). Such a seek starts
  /// from the byte position of the last frame that was drawn, so after a stretch
  /// without drawing a seek "to the current time" lands where drawing stopped.
  static func seeksByBytes(formatName: String) -> Bool {
    guard !formatName.isEmpty, formatName != "ogg",
          let format = av_find_input_format(formatName)
    else { return false }
    let flags = format.pointee.flags
    return flags & AVFMT_NO_BYTE_SEEK == 0 && flags & AVFMT_TS_DISCONT != 0
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

/// KSPlayer's FFmpeg item (`MEPlayerItem`) decides "enough is buffered, start rendering"
/// from a 0.05 s `Timer` scheduled in the default run-loop mode only. While a scroll view
/// tracks or decelerates, the main run loop leaves that mode: the timer stops firing and
/// a stream cannot leave buffering until the scroll settles. Adding the same timer to the
/// common modes keeps it running; KSPlayer registers its own display link that way for
/// the same reason.
///
/// Both properties are private to KSPlayer, so they are read by reflection instead of a
/// fork. If either is renamed nothing is found and playback behaves as it did before.
///
/// `KSPlayerLayer` has a timer of its own, a repeating 0.1 s one that drives the time
/// callback. Nothing in KSPlayer ever invalidates it (`stop()` and `deinit` leave it
/// alone, `pause()` only parks it), so a layer released while playing leaves a 10 Hz
/// timer on the main run loop for the rest of the process. `invalidateProgressTimer`
/// removes it when the engine lets a layer go; it is found the same way. It is a
/// default-mode timer as well, so the position and the subtitle cues froze during a
/// scroll; `promoteProgressTimer` adds it to the common modes once it exists.
///
/// Main thread only: it touches the main run loop.
@MainActor
enum KSPlayerRunLoopGuard {
  /// `KSMEPlayer.playerItem`.
  static let playerItemLabel = "playerItem"
  /// Storage of `MEPlayerItem`'s `private lazy var timer`.
  static let capacityTimerLabel = "$__lazy_storage_$_timer"
  /// Storage of `KSPlayerLayer`'s `private lazy var timer`.
  static let layerTimerLabel = "$__lazy_storage_$_timer"

  /// Position of a labelled child per class, see `child(labelled:of:)`.
  private static var childOffsets: [String: Int] = [:]

  /// Returns false when the player is not the FFmpeg one or the timer was not found.
  @discardableResult
  static func promoteCapacityTimer(of player: MediaPlayerProtocol) -> Bool {
    guard let player = player as? KSMEPlayer,
          let timer = capacityTimer(of: player), timer.isValid
    else { return false }
    // Adding a timer to a mode it is already in does nothing.
    RunLoop.main.add(timer, forMode: .common)
    return true
  }

  static func capacityTimer(of player: KSMEPlayer) -> Timer? {
    guard let item = child(labelled: playerItemLabel, of: player) else { return nil }
    return timer(labelled: capacityTimerLabel, of: item)
  }

  /// For a layer that is being released for good: nothing may call `play()` on it
  /// afterwards. Returns false when the timer was not found, which is also the case
  /// for a layer that never played (the lazy timer was never created).
  @discardableResult
  static func invalidateProgressTimer(of layer: KSPlayerLayer) -> Bool {
    guard let timer = progressTimer(of: layer) else { return false }
    timer.invalidate()
    return true
  }

  /// Keeps the layer's time tick running while a scroll view tracks or decelerates.
  /// Does not create the lazy timer: returns false until the layer has played or
  /// paused once, and for a timer that was invalidated or lives on another run loop.
  @discardableResult
  static func promoteProgressTimer(of layer: KSPlayerLayer) -> Bool {
    guard let timer = progressTimer(of: layer), timer.isValid,
          // KSPlayer schedules the timer on the run loop of whichever thread first
          // plays, pauses or finishes the layer, and AVPlayer's callbacks are not
          // always on the main one. A timer belongs to a single run loop, so one
          // that was scheduled elsewhere is left alone.
          CFRunLoopContainsTimer(CFRunLoopGetMain(), timer, .defaultMode)
    else { return false }
    // Adding a timer to a mode it is already in does nothing.
    RunLoop.main.add(timer, forMode: .common)
    return true
  }

  static func progressTimer(of layer: KSPlayerLayer) -> Timer? {
    timer(labelled: layerTimerLabel, of: layer)
  }

  /// A `lazy var` is stored as an optional that stays nil until its first use.
  static func timer(labelled label: String, of object: Any) -> Timer? {
    guard let value = child(labelled: label, of: object) else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value as? Timer }
    return mirror.children.first?.value as? Timer
  }

  /// Reads one stored property by its label.
  ///
  /// `Mirror` copies every child it visits, and KSPlayer's own threads write some of the
  /// properties declared ahead of the one wanted here. A label's position is fixed per
  /// class, so it is searched once and later reads touch that single child only.
  static func child(labelled label: String, of object: Any) -> Any? {
    let children = Mirror(reflecting: object).children
    let key = "\(String(reflecting: type(of: object))).\(label)"
    if let offset = childOffsets[key], offset < children.count {
      let child = children[children.index(children.startIndex, offsetBy: offset)]
      if child.label == label { return child.value }
    }
    for (offset, child) in children.enumerated() where child.label == label {
      childOffsets[key] = offset
      return child.value
    }
    return nil
  }
}
