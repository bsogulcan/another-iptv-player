import Foundation

/// Bir AirPlay remux oturumunun yaşam döngüsü: temp dizin + FFmpeg remux yazıcısı +
/// yerel HTTP sunucusu. `localPlaylistURL` hazır olunca AVPlayer'a verilir; Apple TV
/// segmentleri telefonun LAN adresinden çeker.
final class AirPlayRemuxSession {
  let sourceURL: URL
  /// Remux'un kaynak içinde başladığı saniye — oynatma konumu = offset + yerel konum.
  let startOffsetSeconds: TimeInterval
  let isLive: Bool
  /// VOD'da oynatma başlamadan biriktirilecek içerik (sn). İlk başlatmada yüksek
  /// (tekleme koruması), seek yenilemesinde düşük (kullanıcı aktif bekliyor).
  let minimumBufferSeconds: Double

  private let directory: URL
  private let sessionPathComponent: String
  private let writer: RemuxHLSWriter
  private let server: LocalHTTPServer
  private(set) var localPlaylistURL: URL?

  var onError: ((Error) -> Void)?

  /// VOD only: called once, on main, when the volume is running low on free space
  /// and this session holds enough for a rebuild to release something (see
  /// `storageRunningLow`). A VOD cast keeps every segment, so the directory grows
  /// with watched time; the owner rebuilds the session at the current position,
  /// which releases this directory. With enough free space it is never called.
  var onStorageBudgetExceeded: (() -> Void)?

  /// When the receiver (any peer that is not this phone) last requested something
  /// from this session; nil = it never did. Thread-safe.
  var lastReceiverFetchAt: Date? {
    server.lastReceiverFetch(session: sessionPathComponent)
  }

  /// One line for the log about who fetched from this session and what they got:
  /// receiver requests served and refused, when the receiver last asked, and the
  /// phone's own requests. Counts and an age only, so no address or URL is in it.
  /// After the fact it tells "the TV never connected" from "the TV got 404s" from
  /// "the TV fetched and then stopped". Thread-safe.
  var receiverFetchSummary: String {
    server.fetchCounters(session: sessionPathComponent)?.summary(now: Date())
      ?? "no request record for this session"
  }

  /// Main-thread state of the storage budget watch and of `stop()`.
  private var isStopped = false
  private var storageBudgetReported = false
  /// The writer ran out of disk space: `stop()` then deletes the directory at once.
  private var endedOutOfSpace = false

  /// Domain and codes of the NSErrors `start` reports, so callers can tell the
  /// failures apart without matching literals.
  static let errorDomain = "AirPlayRemux"
  enum ErrorCode: Int {
    case noLANAddress = 1
    case playlistTimeout = 2
    case localServerUnreachable = 3
    /// The phone has a LAN address but the local HTTP listener has no port. Kept
    /// apart from `noLANAddress`: that one tells the user to connect to Wi-Fi.
    case listenerNotReady = 4
  }

  /// `info` is merged into the error's userInfo next to the message. Callers tell
  /// the failures apart by domain and code only; the rest is for the log.
  private static func makeError(
    _ code: ErrorCode, _ message: String, info: [String: Any] = [:]
  ) -> NSError {
    var userInfo = info
    userInfo[NSLocalizedDescriptionKey] = message
    return NSError(domain: errorDomain, code: code.rawValue, userInfo: userInfo)
  }

  /// Where the writer stood when the wait for the playlist was given up. A dead
  /// source (no packet), a stalled one (packets, then silence) and a slow one
  /// (segments closing until the cap) all end in the same error code; this is what
  /// tells them apart in a log.
  nonisolated struct StartWaitProgress: Equatable {
    /// Packets the writer had read from the source (0 = it never got past the open).
    let packetsRead: Int
    /// Segments listed in the playlist (0 also when no playlist was written yet).
    let closedSegments: Int
    /// The writer's stall clock: seconds since its last packet.
    let stalledSeconds: TimeInterval
    /// Seconds since `start` was called.
    let elapsedSeconds: TimeInterval
  }

  /// userInfo keys of the playlist-timeout error, one per `StartWaitProgress` field.
  static let packetsReadErrorKey = "packetsRead"
  static let closedSegmentsErrorKey = "closedSegments"
  static let stalledSecondsErrorKey = "stalledSeconds"
  static let elapsedSecondsErrorKey = "elapsedSeconds"

  /// The playlist-timeout error with the writer's progress in its message and its
  /// userInfo. Pure function.
  static func playlistTimeoutError(_ progress: StartWaitProgress) -> NSError {
    makeError(
      .playlistTimeout,
      "Remux playlist not produced in time (packets=\(progress.packetsRead), "
        + "segments=\(progress.closedSegments), "
        + "stalled=\(Int(progress.stalledSeconds))s, elapsed=\(Int(progress.elapsedSeconds))s)",
      info: [
        packetsReadErrorKey: progress.packetsRead,
        closedSegmentsErrorKey: progress.closedSegments,
        stalledSecondsErrorKey: progress.stalledSeconds,
        elapsedSecondsErrorKey: progress.elapsedSeconds,
      ]
    )
  }

  /// Segments a media playlist lists (its `#EXTINF` lines). Pure function.
  static func closedSegmentCount(inPlaylist content: String) -> Int {
    content.split(separator: "\n").filter { $0.hasPrefix("#EXTINF:") }.count
  }

  enum PreflightFailure {
    case noLANAddress
    case serverUnavailable
  }

  /// The two local checks `start` makes before anything else, callable on their own
  /// so a cast that cannot work is refused before phone playback is torn down.
  /// Synchronous and local only: the source is never contacted.
  static func preflight() -> PreflightFailure? {
    // The address first: with Wi-Fi off it is the cause worth reporting, and it
    // spares the listener start-up wait.
    guard LocalHTTPServer.lanIPv4Address() != nil else { return .noLANAddress }
    let server = LocalHTTPServer.shared
    do {
      try server.start()
    } catch {
      return .serverUnavailable
    }
    return server.port > 0 ? nil : .serverUnavailable
  }

  /// Bir önceki oturum: yeni writer, bunun kaynak bağlantısı kapanana dek beklemeli
  /// (bağlantı-limitli panelde çift açılış çakışması). start tamamlanınca serbest kalır.
  private var previousToDrain: AirPlayRemuxSession?

  /// Bu oturumun kaynak bağlantısı fiilen kapandı mı (writer döngüsü çözüldü)?
  var isSourceClosed: Bool { writer.isClosed }
  var hasSubtitleRendition: Bool { writer.clientPlaylistFileName == "master.m3u8" }

  init(
    sourceURL: URL,
    startOffsetSeconds: TimeInterval,
    isLive: Bool,
    userAgent: String?,
    minimumBufferSeconds: Double = 12,
    openDelaySeconds: Double = 0,
    previousToDrain: AirPlayRemuxSession? = nil,
    subtitleFileURL: URL? = nil,
    subtitleName: String? = nil,
    subtitleLanguage: String? = nil,
    audioStreamIndex: Int? = nil,
    subtitleStreamIndex: Int? = nil,
    subtitleDelaySeconds: Double = 0,
    applyTrackPreferences: Bool = false
  ) throws {
    self.sourceURL = sourceURL
    self.startOffsetSeconds = isLive ? 0 : startOffsetSeconds
    self.isLive = isLive
    self.minimumBufferSeconds = minimumBufferSeconds
    self.previousToDrain = previousToDrain
    // Paylaşılan sunucunun kökü altında oturuma özel alt dizin: zapping'de listener ve
    // yerel-ağ doğrulaması yeniden kurulmaz.
    server = LocalHTTPServer.shared
    sessionPathComponent = "s\(UUID().uuidString.prefix(8))"
    directory = server.directory.appendingPathComponent(sessionPathComponent, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // `self` strong tutar; closure zayıf yakalar → döngü yok, ama beklerken canlı kalır.
    let readyToOpen: (() -> Bool)? = previousToDrain.map { prev in
      { [weak prev] in prev?.isSourceClosed ?? true }
    }
    writer = RemuxHLSWriter(
      sourceURL: sourceURL,
      outputDirectory: directory,
      startSeconds: self.startOffsetSeconds,
      isLive: isLive,
      userAgent: userAgent,
      openDelaySeconds: openDelaySeconds,
      readyToOpen: readyToOpen,
      subtitleFileURL: subtitleFileURL,
      subtitleName: subtitleName,
      subtitleLanguage: subtitleLanguage,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      subtitleDelaySeconds: subtitleDelaySeconds,
      applyTrackPreferences: applyTrackPreferences
    )
    server.beginTrackingReceiverFetches(session: sessionPathComponent)
  }

  /// Güvenlik ağı: referans stop() çağrılmadan düşerse (state machine hatası vb.)
  /// başıboş writer'ın panel bağlantısını sonsuza dek tutması engellenir.
  deinit {
    writer.cancel()
    server.endTrackingReceiverFetches(session: sessionPathComponent)
  }

  /// Sunucu + remux'u başlatır; playlist ilk segmentiyle diske düşünce completion çağrılır.
  /// Playlist ~10 sn içinde oluşmazsa hata döner (kaynak açılamadı vb.).
  func start(completion: @escaping (Result<URL, Error>) -> Void) {
    do {
      try server.start()
    } catch {
      completion(.failure(error))
      return
    }
    guard let ip = LocalHTTPServer.lanIPv4Address() else {
      completion(
        .failure(Self.makeError(.noLANAddress, "No LAN IPv4 address (Wi-Fi off?)")))
      return
    }
    // Its own code: paths that skip `preflight()` (zap, rebuild, seek refresh, retry)
    // used to report a listener without a port as "no LAN address", and the user was
    // told to connect to Wi-Fi. As above, the writer has not been started.
    guard server.port > 0 else {
      completion(
        .failure(Self.makeError(.listenerNotReady, "Local HTTP listener not ready")))
      return
    }
    let playlistPath = writer.playlistURL.path
    // Playlist üretimi ve erişilebilirlik doğrulaması PARALEL koşar; ikisi de bitince
    // tamamlanır. Canlıda ilk segment gerçek zamanlı dolduğundan süre payı geniş tutulur.
    // VOD'da tampon birikmesi beklenir (aşağıda) — 4K'da indirme ~gerçek zamanlı olabilir.
    // The give-up follows the writer's read progress instead of a fixed 25 s (see
    // startWaitExpired): a long-GOP channel that is still delivering is not a failure.
    let startedAt = ProcessInfo.processInfo.systemUptime
    var playlistReady = false
    var serverVerified = false
    var finished = false
    let finishIfReady = {
      guard playlistReady, serverVerified, !finished else { return }
      finished = true
      self.previousToDrain = nil  // writer artık açtı; drenaj referansını bırak
      // If a subtitle rendition was requested, the writer has upgraded the client
      // playlist to the subtitle master by now (written on the first segment; readiness
      // needs many more). Otherwise this is still the raw video playlist.
      // The port is read here, not at the top: the listener check below may have
      // had to replace a dead listener, and the replacement can sit on another port.
      let baseURL = "http://\(ip):\(self.server.port)/\(self.sessionPathComponent)"
      let localURL = URL(string: "\(baseURL)/\(self.writer.clientPlaylistFileName)")!
      self.localPlaylistURL = localURL
      completion(.success(localURL))
    }
    let failOnce = { (error: Error) in
      guard !finished else { return }
      finished = true
      self.previousToDrain = nil
      self.stop()
      completion(.failure(error))
    }
    // Writer errors during the start window fail the start immediately (a source
    // with incompatible codecs must not sit out the full playlist deadline);
    // errors after a successful start are forwarded to `onError`.
    writer.onError = { [weak self] (error: Error) in
      DispatchQueue.main.async {
        guard let self else { return }
        // Recorded before the owner hears of it: its reaction is `stop()`.
        if Self.isOutOfSpace(error) { self.endedOutOfSpace = true }
        if finished {
          self.onError?(error)
        } else {
          failOnce(error)
        }
      }
    }
    writer.start()
    startStorageBudgetWatch()
    waitForPlaylist(path: playlistPath, startedAt: startedAt) { gaveUpAt in
      if let gaveUpAt {
        failOnce(Self.playlistTimeoutError(gaveUpAt))
      } else {
        playlistReady = true
        finishIfReady()
      }
    }
    // /ping answers 200 at once, independent of the playlist. Two local checks:
    // 1. The listener itself, over loopback, with a few quick tries. This is the
    //    check that can really fail: a listener that iOS defuncted while the app was
    //    suspended may still look ready. It is replaced once and probed again, and
    //    a dead local server is reported in seconds.
    // 2. The phone's own LAN address, the URL the phone-side AVPlayer loads. Apple
    //    documents that on iOS 18+ neither a request to one's own address nor the
    //    receiver's inbound fetch needs the Local Network permission, so this is
    //    expected to pass on the first try; the earlier theory that the first
    //    request waits on the permission dialog is not disproven on a device, so
    //    the retry stays, bounded by the first-packet deadline.
    // Neither says anything about the receiver; see `lastReceiverFetchAt`.
    let verifyLANAddress = {
      self.verifyReachable(
        url: URL(string: "http://\(ip):\(self.server.port)/ping")!,
        startedAt: startedAt
      ) { reachable, probeError in
        if reachable {
          serverVerified = true
          finishIfReady()
        } else {
          var info: [String: Any] = [:]
          if let probeError { info[NSUnderlyingErrorKey] = probeError }
          failOnce(
            Self.makeError(
              .localServerUnreachable,
              "Local server not reachable on the phone's LAN address",
              info: info
            ))
        }
      }
    }
    let listenerDown = {
      failOnce(Self.makeError(.localServerUnreachable, "Local server not answering"))
    }
    server.checkHealth(attempts: Self.listenerProbeAttempts) { answering in
      guard !finished else { return }
      if answering {
        verifyLANAddress()
        return
      }
      _ = self.server.ensureRunning()
      guard self.server.port > 0 else {
        listenerDown()
        return
      }
      self.server.checkHealth(attempts: Self.listenerProbeAttempts) { answering in
        guard !finished else { return }
        if answering {
          verifyLANAddress()
        } else {
          listenerDown()
        }
      }
    }
  }

  /// Quick loopback tries per listener check (0.2 s apart, 1 s timeout each).
  static let listenerProbeAttempts = 5

  var sourceDurationSeconds: TimeInterval { writer.sourceDurationSeconds }
  var sourceTracks: RemuxSourceTracks? { writer.sourceTracks }

  /// Girdi seek'inin gerçekte düştüğü konum; seek edilemeyen kaynakta 0'a düşer.
  /// Zaman çizelgesi muhasebesi istenen offset yerine bunu kullanmalı.
  var effectiveStartOffsetSeconds: TimeInterval { writer.effectiveStartSeconds }

  /// Actual source origin of the local video timeline, including backward seek
  /// preroll. Live sources retain their existing relative timeline.
  var videoStartOffsetSeconds: TimeInterval {
    isLive ? effectiveStartOffsetSeconds
      : (writer.firstVideoContentSeconds ?? effectiveStartOffsetSeconds)
  }

  /// Can this session be rebuilt at another position? False until the writer has
  /// opened the source, then true when the input can seek and no start seek was
  /// refused. A rebuild nobody asked for (the low-space one) must check this:
  /// `effectiveStartOffsetSeconds` only shows a refused seek, and a session started
  /// at 0:00 never tried one. Thread-safe.
  var sourceCanSeek: Bool { writer.sourceCanSeek }

  /// Cast oynatıcısının kaynak-zamanı konumu — yazıcının VOD pacing kapısını besler.
  func updatePlaybackPosition(_ seconds: TimeInterval) {
    writer.updatePlaybackPosition(seconds)
  }

  /// Retries once a second until the first-packet deadline has passed since
  /// `startedAt` (the same clock and limit as the playlist wait), instead of a
  /// fixed number of tries. On failure the completion also gets the last try's
  /// URLSession error (nil when the server answered, with something other than 200).
  private func verifyReachable(
    url: URL,
    startedAt: TimeInterval,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    let task = URLSession.shared.dataTask(with: request) { _, response, error in
      if (response as? HTTPURLResponse)?.statusCode == 200 {
        DispatchQueue.main.async { completion(true, nil) }
      } else if ProcessInfo.processInfo.systemUptime - startedAt
        < Self.firstPacketDeadlineSeconds
      {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
          self.verifyReachable(url: url, startedAt: startedAt, completion: completion)
        }
      } else {
        // The cause of the last try, which used to be thrown away: without it a
        // timeout, a refused connection and a wrong answer look the same in a log.
        Log.error(
          "AirPlayRemux",
          "LAN /ping probe failed: "
            + Self.probeFailureDescription(
              error: error, statusCode: (response as? HTTPURLResponse)?.statusCode
            )
        )
        DispatchQueue.main.async { completion(false, error) }
      }
    }
    task.resume()
  }

  /// What a failed `/ping` try looked like: the URLSession error's domain, code and
  /// text, or the HTTP status when the server did answer. Pure function.
  static func probeFailureDescription(error: Error?, statusCode: Int?) -> String {
    if let error {
      let ns = error as NSError
      return "\(ns.domain) \(ns.code) (\(ns.localizedDescription))"
    }
    if let statusCode { return "HTTP \(statusCode)" }
    return "no response"
  }

  func stop() {
    isStopped = true
    writer.cancel()
    // Paylaşılan sunucu durdurulmaz; yalnız bu oturumun dizini temizlenir. Silme
    // GECİKMELİ: içerik değişiminde Apple TV eski playlist'i bir süre daha
    // yoklayabiliyor — dizin 1 sn'de silinince 404'ler item'ı .failed'a itip
    // sağlıklı devri öldürüyordu.
    // Size: a live directory is the window plus a few retired segments; a VOD
    // directory holds everything written since the session's start offset.
    let dir = directory
    if endedOutOfSpace {
      // The disk is full: the session that replaces this one needs the space now,
      // and with the delay it failed on the same full disk. The delayed pass below
      // still runs, for anything the unwinding writer drops in meanwhile.
      DispatchQueue.global(qos: .utility).async {
        try? FileManager.default.removeItem(at: dir)
      }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
      try? FileManager.default.removeItem(at: dir)
    }
  }

  // MARK: - Storage budget (VOD)

  /// Upper bound of a session's budget, however much space is free.
  static let maximumStorageBudgetBytes: Int64 = 4 * 1024 * 1024 * 1024
  /// Lower bound: room for the start buffer plus the writer's 25 s look-ahead at
  /// 4K remux bitrates. A session that has written less is never rebuilt for
  /// space: it would be asked again before playback settles and every rebuild
  /// would trigger the next one. On a disk that cannot hold even this, the write
  /// fails and the cast ends as "storage full".
  static let minimumStorageBudgetBytes: Int64 = 512 * 1024 * 1024
  /// Free space under which a VOD session asks to be rebuilt.
  static let lowFreeSpaceBytes: Int64 = 1536 * 1024 * 1024
  private static let storageBudgetPollSeconds: TimeInterval = 2
  /// Interval once the free space is being read: the volume query is not free, and
  /// at remux bitrates the margin above cannot be used up in this time.
  private static let freeSpacePollSeconds: TimeInterval = 10

  /// Should a VOD session ask to be rebuilt? Only when the volume is really low
  /// and the session holds enough for a rebuild to free something: a routine byte
  /// count is no reason to reload the picture on the TV. Unknown free space (nil,
  /// or the 0 the system reports when it cannot tell) never triggers; a disk that
  /// does fill up still ends the cast through the out-of-space path. Pure function.
  static func storageRunningLow(bytesWritten: Int64, availableCapacity: Int64?) -> Bool {
    guard let availableCapacity, availableCapacity > 0 else { return false }
    return availableCapacity < lowFreeSpaceBytes && bytesWritten >= minimumStorageBudgetBytes
  }

  /// Room a VOD cast is expected to need, for the check before a cast starts
  /// (`CastController.hasStorageForVODCast`): the smaller of
  /// `maximumStorageBudgetBytes` and a quarter of the free space, never below
  /// `minimumStorageBudgetBytes`. Unknown free space (nil, or the 0 the system
  /// reports when it cannot tell) gets the maximum. Pure function.
  static func storageBudgetBytes(availableCapacity: Int64?) -> Int64 {
    guard let availableCapacity, availableCapacity > 0 else {
      return maximumStorageBudgetBytes
    }
    return max(
      minimumStorageBudgetBytes,
      min(maximumStorageBudgetBytes, availableCapacity / 4)
    )
  }

  static func storageBudgetExceeded(bytesWritten: Int64, budgetBytes: Int64) -> Bool {
    budgetBytes > 0 && bytesWritten >= budgetBytes
  }

  /// A full disk (or quota), whether FFmpeg reports it (errno, negated) or a
  /// Foundation file write does.
  static func isOutOfSpace(_ error: Error) -> Bool {
    if let remuxError = error as? RemuxHLSWriter.RemuxError {
      switch remuxError {
      case let .writeFailed(code), let .openOutputFailed(code):
        return isOutOfSpaceCode(code)
      default:
        return false
      }
    }
    return isOutOfSpaceNSError(error as NSError)
  }

  /// errno as it is, or negated the way FFmpeg returns it (AVERROR(ENOSPC)).
  private static func isOutOfSpaceCode(_ code: Int32) -> Bool {
    code == ENOSPC || code == -ENOSPC || code == EDQUOT || code == -EDQUOT
  }

  private static func isOutOfSpaceNSError(_ error: NSError) -> Bool {
    if error.domain == NSPOSIXErrorDomain, isOutOfSpaceCode(Int32(clamping: error.code)) {
      return true
    }
    if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
      return true
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isOutOfSpaceNSError(underlying)
    }
    return false
  }

  private func startStorageBudgetWatch() {
    // A live session prunes behind its window; only VOD grows with watched time.
    guard !isLive else { return }
    pollStorageBudget(after: Self.storageBudgetPollSeconds)
  }

  /// One check per poll interval on the utility queue: the bytes written, and once
  /// those could matter, the volume's free space as it is now (not as it was at
  /// the start). The chain ends with the session (weak self), with the writer
  /// (closed: nothing more is written) or once low space has been reported.
  private func pollStorageBudget(after delay: TimeInterval) {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      let written = self.writer.bytesWritten
      var available: Int64?
      var nextDelay = Self.storageBudgetPollSeconds
      if written >= Self.minimumStorageBudgetBytes {
        // URL caches resource values; without this every read after the first
        // could return the same number.
        var volume = self.directory
        volume.removeAllCachedResourceValues()
        available = (try? volume.resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ))?.volumeAvailableCapacityForImportantUsage
        nextDelay = Self.freeSpacePollSeconds
      }
      guard Self.storageRunningLow(bytesWritten: written, availableCapacity: available) else {
        if !self.writer.isClosed { self.pollStorageBudget(after: nextDelay) }
        return
      }
      let free = available ?? 0
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isStopped, !self.storageBudgetReported else { return }
        // Still starting: the owner is not ready to rebuild; ask again after start.
        guard self.localPlaylistURL != nil else {
          self.pollStorageBudget(after: Self.storageBudgetPollSeconds)
          return
        }
        self.storageBudgetReported = true
        Log.info(
          "AirPlayRemux",
          "free space low (\(free / 1_048_576) MB free, \(written / 1_048_576) MB written); "
            + "asking for a rebuild"
        )
        self.onStorageBudgetExceeded?()
      }
    }
  }

  /// Cast'in başlamasına yetecek içerik playlist'te birikti mi? Canlı: 3 segment
  /// yeter (gerçek zamanlı dolar). VOD: AVPlayer yazıcının dibinde koşmasın diye
  /// tampon biriksin — 4K'da indirme gerçek zamana yakınken tampon olmadan TV'de
  /// tekleme kaçınılmaz. ENDLIST (kısa içerik/remux bitti) her durumda yeterlidir.
  /// Saf fonksiyon: 13-14. tur düzeltmelerinin (tampon kapıları) regresyon kilidi.
  static func playlistReady(
    content: String,
    isLive: Bool,
    minimumBufferSeconds: Double
  ) -> Bool {
    if content.contains("#EXT-X-ENDLIST") { return true }
    let durations = content.split(separator: "\n")
      .filter { $0.hasPrefix("#EXTINF:") }
      .compactMap { Double($0.dropFirst("#EXTINF:".count).dropLast()) }
    return isLive
      ? durations.count >= 3
      : durations.reduce(0, +) >= minimumBufferSeconds
  }

  /// No packet at all by this point: the source did not open (the previous fixed limit).
  static let firstPacketDeadlineSeconds: TimeInterval = 25
  /// Once packets flow, this long without one is a dead source.
  static let readStallLimitSeconds: TimeInterval = 12
  /// Upper bound on the whole wait, however steadily the source delivers.
  static let maximumStartWaitSeconds: TimeInterval = 60

  /// Should `start` stop waiting for the playlist to become ready? A source that has
  /// delivered nothing fails after `firstPacketDeadlineSeconds`, as before. One that
  /// is delivering (a live channel with 8 s GOPs needs ~25 s for its three segments)
  /// is given time while packets keep coming, fails once they stop for
  /// `readStallLimitSeconds`, and is never waited on past `maximumStartWaitSeconds`.
  /// `stalledSeconds` is the writer's own stall clock, which excludes pacing sleeps
  /// and the pre-open drain wait. Pure function: the regression lock for the deadline.
  static func startWaitExpired(
    elapsedSeconds: TimeInterval,
    packetsRead: Int,
    stalledSeconds: TimeInterval
  ) -> Bool {
    if elapsedSeconds >= maximumStartWaitSeconds { return true }
    if packetsRead <= 0 { return elapsedSeconds >= firstPacketDeadlineSeconds }
    return stalledSeconds >= readStallLimitSeconds
  }

  /// `completion` runs on main: with nil once the playlist is ready, or with the
  /// writer's progress at the moment the wait was given up.
  private func waitForPlaylist(
    path: String,
    startedAt: TimeInterval,
    completion: @escaping (StartWaitProgress?) -> Void
  ) {
    let isLive = self.isLive
    DispatchQueue.global(qos: .userInitiated).async {
      // The playlist as last read, for the segment count of a failed wait.
      var lastContent: String?
      while true {
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
          if Self.playlistReady(
            content: content, isLive: isLive, minimumBufferSeconds: self.minimumBufferSeconds
          ) {
            DispatchQueue.main.async { completion(nil) }
            return
          }
          lastContent = content
        }
        let progress = self.writer.readProgress
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if Self.startWaitExpired(
          elapsedSeconds: elapsed,
          packetsRead: progress.packetsRead,
          stalledSeconds: progress.stalledSeconds
        ) {
          let gaveUpAt = StartWaitProgress(
            packetsRead: progress.packetsRead,
            closedSegments: lastContent.map { Self.closedSegmentCount(inPlaylist: $0) } ?? 0,
            stalledSeconds: progress.stalledSeconds,
            elapsedSeconds: elapsed
          )
          DispatchQueue.main.async { completion(gaveUpAt) }
          return
        }
        Thread.sleep(forTimeInterval: 0.25)
      }
    }
  }
}
