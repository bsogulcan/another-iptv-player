import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import os

struct TrackMenuOption: Identifiable, Hashable {
  let id: Int
  let title: String
  let detail: String?
  let langCode: String?

  init(id: Int, title: String, detail: String? = nil, langCode: String? = nil) {
    self.id = id
    self.title = title
    self.detail = detail
    self.langCode = langCode
  }
}

enum VideoPlayerState: Int {
  case idle = 0
  case loading = 1
  case buffering = 2
  case playing = 3
  case paused = 4
  case stopped = 5
  case ended = 6
  case error = 7
}

enum VideoAspectMode: String, CaseIterable {
  case ratio16x9
  case ratio4x3
  case center
  case bestFit
  case ratio16x10

  var preferredAspectRatio: CGFloat? {
    switch self {
    case .ratio16x9: return 16.0 / 9.0
    case .ratio4x3: return 4.0 / 3.0
    case .ratio16x10: return 16.0 / 10.0
    case .center, .bestFit: return nil
    }
  }

  var iconName: String {
    switch self {
    case .ratio16x9: return "rectangle"
    case .ratio4x3: return "rectangle.portrait"
    case .center: return "dot.square"
    case .bestFit: return "aspectratio"
    case .ratio16x10: return "rectangle.compress.vertical"
    }
  }

  var title: String {
    switch self {
    case .ratio16x9: return "16:9"
    case .ratio4x3: return "4:3"
    case .center: return "Center"
    case .bestFit: return "Best Fit"
    case .ratio16x10: return "16:10"
    }
  }

  var accessibilityLabel: String {
    "Aspect ratio: \(title)"
  }

  var viewportContentMode: UIView.ContentMode {
    // Tüm modlarda .scaleAspectFit: video frame içinde doğal oranında gösterilir.
    // Fixed ratio modlarda (16:9, 4:3) SwiftUI frame zorlu oran boyutuna getirilir;
    // UIImageView içeriği pillarbox/letterbox ile doğal oranında sığar — MPV'nin varsayılan
    // davranışıyla aynı sonuç. .scaleToFill kullanılırsa video yanlış uzatılır.
    return .scaleAspectFit
  }
}

/// `PlayerView` köprüsü: libmpv `MPVPlayer` + Now Playing / uzaktan kumanda.
final class VideoPlayerController: ObservableObject {
  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "another-iptv-player",
    category: "VideoPlayer"
  )

  let mpvEngine = MPVPlayer()

  @Published var state: VideoPlayerState = .idle
  @Published var isPlaying: Bool = false
  @Published var isSeekable: Bool = false
  @Published var position: Float = 0
  @Published var durationMs: Int64 = 0
  @Published var timeMs: Int64 = 0
  @Published var bufferingProgress: Float = 0
  @Published var rate: Float = 1.0
  @Published var videoWidth: Int = 0
  @Published var videoHeight: Int = 0
  @Published var streamFPS: Double = 0
  @Published var renderFPS: Double = 0
  @Published var videoBitrate: Double = 0
  @Published var droppedFrameCount: Int64 = 0
  @Published var delayedFrameCount: Int64 = 0
  @Published var cacheBufferingState: Double = 0
  @Published var cacheDurationSeconds: Double = 0
  @Published var cacheAheadSeconds: Double = 0
  @Published var avSyncSeconds: Double = 0
  @Published var networkSpeedBps: Double = 0
  @Published var hwdecCurrent: String = ""
  @Published var videoCodecName: String = ""
  @Published var seekLatencyMs: Int = -1
  /// Ağ / yükleme hatası (`MPVPlayer.playbackFailureMessage` yansıması).
  @Published var playbackFailureMessage: String?

  @Published var videoTracks: [TrackMenuOption] = []
  @Published var audioTracks: [TrackMenuOption] = []
  @Published var subtitleTracks: [TrackMenuOption] = [TrackMenuOption(id: -1, title: L("player.subtitle_off"))]
  @Published var currentVideoTrackId: Int = -1
  @Published var currentAudioTrackId: Int = -1
  @Published var currentSubtitleTrackId: Int = -1

  @Published var isPiPActive: Bool = false
  @Published var aspectMode: VideoAspectMode = .bestFit
  /// Canlı yayın bayrağı: `setPlaybackPresentation` üzerinden güncellenir. PiP sample buffer
  /// delegesi skip kontrollerini gizlemek için bu değeri okur (mpv duration canlıda 0 dönmeyebilir).
  @Published var isLiveStream: Bool = false

  /// Sistem ekran parlaklığı (0…1). Kontrol Merkezi vb. dış değişimler `brightnessDidChange` ile güncellenir.
  @Published private(set) var screenBrightness: CGFloat

  var hdrAvailable: Bool = false

  private struct PendingLoadRequest {
    let url: URL
    let startSeconds: TimeInterval?
    let isLiveStream: Bool
  }

  private var pendingLoadRequest: PendingLoadRequest?
  private var isTornDown = false
  private var audioSessionActivated = false
  private var playbackPresentation: PlaybackPresentation?
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
  private var seriesEpisodeOnPrevious: (() -> Void)?
  private var seriesEpisodeOnNext: (() -> Void)?
  private var cancellables = Set<AnyCancellable>()

  private var nowPlayingArtwork: UIImage?
  private var artworkFetchTask: URLSessionDataTask?
  private var artworkFetchURL: URL?
  private var seekRequestStartedAt: Date?
  private var seekSourceTimeMs: Int64?
  /// `play` sonrası ilk `isPlaybackEstablished` olayında kayıtlı parça tercihleri uygulanır.
  private var pendingPreferredTrackSelection = false

  init() {
    screenBrightness = UIScreen.main.brightness
    wireEngine()
  }

  deinit {
    teardown()
  }

  private func wireEngine() {
    let e = mpvEngine
    let sync = { [weak self] in
      self?.syncFromEngine()
    }
    e.$position.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$duration.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$isPaused.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$isCompleted.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$playbackRate.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$isBuffering.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$isSeekable.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$videoDisplayWidth.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$videoDisplayHeight.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$streamFPS.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$renderFPS.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$videoBitrate.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$droppedFrameCount.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$delayedFrameCount.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$cacheBufferingState.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$cacheDurationSeconds.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$avSyncSeconds.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$networkSpeedBps.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$hwdecCurrent.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$videoCodecName.receive(on: DispatchQueue.main).sink { _ in sync() }.store(in: &cancellables)
    e.$playbackFailureMessage
      .receive(on: DispatchQueue.main)
      .sink { [weak self] msg in
        self?.playbackFailureMessage = msg
        self?.syncFromEngine()
      }
      .store(in: &cancellables)
    e.$isPlaybackEstablished
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] established in
        guard let self else { return }
        self.syncFromEngine()
        if established, self.pendingPreferredTrackSelection {
          self.pendingPreferredTrackSelection = false
          self.applyPreferredTracksFromSavedPreferences()
        }
      }
      .store(in: &cancellables)

    e.$isReady
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] ready in
        guard let self else { return }
        if ready {
          self.tryFlushPendingLoad()
        }
        self.syncFromEngine()
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.screenBrightness = UIScreen.main.brightness
      }
      .store(in: &cancellables)
  }

  /// Her @Published atama `objectWillChange` fire eder — Swift @Published eşitlik kontrolü yapmaz.
  /// Tüm atamaları `if current != new` ile koru; aksi halde saniyede 8×22 = ~176 gereksiz SwiftUI invalidation olur.
  private func syncFromEngine() {
    let pos = mpvEngine.position
    let dur = mpvEngine.duration
    let posMs = Int64((pos.isFinite ? pos : 0) * 1000)
    let durMs = Int64((dur.isFinite ? dur : 0) * 1000)
    if timeMs != posMs { timeMs = posMs }
    if durationMs != durMs { durationMs = durMs }

    let newPosition: Float
    if dur > 0, pos.isFinite {
      newPosition = Float(min(max(pos / dur, 0), 1))
    } else {
      newPosition = 0
    }
    if position != newPosition { position = newPosition }

    let failed = !(mpvEngine.playbackFailureMessage ?? "").isEmpty
    let newIsPlaying =
      !failed && mpvEngine.isPlaybackEstablished && mpvEngine.isReady
      && !mpvEngine.isPaused && !mpvEngine.isCompleted
    if isPlaying != newIsPlaying { isPlaying = newIsPlaying }

    let newRate = Float(mpvEngine.playbackRate)
    if rate != newRate { rate = newRate }

    if isSeekable != mpvEngine.isSeekable { isSeekable = mpvEngine.isSeekable }

    let newBuf: Float = mpvEngine.isBuffering ? 0.35 : 0
    if bufferingProgress != newBuf { bufferingProgress = newBuf }

    if videoWidth != mpvEngine.videoDisplayWidth { videoWidth = mpvEngine.videoDisplayWidth }
    if videoHeight != mpvEngine.videoDisplayHeight { videoHeight = mpvEngine.videoDisplayHeight }
    if streamFPS != mpvEngine.streamFPS { streamFPS = mpvEngine.streamFPS }
    if renderFPS != mpvEngine.renderFPS { renderFPS = mpvEngine.renderFPS }
    if videoBitrate != mpvEngine.videoBitrate { videoBitrate = mpvEngine.videoBitrate }
    if droppedFrameCount != mpvEngine.droppedFrameCount {
      droppedFrameCount = mpvEngine.droppedFrameCount
    }
    if delayedFrameCount != mpvEngine.delayedFrameCount {
      delayedFrameCount = mpvEngine.delayedFrameCount
    }
    if cacheBufferingState != mpvEngine.cacheBufferingState {
      cacheBufferingState = mpvEngine.cacheBufferingState
    }
    if cacheDurationSeconds != mpvEngine.cacheDurationSeconds {
      cacheDurationSeconds = mpvEngine.cacheDurationSeconds
    }
    let newAhead = max(mpvEngine.bufferTimelineEnd - (Double(timeMs) / 1000.0), 0)
    if cacheAheadSeconds != newAhead { cacheAheadSeconds = newAhead }
    if avSyncSeconds != mpvEngine.avSyncSeconds { avSyncSeconds = mpvEngine.avSyncSeconds }
    if networkSpeedBps != mpvEngine.networkSpeedBps { networkSpeedBps = mpvEngine.networkSpeedBps }
    if hwdecCurrent != mpvEngine.hwdecCurrent { hwdecCurrent = mpvEngine.hwdecCurrent }
    if videoCodecName != mpvEngine.videoCodecName { videoCodecName = mpvEngine.videoCodecName }

    updateSeekLatencyIfNeeded(currentTimeMs: timeMs)

    let newState: VideoPlayerState
    if failed {
      newState = .error
    } else if !mpvEngine.isReady {
      newState = .idle
    } else if mpvEngine.isCompleted {
      newState = .ended
    } else if mpvEngine.isBuffering {
      newState = .buffering
    } else if mpvEngine.isPaused {
      newState = .paused
    } else {
      newState = .playing
    }
    if state != newState { state = newState }

    applyIdleTimerPolicy()
    updateNowPlayingInfo()
  }

  /// Oynatma sırasında ekranın otomatik kapanmasını engeller; duraklatınca veya ekrandan çıkınca normale döner.
  private func applyIdleTimerPolicy() {
    let disableIdleTimer = isPlaying
    if Thread.isMainThread {
      UIApplication.shared.isIdleTimerDisabled = disableIdleTimer
    } else {
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = disableIdleTimer
      }
    }
  }

  private func tryFlushPendingLoad() {
    guard let request = pendingLoadRequest else { return }
    pendingLoadRequest = nil
    log.info("Loading URL into mpv: \(request.url.absoluteString, privacy: .public)")
    mpvEngine.load(
      request.url,
      play: true,
      startSeconds: request.startSeconds,
      liveLowLatency: request.isLiveStream
    )
    let saved = SubtitleAppearancePersistence.load()
    mpvEngine.applySubtitleAppearanceFromSettings(saved)
    mpvEngine.setSubDelay(seconds: saved.delaySeconds)
  }

  func setupAudioSession() {
    if audioSessionActivated { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
      try session.setActive(true, options: [])
      audioSessionActivated = true
    } catch {
      log.error("AVAudioSession: \(error.localizedDescription)")
    }
  }

  func play(url: URL, startSeconds: TimeInterval? = nil, isLiveStream: Bool = false) {
    guard !isTornDown else { return }
    pendingPreferredTrackSelection = true
    setupAudioSession()
    pendingLoadRequest = PendingLoadRequest(
      url: url,
      startSeconds: startSeconds,
      isLiveStream: isLiveStream
    )
    tryFlushPendingLoad()
  }

  func setupAudioHandler() {
    setupAudioSession()
    setupRemoteCommands()
  }

  func setPlaybackPresentation(_ presentation: PlaybackPresentation) {
    playbackPresentation = presentation
    if isLiveStream != presentation.isLive {
      isLiveStream = presentation.isLive
    }
    scheduleNowPlayingArtworkFetch(for: presentation)
    updateNowPlayingInfo(force: true)
  }

  func togglePlayPause() {
    if isPlaying {
      mpvEngine.pause()
    } else {
      mpvEngine.play()
    }
  }

  func jump(seconds: Int) {
    markSeekRequestStart()
    mpvEngine.jumpRelative(seconds: seconds)
  }

  func seek(to pos: Float) {
    markSeekRequestStart()
    mpvEngine.seekToFraction(pos)
  }

  func setRate(_ newRate: Float) {
    mpvEngine.setPlaybackRate(Double(newRate))
    rate = newRate
  }

  func setVolume(_ value: Double) {
    let clamped = min(max(value, 0), 125)
    mpvEngine.setVolume(clamped)
  }

  /// `UIScreen` parlaklığı; ana iş parçacığında uygulanır.
  func setScreenBrightness(_ value: CGFloat) {
    let clamped = min(max(value, 0), 1)
    let apply = { [weak self] in
      UIScreen.main.brightness = clamped
      self?.screenBrightness = clamped
    }
    if Thread.isMainThread {
      apply()
    } else {
      DispatchQueue.main.async(execute: apply)
    }
  }

  func setAspectMode(_ mode: VideoAspectMode, force: Bool = false) {
    if !force, aspectMode == mode { return }
    aspectMode = mode
  }

  func cycleAspectMode() {
    let all = VideoAspectMode.allCases
    guard let idx = all.firstIndex(of: aspectMode) else {
      setAspectMode(.bestFit)
      return
    }
    let next = all[(idx + 1) % all.count]
    setAspectMode(next)
  }

  func updateTracks(applyPreferences: Bool = false) {
    mpvEngine.reloadTrackList { [weak self] video, audio, subs, vid, aid, sid in
      guard let self else { return }
      self.videoTracks = video
      self.audioTracks = audio
      self.subtitleTracks = subs
      self.currentVideoTrackId = vid
      self.currentAudioTrackId = aid
      self.currentSubtitleTrackId = sid
      guard applyPreferences else { return }
      let prefs = PlaybackTrackPreferences.load()
      if let pick = PlaybackTrackPreferences.pickVideo(from: video, prefs: prefs) {
        self.mpvEngine.selectVideoTrack(id: pick)
        self.currentVideoTrackId = pick
      }
      if let pick = PlaybackTrackPreferences.pickAudio(from: audio, prefs: prefs) {
        self.mpvEngine.selectAudioTrack(id: pick)
        self.currentAudioTrackId = pick
      }
      if let pick = PlaybackTrackPreferences.pickSubtitle(from: subs, prefs: prefs) {
        self.mpvEngine.selectSubtitleTrack(id: pick)
        self.currentSubtitleTrackId = pick
      }
    }
  }

  private func applyPreferredTracksFromSavedPreferences() {
    updateTracks(applyPreferences: true)
  }

  func selectVideoTrack(id: Int) {
    mpvEngine.selectVideoTrack(id: id)
    currentVideoTrackId = id
    if let opt = videoTracks.first(where: { $0.id == id }) {
      PlaybackTrackPreferences.saveVideo(from: opt)
    }
  }

  func selectAudioTrack(id: Int) {
    mpvEngine.selectAudioTrack(id: id)
    currentAudioTrackId = id
    if let opt = audioTracks.first(where: { $0.id == id }) {
      PlaybackTrackPreferences.saveAudio(from: opt)
    }
  }

  func selectSubtitleTrack(id: Int) {
    mpvEngine.selectSubtitleTrack(id: id)
    currentSubtitleTrackId = id
    if let opt = subtitleTracks.first(where: { $0.id == id }) {
      PlaybackTrackPreferences.saveSubtitle(from: opt)
    }
  }

  func applySubtitleAppearanceSettings(_ settings: SubtitleAppearanceSettings) {
    SubtitleAppearancePersistence.save(settings)
    mpvEngine.applySubtitleAppearanceFromSettings(settings)
    mpvEngine.setSubDelay(seconds: settings.delaySeconds)
  }

  func applySubtitleDelaySeconds(_ seconds: Double) {
    mpvEngine.setSubDelay(seconds: seconds)
  }

  func teardown() {
    if isTornDown { return }
    isTornDown = true
    seriesEpisodeOnPrevious = nil
    seriesEpisodeOnNext = nil
    MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
    MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
    if Thread.isMainThread {
      UIApplication.shared.isIdleTimerDisabled = false
    } else {
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = false
      }
    }
    cancellables.removeAll()
    removeRemoteCommands()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    playbackPresentation = nil
    cancelNowPlayingArtworkFetch(clearImage: true)
    pendingLoadRequest = nil
    audioSessionActivated = false
    seekRequestStartedAt = nil
    seekSourceTimeMs = nil
    seekLatencyMs = -1
    playbackFailureMessage = nil
    mpvEngine.dispose()
  }

  private func markSeekRequestStart() {
    seekRequestStartedAt = Date()
    seekSourceTimeMs = timeMs
    seekLatencyMs = -1
  }

  private func updateSeekLatencyIfNeeded(currentTimeMs: Int64) {
    guard seekLatencyMs < 0 else { return }
    guard let startedAt = seekRequestStartedAt, let sourceTimeMs = seekSourceTimeMs else { return }
    let shifted = abs(currentTimeMs - sourceTimeMs) >= 900
    let stalledTooLong = Date().timeIntervalSince(startedAt) >= 5.0
    guard shifted || stalledTooLong else { return }
    seekLatencyMs = max(Int(Date().timeIntervalSince(startedAt) * 1000), 0)
    seekRequestStartedAt = nil
    seekSourceTimeMs = nil
  }

  // MARK: - Now Playing

  private var lastNowPlayingUpdate: TimeInterval = 0

  private func updateNowPlayingInfo(force: Bool = false) {
    guard let p = playbackPresentation else { return }
    let now = CFAbsoluteTimeGetCurrent()
    if !force, now - lastNowPlayingUpdate < 0.8 { return }
    lastNowPlayingUpdate = now

    let durationSec = max(Double(durationMs) / 1000.0, 0)
    let elapsedSec = max(Double(timeMs) / 1000.0, 0)

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: p.title,
      MPMediaItemPropertyArtist: p.subtitle ?? "Another IPTV Player",
      MPMediaItemPropertyPlaybackDuration: durationSec,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSec,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if p.isLive {
      info[MPNowPlayingInfoPropertyIsLiveStream] = true
      info[MPMediaItemPropertyPlaybackDuration] = 0
    }
    if let img = nowPlayingArtwork {
      // Sistem istenen boyutta tekrar çağırır; tek `UIImage` yeterli.
      let b = img.size
      let bounds = CGSize(width: max(b.width, 1), height: max(b.height, 1))
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: bounds) { _ in img }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func cancelNowPlayingArtworkFetch(clearImage: Bool) {
    artworkFetchTask?.cancel()
    artworkFetchTask = nil
    artworkFetchURL = nil
    if clearImage { nowPlayingArtwork = nil }
  }

  /// Now Playing yalnızca bitmap kabul eder (`MPMediaItemArtwork`); URL’yi biz indiriyoruz.
  private func scheduleNowPlayingArtworkFetch(for presentation: PlaybackPresentation) {
    guard let url = presentation.artworkURL else {
      cancelNowPlayingArtworkFetch(clearImage: true)
      return
    }
    if artworkFetchURL == url, nowPlayingArtwork != nil { return }
    if artworkFetchURL == url, artworkFetchTask != nil { return }

    cancelNowPlayingArtworkFetch(clearImage: true)
    artworkFetchURL = url

    let capturedURL = url
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if self.artworkFetchURL == capturedURL {
            self.nowPlayingArtwork = nil
            self.artworkFetchTask = nil
            self.artworkFetchURL = nil
            self.updateNowPlayingInfo(force: true)
          }
        }
        return
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard self.artworkFetchURL == capturedURL else { return }
        self.nowPlayingArtwork = image
        self.artworkFetchTask = nil
        self.updateNowPlayingInfo(force: true)
      }
    }
    artworkFetchTask = task
    task.resume()
  }

  private func setupRemoteCommands() {
    guard remoteCommandTargets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    let t1 = center.playCommand.addTarget { [weak self] _ in
      self?.mpvEngine.play()
      return .success
    }
    remoteCommandTargets.append((center.playCommand, t1))

    center.pauseCommand.isEnabled = true
    let t2 = center.pauseCommand.addTarget { [weak self] _ in
      self?.mpvEngine.pause()
      return .success
    }
    remoteCommandTargets.append((center.pauseCommand, t2))

    center.togglePlayPauseCommand.isEnabled = true
    let t3 = center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.togglePlayPause()
      return .success
    }
    remoteCommandTargets.append((center.togglePlayPauseCommand, t3))

    center.changePlaybackPositionCommand.isEnabled = true
    let tSeek = center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self,
            let e = event as? MPChangePlaybackPositionCommandEvent,
            self.durationMs > 0
      else { return .commandFailed }
      self.markSeekRequestStart()
      self.mpvEngine.seek(to: e.positionTime)
      return .success
    }
    remoteCommandTargets.append((center.changePlaybackPositionCommand, tSeek))

    center.skipForwardCommand.isEnabled = true
    center.skipForwardCommand.preferredIntervals = [15]
    let t4 = center.skipForwardCommand.addTarget { [weak self] _ in
      self?.jump(seconds: 15)
      return .success
    }
    remoteCommandTargets.append((center.skipForwardCommand, t4))

    center.skipBackwardCommand.isEnabled = true
    center.skipBackwardCommand.preferredIntervals = [15]
    let t5 = center.skipBackwardCommand.addTarget { [weak self] _ in
      self?.jump(seconds: -15)
      return .success
    }
    remoteCommandTargets.append((center.skipBackwardCommand, t5))

    center.previousTrackCommand.isEnabled = false
    let t6 = center.previousTrackCommand.addTarget { [weak self] _ in
      guard let cb = self?.seriesEpisodeOnPrevious else { return .commandFailed }
      cb()
      return .success
    }
    remoteCommandTargets.append((center.previousTrackCommand, t6))

    center.nextTrackCommand.isEnabled = false
    let t7 = center.nextTrackCommand.addTarget { [weak self] _ in
      guard let cb = self?.seriesEpisodeOnNext else { return .commandFailed }
      cb()
      return .success
    }
    remoteCommandTargets.append((center.nextTrackCommand, t7))
  }

  /// Kontrol Merkezi / kilit ekranından önceki–sonraki bölüm (yalnızca dizi oynatırken).
  /// - swapSkipForNav: true → skip komutları kapatılır, prev/next gösterilir (dizi & canlı TV).
  ///                   false → skip aktif kalır; filmler için her zaman false.
  func configureSeriesEpisodeSkipping(
    canPrevious: Bool,
    canNext: Bool,
    onPrevious: (() -> Void)?,
    onNext: (() -> Void)?,
    swapSkipForNav: Bool = true
  ) {
    seriesEpisodeOnPrevious = canPrevious ? onPrevious : nil
    seriesEpisodeOnNext = canNext ? onNext : nil
    let center = MPRemoteCommandCenter.shared()
    let hasEpisodeNav = (canPrevious && onPrevious != nil) || (canNext && onNext != nil)
    // iOS hides previousTrack/nextTrack buttons when skipForward/skipBackward are enabled.
    // For series & live TV: swap skip → prev/next. For movies: keep skip enabled.
    let disableSkip = swapSkipForNav && hasEpisodeNav
    center.skipForwardCommand.isEnabled = !disableSkip
    center.skipBackwardCommand.isEnabled = !disableSkip
    center.previousTrackCommand.isEnabled = swapSkipForNav && canPrevious && onPrevious != nil
    center.nextTrackCommand.isEnabled = swapSkipForNav && canNext && onNext != nil
  }

  private func removeRemoteCommands() {
    for (cmd, token) in remoteCommandTargets {
      cmd.removeTarget(token)
    }
    remoteCommandTargets.removeAll()
  }
}
