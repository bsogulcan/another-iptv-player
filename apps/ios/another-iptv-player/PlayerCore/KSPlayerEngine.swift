import AVFoundation
import AVKit
import Combine
import Foundation
import KSPlayer
import UIKit

/// Playback engine over `KSPlayerLayer` (KSAVPlayer with KSMEPlayer fallback).
/// Only the core of KSPlayer is used — video view + delegate callbacks; all UI stays ours.
///
/// This class knows NOTHING about AirPlay casting. The cast lifecycle (remux
/// session, cast player, route observation) lives in `CastController`, owned by
/// `VideoPlayerController`; the engine is simply stopped while a cast engagement
/// is active and reloaded when it ends.
final class KSPlayerEngine: NSObject, ObservableObject {
  @Published private(set) var isReady = false
  @Published private(set) var isPaused = true
  @Published private(set) var isSeekable = false
  @Published private(set) var isBuffering = false
  @Published private(set) var isCompleted = false
  @Published private(set) var isPlaybackEstablished = false
  @Published private(set) var playbackFailureMessage: String?
  /// True when the last failure was a transient open failure (timeout / host
  /// unreachable) worth one silent retry, false for terminal ones. Read by
  /// `VideoPlayerController` to decide auto-retry.
  @Published private(set) var playbackFailureIsRecoverable = false
  /// True when the failure just published is an HTTP 403 that arrived before playback
  /// was established: a panel that limits connections can still be counting the
  /// previous channel's socket right after a zap, and one later attempt may pass.
  /// Set before the message is published, like the recoverable flag, and cleared by
  /// the next load. Whether and when to retry is the owner's decision.
  private(set) var playbackFailureWantsDelayedRetry = false
  /// True from a seek request until the player confirms it, the seek fails or its
  /// timeout passes. KSPlayer reports no buffering for the length of a seek, so this
  /// is the only sign that one is under way.
  @Published private(set) var isSeekInFlight = false
  @Published private(set) var position: TimeInterval = 0
  @Published private(set) var duration: TimeInterval = 0
  @Published private(set) var playbackRate: Double = 1
  @Published private(set) var bufferTimelineEnd: TimeInterval = 0

  @Published private(set) var videoDisplayWidth: Int = 0
  @Published private(set) var videoDisplayHeight: Int = 0
  @Published private(set) var streamFPS: Double = 0
  @Published private(set) var renderFPS: Double = 0
  @Published private(set) var videoBitrate: Double = 0
  @Published private(set) var droppedFrameCount: Int64 = 0
  @Published private(set) var delayedFrameCount: Int64 = 0
  @Published private(set) var cacheBufferingState: Double = 0
  @Published private(set) var cacheDurationSeconds: Double = 0
  @Published private(set) var avSyncSeconds: Double = 0
  @Published private(set) var networkSpeedBps: Double = 0
  @Published private(set) var hwdecCurrent: String = ""
  @Published private(set) var videoCodecName: String = ""

  /// Bumped whenever `videoView` may point to a new UIView (engine fallback swaps the
  /// player instance); the SwiftUI surface remounts on change.
  @Published private(set) var surfaceRevision = 0
  /// Gerçek AirPlay (external playback) yalnız AVPlayer motorunda mümkün; FFmpeg
  /// yolundaki remux adaylığını `VideoPlayerController` hesaplar.
  @Published private(set) var isAirPlayVideoCapable = false
  /// Aktif oynatıcı KSMEPlayer (FFmpeg yolu) mu? Remux adaylığının bir bileşeni.
  @Published private(set) var isFFmpegBackendActive = false
  /// Debug overlay teşhisi + remux adaylığı için aktif ses codec'i.
  @Published private(set) var audioCodecName: String = ""
  /// Current subtitle cue for the overlay (nil = hide).
  @Published private(set) var subtitleText: NSAttributedString?
  @Published private(set) var subtitleImage: UIImage?
  /// Native-frame pixel position of `subtitleImage` (PGS/DVB bitmap cues), from
  /// `SubtitlePart.origin`; `.zero` when the image spans multiple merged regions.
  @Published private(set) var subtitleImageOrigin: CGPoint = .zero
  @Published private(set) var subtitleAppearance = SubtitleAppearancePersistence.load()
  @Published private(set) var isPiPActive = false
  /// Whether the system would start Picture in Picture right now. False until the
  /// player is ready and whenever PiP is switched off in the settings.
  @Published private(set) var isPictureInPicturePossible = false

  var changePublisher: AnyPublisher<Void, Never> {
    objectWillChange.eraseToAnyPublisher()
  }

  var videoView: UIView? { layer?.player.view }
  var isExternalPlaybackActive: Bool { layer?.player.isExternalPlaybackActive ?? false }

  /// Called once per load when a live stream runs dry (the server ended it cleanly).
  /// The item is not marked completed; the engine reports buffering until the owner
  /// either loads again or calls `markLiveStreamEnded()`.
  var onLiveStreamEnded: (() -> Void)?
  /// Called by `play()` when the ended item cannot be rewound, so only a fresh load
  /// can play it again.
  var onReloadRequested: (() -> Void)?
  /// True only while the FFmpeg player is active: the audio delay is applied through
  /// `KSOptions.videoDelay`, which AVPlayer never reads.
  var supportsAudioDelay: Bool { layer?.player is KSMEPlayer }
  /// The container FFmpeg detected for the current load ("mpegts", "matroska,webm",
  /// "mov,mp4,m4a,3gp,3g2,mj2", "hls"…), nil on the AVPlayer path and until the
  /// source has opened.
  ///
  /// A copy taken on the main thread when the player reports ready, because KSPlayer
  /// writes `KSOptions.formatName` on its open thread. It outlives `stopPlayback()`,
  /// so the owner can still read it while a cast takes over, and is cleared by the
  /// next load.
  private(set) var containerFormatName: String?

  private(set) var layer: KSPlayerLayer?
  /// Options of the current load; they record which tracks FFmpeg cannot decode.
  private var guardedOptions: GuardedKSOptions?
  private let subtitleModel = SubtitleModel()
  /// Reported subtitle track id → info. Ids are stable per load (insertion order).
  private var subtitleInfosById: [Int: any SubtitleInfo] = [:]
  private var removedSubtitleIDs: Set<String> = []
  private var externalSubtitleIDs: Set<String> = []
  private var embeddedSubtitleSourceAttached = false
  private var pendingAudioDelay: Double = 0
  private var loadTimeoutWorkItem: DispatchWorkItem?
  private var lastPositionPublish: TimeInterval = 0
  private var isDisposed = false
  /// Whether the current load is a live stream (`liveLowLatency` of `load`).
  private var currentLoadIsLive = false
  /// A live stream of the current load has ended; reported at most once per load.
  private var liveStreamEndReported = false
  /// Start position of the current load until the AVPlayer path has seeked to it.
  /// `KSOptions.startPlayTime` is only read by the FFmpeg player.
  private var pendingStartSeconds: TimeInterval?
  /// Set while the start seek is in flight. The layer already reports "playing" for
  /// the opening frame, so the transport flags are held at buffering until it lands.
  private var startSeekHoldsTransport = false
  /// Target of a seek the player has not confirmed yet. `position` shows it at once
  /// and time ticks leave `position` alone until the seek settles.
  private var pendingSeekTarget: TimeInterval? {
    didSet {
      // Every path that ends a seek (completion, timeout, cancel) clears the target,
      // so the published flag needs no bookkeeping of its own.
      let pending = pendingSeekTarget != nil
      if isSeekInFlight != pending { isSeekInFlight = pending }
    }
  }
  /// Bumped for every seek request; completions and timers of older ones are ignored.
  private var seekGeneration = 0
  /// Seeks issued until the pending one settles resume playback even when paused
  /// (start seek, seek after the end).
  private var pendingSeekForcesPlay = false
  private var seekTimeoutWorkItem: DispatchWorkItem?
  private var jumpDebounceWorkItem: DispatchWorkItem?
  private var pausedRepaintWorkItem: DispatchWorkItem?

  /// The first skip tap seeks at once. Taps that follow while that seek is unsettled
  /// are coalesced into one more seek, issued this long after the last of them: every
  /// FFmpeg seek over HTTP reopens the connection to the panel.
  private static let jumpDebounceInterval: TimeInterval = 0.2
  /// A superseded FFmpeg seek never calls back; without this `position` would stay
  /// frozen on the target.
  private static let seekCompletionTimeout: TimeInterval = 5
  private static let pausedRepaintInterval: TimeInterval = 0.06
  private static let pausedRepaintAttempts = 50
  /// Cached quarter-rotation of the current AVPlayer video track. Synchronous
  /// `preferredTransform` access is deprecated (iOS 16); the transform is loaded
  /// asynchronously once per track and consumed by `refreshDiagnostics`.
  private weak var quarterRotationQueriedTrack: AVAssetTrack?
  private var avTrackIsQuarterRotated = false
  /// When `refreshTrackFacts` last ran; 0 makes the next time tick run it.
  private var lastTrackFactsRefresh: TimeInterval = 0
  /// The layer whose time-tick timer already runs in the common run-loop modes. A
  /// layer creates that timer once, so it is looked up once per layer.
  private weak var progressTimerPromotedLayer: KSPlayerLayer?

  // MARK: - Load

  /// URL of the current load, kept for the AVPlayer rescue.
  private var currentLoadURL: URL?
  /// The current load runs on the FFmpeg player with no second player behind it, so
  /// its error reaches `finish(error:)`.
  private var currentLoadIsFFmpegOnly = false
  /// The FFmpeg failure the AVPlayer rescue of this load answers; nil until one ran.
  private var rescuedFailure: KSPlayerLoadPolicy.Failure?
  /// A layer whose stream failed after it was ready: stopped, but kept until the next
  /// load (see `failAndRetireLayer`).
  private var retiredLayer: KSPlayerLayer?

  func load(
    _ url: URL,
    play: Bool,
    startSeconds: TimeInterval?,
    liveLowLatency: Bool,
    userAgent: String?
  ) {
    guard !isDisposed else { return }
    observeAppLifecycleIfNeeded()
    resetForNewLoad()
    currentLoadIsLive = liveLowLatency
    if let startSeconds, startSeconds.isFinite, startSeconds > 0 {
      pendingStartSeconds = startSeconds
    }
    subtitleModel.url = url
    // Motor sırası içerik türünden seçilir. AVPlayer'ın oynatamayacağı kaplarda
    // (mkv/avi/ts/uzantısız canlı TS) önce AVPlayer'ı deneyip başarısızlığını beklemek
    // açılışı saniyelerce uzatıyordu; doğrudan FFmpeg ile başla.
    let ffmpegFirst = Self.prefersFFmpegFirst(for: url)
    if ffmpegFirst {
      KSOptions.firstPlayerType = KSMEPlayer.self
      // No second player: KSPlayerLayer would swap to AVPlayer and drop the FFmpeg
      // error (an HTTP 403, a timeout) before the engine saw it, and AVPlayer would
      // then open the same URL once more for nothing. The error is classified in
      // `finish(error:)`, which starts the AVPlayer attempt itself for the few errors
      // where it can help.
      KSOptions.secondPlayerType = nil
    } else {
      KSOptions.firstPlayerType = KSAVPlayer.self
      KSOptions.secondPlayerType = KSMEPlayer.self
    }
    currentLoadURL = url
    currentLoadIsFFmpegOnly = ffmpegFirst
    AVAssetTrackDataRateGuard.install()
    let options = Self.makeOptions(
      liveLowLatency: liveLowLatency,
      startSeconds: startSeconds,
      userAgent: userAgent
    )
    guardedOptions = options
    // Layer her yüklemede sıfırdan kurulur. `layer.set(url:)` yolu KULLANILMAZ:
    // KSPlayerLayer.url.didSet, herhangi bir kablosuz rota aktifken bizim motor
    // seçimimizi ezip KSAVPlayer'ı zorluyor (mkv/ts'te uzun başarısızlık + fallback
    // beklemesi — "içerik açılmıyor" şikayetinin ikinci kök nedeni). init yolu
    // statiklere sadık kalır.
    releaseLayer()
    let newLayer = KSPlayerLayer(url: url, isAutoPlay: play, options: options, delegate: self)
    layer = newLayer
    // Right after creation: the FFmpeg item's capacity timer already exists and
    // KSPlayer's own threads have barely started writing the item's other fields.
    KSPlayerRunLoopGuard.promoteCapacityTimer(of: newLayer.player)
    bumpSurfaceRevision()
    isReady = true
    scheduleLoadTimeoutWatchdog()
  }

  /// Non-terminal stop: releases the layer (and its source connection) but keeps
  /// the engine reusable. Used when a cast engagement takes over playback.
  /// NOTE: `KSPlayerLayer.deinit` calls `MPRemoteCommandCenter removeTarget(nil)`
  /// unconditionally — the owner must reinstall its remote commands after this.
  func stopPlayback() {
    guard !isDisposed else { return }
    cancelLoadTimeoutWatchdog()
    cancelPendingSeek()
    pendingStartSeconds = nil
    releaseLayer()
    // Nothing is buffered any more; the scrubber draws its buffered range from this.
    resetBufferTimeline()
    if !isBuffering { isBuffering = true }
  }

  /// The one place a layer is let go for good (new load, cast takeover, dispose).
  private func releaseLayer() {
    cancelPlaybackWatchdog()
    endBackgroundVideoSuspension()
    retiredLayer = nil
    guard let oldLayer = layer else {
      // At most a retired layer was left, and its PiP window goes with it.
      releasePictureInPictureController()
      return
    }
    oldLayer.delegate = nil
    oldLayer.stop()
    // KSPlayerLayer never invalidates its repeating 0.1 s timer; left alone it keeps
    // firing on the main run loop after the layer is gone, one more per zap.
    KSPlayerRunLoopGuard.invalidateProgressTimer(of: oldLayer)
    layer = nil
    // Without a layer no state change or time tick reaches `refreshPiPState`: the
    // controller of the stopped player would be kept, and PiP reported as possible,
    // until the next load.
    releasePictureInPictureController()
  }

  /// Stops the current layer so nothing keeps reading from a source that will not
  /// play, and reports the failure. The layer object is parked until the next load
  /// instead of being released: `KSPlayerLayer.deinit` wipes the remote command
  /// targets, and the owner reinstalls them only around its own load and stop calls.
  private func failAndRetireLayer(message: String, recoverable: Bool) {
    cancelLoadTimeoutWatchdog()
    cancelPlaybackWatchdog()
    cancelPendingSeek()
    endBackgroundVideoSuspension()
    if let failed = layer {
      failed.delegate = nil
      failed.stop()
      KSPlayerRunLoopGuard.invalidateProgressTimer(of: failed)
      // A parked layer must stay inert: its own observers would otherwise call
      // `play()` after an audio interruption and reopen the stream behind the
      // engine's back. Its deinit removes them anyway.
      NotificationCenter.default.removeObserver(failed)
      retiredLayer = failed
      layer = nil
      // The parked layer keeps its player and with it the PiP controller, which would
      // go on reporting PiP as possible. A window that is still open is left alone:
      // it has to report its own end, and the orphan check lets go of it then.
      if pipController?.isPictureInPictureActive != true {
        releasePictureInPictureController()
      }
    }
    if isBuffering { isBuffering = false }
    publishFailure(message: message, recoverable: recoverable)
  }

  /// The recoverable flag first: the owner reads both when the message appears. The
  /// delayed-retry flag is written on every failure, so it always describes the one
  /// being published.
  private func publishFailure(
    message: String, recoverable: Bool, wantsDelayedRetry: Bool = false
  ) {
    playbackFailureWantsDelayedRetry = wantsDelayedRetry
    if playbackFailureIsRecoverable != recoverable { playbackFailureIsRecoverable = recoverable }
    if playbackFailureMessage != message { playbackFailureMessage = message }
  }

  /// One AVPlayer attempt at a URL FFmpeg could not open, inside the same layer. It
  /// is what KSPlayer's second-player swap used to do for every FFmpeg error; here it
  /// runs only for errors where a different player can help (an extensionless HLS or
  /// MP4 link). The FFmpeg item has closed its connection by the time its error
  /// arrives, so the two never read the source together.
  private func startAVPlayerRescue(
    on layer: KSPlayerLayer, after failure: KSPlayerLoadPolicy.Failure
  ) -> Bool {
    guard let url = currentLoadURL, let options = guardedOptions else { return false }
    rescuedFailure = failure
    currentLoadIsFFmpegOnly = false
    KSOptions.firstPlayerType = KSAVPlayer.self
    KSOptions.secondPlayerType = nil
    // `set(url:)` stops the layer first, which resets both values on the old player
    // before the new one copies them.
    let volume = layer.player.playbackVolume
    let rate = layer.player.playbackRate
    // Same URL, other player type: the layer replaces its player and, when the load
    // was started with autoplay, prepares it.
    layer.set(url: url, options: options)
    layer.player.playbackVolume = volume
    layer.player.playbackRate = rate
    scheduleLoadTimeoutWatchdog()
    return true
  }

  private func resetForNewLoad() {
    cancelLoadTimeoutWatchdog()
    cancelPlaybackWatchdog()
    cancelPendingSeek()
    pendingStartSeconds = nil
    currentLoadIsLive = false
    currentLoadURL = nil
    currentLoadIsFFmpegOnly = false
    containerFormatName = nil
    rescuedFailure = nil
    liveStreamEndReported = false
    playbackFailureMessage = nil
    playbackFailureIsRecoverable = false
    playbackFailureWantsDelayedRetry = false
    isPlaybackEstablished = false
    isCompleted = false
    isBuffering = true
    isPaused = true
    isSeekable = false
    position = 0
    duration = 0
    bufferTimelineEnd = 0
    subtitleText = nil
    subtitleImage = nil
    subtitleImageOrigin = .zero
    subtitleInfosById = [:]
    removedSubtitleIDs = []
    externalSubtitleIDs = []
    embeddedSubtitleSourceAttached = false
    // Codec/capability diagnostics belong to the previous content; a stale value
    // must not gate AirPlay/remux candidacy for the next one.
    videoCodecName = ""
    audioCodecName = ""
    isFFmpegBackendActive = false
    isAirPlayVideoCapable = false
    lastTrackFactsRefresh = 0
    // The cached rotation is applied on every time tick, also before the new item's
    // video track has been looked at; the previous item's value must not swap the
    // new picture's size.
    quarterRotationQueriedTrack = nil
    avTrackIsQuarterRotated = false
  }

  /// AVPlayer'ın native oynatabildiği uzantılar; geri kalan her şey (mkv, avi, ts,
  /// uzantısız Xtream canlı) FFmpeg'e gider. mpv dönemindeki davranışla birebir —
  /// yalnızca HLS/mp4 ailesi AVPlayer'a (ve gerçek AirPlay'e) çıkar.
  ///
  /// Audio-only files (mp3, m4a, aac) are not in the set: KSAVPlayer fails every item
  /// without a playable video track, so they were opened on AVPlayer, failed there
  /// and were opened a second time on FFmpeg.
  private static let avPlayerExtensions: Set<String> = [
    "m3u8", "mp4", "m4v", "mov",
  ]
  /// Audio containers AVFoundation plays, but KSAVPlayer does not (see above).
  private static let avFoundationAudioExtensions: Set<String> = ["mp3", "m4a", "aac"]

  static func prefersFFmpegFirst(for url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return !avPlayerExtensions.contains(ext)
  }

  /// Whether a plain `AVPlayer` can play the URL, judged by its extension. Wider than
  /// `!prefersFFmpegFirst(for:)`, which is about the order this engine opens players
  /// in: an audio-only file opens on FFmpeg here, while an AVPlayer without
  /// KSAVPlayer's video-track check plays it.
  static func isAVFoundationPlayable(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return avPlayerExtensions.contains(ext) || avFoundationAudioExtensions.contains(ext)
  }

  private static func makeOptions(
    liveLowLatency: Bool,
    startSeconds: TimeInterval?,
    userAgent: String?
  ) -> GuardedKSOptions {
    let options = GuardedKSOptions()
    if let userAgent, !userAgent.isEmpty {
      options.userAgent = userAgent
      // `KSOptions.userAgent` only sets the FFmpeg header (`formatContextOptions`). The
      // native path builds `AVURLAsset(url:options: options.avOptions)`, so without this
      // AVPlayer sends the default `AppleCoreMedia` UA. Panels that gate on User-Agent
      // reject that → AVPlayer fails → falls back to FFmpeg, losing native playback AND
      // native AirPlay. Mirror the UA onto the asset HTTP headers so UA-compatible content
      // stays on AVPlayer. (Set avOptions directly rather than `appendHeader`, which would
      // also duplicate the UA into the FFmpeg `headers` option.)
      var assetHeaders =
        options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] ?? [:]
      assetHeaders["User-Agent"] = userAgent
      options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] = assetHeaders
    }
    if let startSeconds, startSeconds > 0 {
      options.startPlayTime = startSeconds
    }
    // isSecondOpen: ilk kare her parça 2 kare decode edince salınır — açılış süresini
    // kısaltır. NOT: bu yüzden preferredForwardBufferDuration/maxBufferDuration İLK
    // kareyi geciktirmez; yalnız yeniden-buffer yastığını ve seek/second-open'ı yönetir.
    options.isSecondOpen = true
    if liveLowLatency {
      options.preferredForwardBufferDuration = 2
      options.maxBufferDuration = 16
      // FFmpeg yolunda ilk kare, avformat_find_stream_info'nun varsayılan 5 MB probe'u
      // yavaş IPTV soketinden çekmesine takılıyordu. Bu iki değer, uygulamanın kendi
      // remux giriş yolunda (RemuxHLSWriter) sahada kanıtlanmış değerlerdir; AVPlayer/HLS
      // yolunda bu alanlar okunmaz (inert). `nobuffer` bilerek KAPALI — find_stream_info'nun
      // ikincil ses parçasını kaçırmasına yol açabiliyor.
      options.probesize = 1_500_000
      options.maxAnalyzeDuration = 2_000_000  // AV_TIME_BASE birimi = 2.0s
    } else {
      options.preferredForwardBufferDuration = 3
      options.maxBufferDuration = 60
      // VOD (mkv/avi/ts): çok parçalı başlıkları aç bırakmadan en kötü analiz süresini sınırla.
      options.maxAnalyzeDuration = 3_000_000  // 3.0s tavan
    }
    // Duran sokette tek IO 10 sn'de başarısız olsun; watchdog (12s) devreye girmeden
    // FFmpeg gerçek hata kodunu döndürür. Yalnız FFmpeg yolu (AVPlayer bunu yok sayar).
    options.formatContextOptions["rw_timeout"] = 10_000_000  // mikrosaniye
    // FFmpeg's HTTP reader reconnects after a broken read with growing pauses (0, 1,
    // 3, 7, 15… s) until one would exceed this limit, 120 s by default. Capped so a
    // dead source comes back as an error the engine can classify and retry.
    options.formatContextOptions["reconnect_delay_max"] = 10  // seconds
    // Remote commands are ours (VideoPlayerController). KSPlayerLayer's own
    // registration would double-handle events; its deinit still wipes all
    // targets regardless of this flag, which the controller compensates for.
    options.registerRemoteControll = false
    let defaults = UserDefaults.standard
    let pipEnabled = defaults.object(forKey: "player.pipEnabled") as? Bool ?? true
    let backgroundEnabled =
      defaults.object(forKey: "player.continuePlayingInBackground") as? Bool ?? true
    options.canStartPictureInPictureAutomaticallyFromInline = pipEnabled && backgroundEnabled
    // Read by KSPlayerLayer when the app enters the background (it leaves an active
    // PiP alone): false pauses, true calls `player.enterBackground()`. That call
    // detaches the picture on AVPlayer and does nothing on the FFmpeg player, whose
    // video the engine suspends itself (see "Background").
    KSOptions.canBackgroundPlay = backgroundEnabled
    return options
  }

  // MARK: - Transport

  func play() {
    let action = KSPlayerEngineMath.playAction(
      isCompleted: isCompleted,
      isSeekable: isSeekable,
      liveStreamEnded: liveStreamEndReported,
      canReload: onReloadRequested != nil
    )
    switch action {
    case .reload:
      // Nothing is left to play and the source cannot be rewound (a live stream the
      // server closed): seeking to 0 would do nothing, only a new load helps.
      onReloadRequested?()
    case .restartFromBeginning:
      layer?.seek(time: 0, autoPlay: true) { _ in }
      isCompleted = false
    case .resume:
      layer?.play()
    }
  }

  func pause() {
    layer?.pause()
  }

  /// Puts the engine into the regular completed state. For the owner, once it gives
  /// up reloading a live stream that `onLiveStreamEnded` reported.
  func markLiveStreamEnded() {
    guard !isDisposed else { return }
    liveStreamEndReported = true
    if !isCompleted { isCompleted = true }
    if !isPaused { isPaused = true }
    if isBuffering { isBuffering = false }
  }

  func seek(to seconds: TimeInterval) {
    guard seconds.isFinite, let layer, Self.canSeek(layer) else { return }
    let target = KSPlayerEngineMath.clampedSeekTarget(seconds, duration: knownDuration(of: layer))
    requestSeek(to: target, on: layer, debounced: false)
  }

  func seekToFraction(_ pos: Float) {
    guard duration > 0 else { return }
    seek(to: duration * Double(min(max(pos, 0), 1)))
  }

  func jumpRelative(seconds: Int) {
    guard let layer, Self.canSeek(layer) else { return }
    let target = KSPlayerEngineMath.accumulatedSeekTarget(
      position: position,
      pendingTarget: pendingSeekTarget,
      delta: Double(seconds),
      duration: knownDuration(of: layer)
    )
    // A skip is meant to move by exactly its interval; a scrub lands on a keyframe.
    requestSeek(to: target, on: layer, debounced: true, accurate: true)
  }

  // MARK: - Seek bookkeeping

  /// Whether the pending seek asks for the exact time instead of the nearest keyframe.
  private var pendingSeekIsAccurate = false
  /// Play/pause intent of the seek last handed to the player; restored when it fails.
  private var issuedSeekResumesPlayback = false
  /// When the player was first seen parked in its seeking state with no seek of the
  /// engine pending (see `resumeStrandedSeek`).
  private var strandedSeekSince: CFAbsoluteTime?
  /// A seek that only just finished still reports the seeking state for a moment.
  private static let strandedSeekGrace: TimeInterval = 1

  /// Same condition `KSPlayerLayer.seek` uses to seek right away. When it does not
  /// hold the layer only stores the target for its next ready callback, which never
  /// resumes a stream that cannot seek, so such requests are dropped here instead.
  private static func canSeek(_ layer: KSPlayerLayer) -> Bool {
    layer.player.isReadyToPlay && layer.player.seekable
  }

  /// The player's own duration: valid as soon as it is ready, before the first time tick.
  private func knownDuration(of layer: KSPlayerLayer) -> TimeInterval {
    let reported = layer.player.duration
    return reported.isFinite && reported > 0 ? reported : duration
  }

  private func publishPosition(_ seconds: TimeInterval) {
    lastPositionPublish = CFAbsoluteTimeGetCurrent()
    if position != seconds { position = seconds }
  }

  private func resetBufferTimeline() {
    if bufferTimelineEnd != 0 { bufferTimelineEnd = 0 }
  }

  /// KSPlayer's time callback is the only other writer of `position`, and it stops
  /// while paused. The target is therefore published at once and kept until the
  /// player confirms the seek.
  private func requestSeek(
    to target: TimeInterval, on layer: KSPlayerLayer, debounced: Bool, accurate: Bool = false
  ) {
    seekGeneration += 1
    jumpDebounceWorkItem?.cancel()
    jumpDebounceWorkItem = nil
    seekTimeoutWorkItem?.cancel()
    seekTimeoutWorkItem = nil
    pausedRepaintWorkItem?.cancel()
    pausedRepaintWorkItem = nil
    // A newer seek supersedes the start seek; its transport hold ends here.
    releaseStartSeekHold()
    // True while a debounce is armed or a seek the player has not confirmed is in flight.
    let isFollower = pendingSeekTarget != nil
    pendingSeekTarget = target
    // The latest request decides: a scrub that follows a burst of skips is a scrub.
    pendingSeekIsAccurate = accurate
    publishPosition(target)
    // The buffer belongs to the position the seek leaves. Time ticks publish the new
    // one once the seek has settled.
    resetBufferTimeline()
    leaveCompletedStateForSeek(on: layer)
    // The first skip seeks at once; only taps that follow an unsettled one are coalesced.
    guard debounced, isFollower else {
      issuePendingSeek()
      return
    }
    let generation = seekGeneration
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.isDisposed, generation == self.seekGeneration else { return }
      self.jumpDebounceWorkItem = nil
      self.issuePendingSeek()
    }
    jumpDebounceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.jumpDebounceInterval, execute: item)
  }

  private func issuePendingSeek() {
    guard let layer, let target = pendingSeekTarget else { return }
    guard Self.canSeek(layer) else {
      // The player changed under a debounced skip; drop the optimistic position.
      settlePendingSeek()
      return
    }
    leaveCompletedStateForSeek(on: layer)
    let generation = seekGeneration
    armSeekTimeout(generation: generation)
    let resumesPlayback = pendingSeekForcesPlay || !isPaused
    issuedSeekResumesPlayback = resumesPlayback
    applySeekAccuracy(pendingSeekIsAccurate, on: layer)
    layer.seek(time: target, autoPlay: resumesPlayback) { [weak self] finished in
      // KSPlayer calls back on whatever thread finished the seek.
      DispatchQueue.main.async { [weak self] in
        self?.seekDidComplete(generation: generation, finished: finished)
      }
    }
  }

  /// Both players read `KSOptions.isAccurateSeek` from the options object of the load
  /// each time they seek, so it can be chosen per seek. It is written before the seek
  /// and never reset afterwards: the FFmpeg player reads it a second time on its read
  /// thread.
  ///
  /// Exact seeks stay limited to AVPlayer (zero tolerance instead of "any keyframe").
  /// On the FFmpeg player they download and decode everything from the previous
  /// keyframe, can stall on containers that seek by byte position (MPEG-TS), and are
  /// compared against timestamps that still include the stream's start offset. That
  /// needs measuring on a device before it is switched on there.
  private func applySeekAccuracy(_ accurate: Bool, on layer: KSPlayerLayer) {
    guard let options = guardedOptions else { return }
    let exact = accurate && layer.player is KSAVPlayer
    if options.isAccurateSeek != exact { options.isAccurateSeek = exact }
  }

  /// A seek after the end: leave the completed state so the owner stops treating the
  /// item as finished, and resume at the target once the seek lands.
  private func leaveCompletedStateForSeek(on layer: KSPlayerLayer) {
    guard isCompleted else { return }
    isCompleted = false
    // `KSPlayerLayer.play()` rewinds to 0 while its state is `.playedToTheEnd`;
    // pausing first moves it to `.paused`, so the play after the seek keeps the target.
    layer.pause()
    pendingSeekForcesPlay = true
  }

  private func armSeekTimeout(generation: Int) {
    seekTimeoutWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.isDisposed, generation == self.seekGeneration,
            self.pendingSeekTarget != nil
      else { return }
      self.settlePendingSeek()
    }
    seekTimeoutWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.seekCompletionTimeout, execute: item)
  }

  private func seekDidComplete(generation: Int, finished: Bool) {
    guard !isDisposed, generation == seekGeneration, let layer else { return }
    // Also when the timeout already settled a slow seek: the real landing time and
    // the repaint below still apply.
    settlePendingSeek()
    guard finished else {
      recoverFromFailedSeek(on: layer)
      return
    }
    repaintPausedFrame(on: layer, generation: generation, attemptsLeft: Self.pausedRepaintAttempts)
  }

  /// KSPlayer parks the player in its seeking state for the length of a seek, with
  /// picture and sound stopped, and only the layer's completion of a successful seek
  /// resumes it. After a failed one (the panel refused the range request, no usable
  /// index, a start seek that did not land) it would stay frozen while the layer still
  /// reports "playing". Put it back into the state the seek was issued in.
  private func recoverFromFailedSeek(on layer: KSPlayerLayer) {
    guard layer.player.isReadyToPlay else { return }
    switch layer.state {
    case .readyToPlay, .buffering, .bufferFinished, .paused:
      if issuedSeekResumesPlayback {
        layer.play()
      } else {
        layer.pause()
      }
    case .initialized, .preparing, .playedToTheEnd, .error:
      // `play()` would prepare a failed layer again or rewind a finished one to 0.
      break
    }
  }

  /// The PiP window's skip buttons seek the FFmpeg player directly, with a completion
  /// that resumes nothing, and such a seek also swallows the completion of a seek of
  /// ours that was still in flight. Either way the player stays in its seeking state
  /// while the layer reports "playing". Called on every time tick.
  ///
  /// `play()` during a seek that is merely slow is harmless: the outputs stay stopped
  /// until the player has buffered again.
  private func resumeStrandedSeek(on layer: KSPlayerLayer) {
    // Not when the PiP window's button paused the player: the layer still reports
    // "playing" then, and the skip must leave it paused.
    guard pendingSeekTarget == nil, !isPaused, layer.state.isPlaying,
          layer.player.playbackState == .seeking
    else {
      strandedSeekSince = nil
      return
    }
    let now = CFAbsoluteTimeGetCurrent()
    guard let since = strandedSeekSince else {
      strandedSeekSince = now
      return
    }
    guard now - since >= Self.strandedSeekGrace else { return }
    strandedSeekSince = nil
    layer.play()
  }

  /// Ends the pending seek and hands `position` back to the player's clock.
  private func settlePendingSeek() {
    seekTimeoutWorkItem?.cancel()
    seekTimeoutWorkItem = nil
    pendingSeekTarget = nil
    pendingSeekForcesPlay = false
    releaseStartSeekHold()
    guard let layer else { return }
    let current = layer.player.currentPlaybackTime
    if current.isFinite { publishPosition(max(current, 0)) }
  }

  /// Drops every pending seek without touching the player (new load, stop, player swap).
  private func cancelPendingSeek() {
    seekGeneration += 1
    jumpDebounceWorkItem?.cancel()
    jumpDebounceWorkItem = nil
    seekTimeoutWorkItem?.cancel()
    seekTimeoutWorkItem = nil
    pausedRepaintWorkItem?.cancel()
    pausedRepaintWorkItem = nil
    pendingSeekTarget = nil
    pendingSeekForcesPlay = false
    startSeekHoldsTransport = false
    strandedSeekSince = nil
  }

  /// AVPlayer path only: KSAVPlayer ignores `KSOptions.startPlayTime`, so the load's
  /// start position is applied with one seek once the item can seek. The FFmpeg
  /// player has already started there and must not seek a second time.
  private func applyPendingStart(on layer: KSPlayerLayer, isLastChance: Bool) {
    guard let start = pendingStartSeconds else { return }
    // A live stream without a length has no position to resume: the value is the
    // previous load's clock and lies outside the new item's seekable window.
    if isLiveWithoutDuration(layer) {
      pendingStartSeconds = nil
      return
    }
    let action = KSPlayerEngineMath.pendingStartAction(
      start: start,
      isFFmpegPlayer: layer.player is KSMEPlayer,
      isSeekable: Self.canSeek(layer),
      duration: knownDuration(of: layer)
    )
    switch action {
    case .discard:
      pendingStartSeconds = nil
    case .wait:
      if isLastChance { pendingStartSeconds = nil }
    case .seek(let target):
      pendingStartSeconds = nil
      if !isSeekable { isSeekable = true }
      // A load paused before it became ready (interruption, lock-screen pause)
      // seeks and stays paused.
      let autoplays = layer.state.isPlaying
      pendingSeekForcesPlay = autoplays
      // The seek takes its play/pause intent from `isPaused`, which may not have
      // caught up with a pause whose state callback is still queued.
      if !autoplays, !isPaused { isPaused = true }
      requestSeek(to: target, on: layer, debounced: false)
      if autoplays {
        // The layer has already started playing the opening frame. Keep reporting
        // buffering (not paused) until the seek lands.
        startSeekHoldsTransport = true
        if !isBuffering { isBuffering = true }
        if isPaused { isPaused = false }
      }
    }
  }

  private func releaseStartSeekHold() {
    guard startSeekHoldsTransport else { return }
    startSeekHoldsTransport = false
    guard let layer else { return }
    // The layer's state carries the play/pause intent; the player itself may still
    // be in the middle of a seek and report "not playing".
    switch layer.state {
    case .bufferFinished:
      if isBuffering { isBuffering = false }
      if isPaused { isPaused = false }
    case .paused:
      if isBuffering { isBuffering = false }
      if !isPaused { isPaused = true }
    case .initialized, .preparing, .readyToPlay, .buffering:
      if !isBuffering { isBuffering = true }
    case .playedToTheEnd, .error:
      if isBuffering { isBuffering = false }
    }
  }

  /// FFmpeg path: while paused the renderer's display link is parked, so after a seek
  /// the old frame would stay on screen until playback resumes. `readNextFrame()` is
  /// the call KSMEPlayer itself uses for the first frame of a load; it pops one decoded
  /// frame without blocking and draws it. Decoding lags the seek, so it is retried
  /// briefly and stops as soon as a frame was drawn.
  private func repaintPausedFrame(on layer: KSPlayerLayer, generation: Int, attemptsLeft: Int) {
    pausedRepaintWorkItem = nil
    guard attemptsLeft > 0, layer === self.layer, layer.state == .paused,
          let output = (layer.player as? KSMEPlayer)?.videoOutput
    else { return }
    let before = output.pixelBuffer
    output.readNextFrame()
    if output.pixelBuffer !== before { return }
    // The layer is captured weakly: a cancelled work item keeps its captures until its
    // deadline, and a released layer must not outlive the owner's reinstall of the
    // remote commands (`KSPlayerLayer.deinit` wipes them).
    let item = DispatchWorkItem { [weak self, weak layer] in
      guard let self, let layer, !self.isDisposed, generation == self.seekGeneration
      else { return }
      self.repaintPausedFrame(on: layer, generation: generation, attemptsLeft: attemptsLeft - 1)
    }
    pausedRepaintWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.pausedRepaintInterval, execute: item)
  }

  func setVolume(_ value: Double) {
    layer?.player.playbackVolume = Float(min(max(value, 0), 125) / 100)
  }

  func setPlaybackRate(_ value: Double) {
    layer?.player.playbackRate = Float(value)
    if playbackRate != value { playbackRate = value }
  }

  func dispose() {
    guard !isDisposed else { return }
    isDisposed = true
    cancelLoadTimeoutWatchdog()
    cancelPendingSeek()
    backgroundSuspendWorkItem?.cancel()
    backgroundSuspendWorkItem = nil
    releaseLayer()
  }

  // MARK: - PiP

  // PiP is driven on the player's own `AVPictureInPictureController`, with the engine
  // as its delegate. `KSPlayerLayer.isPipActive` is not used: it goes through KSPlayer's
  // `start(view:)`, which also sends the app to the Home Screen with a private selector,
  // never hears that the window was closed, and leaves the restore request unanswered.

  /// The controller the engine is the delegate of. KSPlayer builds it lazily and the
  /// FFmpeg player replaces it whenever its display layer changes, so `refreshPiPState`
  /// compares identity on every state change and time tick.
  ///
  /// Held strongly on purpose: a layer that failed with its PiP window open still has
  /// to report that the window closed. It is dropped as soon as that arrives, and at
  /// once when a layer is released for good.
  private var pipController: AVPictureInPictureController?
  /// The layer `pipController` was taken from.
  private weak var pipControllerLayer: KSPlayerLayer?
  private var pipPossibleObservation: NSKeyValueObservation?

  /// Same key `makeOptions` reads. With PiP switched off no controller is created.
  private static var isPictureInPictureEnabledInSettings: Bool {
    UserDefaults.standard.object(forKey: "player.pipEnabled") as? Bool ?? true
  }

  /// Opens the PiP window over the app; the app stays in front. Does nothing while
  /// the player is not ready. When the system refuses, `isPiPActive` stays false.
  func startPictureInPicture() {
    guard !isDisposed, let controller = adoptPictureInPictureController(),
          !controller.isPictureInPictureActive
    else { return }
    controller.startPictureInPicture()
  }

  func stopPictureInPicture() {
    pipController?.stopPictureInPicture()
  }

  func setPictureInPictureActive(_ active: Bool) {
    if active {
      startPictureInPicture()
    } else {
      stopPictureInPicture()
    }
  }

  func togglePictureInPicture() {
    // Asked of the controller, not of a flag of ours: after the window was closed
    // with its X the next tap has to open it again.
    setPictureInPictureActive(!(pipController?.isPictureInPictureActive ?? false))
  }

  /// Called on every state change and time tick of the layer.
  private func refreshPiPState() {
    guard let layer else {
      releasePictureInPictureController()
      return
    }
    if pipController != nil, pipControllerLayer !== layer {
      // Left over from the previous load.
      releasePictureInPictureController()
    }
    // Not before the player is ready: reading `pipController` creates it, and the
    // FFmpeg player builds its own on the video output.
    guard layer.player.isReadyToPlay,
          pipController != nil || Self.isPictureInPictureEnabledInSettings
    else { return }
    adoptPictureInPictureController()
    publishPictureInPictureTransport(on: layer)
  }

  /// Makes the engine the delegate of the current player's PiP controller.
  @discardableResult
  private func adoptPictureInPictureController() -> AVPictureInPictureController? {
    guard let layer, layer.player.isReadyToPlay,
          let controller = layer.player.pipController
    else { return nil }
    if controller === pipController { return controller }
    releasePictureInPictureController()
    pipController = controller
    pipControllerLayer = layer
    controller.delegate = self
    // `KSPlayerLayer` sets this once, on the controller that exists when the player
    // becomes ready. One built later (display layer change) would lose automatic PiP.
    let automatic = guardedOptions?.canStartPictureInPictureAutomaticallyFromInline ?? false
    if controller.canStartPictureInPictureAutomaticallyFromInline != automatic {
      controller.canStartPictureInPictureAutomaticallyFromInline = automatic
    }
    pipPossibleObservation = controller.observe(\.isPictureInPicturePossible) { [weak self] _, _ in
      DispatchQueue.main.async { self?.pictureInPicturePossibleDidChange() }
    }
    let active = controller.isPictureInPictureActive
    if isPiPActive != active { isPiPActive = active }
    let possible = controller.isPictureInPicturePossible
    if isPictureInPicturePossible != possible { isPictureInPicturePossible = possible }
    return controller
  }

  private func releasePictureInPictureController() {
    pipPossibleObservation?.invalidate()
    pipPossibleObservation = nil
    if let controller = pipController, controller.delegate === self {
      controller.delegate = nil
    }
    pipController = nil
    pipControllerLayer = nil
    if isPiPActive { isPiPActive = false }
    if isPictureInPicturePossible { isPictureInPicturePossible = false }
  }

  /// True once the layer the controller came from has been replaced or released
  /// (new load, stop for a cast, dispose): nothing will start PiP on it again.
  private var isPictureInPictureControllerOrphaned: Bool {
    guard pipController != nil else { return false }
    return pipControllerLayer == nil || pipControllerLayer !== layer
  }

  private func pictureInPicturePossibleDidChange() {
    if isPictureInPictureControllerOrphaned {
      releasePictureInPictureController()
      return
    }
    let possible = pipController?.isPictureInPicturePossible ?? false
    if isPictureInPicturePossible != possible { isPictureInPicturePossible = possible }
  }

  /// Delegate callbacks, already on the main thread. `controllerID` filters out a
  /// controller the engine has let go of in the meantime.
  private func pictureInPictureDidChange(
    controllerID: ObjectIdentifier, active: Bool, stopped: Bool
  ) {
    guard let controller = pipController, ObjectIdentifier(controller) == controllerID
    else { return }
    if isPictureInPictureControllerOrphaned {
      releasePictureInPictureController()
      return
    }
    if isPiPActive != active { isPiPActive = active }
    if stopped, !isDisposed, let layer {
      reconcileTransportAfterPictureInPicture(on: layer)
    }
  }

  /// What the player itself is doing, or nil when that cannot be told apart from a
  /// seek or a stall. The PiP window's play/pause button drives the player directly:
  /// `KSPlayerLayer.state`, and with it `isPaused`, never hears of it.
  private static func playerIsPlaying(_ player: MediaPlayerProtocol) -> Bool? {
    if let avPlayer = player as? KSAVPlayer {
      if avPlayer.player.rate > 0 { return true }
      // The system pauses the AVPlayer behind KSPlayer's back, which still believes
      // it is playing. A stalled item also has rate 0, but is not playable.
      return avPlayer.playbackState == .playing && avPlayer.loadState == .playable ? false : nil
    }
    switch player.playbackState {
    case .playing: return true
    case .paused: return false
    case .idle, .seeking, .finished, .stopped: return nil
    }
  }

  /// While the window is up only the published flag follows the player; the layer is
  /// left alone so its time ticks keep coming and a later "play" is seen as well.
  private func publishPictureInPictureTransport(on layer: KSPlayerLayer) {
    guard isPiPActive, !startSeekHoldsTransport, pendingSeekTarget == nil,
          let playing = Self.playerIsPlaying(layer.player)
    else { return }
    if isPaused == playing { isPaused = !playing }
  }

  /// PiP ended: bring the layer in line with what the window's button left behind,
  /// so the in-app transport, the idle timer and the time ticks match the player.
  private func reconcileTransportAfterPictureInPicture(on layer: KSPlayerLayer) {
    guard layer.player.isReadyToPlay, pendingSeekTarget == nil,
          let playing = Self.playerIsPlaying(layer.player)
    else { return }
    switch layer.state {
    case .buffering, .bufferFinished:
      if !playing { layer.pause() }
    case .paused:
      if playing { layer.play() }
    case .initialized, .preparing, .readyToPlay, .playedToTheEnd, .error:
      break
    }
  }

  // MARK: - Tracks

  func reloadTrackList(
    completion: @escaping (
      [TrackMenuOption], [TrackMenuOption], [TrackMenuOption], Int, Int, Int
    ) -> Void
  ) {
    guard let player = layer?.player else {
      completion([], [], [TrackMenuOption(id: -1, title: L("player.subtitle_off"))], -1, -1, -1)
      return
    }
    attachEmbeddedSubtitleSourceIfNeeded()
    if isAwaitingMediaSelection {
      // The AVPlayer renditions are still loading, a few run-loop turns once the item
      // is ready. Answering now would list no captions or alternate audio, and the
      // owner would apply the saved preferences to that incomplete list.
      deferredTrackListRequests.append { [weak self] in
        self?.reloadTrackList(completion: completion)
      }
      return
    }
    let renditions = activeMediaSelection()
    let locale = Self.trackDisplayLocale

    let videoTracks = selectableTracks(.video, of: player)
    let audioTracks = selectableTracks(.audio, of: player)

    let video = videoTracks.enumerated().map {
      Self.menuOption(for: $1, position: $0 + 1, locale: locale)
    }
    let currentVideo = videoTracks.first { $0.isEnabled }.map { Int($0.trackID) } ?? -1

    let audio: [TrackMenuOption]
    let currentAudio: Int
    if let (item, selection) = renditions, let group = selection.audibleGroup,
       !selection.audibleOptions.isEmpty {
      // Alternate audio of an HLS stream is a set of renditions, not item tracks:
      // the item only ever carries the track of the rendition that is playing.
      audio = selection.audibleOptions.enumerated().map {
        Self.menuOption(
          for: $1, id: Self.audibleOptionIDBase + $0, position: $0 + 1, locale: locale
        )
      }
      currentAudio = item.currentMediaSelection.selectedMediaOption(in: group)
        .flatMap { selection.audibleOptions.firstIndex(of: $0) }
        .map { Self.audibleOptionIDBase + $0 } ?? -1
    } else {
      audio = audioTracks.enumerated().map {
        Self.menuOption(for: $1, position: $0 + 1, locale: locale)
      }
      currentAudio = audioTracks.first { $0.isEnabled }.map { Int($0.trackID) } ?? -1
    }

    var subs: [TrackMenuOption] = [TrackMenuOption(id: -1, title: L("player.subtitle_off"))]
    subtitleInfosById = [:]
    var currentSubId = -1
    if let (item, selection) = renditions, let group = selection.legibleGroup {
      let selected = item.currentMediaSelection.selectedMediaOption(in: group)
      for (index, option) in selection.legibleOptions.enumerated() {
        let id = Self.legibleOptionIDBase + index
        subs.append(Self.menuOption(for: option, id: id, position: index + 1, locale: locale))
        if let selected, selected == option { currentSubId = id }
      }
    }
    var nextId = 0
    for info in subtitleModel.subtitleInfos {
      if removedSubtitleIDs.contains(info.subtitleID) { continue }
      let id = nextId
      nextId += 1
      subtitleInfosById[id] = info
      subs.append(
        Self.menuOption(
          for: info,
          id: id,
          isExternal: externalSubtitleIDs.contains(info.subtitleID),
          locale: locale
        )
      )
      if subtitleModel.selectedSubtitleInfo?.subtitleID == info.subtitleID {
        currentSubId = id
      }
    }

    completion(video, audio, subs, currentVideo, currentAudio, currentSubId)
  }

  /// Language names follow the app's language rather than the device's, like every
  /// other text of the track sheet (`L()`).
  private static var trackDisplayLocale: Locale {
    Locale(identifier: LocalizationManager.shared.effectiveLanguageCode)
  }

  /// - Parameter position: 1-based place in its list, for the "Track N" fallback.
  private static func menuOption(
    for track: MediaPlayerTrack, position: Int, locale: Locale
  ) -> TrackMenuOption {
    let codecName = (track as? FFmpegAssetTrack)?.codecName
    // KSPlayer fills a missing title with the language code or the codec name. Such a
    // row is named after its language instead, and a fallback like "Track N" must not
    // be stored as a preference (see TrackMenuOption.isSyntheticTitle).
    let title = TrackNaming.title(
      name: track.name,
      languageCode: track.languageCode,
      codecName: codecName,
      fallback: L("player.tracks.fallback_title", position),
      locale: locale
    )
    var detailParts: [String] = []
    if let language = TrackNaming.detailLanguageName(
      for: title, languageCode: track.languageCode, locale: locale
    ) {
      detailParts.append(language)
    }
    if let codec = TrackNaming.codecLabel(codecName) {
      detailParts.append(codec)
    }
    if track.mediaType == .video {
      let size = track.formatDescription.map { CMVideoFormatDescriptionGetDimensions($0) }
      if let size, size.width > 0 {
        detailParts.append("\(size.width)×\(size.height)")
      }
    }
    if track.mediaType == .audio,
       let channels = track.audioStreamBasicDescription?.mChannelsPerFrame, channels > 0 {
      detailParts.append(L("player.tracks.channels", Int(channels)))
    }
    if track.bitRate > 0 {
      detailParts.append("\(track.bitRate / 1000) kbps")
    }
    return TrackMenuOption(
      id: Int(track.trackID),
      title: title.text,
      detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
      langCode: track.languageCode,
      isSyntheticTitle: title.isSynthetic
    )
  }

  /// Subtitle rows. Embedded tracks of the FFmpeg player are `MediaPlayerTrack`s and
  /// carry a language, which is what a subtitle preference is matched by. Imported
  /// and sidecar files keep their file name.
  private static func menuOption(
    for info: any SubtitleInfo, id: Int, isExternal: Bool, locale: Locale
  ) -> TrackMenuOption {
    guard !isExternal, let track = info as? MediaPlayerTrack else {
      return TrackMenuOption(id: id, title: info.name, isExternal: isExternal)
    }
    let codecName = (track as? FFmpegAssetTrack)?.codecName
    let title = TrackNaming.title(
      name: track.name,
      languageCode: track.languageCode,
      codecName: codecName,
      fallback: L("player.tracks.fallback_title", id + 1),
      locale: locale
    )
    let detailParts = [
      TrackNaming.detailLanguageName(for: title, languageCode: track.languageCode, locale: locale),
      TrackNaming.codecLabel(codecName),
    ].compactMap { $0 }
    return TrackMenuOption(
      id: id,
      title: title.text,
      detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
      langCode: track.languageCode,
      isSyntheticTitle: title.isSynthetic
    )
  }

  /// A rendition of the AVPlayer item (see "AVPlayer renditions").
  private static func menuOption(
    for option: AVMediaSelectionOption, id: Int, position: Int, locale: Locale
  ) -> TrackMenuOption {
    let name = option.displayName(with: locale).trimmingCharacters(in: .whitespacesAndNewlines)
    let languageTag = option.extendedLanguageTag.flatMap { $0.lowercased() == "und" ? nil : $0 }
    return TrackMenuOption(
      id: id,
      title: name.isEmpty ? L("player.tracks.fallback_title", position) : name,
      langCode: languageTag,
      // The name is localized. With a language tag the preference is stored by
      // language; without one the name comes from the stream and may be stored.
      isSyntheticTitle: name.isEmpty || languageTag != nil
    )
  }

  // MARK: - AVPlayer renditions

  // KSAVPlayer exposes no subtitle source and lists only the item's own tracks.
  // Captions and alternate audio of an AVPlayer item (HLS renditions, mp4 text
  // tracks) are media selection options instead. They are selected on the item,
  // never through `select(track:)`, and the captions are drawn by AVPlayerLayer
  // itself: the app's subtitle appearance and time offset do not apply to them.

  /// Ids of rendition rows start far above any track id (stream indexes and
  /// AVAssetTrack ids) and above the running ids of the subtitle list.
  private static let audibleOptionIDBase = 1_000_000
  private static let legibleOptionIDBase = 2_000_000
  /// The groups come with an item that is ready, so loading them is quick; this only
  /// keeps a hung asset from holding back the track list.
  private static let mediaSelectionLoadTimeout: TimeInterval = 2

  private struct AVPlayerMediaSelection {
    weak var item: AVPlayerItem?
    var audibleGroup: AVMediaSelectionGroup?
    var audibleOptions: [AVMediaSelectionOption] = []
    var legibleGroup: AVMediaSelectionGroup?
    var legibleOptions: [AVMediaSelectionOption] = []
  }

  /// Renditions of one AVPlayer item. Loading is asynchronous while
  /// `reloadTrackList` builds its lists synchronously, hence the cache. It is keyed
  /// by the item, so a new load needs no reset.
  private var mediaSelection: AVPlayerMediaSelection?
  /// The item whose renditions are being loaded.
  private weak var mediaSelectionLoadingItem: AVPlayerItem?
  /// Track list requests that arrived while the renditions were loading.
  private var deferredTrackListRequests: [() -> Void] = []

  private var currentAVPlayerItem: AVPlayerItem? {
    (layer?.player as? KSAVPlayer)?.player.currentItem
  }

  private var isAwaitingMediaSelection: Bool {
    guard let loading = mediaSelectionLoadingItem else { return false }
    return currentAVPlayerItem === loading
  }

  /// The cached renditions, when they belong to the item that is playing.
  private func activeMediaSelection() -> (AVPlayerItem, AVPlayerMediaSelection)? {
    guard let selection = mediaSelection, let item = selection.item,
          currentAVPlayerItem === item
    else { return nil }
    return (item, selection)
  }

  /// Once per item, as soon as it is ready.
  private func loadMediaSelectionIfNeeded() {
    guard let avPlayer = layer?.player as? KSAVPlayer, avPlayer.isReadyToPlay,
          let item = avPlayer.player.currentItem,
          mediaSelection?.item !== item, mediaSelectionLoadingItem !== item
    else { return }
    mediaSelection = nil
    mediaSelectionLoadingItem = item
    let asset = item.asset
    Task { [weak self] in
      let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
      let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
      self?.mediaSelectionDidLoad(for: item, audible: audible, legible: legible, timedOut: false)
    }
    let timeout = DispatchWorkItem { [weak self] in
      self?.mediaSelectionDidLoad(for: item, audible: nil, legible: nil, timedOut: true)
    }
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.mediaSelectionLoadTimeout, execute: timeout
    )
  }

  private func mediaSelectionDidLoad(
    for item: AVPlayerItem,
    audible: AVMediaSelectionGroup?,
    legible: AVMediaSelectionGroup?,
    timedOut: Bool
  ) {
    let wasAwaited = mediaSelectionLoadingItem === item
    // The timeout only matters while the load is still awaited.
    if timedOut, !wasAwaited { return }
    if wasAwaited { mediaSelectionLoadingItem = nil }
    if !isDisposed, currentAVPlayerItem === item {
      var selection = AVPlayerMediaSelection()
      selection.item = item
      if !timedOut {
        selection.audibleGroup = audible
        selection.audibleOptions = audible.map {
          AVMediaSelectionGroup.playableMediaSelectionOptions(from: $0.options)
        } ?? []
        selection.legibleGroup = legible
        // Forced-only renditions are picked by the system next to the audio
        // language; they are not something to choose from a list.
        selection.legibleOptions = legible.map {
          AVMediaSelectionGroup.mediaSelectionOptions(
            from: AVMediaSelectionGroup.playableMediaSelectionOptions(from: $0.options),
            withoutMediaCharacteristics: [.containsOnlyForcedSubtitles]
          )
        } ?? []
      }
      // After a timeout an empty entry is kept, so the load is not started over on
      // every request; a late answer still replaces it.
      mediaSelection = selection
      // An imported subtitle was selected before the renditions were known.
      if subtitleModel.selectedSubtitleInfo != nil { selectLegibleOption(nil) }
    }
    let requests = deferredTrackListRequests
    deferredTrackListRequests = []
    requests.forEach { $0() }
  }

  /// After an explicit choice AVPlayer has to stop applying the system's language
  /// and caption preferences, or it selects again by itself and subtitles that were
  /// switched off come back.
  private func stopAutomaticMediaSelection() {
    guard let player = (layer?.player as? KSAVPlayer)?.player,
          player.appliesMediaSelectionCriteriaAutomatically
    else { return }
    player.appliesMediaSelectionCriteriaAutomatically = false
  }

  private func selectAudibleOption(id: Int) {
    guard let (item, selection) = activeMediaSelection(), let group = selection.audibleGroup,
          selection.audibleOptions.indices.contains(id - Self.audibleOptionIDBase)
    else { return }
    let option = selection.audibleOptions[id - Self.audibleOptionIDBase]
    stopAutomaticMediaSelection()
    if item.currentMediaSelection.selectedMediaOption(in: group) != option {
      item.select(option, in: group)
    }
  }

  /// `nil` switches the stream's own captions off. Does nothing on the FFmpeg player
  /// and for items without captions.
  private func selectLegibleOption(_ option: AVMediaSelectionOption?) {
    guard let (item, selection) = activeMediaSelection(), let group = selection.legibleGroup
    else { return }
    stopAutomaticMediaSelection()
    if item.currentMediaSelection.selectedMediaOption(in: group) != option {
      item.select(option, in: group)
    }
  }

  /// Tracks FFmpeg has no working decoder for are left out: enabling one makes
  /// KSPlayer keep a dead decoder that crashes on the next seek. Only the FFmpeg
  /// engine is filtered — AVPlayer track ids live in a different namespace.
  private func selectableTracks(
    _ mediaType: AVFoundation.AVMediaType, of player: MediaPlayerProtocol
  ) -> [MediaPlayerTrack] {
    let tracks = player.tracks(mediaType: mediaType)
    guard player is KSMEPlayer, let undecodable = guardedOptions?.undecodableTrackIDs,
          !undecodable.isEmpty
    else { return tracks }
    return tracks.filter { !undecodable.contains($0.trackID) }
  }

  func selectVideoTrack(id: Int) {
    guard let player = layer?.player,
          let track = selectableTracks(.video, of: player).first(where: { Int($0.trackID) == id })
    else { return }
    // Selecting the track that is already playing is not free: AVPlayer toggles it
    // off and on, and the owner re-applies the saved preference on every load.
    if !track.isEnabled {
      player.select(track: track)
      // Another track is enabled now: publish its codec without waiting for the
      // next heartbeat of the time tick.
      refreshDiagnostics()
    }
  }

  func selectAudioTrack(id: Int) {
    if id >= Self.audibleOptionIDBase {
      selectAudibleOption(id: id)
      return
    }
    guard let player = layer?.player,
          let track = selectableTracks(.audio, of: player).first(where: { Int($0.trackID) == id })
    else { return }
    // Usually the preferred language is already the one playback started with
    // (chosen while the source opened); selecting again would cost a seek and an
    // audio flush on the FFmpeg player.
    if !track.isEnabled {
      player.select(track: track)
      // As for a video track: the audio codec decides whether the stream can be cast.
      refreshDiagnostics()
    }
    applyAudioDelay()
  }

  func selectSubtitleTrack(id: Int) {
    if id < 0 {
      deselectSubtitleInfo()
      selectLegibleOption(nil)
      return
    }
    if id >= Self.legibleOptionIDBase {
      guard let (_, selection) = activeMediaSelection(),
            selection.legibleOptions.indices.contains(id - Self.legibleOptionIDBase)
      else { return }
      // The stream's captions are drawn by AVPlayerLayer. A file that stayed
      // selected would be drawn over them by the app's own overlay.
      deselectSubtitleInfo()
      selectLegibleOption(selection.legibleOptions[id - Self.legibleOptionIDBase])
      return
    }
    guard let info = subtitleInfosById[id] else { return }
    subtitleModel.selectedSubtitleInfo = info
    // And the other way round: only one subtitle at a time.
    selectLegibleOption(nil)
  }

  private func deselectSubtitleInfo() {
    subtitleModel.selectedSubtitleInfo = nil
    if subtitleText != nil { subtitleText = nil }
    if subtitleImage != nil { subtitleImage = nil }
    if subtitleImageOrigin != .zero { subtitleImageOrigin = .zero }
  }

  // MARK: - Subtitles

  /// Called when the player becomes ready and again for every track list. The FFmpeg
  /// player is itself the source of its embedded subtitle tracks; AVPlayer has none
  /// and carries its captions as renditions, which are loaded from here as well.
  private func attachEmbeddedSubtitleSourceIfNeeded() {
    loadMediaSelectionIfNeeded()
    guard !embeddedSubtitleSourceAttached,
          let dataSource = layer?.player.subtitleDataSouce
    else { return }
    embeddedSubtitleSourceAttached = true
    subtitleModel.addSubtitle(dataSouce: dataSource)
  }

  func addExternalSubtitle(filePath: String, title: String, select: Bool) {
    let url = URL(fileURLWithPath: filePath)
    let info = URLSubtitleInfo(subtitleID: url.absoluteString, name: title, url: url)
    removedSubtitleIDs.remove(info.subtitleID)
    externalSubtitleIDs.insert(info.subtitleID)
    subtitleModel.addSubtitle(info: info)
    if select {
      subtitleModel.selectedSubtitleInfo = info
      // Not next to the stream's own captions. When the renditions are not loaded
      // yet, `mediaSelectionDidLoad` does this.
      selectLegibleOption(nil)
    }
  }

  func removeExternalSubtitle(id: Int) {
    guard let info = subtitleInfosById[id] else { return }
    // SubtitleModel has no removal API; hide the entry and drop the selection.
    removedSubtitleIDs.insert(info.subtitleID)
    if subtitleModel.selectedSubtitleInfo?.subtitleID == info.subtitleID {
      subtitleModel.selectedSubtitleInfo = nil
      subtitleText = nil
      subtitleImage = nil
      subtitleImageOrigin = .zero
    }
  }

  func setSubDelay(seconds: Double) {
    subtitleModel.subtitleDelay = seconds
  }

  /// Positive values delay the audio. Kept across loads and re-applied when the next
  /// one is ready; see `supportsAudioDelay` for when it has an effect.
  func setAudioDelay(seconds: Double) {
    pendingAudioDelay = seconds
    applyAudioDelay()
  }

  /// KSMEPlayer only. `KSOptions.videoDelay` shifts video against the audio clock and
  /// is read for every frame from the options object the player already holds, so a
  /// change takes effect at once. Delaying the audio means showing video early, hence
  /// the negated value. Without an enabled audio track the player paces video against
  /// its own clock and any offset would turn into slow motion or dropped frames.
  private func applyAudioDelay() {
    guard let options = guardedOptions else { return }
    let player = layer?.player
    let isFFmpegPlayer = player is KSMEPlayer
    // KSPlayer's open thread fills the track list; it is safe to read once ready.
    var hasEnabledAudioTrack = false
    if isFFmpegPlayer, let player, player.isReadyToPlay {
      hasEnabledAudioTrack = player.tracks(mediaType: .audio).contains(where: { $0.isEnabled })
    }
    let delay = KSPlayerEngineMath.videoDelay(
      forAudioDelay: pendingAudioDelay,
      isFFmpegPlayer: isFFmpegPlayer,
      hasEnabledAudioTrack: hasEnabledAudioTrack
    )
    if options.videoDelay != delay { options.videoDelay = delay }
  }

  /// Appearance only. The subtitle time offset belongs to the content being played
  /// and is set by the owner through `setSubDelay(seconds:)`.
  func applySubtitleAppearanceFromSettings(_ settings: SubtitleAppearanceSettings) {
    if subtitleAppearance != settings { subtitleAppearance = settings }
  }

  /// Drives the subtitle overlay from an external clock — used while a cast
  /// engagement is presenting (the layer is stopped, but external SRT subtitles
  /// can still be rendered over the cast placeholder).
  func updateSubtitleCue(at seconds: TimeInterval) {
    guard !isDisposed else { return }
    if subtitleModel.subtitle(currentTime: seconds) {
      publishSubtitleParts()
    }
  }

  /// Publishes the cues `subtitleModel` holds for the current time.
  private func publishSubtitleParts() {
    let parts = subtitleModel.parts
    let text = Self.mergedSubtitleText(parts.compactMap(\.text))
    if subtitleText != text { subtitleText = text }
    // Bitmap cues (PGS/DVB) are not merged; the first one is shown, as before.
    let imagePart = parts.first { $0.image != nil }
    if subtitleImage !== imagePart?.image { subtitleImage = imagePart?.image }
    let origin = imagePart?.origin ?? .zero
    if subtitleImageOrigin != origin { subtitleImageOrigin = origin }
  }

  /// At most this many text cues are shown at the same time.
  static let maxSimultaneousSubtitleCues = 4

  /// Cues that overlap in time (two speakers, a sign over dialogue) arrive as separate
  /// parts. They are stacked into one block in the order the subtitle lists them. A
  /// line repeated across parts is shown once (ASS files layer the same text for
  /// effects), and the block is capped so a heavily typeset scene cannot fill the
  /// picture.
  static func mergedSubtitleText(_ texts: [NSAttributedString]) -> NSAttributedString? {
    var seen = Set<String>()
    var lines: [NSAttributedString] = []
    for text in texts {
      let string = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !string.isEmpty, seen.insert(string).inserted else { continue }
      lines.append(text)
      if lines.count == maxSimultaneousSubtitleCues { break }
    }
    guard lines.count > 1 else { return lines.first }
    let merged = NSMutableAttributedString()
    for (index, line) in lines.enumerated() {
      if index > 0 { merged.append(NSAttributedString(string: "\n")) }
      merged.append(line)
    }
    return merged
  }

  // MARK: - Watchdog

  private func scheduleLoadTimeoutWatchdog() {
    cancelLoadTimeoutWatchdog()
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.isDisposed else { return }
      if !self.isPlaybackEstablished, self.playbackFailureMessage == nil {
        self.publishFailure(message: L("playback.error.timeout"), recoverable: true)
      }
    }
    loadTimeoutWorkItem = item
    // Kept strictly above the 10s FFmpeg rw_timeout so its specific error surfaces first;
    // trimmed from 16s so a dead channel doesn't spin the spinner as long.
    DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: item)
  }

  private func cancelLoadTimeoutWatchdog() {
    loadTimeoutWorkItem?.cancel()
    loadTimeoutWorkItem = nil
  }

  // MARK: - Watchdog (after ready, FFmpeg player)

  /// The load watchdog above ends when the source reports ready, which the FFmpeg
  /// player does before it has decoded anything. From there on this one watches for a
  /// first frame that never comes and for a rebuffer that never ends. AVPlayer has
  /// its own stall handling and, in external playback, reports buffering on the phone
  /// while the TV plays, so it is left alone.
  private var playbackWatchdogWorkItem: DispatchWorkItem?
  private var playbackWatchdog = KSPlayerLoadPolicy.ProgressWatchdog(isLive: false)

  private func startPlaybackWatchdog(on layer: KSPlayerLayer) {
    cancelPlaybackWatchdog()
    guard layer.player is KSMEPlayer else { return }
    playbackWatchdog = KSPlayerLoadPolicy.ProgressWatchdog(isLive: isLiveWithoutDuration(layer))
    schedulePlaybackWatchdogTick()
  }

  private func cancelPlaybackWatchdog() {
    playbackWatchdogWorkItem?.cancel()
    playbackWatchdogWorkItem = nil
  }

  private func schedulePlaybackWatchdogTick() {
    let item = DispatchWorkItem { [weak self] in
      self?.playbackWatchdogTick()
    }
    playbackWatchdogWorkItem = item
    DispatchQueue.main.asyncAfter(
      deadline: .now() + KSPlayerLoadPolicy.ProgressWatchdog.tickInterval, execute: item
    )
  }

  /// Counts ticks rather than wall time: while iOS has the app suspended no tick
  /// runs, so the time spent suspended is not mistaken for a stall.
  private func playbackWatchdogTick() {
    playbackWatchdogWorkItem = nil
    guard !isDisposed, let layer, let player = layer.player as? KSMEPlayer else { return }
    let state = layer.state
    // A live stream that ended while the video track is switched off for the
    // background: the audio has drained, but KSPlayer never calls `finish`, because
    // the suspended track's stale frames keep its queue from emptying. Live only: a
    // VOD item is left as it is and resynced by the seek on return to the foreground.
    if guardedOptions?.hasAudioEndedWhileVideoSuspended == true, state.isPlaying,
       endedAsLiveStream(on: layer) {
      cancelLoadTimeoutWatchdog()
      reportLiveStreamEnd()
      // No further ticks, as after `finish(error:)`.
      return
    }
    let sample = KSPlayerLoadPolicy.ProgressWatchdog.Sample(
      isPlaying: state.isPlaying,
      // During a seek the layer keeps its last state; the player's own flag still
      // says whether it has frames to show.
      isBuffering: state == .buffering || player.loadState != .playable,
      bytesRead: player.dynamicInfo?.bytesRead ?? 0,
      playableTime: player.playableTime
    )
    switch playbackWatchdog.tick(sample) {
    case .healthy:
      schedulePlaybackWatchdogTick()
    case .firstFrameTimeout, .stalled:
      failAndRetireLayer(message: L("playback.error.timeout"), recoverable: true)
    }
  }

  /// A live load that reports no length. A finite file the playlist merely labelled
  /// live has one and is treated as VOD.
  private func isLiveWithoutDuration(_ layer: KSPlayerLayer) -> Bool {
    KSPlayerEngineMath.isLiveStreamEnd(
      isLive: currentLoadIsLive, duration: knownDuration(of: layer)
    )
  }

  /// FFmpeg path: a media type whose every track lacks a decoder never fills its
  /// queue, so the player would buffer forever while the reader keeps queueing the
  /// other track.
  private func hasUndecodableMediaType(_ player: MediaPlayerProtocol) -> Bool {
    guard player is KSMEPlayer, let undecodable = guardedOptions?.undecodableTrackIDs,
          !undecodable.isEmpty
    else { return false }
    // Cover art in an audio file is left out: with it the audio still starts once the
    // reader has reached the end of the file, as it did before.
    let videoTrackIDs = player.tracks(mediaType: .video)
      .filter { track in
        !KSPlayerLoadPolicy.isStillImageCodec((track as? FFmpegAssetTrack)?.codecName ?? "")
      }
      .map(\.trackID)
    return KSPlayerLoadPolicy.hasUndecodableMediaType(
      videoTrackIDs: videoTrackIDs,
      audioTrackIDs: player.tracks(mediaType: .audio).map(\.trackID),
      undecodable: undecodable
    )
  }

  // MARK: - Background (FFmpeg player)

  /// KSPlayer does nothing for its FFmpeg player when the app leaves the foreground
  /// (`KSMEPlayer.enterBackground()` is empty). The audio keeps playing, the display
  /// link stops drawing, the decoder blocks on its full frame queue and the reader
  /// keeps queueing video packets for as long as the app stays away; on return the
  /// picture replays that backlog. The engine therefore switches the video track off
  /// itself and brings the picture back in sync on return.
  private var observesAppLifecycle = false
  private var isAppInBackground = false
  private var backgroundSuspendWorkItem: DispatchWorkItem?
  /// The video track switched off for the background. Only this one is switched
  /// back on.
  private var backgroundSuspendedTrack: MediaPlayerTrack?

  private func observeAppLifecycleIfNeeded() {
    guard !observesAppLifecycle else { return }
    observesAppLifecycle = true
    isAppInBackground = UIApplication.shared.applicationState == .background
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil
    )
    center.addObserver(
      self, selector: #selector(appWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil
    )
  }

  @objc private func appDidEnterBackground() {
    isAppInBackground = true
    scheduleBackgroundVideoSuspension()
  }

  @objc private func appWillEnterForeground() {
    isAppInBackground = false
    backgroundSuspendWorkItem?.cancel()
    backgroundSuspendWorkItem = nil
    resumeVideoAfterBackground()
  }

  /// Not at once: automatic PiP starts around the moment the app enters the
  /// background, and a short absence is not worth the resync on return.
  private func scheduleBackgroundVideoSuspension() {
    backgroundSuspendWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.backgroundSuspendWorkItem = nil
      self.suspendVideoForBackgroundIfNeeded()
    }
    backgroundSuspendWorkItem = item
    DispatchQueue.main.asyncAfter(
      deadline: .now() + KSPlayerLoadPolicy.backgroundSuspendDelay, execute: item
    )
  }

  /// For playback that starts or resumes while the app is already in the background
  /// (lock-screen play, next channel from the lock screen).
  private func scheduleBackgroundVideoSuspensionIfIdle() {
    guard isAppInBackground, backgroundSuspendWorkItem == nil, backgroundSuspendedTrack == nil
    else { return }
    scheduleBackgroundVideoSuspension()
  }

  private func suspendVideoForBackgroundIfNeeded() {
    guard !isDisposed, isAppInBackground, backgroundSuspendedTrack == nil,
          let layer, let player = layer.player as? KSMEPlayer, player.isReadyToPlay,
          let options = guardedOptions
    else { return }
    let videoTrack = player.tracks(mediaType: .video).first(where: { $0.isEnabled })
    // The player's own controller is asked as well, in case automatic PiP started on
    // one the engine has not adopted yet. Only with automatic PiP on: KSPlayerLayer
    // has then created that controller already, and reading it would create it.
    let automaticPiP = options.canStartPictureInPictureAutomaticallyFromInline
    let action = KSPlayerLoadPolicy.backgroundAction(
      isPlaying: layer.state.isPlaying,
      isPictureInPictureActive: isPiPActive || layer.isPipActive
        || (automaticPiP && player.pipController?.isPictureInPictureActive == true),
      hasEnabledVideoTrack: videoTrack != nil,
      hasEnabledAudioTrack: player.tracks(mediaType: .audio).contains(where: { $0.isEnabled }),
      isLive: isLiveWithoutDuration(layer),
      isSeekable: player.seekable,
      seeksByBytes: DemuxerProbe.seeksByBytes(formatName: options.formatName)
    )
    switch action {
    case .leave:
      break
    case .checkAgain:
      scheduleBackgroundVideoSuspension()
    case .suspendVideo:
      guard let videoTrack else { return }
      // Marks the stream as discarded: the demuxer and KSPlayer's reader drop its
      // packets from here on.
      videoTrack.isEnabled = false
      options.isVideoSuspended = true
      backgroundSuspendedTrack = videoTrack
    }
  }

  private func resumeVideoAfterBackground() {
    guard let track = backgroundSuspendedTrack else { return }
    backgroundSuspendedTrack = nil
    guardedOptions?.isVideoSuspended = false
    guard !isDisposed, let layer, let player = layer.player as? KSMEPlayer,
          player.tracks(mediaType: .video).contains(where: { $0 === track })
    else { return }
    let action = KSPlayerLoadPolicy.foregroundAction(
      isPlaying: layer.state.isPlaying,
      isLive: isLiveWithoutDuration(layer),
      canReload: onReloadRequested != nil,
      canSeek: Self.canSeek(layer)
    )
    switch action {
    case .reload:
      // A fresh load starts at the live edge with an empty decoder. The track is
      // switched back on first in case the owner declines the reload.
      track.isEnabled = true
      onReloadRequested?()
    case .seekToCurrentPosition:
      // The seek flushes the packets and frames that piled up before the track was
      // switched off; the picture restarts at the keyframe before the position.
      track.isEnabled = true
      let current = player.currentPlaybackTime
      seek(to: current.isFinite ? current : position)
    case .reselectTrack:
      // KSPlayer's own track switch: enables the track and flushes every queue,
      // without changing the play/pause state.
      player.select(track: track)
      refreshDiagnostics()
    }
  }

  /// The layer is going away or failed: forget the suspension without touching the
  /// track.
  private func endBackgroundVideoSuspension() {
    backgroundSuspendedTrack = nil
    guardedOptions?.isVideoSuspended = false
  }

  private func bumpSurfaceRevision() {
    surfaceRevision += 1
  }

  /// The numbers that change while a stream plays (size, frame rate, drop counts).
  /// Cheap enough for every time tick.
  ///
  /// - Parameter trackFacts: also re-read the track list first, see `refreshTrackFacts`.
  ///   The time tick asks for that only now and then.
  private func refreshDiagnostics(trackFacts: Bool = true) {
    guard let player = layer?.player else { return }
    if trackFacts { refreshTrackFacts(of: player) }
    var size = player.naturalSize
    // AVPlayer's naturalSize is the encoded (unrotated) frame — it never consults the
    // track's preferredTransform, unlike the FFmpeg path's display-matrix handling.
    // The rotation itself is looked up with the track facts and cached.
    if player is KSAVPlayer, avTrackIsQuarterRotated {
      size = CGSize(width: size.height, height: size.width)
    }
    let w = Int(size.width)
    let h = Int(size.height)
    // A layer that is still preparing has no size yet. Publishing that zero made the
    // surface fall back to 16:9 and jump again once the stream reported its own
    // size, so the previous size stays until the new stream has one.
    if w > 0, h > 0 {
      if videoDisplayWidth != w { videoDisplayWidth = w }
      if videoDisplayHeight != h { videoDisplayHeight = h }
    }
    if let info = player.dynamicInfo {
      if renderFPS != info.displayFPS { renderFPS = info.displayFPS }
      let dropped = Int64(info.droppedVideoFrameCount)
      if droppedFrameCount != dropped { droppedFrameCount = dropped }
      if avSyncSeconds != info.audioVideoSyncDiff { avSyncSeconds = info.audioVideoSyncDiff }
      let bitrate = Double(info.videoBitrate)
      if videoBitrate != bitrate { videoBitrate = bitrate }
    }
  }

  /// Which player is active, the codecs of the enabled tracks and the rotation of an
  /// AVPlayer video track. These change with the player or the selected track, not
  /// with time, and reading them is not free: on AVPlayer every call builds a wrapper
  /// per item track with synchronous `AVAssetTrack` reads. They are therefore read on
  /// state changes and after a track selection; the time tick only repeats them while
  /// the video codec is still unknown (it gates the AirPlay button) and as a slow
  /// heartbeat for changes that raise no state change, such as an HLS variant switch.
  private func refreshTrackFacts(of player: MediaPlayerProtocol) {
    lastTrackFactsRefresh = CFAbsoluteTimeGetCurrent()
    if let avPlayer = player as? KSAVPlayer,
       let assetTrack = avPlayer.player.currentItem?.tracks
         .first(where: { $0.isEnabled && $0.assetTrack?.mediaType == .video })?.assetTrack {
      updateQuarterRotation(for: assetTrack)
    }
    let videoTrack = player.tracks(mediaType: .video).first(where: { $0.isEnabled })
    if let videoTrack {
      let codec = Self.codecName(of: videoTrack)
      if !codec.isEmpty, videoCodecName != codec { videoCodecName = codec }
    }
    // The frame rate belongs to the enabled video track: KSPlayer's
    // `nominalFrameRate` on the player enumerates the tracks to find it, so it is
    // read here with the other track facts and not on every time tick.
    let fps = Double(videoTrack?.nominalFrameRate ?? 0)
    if streamFPS != fps { streamFPS = fps }
    if let track = player.tracks(mediaType: .audio).first(where: { $0.isEnabled }) {
      let codec = Self.codecName(of: track)
      if !codec.isEmpty, audioCodecName != codec { audioCodecName = codec }
    }
    let isAVPlayer = !(player is KSMEPlayer)
    let ffmpegActive = !isAVPlayer
    if isFFmpegBackendActive != ffmpegActive { isFFmpegBackendActive = ffmpegActive }
    let engineName = isAVPlayer ? "avplayer" : "ffmpeg"
    if hwdecCurrent != engineName { hwdecCurrent = engineName }
    // AVPlayer yolunda native external playback mümkün; FFmpeg yolundaki remux
    // adaylığını controller hesaplar.
    if isAirPlayVideoCapable != isAVPlayer { isAirPlayVideoCapable = isAVPlayer }
  }

  /// Loads `preferredTransform` asynchronously (the sync property is deprecated since
  /// iOS 16) once per track and caches whether the frame is quarter-rotated. The load
  /// is near-instant for an already-playing item, and diagnostics are re-run on
  /// completion so the swapped size is published without waiting for the next tick.
  private func updateQuarterRotation(for track: AVAssetTrack) {
    guard quarterRotationQueriedTrack !== track else { return }
    quarterRotationQueriedTrack = track
    avTrackIsQuarterRotated = false
    Task { [weak self] in
      guard let transform = try? await track.load(.preferredTransform) else { return }
      guard let self, !self.isDisposed, self.quarterRotationQueriedTrack === track else { return }
      let rotated = Self.isQuarterRotated(transform)
      if rotated != self.avTrackIsQuarterRotated {
        self.avTrackIsQuarterRotated = rotated
        self.refreshDiagnostics()
      }
    }
  }

  /// True for a ~90°/270° `preferredTransform` (portrait-recorded mp4/mov), where the
  /// encoded frame's width/height are swapped relative to the displayed orientation.
  private static func isQuarterRotated(_ transform: CGAffineTransform) -> Bool {
    var degrees = atan2(transform.b, transform.a) * 180 / .pi
    if degrees < 0 { degrees += 360 }
    return abs(degrees - 90) <= 1 || abs(degrees - 270) <= 1
  }

  /// FFmpeg track'lerinde `codecName` her zaman dolu ama profil ekli gelir ("h264 (High)");
  /// formatDescription canlı TS'te extradata gelene kadar nil kalabilir — tespit codecName'in
  /// normalize edilmiş ilk kelimesine dayanır.
  private static func codecName(of track: MediaPlayerTrack) -> String {
    if let ffTrack = track as? FFmpegAssetTrack, !ffTrack.codecName.isEmpty {
      return RemuxHLSWriter.normalizeCodec(ffTrack.codecName)
    }
    guard let desc = track.formatDescription else { return "" }
    let code = CMFormatDescriptionGetMediaSubType(desc)
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
    ]
    return (String(bytes: bytes, encoding: .ascii) ?? "")
      .trimmingCharacters(in: .whitespaces).lowercased()
  }
}

// MARK: - AVPictureInPictureControllerDelegate

extension KSPlayerEngine: AVPictureInPictureControllerDelegate {
  nonisolated func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    let controllerID = ObjectIdentifier(pictureInPictureController)
    Self.runOnMain { [weak self] in
      self?.pictureInPictureDidChange(controllerID: controllerID, active: true, stopped: false)
    }
  }

  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError _: Error
  ) {
    let controllerID = ObjectIdentifier(pictureInPictureController)
    Self.runOnMain { [weak self] in
      self?.pictureInPictureDidChange(controllerID: controllerID, active: false, stopped: false)
    }
  }

  nonisolated func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    let controllerID = ObjectIdentifier(pictureInPictureController)
    Self.runOnMain { [weak self] in
      self?.pictureInPictureDidChange(controllerID: controllerID, active: false, stopped: true)
    }
  }

  /// The system waits for this answer before it animates the window back into the
  /// app. The player view stays mounted while PiP runs (fullscreen or as the mini
  /// card), so there is nothing to rebuild first.
  nonisolated func pictureInPictureController(
    _: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }

  /// AVKit calls its delegate on the main thread, where this stays synchronous; the
  /// hop only covers an unexpected background delivery.
  nonisolated private static func runOnMain(_ work: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated(work)
    } else {
      DispatchQueue.main.async { work() }
    }
  }
}

// MARK: - KSPlayerLayerDelegate

extension KSPlayerEngine: KSPlayerLayerDelegate {
  func player(layer: KSPlayerLayer, state: KSPlayerState) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed, layer === self.layer else { return }
      switch state {
      case .initialized:
        if !self.isBuffering { self.isBuffering = true }
        // Only reported when the layer swaps its player (fallback to the second
        // engine): a seek handed to the old player never completes.
        self.cancelPendingSeek()
        // What the old player detected says nothing about the new one.
        self.containerFormatName = nil
        // The new player opens the source from scratch: it gets a full load timeout
        // of its own, and the old player's progress is not watched any more.
        self.cancelPlaybackWatchdog()
        self.endBackgroundVideoSuspension()
        if !self.isPlaybackEstablished, self.playbackFailureMessage == nil {
          self.scheduleLoadTimeoutWatchdog()
        }
      case .preparing:
        if !self.isBuffering { self.isBuffering = true }
        // After a fallback swap this is a new FFmpeg item with its own capacity
        // timer. Done here rather than at ready, before its threads get busy.
        KSPlayerRunLoopGuard.promoteCapacityTimer(of: layer.player)
      case .readyToPlay:
        self.cancelLoadTimeoutWatchdog()
        // Before anything is published: observers of the flags below may read it.
        self.containerFormatName = KSPlayerEngineMath.containerFormatName(
          isFFmpegPlayer: layer.player is KSMEPlayer,
          detected: self.guardedOptions?.formatName
        )
        if self.hasUndecodableMediaType(layer.player) {
          // Waiting cannot help; say so now instead of buffering without end.
          self.failAndRetireLayer(message: L("playback.error.unsupported"), recoverable: false)
          return
        }
        if !self.isPlaybackEstablished { self.isPlaybackEstablished = true }
        // Establishing playback always supersedes a stale watchdog/error message.
        if self.playbackFailureMessage != nil { self.playbackFailureMessage = nil }
        if self.playbackFailureIsRecoverable { self.playbackFailureIsRecoverable = false }
        self.playbackFailureWantsDelayedRetry = false
        if self.isBuffering { self.isBuffering = false }
        self.isSeekable = layer.player.seekable
        // AVPlayer path: true AirPlay external playback.
        layer.player.allowsExternalPlayback = true
        self.applyAudioDelay()
        self.attachEmbeddedSubtitleSourceIfNeeded()
        self.bumpSurfaceRevision()
        self.applyPendingStart(on: layer, isLastChance: false)
        self.startPlaybackWatchdog(on: layer)
      case .buffering:
        if !self.isBuffering { self.isBuffering = true }
      case .bufferFinished:
        // Frames are flowing: the first-frame and stall counts start over.
        self.playbackWatchdog.notePlaying()
        // AVPlayer can report its seekable ranges a moment after it is ready.
        self.applyPendingStart(on: layer, isLastChance: true)
        if !self.startSeekHoldsTransport {
          if self.isBuffering { self.isBuffering = false }
          if self.isPaused != !layer.player.isPlaying {
            self.isPaused = !layer.player.isPlaying
          }
        }
      case .paused:
        if !self.isPaused { self.isPaused = true }
        // A pause taken during a rebuffer: the layer is paused now, not buffering.
        if self.isBuffering { self.isBuffering = false }
      case .playedToTheEnd:
        // A live stream that ran dry is not a finished item; `finish(error:)`
        // reports it instead.
        if !self.endedAsLiveStream(on: layer) {
          if !self.isCompleted { self.isCompleted = true }
          if !self.isPaused { self.isPaused = true }
        }
      case .error:
        break  // message arrives via finish(error:)
      }
      if !self.startSeekHoldsTransport, state == .bufferFinished || state == .readyToPlay {
        let playing = layer.player.isPlaying
        if self.isPaused == playing { self.isPaused = !playing }
      }
      if state == .bufferFinished || state == .readyToPlay {
        self.scheduleBackgroundVideoSuspensionIfIdle()
      }
      // The layer creates its 0.1 s time-tick timer inside `play()` and `pause()`
      // and reports one of these states right after, so this is the first point
      // where it exists. It is a default-mode timer: without this the position,
      // the subtitle cues and the stranded-seek check stop while a list scrolls.
      // The timer belongs to the layer and survives a player swap.
      if state == .buffering || state == .bufferFinished || state == .paused,
         self.progressTimerPromotedLayer !== layer,
         KSPlayerRunLoopGuard.promoteProgressTimer(of: layer) {
        self.progressTimerPromotedLayer = layer
      }
      self.refreshPiPState()
      self.refreshDiagnostics()
    }
  }

  func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed, layer === self.layer else { return }
      let now = CFAbsoluteTimeGetCurrent()
      // mpv motorundaki 0.12s pozisyon throttle'ının karşılığı.
      if now - self.lastPositionPublish >= 0.12 {
        self.lastPositionPublish = now
        // While a seek is pending `position` shows its target; the player's clock
        // takes over again once the seek settles.
        if self.pendingSeekTarget == nil, self.position != currentTime {
          self.position = currentTime
        }
        let total = totalTime.isFinite ? max(totalTime, 0) : 0
        if self.duration != total { self.duration = total }
        let playable = layer.player.playableTime
        // Not while a seek is pending: until it lands the player still reports the
        // buffer of the position it is leaving.
        if KSPlayerEngineMath.publishesBufferTimeline(
          playable: playable, seekPending: self.pendingSeekTarget != nil
        ), self.bufferTimelineEnd != playable {
          self.bufferTimelineEnd = playable
          self.cacheDurationSeconds = max(playable - currentTime, 0)
        }
        self.refreshDiagnostics(
          trackFacts: KSPlayerEngineMath.refreshesTrackFacts(
            videoCodecKnown: !self.videoCodecName.isEmpty,
            now: now,
            lastRefresh: self.lastTrackFactsRefresh
          )
        )
        // Neither a replaced PiP controller nor a seek issued from the PiP window
        // raises a state change; both are noticed here.
        self.refreshPiPState()
        self.resumeStrandedSeek(on: layer)
      }
      if self.subtitleModel.subtitle(currentTime: currentTime) {
        self.publishSubtitleParts()
      }
    }
  }

  func player(layer: KSPlayerLayer, finish error: Error?) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isDisposed, layer === self.layer else { return }
      self.cancelLoadTimeoutWatchdog()
      self.cancelPlaybackWatchdog()
      if let error {
        self.handlePlaybackError(error as NSError, on: layer)
      } else if self.endedAsLiveStream(on: layer) {
        self.reportLiveStreamEnd()
      } else {
        if !self.isCompleted { self.isCompleted = true }
        if !self.isPaused { self.isPaused = true }
      }
    }
  }

  func player(layer _: KSPlayerLayer, bufferedCount _: Int, consumeTime _: TimeInterval) {}

  /// Names the failure for the user and decides whether the owner may retry it. An
  /// FFmpeg error carries the libav code as its underlying error; AVPlayer reports
  /// `NSURLError`s.
  private func handlePlaybackError(_ error: NSError, on layer: KSPlayerLayer) {
    var failure = KSPlayerLoadPolicy.failure(
      domain: error.domain,
      code: error.code,
      avErrorCode: KSPlayerLoadPolicy.underlyingAVErrorCode(of: error)
    )
    if KSPlayerLoadPolicy.shouldRescueWithAVPlayer(
      failure,
      isFFmpegOnlyLoad: currentLoadIsFFmpegOnly && layer.player is KSMEPlayer,
      rescueAlreadyRan: rescuedFailure != nil,
      isPlaybackEstablished: isPlaybackEstablished
    ), startAVPlayerRescue(on: layer, after: failure) {
      return
    }
    // AVPlayer could not open it either and has no better name for the reason: keep
    // what FFmpeg said about the source.
    if let rescuedFailure, failure == .other, !isPlaybackEstablished { failure = rescuedFailure }
    publishFailure(
      message: L(failure.messageKey),
      recoverable: failure.isRecoverable,
      // Only for a stream that never played: the same answer in the middle of
      // playback is the server ending the session, not a slot that is still taken.
      wantsDelayedRetry: failure.isDelayedRetryCandidate && !isPlaybackEstablished
    )
  }

  private func endedAsLiveStream(on layer: KSPlayerLayer) -> Bool {
    KSPlayerEngineMath.isLiveStreamEnd(
      isLive: currentLoadIsLive, duration: knownDuration(of: layer)
    )
  }

  private func reportLiveStreamEnd() {
    // A later play() can make the layer run into the same end again.
    guard !liveStreamEndReported else { return }
    liveStreamEndReported = true
    guard let onLiveStreamEnded else {
      // Nobody can reload: behave like a finished item, as before.
      markLiveStreamEnded()
      return
    }
    // Show the spinner over the frozen frame while the owner decides between a
    // reload and `markLiveStreamEnded()`.
    if !isBuffering { isBuffering = true }
    onLiveStreamEnded()
  }
}

/// Pure decisions of the engine's load, failure and background life cycle, kept free of
/// player state so they can be tested.
nonisolated enum KSPlayerLoadPolicy {
  /// `AVError` alone is ambiguous here: AVFoundation has a type of the same name.
  typealias LibavError = KSPlayer.AVError

  // MARK: Failures

  nonisolated enum Failure: Equatable {
    case unauthorized
    case forbidden
    case notFound
    case timeout
    /// Host unreachable, connection refused or reset.
    case unreachable
    /// FFmpeg does not recognise what the source delivers.
    case unreadableSource
    /// The source did not open, for a reason that is neither HTTP nor the network.
    case openFailed
    case other

    var messageKey: String {
      switch self {
      case .unauthorized: return "playback.error.unauthorized"
      case .forbidden: return "playback.error.forbidden"
      case .notFound: return "playback.error.not_found"
      case .timeout: return "playback.error.timeout"
      case .unreachable: return "playback.error.cannot_reach"
      case .unreadableSource: return "playback.error.unsupported"
      case .openFailed: return "playback.error.failed_to_start"
      case .other: return "playback.error.failed_check_network"
      }
    }

    /// Worth one silent retry by the owner.
    var isRecoverable: Bool { self == .timeout || self == .unreachable }

    /// Worth one retry after a pause, HTTP 403 only: a panel that limits connections
    /// refuses the next channel while it still counts the socket of the previous one,
    /// and accepts it a moment later. Kept apart from `isRecoverable`, which retries
    /// at once; a 403 from a blocked or expired account stays what it is and is shown
    /// after that one attempt.
    var isDelayedRetryCandidate: Bool { self == .forbidden }

    /// A different player may open what FFmpeg could not. Never an HTTP status: there
    /// the server has answered, and a second request changes nothing.
    var isAVPlayerRescueCandidate: Bool { self == .unreadableSource || self == .openFailed }
  }

  /// errno values FFmpeg reports (negated) when the connection could not be made or
  /// broke. `EIO` is what its TCP and HTTP code return for a failed name lookup and
  /// after the last reconnect attempt.
  private static let unreachableCodes: Set<Int32> = Set(
    [
      ECONNREFUSED, ECONNRESET, ECONNABORTED, EHOSTUNREACH, EHOSTDOWN, ENETUNREACH,
      ENETDOWN, ENETRESET, ENOTCONN, EPIPE, EADDRNOTAVAIL, EIO,
    ].map { -$0 }
  )

  /// - Parameters:
  ///   - domain: `NSError.domain` of what the layer reported.
  ///   - code: `NSError.code`; a `KSPlayerErrorCode` in KSPlayer's domain.
  ///   - avErrorCode: the libav code behind an FFmpeg error, see `underlyingAVErrorCode`.
  static func failure(domain: String, code: Int, avErrorCode: Int32?) -> Failure {
    if domain == NSURLErrorDomain {
      switch code {
      case NSURLErrorTimedOut:
        return .timeout
      case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
           NSURLErrorNotConnectedToInternet:
        return .unreachable
      default:
        return .other
      }
    }
    guard domain == KSPlayerErrorDomain else { return .other }
    // Only an error from opening or probing says something about the source as a
    // whole; the same code from a later read is a broken stream.
    let isOpenStage = code == KSPlayerErrorCode.formatOpenInput.rawValue
      || code == KSPlayerErrorCode.formatFindStreamInfo.rawValue
    guard let avErrorCode else { return .other }
    if avErrorCode == LibavError.httpUnauthorized.code { return .unauthorized }
    if avErrorCode == LibavError.httpForbidden.code { return .forbidden }
    if avErrorCode == LibavError.httpNotFound.code { return .notFound }
    let unnamed = [
      LibavError.httpBadRequest.code, LibavError.httpOther4xx.code,
      LibavError.httpServerError.code,
      // The read was interrupted by a shutdown, not by the source.
      LibavError.exit.code,
    ]
    if unnamed.contains(avErrorCode) { return .other }
    if avErrorCode == -ETIMEDOUT { return .timeout }
    if unreachableCodes.contains(avErrorCode) { return .unreachable }
    guard isOpenStage else { return .other }
    let unreadable = [
      LibavError.invalidData.code, LibavError.demuxerNotFound.code,
      LibavError.protocolNotFound.code, LibavError.patchWelcome.code,
    ]
    return unreadable.contains(avErrorCode) ? .unreadableSource : .openFailed
  }

  /// KSPlayer wraps the libav return code as the underlying error of its `NSError`.
  static func underlyingAVErrorCode(of error: NSError) -> Int32? {
    (error.userInfo[NSUnderlyingErrorKey] as? LibavError)?.code
  }

  /// One AVPlayer attempt per load, only for an FFmpeg-only load that never got as
  /// far as reporting ready.
  static func shouldRescueWithAVPlayer(
    _ failure: Failure,
    isFFmpegOnlyLoad: Bool,
    rescueAlreadyRan: Bool,
    isPlaybackEstablished: Bool
  ) -> Bool {
    failure.isAVPlayerRescueCandidate && isFFmpegOnlyLoad && !rescueAlreadyRan
      && !isPlaybackEstablished
  }

  /// True when the stream has video (or audio) tracks and FFmpeg can decode none of
  /// them.
  static func hasUndecodableMediaType(
    videoTrackIDs: [Int32], audioTrackIDs: [Int32], undecodable: Set<Int32>
  ) -> Bool {
    func allUndecodable(_ ids: [Int32]) -> Bool {
      !ids.isEmpty && ids.allSatisfy(undecodable.contains)
    }
    return allUndecodable(videoTrackIDs) || allUndecodable(audioTrackIDs)
  }

  /// Codecs of a picture attached to an audio file. FFmpegKit ships no decoder for
  /// most of them, yet such a "video track" does not make the file unplayable.
  static func isStillImageCodec(_ codecName: String) -> Bool {
    let stillImageCodecs: Set<String> = ["png", "apng", "bmp", "gif", "tiff", "webp", "mjpeg"]
    return stillImageCodecs.contains(DecoderProbe.baseName(of: codecName))
  }

  // MARK: Progress after ready

  /// Watches an FFmpeg stream that has reported ready. It is fed one sample per
  /// `tickInterval` and counts ticks, so a stretch without ticks adds nothing.
  nonisolated struct ProgressWatchdog: Equatable {
    static let tickInterval: TimeInterval = 2
    /// Before the first frame: this long without a byte or a packet arriving. A slow
    /// start that keeps receiving data is left alone.
    static let firstFrameIdleLimit: TimeInterval = 12
    /// Live, after it played: this long in one uninterrupted rebuffer.
    static let liveStallLimit: TimeInterval = 20
    /// VOD, after it played: a rebuffer during which nothing arrived for this long.
    /// A slow link that still delivers may take longer than any fixed limit.
    static let vodStallIdleLimit: TimeInterval = 30

    nonisolated struct Sample: Equatable {
      /// The layer wants to play (it is not paused, ended or failed).
      var isPlaying: Bool
      var isBuffering: Bool
      var bytesRead: Int64
      var playableTime: TimeInterval
    }

    nonisolated enum Verdict: Equatable {
      case healthy
      case firstFrameTimeout
      case stalled
    }

    let isLive: Bool
    private(set) var hasPlayed = false
    private(set) var bufferingSeconds: TimeInterval = 0
    private(set) var idleSeconds: TimeInterval = 0
    private var lastBytesRead: Int64?
    private var lastPlayableTime: TimeInterval?

    init(isLive: Bool) {
      self.isLive = isLive
    }

    /// The player left buffering: frames of every track are available.
    mutating func notePlaying() {
      hasPlayed = true
      bufferingSeconds = 0
      idleSeconds = 0
    }

    mutating func tick(_ sample: Sample) -> Verdict {
      // NaN never equals itself and would read as progress on every tick.
      let playableTime = sample.playableTime.isFinite ? sample.playableTime : 0
      let progressed = sample.bytesRead != lastBytesRead || playableTime != lastPlayableTime
      lastBytesRead = sample.bytesRead
      lastPlayableTime = playableTime
      guard sample.isPlaying else {
        // Paused: nothing is expected to arrive or to be shown.
        bufferingSeconds = 0
        idleSeconds = 0
        return .healthy
      }
      guard sample.isBuffering else {
        notePlaying()
        return .healthy
      }
      bufferingSeconds += Self.tickInterval
      idleSeconds = progressed ? 0 : idleSeconds + Self.tickInterval
      if !hasPlayed {
        return idleSeconds >= Self.firstFrameIdleLimit ? .firstFrameTimeout : .healthy
      }
      if isLive {
        return bufferingSeconds >= Self.liveStallLimit ? .stalled : .healthy
      }
      return idleSeconds >= Self.vodStallIdleLimit ? .stalled : .healthy
    }
  }

  // MARK: Background

  /// How long the app has to stay in the background before the video is suspended.
  static let backgroundSuspendDelay: TimeInterval = 5

  nonisolated enum BackgroundAction: Equatable {
    case leave
    /// Picture in Picture is drawing the frames; its window can be closed while the
    /// app stays in the background, so look again later.
    case checkAgain
    case suspendVideo
  }

  static func backgroundAction(
    isPlaying: Bool,
    isPictureInPictureActive: Bool,
    hasEnabledVideoTrack: Bool,
    hasEnabledAudioTrack: Bool,
    isLive: Bool,
    isSeekable: Bool,
    seeksByBytes: Bool
  ) -> BackgroundAction {
    if isPictureInPictureActive { return .checkAgain }
    // Paused, or without audio to keep the clock running: the reader stops by itself
    // once its buffer is full.
    guard isPlaying, hasEnabledVideoTrack, hasEnabledAudioTrack else { return .leave }
    // The return path for VOD is a seek to the current position. A container that
    // seeks by byte position would land where the picture stopped instead, rewinding
    // the audio by the whole absence. Such a title is left as it is.
    if !isLive, isSeekable, seeksByBytes { return .leave }
    return .suspendVideo
  }

  nonisolated enum ForegroundAction: Equatable {
    /// Live: a fresh load, at the live edge.
    case reload
    /// VOD: a seek to where the audio is.
    case seekToCurrentPosition
    /// Switch the track back on through the player, which flushes its queues.
    case reselectTrack
  }

  static func foregroundAction(
    isPlaying: Bool, isLive: Bool, canReload: Bool, canSeek: Bool
  ) -> ForegroundAction {
    // Paused or ended: a reload would start playing on its own.
    guard isPlaying else { return .reselectTrack }
    if isLive { return canReload ? .reload : .reselectTrack }
    return canSeek ? .seekToCurrentPosition : .reselectTrack
  }
}

/// Pure decisions of `KSPlayerEngine`, kept free of player state so they can be tested.
nonisolated enum KSPlayerEngineMath {
  /// A seek that lands exactly on the end finishes the item again at once.
  static let seekEndMargin: TimeInterval = 0.5

  /// Clamps a seek target to the playable range. The upper bound applies only when
  /// the duration is known (live streams report none).
  static func clampedSeekTarget(_ seconds: TimeInterval, duration: TimeInterval) -> TimeInterval {
    let lower = seconds.isFinite ? max(seconds, 0) : 0
    guard duration.isFinite, duration > 0 else { return lower }
    return min(lower, max(duration - seekEndMargin, 0))
  }

  /// Target of a relative skip. While an earlier seek is still pending the skip adds
  /// to its target, so a burst of taps accumulates instead of repeating one jump.
  static func accumulatedSeekTarget(
    position: TimeInterval,
    pendingTarget: TimeInterval?,
    delta: TimeInterval,
    duration: TimeInterval
  ) -> TimeInterval {
    clampedSeekTarget((pendingTarget ?? position) + delta, duration: duration)
  }

  enum PendingStartAction: Equatable {
    /// The FFmpeg player already started at the position (`KSOptions.startPlayTime`).
    case discard
    /// The item cannot seek yet.
    case wait
    case seek(TimeInterval)
  }

  static func pendingStartAction(
    start: TimeInterval,
    isFFmpegPlayer: Bool,
    isSeekable: Bool,
    duration: TimeInterval
  ) -> PendingStartAction {
    guard start.isFinite, start > 0, !isFFmpegPlayer else { return .discard }
    guard isSeekable else { return .wait }
    return .seek(clampedSeekTarget(start, duration: duration))
  }

  /// `KSOptions.videoDelay` for the "audio delay" setting, where positive values delay
  /// the audio: the video is shown that much ahead of the audio clock.
  static func videoDelay(
    forAudioDelay seconds: Double,
    isFFmpegPlayer: Bool,
    hasEnabledAudioTrack: Bool
  ) -> Double {
    guard isFFmpegPlayer, hasEnabledAudioTrack, seconds.isFinite, seconds != 0 else { return 0 }
    return -seconds
  }

  /// An end without an error on a live load whose length is unknown means the stream
  /// ran dry. A finite file that was merely classified as live has a duration and
  /// ends like any other item.
  static func isLiveStreamEnd(isLive: Bool, duration: TimeInterval) -> Bool {
    isLive && !(duration.isFinite && duration > 0)
  }

  /// How often a time tick re-reads the track list once the video codec is known.
  static let trackFactsInterval: TimeInterval = 2

  /// Whether a time tick should also re-read the track list and codec facts. Every
  /// tick until the video codec is known, then once per `trackFactsInterval`. The
  /// times are wall-clock readings: one that was set back must not stop the refresh.
  static func refreshesTrackFacts(
    videoCodecKnown: Bool, now: TimeInterval, lastRefresh: TimeInterval
  ) -> Bool {
    !videoCodecKnown || now < lastRefresh || now - lastRefresh >= trackFactsInterval
  }

  /// Whether a time tick may publish the player's buffered end. A seek resets it, and
  /// until the seek has landed the player's value is still the old buffer.
  static func publishesBufferTimeline(playable: TimeInterval, seekPending: Bool) -> Bool {
    playable.isFinite && !seekPending
  }

  /// The engine's `containerFormatName`: what FFmpeg detected, and only while its
  /// player is the active one. After a fallback or rescue swap to AVPlayer the options
  /// can still carry the name from the FFmpeg attempt.
  static func containerFormatName(isFFmpegPlayer: Bool, detected: String?) -> String? {
    guard isFFmpegPlayer, let detected, !detected.isEmpty else { return nil }
    return detected
  }

  enum PlayAction: Equatable {
    case resume
    case restartFromBeginning
    case reload
  }

  static func playAction(
    isCompleted: Bool,
    isSeekable: Bool,
    liveStreamEnded: Bool,
    canReload: Bool
  ) -> PlayAction {
    if canReload, liveStreamEnded || (isCompleted && !isSeekable) { return .reload }
    return isCompleted ? .restartFromBeginning : .resume
  }
}
