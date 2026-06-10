import Combine
import CoreVideo
import Darwin
import Foundation

private final class WakeupHelper {
  let queue: DispatchQueue
  let handle: OpaquePointer
  weak var videoOutput: NativeVideoOutput?
  weak var player: MPVPlayer?

  init(queue: DispatchQueue, handle: OpaquePointer) {
    self.queue = queue
    self.handle = handle
  }

  func scheduleDrain() {
    queue.async { [weak self] in
      guard let self else { return }
      while true {
        let evPtr = mpv_wait_event(self.handle, 0)!
        let ev = evPtr.pointee
        if ev.event_id == MPV_EVENT_NONE { break }
        self.handleEvent(ev)
      }
    }
  }

  /// Video boyutu `mpv` kuyruğunda güncellenir; render worker asla `mpv_get_property` çağırmaz.
  private func handleEvent(_ ev: mpv_event) {
    let id = ev.event_id
    if id == MPV_EVENT_PROPERTY_CHANGE {
      player?.handleObservedPropertyChange(replyUserdata: ev.reply_userdata)
    }

    if id == MPV_EVENT_LOG_MESSAGE, let data = ev.data {
      let logMsg = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
      player?.handleMpvLogMessage(logMsg)
    }

    if id == MPV_EVENT_START_FILE {
      player?.onMpvStartFile()
      player?.clearPlaybackFailure()
    }
    if id == MPV_EVENT_FILE_LOADED || id == MPV_EVENT_PLAYBACK_RESTART {
      player?.onMpvPlaybackPipelineReady()
    }
    if id == MPV_EVENT_END_FILE, let data = ev.data {
      player?.onMpvEndFile()
      let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
      player?.handleEndFileEvent(end)
    }

    // `PROPERTY_CHANGE` (raw=22) çok sık gelir; her seferinde worker’da tam render tetiklemek PiP / ana kuyruk ile çarpışır.
    // Boyut için `VIDEO_RECONFIG` ve dosya yaşam döngüsü olayları yeterli; özellik gözlemi `handleObservedPropertyChange` ile kalır.
    switch id {
    case MPV_EVENT_VIDEO_RECONFIG,
         MPV_EVENT_FILE_LOADED,
         MPV_EVENT_PLAYBACK_RESTART,
         MPV_EVENT_START_FILE,
         MPV_EVENT_END_FILE:
      MPVPlayerVideoLog.throttled("Wakeup.video", first: 60, every: 0) {
        "mpv event raw=\(id.rawValue) → refreshDecodedVideoSizeFromMpv"
      }
      videoOutput?.refreshDecodedVideoSizeFromMpv()
      if id == MPV_EVENT_FILE_LOADED
        || id == MPV_EVENT_PLAYBACK_RESTART
        || id == MPV_EVENT_END_FILE
      {
        player?.publishPlaybackStateFromMpvQueue()
      }
    default:
      break
    }
  }
}

/// libmpv çekirdeği + `NativeVideoOutput` (GLES / yazılım render yolu ayrımı demo ile aynı).
public final class MPVPlayer: ObservableObject {
  private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { userdata in
    guard let userdata else { return }
    Unmanaged<WakeupHelper>.fromOpaque(userdata).takeUnretainedValue().scheduleDrain()
  }

  /// `deinit` içinde `mpvQueue.sync` ile aynı kuyrukta yeniden giriş deadlock olmasın diye.
  private static let mpvQueueSpecificKey = DispatchSpecificKey<UInt8>()
  private let mpvQueue = DispatchQueue(label: "MPVPlayer.mpv", qos: .userInitiated)
  private var mpv: OpaquePointer?
  private var videoOutput: NativeVideoOutput?
  private var wakeupHelper: WakeupHelper?
  private var wakeupRetained: Unmanaged<WakeupHelper>?
  private var isDisposed = false
  private let renderCallbackLock = NSLock()
  private var onFrameCallback: NativeVideoOutput.FrameCallback?
  private var onVideoSizeChangeCallback: NativeVideoOutput.SizeCallback?
  /// `time-pos` gözleminde ana iş parçacığına basma sıklığı (saniye).
  private var lastPositionPublishTime: CFTimeInterval = 0
  /// `loadfile start=...` ile açılışta ilk time-pos doğrulaması için.
  private var pendingInitialStartSeconds: Double?
  private var didLogInitialStartPosition = false
  /// Yalnızca `mpv` kuyruğu: `FILE_LOADED` / `PLAYBACK_RESTART` gelene kadar `false` (pause=no olsa bile UI “oynatılıyor” sayılmasın).
  private var playbackPipelinePrimed = false
  private var loadTimeoutWorkItem: DispatchWorkItem?

  @Published public private(set) var isReady = false
  @Published public private(set) var isPaused = true
  @Published public private(set) var isSeekable = false

  // MARK: - Oynatma durumu özeti

  @Published public private(set) var position: TimeInterval = 0
  @Published public private(set) var duration: TimeInterval = 0
  @Published public private(set) var isBuffering = false
  @Published public private(set) var isCompleted = false
  @Published public private(set) var volume: Double = 100
  @Published public private(set) var playbackRate: Double = 1
  @Published public private(set) var videoDisplayWidth: Int = 0
  @Published public private(set) var videoDisplayHeight: Int = 0
  @Published public private(set) var streamFPS: Double = 0
  @Published public private(set) var renderFPS: Double = 0
  @Published public private(set) var videoBitrate: Double = 0
  @Published public private(set) var droppedFrameCount: Int64 = 0
  @Published public private(set) var delayedFrameCount: Int64 = 0
  @Published public private(set) var cacheBufferingState: Double = 0
  @Published public private(set) var cacheDurationSeconds: Double = 0
  @Published public private(set) var avSyncSeconds: Double = 0
  @Published public private(set) var networkSpeedBps: Double = 0
  @Published public private(set) var hwdecCurrent: String = ""
  @Published public private(set) var videoCodecName: String = ""
  @Published public private(set) var mediaTitle: String = ""
  /// Zaman çizelgesi üst sınırı (saniye); `demuxer-cache-time` (tampon sonu).
  @Published public private(set) var bufferTimelineEnd: TimeInterval = 0
  /// `MPV_EVENT_END_FILE` + `MPV_END_FILE_REASON_ERROR` (ör. ağ / yükleme hatası).
  @Published public private(set) var playbackFailureMessage: String?
  /// Gerçek demuxer/decoder hazır (`FILE_LOADED` veya `PLAYBACK_RESTART`); bağlantı beklerken `false`.
  @Published public private(set) var isPlaybackEstablished = false

  /// Tek struct’ta anlık kopya (ör. debug veya köprü).
  public var playbackInfo: MPVPlaybackInfo {
    MPVPlaybackInfo(
      positionSeconds: position,
      durationSeconds: duration,
      isPaused: isPaused,
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      volume: volume,
      playbackRate: playbackRate,
      videoDisplayWidth: videoDisplayWidth,
      videoDisplayHeight: videoDisplayHeight,
      mediaTitle: mediaTitle
    )
  }

  public init() {
    mpvQueue.setSpecific(key: Self.mpvQueueSpecificKey, value: 1)
  }

  deinit {
    if DispatchQueue.getSpecific(key: Self.mpvQueueSpecificKey) != nil {
      disposeBodyIfNeeded()
    } else {
      mpvQueue.sync { [self] in
        self.disposeBodyIfNeeded()
      }
    }
  }

  /// Tüm libmpv API çağrıları bu kuyrukta yapılmalıdır.
  public func configure(
    enableHardwareAcceleration: Bool = true,
    onVideoSizeChange: NativeVideoOutput.SizeCallback? = nil,
    onFrame: @escaping NativeVideoOutput.FrameCallback
  ) {
    mpvQueue.async { [weak self] in
      guard let self, !self.isDisposed else { return }
      self.updateRenderCallbacks(onVideoSizeChange: onVideoSizeChange, onFrame: onFrame)
      if self.mpv != nil { return }

      let handle = mpv_create()
      guard let handle else {
        Log.error("MPVPlayer", "mpv_create failed")
        return
      }

      // `vo=null` video çıkışını kapatır; OpenGL FBO’ya çizim için `libmpv` VO şart (render.h).
      let voSt = mpv_set_option_string(handle, "vo", "libmpv")
      if voSt < 0 {
        Log.error(
          "MPVPlayer",
          "vo=libmpv başarısız: \(String(cString: mpv_error_string(voSt))) — vo=null deneniyor (FBO genelde siyah kalır)"
        )
        MPVHelpers.checkError(mpv_set_option_string(handle, "vo", "null"))
      }
      let initSt = mpv_initialize(handle)
      if initSt < 0 {
        Log.error(
          "MPVPlayer",
          "mpv_initialize failed: \(String(cString: mpv_error_string(initSt))) — handle yok ediliyor"
        )
        mpv_terminate_destroy(handle)
        return
      }

      self.applyDefaultProperties(handle: handle)
      self.registerPropertyObservers(handle: handle)

      let logReq = mpv_request_log_messages(handle, "warn")
      if logReq < 0 {
        Log.error(
          "MPVPlayer",
          "mpv_request_log_messages: \(String(cString: mpv_error_string(logReq)))"
        )
      }

      self.mpv = handle

      let helper = WakeupHelper(queue: self.mpvQueue, handle: handle)
      helper.player = self
      self.wakeupHelper = helper
      self.wakeupRetained = Unmanaged.passRetained(helper)
      mpv_set_wakeup_callback(
        handle,
        Self.wakeupCallback,
        self.wakeupRetained!.toOpaque()
      )

      self.videoOutput = NativeVideoOutput(
        mpvHandle: handle,
        configuration: VideoOutputConfiguration(
          width: nil,
          height: nil,
          enableHardwareAcceleration: enableHardwareAcceleration
        ),
        onVideoSizeChange: { [weak self] size in
          self?.emitVideoSizeChange(size)
        },
        onFrame: { [weak self] buffer, size, flip in
          self?.emitFrame(buffer, size: size, flipVerticalForOpenGL: flip)
        },
        onPipelineReady: { [weak self] in
          DispatchQueue.main.async {
            guard let self, !self.isDisposed else { return }
            self.isReady = true
          }
        }
      )
      helper.videoOutput = self.videoOutput
      self.videoOutput?.refreshDecodedVideoSizeFromMpv()
      self.publishPlaybackState(handle: handle)
    }
  }

  private func updateRenderCallbacks(
    onVideoSizeChange: NativeVideoOutput.SizeCallback?,
    onFrame: @escaping NativeVideoOutput.FrameCallback
  ) {
    renderCallbackLock.lock()
    onVideoSizeChangeCallback = onVideoSizeChange
    onFrameCallback = onFrame
    renderCallbackLock.unlock()
  }

  private func emitFrame(
    _ buffer: CVPixelBuffer,
    size: CGSize,
    flipVerticalForOpenGL: Bool
  ) {
    renderCallbackLock.lock()
    let cb = onFrameCallback
    renderCallbackLock.unlock()
    cb?(buffer, size, flipVerticalForOpenGL)
  }

  private func emitVideoSizeChange(_ size: CGSize) {
    renderCallbackLock.lock()
    let cb = onVideoSizeChangeCallback
    renderCallbackLock.unlock()
    cb?(size)
  }

  public func load(
    _ url: URL,
    play: Bool = true,
    startSeconds: TimeInterval? = nil,
    liveLowLatency: Bool = false
  ) {
    mpvQueue.async { [weak self] in
      guard let self, !self.isDisposed else { return }
      if self.mpv == nil {
        // `configure` ile `load` aynı tick’te yarışırsa ilk blok `mpv` görmeden dönebilir; bir kez yeniden dene.
        self.mpvQueue.async { [weak self] in
          self?.applyLoadOnMpvQueueIfReady(
            url: url,
            play: play,
            startSeconds: startSeconds,
            liveLowLatency: liveLowLatency
          )
        }
        return
      }
      self.applyLoadOnMpvQueueIfReady(
        url: url,
        play: play,
        startSeconds: startSeconds,
        liveLowLatency: liveLowLatency
      )
    }
  }

  private func applyLoadOnMpvQueueIfReady(
    url: URL,
    play: Bool,
    startSeconds: TimeInterval?,
    liveLowLatency: Bool
  ) {
    guard let handle = mpv, !isDisposed else { return }
    clearPlaybackFailure()
    cancelLoadTimeoutWatchdog()
    playbackPipelinePrimed = false
    DispatchQueue.main.async { [weak self] in
      self?.isPlaybackEstablished = false
    }
    applyStreamBufferPolicy(handle: handle, liveLowLatency: liveLowLatency)
    pendingInitialStartSeconds = startSeconds
    didLogInitialStartPosition = false
    var args: [String] = ["loadfile", url.absoluteString, "replace"]
    if let startSeconds, startSeconds.isFinite, startSeconds > 0 {
      args.append("start=\(startSeconds)")
    }
    MPVPlayerVideoLog.always(
      "Player.start",
      "load startSeconds=\(startSeconds?.description ?? "nil") args=\(args)"
    )
    MPVPlayerVideoLog.armStartupProbe(expectedStartSeconds: startSeconds)
    var cArgs = args.map { strdup($0) }
    defer { cArgs.forEach { free($0) } }
    var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
    argv.append(nil)
    let st = mpv_command(handle, &argv)
    if st < 0 {
      MPVPlayerVideoLog.always(
        "Player.load",
        "mpv_command: \(String(cString: mpv_error_string(st))) (code \(st)) args=\(args)"
      )
    }
    MPVHelpers.checkError(st)
    if play {
      setPause(handle: handle, paused: false)
    }
    videoOutput?.refreshDecodedVideoSizeFromMpv()
    publishPlaybackState(handle: handle)
    scheduleLoadTimeoutWatchdog()
  }

  public func play() {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let eof = MPVHelpers.getFlagProperty(handle, name: "eof-reached") ?? false
      if eof {
        let cmd = "seek 0 absolute"
        cmd.withCString { cstr in
          MPVHelpers.checkError(mpv_command_string(handle, cstr))
        }
      }
      self.setPause(handle: handle, paused: false)
    }
  }

  public func pause() {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      self.setPause(handle: handle, paused: true)
    }
  }

  /// Saniye cinsinden mutlak konum (`seek`).
  public func seek(to seconds: TimeInterval) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let cmd = "seek \(seconds) absolute"
      cmd.withCString { cstr in
        MPVHelpers.checkError(mpv_command_string(handle, cstr))
      }
    }
  }

  /// mpv `volume` (0–100+).
  public func setVolume(_ value: Double) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      var v = value
      let st = mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &v)
      if st < 0 {
        Log.error(
          "MPVPlayer",
          "set volume: \(String(cString: mpv_error_string(st)))"
        )
      }
    }
  }

  /// mpv `speed` (ör. 1.0).
  public func setPlaybackRate(_ value: Double) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      var v = value
      let st = mpv_set_property(handle, "speed", MPV_FORMAT_DOUBLE, &v)
      if st < 0 {
        Log.error(
          "MPVPlayer",
          "set speed: \(String(cString: mpv_error_string(st)))"
        )
      }
    }
  }

  public func dispose() {
    // `weak self` kullanma: blok sıraya alındıktan sonra `MPVPlayer` başka referans kalmadan
    // serbest kalırsa guard başarısız olur ve `mpv_terminate_destroy` hiç çalışmaz (sızıntı + UAF riski).
    mpvQueue.async { [self] in
      self.disposeBodyIfNeeded()
    }
  }

  /// Yalnızca `mpvQueue` üzerinde çağrılmalı (`dispose`, `deinit`).
  private func disposeBodyIfNeeded() {
    if isDisposed { return }
    isDisposed = true
    cancelLoadTimeoutWatchdog()
    playbackPipelinePrimed = false

    if let handle = mpv {
      mpv_set_wakeup_callback(handle, nil, nil)
      for rid in 1 ... 21 {
        mpv_unobserve_property(handle, UInt64(rid))
      }
      // `NativeVideoOutput` aynı anda `Worker` üzerinde `render` çalıştırabilir; `texture` serbest
      // bırakımı işçi kuyruğunda bitmeden `TextureHW`/`TextureSW` deinit edilmemeli.
      videoOutput?.releaseRenderingResourcesSynchronously()
      videoOutput = nil
      wakeupHelper = nil
      if let r = wakeupRetained {
        r.release()
        wakeupRetained = nil
      }
      mpv_command_string(handle, "quit")
      mpv_terminate_destroy(handle)
    }
    mpv = nil

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isReady = false
      self.isPaused = true
      self.position = 0
      self.duration = 0
      self.isBuffering = false
      self.isCompleted = false
      self.volume = 100
      self.playbackRate = 1
      self.videoDisplayWidth = 0
      self.videoDisplayHeight = 0
      self.streamFPS = 0
      self.renderFPS = 0
      self.videoBitrate = 0
      self.droppedFrameCount = 0
      self.delayedFrameCount = 0
      self.cacheBufferingState = 0
      self.cacheDurationSeconds = 0
      self.avSyncSeconds = 0
      self.networkSpeedBps = 0
      self.hwdecCurrent = ""
      self.videoCodecName = ""
      self.mediaTitle = ""
      self.bufferTimelineEnd = 0
      self.playbackFailureMessage = nil
      self.isPlaybackEstablished = false
    }
  }

  fileprivate func onMpvStartFile() {
    playbackPipelinePrimed = false
    DispatchQueue.main.async { [weak self] in
      self?.isPlaybackEstablished = false
    }
  }

  fileprivate func onMpvPlaybackPipelineReady() {
    playbackPipelinePrimed = true
    cancelLoadTimeoutWatchdog()
    // Yükleme aşamasında düşen ffmpeg/http satırları bazen gerçek hatadan önce yanlış pozitif üretir;
    // pipeline hazır olduktan sonra mesajı sıfırlamazsak görüntü gelirken UI kilitli kalır.
    clearPlaybackFailure()
    DispatchQueue.main.async { [weak self] in
      self?.isPlaybackEstablished = true
    }
  }

  fileprivate func onMpvEndFile() {
    cancelLoadTimeoutWatchdog()
    playbackPipelinePrimed = false
    DispatchQueue.main.async { [weak self] in
      self?.isPlaybackEstablished = false
    }
  }

  private func cancelLoadTimeoutWatchdog() {
    loadTimeoutWorkItem?.cancel()
    loadTimeoutWorkItem = nil
  }

  /// Sunucu hiç yanıt vermezse (log da gelmezse) yedek; `network-timeout` ile aynı mertebede.
  private func scheduleLoadTimeoutWatchdog() {
    cancelLoadTimeoutWatchdog()
    let seconds: TimeInterval = 16
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.isDisposed else { return }
      if self.playbackPipelinePrimed { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isDisposed else { return }
        if self.playbackFailureMessage != nil { return }
        self.playbackFailureMessage = L("playback.error.timeout")
      }
    }
    loadTimeoutWorkItem = item
    mpvQueue.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  fileprivate func clearPlaybackFailure() {
    DispatchQueue.main.async { [weak self] in
      self?.playbackFailureMessage = nil
    }
  }

  /// Ağ / demuxer hataları logda `END_FILE`’dan önce düşer; kullanıcıya hemen yansıt.
  fileprivate func handleMpvLogMessage(_ lm: mpv_event_log_message) {
    guard !isDisposed else { return }
    if playbackPipelinePrimed { return }

    guard let levelPtr = lm.level else { return }
    let level = String(cString: levelPtr)
    let prefix = lm.prefix != nil ? String(cString: lm.prefix!) : ""
    let text = lm.text != nil ? String(cString: lm.text!) : ""

    guard Self.shouldSurfaceLogAsPlaybackFailure(level: level, prefix: prefix, text: text) else {
      return
    }

    let line = "\(prefix): \(text)".trimmingCharacters(in: .newlines)
    MPVPlayerVideoLog.always("Player.logFailure", "[\(level)] \(line)")

    cancelLoadTimeoutWatchdog()
    let message = Self.userFacingMessageFromLogLine(level: level, text: text)
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed else { return }
      if self.playbackFailureMessage != nil { return }
      self.playbackFailureMessage = message
    }
  }

  /// `END_FILE` öncesi gelen ffmpeg/lavf/http satırlarını süzer; yanlış pozitifleri azaltır.
  private static func shouldSurfaceLogAsPlaybackFailure(
    level: String,
    prefix: String,
    text: String
  ) -> Bool {
    let p = prefix.lowercased()
    let t = text.lowercased()
    let c = p + " " + t

    if p == "vo" || p == "ao" || p.hasPrefix("vo/") || p.hasPrefix("ao/") {
      return false
    }

    let openPrefixes = [
      "ffmpeg", "lavf", "demuxer", "demux", "stream", "http", "https", "network",
      "libavformat", "read_file", "ffmpeg/http", "ffmpeg/tcp", "ffmpeg/tls",
    ]
    let openHints = [
      "connection refused", "connection timed out", "connection reset", "timed out",
      "network is unreachable", "no route to host", "could not connect", "failed to connect",
      "http error", "server returned", "http status", "http response",
      "403 forbidden", "404 not found", "401 unauthorized", "500 internal", "502 bad gateway",
      "503 service", "tls:", "ssl error", "certificate", "resolve host",
      "name or service not known", "failed to open", "error opening", "invalid data found",
      "i/o error", "input/output error",
      "operation timed out", "host is down", "broken pipe", "errno",
    ]
    // `end of file` / eof satırları çoğu zaman normal kapanış veya demuxer gürültüsüdür; uyarıda asla yüzeye çıkarma.
    let warnOnlyHints = [
      "connection refused", "connection timed out", "connection reset", "timed out",
      "network is unreachable", "no route to host", "could not connect", "failed to connect",
      "http error", "server returned", "http status", "http response",
      "403 forbidden", "404 not found", "401 unauthorized", "500 internal", "502 bad gateway",
      "503 service", "tls:", "ssl error", "certificate", "resolve host",
      "name or service not known", "operation timed out", "host is down", "broken pipe",
    ]

    switch level {
    case "fatal":
      return true
    case "error":
      if openPrefixes.contains(where: { p.contains($0) }) { return true }
      return openHints.contains { c.contains($0) }
    case "warn":
      return warnOnlyHints.contains { c.contains($0) }
    default:
      return false
    }
  }

  private static func userFacingMessageFromLogLine(level: String, text: String) -> String {
    let t = text.lowercased()
    if t.contains("403") || t.contains("forbidden") { return L("playback.error.forbidden") }
    if t.contains("401") || t.contains("unauthorized") { return L("playback.error.unauthorized") }
    if t.contains("404") || t.contains("not found") { return L("playback.error.not_found") }
    if t.contains("timed out") || t.contains("timeout") {
      return L("playback.error.timeout")
    }
    if level == "fatal" { return L("playback.error.failed_to_start") }
    return L("playback.error.cannot_reach")
  }

  fileprivate func handleEndFileEvent(_ end: mpv_event_end_file) {
    guard end.reason == MPV_END_FILE_REASON_ERROR else { return }
    let code = Int(end.error)
    let message = Self.userFacingPlaybackFailureMessage(mpvErrorCode: code)
    MPVPlayerVideoLog.always(
      "Player.endFile",
      "reason=error mpvError=\(code) userMsg=\(message)"
    )
    // Log’dan hızlı HTTP/timeout metni geldiyse koru; codec/VO gibi net mpv kodlarında güncelle.
    let specificMpvCodes = [-16, -17, -18, -14, -15]
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.playbackFailureMessage == nil || specificMpvCodes.contains(code) {
        self.playbackFailureMessage = message
      }
    }
  }

  private static func userFacingPlaybackFailureMessage(mpvErrorCode: Int) -> String {
    // `mpv_error` (client.h), örn. MPV_ERROR_LOADING_FAILED = -13
    switch mpvErrorCode {
    case -13, -17, -20:
      return L("playback.error.cannot_reach")
    case -18:
      return L("playback.error.unsupported")
    case -16:
      return L("playback.error.no_playable_stream")
    case -14, -15:
      return L("playback.error.output_init_failed")
    default:
      return L("playback.error.failed_check_network")
    }
  }

  private func setPause(handle: OpaquePointer, paused: Bool) {
    var flag: CInt = paused ? 1 : 0
    let st = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
    if st < 0 {
      Log.error(
        "MPVPlayer",
        "pause property: \(String(cString: mpv_error_string(st)))"
      )
    }
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed else { return }
      self.isPaused = paused
    }
  }

  /// `mpv_observe_property` + `PROPERTY_CHANGE` ile durum güncellemesi.
  private func registerPropertyObservers(handle: OpaquePointer) {
    let observations: [(UInt64, String, mpv_format)] = [
      (1, "video-params", MPV_FORMAT_NODE),
      (2, "video-out-params", MPV_FORMAT_NODE),
      (3, "time-pos", MPV_FORMAT_DOUBLE),
      (4, "duration", MPV_FORMAT_DOUBLE),
      (5, "pause", MPV_FORMAT_FLAG),
      (6, "eof-reached", MPV_FORMAT_FLAG),
      (7, "paused-for-cache", MPV_FORMAT_FLAG),
      (8, "volume", MPV_FORMAT_DOUBLE),
      (9, "speed", MPV_FORMAT_DOUBLE),
      (10, "media-title", MPV_FORMAT_STRING),
      (11, "container-fps", MPV_FORMAT_DOUBLE),
      (12, "estimated-vf-fps", MPV_FORMAT_DOUBLE),
      (13, "video-bitrate", MPV_FORMAT_DOUBLE),
      (14, "vo-drop-frame-count", MPV_FORMAT_INT64),
      (15, "vo-delayed-frame-count", MPV_FORMAT_INT64),
      (16, "cache-buffering-state", MPV_FORMAT_DOUBLE),
      (17, "demuxer-cache-duration", MPV_FORMAT_DOUBLE),
      (18, "avsync", MPV_FORMAT_DOUBLE),
      (19, "cache-speed", MPV_FORMAT_DOUBLE),
      (20, "hwdec-current", MPV_FORMAT_STRING),
      (21, "video-codec", MPV_FORMAT_STRING),
    ]
    for (replyId, name, fmt) in observations {
      MPVHelpers.observePropertyIfAvailable(handle, replyId: replyId, name: name, format: fmt)
    }
  }

  fileprivate func handleObservedPropertyChange(replyUserdata: UInt64) {
    guard let handle = mpv, !isDisposed else { return }
    if replyUserdata == 1 || replyUserdata == 2 {
      videoOutput?.refreshDecodedVideoSizeFromMpv()
    }
    if replyUserdata == 3 {
      publishPositionThrottled(handle: handle)
    } else {
      publishPlaybackState(handle: handle)
    }
  }

  fileprivate func publishPlaybackStateFromMpvQueue() {
    guard let handle = mpv, !isDisposed else { return }
    publishPlaybackState(handle: handle)
  }

  private func publishPositionThrottled(handle: OpaquePointer) {
    let now = CFAbsoluteTimeGetCurrent()
    if now - lastPositionPublishTime < 0.12 { return }
    lastPositionPublishTime = now
    let pos = MPVHelpers.getDoubleProperty(handle, name: "time-pos") ?? 0
    maybeLogInitialStartPosition(currentPos: pos)
    let cacheEnd = MPVHelpers.getDoubleProperty(handle, name: "demuxer-cache-time") ?? 0
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed else { return }
      if self.position != pos { self.position = pos }
      if self.bufferTimelineEnd != cacheEnd { self.bufferTimelineEnd = cacheEnd }
    }
  }

  private func maybeLogInitialStartPosition(currentPos: Double) {
    guard !didLogInitialStartPosition else { return }
    didLogInitialStartPosition = true
    let expected = pendingInitialStartSeconds
    pendingInitialStartSeconds = nil
    MPVPlayerVideoLog.always(
      "Player.start",
      "first time-pos=\(currentPos)s expectedStart=\(expected?.description ?? "nil")"
    )
  }

  private func publishPlaybackState(handle: OpaquePointer) {
    let pos = MPVHelpers.getDoubleProperty(handle, name: "time-pos") ?? 0
    let dur = MPVHelpers.getDoubleProperty(handle, name: "duration") ?? 0
    let paused = MPVHelpers.getFlagProperty(handle, name: "pause") ?? true
    let eof = MPVHelpers.getFlagProperty(handle, name: "eof-reached") ?? false
    let buffering = MPVHelpers.getFlagProperty(handle, name: "paused-for-cache") ?? false
    let vol = MPVHelpers.getDoubleProperty(handle, name: "volume") ?? 100
    let spd = MPVHelpers.getDoubleProperty(handle, name: "speed") ?? 1
    let title = MPVHelpers.getStringProperty(handle, name: "media-title") ?? ""
    let vp = MPVHelpers.getVideoParamsDisplayDimensions(handle)
    let dw = vp.dw > 0 ? vp.dw : vp.w
    let dh = vp.dh > 0 ? vp.dh : vp.h
    let cacheEnd = MPVHelpers.getDoubleProperty(handle, name: "demuxer-cache-time") ?? 0
    let seekable = MPVHelpers.getFlagProperty(handle, name: "seekable") ?? false
    let containerFPS = MPVHelpers.getDoubleProperty(handle, name: "container-fps") ?? 0
    let estimatedVfFPS = MPVHelpers.getDoubleProperty(handle, name: "estimated-vf-fps") ?? 0
    let videoBitrate = MPVHelpers.getDoubleProperty(handle, name: "video-bitrate") ?? 0
    let dropped = MPVHelpers.getInt64Property(handle, name: "vo-drop-frame-count") ?? 0
    let delayed = MPVHelpers.getInt64Property(handle, name: "vo-delayed-frame-count") ?? 0
    let cacheBuffering = MPVHelpers.getDoubleProperty(handle, name: "cache-buffering-state") ?? 0
    let cacheDuration = MPVHelpers.getDoubleProperty(handle, name: "demuxer-cache-duration") ?? 0
    let avSync = MPVHelpers.getDoubleProperty(handle, name: "avsync") ?? 0
    let cacheSpeed = MPVHelpers.getDoubleProperty(handle, name: "cache-speed") ?? 0
    let hwdecCurrent = MPVHelpers.getStringProperty(handle, name: "hwdec-current") ?? ""
    let videoCodec = MPVHelpers.getStringProperty(handle, name: "video-codec") ?? ""

    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed else { return }
      // Her @Published atama SwiftUI invalidation tetikler — aynı değerleri tekrar atamayarak
      // `VideoPlayerController` ve `PlayerView` gereksiz render çevrimlerinden korunur.
      if self.position != pos { self.position = pos }
      if self.duration != dur { self.duration = dur }
      if self.isPaused != paused { self.isPaused = paused }
      if self.isCompleted != eof { self.isCompleted = eof }
      if self.isBuffering != buffering { self.isBuffering = buffering }
      if self.volume != vol { self.volume = vol }
      if self.playbackRate != spd { self.playbackRate = spd }
      if self.mediaTitle != title { self.mediaTitle = title }
      let dwInt = Int(dw)
      let dhInt = Int(dh)
      if self.videoDisplayWidth != dwInt { self.videoDisplayWidth = dwInt }
      if self.videoDisplayHeight != dhInt { self.videoDisplayHeight = dhInt }
      if self.streamFPS != containerFPS { self.streamFPS = containerFPS }
      if self.renderFPS != estimatedVfFPS { self.renderFPS = estimatedVfFPS }
      if self.videoBitrate != videoBitrate { self.videoBitrate = videoBitrate }
      if self.droppedFrameCount != dropped { self.droppedFrameCount = dropped }
      if self.delayedFrameCount != delayed { self.delayedFrameCount = delayed }
      if self.cacheBufferingState != cacheBuffering { self.cacheBufferingState = cacheBuffering }
      if self.cacheDurationSeconds != cacheDuration { self.cacheDurationSeconds = cacheDuration }
      if self.avSyncSeconds != avSync { self.avSyncSeconds = avSync }
      if self.networkSpeedBps != cacheSpeed { self.networkSpeedBps = cacheSpeed }
      if self.hwdecCurrent != hwdecCurrent { self.hwdecCurrent = hwdecCurrent }
      if self.videoCodecName != videoCodec { self.videoCodecName = videoCodec }
      if self.bufferTimelineEnd != cacheEnd { self.bufferTimelineEnd = cacheEnd }
      if self.isSeekable != seekable { self.isSeekable = seekable }
    }
  }

  /// Mobil profil: telefon GPU'sunda ucuz bilinear scale, audio-sync, hızlı seek.
  /// Masaüstü tipi spline36/mitchell/display-resample telefon ekranında fark edilmez,
  /// ancak GPU yükünü 2-3x artırarak termal kısma ve frame drop'a yol açar.
  private func applyDefaultProperties(handle: OpaquePointer) {
    var props: [(String, String)] = [
      ("idle", "yes"),
      ("pause", "yes"),
      ("keep-open", "yes"),
      ("audio-display", "no"),
      // Log tabanlı hata + `END_FILE` ile uyumlu makul süre.
      ("network-timeout", "14"),
      // Mobil: ucuz bilinear yeterli; retina ekranda spline36'dan ayırt edilemez.
      ("scale", "bilinear"),
      ("dscale", "bilinear"),
      ("cache", "yes"),
      ("cache-on-disk", "yes"),
      // `default`: keyframe seek (hızlı); `hr-seek=yes` VOD'da her scrub'da uzun gecikme yaratıyor.
      ("hr-seek", "default"),
      ("hr-seek-framedrop", "yes"),
      // HDR akışlarda renk/parlaklık daha doğal (ucuz).
      ("hdr-compute-peak", "yes"),
      ("tone-mapping", "bt.2390"),
      ("vid", "auto"),
      // `audio`: video frameleri ses saatine senkron; `display-resample` GL yolunda pahalı
      // ve telefon 60Hz ekranda kayda değer katkı sağlamıyor.
      ("video-sync", "audio"),
      ("interpolation", "no"),
      ("video-timing-offset", "0"),
      ("osd-level", "0"),
      ("demuxer-max-bytes", "\(32 * 1024 * 1024)"),
      ("demuxer-max-back-bytes", "\(32 * 1024 * 1024)"),
    ]
    #if targetEnvironment(simulator)
    props.append(("hwdec", "no"))
    #else
    props.append(("hwdec", "videotoolbox"))
    #endif
    for (k, v) in props {
      MPVHelpers.setPropertyStringIfSupported(handle, name: k, value: v)
    }
  }

  /// Her `loadfile` öncesi: canlıda ileri tamponu kısaltır (maç vb. gecikmesin); VOD’da önceki geniş ayarlara döner.
  private func applyStreamBufferPolicy(handle: OpaquePointer, liveLowLatency: Bool) {
    let mb32 = 32 * 1024 * 1024
    let mb4 = 4 * 1024 * 1024
    let kb512 = 512 * 1024
    if liveLowLatency {
      MPVHelpers.setPropertyStringIfSupported(handle, name: "cache", value: "yes")
      MPVHelpers.setPropertyStringIfSupported(handle, name: "cache-on-disk", value: "no")
      // Süre ve bayt üst sınırı birlikte: hangisi önce dolarsa (HLS segment süresi sunucuya bağlı).
      MPVHelpers.setPropertyStringIfSupported(handle, name: "cache-secs", value: "5")
      MPVHelpers.setPropertyStringIfSupported(handle, name: "demuxer-readahead-secs", value: "2")
      MPVHelpers.setPropertyStringIfSupported(
        handle, name: "demuxer-max-bytes", value: "\(mb4)"
      )
      MPVHelpers.setPropertyStringIfSupported(
        handle, name: "demuxer-max-back-bytes", value: "\(kb512)"
      )
    } else {
      MPVHelpers.setPropertyStringIfSupported(handle, name: "cache", value: "yes")
      MPVHelpers.setPropertyStringIfSupported(handle, name: "cache-on-disk", value: "yes")
      // 36000s (10 saat) anlamsızdı: `demuxer-max-bytes` (32MB) zaten pratikte süreyi
      // sınırlıyor. 300s (5dk) telefon için makul bir kapak.
      MPVHelpers.setPropertyStringIfSupported(handle, name: "cache-secs", value: "300")
      MPVHelpers.setPropertyStringIfSupported(handle, name: "demuxer-readahead-secs", value: "10")
      MPVHelpers.setPropertyStringIfSupported(
        handle, name: "demuxer-max-bytes", value: "\(mb32)"
      )
      MPVHelpers.setPropertyStringIfSupported(
        handle, name: "demuxer-max-back-bytes", value: "\(mb32)"
      )
    }
  }
}

// MARK: - IPTV / PlayerView köprüsü (aynı dosya: `mpv`/`mpvQueue` erişimi)

extension MPVPlayer {

  func seekToFraction(_ pos: Float) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let dur = MPVHelpers.getDoubleProperty(handle, name: "duration") ?? 0
      guard dur > 0, pos.isFinite else { return }
      let seconds = Double(min(max(pos, 0), 1)) * dur
      let cmd = "seek \(seconds) absolute"
      cmd.withCString { cstr in
        let st = mpv_command_string(handle, cstr)
        if st < 0 {
          Log.error("MPVPlayer", "seekToFraction: \(String(cString: mpv_error_string(st)))")
        }
      }
    }
  }

  func jumpRelative(seconds: Int) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let cmd = "seek \(seconds) relative"
      cmd.withCString { cstr in
        let st = mpv_command_string(handle, cstr)
        if st < 0 {
          Log.error("MPVPlayer", "jumpRelative: \(String(cString: mpv_error_string(st)))")
        }
      }
    }
  }

  func reloadTrackList(
    completion: @escaping (
      _ video: [TrackMenuOption],
      _ audio: [TrackMenuOption],
      _ subs: [TrackMenuOption],
      _ videoId: Int,
      _ audioId: Int,
      _ subtitleId: Int
    ) -> Void
  ) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else {
        DispatchQueue.main.async {
          completion(
            [],
            [],
            [TrackMenuOption(id: -1, title: L("player.subtitle_off"))],
            -1,
            -1,
            -1
          )
        }
        return
      }

      var video: [TrackMenuOption] = []
      var audio: [TrackMenuOption] = []
      var subs: [TrackMenuOption] = [TrackMenuOption(id: -1, title: L("player.subtitle_off"))]
      let count = MPVHelpers.getInt64Property(handle, name: "track-list/count") ?? 0

      for i in 0 ..< count {
        let prefix = "track-list/\(i)"
        guard let typeStr = MPVHelpers.getStringProperty(handle, name: "\(prefix)/type") else { continue }
        let trackId = MPVHelpers.getInt64Property(handle, name: "\(prefix)/id") ?? 0
        if let opt = Self.buildTrackMenuOption(handle: handle, prefix: prefix, trackId: Int(trackId), typeStr: typeStr) {
          switch typeStr {
          case "video": video.append(opt)
          case "audio": audio.append(opt)
          case "sub": subs.append(opt)
          default: break
          }
        }
      }

      let vidVal = MPVHelpers.getInt64Property(handle, name: "vid") ?? -1
      let aidVal = MPVHelpers.getInt64Property(handle, name: "aid") ?? -1
      let sidVal = MPVHelpers.getInt64Property(handle, name: "sid") ?? -1

      DispatchQueue.main.async {
        completion(video, audio, subs, Int(vidVal), Int(aidVal), Int(sidVal))
      }
    }
  }

  private static func buildTrackMenuOption(
    handle: OpaquePointer,
    prefix: String,
    trackId: Int,
    typeStr: String
  ) -> TrackMenuOption? {
    let rawTitle = MPVHelpers.getStringProperty(handle, name: "\(prefix)/title")
    let rawLang = MPVHelpers.getStringProperty(handle, name: "\(prefix)/lang")
    let codec = MPVHelpers.getStringProperty(handle, name: "\(prefix)/codec") ?? ""
    let isDefault = MPVHelpers.getFlagProperty(handle, name: "\(prefix)/default") ?? false
    let isForced = MPVHelpers.getFlagProperty(handle, name: "\(prefix)/forced") ?? false
    let isImage = MPVHelpers.getFlagProperty(handle, name: "\(prefix)/image") ?? false
    let isExternal = MPVHelpers.getFlagProperty(handle, name: "\(prefix)/external") ?? false
    let demuxW = MPVHelpers.getInt64Property(handle, name: "\(prefix)/demux-w") ?? 0
    let demuxH = MPVHelpers.getInt64Property(handle, name: "\(prefix)/demux-h") ?? 0
    let demuxFps = MPVHelpers.getDoubleProperty(handle, name: "\(prefix)/demux-fps") ?? 0
    let channels = MPVHelpers.getInt64Property(handle, name: "\(prefix)/audio-channels") ?? 0

    let titleTrim = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let langTrim = rawLang?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let mainTitle: String
    if !titleTrim.isEmpty {
      mainTitle = titleTrim
    } else if !langTrim.isEmpty {
      mainTitle = langTrim.uppercased()
    } else {
      mainTitle = "Parça \(trackId)"
    }

    var parts: [String] = []
    if !codec.isEmpty { parts.append(codec) }
    if demuxW > 0, demuxH > 0 {
      parts.append("\(demuxW)×\(demuxH)")
    }
    if demuxFps > 0.05 {
      parts.append(String(format: "%.2f fps", demuxFps))
    }
    if typeStr == "audio", channels > 0 {
      parts.append("\(channels) kanal")
    }
    if isImage { parts.append("Kapak / resim") }
    if isDefault { parts.append("Varsayılan") }
    if isForced { parts.append("Zorunlu") }
    if !langTrim.isEmpty, titleTrim.isEmpty || titleTrim.lowercased() != langTrim.lowercased() {
      parts.append(langTrim.uppercased())
    }

    let detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
    let langCode = langTrim.isEmpty ? nil : langTrim
    return TrackMenuOption(
      id: trackId, title: mainTitle, detail: detail, langCode: langCode, isExternal: isExternal
    )
  }

  func selectVideoTrack(id: Int) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      MPVHelpers.setPropertyStringIfSupported(handle, name: "vid", value: "\(id)")
    }
  }

  func selectAudioTrack(id: Int) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      MPVHelpers.setPropertyStringIfSupported(handle, name: "aid", value: "\(id)")
    }
  }

  func selectSubtitleTrack(id: Int) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let v = id < 0 ? "no" : "\(id)"
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sid", value: v)
    }
  }

  /// Adds an external subtitle file to the track list; with `select` it becomes active immediately.
  func addExternalSubtitle(filePath: String, title: String, select: Bool) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let args: [String] = ["sub-add", filePath, select ? "select" : "auto", title]
      var cArgs = args.map { strdup($0) }
      defer { cArgs.forEach { free($0) } }
      var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
      argv.append(nil)
      let st = mpv_command(handle, &argv)
      if st < 0 {
        Log.error("MPVPlayer", "sub-add: \(String(cString: mpv_error_string(st))) (\(filePath))")
      }
    }
  }

  /// Only external tracks (added via sub-add) can be removed; mpv returns an error otherwise.
  func removeExternalSubtitle(id: Int) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      let cmd = "sub-remove \(id)"
      cmd.withCString { cstr in
        let st = mpv_command_string(handle, cstr)
        if st < 0 {
          Log.error("MPVPlayer", "sub-remove: \(String(cString: mpv_error_string(st)))")
        }
      }
    }
  }

  func setSubDelay(seconds: Double) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-delay", value: String(seconds))
    }
  }

  func applySubtitleAppearanceFromSettings(_ settings: SubtitleAppearanceSettings) {
    mpvQueue.async { [weak self] in
      guard let self, let handle = self.mpv, !self.isDisposed else { return }

      // ASS yeniden yazımını etkin tut: libmpv bu ayarları stil override ile uyguluyor.
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-ass-override", value: "force")

      var size = Double(settings.fontSize)
      _ = mpv_set_property(handle, "sub-font-size", MPV_FORMAT_DOUBLE, &size)
      var scaleOne = 1.0
      _ = mpv_set_property(handle, "sub-scale", MPV_FORMAT_DOUBLE, &scaleOne)

      // libmpv `sub-line-spacing` satır aralığını piksel olarak alır; yüzdeyi yaklaşık piksele çevir.
      var lineSpace = Double(settings.fontSize) * max(0, settings.lineHeight - 1.0)
      _ = mpv_set_property(handle, "sub-line-spacing", MPV_FORMAT_DOUBLE, &lineSpace)

      var spacing = settings.letterSpacing
      _ = mpv_set_property(handle, "sub-spacing", MPV_FORMAT_DOUBLE, &spacing)

      // libass'ta "kelime aralığı" yok; yaklaşık olarak harf aralığına katkı ekliyoruz.
      if settings.wordSpacing > 0.01 {
        var boosted = settings.letterSpacing + settings.wordSpacing * 0.15
        _ = mpv_set_property(handle, "sub-spacing", MPV_FORMAT_DOUBLE, &boosted)
      }

      // Kenar boşluğu: libass alt/sol kenardan uzaklık. "İç boşluk" isteğini kenar boşluğuna eşliyoruz.
      var marginX = Double(settings.padding)
      _ = mpv_set_property(handle, "sub-margin-x", MPV_FORMAT_DOUBLE, &marginX)
      var marginY = Double(settings.padding + max(0, -settings.verticalOffset))
      _ = mpv_set_property(handle, "sub-margin-y", MPV_FORMAT_DOUBLE, &marginY)

      // Metin rengi.
      let tr = (settings.textColorHex6 >> 16) & 0xFF
      let tg = (settings.textColorHex6 >> 8) & 0xFF
      let tb = settings.textColorHex6 & 0xFF
      let textColorStr = String(format: "#%02X%02X%02X", tr, tg, tb)
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-color", value: textColorStr)

      // Kalınlık: libass'ın Bold biti yalnız bold/no-bold ayırır. Gerçek ince/orta/heavy için
      // `sub-font`'u iOS sistem yazı tipinin weight varyantına yönlendiriyoruz; CoreText fontselect
      // bu postscript adını bulursa uygun weight'te render eder.
      MPVHelpers.setPropertyStringIfSupported(
        handle, name: "sub-font", value: settings.fontWeight.iosPostscriptName
      )
      let bold = settings.fontWeight == .bold || settings.fontWeight == .extraBold
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-bold", value: bold ? "yes" : "no")

      // İtalik.
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-italic", value: settings.italic ? "yes" : "no")

      // Hizalama: justify → center fallback.
      let alignX: String
      switch settings.textAlignment {
      case .left: alignX = "left"
      case .right: alignX = "right"
      case .center, .justify: alignX = "center"
      }
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-align-x", value: alignX)

      // Kenar kalınlığı + kenar rengi.
      var borderSize = settings.outlineSize
      _ = mpv_set_property(handle, "sub-border-size", MPV_FORMAT_DOUBLE, &borderSize)
      let br2 = (settings.outlineColorHex6 >> 16) & 0xFF
      let bg2 = (settings.outlineColorHex6 >> 8) & 0xFF
      let bb2 = settings.outlineColorHex6 & 0xFF
      let borderColorStr = String(format: "#%02X%02X%02X", br2, bg2, bb2)
      MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-border-color", value: borderColorStr)

      // Arka plan kutusu.
      if settings.backgroundEnabled {
        let alphaByte = UInt32((max(0, min(1, settings.backgroundOpacity))) * 255)
        let br3 = (settings.backgroundColorHex6 >> 16) & 0xFF
        let bg3 = (settings.backgroundColorHex6 >> 8) & 0xFF
        let bb3 = settings.backgroundColorHex6 & 0xFF
        let backStr = String(format: "#%02X%02X%02X%02X", alphaByte, br3, bg3, bb3)
        MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-back-color", value: backStr)
        MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-border-style", value: "opaque-box")
      } else {
        MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-back-color", value: "#00000000")
        let style = settings.outlineSize > 0 ? "outline-and-shadow" : "none"
        MPVHelpers.setPropertyStringIfSupported(handle, name: "sub-border-style", value: style)
      }
    }
  }

}
