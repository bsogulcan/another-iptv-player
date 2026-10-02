import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswresample

/// FFmpeg remux: kaynak URL (mkv/ts/avi…) → HLS segmentleri. Video daima passthrough
/// (H.264/HEVC); ses uyumluysa passthrough, değilse (MP2/DTS/TrueHD…) AAC'ye transcode
/// edilir. Arka plan kuyruğunda koşar.
///
/// İki segment biçimi:
/// - H.264 → MPEG-TS segmentleri (FFmpegKit'te `hls` muxer'ı derli değil; mpegts muxer
///   ile segmentasyon + m3u8 üretimi elle yapılır, cihazda doğrulandı).
/// - HEVC → fMP4 segmentleri (HLS spec'i HEVC'yi TS'te kabul etmez): tek `mp4` muxer,
///   `frag_custom` ile bizim sınırlarımızda fragment üretir; custom AVIO ile byte'lar
///   yakalanıp init.mp4 + segNNNNN.m4s dosyalarına bölünür.
final class RemuxHLSWriter {
  enum RemuxError: LocalizedError {
    case openInputFailed(Int32)
    case noCompatibleStreams
    case openOutputFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    /// Probing ended before the video stream's dimensions were known (a live stream
    /// joined mid-GOP with no keyframe inside the probe window). The mp4 muxer would
    /// reject the header with a bare EINVAL; a later attempt can land on a keyframe.
    case videoParametersUnknown
    /// Probing ended before the sample rate of the audio stream that would be copied
    /// was known (a declared stream whose first frame had not arrived). Every muxer
    /// rejects such a header with a bare EINVAL ("sample rate not set"), which reads
    /// as an incompatible source; a later attempt can land on audio that has started.
    case audioParametersUnknown
    /// The source's video clock jumped (provider restart or splice) on the fMP4 path,
    /// where one muxer context cannot start a new timeline. The session has to be
    /// rebuilt; the MPEG-TS path splices in place and never throws this.
    case timestampDiscontinuity

    var errorDescription: String? {
      switch self {
      case let .openInputFailed(code): return "remux: input open failed (\(code))"
      case .noCompatibleStreams: return "remux: no AVPlayer-compatible streams"
      case let .openOutputFailed(code): return "remux: output open failed (\(code))"
      case let .writeFailed(code): return "remux: write failed (\(code))"
      case let .readFailed(code): return "remux: source read failed (\(code))"
      case .videoParametersUnknown:
        return "remux: video dimensions unknown after probing (no keyframe in the probe window)"
      case .audioParametersUnknown:
        return "remux: audio sample rate unknown after probing (no audio frame in the probe window)"
      case .timestampDiscontinuity:
        return "remux: source timestamps jumped; the session has to be rebuilt"
      }
    }
  }

  /// AVERROR_EOF — FFERRTAG('E','O','F',' '); the function-like C macro is not
  /// imported into Swift.
  private static let avErrorEOF: Int32 = -541_478_725

  enum SegmentFormat {
    case mpegTS
    case fmp4
  }

  static let compatibleVideoCodecs: Set<UInt32> = [
    AV_CODEC_ID_H264.rawValue, AV_CODEC_ID_HEVC.rawValue,
  ]
  /// Passthrough'a uygun ses; biçime göre değişir. Liste dışındaki her ses AAC'ye
  /// transcode edilir (decoder varsa; yoksa ses düşürülür, video sessiz gider).
  private static let fmp4AudioPassthrough: Set<UInt32> = [
    AV_CODEC_ID_AAC.rawValue, AV_CODEC_ID_AC3.rawValue, AV_CODEC_ID_EAC3.rawValue,
  ]
  private static let tsAudioPassthrough: Set<UInt32> = [
    AV_CODEC_ID_AAC.rawValue, AV_CODEC_ID_AC3.rawValue, AV_CODEC_ID_EAC3.rawValue,
    AV_CODEC_ID_MP3.rawValue,
  ]

  private let sourceURL: URL
  private let outputDirectory: URL
  private let startSeconds: TimeInterval
  private let isLive: Bool
  private let userAgent: String?
  /// Girdi açılmadan önce beklenecek süre: az önce kapatılmış bir bağlantının
  /// (önceki oturum / telefon oynatıcısı) panelde ölmesine fırsat verir —
  /// bağlantı-limitli panellerde ilk açılış çakışması kalıcı hataya dönüyordu.
  /// `readyToOpen` verilmişse bu değer sabit gecikme değil ÜST SINIRDIR.
  private let openDelaySeconds: Double
  /// Verilirse: girdi açmadan önce bu koşul true olana (ya da `openDelaySeconds`
  /// sınırına) kadar bekle. Zap'ta önceki oturumun kaynak bağlantısı fiilen
  /// kapanana dek bekleyip panelin slotu boşaltmasını garantiler.
  private let readyToOpen: (() -> Bool)?
  private let targetSegmentSeconds: Double
  /// Canlıda playlist'te tutulan segment sayısı (kayan pencere). VOD event-playlist
  /// kullanır (tüm segmentler kalır): kayan-pencere/canlı-görünüm denemesi sahada
  /// tekleme ve pencere-kaçması sorunları üretti, kullanıcı kararıyla geri alındı.
  /// 20 segments (30-40 s at the 1.5 s live target): with 8 a pause of 7-11 s already
  /// left the TV behind the window and cost a full session rebuild. The join point
  /// does not move; clients still start three target durations from the end.
  private let liveWindowSize = 20
  /// Files kept after their segment left the live playlist, so a receiver working
  /// from a slightly stale playlist copy does not get a 404.
  private let retiredSegmentLimit = 6
  /// Test için biçimi zorlamaya izin verir; nil = codec'e göre otomatik.
  let forcedFormat: SegmentFormat?

  /// External or selected embedded text subtitles share a segmented WebVTT
  /// rendition on both container paths. With neither selected, no rendition is added.
  private let subtitleFileURL: URL?
  private let subtitleName: String?
  private let subtitleLanguage: String?
  private let audioStreamIndex: Int?
  private let subtitleStreamIndex: Int?
  private let subtitleDelaySeconds: Double
  private var subtitleDecoder: TextSubtitleDecoder?
  private var subtitleEntries: [SubtitleEntry] = []
  private var subtitleInputStartTime: Int64 = 0
  private var subtitleTimestampBase: Int64 = 0
  private var subtitleUsesFMP4 = false
  private var subtitleVariantBandwidth = 6_000_000
  private var hasSubtitles = false
  private var loggedFirstSubtitleCue = false
  private var loggedFirstPublishedSubtitleCue = false
  private let clientPlaylistLock = NSLock()
  private var clientPlaylistFileNameStorage = "stream.m3u8"
  /// Filename the cast AVPlayer should load: the subtitle master once a rendition has
  /// been written, else the raw video playlist. Written on the remux thread, read by the
  /// session after playlist readiness (well after the first segment), hence the lock.
  var clientPlaylistFileName: String {
    clientPlaylistLock.lock(); defer { clientPlaylistLock.unlock() }
    return clientPlaylistFileNameStorage
  }
  private func setClientPlaylistFileName(_ name: String) {
    clientPlaylistLock.lock(); clientPlaylistFileNameStorage = name; clientPlaylistLock.unlock()
  }

  private let queue = DispatchQueue(label: "AirPlayRemux.writer", qos: .userInitiated)
  /// Interrupt callback okur; blocking av_read_frame'i iptalde kırar.
  private let cancelled = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

  /// A single source read blocked this long is a dead source. FFmpeg's own HTTP
  /// reconnect loop runs inside one `av_read_frame` call, so without a bound here
  /// the cast controller hears nothing while the TV sits on a frozen frame.
  static let liveReadStallLimitSeconds: TimeInterval = 20
  static let vodReadStallLimitSeconds: TimeInterval = 30

  /// Caps of the live input probe (`analyzeduration` in microseconds, `probesize` in
  /// bytes). libavformat stops at whichever is reached first, so they are sized
  /// together: 24 MB is 10 s at about 19 Mbit/s. The window has to reach the first
  /// keyframe of a channel joined mid-GOP, because the video dimensions come from
  /// it: measured on a real-time HEVC source with a 6 s GOP at 9 Mbit/s, joined 5 s
  /// before its next keyframe, 4.5 s / 8 MB ended in `videoParametersUnknown` on the
  /// first attempt and again on the retry.
  static let liveProbeDurationMicroseconds: Int64 = 10_000_000
  static let liveProbeSizeBytes: Int64 = 24_000_000

  /// What the FFmpeg interrupt callback looks at (it is a C function and can only
  /// take a pointer). The watchdog fields are written and read on the remux thread:
  /// FFmpeg polls the callback from the thread that is blocked in the read.
  private struct InterruptState {
    let cancelled: UnsafeMutablePointer<Int32>
    /// Uptime at which the current `av_read_frame` call began; 0 = no read in
    /// progress (opening, probing, pacing sleeps and muxing are never timed).
    var readStartedUptime: TimeInterval = 0
    var stallLimitSeconds: TimeInterval
    /// Set by the callback when it broke a read because of the limit.
    var stallFired = false
  }
  private let interrupt = UnsafeMutablePointer<InterruptState>.allocate(capacity: 1)

  /// Running total of segment bytes (media segments and the fMP4 init segment) this
  /// writer has put on disk. It only grows: files the live window deletes later are
  /// not subtracted. Written on the remux thread, read by the session, hence the lock.
  var bytesWritten: Int64 {
    bytesLock.lock()
    defer { bytesLock.unlock() }
    return bytesWrittenStorage
  }
  private let bytesLock = NSLock()
  private var bytesWrittenStorage: Int64 = 0

  private func addBytesWritten(_ count: Int64) {
    guard count > 0 else { return }
    bytesLock.lock()
    bytesWrittenStorage += count
    bytesLock.unlock()
  }

  /// Remux döngüsü tamamen çözülüp kaynak bağlantısı (avformat_close_input) kapandı.
  /// Sonraki oturum, panel slotunun boşaldığını buradan anlar.
  private let closedLock = NSLock()
  private var sourceClosed = false
  var isClosed: Bool {
    closedLock.lock()
    defer { closedLock.unlock() }
    return sourceClosed
  }
  private(set) var playlistURL: URL
  /// Kaynağın toplam süresi (girdi açılınca yazılır; canlıda 0 kalır).
  private(set) var sourceDurationSeconds: TimeInterval = 0
  /// Girdi seek'inin GERÇEKTE düştüğü konum. `av_seek_frame` başarısız olursa
  /// (seek edilemeyen kaynak) 0'a döner — zaman çizelgesi muhasebesi buna bakmalı,
  /// aksi halde UI istenen konumu gösterirken cast 0:00'dan oynar.
  private(set) var effectiveStartSeconds: TimeInterval

  /// Source time of the first video keyframe actually written. A backward input
  /// seek can land several seconds before the requested position.
  var firstVideoContentSeconds: TimeInterval? {
    firstVideoLock.lock()
    defer { firstVideoLock.unlock() }
    return firstVideoContentStorage
  }
  private let firstVideoLock = NSLock()
  private var firstVideoContentStorage: TimeInterval?

  private func noteFirstVideoContentSeconds(_ seconds: TimeInterval) {
    guard seconds.isFinite else { return }
    firstVideoLock.lock()
    if firstVideoContentStorage == nil { firstVideoContentStorage = seconds }
    firstVideoLock.unlock()
  }

  /// Can a new writer be opened on this source at another position? False until the
  /// input is open; then whether its I/O reports byte seeking, and false again once
  /// the start seek was refused. `effectiveStartSeconds` alone cannot answer this: a
  /// session started at 0:00 never attempts a seek, so a source that cannot seek
  /// looks exactly like one that can. Written on the remux thread, read by the
  /// session, hence the lock.
  var sourceCanSeek: Bool {
    seekableLock.lock()
    defer { seekableLock.unlock() }
    return sourceCanSeekStorage
  }
  private let seekableLock = NSLock()
  private var sourceCanSeekStorage = false

  private func setSourceCanSeek(_ canSeek: Bool) {
    seekableLock.lock()
    sourceCanSeekStorage = canSeek
    seekableLock.unlock()
  }

  var onError: ((Error) -> Void)?

  // MARK: - VOD pacing (round-16 leaky bucket)

  /// VOD'da yazıcı, oynatma konumunun en fazla bu kadar ilerisine yazar. Sınırsız
  /// bırakılırsa tüm film hat hızında iner: panelin bağlantı sınırı doyar
  /// (devir hataları), disk/pil boşa gider.
  private let pacingAheadSeconds: Double = 25
  private let positionLock = NSLock()
  private var playbackPositionSeconds: Double = 0

  /// Cast oynatıcısının kaynak-zamanı konumu; pacing kapısını besler.
  func updatePlaybackPosition(_ seconds: TimeInterval) {
    positionLock.lock()
    playbackPositionSeconds = seconds
    positionLock.unlock()
  }

  private func currentPlaybackPosition() -> Double {
    positionLock.lock()
    defer { positionLock.unlock() }
    return playbackPositionSeconds
  }

  /// Yazılan medya zamanı izin verilen pencerenin ilerisindeyse bekler (iptal duyarlı).
  /// Oynatma başlamadan önce taban gerçek başlangıç konumudur (seek başarısızsa 0):
  /// oturum, başlangıç tamponunu (12 sn < 25 sn pencere) engellenmeden biriktirir.
  private func waitForPacing(mediaSeconds: Double) {
    guard !isLive else { return }
    var holding = false
    while cancelled.pointee == 0 {
      let floorPosition = max(currentPlaybackPosition(), effectiveStartSeconds)
      if mediaSeconds <= floorPosition + pacingAheadSeconds { break }
      // A pacing sleep is a deliberate wait, not a stalled source: keep it out of
      // the stall clock the session's start deadline reads.
      if !holding {
        holding = true
        setReadHold(true)
      }
      Thread.sleep(forTimeInterval: 0.2)
    }
    if holding { setReadHold(false) }
  }

  /// Container timestamp → 0-based content time. Pacing and the early-EOF test
  /// compare against the playback position and the source duration, both 0-based,
  /// while MPEG-TS recordings (catch-up) start at an arbitrary PTS. `inputStartTime`
  /// is `AVFormatContext.start_time` in AV_TIME_BASE units, the same origin the input
  /// seek adds; AV_NOPTS_VALUE (Int64.min) means unknown and leaves the value as is.
  static func contentSeconds(containerSeconds: Double, inputStartTime: Int64) -> Double {
    guard inputStartTime != Int64.min else { return containerSeconds }
    return containerSeconds - Double(inputStartTime) / Double(AV_TIME_BASE)
  }

  // MARK: - Read progress (start-deadline input)

  /// Snapshot of how the source read is going, for the session's start deadline.
  struct ReadProgress: Equatable {
    /// Packets the remux loop has read from the source (0 = still opening/probing).
    let packetsRead: Int
    /// How long the loop has gone without reading a packet. Deliberate waits (the
    /// pre-open drain wait, VOD pacing sleeps) report 0: they are not a stall.
    let stalledSeconds: TimeInterval
  }

  private let progressLock = NSLock()
  private var packetsReadCount = 0
  private var lastReadUptime: TimeInterval = 0
  /// True while the loop waits on purpose; starts true to cover the pre-open wait.
  private var readOnHold = true

  /// Written on the remux thread, read by the session's playlist poll, hence the lock.
  var readProgress: ReadProgress {
    progressLock.lock()
    defer { progressLock.unlock() }
    let stalled = readOnHold
      ? 0 : max(ProcessInfo.processInfo.systemUptime - lastReadUptime, 0)
    return ReadProgress(packetsRead: packetsReadCount, stalledSeconds: stalled)
  }

  private func notePacketRead() {
    progressLock.lock()
    packetsReadCount += 1
    lastReadUptime = ProcessInfo.processInfo.systemUptime
    progressLock.unlock()
  }

  private func setReadHold(_ hold: Bool) {
    progressLock.lock()
    readOnHold = hold
    // The stall clock restarts when a hold ends, so the wait itself is never counted.
    if !hold { lastReadUptime = ProcessInfo.processInfo.systemUptime }
    progressLock.unlock()
  }

  init(
    sourceURL: URL,
    outputDirectory: URL,
    startSeconds: TimeInterval,
    isLive: Bool,
    userAgent: String?,
    openDelaySeconds: Double = 0,
    readyToOpen: (() -> Bool)? = nil,
    forcedFormat: SegmentFormat? = nil,
    subtitleFileURL: URL? = nil,
    subtitleName: String? = nil,
    subtitleLanguage: String? = nil,
    audioStreamIndex: Int? = nil,
    subtitleStreamIndex: Int? = nil,
    subtitleDelaySeconds: Double = 0
  ) {
    self.sourceURL = sourceURL
    self.outputDirectory = outputDirectory
    self.startSeconds = startSeconds
    self.isLive = isLive
    self.userAgent = userAgent
    self.openDelaySeconds = openDelaySeconds
    self.readyToOpen = readyToOpen
    self.forcedFormat = forcedFormat
    self.subtitleFileURL = subtitleFileURL
    self.subtitleName = subtitleName
    self.subtitleLanguage = subtitleLanguage
    self.audioStreamIndex = audioStreamIndex
    self.subtitleStreamIndex = subtitleStreamIndex
    self.subtitleDelaySeconds = subtitleDelaySeconds
    effectiveStartSeconds = startSeconds
    targetSegmentSeconds = isLive ? 1.5 : 4
    cancelled.pointee = 0
    playlistURL = outputDirectory.appendingPathComponent("stream.m3u8")
    interrupt.initialize(to: InterruptState(
      cancelled: cancelled,
      stallLimitSeconds: isLive
        ? Self.liveReadStallLimitSeconds : Self.vodReadStallLimitSeconds
    ))
  }

  deinit {
    interrupt.deinitialize(count: 1)
    interrupt.deallocate()
    cancelled.deallocate()
  }

  func start() {
    queue.async { [self] in
      do {
        try runRemuxLoop()
      } catch {
        if cancelled.pointee == 0 {
          Log.error("AirPlayRemux", "remux failed: \(error.localizedDescription)")
          DispatchQueue.main.async { [weak self] in self?.onError?(error) }
        }
      }
      // Döngü çözüldü → defer'daki avformat_close_input koştu → kaynak bağlantısı
      // kapandı. Sonraki oturum bunu bekliyor olabilir.
      closedLock.lock()
      sourceClosed = true
      closedLock.unlock()
    }
  }

  func cancel() {
    cancelled.pointee = 1
  }

  // MARK: - Ses transcode (MP2/DTS/… → AAC)

  /// Decode → swresample (FLTP) → FIFO → AAC encode zinciri. Zaman damgaları girdinin
  /// mutlak zaman çizelgesine oturtulur (ilk decode edilen frame'in PTS'inden başlar).
  private final class AudioTranscoder {
    let decoder: UnsafeMutablePointer<AVCodecContext>
    let encoder: UnsafeMutablePointer<AVCodecContext>
    /// Encoder çıkış paketlerinin time base'i: 1/sampleRate.
    var encoderTimeBase: AVRational { AVRational(num: 1, den: sampleRate) }
    private var swr: OpaquePointer?
    private let fifo: OpaquePointer
    private let sampleRate: Int32
    private let decodedFrame = av_frame_alloc()
    private let convertedFrame = av_frame_alloc()
    private let encodeFrame = av_frame_alloc()
    private let encodedPacket = av_packet_alloc()
    /// Bir sonraki encode frame'inin PTS'i (örnek biriminde); ilk frame'de kurulur.
    private var nextPts: Int64 = .min

    init?(inStream: UnsafeMutablePointer<AVStream>) {
      guard let codecpar = inStream.pointee.codecpar,
            let decCodec = avcodec_find_decoder(codecpar.pointee.codec_id),
            let decCtx = avcodec_alloc_context3(decCodec)
      else { return nil }
      avcodec_parameters_to_context(decCtx, codecpar)
      decCtx.pointee.pkt_timebase = inStream.pointee.time_base
      guard avcodec_open2(decCtx, decCodec, nil) >= 0 else {
        var freeing: UnsafeMutablePointer<AVCodecContext>? = decCtx
        avcodec_free_context(&freeing)
        return nil
      }
      decoder = decCtx

      guard let encCodec = avcodec_find_encoder(AV_CODEC_ID_AAC),
            let encCtx = avcodec_alloc_context3(encCodec)
      else {
        var freeing: UnsafeMutablePointer<AVCodecContext>? = decCtx
        avcodec_free_context(&freeing)
        return nil
      }
      let rate = decCtx.pointee.sample_rate > 0 ? decCtx.pointee.sample_rate : 48000
      sampleRate = rate
      encCtx.pointee.sample_rate = rate
      av_channel_layout_copy(&encCtx.pointee.ch_layout, &decCtx.pointee.ch_layout)
      if encCtx.pointee.ch_layout.nb_channels <= 0 || encCtx.pointee.ch_layout.nb_channels > 6 {
        av_channel_layout_uninit(&encCtx.pointee.ch_layout)
        av_channel_layout_default(&encCtx.pointee.ch_layout, 2)
      }
      encCtx.pointee.sample_fmt = AV_SAMPLE_FMT_FLTP
      // 160 kbit/s is a stereo rate; spread over six channels it sounds thin.
      // Apple's HLS authoring table gives 320 kbit/s for 5.1 AAC.
      encCtx.pointee.bit_rate = encCtx.pointee.ch_layout.nb_channels > 2 ? 320_000 : 160_000
      encCtx.pointee.time_base = AVRational(num: 1, den: rate)
      // mp4/fMP4 için extradata (AudioSpecificConfig) global header'da olmalı.
      encCtx.pointee.flags |= 1 << 22  // AV_CODEC_FLAG_GLOBAL_HEADER (makro import edilmiyor)
      guard avcodec_open2(encCtx, encCodec, nil) >= 0 else {
        var f1: UnsafeMutablePointer<AVCodecContext>? = decCtx
        avcodec_free_context(&f1)
        var f2: UnsafeMutablePointer<AVCodecContext>? = encCtx
        avcodec_free_context(&f2)
        return nil
      }
      encoder = encCtx

      guard let fifoPtr = av_audio_fifo_alloc(
        AV_SAMPLE_FMT_FLTP, encCtx.pointee.ch_layout.nb_channels, rate
      ) else { return nil }
      fifo = fifoPtr
    }

    deinit {
      var d: UnsafeMutablePointer<AVCodecContext>? = decoder
      avcodec_free_context(&d)
      var e: UnsafeMutablePointer<AVCodecContext>? = encoder
      avcodec_free_context(&e)
      swr_free(&swr)
      av_audio_fifo_free(fifo)
      var f1 = decodedFrame
      av_frame_free(&f1)
      var f2 = convertedFrame
      av_frame_free(&f2)
      var f3 = encodeFrame
      av_frame_free(&f3)
      var p = encodedPacket
      av_packet_free(&p)
    }

    /// Girdi ses paketini işler; üretilen her AAC paketi için `emit` çağrılır.
    func process(
      packet: UnsafeMutablePointer<AVPacket>?,
      emit: (UnsafeMutablePointer<AVPacket>) throws -> Void
    ) throws {
      guard let decodedFrame, let convertedFrame else { return }
      _ = avcodec_send_packet(decoder, packet)
      while avcodec_receive_frame(decoder, decodedFrame) == 0 {
        defer { av_frame_unref(decodedFrame) }
        let tb = decoder.pointee.pkt_timebase
        let framePts = decodedFrame.pointee.pts
        if framePts != Int64.min, tb.den > 0 {
          let framePtsSamples = av_rescale_q(framePts, tb, AVRational(num: 1, den: sampleRate))
          if nextPts == .min {
            nextPts = framePtsSamples
          } else {
            // Kaynakta zaman sıçraması (reconnect/gap): sentetik PTS düz devam ederse
            // ses her sıçramada videodan biraz daha kayar (birikimli desync). 200 ms'den
            // büyük sapmada senkronu kaynağın zamanına yeniden kilitle.
            let expected = nextPts + Int64(av_audio_fifo_size(fifo))
            if abs(framePtsSamples - expected) > Int64(sampleRate / 5) {
              nextPts = framePtsSamples - Int64(av_audio_fifo_size(fifo))
            }
          }
        } else if nextPts == .min {
          nextPts = 0
        }
        if swr == nil {
          swr_alloc_set_opts2(
            &swr,
            &encoder.pointee.ch_layout, AV_SAMPLE_FMT_FLTP, sampleRate,
            &decodedFrame.pointee.ch_layout,
            AVSampleFormat(rawValue: decodedFrame.pointee.format), decodedFrame.pointee.sample_rate,
            0, nil
          )
          guard swr != nil, swr_init(swr) >= 0 else {
            throw RemuxError.openOutputFailed(-1)
          }
        }
        // Dönüştür ve FIFO'ya yaz.
        convertedFrame.pointee.sample_rate = sampleRate
        convertedFrame.pointee.format = AV_SAMPLE_FMT_FLTP.rawValue
        av_channel_layout_copy(&convertedFrame.pointee.ch_layout, &encoder.pointee.ch_layout)
        convertedFrame.pointee.nb_samples =
          swr_get_out_samples(swr, decodedFrame.pointee.nb_samples)
        guard av_frame_get_buffer(convertedFrame, 0) >= 0 else {
          throw RemuxError.writeFailed(-1)
        }
        defer { av_frame_unref(convertedFrame) }
        let outData = UnsafeMutableRawPointer(convertedFrame.pointee.extended_data)
          .assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        let inData = UnsafeMutableRawPointer(decodedFrame.pointee.extended_data)
          .assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
        let converted = swr_convert(
          swr, outData, convertedFrame.pointee.nb_samples,
          inData, decodedFrame.pointee.nb_samples
        )
        guard converted >= 0 else { throw RemuxError.writeFailed(converted) }
        if converted > 0 {
          let raw = UnsafeMutableRawPointer(convertedFrame.pointee.extended_data)
            .assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
          av_audio_fifo_write(fifo, raw, converted)
        }
        try drainEncoder(flush: false, emit: emit)
      }
    }

    /// Kaynak bitti/iptal: kalan örnekleri encode edip encoder'ı boşaltır.
    func finish(emit: (UnsafeMutablePointer<AVPacket>) throws -> Void) throws {
      try? process(packet: nil, emit: emit)  // decoder drain
      try drainEncoder(flush: true, emit: emit)
    }

    private func drainEncoder(
      flush: Bool,
      emit: (UnsafeMutablePointer<AVPacket>) throws -> Void
    ) throws {
      guard let encodeFrame, let encodedPacket else { return }
      let frameSize = encoder.pointee.frame_size > 0 ? encoder.pointee.frame_size : 1024
      while av_audio_fifo_size(fifo) >= frameSize
        || (flush && av_audio_fifo_size(fifo) > 0)
      {
        let take = min(av_audio_fifo_size(fifo), frameSize)
        encodeFrame.pointee.nb_samples = take
        encodeFrame.pointee.format = AV_SAMPLE_FMT_FLTP.rawValue
        encodeFrame.pointee.sample_rate = sampleRate
        av_channel_layout_copy(&encodeFrame.pointee.ch_layout, &encoder.pointee.ch_layout)
        guard av_frame_get_buffer(encodeFrame, 0) >= 0 else { return }
        let raw = UnsafeMutableRawPointer(encodeFrame.pointee.extended_data)
          .assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
        av_audio_fifo_read(fifo, raw, take)
        encodeFrame.pointee.pts = nextPts == .min ? 0 : nextPts
        nextPts = encodeFrame.pointee.pts + Int64(take)
        _ = avcodec_send_frame(encoder, encodeFrame)
        av_frame_unref(encodeFrame)
        while avcodec_receive_packet(encoder, encodedPacket) == 0 {
          try emit(encodedPacket)
          av_packet_unref(encodedPacket)
        }
        if flush, av_audio_fifo_size(fifo) <= 0 { break }
      }
      if flush {
        _ = avcodec_send_frame(encoder, nil)
        while avcodec_receive_packet(encoder, encodedPacket) == 0 {
          try emit(encodedPacket)
          av_packet_unref(encodedPacket)
        }
      }
    }
  }

  // MARK: - ADTS → ASC (AAC copied from MPEG-TS into fMP4)

  /// `aac_adtstoasc` bitstream filter. MPEG-TS carries AAC as ADTS frames with no
  /// extradata, while mp4 wants raw frames plus an AudioSpecificConfig. The mp4 muxer
  /// does not insert this filter itself once `empty_moov` is set (it clears
  /// AVFMT_FLAG_AUTO_BSF) and rejects the first ADTS packet as "Malformed AAC
  /// bitstream", so it is applied explicitly. The filter strips the ADTS header and
  /// attaches the config to the first packet as NEW_EXTRADATA side data, which the
  /// muxer picks up before the delayed moov is written.
  private final class ADTSToASCFilter {
    let context: UnsafeMutablePointer<AVBSFContext>

    init?(inStream: UnsafeMutablePointer<AVStream>) {
      guard let filter = av_bsf_get_by_name("aac_adtstoasc") else { return nil }
      var allocated: UnsafeMutablePointer<AVBSFContext>?
      guard av_bsf_alloc(filter, &allocated) >= 0, let ctx = allocated else { return nil }
      guard avcodec_parameters_copy(ctx.pointee.par_in, inStream.pointee.codecpar) >= 0 else {
        av_bsf_free(&allocated)
        return nil
      }
      ctx.pointee.time_base_in = inStream.pointee.time_base
      guard av_bsf_init(ctx) >= 0 else {
        av_bsf_free(&allocated)
        return nil
      }
      context = ctx
    }

    /// The writer holds the filter in a local of the remux loop, so this runs on
    /// every exit path (EOF, cancel, thrown error).
    deinit {
      var freeing: UnsafeMutablePointer<AVBSFContext>? = context
      av_bsf_free(&freeing)
    }
  }

  // MARK: - Zaman damgası onarımı

  /// MKV/HEVC konteyner dts'i güvenilmez: çoğu karede yok, olanlarda eşit/geri
  /// gelebiliyor. Muxer'ın tahmini mp4'te -22, TS'te SESSİZ HİZA KAYMASI üretir
  /// (sahadaki ses kaymasının kökü — 18. tur). dts konteynerden beklenmeden
  /// deterministik üretilir: decode-sırası saati = önceki dts + kare süresi.
  /// İki segment döngüsü de bu tek implementasyonu paylaşır; saf değer tipi
  /// olduğu için tablo-testlenebilir.
  struct TimestampRepair {
    private var lastDTS: Int64?
    private var lastDuration: Int64 = 0

    /// True once a packet has been stamped; until then `repairAudio` skips a packet
    /// that carries neither pts nor dts.
    var hasReference: Bool { lastDTS != nil }

    /// Video: dts daima sentezlenir. nil = paket atlanmalı (ilk karede pts yok).
    mutating func repairVideo(pts: Int64, duration: Int64) -> (pts: Int64, dts: Int64)? {
      let dur = max(duration > 0 ? duration : lastDuration, 1)
      let outPts: Int64
      let outDts: Int64
      if let last = lastDTS {
        var dts = last + dur
        if pts != Int64.min, dts > pts { dts = pts }
        if dts <= last { dts = last + 1 }
        // Geriye zaman sıçramasında monotonluk bump'ı dts'i pts'in üstüne
        // itebilir; muxer EINVAL ile ölmesin diye pts kaldırılır.
        outPts = (pts != Int64.min && pts < dts) ? dts : pts
        outDts = dts
      } else {
        guard pts != Int64.min else { return nil }
        // İlk kare (keyframe): decode saati pts'in ~4 kare gerisinden başlar ki
        // B-frame'lerde dts ≤ pts hep sağlansın (mp4 edit list telafi eder).
        outPts = pts
        outDts = pts - dur * 4
      }
      lastDTS = outDts
      if duration > 0 { lastDuration = duration }
      return (outPts, outDts)
    }

    /// Ses: konteyner ts'i güvenilir; yalnız eksik/geri durumda düzeltilir.
    /// nil = paket atlanmalı (henüz referans yokken iki damga da eksik).
    mutating func repairAudio(
      pts: Int64, dts: Int64, duration: Int64
    ) -> (pts: Int64, dts: Int64)? {
      var outPts = pts
      var outDts = dts
      if outPts == Int64.min, outDts == Int64.min {
        guard let last = lastDTS else { return nil }
        outDts = last + max(duration > 0 ? duration : lastDuration, 1)
        outPts = outDts
      } else if outDts == Int64.min {
        outDts = outPts
      }
      if let last = lastDTS, outDts <= last {
        let bumped = last + 1
        if outPts != Int64.min, outPts < bumped { outPts = bumped }
        outDts = bumped
      }
      lastDTS = outDts
      if duration > 0 { lastDuration = duration }
      return (outPts, outDts)
    }
  }

  // MARK: - Source timestamp jumps

  /// Watches the source clock for a reset or a leap, judged on video keyframes only.
  /// MKV packets carry pts in decode order, so with B-frames a packet-by-packet
  /// comparison sees backward steps that are plain reordering; keyframe times only
  /// move forward in a continuous stream.
  ///
  /// - Backward: a keyframe more than `backwardLimitSeconds` before the previous
  ///   keyframe (provider restart, a reconnect that replays buffered seconds,
  ///   catch-up files whose timestamps restart).
  /// - Forward: a keyframe more than `forwardLimitSeconds` past the latest media
  ///   time. The reference is the latest packet, audio included, rather than the
  ///   previous keyframe: a GOP of 10 s is ordinary (x264/x265 default keyint 250
  ///   at 24 fps), and a slideshow channel sends a picture now and then while its
  ///   audio runs on; neither is a jump. A packet that itself leaps ahead does not
  ///   move the reference, so a jump in the middle of a GOP is still seen at the
  ///   next keyframe.
  ///
  /// Pure value type, like `TimestampRepair`: table-testable.
  struct KeyframeContinuity {
    struct Jump: Equatable {
      /// Signed size of the jump in seconds; negative = the clock went backward.
      let seconds: Double
      var isBackward: Bool { seconds < 0 }
    }

    static let backwardLimitSeconds: Double = 1
    static let forwardLimitSeconds: Double = 10

    /// Time of the last keyframe seen (the reference for a backward jump).
    private(set) var lastKeyframeSeconds: Double?
    /// Latest video time that continued the clock: the end of the video read so far.
    private(set) var lastVideoSeconds: Double?
    /// Latest audio time that continued the clock.
    private(set) var lastAudioSeconds: Double?

    /// Latest audio or video time that continued the clock (the reference for a
    /// forward jump).
    var lastMediaSeconds: Double? {
      guard let video = lastVideoSeconds else { return lastAudioSeconds }
      guard let audio = lastAudioSeconds else { return video }
      return max(video, audio)
    }

    static func jump(
      keyframeSeconds: Double, previousKeyframeSeconds: Double?, lastMediaSeconds: Double?
    ) -> Jump? {
      if let previous = previousKeyframeSeconds,
         keyframeSeconds < previous - backwardLimitSeconds
      {
        return Jump(seconds: keyframeSeconds - previous)
      }
      if let last = lastMediaSeconds, keyframeSeconds > last + forwardLimitSeconds {
        return Jump(seconds: keyframeSeconds - last)
      }
      return nil
    }

    /// Feed every video packet in read order. Returns the jump when this keyframe
    /// breaks the clock; the detector is then anchored at the keyframe.
    mutating func observe(videoSeconds seconds: Double, isKeyframe: Bool) -> Jump? {
      guard isKeyframe else {
        // Frames ahead of the first keyframe are not written and do not count.
        if lastKeyframeSeconds != nil, let media = lastMediaSeconds,
           seconds <= media + Self.forwardLimitSeconds
        {
          lastVideoSeconds = max(lastVideoSeconds ?? seconds, seconds)
        }
        return nil
      }
      // The very first keyframe has nothing to break: audio read ahead of it is
      // only the mux order, not a clock.
      let jump = lastKeyframeSeconds == nil ? nil : Self.jump(
        keyframeSeconds: seconds,
        previousKeyframeSeconds: lastKeyframeSeconds,
        lastMediaSeconds: lastMediaSeconds
      )
      lastKeyframeSeconds = seconds
      if jump != nil {
        lastVideoSeconds = seconds
        // Audio re-anchors at its next packet, on the new timeline.
        lastAudioSeconds = nil
      } else {
        lastVideoSeconds = max(lastVideoSeconds ?? seconds, seconds)
      }
      return jump
    }

    /// Feed every audio packet in read order. Audio that steps on from its own
    /// previous packet, or stays near the video, continues the clock.
    mutating func observe(audioSeconds seconds: Double) {
      guard let last = lastAudioSeconds else {
        if !isOffTimeline(seconds) { lastAudioSeconds = seconds }
        return
      }
      guard seconds > last else { return }
      if seconds - last <= Self.forwardLimitSeconds
        || seconds <= (lastMediaSeconds ?? last) + Self.forwardLimitSeconds
      {
        lastAudioSeconds = seconds
      }
    }

    /// A packet from the far side of a jump whose keyframe has not arrived yet: more
    /// than `forwardLimitSeconds` past the clock, or that far before the last
    /// keyframe. It belongs to the next timeline and has no place in this segment.
    func isOffTimeline(_ seconds: Double) -> Bool {
      guard let media = lastMediaSeconds, let keyframe = lastKeyframeSeconds else {
        return false
      }
      return seconds > media + Self.forwardLimitSeconds
        || seconds < keyframe - Self.forwardLimitSeconds
    }
  }

  /// A jump no larger than this is left to heal on the fMP4 path: the repaired
  /// timestamps catch up once the source clock passes its old value, which costs at
  /// most this many seconds, about what a session rebuild costs.
  static let fmp4RebuildJumpSeconds: Double = 10

  /// fMP4 keeps one muxer context for the session, so it cannot splice a new
  /// timeline in place the way the MPEG-TS path does. Should the jump end the session
  /// (`RemuxError.timestampDiscontinuity`) so the cast controller rebuilds it?
  /// - Live: yes for a large jump; the rebuild rejoins the live edge on fresh timestamps.
  /// - VOD: only for a large backward jump on a seekable source. A forward gap still
  ///   cuts segments and plays through, and a source that cannot seek would restart
  ///   from 0:00 and meet the same jump again, in a loop.
  static func fmp4NeedsRebuild(
    after jump: KeyframeContinuity.Jump, isLive: Bool, sourceSeekable: Bool
  ) -> Bool {
    guard abs(jump.seconds) > fmp4RebuildJumpSeconds else { return false }
    if isLive { return true }
    return jump.isBackward && sourceSeekable
  }

  // MARK: - Ortak durum

  struct SegmentRecord {
    let index: Int
    let fileName: String
    let duration: Double
    /// The source clock restarted before this segment (MPEG-TS path): it is listed
    /// after an EXT-X-DISCONTINUITY tag.
    var discontinuity = false
  }

  private var segments: [SegmentRecord] = []
  /// EXT-X-DISCONTINUITY tags that have left the live window with their segment
  /// (RFC 8216 6.2.2: the sequence rises by one for every tag removed).
  private var discontinuitySequence = 0
  /// Highest EXT-X-TARGETDURATION this session has published; the value never
  /// falls below it again (see `writePlaylist`).
  private var sessionTargetDuration = 0
  /// Playlist penceresinden çıkmış ama dosyası henüz silinmemiş segmentler:
  /// pencerenin ucundan okuyan (geciken) TV, playlist güncellemesini görmeden
  /// istek atarsa 404 yememeli — birkaç segmentlik silme payı bırakılır.
  private var retiredSegments: [SegmentRecord] = []

  /// Sanity ceiling for a published EXTINF. Durations are measured keyframe to
  /// keyframe on a clock the jump detector has vouched for, so a real segment is
  /// never near this; it only keeps a freak value out of AVPlayer's seekable map.
  static let maximumSegmentSeconds: Double = 60

  /// EXTINF for a measured segment duration. The value is published as measured (the
  /// old cap of four target durations listed an 8-10 s GOP as 6.000); only an
  /// unusable measurement falls back to the previous 0.5 s floor.
  static func publishedSegmentDuration(measuredSeconds: Double) -> Double {
    guard measuredSeconds.isFinite, measuredSeconds > 0.001 else { return 0.5 }
    return min(measuredSeconds, maximumSegmentSeconds)
  }

  private func recordSegment(
    index: Int, fileName: String, duration: Double, discontinuity: Bool = false,
    sourceStartSeconds: Double = 0, final: Bool
  ) {
    subtitleVariantBandwidth = Self.variantBandwidth(
      segmentBytes: fileSize(named: fileName), duration: duration,
      previous: subtitleVariantBandwidth
    )
    segments.append(SegmentRecord(
      index: index,
      fileName: fileName,
      duration: Self.publishedSegmentDuration(measuredSeconds: duration),
      discontinuity: discontinuity
    ))
    if isLive {
      while segments.count > liveWindowSize {
        let retired = segments.removeFirst()
        if retired.discontinuity { discontinuitySequence += 1 }
        retiredSegments.append(retired)
      }
      while retiredSegments.count > retiredSegmentLimit {
        let old = retiredSegments.removeFirst()
        try? FileManager.default.removeItem(
          at: outputDirectory.appendingPathComponent(old.fileName)
        )
        try? FileManager.default.removeItem(
          at: outputDirectory.appendingPathComponent(String(format: "subs%05d.vtt", old.index))
        )
      }
    }
    writeSubtitleAssets(
      index: index, sourceStartSeconds: sourceStartSeconds, duration: duration, final: final
    )
    writePlaylist(final: final)
  }

  /// Match the video's segment sequence and timestamp origin on TS and fMP4.
  /// Empty WebVTT segments are required too: captions can start much later than video.
  private func writeSubtitleAssets(
    index: Int, sourceStartSeconds: Double, duration: Double, final: Bool
  ) {
    guard hasSubtitles else { return }
    let contentStart = Self.contentSeconds(
      containerSeconds: sourceStartSeconds, inputStartTime: subtitleInputStartTime
    )
    let contentEnd = contentStart + Self.publishedSegmentDuration(measuredSeconds: duration)
    let cues = subtitleEntries.compactMap { entry -> SubtitleEntry? in
      let start = entry.startTime + subtitleDelaySeconds
      let end = entry.endTime + subtitleDelaySeconds
      guard end > contentStart, start < contentEnd else { return nil }
      return SubtitleEntry(startTime: start, endTime: end, text: entry.text)
    }
    let clock = Int64((sourceStartSeconds * 90_000).rounded()) + subtitleTimestampBase
    let built = AirPlaySubtitleRendition.build(
      from: cues, mpegtsClock: clock, localSeconds: max(contentStart, 0)
    )
    if !cues.isEmpty, !loggedFirstPublishedSubtitleCue {
      loggedFirstPublishedSubtitleCue = true
      Log.info("AirPlayRemux", "subtitle published: segment=\(index), cues=\(cues.count), local=\(contentStart), MPEGTS=\(clock)")
    }
    do {
      try built.webVTT.write(
        to: outputDirectory.appendingPathComponent(String(format: "subs%05d.vtt", index)),
        atomically: true, encoding: .utf8
      )
      var lines = ["#EXTM3U", "#EXT-X-VERSION:3",
        "#EXT-X-TARGETDURATION:\(Int(segments.map(\.duration).max()?.rounded(.up) ?? 1))",
        "#EXT-X-MEDIA-SEQUENCE:\(segments.first?.index ?? 0)"]
      if isLive {
        lines.append("#EXT-X-DISCONTINUITY-SEQUENCE:\(discontinuitySequence)")
      } else {
        lines.append("#EXT-X-PLAYLIST-TYPE:EVENT")
      }
      for segment in segments {
        if segment.discontinuity { lines.append("#EXT-X-DISCONTINUITY") }
        lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
        lines.append(String(format: "subs%05d.vtt", segment.index))
      }
      if final { lines.append("#EXT-X-ENDLIST") }
      try (lines.joined(separator: "\n") + "\n").write(
        to: outputDirectory.appendingPathComponent("subs.m3u8"),
        atomically: true, encoding: .utf8
      )
      try AirPlaySubtitleRendition.masterPlaylist(
        videoPlaylistFileName: "stream.m3u8", subtitlePlaylistFileName: "subs.m3u8",
        name: subtitleName ?? "Subtitles", languageCode: subtitleLanguage,
        bandwidth: subtitleVariantBandwidth, version: subtitleUsesFMP4 ? 7 : 3
      ).write(
        to: outputDirectory.appendingPathComponent("master.m3u8"),
        atomically: true, encoding: .utf8
      )
      setClientPlaylistFileName("master.m3u8")
      // Decoded cues are a streaming window; external files remain reusable on seek.
      if subtitleDecoder != nil {
        subtitleEntries.removeAll { $0.endTime + subtitleDelaySeconds <= contentEnd }
      }
    } catch {
      Log.error("AirPlayRemux", "subtitle rendition write failed: \(error.localizedDescription)")
    }
  }

  private func decodeSubtitlePacket(_ packet: inout AVPacket, input: UnsafeMutablePointer<AVFormatContext>) -> Bool {
    guard let subtitleDecoder, Int(packet.stream_index) == subtitleStreamIndex,
          let stream = input.pointee.streams[Int(packet.stream_index)]
    else { return false }
    let entries = subtitleDecoder.decode(
      packet: &packet, timeBase: stream.pointee.time_base, inputStartTime: subtitleInputStartTime
    )
    if let first = entries.first, !loggedFirstSubtitleCue {
      loggedFirstSubtitleCue = true
      Log.info("AirPlayRemux", "subtitle decoded: stream=\(packet.stream_index), start=\(first.startTime), end=\(first.endTime)")
    }
    subtitleEntries += entries
    return true
  }

  /// İlk segment kısa tutulur ki playlist (ve TV'deki ilk kare) erken hazır olsun.
  private func targetDuration(forSegmentIndex index: Int) -> Double {
    index == 0 ? min(1.5, targetSegmentSeconds) : targetSegmentSeconds
  }

  /// A fixed 6 Mbit/s variant understated UHD segments (~20 Mbit/s), which the
  /// receiver rejected. Retain the observed peak with room for mux/subtitle overhead.
  static func variantBandwidth(segmentBytes: Int64, duration: Double, previous: Int) -> Int {
    let seconds = publishedSegmentDuration(measuredSeconds: duration)
    let measured = (Double(max(segmentBytes, 0)) * 8 / seconds * 1.25).rounded(.up)
    guard measured.isFinite, measured < Double(Int.max) else { return previous }
    return max(previous, Int(measured))
  }

  /// Constant added to every timestamp on the MPEG-TS path, in 90 kHz ticks (10 s).
  /// Each TS segment is its own muxer context, and a context whose first dts is
  /// negative shifts all its packets up to zero. The synthesized video dts starts
  /// four frames before the first pts, so on a cast started near 0:00 segment 0
  /// alone was shifted and overlapped segment 1 by those frames. With one base for
  /// the whole session no context ever sees a negative dts.
  static let tsTimestampBase90k: Int64 = 900_000

  private static func tsTimestampBase(in timeBase: AVRational) -> Int64 {
    av_rescale_q(tsTimestampBase90k, AVRational(num: 1, den: 90_000), timeBase)
  }

  private func fileSize(named fileName: String) -> Int64 {
    let path = outputDirectory.appendingPathComponent(fileName).path
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }

  /// `av_read_frame` under the stall watchdog: the interrupt callback times exactly
  /// this call, so pacing sleeps and muxing between reads never count. A read the
  /// watchdog broke is a source failure whatever code the demuxer maps it to (some
  /// turn an aborted read into a clean EOF, which on VOD would read as "finished").
  private func readFrame(
    _ input: UnsafeMutablePointer<AVFormatContext>, into packet: inout AVPacket
  ) throws -> Int32 {
    interrupt.pointee.stallFired = false
    interrupt.pointee.readStartedUptime = ProcessInfo.processInfo.systemUptime
    let result = av_read_frame(input, &packet)
    interrupt.pointee.readStartedUptime = 0
    if result < 0, interrupt.pointee.stallFired, cancelled.pointee == 0 {
      Log.error(
        "AirPlayRemux",
        "source read blocked for \(Int(interrupt.pointee.stallLimitSeconds))s; giving up on this connection"
      )
      throw RemuxError.readFailed(result)
    }
    return result
  }


  private enum AudioMode {
    case none
    case copy(inputIndex: Int)
    case transcode(inputIndex: Int, AudioTranscoder)

    var inputIndex: Int? {
      switch self {
      case .none: return nil
      case let .copy(index), let .transcode(index, _): return index
      }
    }
  }

  /// Which of a source's audio streams to use, given their probed sample rates in
  /// stream order: the first one whose rate is known, else the first one (nil when
  /// there is no audio). A rate of 0 means probing saw no frame of that stream.
  /// Pure function.
  static func preferredAudioCandidate(sampleRates: [Int32], selectedIndex: Int? = nil) -> Int? {
    if let selectedIndex, sampleRates.indices.contains(selectedIndex) { return selectedIndex }
    return sampleRates.firstIndex { $0 > 0 } ?? (sampleRates.isEmpty ? nil : 0)
  }

  // MARK: - Remux loop (queue üzerinde)

  private func runRemuxLoop() throws {
    if let readyToOpen {
      // Önceki oturumun kaynak bağlantısı kapanana kadar bekle (panel slotu boşalsın);
      // openDelaySeconds üst sınır. Kapanınca kısa bir yerleşme payı bırak.
      let cap = Date().addingTimeInterval(openDelaySeconds > 0 ? openDelaySeconds : 3.0)
      var drained = false
      while cancelled.pointee == 0, Date() < cap {
        if readyToOpen() {
          drained = true
          break
        }
        Thread.sleep(forTimeInterval: 0.05)
      }
      if cancelled.pointee != 0 { return }
      if drained { Thread.sleep(forTimeInterval: 0.3) }
    } else if openDelaySeconds > 0 {
      let deadline = Date().addingTimeInterval(openDelaySeconds)
      while cancelled.pointee == 0, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if cancelled.pointee != 0 { return }
    }
    // The pre-open wait is over: from here on, time without a packet is the source's.
    setReadHold(false)
    var inputCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
    inputCtx?.pointee.interrupt_callback.callback = { opaque in
      guard let state = opaque?.assumingMemoryBound(to: InterruptState.self) else { return 0 }
      if state.pointee.cancelled.pointee != 0 { return 1 }
      // Stall watchdog: armed only while a single av_read_frame call is in flight.
      let startedAt = state.pointee.readStartedUptime
      guard startedAt > 0 else { return 0 }
      if ProcessInfo.processInfo.systemUptime - startedAt >= state.pointee.stallLimitSeconds {
        state.pointee.stallFired = true
        return 1
      }
      return 0
    }
    inputCtx?.pointee.interrupt_callback.opaque = UnsafeMutableRawPointer(interrupt)

    var inputOpts: OpaquePointer?
    defer { av_dict_free(&inputOpts) }
    if let userAgent, !userAgent.isEmpty {
      av_dict_set(&inputOpts, "user_agent", userAgent, 0)
    }
    av_dict_set(&inputOpts, "reconnect", "1", 0)
    av_dict_set(&inputOpts, "reconnect_streamed", "1", 0)
    // FFmpeg's default back-off (120) retries at 0, 1, 3, 7, 15, 31 and 63 s inside
    // one read, hiding a dead source for two minutes. 15 keeps the early retries
    // that ride out a short panel hiccup; past that the read watchdog ends the read
    // and the cast controller decides (rebuild or end).
    av_dict_set(&inputOpts, "reconnect_delay_max", "15", 0)
    av_dict_set(&inputOpts, "rw_timeout", "15000000", 0)
    if isLive {
      // Both caps are raised together: 2 s / 1.5 MB ended probing before the first
      // keyframe on streams joined mid-GOP (4K HEVC: 1.5 MB is under a second), which
      // left the video dimensions unset. A stream that starts on a keyframe still
      // stops as soon as everything is known, and probed packets are replayed to the
      // loop, so this does not delay the first segment.
      // The caps are an upper bound, not a wait: only a stream that has not shown a
      // keyframe yet (or has a declared stream that never delivers) probes that far.
      // With no keyframe inside the whole window the fMP4 path still ends in
      // `videoParametersUnknown`, which the cast controller retries.
      av_dict_set(&inputOpts, "analyzeduration", String(Self.liveProbeDurationMicroseconds), 0)
      av_dict_set(&inputOpts, "probesize", String(Self.liveProbeSizeBytes), 0)
      // Canlı yayın EOF'lamaz: panel resetleri temiz EOF olarak görünebiliyor.
      // Protokol katmanında yeniden bağlan — aksi halde EOF üst katmanda kopma
      // sayılır ve cast düşer (canlı zap'ta "görüntü kesiliyor").
      av_dict_set(&inputOpts, "reconnect_at_eof", "1", 0)
    }

    var openResult = avformat_open_input(&inputCtx, sourceURL.absoluteString, nil, &inputOpts)
    guard openResult >= 0, let input = inputCtx else {
      throw RemuxError.openInputFailed(openResult)
    }
    defer {
      var closing: UnsafeMutablePointer<AVFormatContext>? = input
      avformat_close_input(&closing)
    }
    openResult = avformat_find_stream_info(input, nil)
    guard openResult >= 0 else { throw RemuxError.openInputFailed(openResult) }
    if input.pointee.duration > 0 {
      sourceDurationSeconds = Double(input.pointee.duration) / Double(AV_TIME_BASE)
    }
    // Published before the start seek, which may not happen at all (a start at
    // 0:00). AVIO_SEEKABLE_NORMAL is bit 0; the macro is not imported.
    setSourceCanSeek(((input.pointee.pb?.pointee.seekable ?? 0) & 1) != 0)

    if !isLive, startSeconds > 1 {
      // stream_index=-1 → zaman damgası paketlerle aynı orijinde olmalı: start_time
      // sıfır olmayan kaynaklarda (TS catchup kayıtları) eklenmezse yanlış yere düşer.
      var ts = Int64(startSeconds * Double(AV_TIME_BASE))
      if input.pointee.start_time != Int64.min {
        ts += input.pointee.start_time
      }
      let seekResult = av_seek_frame(input, -1, ts, AVSEEK_FLAG_BACKWARD)
      if seekResult < 0 {
        // Seek edilemeyen kaynak: 0:00'dan yazılacak — zaman çizelgesi muhasebesi
        // bunu bilmezse UI istenen konumu gösterirken cast baştan oynar.
        Log.error("AirPlayRemux", "input seek failed (\(seekResult)); remuxing from 0:00")
        effectiveStartSeconds = 0
        // Whatever the I/O layer reports, this source just refused a seek.
        setSourceCanSeek(false)
      }
    }

    // Stream selection: compatible video and the selected audio (transcode if needed).
    let streamCount = Int(input.pointee.nb_streams)
    var videoInputIndex = -1
    var videoIsHEVC = false
    var firstAudioIndex = -1
    var audioCodecId: UInt32 = 0
    var audioCandidates: [(index: Int, codecId: UInt32, sampleRate: Int32)] = []
    for i in 0..<streamCount {
      guard let inStream = input.pointee.streams[i],
            let codecpar = inStream.pointee.codecpar
      else { continue }
      let codecId = codecpar.pointee.codec_id.rawValue
      switch codecpar.pointee.codec_type {
      case AVMEDIA_TYPE_VIDEO:
        if videoInputIndex < 0, Self.compatibleVideoCodecs.contains(codecId) {
          videoInputIndex = i
          videoIsHEVC = codecId == AV_CODEC_ID_HEVC.rawValue
        }
      case AVMEDIA_TYPE_AUDIO:
        audioCandidates.append((i, codecId, codecpar.pointee.sample_rate))
      default:
        break
      }
    }
    guard videoInputIndex >= 0 else { throw RemuxError.noCompatibleStreams }
    // An explicit selection is preserved even if probing missed its first frame;
    // the parameters check below then retries instead of choosing another language.
    // Without a selection, prefer a stream whose sample rate is already known.
    if let choice = Self.preferredAudioCandidate(
      sampleRates: audioCandidates.map { $0.sampleRate },
      selectedIndex: audioCandidates.firstIndex { $0.index == audioStreamIndex }
    ) {
      firstAudioIndex = audioCandidates[choice].index
      audioCodecId = audioCandidates[choice].codecId
      if choice > 0 {
        Log.info(
          "AirPlayRemux",
          "audio stream \(firstAudioIndex) chosen (requested stream: \(audioStreamIndex ?? -1))"
        )
      }
    }

    let format = forcedFormat ?? (videoIsHEVC ? .fmp4 : .mpegTS)
    subtitleInputStartTime = input.pointee.start_time
    subtitleTimestampBase = format == .mpegTS ? Self.tsTimestampBase90k : 0
    subtitleUsesFMP4 = format == .fmp4
    if let subtitleFileURL,
       let text = try? String(contentsOf: subtitleFileURL, encoding: .utf8) {
      subtitleEntries = SRTParser().parse(content: text)
      hasSubtitles = !subtitleEntries.isEmpty
      Log.info("AirPlayRemux", "external subtitle: cues=\(subtitleEntries.count), input origin=\(subtitleInputStartTime)")
    } else if let subtitleStreamIndex, (0..<streamCount).contains(subtitleStreamIndex),
              let stream = input.pointee.streams[subtitleStreamIndex] {
      subtitleDecoder = TextSubtitleDecoder(stream: stream)
      hasSubtitles = subtitleDecoder != nil
      if let parameters = stream.pointee.codecpar {
        Log.info("AirPlayRemux", "subtitle stream \(subtitleStreamIndex): codec=\(String(cString: avcodec_get_name(parameters.pointee.codec_id))), supported=\(hasSubtitles), input origin=\(subtitleInputStartTime)")
      }
      if !hasSubtitles {
        Log.error("AirPlayRemux", "selected subtitle is not a supported text stream")
      }
    }
    let passthrough = format == .fmp4 ? Self.fmp4AudioPassthrough : Self.tsAudioPassthrough

    var audioMode: AudioMode = .none
    var audioFilter: ADTSToASCFilter?
    if firstAudioIndex >= 0, let audioStream = input.pointee.streams[firstAudioIndex] {
      var canCopy = passthrough.contains(audioCodecId)
      // AAC without extradata is ADTS (MPEG-TS): fMP4 cannot take it as is. AAC that
      // already carries its config (MKV/MP4) is copied untouched, as before.
      if canCopy, format == .fmp4, audioCodecId == AV_CODEC_ID_AAC.rawValue,
         (audioStream.pointee.codecpar?.pointee.extradata_size ?? 0) <= 0
      {
        audioFilter = ADTSToASCFilter(inStream: audioStream)
        if audioFilter == nil {
          // No filter: re-encode instead of failing the whole cast.
          Log.error("AirPlayRemux", "aac_adtstoasc unavailable; transcoding ADTS AAC")
          canCopy = false
        }
      }
      if canCopy {
        audioMode = .copy(inputIndex: firstAudioIndex)
      } else if let transcoder = AudioTranscoder(inStream: audioStream) {
        Log.info("AirPlayRemux", "audio transcode to AAC (source codec id \(audioCodecId))")
        audioMode = .transcode(inputIndex: firstAudioIndex, transcoder)
      } else {
        Log.error("AirPlayRemux", "audio codec \(audioCodecId) not decodable; dropping audio")
        audioMode = .none
      }
    }
    // A copied stream goes into the output header as it was probed, and the header
    // write refuses an audio stream without a sample rate on both paths (EINVAL,
    // reported as `openOutputFailed` and taken for an incompatible source). Name the
    // cause before any output exists, so the start can be retried. Transcoding is not
    // affected: the encoder falls back to 48 kHz.
    if case let .copy(inputIndex) = audioMode,
       (input.pointee.streams[inputIndex]?.pointee.codecpar?.pointee.sample_rate ?? 0) <= 0
    {
      throw RemuxError.audioParametersUnknown
    }

    switch format {
    case .mpegTS:
      try runTSLoop(
        input: input, videoInputIndex: videoInputIndex, audioMode: audioMode
      )
    case .fmp4:
      try runFMP4Loop(
        input: input, videoInputIndex: videoInputIndex, audioMode: audioMode,
        audioFilter: audioFilter
      )
    }
  }

  /// Paket zaman damgası → saniye (girdi time base'inde). Int64.min == AV_NOPTS_VALUE.
  private func packetSeconds(
    _ packet: AVPacket,
    inStream: UnsafeMutablePointer<AVStream>,
    fallback: Double
  ) -> Double {
    let rawTS = packet.dts != Int64.min ? packet.dts : packet.pts
    return rawTS != Int64.min ? Double(rawTS) * av_q2d(inStream.pointee.time_base) : fallback
  }

  /// Çıkış ctx'ine video(0) + varsa ses(1) stream'lerini kurar.
  private func addOutputStreams(
    to output: UnsafeMutablePointer<AVFormatContext>,
    input: UnsafeMutablePointer<AVFormatContext>,
    videoInputIndex: Int,
    audioMode: AudioMode
  ) throws {
    guard let videoIn = input.pointee.streams[videoInputIndex],
          let videoOut = avformat_new_stream(output, nil)
    else { throw RemuxError.openOutputFailed(-1) }
    var result = avcodec_parameters_copy(videoOut.pointee.codecpar, videoIn.pointee.codecpar)
    guard result >= 0 else { throw RemuxError.openOutputFailed(result) }
    if videoOut.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_HEVC {
      // Apple, HLS'te HEVC için yalnız 'hvc1' sample entry kabul eder ('hev1' → -12848).
      videoOut.pointee.codecpar.pointee.codec_tag =
        UInt32(UInt8(ascii: "h")) | UInt32(UInt8(ascii: "v")) << 8
        | UInt32(UInt8(ascii: "c")) << 16 | UInt32(UInt8(ascii: "1")) << 24
    } else {
      videoOut.pointee.codecpar.pointee.codec_tag = 0
    }

    switch audioMode {
    case .none:
      break
    case let .copy(inputIndex):
      guard let audioIn = input.pointee.streams[inputIndex],
            let audioOut = avformat_new_stream(output, nil)
      else { throw RemuxError.openOutputFailed(-1) }
      result = avcodec_parameters_copy(audioOut.pointee.codecpar, audioIn.pointee.codecpar)
      guard result >= 0 else { throw RemuxError.openOutputFailed(result) }
      audioOut.pointee.codecpar.pointee.codec_tag = 0
    case let .transcode(_, transcoder):
      guard let audioOut = avformat_new_stream(output, nil) else {
        throw RemuxError.openOutputFailed(-1)
      }
      result = avcodec_parameters_from_context(audioOut.pointee.codecpar, transcoder.encoder)
      guard result >= 0 else { throw RemuxError.openOutputFailed(result) }
      audioOut.pointee.codecpar.pointee.codec_tag = 0
    }
  }

  // MARK: - MPEG-TS segment yolu (H.264)

  private final class TSSegmentContext {
    let ctx: UnsafeMutablePointer<AVFormatContext>
    let index: Int
    /// The source clock restarted before this segment (see `KeyframeContinuity`).
    let afterDiscontinuity: Bool
    var startSeconds: Double
    var lastSeconds: Double
    /// dts of the last transcoded audio packet written to this segment, in the
    /// output time base.
    var lastTranscodedDTS = Int64.min

    init(
      ctx: UnsafeMutablePointer<AVFormatContext>, index: Int, startSeconds: Double,
      afterDiscontinuity: Bool
    ) {
      self.ctx = ctx
      self.index = index
      self.afterDiscontinuity = afterDiscontinuity
      self.startSeconds = startSeconds
      lastSeconds = startSeconds
    }
  }

  private func runTSLoop(
    input: UnsafeMutablePointer<AVFormatContext>,
    videoInputIndex: Int,
    audioMode: AudioMode
  ) throws {
    // Mutable: the transcoder is replaced when the source timeline restarts.
    var audioMode = audioMode
    var current: TSSegmentContext?
    var nextSegmentIndex = 0
    var continuity = KeyframeContinuity()
    // Set when a source timestamp jump closed a segment: the next one starts a new
    // timeline and is listed after EXT-X-DISCONTINUITY.
    var pendingDiscontinuity = false
    // Duration of the latest video frame in seconds: the tail of a segment that
    // does not end at the next keyframe.
    var videoFrameSeconds: Double = 0

    func openSegment(startSeconds: Double) throws {
      let fileName = String(format: "seg%05d.ts", nextSegmentIndex)
      let path = outputDirectory.appendingPathComponent(fileName).path
      var outCtx: UnsafeMutablePointer<AVFormatContext>?
      var result = avformat_alloc_output_context2(&outCtx, nil, "mpegts", path)
      guard result >= 0, let out = outCtx else { throw RemuxError.openOutputFailed(result) }
      do {
        try addOutputStreams(
          to: out, input: input, videoInputIndex: videoInputIndex, audioMode: audioMode
        )
      } catch {
        avformat_free_context(out)
        throw error
      }
      result = avio_open(&out.pointee.pb, path, AVIO_FLAG_WRITE)
      guard result >= 0 else {
        avformat_free_context(out)
        throw RemuxError.openOutputFailed(result)
      }
      result = avformat_write_header(out, nil)
      guard result >= 0 else {
        avio_closep(&out.pointee.pb)
        avformat_free_context(out)
        throw RemuxError.openOutputFailed(result)
      }
      current = TSSegmentContext(
        ctx: out, index: nextSegmentIndex, startSeconds: startSeconds,
        afterDiscontinuity: pendingDiscontinuity
      )
      pendingDiscontinuity = false
      nextSegmentIndex += 1
    }

    // `endSeconds` is where the segment ends on the source clock: the keyframe that
    // opens the next segment, or the end of the last video frame when there is none.
    // Last packet minus first packet came out one frame short.
    func closeSegment(final: Bool, endSeconds: Double) {
      guard let segment = current else { return }
      current = nil
      av_write_trailer(segment.ctx)
      avio_closep(&segment.ctx.pointee.pb)
      let fileName = String(format: "seg%05d.ts", segment.index)
      avformat_free_context(segment.ctx)
      addBytesWritten(fileSize(named: fileName))
      recordSegment(
        index: segment.index,
        fileName: fileName,
        duration: endSeconds - segment.startSeconds,
        discontinuity: segment.afterDiscontinuity,
        sourceStartSeconds: segment.startSeconds,
        final: final
      )
    }

    // End of the video read so far, for a segment that closes without a following
    // keyframe (end of stream, timestamp jump, write error).
    func videoTailSeconds() -> Double {
      (continuity.lastVideoSeconds ?? current?.lastSeconds ?? 0) + videoFrameSeconds
    }

    // Transcoded AAC paketleri: encoder tb → mevcut segmentin ses stream tb'sine.
    func writeTranscodedPacket(
      _ encoded: UnsafeMutablePointer<AVPacket>, transcoder: AudioTranscoder
    ) throws {
      guard let segment = current,
            let outStream = segment.ctx.pointee.streams[1]
      else { return }
      encoded.pointee.stream_index = 1
      av_packet_rescale_ts(
        encoded, transcoder.encoderTimeBase, outStream.pointee.time_base
      )
      // The transcoder re-locks to the source clock when it jumps, and after a
      // backward jump its packets run behind what this segment already holds. The
      // muxer would reject them (non-monotonic dts) and end the session before the
      // keyframe that starts the new timeline arrives; that audio belongs to
      // frames which are not shown anyway, so it is dropped.
      let dts = encoded.pointee.dts
      if dts != Int64.min {
        if dts <= segment.lastTranscodedDTS { return }
        segment.lastTranscodedDTS = dts
      }
      let timestampBase = Self.tsTimestampBase(in: outStream.pointee.time_base)
      if encoded.pointee.pts != Int64.min { encoded.pointee.pts += timestampBase }
      if encoded.pointee.dts != Int64.min { encoded.pointee.dts += timestampBase }
      let result = av_interleaved_write_frame(segment.ctx, encoded)
      if result < 0 { throw RemuxError.writeFailed(result) }
    }

    var videoClock = TimestampRepair()
    var audioClock = TimestampRepair()
    var packet = AVPacket()
    // Yazılan son video medya zamanı (kaynak zaman çizelgesinde) — pacing kapısı
    // ve erken-EOF tespiti buna bakar.
    // Kept in 0-based content time (see contentSeconds): a recording whose first PTS
    // is hours in would otherwise sit past the pacing window forever.
    var paceClock = effectiveStartSeconds
    // The same high-water mark on the source's own clock, for the early-EOF test,
    // which compares against the source's duration. The two differ only after a
    // timestamp jump: the pacing gate is measured against the playback position,
    // which follows the playlist, and the playlist does not contain the jump.
    var sourceClock = effectiveStartSeconds
    var paceOffset: Double = 0
    let inputStartTime = input.pointee.start_time
    while cancelled.pointee == 0 {
      waitForPacing(mediaSeconds: paceClock)
      if cancelled.pointee != 0 { break }
      let readResult = try readFrame(input, into: &packet)
      if readResult == Self.avErrorEOF {
        // Canlı yayın "bitmez": EOF = kaynak koptu. VOD'da sürenin belirgin
        // gerisindeki EOF de kopmadır (panel bağlantıyı temiz kapatmış olabilir) —
        // ikisi de tamamlanma DEĞİL hatadır; ENDLIST yazılırsa film ortasında
        // sahte "bitti" + auto-next tetiklenir.
        if isLive { throw RemuxError.readFailed(readResult) }
        if sourceDurationSeconds > 0, sourceClock < sourceDurationSeconds - 30 {
          throw RemuxError.readFailed(readResult)
        }
        break
      }
      if readResult < 0 { throw RemuxError.readFailed(readResult) }
      defer { av_packet_unref(&packet) }
      notePacketRead()
      if decodeSubtitlePacket(&packet, input: input) { continue }
      let inIndex = Int(packet.stream_index)
      guard let inStream = input.pointee.streams[inIndex] else { continue }
      let isVideo = inIndex == videoInputIndex
      let isAudio = inIndex == audioMode.inputIndex
      guard isVideo || isAudio else { continue }

      let seconds = packetSeconds(packet, inStream: inStream, fallback: current?.lastSeconds ?? 0)
      let contentSeconds = Self.contentSeconds(
        containerSeconds: seconds, inputStartTime: inputStartTime
      )
      if isVideo, contentSeconds > sourceClock { sourceClock = contentSeconds }
      let isKeyframe = (packet.flags & AV_PKT_FLAG_KEY) != 0
      var jump: KeyframeContinuity.Jump?
      if isVideo {
        // The tail has to be taken before this packet moves the detector.
        let tailSeconds = videoTailSeconds()
        jump = continuity.observe(videoSeconds: seconds, isKeyframe: isKeyframe)
        if let jump {
          // The source clock restarted (or leapt) at this keyframe. Left alone, a
          // backward jump stops every segment cut until the clock passes its old
          // value and squashes each packet one tick apart, without any error.
          // Splice instead: end the segment here, start both repair clocks afresh
          // at the keyframe and tell the player the timeline restarts.
          Log.info(
            "AirPlayRemux",
            String(format: "source timestamps jumped %+.1fs; starting a new timeline", jump.seconds)
          )
          closeSegment(final: false, endSeconds: tailSeconds)
          videoClock = TimestampRepair()
          audioClock = TimestampRepair()
          pendingDiscontinuity = true
          // The encoder still holds frames stamped on the old timeline; they would
          // open the new segment ahead of (or far behind) its video. A fresh
          // transcoder starts on the new timeline with nothing queued.
          if case let .transcode(audioIndex, _) = audioMode,
             let audioStream = input.pointee.streams[audioIndex],
             let fresh = AudioTranscoder(inStream: audioStream)
          {
            audioMode = .transcode(inputIndex: audioIndex, fresh)
          }
          // The playlist carries on where the old timeline ended, so does pacing.
          paceOffset = contentSeconds - paceClock
        }
        if packet.duration > 0 {
          videoFrameSeconds = Double(packet.duration) * av_q2d(inStream.pointee.time_base)
        }
      } else {
        continuity.observe(audioSeconds: seconds)
      }
      // Between a jump and its keyframe the source already sends the next timeline.
      // Those packets cannot be shown (their keyframe is not here yet), and written
      // to this segment they leave audio or frames stamped far from its video.
      if jump == nil, continuity.isOffTimeline(seconds) { continue }
      if isVideo, contentSeconds - paceOffset > paceClock {
        paceClock = contentSeconds - paceOffset
      }
      if jump == nil, let segment = current, isVideo, isKeyframe,
         seconds - segment.startSeconds >= targetDuration(forSegmentIndex: segment.index)
      {
        closeSegment(final: false, endSeconds: seconds)
      }
      if current == nil {
        guard isVideo, isKeyframe else { continue }
        noteFirstVideoContentSeconds(contentSeconds)
        try openSegment(startSeconds: seconds)
      }
      guard let segment = current else { continue }
      if isVideo || audioMode.inputIndex == inIndex, seconds > segment.lastSeconds {
        segment.lastSeconds = seconds
      }

      if isAudio, case let .transcode(_, transcoder) = audioMode {
        try transcoder.process(packet: &packet) { encoded in
          try writeTranscodedPacket(encoded, transcoder: transcoder)
        }
        continue
      }

      let outIndex = isVideo ? 0 : 1
      guard let outStream = segment.ctx.pointee.streams[outIndex] else { continue }
      packet.stream_index = Int32(outIndex)
      av_packet_rescale_ts(&packet, inStream.pointee.time_base, outStream.pointee.time_base)
      if isVideo {
        guard let repaired = videoClock.repairVideo(pts: packet.pts, duration: packet.duration)
        else { continue }
        packet.pts = repaired.pts
        packet.dts = repaired.dts
      } else {
        guard let repaired = audioClock.repairAudio(
          pts: packet.pts, dts: packet.dts, duration: packet.duration
        ) else { continue }
        packet.pts = repaired.pts
        packet.dts = repaired.dts
      }
      // The session's constant base goes on after the repair, which works on the
      // source's own values (see tsTimestampBase90k).
      let timestampBase = Self.tsTimestampBase(in: outStream.pointee.time_base)
      if packet.pts != Int64.min { packet.pts += timestampBase }
      if packet.dts != Int64.min { packet.dts += timestampBase }
      packet.pos = -1
      let writeResult = av_interleaved_write_frame(segment.ctx, &packet)
      if writeResult < 0 {
        closeSegment(final: false, endSeconds: videoTailSeconds())
        throw RemuxError.writeFailed(writeResult)
      }
    }
    // İptalde final flush atlanır: yarım muxer'ı boşaltmak hem gürültü ("Cannot write
    // moov…") hem panelin bağlantı sınırını meşgul eden gereksiz kapanış işi üretir.
    if cancelled.pointee == 0, case let .transcode(_, transcoder) = audioMode, current != nil {
      try? transcoder.finish { encoded in
        try writeTranscodedPacket(encoded, transcoder: transcoder)
      }
    }
    if cancelled.pointee == 0 {
      closeSegment(final: !isLive, endSeconds: videoTailSeconds())
    } else if let segment = current {
      current = nil
      avio_closep(&segment.ctx.pointee.pb)
      avformat_free_context(segment.ctx)
    }
  }

  // MARK: - fMP4 segment yolu (HEVC)

  /// Custom AVIO'nun yazdığı byte'ları biriktirir; fragment sınırında dosyaya bölünür.
  private final class ByteSink {
    var data = Data()
  }

  private func runFMP4Loop(
    input: UnsafeMutablePointer<AVFormatContext>,
    videoInputIndex: Int,
    audioMode: AudioMode,
    audioFilter: ADTSToASCFilter?
  ) throws {
    // mp4 (unlike mpegts) refuses a video stream without dimensions: the header
    // write would fail with EINVAL ("dimensions not set"). Name the cause instead.
    if let videoPar = input.pointee.streams[videoInputIndex]?.pointee.codecpar,
       videoPar.pointee.width <= 0 || videoPar.pointee.height <= 0
    {
      throw RemuxError.videoParametersUnknown
    }

    let sink = ByteSink()
    let sinkRef = Unmanaged.passRetained(sink)
    defer { sinkRef.release() }

    let bufferSize: Int32 = 1 << 16
    guard let avioBuffer = av_malloc(Int(bufferSize)) else {
      throw RemuxError.openOutputFailed(-1)
    }
    let writeCallback: @convention(c) (
      UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32
    ) -> Int32 = { opaque, buf, size in
      guard let opaque, let buf, size > 0 else { return size }
      let sink = Unmanaged<ByteSink>.fromOpaque(opaque).takeUnretainedValue()
      sink.data.append(buf, count: Int(size))
      return size
    }
    var avio = avio_alloc_context(
      avioBuffer.assumingMemoryBound(to: UInt8.self), bufferSize, 1,
      sinkRef.toOpaque(), nil, writeCallback, nil
    )
    guard avio != nil else {
      av_free(avioBuffer)
      throw RemuxError.openOutputFailed(-1)
    }

    var outCtx: UnsafeMutablePointer<AVFormatContext>?
    var result = avformat_alloc_output_context2(&outCtx, nil, "mp4", nil)
    guard result >= 0, let out = outCtx else {
      avioFree(&avio)
      throw RemuxError.openOutputFailed(result)
    }
    out.pointee.pb = avio
    defer {
      out.pointee.pb = nil
      avioFree(&avio)
      avformat_free_context(out)
    }

    try addOutputStreams(
      to: out, input: input, videoInputIndex: videoInputIndex, audioMode: audioMode
    )

    var headerOpts: OpaquePointer?
    // frag_custom: fragment sınırlarını biz belirleriz (NULL-frame flush);
    // delay_moov: moov ilk flush'ta yazılır — EAC3 gibi codec'ler moov'daki kutular için
    // önce paket görmek ister; skip_trailer: mfra üretme.
    av_dict_set(
      &headerOpts, "movflags",
      "+empty_moov+default_base_moof+frag_custom+delay_moov+skip_trailer", 0
    )
    result = avformat_write_header(out, &headerOpts)
    av_dict_free(&headerOpts)
    guard result >= 0 else { throw RemuxError.openOutputFailed(result) }

    var segmentIndex = 0
    var segmentStart: Double = 0
    var segmentLast: Double = 0
    var segmentHasData = false
    var initWritten = false
    // dts of the last transcoded audio packet written, in the output time base. One
    // muxer serves the whole session, so this is not per segment.
    var lastTranscodedDTS = Int64.min

    // `endSeconds`: where the segment ends on the source clock (see the TS loop).
    func emitFragment(final: Bool, endSeconds: Double) throws {
      // Önce interleave kuyruğu boşaltılır; sonra av_write_frame(NULL) muxer'ı flush eder —
      // frag_custom'da fragment (moof+mdat) ancak bununla üretilir (interleaved NULL yetmez).
      // delay_moov ile ilk flush moov'u da üretir; kutu sınırından bölünür.
      _ = av_interleaved_write_frame(out, nil)
      _ = av_write_frame(out, nil)
      if !initWritten {
        _ = av_write_frame(out, nil)
      }
      avio_flush(out.pointee.pb)
      guard !sink.data.isEmpty else { return }
      if !initWritten {
        let (initData, fragmentData) = Self.splitAtFirstFragmentBox(sink.data)
        guard !initData.isEmpty else { return }
        // Disk hatası (dolu disk vb.) yutulursa TV sessizce donar; hata olarak yüzer.
        try initData.write(to: outputDirectory.appendingPathComponent("init.mp4"))
        addBytesWritten(Int64(initData.count))
        Log.info(
          "AirPlayRemux",
          "fmp4 init: \(initData.count)B, first fragment: \(fragmentData.count)B"
        )
        initWritten = true
        sink.data = fragmentData
      }
      guard segmentHasData, !sink.data.isEmpty else { return }
      let fileName = String(format: "seg%05d.m4s", segmentIndex)
      try sink.data.write(to: outputDirectory.appendingPathComponent(fileName))
      addBytesWritten(Int64(sink.data.count))
      sink.data.removeAll(keepingCapacity: true)
      recordSegment(
        index: segmentIndex,
        fileName: fileName,
        duration: endSeconds - segmentStart,
        sourceStartSeconds: segmentStart,
        final: final
      )
      segmentIndex += 1
      segmentHasData = false
    }

    func writeTranscodedPacket(
      _ encoded: UnsafeMutablePointer<AVPacket>, transcoder: AudioTranscoder
    ) throws {
      guard let outStream = out.pointee.streams[1] else { return }
      encoded.pointee.stream_index = 1
      av_packet_rescale_ts(encoded, transcoder.encoderTimeBase, outStream.pointee.time_base)
      // After a backward source jump the transcoder re-locks behind what the muxer
      // already holds; mp4 rejects that (non-monotonic dts) and the session would
      // end before the jump keyframe decides between healing and a rebuild. Drop
      // until the clock passes its old value, as the MPEG-TS path does.
      let dts = encoded.pointee.dts
      if dts != Int64.min {
        if dts <= lastTranscodedDTS { return }
        lastTranscodedDTS = dts
      }
      let writeResult = av_interleaved_write_frame(out, encoded)
      if writeResult < 0 { throw RemuxError.writeFailed(writeResult) }
      segmentHasData = true
    }

    var videoClock = TimestampRepair()
    var audioClock = TimestampRepair()
    var packet = AVPacket()
    var startedAtKeyframe = false
    var continuity = KeyframeContinuity()
    // Duration of the latest video frame in seconds (see the TS loop).
    var videoFrameSeconds: Double = 0
    // A rebuild reopens the source at the playback position, which needs a source
    // that can seek (AVIO_SEEKABLE_NORMAL is bit 0; the macro is not imported) and
    // whose start seek did not already fail.
    let sourceSeekable = ((input.pointee.pb?.pointee.seekable ?? 0) & 1) != 0
      && !(startSeconds > 1 && effectiveStartSeconds == 0)
    // 0-based content time, as in the TS loop.
    var paceClock = effectiveStartSeconds
    // Source-clock high-water mark for the early-EOF test (see the TS loop).
    var sourceClock = effectiveStartSeconds
    var paceOffset: Double = 0
    let inputStartTime = input.pointee.start_time
    while cancelled.pointee == 0 {
      waitForPacing(mediaSeconds: paceClock)
      if cancelled.pointee != 0 { break }
      let readResult = try readFrame(input, into: &packet)
      if readResult == Self.avErrorEOF {
        // Bkz. TS döngüsündeki not: canlıda ve sürenin belirgin gerisindeki VOD'da
        // EOF kopmadır — tamamlanma değil.
        if isLive { throw RemuxError.readFailed(readResult) }
        if sourceDurationSeconds > 0, sourceClock < sourceDurationSeconds - 30 {
          throw RemuxError.readFailed(readResult)
        }
        break
      }
      if readResult < 0 { throw RemuxError.readFailed(readResult) }
      defer { av_packet_unref(&packet) }
      notePacketRead()
      if decodeSubtitlePacket(&packet, input: input) { continue }
      let inIndex = Int(packet.stream_index)
      guard let inStream = input.pointee.streams[inIndex] else { continue }
      let isVideo = inIndex == videoInputIndex
      let isAudio = inIndex == audioMode.inputIndex
      guard isVideo || isAudio else { continue }

      let seconds = packetSeconds(packet, inStream: inStream, fallback: segmentLast)
      let contentSeconds = Self.contentSeconds(
        containerSeconds: seconds, inputStartTime: inputStartTime
      )
      if isVideo, contentSeconds > sourceClock { sourceClock = contentSeconds }
      let isKeyframe = (packet.flags & AV_PKT_FLAG_KEY) != 0
      if !startedAtKeyframe {
        guard isVideo, isKeyframe else { continue }
        startedAtKeyframe = true
        noteFirstVideoContentSeconds(contentSeconds)
        segmentStart = seconds
        segmentLast = seconds
      }
      var jump: KeyframeContinuity.Jump?
      if isVideo {
        // The tail has to be taken before this packet moves the detector.
        let tailSeconds = (continuity.lastVideoSeconds ?? segmentLast) + videoFrameSeconds
        jump = continuity.observe(videoSeconds: seconds, isKeyframe: isKeyframe)
        if let jump {
          let rebuild = Self.fmp4NeedsRebuild(
            after: jump, isLive: isLive, sourceSeekable: sourceSeekable
          )
          Log.info(
            "AirPlayRemux",
            String(
              format: "source timestamps jumped %+.1fs on the fmp4 path; %@",
              jump.seconds, rebuild ? "session rebuild" : "cutting the segment here"
            )
          )
          // One mp4 muxer serves the whole session and cannot restart its
          // timeline, so a large jump ends the session for the controller's
          // in-place rebuild.
          if rebuild { throw RemuxError.timestampDiscontinuity }
          // Otherwise keep going on the repaired timestamps, but cut here: after
          // a backward jump `seconds - segmentStart` stays negative and no
          // segment would close until the clock passed its old value.
          if segmentHasData {
            try emitFragment(final: false, endSeconds: tailSeconds)
          }
          segmentStart = seconds
          segmentLast = seconds
          paceOffset = contentSeconds - paceClock
        }
        if packet.duration > 0 {
          videoFrameSeconds = Double(packet.duration) * av_q2d(inStream.pointee.time_base)
        }
      } else {
        continuity.observe(audioSeconds: seconds)
      }
      // Packets that have leapt ahead of a jump's keyframe must not move the pacing
      // clock: the gate would close before that keyframe is read.
      if isVideo, jump != nil || !continuity.isOffTimeline(seconds),
         contentSeconds - paceOffset > paceClock
      {
        paceClock = contentSeconds - paceOffset
      }
      if jump == nil, segmentHasData, isVideo, isKeyframe,
         seconds - segmentStart >= targetDuration(forSegmentIndex: segmentIndex)
      {
        try emitFragment(final: false, endSeconds: seconds)
        segmentStart = seconds
      }
      if seconds > segmentLast { segmentLast = seconds }

      if isAudio, case let .transcode(_, transcoder) = audioMode {
        try transcoder.process(packet: &packet) { encoded in
          try writeTranscodedPacket(encoded, transcoder: transcoder)
        }
        continue
      }

      if isAudio, let audioFilter {
        // An empty packet would be taken as end-of-stream by the filter and every
        // later send would fail.
        guard packet.size > 0 else { continue }
        // The filter attaches the AudioSpecificConfig to the first packet it sees, so
        // a packet the timestamp repair below would skip must not reach it: the
        // config would be dropped with it and the track written without one.
        guard audioClock.hasReference || packet.pts != Int64.min || packet.dts != Int64.min
        else { continue }
        // aac_adtstoasc is strictly one packet in, one packet out, so a single
        // receive drains it and the filtered packet takes the normal copy path below
        // (timestamps and stream index are carried through in the input time base).
        var filterResult = av_bsf_send_packet(audioFilter.context, &packet)
        if filterResult >= 0 {
          filterResult = av_bsf_receive_packet(audioFilter.context, &packet)
        }
        if filterResult == -EAGAIN { continue }
        if filterResult < 0 {
          Log.error("AirPlayRemux", "aac_adtstoasc failed \(filterResult)")
          throw RemuxError.writeFailed(filterResult)
        }
      }

      let outIndex = isVideo ? 0 : 1
      guard let outStream = out.pointee.streams[outIndex] else { continue }
      packet.stream_index = Int32(outIndex)
      av_packet_rescale_ts(&packet, inStream.pointee.time_base, outStream.pointee.time_base)
      if isVideo {
        let isFirstVideoPacket = !videoClock.hasReference
        guard let repaired = videoClock.repairVideo(pts: packet.pts, duration: packet.duration)
        else { continue }
        packet.pts = repaired.pts
        packet.dts = repaired.dts
        if isFirstVideoPacket {
          // The MP4 muxer rebases tfdt to the first decode timestamp. Absolute
          // source PTS survive only in edit lists, which HLS ignores. WebVTT must
          // use the fragment's media clock, including its first frame's CTS offset.
          subtitleTimestampBase = -av_rescale_q(
            repaired.dts, outStream.pointee.time_base, AVRational(num: 1, den: 90_000)
          )
          Log.info("AirPlayRemux", "fmp4 subtitle clock offset=\(subtitleTimestampBase)")
        }
      } else {
        guard let repaired = audioClock.repairAudio(
          pts: packet.pts, dts: packet.dts, duration: packet.duration
        ) else { continue }
        packet.pts = repaired.pts
        packet.dts = repaired.dts
      }
      packet.pos = -1
      let logPTS = packet.pts
      let logDTS = packet.dts
      let writeResult = av_interleaved_write_frame(out, &packet)
      if writeResult < 0 {
        Log.error(
          "AirPlayRemux",
          "fmp4 write failed \(writeResult): out=\(outIndex) pts=\(logPTS) dts=\(logDTS) key=\(isKeyframe)"
        )
        throw RemuxError.writeFailed(writeResult)
      }
      segmentHasData = true
    }
    if cancelled.pointee == 0 {
      if case let .transcode(_, transcoder) = audioMode, startedAtKeyframe {
        try? transcoder.finish { encoded in
          try writeTranscodedPacket(encoded, transcoder: transcoder)
        }
      }
      try emitFragment(
        final: !isLive,
        endSeconds: (continuity.lastVideoSeconds ?? segmentLast) + videoFrameSeconds
      )
      av_write_trailer(out)
    }
  }

  /// MP4 kutu akışını ilk 'moof'/'styp' kutusunda böler: öncesi init (ftyp+moov),
  /// sonrası ilk media fragment'ı.
  static func splitAtFirstFragmentBox(_ data: Data) -> (initData: Data, fragmentData: Data) {
    var offset = data.startIndex
    while offset + 8 <= data.endIndex {
      let size = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
      let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
      if type == "moof" || type == "styp" {
        return (Data(data[data.startIndex..<offset]), Data(data[offset...]))
      }
      guard size >= 8, offset + size <= data.endIndex else { break }
      offset += size
    }
    return (Data(data), Data())
  }

  private func avioFree(_ avio: inout UnsafeMutablePointer<AVIOContext>?) {
    guard let ctx = avio else { return }
    av_free(ctx.pointee.buffer)
    ctx.pointee.buffer = nil
    avio_context_free(&avio)
  }

  // MARK: - Playlist

  /// m3u8 atomik yazım: AVPlayer yarım playlist okumasın.
  private func writePlaylist(final: Bool) {
    guard !segments.isEmpty else { return }
    // RFC 8216 6.2.1 wants TARGETDURATION constant. It used to be recomputed from
    // the listed segments on every write, so on live it rose with a long segment
    // and fell again when that segment left the window. It now never falls: for a
    // source with a regular GOP it is constant from the first playlist a client can
    // see. It still rises when a later segment is longer, because the alternative
    // is worse: AVPlayer refuses a playlist whose segment is more than about twice
    // the target (CoreMediaErrorDomain -12642). No headroom is added up front; a
    // larger value would lengthen the receiver's three-target hold-back.
    let target = max(
      sessionTargetDuration,
      Self.targetDuration(for: segments, nominalSeconds: targetSegmentSeconds)
    )
    sessionTargetDuration = target
    let content = Self.mediaPlaylist(
      segments: segments,
      isLive: isLive,
      targetDuration: target,
      discontinuitySequence: discontinuitySequence,
      final: final
    )
    do {
      try content.write(to: playlistURL, atomically: true, encoding: .utf8)
    } catch {
      // Bayat playlist TV'yi sessizce dondurur (disk dolu/sandbox): hata olarak yüz.
      Log.error("AirPlayRemux", "playlist write failed: \(error.localizedDescription)")
      if cancelled.pointee == 0 {
        DispatchQueue.main.async { [weak self] in self?.onError?(error) }
      }
    }
  }

  static func targetDuration(for segments: [SegmentRecord], nominalSeconds: Double) -> Int {
    // Taban targetSegmentSeconds: ilk (kısa) segmentte TD'nin 2'den başlayıp sonra
    // büyümesi yerine kararlı başlar; seyrek keyframe'li kaynakta yine büyüyebilir.
    // One frame of tolerance before rounding up. Durations are now exact, and a 2 s
    // segment measures 2.0000000000000018: rounded up as it is, the target would
    // become 3 and add a whole target duration to the receiver's hold-back. RFC
    // 8216 4.3.3.1 accepts any EXTINF that rounds to the target or less.
    let longest = (segments.map(\.duration).max() ?? 0) - 0.05
    return max(Int(longest.rounded(.up)), Int(nominalSeconds.rounded(.up)), 1)
  }

  /// The media playlist text. Pure, so tag placement is table-testable.
  static func mediaPlaylist(
    segments: [SegmentRecord],
    isLive: Bool,
    targetDuration: Int,
    discontinuitySequence: Int,
    final: Bool
  ) -> String {
    let usesFMP4 = segments.first?.fileName.hasSuffix(".m4s") ?? false
    var lines: [String] = [
      "#EXTM3U",
      "#EXT-X-VERSION:\(usesFMP4 ? 7 : 3)",
      "#EXT-X-INDEPENDENT-SEGMENTS",
      "#EXT-X-TARGETDURATION:\(max(targetDuration, 1))",
      "#EXT-X-MEDIA-SEQUENCE:\(segments.first?.index ?? 0)",
    ]
    // RFC 8216 6.2.2: a playlist that drops segments and carries a discontinuity
    // must number them, so a client that reloads after the tagged segment has
    // left the window still knows which timeline each segment belongs to. It is
    // written only once a jump has happened, so an ordinary session's playlist is
    // unchanged.
    if isLive, discontinuitySequence > 0 || segments.contains(where: \.discontinuity) {
      lines.append("#EXT-X-DISCONTINUITY-SEQUENCE:\(discontinuitySequence)")
    }
    if !isLive {
      // Büyüyen event playlist'i taze bir istemci canlı sanıp YAYIN UCUNDAN katılır.
      // AirPlay'de Apple TV playlist'i KENDİSİ çektiğinden telefon tarafındaki seek
      // düzeltmesi TV'nin katılımını koruyamaz — ilk açılıştaki donma + sessiz ileri
      // sıçramanın kökü. EVENT + START=0 her taze istemciyi baştan başlatır.
      lines.append("#EXT-X-PLAYLIST-TYPE:EVENT")
      lines.append("#EXT-X-START:TIME-OFFSET=0,PRECISE=YES")
    }
    if usesFMP4 {
      lines.append("#EXT-X-MAP:URI=\"init.mp4\"")
    }
    for segment in segments {
      // The tag stays with its segment, also when that segment is first in the
      // window; the sequence above rises only when the pair is removed.
      if segment.discontinuity {
        lines.append("#EXT-X-DISCONTINUITY")
      }
      lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
      lines.append(segment.fileName)
    }
    if final {
      lines.append("#EXT-X-ENDLIST")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// Motor tarafında hızlı codec ön-kontrolü: adaylık artık yalnız videoya bakar —
  /// uyumsuz ses AAC'ye transcode edilir. Profil ekli adlar normalize edilir.
  static func isCompatible(videoFourCC: String, audioFourCC _: String? = nil) -> Bool {
    ["avc1", "h264", "hvc1", "hev1", "hevc"].contains(normalizeCodec(videoFourCC))
  }

  static func normalizeCodec(_ raw: String) -> String {
    raw.lowercased()
      .split(separator: " ").first.map(String.init)?
      .trimmingCharacters(in: .whitespaces) ?? ""
  }
}
