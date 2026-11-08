import AVKit
import AppKit
import Combine
import GRDB
import KSPlayer
import SwiftUI

struct MediaSelection: Equatable {
  var url: URL
  let playlistId: UUID
  let streamId: String
  let type: String
  let title: String
  var secondaryTitle: String?
  var artwork: String?
  var ext: String?
  var seriesId: String?
  var userAgent: String?
  var epgKey: String?
  var downloadID: String?
  enum StartPosition { case automatic, beginning, latestEpisode }
  var startPosition: StartPosition = .automatic
  var storesHistory = true
  var isLive: Bool { type == "live" }
  var historyID: String { "\(playlistId)_\(type)_\(streamId)" }

  private static func categoryName(_ id: String?, for item: CatalogItem, playlistID: UUID, in db: Database) throws -> String {
    guard let id else { return "" }
    return try DBCategory.filter(Column("playlistId") == playlistID && Column("type") == item.kind && Column("id") == id)
      .fetchOne(db)?.name ?? ""
  }

  static func resolve(_ item: CatalogItem, in source: Playlist, database: AppDatabase, fallbackExtension: String? = nil) async throws
    -> Self
  {
    let builder = PlaybackURLBuilder(playlist: source)
    let number = Int(item.streamKey) ?? 0
    var url: URL?
    var ext: String?
    var agent: String?
    var epgKey: String?
    var download: String?
    var type = item.kind
    var category = item.category
    var title = item.title
    var artwork = item.artwork
    switch item.media {
    case .live:
      url = builder.liveURL(streamId: number)
      let (row, currentCategory) = try await database.read { db in
        let row = try DBLiveStream.filter(Column("playlistId") == source.id && Column("streamId") == number)
          .fetchOne(db)
        return (row, try categoryName(row?.categoryId, for: item, playlistID: source.id, in: db))
      }
      if let row {
        category = currentCategory
        title = row.name
        artwork = row.streamIcon
      }
      epgKey = EPGStore.shared.storedKey(
        idKey: EPGConstants.normalizeChannelKey(row?.epgChannelId),
        nameKey: EPGConstants.normalizeChannelKey(row?.name ?? item.title))
    case .vod:
      let (row, currentCategory) = try await database.read { db in
        let row = try DBVODStream.filter(Column("playlistId") == source.id && Column("streamId") == number)
          .fetchOne(db)
        return (row, try categoryName(row?.categoryId, for: item, playlistID: source.id, in: db))
      }
      if let row {
        category = currentCategory
        title = row.name
        artwork = row.streamIcon
      }
      ext = row?.containerExtension ?? fallbackExtension
      url = builder.movieURL(streamId: number, containerExtension: ext)
      download = DownloadManager.idFor(vod: source.id, streamId: number)
    case .m3u:
      let channel = try await database.read { db in
        try DBM3UChannel.filter(Column("playlistId") == source.id && Column("id") == item.streamKey)
          .fetchOne(db)
      }
      if let channel, let valid = M3UParser.sanitizedURL(from: channel.url) {
        let media = M3UStreamClassifier.classify(url: valid, groupTitle: channel.groupTitle)
        title = channel.name
        artwork = channel.tvgLogo
        category = channel.groupTitle ?? ""
        url = valid
        type = media.playbackType
        ext = media.containerExtension
        agent = channel.userAgent
        if media.isLive {
          epgKey = EPGStore.shared.storedKey(
            idKey: EPGConstants.normalizeChannelKey(channel.tvgId),
            nameKey: EPGConstants.normalizeChannelKey(channel.tvgName ?? channel.name))
        }
        if !media.isLive {
          download = DownloadManager.idFor(m3uChannel: source.id, channelId: item.streamKey)
        }
      } else if item.isM3UMovie {
        return try await downloadedM3UMovie(item, database: database)
      }
    case .series: break
    }
    guard let url else { throw URLError(.badURL) }
    return Self(
      url: url, playlistId: source.id, streamId: item.streamKey, type: type, title: title,
      secondaryTitle: category, artwork: artwork, ext: ext, userAgent: agent,
      epgKey: epgKey,
      downloadID: download)
  }

  static func downloadedM3UMovie(_ item: CatalogItem, database: AppDatabase) async throws -> Self {
    let id = DownloadManager.idFor(m3uChannel: item.playlistId, channelId: item.streamKey)
    guard let local = await DownloadManager.shared.localURL(forId: id),
          let stored = try await database.read({ try DBDownloadedItem.fetchOne($0, key: id) })
    else { throw URLError(.badURL) }
    return Self(url: local, playlistId: item.playlistId, streamId: item.streamKey, type: "vod",
                title: stored.title, secondaryTitle: stored.secondaryTitle, artwork: stored.imageURL,
                ext: stored.containerExtension ?? local.pathExtension, downloadID: id)
  }

  func enqueueDownload(seasonNumber: Int? = nil, episodeNumber: Int? = nil) async {
    guard let downloadID else { return }
    await DownloadManager.shared.enqueue(
      id: downloadID, playlistId: playlistId, streamId: streamId,
      type: type == "series" ? "episode" : "vod", title: title, secondaryTitle: secondaryTitle,
      imageURL: artwork, remoteURL: url, containerExtension: ext, seriesId: seriesId,
      seasonNumber: seasonNumber, episodeNumber: episodeNumber)
  }

  static func episodeArtwork(_ episode: String?, _ series: String?, _ fallback: String?) -> String? {
    [episode, series, fallback]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  static func episode(_ episode: DBEpisode, series: CatalogItem, source: Playlist, currentSeries: DBSeries? = nil) throws -> Self {
    let id = episode.episodeId ?? episode.id
    guard !id.isEmpty, let url = PlaybackURLBuilder(playlist: source).seriesURL(
        streamId: id, containerExtension: episode.containerExtension)
    else { throw URLError(.badURL) }
    let artwork = episodeArtwork(episode.cover, currentSeries?.cover, series.artwork)
    return Self(
      url: url, playlistId: source.id, streamId: id, type: "series",
      title: SeriesDetailData.episodeTitle(episode),
      secondaryTitle: currentSeries?.name ?? series.title, artwork: artwork,
      ext: episode.containerExtension,
      seriesId: series.streamKey,
      downloadID: DownloadManager.idFor(episode: source.id, episodeId: id))
  }
}

@MainActor final class DesktopPlayback: ObservableObject {
  let engine: KSPlayerEngine
  let tracks: MacPlaybackTracks
  @Published private(set) var current: MediaSelection?
  @Published var expanded = false
  @Published private(set) var cast: CastController?
  @Published private(set) var pickerRequest: UUID?
  private var castSubscriptions = Set<AnyCancellable>()
  private var playbackURL: URL?
  private var presentingCast: CastController? {
    guard let cast, cast.isPresenting else { return nil }
    return cast
  }
  var duration: Double { presentingCast?.duration ?? engine.duration }
  var position: Double { presentingCast?.position ?? engine.position }
  var isPaused: Bool { presentingCast?.isPaused ?? engine.isPaused }
  var isBuffering: Bool {
    presentingCast?.isBuffering ?? (waitingToReconnect || !engine.isReady || engine.isBuffering)
  }

  var canSeek: Bool {
    guard current?.isLive == false, duration > 0 else { return false }
    return presentingCast?.isSeekable ?? true
  }


  func seek(to seconds: Double) {
    guard canSeek, seconds.isFinite else { return }
    cancelNextEpisode()
    systemPlayback.noteSeek(to: seconds)
    if let cast, cast.isPresenting {
      cast.seek(toSource: seconds)
    } else {
      engine.seek(to: seconds)
    }
  }

  func prepareAirPlay() {
    guard let url = playbackURL, let current, engine.isFFmpegBackendActive else { return }
    let controller = cast ?? makeCastController()
    let selectedSubtitle = tracks.subtitles.first { $0.id == tracks.subtitleID }
    let external = tracks.files.first {
      selectedSubtitle?.isExternal == true && $0.lastPathComponent == selectedSubtitle?.title
    }
    let content = CastController.Content(
      url: url, isLive: current.isLive, userAgent: current.userAgent,
      startAt: current.isLive ? 0 : engine.position, knownDuration: engine.duration,
      nativelyPlayable: false,
      startPaused: engine.isPaused, subtitleFileURL: external,
      subtitleName: selectedSubtitle?.title,
      subtitleLanguage: selectedSubtitle?.langCode,
      audioStreamIndex: tracks.audioID >= 0 ? tracks.audioID : nil,
      subtitleStreamIndex: engine.embeddedSubtitleStreamIndex(id: tracks.subtitleID),
      subtitleDelaySeconds: tracks.subtitleDelay, discoversSourceTracks: true)
    // A single audio track has no alternative for the native player to select.
    // Keep its index in the content in case the provider needs a remux.
    controller.startFromPlayer(content: content, engine: engine,
      requiresSelectedAudio: content.audioStreamIndex != nil && tracks.audio.count != 1
    ) { [weak self] ready in
      guard ready, let self else { return }
      controller.setVolume(volume * 100)
      pickerRequest = UUID()
    }
  }

  func didOpenPicker(request: UUID) {
    if pickerRequest == request { pickerRequest = nil }
  }

  private func makeCastController() -> CastController {
    let controller = castFactory()
    cast = controller
    tracks.cast = controller
    controller.$sourceTracks.removeDuplicates().compactMap { $0 }.sink { [weak tracks] catalog in
      tracks?.applyRemuxCatalog(catalog)
    }.store(in: &castSubscriptions)
    controller.attachOwner(
      token: UUID(),
      stopDirectPlayback: { [weak self] in
        self?.checkpoint()
        self?.cancelRecovery()
        self?.engine.stopPlayback()
      },
      resumeDirectPlayback: { [weak self] content, seconds in
        guard let self, playbackURL == content.url, current != nil else { return }
        retryAfterCast = true
        loadDirect(at: content.isLive ? nil : seconds, play: !content.startPaused)
      },
      onTimeTick: { [weak self] seconds in
        guard let self else { return }
        engine.updateSubtitleCue(at: seconds)
        if Date().timeIntervalSince(lastCheckpoint) >= 5 { checkpoint(seconds: seconds) }
      })
    controller.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &castSubscriptions)
    controller.$isContinuingLocally.removeDuplicates().receive(on: DispatchQueue.main)
      .sink { [weak self, weak controller] _ in
        guard let self, let controller, self.cast === controller else { return }
        controller.setLocalPlaybackSpeed(Float(speed))
      }.store(in: &castSubscriptions)
    controller.$isCompleted.removeDuplicates().filter { $0 }.sink { [weak self] _ in
      self?.advanceCompletedEpisode()
    }.store(in: &castSubscriptions)
    return controller
  }

  @Published private(set) var nextEpisodeSeconds: Int?
  private var nextEpisodeTask: Task<Void, Never>?
  private var isScrubbing = false
  private var sleepTimerDidPause = false

  func setScrubbing(_ active: Bool) {
    isScrubbing = active
    if active { cancelNextEpisode() }
  }

  private var autoNextEnabled: Bool {
    preferences.object(forKey: "player.autoPlayNextEpisode") as? Bool ?? true
  }

  private func advanceCompletedEpisode() {
    guard !sleepTimerDidPause, !isScrubbing, current?.type == "series", let index = queueIndex,
      queue?.items.indices.contains(index + 1) == true, nextEpisodeSeconds == nil,
      autoNextEnabled
    else { return }
    nextEpisodeSeconds = 5
    nextEpisodeTask = Task { [weak self] in
      for seconds in (0..<5).reversed() {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard let self else { return }
        guard autoNextEnabled else { cancelNextEpisode(); return }
        if seconds == 0 { playNextEpisodeNow(); return }
        nextEpisodeSeconds = seconds
      }
    }
  }

  func cancelNextEpisode() {
    nextEpisodeTask?.cancel()
    nextEpisodeTask = nil
    nextEpisodeSeconds = nil
  }

  func playNextEpisodeNow() {
    guard nextEpisodeSeconds != nil else { return }
    cancelNextEpisode()
    step(1)
  }

  private let preferences: UserDefaults
  @Published var aspect: VideoAspectMode {
    didSet { preferences.set(aspect.rawValue, forKey: "player.videoAspectMode") }
  }
  @Published private(set) var speed = 1.0
  @Published private(set) var sleepDeadline: Date?
  @Published private(set) var sleepPresetMinutes = 0
  private var sleepTask: Task<Void, Never>?

  var canChangeSpeed: Bool {
    current?.isLive == false && (presentingCast?.isContinuingLocally ?? true)
  }

  func setSpeed(_ value: Double) {
    guard canChangeSpeed, value.isFinite else { return }
    speed = min(3, max(0.25, value))
    if let cast, cast.isPresenting {
      cast.setLocalPlaybackSpeed(Float(speed))
    } else {
      engine.setPlaybackRate(speed)
    }
  }
  func setSleepTimer(seconds: TimeInterval?, presetMinutes: Int = 0) {
    sleepTask?.cancel()
    sleepDeadline = nil
    sleepPresetMinutes = 0
    guard let seconds, seconds.isFinite, seconds > 0 else { return }
    sleepPresetMinutes = presetMinutes
    sleepDeadline = Date().addingTimeInterval(seconds)
    sleepTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard let self else { return }
      sleepTimerDidPause = true
      cancelNextEpisode()
      playOnLoad = false
      if let cast, cast.isPresenting { cast.pause() } else { engine.pause() }
      checkpoint()
      sleepPresetMinutes = 0
      sleepDeadline = nil
    }
  }
  private var volumeBeforeMute = 0.3
  func toggleMute() {
    if volume > 0 {
      volumeBeforeMute = volume
      volume = 0
    } else {
      volume = volumeBeforeMute
    }
  }
  @Published var volume = 1.0 {
    didSet {
      engine.setVolume(volume * 100)
      cast?.setVolume(volume * 100)
    }
  }
  private(set) var channelBannerDeadline: Date?
  @Published private(set) var lastChannel: MediaSelection?
  private var lastChannelCatalog: MacCatalogQuery?
  private var originCatalog: MacCatalogQuery?
  var catalogOrder: CatalogOrder { originCatalog?.order ?? .provider }
  @Published private(set) var queue: MacQueue?
  @Published private(set) var queueIndex: Int?
  private var queueTask: Task<Void, Never>?
  private var completion: AnyCancellable?
  let detailRequests = PassthroughSubject<CatalogItem, Never>()

  func observeDetail(for media: MediaSelection, update: (CatalogItem?) -> Void) async throws {
    guard media.type == "vod" || media.type == "series" else { return }
    let observation = ValueObservation.tracking { db -> CatalogItem? in
      guard let source = try Playlist.fetchOne(db, key: media.playlistId) else { return nil }
      let kind: MediaKind = media.type == "series" ? .series : (source.kind == .m3u ? .m3u : .vod)
      guard let key = kind == .series ? media.seriesId : media.streamId else { return nil }
      let item = try MacCatalogQuery(playlistID: source.id, kinds: [kind], limit: 1, streamKey: key).fetch(db).first
      guard let item, kind != .m3u || item.isM3UMovie else { return nil }
      return item
    }
    for try await item in observation.removeDuplicates().values(in: database.reader) {
      try Task.checkCancellation()
      update(item)
    }
  }

  private let database: AppDatabase
  private var lastCheckpoint = Date.distantPast
  private(set) lazy var systemPlayback = MacSystemPlayback(session: self)
  private var loadTask: Task<Void, Never>?
  private var tick: AnyCancellable?
  private var loaded = false
  private var failureObserver: AnyCancellable?
  private var recoveryTask: Task<Void, Never>?
  private var liveBudget = LiveReloadBudget()
  private var retriedFailure = false
  private var newContent = false
  private var replacedLayer = false
  private var retryAfterCast = false
  private var resumeAt: Double?
  private var playOnLoad = true
  private var backgrounded = false
  private var allowsBackgroundPlayback = true

  func applyVisibility(hidden: Bool, minimized: Bool, allowsBackground: Bool) {
    engine.setWindowMinimized(minimized)
    let behind = hidden || minimized
    guard backgrounded != behind || allowsBackgroundPlayback != allowsBackground else { return }
    backgrounded = behind
    allowsBackgroundPlayback = allowsBackground
    guard current != nil, !engine.isPiPActive, engine.layer?.isPipActive != true,
          !engine.isExternalPlaybackActive, cast?.isExternalPlaybackActive != true else { return }
    if behind && !allowsBackground {
      playOnLoad = false
      if let cast, cast.isPresenting { cast.pause() } else { engine.pause() }
      checkpoint()
    }
  }
  private var healthySince: Date?
  private var lastHealthy: Date?
  @Published private(set) var waitingToReconnect = false

  private var healthySeconds: Double {
    guard let healthySince, let lastHealthy else { return 0 }
    return lastHealthy.timeIntervalSince(healthySince)
  }

  private func cancelRecovery() {
    recoveryTask?.cancel()
    recoveryTask = nil
    waitingToReconnect = false
  }

  private func loadDirect(at seconds: Double?, play: Bool) {
    guard let media = current, let playbackURL else { return }
    resumeAt = seconds
    playOnLoad = play && (!backgrounded || allowsBackgroundPlayback || engine.isPiPActive || engine.isExternalPlaybackActive)
    healthySince = nil
    lastHealthy = nil
    engine.load(
      playbackURL, play: playOnLoad, startSeconds: seconds, liveLowLatency: media.isLive,
      userAgent: media.userAgent)
    engine.setVolume(volume * 100)
    engine.setPlaybackRate(speed)
    engine.setSubDelay(seconds: tracks.subtitleDelay)
  }

  private func scheduleRecovery(after delay: Double) {
    guard recoveryTask == nil, let media = current, playbackURL != nil, cast?.isEngaged != true
    else { return }
    let position =
      engine.isPlaybackEstablished && engine.position > 0.5 ? engine.position : resumeAt
    waitingToReconnect = true
    Log.info("Playback", "Retrying playback in \(delay)s")
    recoveryTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self, current == media, cast?.isEngaged != true else { return }
      recoveryTask = nil
      waitingToReconnect = false
      loadDirect(at: media.isLive ? nil : position, play: playOnLoad)
    }
  }

  func retryCurrentMedia() {
    guard let current, let playbackURL, cast?.isPresenting != true else { return }
    if playbackURL.isFileURL && !FileManager.default.fileExists(atPath: playbackURL.path) {
      start(current)
      return
    }
    cancelRecovery()
    liveBudget.reset()
    retriedFailure = false
    newContent = false
    retryAfterCast = false
    let seconds = engine.isPlaybackEstablished && engine.position > 0.5 ? engine.position : resumeAt
    loadDirect(at: current.isLive ? nil : seconds, play: true)
  }

  private func directStreamEnded() {
    guard cast?.isEngaged != true else { return }
    guard current?.isLive == true, engine.duration <= 0,
      let delay = liveBudget.nextDelay(stablePlaybackSeconds: healthySeconds)
    else {
      engine.markLiveStreamEnded()
      return
    }
    scheduleRecovery(after: delay)
  }

  private func directLoadFailed() {
    guard current != nil, playbackURL != nil, cast?.isEngaged != true, recoveryTask == nil else {
      return
    }
    if let media = current, media.type == "catchup" {
      let elapsed = engine.position
      Task {
        await CatchupURLResolver.reportPlaybackFailure(of: media.url, playedSeconds: elapsed,
          playlistId: media.playlistId, in: database)
      }
    }
    let healthy = healthySeconds >= 30
    if healthy { retriedFailure = false }
    defer {
      newContent = false
      retryAfterCast = false
    }
    if retryAfterCast && !healthy {
      retriedFailure = true
      scheduleRecovery(after: 2)
      return
    }
    if newContent {
      let decision = VideoPlayerControllerLogic.zapRetryDecision(
        retryAlreadyScheduled: false, castOwnsContent: false,
        hadHealthyStretch: healthy, failureIsRecoverable: engine.playbackFailureIsRecoverable,
        hasLoadRequest: true,
        failureWantsDelayedRetry: engine.playbackFailureWantsDelayedRetry,
        isLiveStream: current?.isLive == true, replacedActiveLayer: replacedLayer)
      if decision != .none {
        retriedFailure = true
        scheduleRecovery(
          after: decision == .afterForbidden
            ? VideoPlayerControllerLogic.forbiddenRetryDelaySeconds : 2)
        return
      }
    }
    if engine.playbackFailureIsRecoverable && !retriedFailure {
      retriedFailure = true
      scheduleRecovery(after: 0)
    }
  }

  private let castFactory: @MainActor () -> CastController

  init(
    database: AppDatabase = .shared, preferences: UserDefaults = .standard,
    castFactory: @escaping @MainActor () -> CastController = { CastController() }
  ) {
    self.preferences = preferences
    self.aspect = preferences.string(forKey: "player.videoAspectMode").flatMap(VideoAspectMode.init(rawValue:)) ?? .fit
    self.castFactory = castFactory
    let engine = KSPlayerEngine()
    self.engine = engine
    self.tracks = MacPlaybackTracks(engine: engine)
    self.database = database
    engine.onLiveStreamEnded = { [weak self] in self?.directStreamEnded() }
    engine.onReloadRequested = { [weak self] in
      guard let self, cast?.isEngaged != true else { return }
      cancelRecovery()
      liveBudget.reset()
      retriedFailure = false
      loadDirect(at: nil, play: true)
    }
    failureObserver = engine.$playbackFailureMessage.compactMap { $0 }.sink { [weak self] _ in
      self?.directLoadFailed()
    }
    completion = engine.$isCompleted.removeDuplicates().filter { $0 }.sink { [weak self] _ in
      self?.advanceCompletedEpisode()
    }
    tick = engine.$position.sink { [weak self] seconds in
      guard let self else { return }
      engine.updateSubtitleCue(at: seconds)
      if engine.isPlaybackEstablished && !engine.isBuffering && !engine.isPaused
        && engine.playbackFailureMessage == nil
      {
        let now = Date()
        if healthySince == nil { healthySince = now }
        lastHealthy = now
      }
      guard Date().timeIntervalSince(lastCheckpoint) >= 5 else { return }
      checkpoint(seconds: seconds)
    }
  }

  func start(_ media: MediaSelection, catalog: MacCatalogQuery? = nil) {
    start(media, catalog: catalog, retained: nil)
  }

  private func start(_ media: MediaSelection, catalog: MacCatalogQuery?, retained: MacQueue?, expand: Bool = true) {
    let previousSpeed = speed
    let wasExternal = engine.isExternalPlaybackActive
    let replacing = engine.layer != nil && engine.playbackFailureMessage == nil
    if let previous = current, previous.isLive, media.isLive, previous.playlistId == media.playlistId {
      if previous.streamId != media.streamId {
        channelBannerDeadline = Date().addingTimeInterval(3)
        lastChannel = previous
        lastChannelCatalog = originCatalog
      }
    } else {
      channelBannerDeadline = nil
      lastChannel = nil
      lastChannelCatalog = nil
    }
    originCatalog = catalog
    reset(preservingCast: cast?.isEngaged == true)
    newContent = true
    replacedLayer = replacing
    current = media
    playOnLoad = true
    systemPlayback.start(media)
    speed = media.isLive ? 1 : previousSpeed
    expanded = expand
    if let retained, let index = retained.items.firstIndex(where: { $0.id == media.streamId }) {
      queue = retained
      queueIndex = index
    } else {
      queueTask = Task {
        do {
          let new = try await MacQueue.load(for: media, catalog: catalog, in: database)
          guard !Task.isCancelled, current == media else { return }
          queue = new
          queueIndex = new?.items.firstIndex { $0.id == media.streamId }
        } catch { if !Task.isCancelled { Log.error("Queue", NetworkErrorText.describe(error)) } }
      }
    }
    loadTask = Task {
      var resume: Int?
      if !media.isLive, media.storesHistory, media.startPosition != .beginning {
        let history = try? await database.read { db in
          try DBWatchHistory.fetchOne(db, key: media.historyID)
        }
        resume = media.startPosition == .latestEpisode ? history?.lastTimeMs
          : history?.resumePositionMs(as: media.type == "series" ? .episode : .film)
      }
      var url = media.url
      if let id = media.downloadID, let local = await DownloadManager.shared.localURL(forId: id) {
        url = local
      }
      guard !Task.isCancelled, current == media else { return }
      tracks.prepare(
        ImportedSubtitleStore.contentKey(
          playlistId: media.playlistId, type: media.type, streamId: media.streamId))
      playbackURL = url
      if cast?.isEngaged == true || wasExternal {
        let controller = cast ?? makeCastController()
        let native = !KSPlayerEngine.prefersFFmpegFirst(for: url)
        let key = ImportedSubtitleStore.contentKey(
          playlistId: media.playlistId, type: media.type, streamId: media.streamId)
        let selected = ImportedSubtitleStore.selectedFileName(for: key)
        let file = tracks.files.first { $0.lastPathComponent == selected }
        let content = CastController.Content(
          url: url, isLive: media.isLive, userAgent: media.userAgent,
          startAt: resume.map { Double($0) / 1000 } ?? 0, knownDuration: 0,
          nativelyPlayable: native, subtitleFileURL: file, subtitleName: selected,
          subtitleDelaySeconds: tracks.subtitleDelay, discoversSourceTracks: true,
          applyTrackPreferences: true)
        if controller.isEngaged {
          if controller.playContent(content) {
            loaded = true
            return
          }
        } else if native {
          controller.continueNativeExternalPlayback(with: content)
          loaded = true
          return
        } else if controller.startRemuxCast(
          content: content, fromButton: false, completion: { _ in })
        {
          loaded = true
          return
        }
      }
      loadDirect(at: resume.map { Double($0) / 1000 }, play: playOnLoad)
      loaded = true
    }
  }

  func checkpoint(seconds: Double? = nil) {
    guard loaded, let item = current, item.storesHistory,
      cast?.isPresenting == true
        ? cast?.isPlaybackEstablished == true : engine.isPlaybackEstablished
    else {
      return
    }
    let seconds = seconds ?? position
    let duration = self.duration
    guard seconds.isFinite, duration.isFinite, item.isLive || duration > 0 else { return }
    lastCheckpoint = Date()
    let record = DBWatchHistory(
      id: item.historyID, playlistId: item.playlistId, streamId: item.streamId, type: item.type,
      lastTimeMs: Int(max(seconds, 0) * 1000), durationMs: Int(max(duration, 0) * 1000),
      lastWatchedAt: lastCheckpoint,
      seriesId: item.seriesId, title: item.title, secondaryTitle: item.secondaryTitle,
      imageURL: item.artwork, containerExtension: item.ext)
    Task {
      do {
        try await database.write { db in
          guard try Playlist.fetchOne(db, key: record.playlistId) != nil else { return }
          if let existing = try DBWatchHistory.fetchOne(db, key: record.id),
            existing.lastWatchedAt > record.lastWatchedAt
          {
            return
          }
          try record.save(db)
        }
      } catch {
        Log.error("WatchHistory", "Could not save playback progress: \(error.localizedDescription)")
      }
    }
  }
  func step(_ offset: Int) {
    guard let index = queueIndex, let queue, queue.items.indices.contains(index + offset) else {
      return
    }
    choose(queue.items[index + offset])
  }
  func choose(_ item: MacQueueItem) {
    cancelNextEpisode()
    guard let queue else { return }
    queueTask?.cancel()
    queueTask = Task {
      do {
        let media = try await item.resolve(source: queue.source, database: database)
        try Task.checkCancellation()
        start(media, catalog: originCatalog, retained: queue, expand: expanded)
      } catch { if !Task.isCancelled { Log.error("Queue", NetworkErrorText.describe(error)) } }
    }
  }
  func tune(_ item: CatalogItem, in source: Playlist, catalog: MacCatalogQuery) async throws {
    let media = try await MediaSelection.resolve(item, in: source, database: database)
    try Task.checkCancellation()
    guard current?.isLive == true, current?.playlistId == source.id, media.isLive else { return }
    start(media, catalog: catalog)
  }

  func recallLastChannel() {
    guard let lastChannel, let current, current.isLive, lastChannel.playlistId == current.playlistId else { return }
    start(lastChannel, catalog: lastChannelCatalog)
  }
  func close() {
    channelBannerDeadline = nil
    lastChannel = nil
    lastChannelCatalog = nil
    originCatalog = nil
    setSleepTimer(seconds: nil)
    reset(preservingCast: false)
  }

  private func reset(preservingCast: Bool) {
    sleepTimerDidPause = false
    isScrubbing = false
    cancelNextEpisode()
    checkpoint()
    if current != nil { systemPlayback.stop() }
    cancelRecovery()
    liveBudget.reset()
    retriedFailure = false
    retryAfterCast = false
    newContent = false
    playbackURL = nil
    pickerRequest = nil
    if !preservingCast {
      cast?.dispose()
      castSubscriptions.removeAll()
      cast = nil
    }
    loadTask?.cancel()
    loadTask = nil
    queueTask?.cancel()
    queueTask = nil
    queue = nil
    queueIndex = nil
    speed = 1
    tracks.prepare(nil)
    loaded = false
    lastCheckpoint = .distantPast
    if current != nil { engine.stopPlayback() }
    current = nil
    expanded = false
  }
  func toggle() {
    if isPaused { sleepTimerDidPause = false }
    if let cast, cast.isPresenting {
      if cast.isPaused {
        cast.play()
      } else {
        cast.pause()
        checkpoint()
      }
      return
    }
    playOnLoad = engine.isPaused
    if engine.isPaused {
      engine.play()
    } else {
      engine.pause()
      checkpoint()
    }
  }
}

struct MacVideoSurface: NSViewRepresentable {
  let engine: KSPlayerEngine
  let revision: Int
  func makeNSView(context: Context) -> NSView {
    let host = VideoHost()
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor.black.cgColor
    return host
  }
  // The native decoder surface only draws pixels. Let the enclosing SwiftUI
  // picture handle clicks, magnification and dragging.
  private final class VideoHost: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  func updateNSView(_ host: NSView, context: Context) {
    guard let video = engine.videoView else {
      host.subviews.forEach { $0.removeFromSuperview() }
      return
    }
    guard host.subviews.first !== video else { return }
    host.subviews.forEach { $0.removeFromSuperview() }
    video.frame = host.bounds
    video.autoresizingMask = [.width, .height]
    host.addSubview(video)
  }
}

private struct MacNextEpisodeControls: View {
  let session: DesktopPlayback
  let seconds: Int

  var body: some View {
    HStack {
      Button(L("common.cancel"), action: session.cancelNextEpisode)
      Button(action: session.playNextEpisodeNow) {
        Label(L("player.autonext.countdown", seconds), systemImage: "play.fill").monospacedDigit()
      }.buttonStyle(.borderedProminent)
    }
  }
}

struct MacPlayerBar: View {
  @ObservedObject var session: DesktopPlayback
  @ObservedObject var engine: KSPlayerEngine
  @ObservedObject private var guide = EPGStore.shared
  let media: MediaSelection
  private var programmeTitle: String? {
    guard media.isLive else { return nil }
    return guide.nowNext(playlistId: media.playlistId, channelKey: media.epgKey)?.now?.title
  }
  var body: some View {
    HStack(spacing: 14) {
      Button {
        session.expanded = true
      } label: {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: media.title)
            if let programmeTitle {
              Text(verbatim: programmeTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          }
        } icon: { Image(systemName: "play.rectangle") }
      }.buttonStyle(.plain).accessibilityLabel(media.title)
        .accessibilityValue(programmeTitle.map { L("epg.a11y.now_playing_format", $0) } ?? "")
      Spacer()
      if let seconds = session.nextEpisodeSeconds {
        MacNextEpisodeControls(session: session, seconds: seconds)
      }
      Button {
        session.toggle()
      } label: {
        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
      }.font(.title3).accessibilityLabel(L(session.isPaused ? "player.a11y.play" : "player.a11y.pause"))
      Button {
        session.close()
      } label: {
        Image(systemName: "xmark")
      }.accessibilityLabel(L("common.close"))
    }.padding(12).background(.bar)
  }
}

private struct MacLiveProgramme: View {
  @ObservedObject private var guide = EPGStore.shared
  @Environment(\.appDatabase) private var database
  @State private var upcoming: EPGProgramme?
  let media: MediaSelection
  let bannerDeadline: Date?
  let suppressBanner: Bool
  @State private var showingBanner = false

  var body: some View {
    let programme = guide.nowNext(playlistId: media.playlistId, channelKey: media.epgKey)?.now
    let nextLine: String? = programme.flatMap { now in
      guard let upcoming, upcoming.channelKey == now.channelKey, upcoming.start > now.start else { return nil }
      if Calendar.current.isDate(now.start, inSameDayAs: upcoming.start) {
        return PlayerProgrammeStrip.nextLine(upcoming)
      }
      let day = EPGTimeFormat.dayLabel(upcoming.start, wide: false)
      return L("epg.next_format", "\(day) \(EPGTimeFormat.time(upcoming.start)) \(upcoming.title)")
    }
    VStack(spacing: 0) {
      if let programme {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: programme.title).font(.headline).lineLimit(1)
              .accessibilityLabel(L("epg.a11y.now_playing_format", programme.title))
            Text(verbatim: EPGTimeFormat.range(programme.start, programme.stop))
              .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let nextLine {
              Text(verbatim: nextLine)
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          TimelineView(.periodic(from: .now, by: 30)) { tick in
            ProgressView(value: programme.progress(at: tick.date) ?? 1).progressViewStyle(.linear)
              .accessibilityHidden(true)
          }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
      }
    }
    .frame(maxWidth: .infinity)
    .overlay(alignment: .topLeading) {
      if showingBanner && !suppressBanner {
        HStack(spacing: 10) {
          CachedImage(url: media.artwork.flatMap(URL.init(string:)), width: 40, height: 40,
                      cornerRadius: 6, iconName: "tv", loadProfile: .standard)
          VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: media.title).font(.headline).lineLimit(1)
            if let programme {
              Text(verbatim: EPGTimeFormat.range(programme.start, programme.stop) + " · " + programme.title)
                .font(.caption).lineLimit(1)
              if let nextLine { Text(verbatim: nextLine).font(.caption).lineLimit(1) }
            }
          }
        }
        .padding(10).frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).environment(\.colorScheme, .dark)
        .padding(.leading, 12).padding(.bottom, 12)
        .visualEffect { card, size in card.offset(y: -size.size.height) }
        .accessibilityElement(children: .combine).accessibilityIdentifier("liveChannelBanner")
        .allowsHitTesting(false)
      }
    }
    .task(id: bannerDeadline) {
      guard let bannerDeadline, bannerDeadline.timeIntervalSinceNow > 0 else { showingBanner = false; return }
      showingBanner = true
      if NSWorkspace.shared.isVoiceOverEnabled, let window = NSApp.keyWindow {
        NSAccessibility.post(element: window, notification: .announcementRequested,
          userInfo: [.announcement: media.title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
      }
      do { try await Task.sleep(for: .seconds(max(0, bannerDeadline.timeIntervalSinceNow))) } catch { return }
      showingBanner = false
    }
    .task(id: programme) {
      upcoming = nil
      guard let programme else { return }
      let following = ValueObservation.tracking { db in
        try PlayerNextProgrammeQuery.fetch(
          db, playlistId: media.playlistId, channelKey: programme.channelKey,
          after: programme.start, now: Date())
      }
      do {
        for try await next in following.values(in: database.reader) {
          try Task.checkCancellation()
          if upcoming != next { upcoming = next }
        }
      } catch {
        if !Task.isCancelled { upcoming = nil }
      }
    }
  }
}

struct MacPlayerView: View {
  @ObservedObject var session: DesktopPlayback
  @ObservedObject var engine: KSPlayerEngine
  let media: MediaSelection
  @State private var detailItem: CatalogItem?
  @State private var showSubtitleStyle = false
  @State private var showDiagnosticsSettings = false
  @AppStorage("player.debugOverlayEnabled") private var showDiagnostics = false
  @State private var seek: Double?
  @State private var windowAnchor = NSView(frame: .zero)
  @FocusState private var keyboardFocused: Bool
  @State private var showPlaybackSettings = false
  @State private var showTrackSettings = false
  @State private var showQueue = false
  @State private var queueFilter = ""
  @State private var isHoldingForSpeed = false
  @State private var aspectNotice: VideoAspectMode?
  @AppStorage("player.speedUpOnLongPress") private var canHold = true
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @State private var controlsIdle = false
  @State private var hoveringControls = false
  @State private var menuTracking = false
  @State private var transportHeight: CGFloat = 0
  @State private var hideDeadline = ContinuousClock.now.advanced(by: .seconds(3))

  private var mayHideControls: Bool {
    !voiceOver && !NSApp.isFullKeyboardAccessEnabled && !session.isPaused && !session.isBuffering &&
      !engine.isCompleted && engine.playbackFailureMessage == nil && !session.waitingToReconnect &&
      !showSubtitleStyle && !showDiagnosticsSettings && !showPlaybackSettings && !showTrackSettings && !showQueue && !menuTracking &&
      seek == nil && !isHoldingForSpeed
  }

  private var controlsVisible: Bool { !controlsIdle || !mayHideControls }

  private func revealControls() {
    hideDeadline = .now.advanced(by: .seconds(3))
    controlsIdle = false
  }

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < 660
      ZStack(alignment: .trailing) {
        HStack(spacing: 0) {
          playerContent(compact: compact || showSubtitleStyle).frame(maxWidth: .infinity)
          if showSubtitleStyle && !compact { stylePanel }
        }
        if showSubtitleStyle && compact {
          stylePanel.background(.regularMaterial)
        }
      }
    }
  }

  private var stylePanel: some View {
    SubtitleAppearanceSheet(player: session.tracks) {
      showSubtitleStyle = false
      keyboardFocused = true
    }.frame(width: 350).clipped()
  }

  private func playerContent(compact: Bool) -> some View {
    VStack(spacing: 0) {
      picture
        .overlay(alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 0) {
            if controlsVisible {
              HStack(spacing: 8) {
                Button { session.close() } label: {
                  Image(systemName: "xmark").frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain).help(L("common.close")).accessibilityLabel(L("common.close"))
                header.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
              }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(12).onHover { hoveringControls = $0 }
            }
            if showDiagnostics {
              MacPlaybackDiagnostics(engine: engine, isNetwork: !media.url.isFileURL)
                .id(media.historyID).padding(12).environment(\.colorScheme, .dark)
            }
          }
        }
        .overlay(alignment: .bottom) {
          if controlsVisible {
            transport(compact: compact).frame(maxWidth: 760)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
              .padding([.horizontal, .bottom], 16)
              .onHover { hoveringControls = $0 }

              .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { transportHeight = $0 }
          }
        }
    }
    .background(.background)
      .background(MacPlayerWindowAnchor(view: windowAnchor).frame(width: 0, height: 0))
      .task(id: media.historyID) {
        detailItem = nil
        try? await session.observeDetail(for: media) { detailItem = $0 }
      }
      .focusable(interactions: .edit).focused($keyboardFocused).focusEffectDisabled()
      .onAppear {
        keyboardFocused = true
      }
      .onDisappear { session.setScrubbing(false) }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { event in
        guard let window = event.object as? NSWindow, window === windowAnchor.window else { return }
        revealControls()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { event in
        guard let window = event.object as? NSWindow, window === windowAnchor.window else { return }
        revealControls()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
        if windowAnchor.window?.isKeyWindow == true { menuTracking = true }
      }
      .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
        menuTracking = false
      }
      .onContinuousHover { phase in
        if case .active = phase { revealControls() }
      }
      .onChange(of: mayHideControls) { _, _ in revealControls() }
      .onChange(of: media.historyID) { _, _ in setSpeedHold(false); revealControls() }
      .onChange(of: engine.isPaused) { _, paused in if paused { setSpeedHold(false) } }
      .task(id: mayHideControls && !controlsIdle) {
        guard mayHideControls, !controlsIdle else { return }
        while true {
          do { try await Task.sleep(until: hideDeadline, clock: .continuous) } catch { return }
          guard ContinuousClock.now >= hideDeadline else { continue }
          hoveringControls = false
          controlsIdle = true
          return
        }
      }
      .onKeyPress(phases: .down, action: handlePlayerKey)
  }

  private func minimizePlayer() {
    session.cancelNextEpisode()
    setSpeedHold(false)
    session.expanded = false
  }

  private var header: some View {
    HStack {
      Button {
        minimizePlayer()
      } label: {
        Image(systemName: "rectangle.bottomthird.inset.filled")
      }.accessibilityLabel(ML("minimize")).help(ML("minimize"))
      VStack(alignment: .leading) {
        if let detailItem {
          Button {
            minimizePlayer()
            session.detailRequests.send(detailItem)
          } label: {
            HStack(spacing: 4) {
              Text(verbatim: media.title).font(.headline)
              Image(systemName: "chevron.forward").font(.caption)
            }
          }.buttonStyle(.plain).accessibilityLabel(media.title)
        } else {
          Text(verbatim: media.title).font(.headline)
        }
        if let secondary = media.secondaryTitle {
          Text(verbatim: secondary).font(.caption).foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
      Button {
        showDiagnosticsSettings.toggle()
      } label: {
        Image(systemName: "waveform.path.ecg")
      }.help(L("player.dev_section")).accessibilityLabel(L("player.dev_section"))
        .popover(isPresented: $showDiagnosticsSettings) {
          MacDiagnosticControls(showOverlay: $showDiagnostics, url: media.url)
        }
    }.buttonStyle(.borderless).padding(12)
  }

  private var canStartSpeedHold: Bool {
    canHold && !media.isLive && !engine.isPaused && !showSubtitleStyle && !showQueue && !showDiagnosticsSettings
  }

  private func setSpeedHold(_ active: Bool) {
    guard active != isHoldingForSpeed, !active || canStartSpeedHold else { return }
    isHoldingForSpeed = active
    engine.setPlaybackRate(active ? 2 : session.speed)
  }

  private var pictureRetry: (() -> Void)? {
    guard !session.waitingToReconnect, engine.playbackFailureMessage != nil || (media.isLive && engine.isCompleted) else { return nil }
    return session.retryCurrentMedia
  }

  private var picture: some View {
    ZStack(alignment: .bottom) {
      if let cast = session.cast, cast.isPresenting {
        if let video = cast.castVideoView {
          MacCastSurface(video: video, aspect: session.aspect).id(cast.surfaceRevision)
            .onTapGesture(count: 2) { windowAnchor.window?.toggleFullScreen(nil) }
        } else {
          Color.black
        }
        if cast.isExternalPlaybackActive {
          Label(L("player.airplay_active"), systemImage: "airplayvideo").padding().background(
            .regularMaterial, in: Capsule())
        }
      } else {
        MacPicture(engine: engine, aspect: $session.aspect, mediaID: media.historyID,
          togglePlayback: session.toggle,
          retry: pictureRetry,
          minimize: minimizePlayer, showControls: controlsVisible ? nil : revealControls,
          toggleSpeed: canStartSpeedHold || isHoldingForSpeed ? { setSpeedHold(!isHoldingForSpeed) } : nil,
          hold: { active in
            if !active || !hoveringControls { setSpeedHold(active) }
          }) {
          guard !hoveringControls, !showSubtitleStyle, !showQueue, !showDiagnosticsSettings else { return }
          windowAnchor.window?.toggleFullScreen(nil)
        }

      }
      if session.cast?.isPresenting != true {
        KSSubtitleTextLayer(engine: engine, minimumBottomClearance: controlsVisible ? transportHeight : 0)
      }
      if !session.waitingToReconnect, session.cast?.isPresenting != true,
        let message = engine.playbackFailureMessage
      {
        ContentUnavailableView {
          Label(L("loading.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button(L("common.try_again"), action: session.retryCurrentMedia)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if media.isLive && engine.isCompleted && session.cast?.isPresenting != true {
        VStack(spacing: 10) {
          Text(L("player.ended")).font(.headline)
          Button(L("common.try_again"), action: session.retryCurrentMedia)
        }.padding().background(.regularMaterial, in: .rect(cornerRadius: 8))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if session.waitingToReconnect {
        ProgressView(ML("reconnecting")).foregroundStyle(.white).controlSize(.large)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if session.isBuffering {
        GeometryReader { bounds in
          let size = min(280, min(bounds.size.width, bounds.size.height) * 0.5)
          VStack(spacing: 12) {
            if size >= 32, !engine.isPlaybackEstablished, session.cast?.isPresenting != true,
               let artwork = media.artwork.flatMap(URL.init(string:)) {
              CachedImage(url: artwork, width: size, height: size, cornerRadius: 14,
                contentMode: .fit, iconName: media.isLive ? "tv" : "film", loadProfile: .standard)
                .opacity(0.5).accessibilityHidden(true)
            }
            ProgressView().controlSize(.large)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.allowsHitTesting(false)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay(alignment: .center) {
        if let seconds = session.nextEpisodeSeconds {
          MacNextEpisodeControls(session: session, seconds: seconds).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .overlay(alignment: .top) {
        VStack(spacing: 6) {
          if isHoldingForSpeed { playerNotice("2×", icon: "forward.fill") }
          if let aspectNotice { playerNotice(aspectNotice.title, icon: aspectNotice.iconName) }
        }.padding(.top, 12).allowsHitTesting(false)
      }
      .onChange(of: session.aspect) { _, mode in
        aspectNotice = mode
        if voiceOver { AccessibilityNotification.Announcement(mode.title).post() }
      }
      .task(id: aspectNotice) {
        guard aspectNotice != nil else { return }
        do { try await Task.sleep(for: .milliseconds(1300)) } catch { return }
        aspectNotice = nil
      }
      .environment(\.colorScheme, .dark)
  }

  private func playerNotice(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.headline).padding(.horizontal, 12).padding(.vertical, 6)
      .background(.regularMaterial, in: Capsule())
  }

  private func transport(compact: Bool) -> some View {
    VStack(spacing: 0) {
      if media.isLive {
        MacLiveProgramme(media: media, bannerDeadline: session.channelBannerDeadline,
                         suppressBanner: showQueue || session.waitingToReconnect || engine.playbackFailureMessage != nil)
          .id(media.historyID)
      }
      VStack(spacing: 10) {
        if let notice = session.cast?.lastNotice, let key = notice.reason.messageKey {
          Text(
            (notice.reason == .noWiFi ? ML("airplay_network") : L(key))
              + (notice.soundStaysOnRoute
                ? " " + L("player.airplay.notice.sound_stays_on_airplay") : "")
          )
          .font(.callout).foregroundStyle(.secondary)
        }
        if session.canSeek {
          HStack {
            Text(DetailFormatting.formatMs(Int((seek ?? session.position) * 1000)))
              .monospacedDigit()
            Slider(
              value: Binding(
                get: { seek ?? min(session.position, session.duration) }, set: { seek = $0 }),
              in: 0...max(1, session.duration)
            ) {
              Text(L("movie.duration"))
            } onEditingChanged: { editing in
              session.setScrubbing(editing)
              if !editing, let target = seek {
                session.seek(to: target)
                seek = nil
              }
            }.labelsHidden()
            Text(DetailFormatting.formatMs(Int(session.duration * 1000))).monospacedDigit()
          }
        }
        HStack(spacing: compact ? 6 : 12) {
          Button {
            session.toggle()
          } label: {
            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
          }.font(.title3).accessibilityLabel(L(session.isPaused ? "player.a11y.play" : "player.a11y.pause"))
          if !media.isLive {
            Button {
              session.seek(to: max(0, session.position - 15))
            } label: {
              Label(L("player.a11y.skip_back_15"), systemImage: "gobackward.15")
            }.labelStyle(.iconOnly).help(L("player.a11y.skip_back_15"))
            Button {
              session.seek(to: min(session.duration, session.position + 15))
            } label: {
              Label(L("player.a11y.skip_forward_15"), systemImage: "goforward.15")
            }.labelStyle(.iconOnly).help(L("player.a11y.skip_forward_15"))
          }
          if media.isLive, let last = session.lastChannel {
            Button(action: session.recallLastChannel) {
              Label(L("player.a11y.last_channel"), systemImage: "arrow.uturn.backward.circle")
            }.labelStyle(.iconOnly)
              .help(L("player.a11y.last_channel") + " · " + last.title + " (L)")
              .accessibilityValue(last.title)
          }
          if let queue = session.queue, let index = session.queueIndex {
            Button {
              session.step(-1)
            } label: {
              Label(ML("previous"), systemImage: "backward.end.fill")
            }.labelStyle(.iconOnly).disabled(index == 0).help(ML("previous"))
            Button {
              session.step(1)
            } label: {
              Label(ML("next"), systemImage: "forward.end.fill")
            }.labelStyle(.iconOnly).disabled(index + 1 >= queue.items.count).help(ML("next"))
            Button {
              showQueue.toggle()
            } label: {
              Image(systemName: "list.bullet")
            }.accessibilityLabel(L(media.isLive ? "player.all_channels" :
              media.type == "series" ? "dashboard.series" : "dashboard.movies"))
            .help(L(media.isLive ? "player.all_channels" :
              media.type == "series" ? "dashboard.series" : "dashboard.movies"))
            .popover(isPresented: $showQueue) {
              if media.isLive, case let .catalog(current) = queue.items[index] {
                MacLiveChannelPicker(source: queue.source, current: current,
                                     order: session.catalogOrder, didTune: { showQueue = false })
                  .environmentObject(session)
              } else {
                VStack {
                  TextField(L("search.placeholder"), text: $queueFilter).textFieldStyle(
                    .roundedBorder)
                  List(
                    queue.items.filter {
                      queueFilter.isEmpty || $0.title.localizedCaseInsensitiveContains(queueFilter)
                    }
                  ) { item in
                    Button {
                      showQueue = false
                      session.choose(item)
                    } label: {
                      HStack {
                        Text(item.title)
                        Spacer()
                        if item.id == media.streamId { Image(systemName: "speaker.wave.2") }
                      }
                    }
                    .buttonStyle(.plain)
                  }
                }.padding(12).frame(width: 300, height: 330)
              }
            }
          }
          Button(action: session.toggleMute) {
            Image(systemName: session.volume == 0 ? "speaker.slash" : "speaker.wave.2")
          }
          .buttonStyle(.plain)
          .accessibilityLabel(ML(session.volume == 0 ? "unmute" : "mute"))
          .help(ML(session.volume == 0 ? "unmute" : "mute"))
          if !compact {
            Slider(value: $session.volume, in: 0...1).frame(width: 60)
              .accessibilityLabel(ML("volume"))
          }
          Spacer(minLength: 2)
          Button { showPlaybackSettings.toggle() } label: {
            Label(L("settings.player.title"), systemImage: "ellipsis.circle")
          }.labelStyle(.iconOnly)
          .popover(isPresented: $showPlaybackSettings) {
            playbackSettings(compact: compact)
          }
          MacTrackMenu(
            editStyle: { showSubtitleStyle = true }, tracks: session.tracks,
            supportsAudioDelay: engine.supportsAudioDelay, presented: $showTrackSettings)
          if let avPlayer = session.cast?.routePlayer
            ?? (engine.layer?.player as? KSAVPlayer)?.player
          {
            MacRoutePicker(
              player: avPlayer, cast: session.cast, openRequest: session.pickerRequest,
              didOpen: session.didOpenPicker
            )
            .frame(width: 32, height: 26).help("AirPlay").accessibilityLabel("AirPlay")
          } else if session.cast?.isPreparing == true {
            ProgressView().controlSize(.small).help(L("player.airplay.preparing"))
          } else if engine.isFFmpegBackendActive {
            Button("AirPlay", systemImage: "airplayvideo", action: session.prepareAirPlay)
              .labelStyle(.iconOnly).help("AirPlay")
          }
          if let cast = session.cast, cast.isEngaged {
            Button(L("common.cancel"), systemImage: "xmark.circle", action: cast.stopCasting)
              .labelStyle(.iconOnly).help(L("common.cancel") + " AirPlay")
          }
          Button {
            windowAnchor.window?.toggleFullScreen(nil)
          } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
          }.help(ML("fullscreen"))
        }
      }.buttonStyle(.borderless).padding(12)
    }
  }

  private func playbackSettings(compact: Bool) -> some View {
    Form {
      if compact {
        ControlGroup(ML("volume")) {
          Button("−") { session.volume = max(0, session.volume - 0.1) }
          Button("+") { session.volume = min(1, session.volume + 0.1) }
        }
      }
      if engine.isPictureInPicturePossible || engine.isPiPActive {
        Button(L("settings.player.pip.title"), systemImage: engine.isPiPActive ? "pip.exit" : "pip.enter") {
          engine.togglePictureInPicture()
        }
      }
      Divider()
      Picker(L("player.aspect.title"), selection: $session.aspect) {
        ForEach(VideoAspectMode.allCases, id: \.self) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      if session.canChangeSpeed {
        Picker(
          L("player.speed.title"),
          selection: Binding(get: { session.speed }, set: session.setSpeed)
        ) {
          ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3], id: \.self) { rate in
            Text(rate.formatted(.number.locale(AppLocale.current)) + "×").tag(rate)
          }
        }
      }
      Picker(selection: Binding(
        get: { session.sleepPresetMinutes },
        set: { minutes in
          session.setSleepTimer(seconds: Double(minutes * 60), presetMinutes: minutes)
        }
      )) {
        Text(L("player.sleep.off")).tag(0)
        ForEach([5, 15, 30, 45, 60, 90], id: \.self) { minutes in
          Text(L("player.sleep.minutes", minutes)).tag(minutes)
        }
      } label: {
        if let deadline = session.sleepDeadline {
          Label(L("player.sleep.remaining", max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))),
                systemImage: "moon.zzz")
        } else {
          Label(L("player.sleep.title"), systemImage: "moon.zzz")
        }
      }.pickerStyle(.menu)
    }.padding(16).frame(width: 330)
  }

  private func handlePlayerKey(_ key: KeyPress) -> KeyPress.Result {
    guard session.expanded, !showPlaybackSettings, !showTrackSettings, !showQueue, !showSubtitleStyle, !showDiagnosticsSettings,
      key.modifiers.isDisjoint(with: [.command, .control, .option]),
      !(windowAnchor.window?.firstResponder is NSTextView) else { return .ignored }
    let action: () -> Void
    switch key.key {
    case .leftArrow, .rightArrow:
      guard session.canSeek, engine.playbackFailureMessage == nil else { return .ignored }
      let delta: Double = key.key == .leftArrow ? -15 : 15
      action = { session.seek(to: min(session.duration, max(0, session.position + delta))) }
    case .upArrow, .downArrow:
      let delta = (key.key == .upArrow ? 1.0 : -1.0) / 16
      action = { session.volume = min(1, max(0, session.volume + delta)) }
    case .space: action = session.toggle
    case .escape:
      action = {
        if let window = windowAnchor.window, window.styleMask.contains(.fullScreen) {
          window.toggleFullScreen(nil)
        } else {
          minimizePlayer()
        }
      }
    default:
      switch key.characters.lowercased() {
      case "l":
        guard media.isLive, session.lastChannel != nil else { return .ignored }
        action = session.recallLastChannel
      case "m": action = session.toggleMute
      case "f": action = { windowAnchor.window?.toggleFullScreen(nil) }
      default: return .ignored
      }
    }
    // SwiftUI delivers the key during a view update. Start transport work after
    // that update so synchronous decoder notifications can publish safely.
    Task { @MainActor in
      if session.expanded && session.current?.historyID == media.historyID {
        revealControls()
        action()
      }
    }
    return .handled
  }

}

/// Captures the containing window for local keyboard/fullscreen actions, including
/// while AVPlayer or a detached cast surface owns the picture.
struct MacPlayerWindowAnchor: NSViewRepresentable {
  let view: NSView
  func makeNSView(context: Context) -> NSView { view }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MacPictureTransform: Equatable {
  var scale: CGFloat = 1
  var offset: CGSize = .zero

  func adjusted(factor: CGFloat = 1, anchor: UnitPoint = .center, drag: CGSize = .zero,
                picture: CGSize, viewport: CGSize, floor: CGFloat = 1) -> Self {
    let next = min(4, max(floor, scale * factor))
    if next == 1 { return Self() }
    let ratio = next / scale
    func axis(_ old: CGFloat, _ anchor: CGFloat, _ delta: CGFloat, _ length: CGFloat, _ window: CGFloat) -> CGFloat {
      let limit = max(0, (length * next - window) / 2)
      let proposed = old * ratio + (anchor - 0.5) * window * (1 - ratio) + delta
      return min(limit, max(-limit, proposed))
    }
    return Self(scale: next, offset: CGSize(
      width: axis(offset.width, anchor.x, drag.width, picture.width, viewport.width),
      height: axis(offset.height, anchor.y, drag.height, picture.height, viewport.height)))
  }
}

private struct MacPictureClicks: NSViewRepresentable {
  let hold: (Bool) -> Void
  let onDoubleClick: () -> Void
  func makeNSView(context: Context) -> Target { Target() }
  func updateNSView(_ view: Target, context: Context) { view.action = onDoubleClick; view.hold = hold }
  static func dismantleNSView(_ view: Target, coordinator: ()) { view.stop() }

  final class Target: NSView {
    var action: (() -> Void)?
    var hold: ((Bool) -> Void)?
    private var pendingHold: Task<Void, Never>?
    private var holdStarted = false

    @objc private func endHold() {
      pendingHold?.cancel()
      pendingHold = nil
      if holdStarted { holdStarted = false; hold?(false) }
    }

    private var monitor: Any?
    private var lastMouseDown: (time: TimeInterval, number: Int)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard let window else { return }
      NotificationCenter.default.addObserver(self, selector: #selector(endHold),
        name: NSWindow.didResignKeyNotification, object: window)
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
        if event.type != .leftMouseDown { self?.endHold(); return event }
        guard let self, event.window === window,
          !isHiddenOrHasHiddenAncestor else { return event }
        if lastMouseDown?.time == event.timestamp, lastMouseDown?.number == event.eventNumber { return event }
        lastMouseDown = (event.timestamp, event.eventNumber)
        let point = convert(event.locationInWindow, from: nil)
        endHold()
        if visibleRect.contains(point), event.clickCount == 1 {
          pendingHold = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, self.window != nil else { return }
            holdStarted = true
            hold?(true)
          }
        }
        if visibleRect.contains(point), event.clickCount == 2 {
          action?()
        }
        return event
      }
    }
    func stop() {
      NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
      endHold()
      lastMouseDown = nil
      if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
  }
}

private struct MacPicture: View {
  @ObservedObject var engine: KSPlayerEngine
  @Binding var aspect: VideoAspectMode
  let mediaID: String
  let togglePlayback: () -> Void
  let retry: (() -> Void)?
  let minimize: () -> Void
  let showControls: (() -> Void)?
  let toggleSpeed: (() -> Void)?
  let hold: (Bool) -> Void
  let doubleClick: () -> Void
  @State private var transform = MacPictureTransform()
  @GestureState private var pinch: MagnifyGesture.Value?
  @GestureState private var drag = CGSize.zero
  @Environment(\.displayScale) private var displayScale
  var body: some View {
    GeometryReader { box in
      let natural = CGSize(width: engine.videoDisplayWidth, height: engine.videoDisplayHeight)
      let size = Self.pictureSize(
        natural: natural, available: box.size, aspect: aspect, displayScale: displayScale)
      let fitted = Self.pictureSize(natural: natural, available: box.size, aspect: .fit, displayScale: displayScale)
      let cover = PlayerPinchAspectSnapPolicy.coverScale(fitted: fitted, container: box.size)
      let floor = PlayerPinchAspectSnapPolicy.minimumZoom(mode: aspect, committedZoom: transform.scale, coverScale: cover)
      let shown = transform.adjusted(factor: pinch?.magnification ?? 1, anchor: pinch?.startAnchor ?? .center,
                                     drag: drag, picture: size, viewport: box.size, floor: floor)
      ZStack {
        MacVideoSurface(engine: engine, revision: engine.surfaceRevision)
          .frame(width: engine.pipPanelSize?.width, height: engine.pipPanelSize?.height)
        KSSubtitleBitmapOverlay(
          image: engine.subtitleImage, imageOrigin: engine.subtitleImageOrigin, naturalSize: natural
        )
      }
      .frame(width: size.width, height: size.height)
      .scaleEffect(shown.scale)
      .position(x: box.size.width / 2 + shown.offset.width, y: box.size.height / 2 + shown.offset.height)
      .frame(width: box.size.width, height: box.size.height)
      .contentShape(Rectangle())
      .background(MacPictureClicks(hold: hold, onDoubleClick: doubleClick))
      .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value }
        .onEnded { value in
          let end = transform.adjusted(factor: value.magnification, anchor: value.startAnchor,
                                       picture: size, viewport: box.size, floor: floor)
          switch PlayerPinchAspectSnapPolicy.outcome(mode: aspect, committedZoom: transform.scale,
            endZoom: end.scale, coverScale: cover, cancelled: false) {
          case .freeZoom: transform = end
          case .snapToFit: transform = MacPictureTransform(); aspect = .fit
          case .snapToFill: transform = MacPictureTransform(); aspect = .fill
          case .returnToFill: transform = MacPictureTransform()
          }
        })
      .simultaneousGesture(DragGesture(minimumDistance: 3).updating($drag) { value, state, _ in
        if transform.scale > 1 { state = value.translation }
      }.onEnded { value in
        if transform.scale > 1 {
          transform = transform.adjusted(drag: value.translation, picture: size, viewport: box.size)
        }
      })
      .contextMenu {
        Button(ML("zoom_in")) { transform = transform.adjusted(factor: 2, picture: size, viewport: box.size) }
          .disabled(shown.scale >= 4)
        Button(ML("zoom_out")) { transform = transform.adjusted(factor: 0.5, picture: size, viewport: box.size) }
          .disabled(shown.scale <= 1)
        Button("100%") { transform = MacPictureTransform() }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(ML("video_zoom"))
      .accessibilityValue(Double(shown.scale).formatted(.percent))
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment: transform = transform.adjusted(factor: 2, picture: size, viewport: box.size)
        case .decrement: transform = transform.adjusted(factor: 0.5, picture: size, viewport: box.size)
        @unknown default: break
        }
      }
      .accessibilityActions {
        if let retry {
          Button(L("common.try_again"), action: retry)
        } else {
          Button(L(engine.isPaused ? "player.a11y.play" : "player.a11y.pause"), action: togglePlayback)
        }
        Button(L("player.a11y.minimize"), action: minimize)
        if let showControls { Button(L("player.a11y.show_controls"), action: showControls) }
        if let toggleSpeed { Button(L("player.a11y.toggle_2x"), action: toggleSpeed) }
      }
      .onChange(of: box.size) { _, viewport in
        transform = transform.adjusted(picture: size, viewport: viewport)
      }
    }.background(.black).clipped()
      .onChange(of: mediaID) { _, _ in transform = MacPictureTransform() }
      .onChange(of: aspect) { _, _ in transform = MacPictureTransform() }
  }
  static func pictureSize(
    natural: CGSize, available: CGSize, aspect: VideoAspectMode, displayScale: CGFloat
  ) -> CGSize {
    guard natural.width > 0, natural.height > 0 else { return available }
    let x = available.width / natural.width
    let y = available.height / natural.height
    let factor: CGFloat
    switch aspect {
    case .fit: factor = min(x, y)
    case .fill: factor = max(x, y)
    case .center: factor = min(x, y, 1 / max(1, displayScale))
    }
    return CGSize(width: natural.width * factor, height: natural.height * factor)
  }
}

private struct MacCastSurface: NSViewRepresentable {
  let video: AirPlayCastPlayer.View
  let aspect: VideoAspectMode
  func makeNSView(context: Context) -> NSView { video }
  func updateNSView(_ view: NSView, context: Context) {
    video.playerLayer.videoGravity = aspect == .fill ? .resizeAspectFill : .resizeAspect
  }
}

/// The picker always targets the player that owns the video, including remux HLS.
struct MacRoutePicker: NSViewRepresentable {
  let player: AVPlayer
  let cast: CastController?
  let openRequest: UUID?
  let didOpen: (UUID) -> Void
  final class Coordinator: NSObject, AVRoutePickerViewDelegate {
    weak var cast: CastController?
    var handledRequest: UUID?
    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
      cast?.pickerWillOpen()
    }
    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
      cast?.pickerDidClose()
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.player = player
    picker.delegate = context.coordinator
    return picker
  }
  func updateNSView(_ picker: AVRoutePickerView, context: Context) {
    context.coordinator.cast = cast
    if picker.player !== player { picker.player = player }
    if let openRequest, context.coordinator.handledRequest != openRequest {
      context.coordinator.handledRequest = openRequest
      DispatchQueue.main.async { [weak picker] in
        guard let picker, picker.window != nil else { return }
        func button(in view: NSView) -> NSButton? {
          (view as? NSButton) ?? view.subviews.lazy.compactMap { button(in: $0) }.first
        }
        if let routeButton = button(in: picker) {
          didOpen(openRequest)
          routeButton.performClick(nil)
        }
      }
    }
  }
}
