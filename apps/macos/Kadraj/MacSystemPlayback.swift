import AppKit
import Combine
import ImageIO
import MediaPlayer

/// Owns the system media session for the window's current channel, film or episode.
@MainActor final class MacSystemPlayback {
  weak var session: DesktopPlayback?
  private let center = MPNowPlayingInfoCenter.default()
  private let commands = MPRemoteCommandCenter.shared()
  private var registrations: [(MPRemoteCommand, Any)] = []
  private var observation: AnyCancellable?
  private var artworkTask: Task<Void, Never>?
  private var artwork: MPMediaItemArtwork?
  private var layerID: ObjectIdentifier?
  private var lastFields: VideoPlayerControllerLogic.NowPlayingFields?
  private var lastElapsed = 0.0
  private var lastPush = 0.0
  private var lastRepair = 0.0
  private var seekTarget: Double?

  func noteSeek(to seconds: Double) { seekTarget = seconds }

  init(session: DesktopPlayback) { self.session = session }

  func start(_ media: MediaSelection) {
    guard let session else { return }
    registerCommands()
    observation = Publishers.Merge3(
      session.objectWillChange, session.engine.objectWillChange,
      EPGStore.shared.objectWillChange
    )
    .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.publish() }
    if let raw = media.artwork, let url = URL(string: raw),
      ["http", "https"].contains(url.scheme?.lowercased())
    {
      artworkTask = Task { [weak self] in
        guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
          let decoded = await Task.detached(operation: { Self.thumbnail(data) }).value,
          let self, !Task.isCancelled, session.current == media
        else { return }
        let size = NSSize(width: decoded.width, height: decoded.height)
        artwork = MPMediaItemArtwork(boundsSize: size) { _ in NSImage(cgImage: decoded, size: size)
        }
        publish(force: true)
      }
    }
    publish(force: true)
  }

  nonisolated private static func thumbnail(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(
        VideoPlayerControllerLogic.nowPlayingArtworkMaxDimension),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  func stop() {
    observation?.cancel()
    artworkTask?.cancel()
    artwork = nil
    layerID = nil
    lastFields = nil
    seekTarget = nil
    for (command, _) in registrations { command.isEnabled = false }
    removeCommands()
    center.playbackState = .stopped
    center.nowPlayingInfo = nil
  }

  private func publish(force: Bool = false) {
    guard let session, let media = session.current else { return }
    let currentLayer = session.engine.layer.map(ObjectIdentifier.init)
    var reinstall = currentLayer != layerID
    layerID = currentLayer
    let clock = ProcessInfo.processInfo.systemUptime
    let programme =
      media.isLive ? EPGStore.shared.nowNext(playlistId: media.playlistId, channelKey: media.epgKey)?.now?.title : nil
    let playing = !session.isPaused && !session.isBuffering
    let rate =
      session.cast?.isPresenting == true
      ? (session.cast?.routePlayer?.rate ?? 0) : Float(session.engine.playbackRate)
    let fields = VideoPlayerControllerLogic.NowPlayingFields(
      title: programme ?? media.title,
      artist: programme == nil ? (media.secondaryTitle ?? "Another IPTV Player") : media.title,
      durationSeconds: media.isLive || !session.duration.isFinite ? 0 : max(0, session.duration),
      rate: playing ? Double(rate) : 0, isLive: media.isLive,
      artworkID: artwork.map(ObjectIdentifier.init))
    let elapsed = session.position.isFinite ? max(0, session.position) : 0
    if clock - lastRepair >= 2 {
      lastRepair = clock
      let info = center.nowPlayingInfo
      if lastFields != nil
        && !VideoPlayerControllerLogic.nowPlayingIsIntact(
          title: info?[MPMediaItemPropertyTitle] as? String,
          artist: info?[MPMediaItemPropertyArtist] as? String,
          durationSeconds: info?[MPMediaItemPropertyPlaybackDuration] as? Double,
          hasArtwork: info?[MPMediaItemPropertyArtwork] != nil, expected: fields)
      {
        reinstall = true
      }
    }
    let reachedSeekTarget =
      !session.engine.isSeekInFlight && (seekTarget.map { abs($0 - elapsed) < 0.2 } ?? false)
    if reachedSeekTarget { seekTarget = nil }
    if reinstall { registerCommands() }
    configureCommands(session, media: media)
    guard
      VideoPlayerControllerLogic.shouldPushNowPlaying(
        force: force || reinstall || reachedSeekTarget, fields: fields,
        pushed: lastFields, elapsed: elapsed, pushedElapsed: lastElapsed,
        secondsSincePush: clock - lastPush)
    else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: fields.title, MPMediaItemPropertyArtist: fields.artist,
      MPMediaItemPropertyPlaybackDuration: fields.durationSeconds,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
      MPNowPlayingInfoPropertyPlaybackRate: fields.rate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
      MPNowPlayingInfoPropertyIsLiveStream: media.isLive,
    ]
    if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
    center.nowPlayingInfo = info
    center.playbackState = playing ? .playing : .paused
    lastFields = fields
    lastElapsed = elapsed
    lastPush = clock
  }

  private func supportsTimeSkip(_ session: DesktopPlayback, media: MediaSelection) -> Bool {
    guard !media.isLive else { return false }
    guard media.type == "series", let index = session.queueIndex, let queue = session.queue else { return true }
    return !queue.items.indices.contains(index - 1) && !queue.items.indices.contains(index + 1)
  }

  private func configureCommands(_ session: DesktopPlayback, media: MediaSelection) {
    let index = session.queueIndex ?? -1
    let navigates = media.isLive || media.type == "series"
    let previous = navigates && index > 0
    let next = navigates && index >= 0 && index + 1 < (session.queue?.items.count ?? 0)
    let skip = supportsTimeSkip(session, media: media)
    for (command, enabled) in [
      (commands.previousTrackCommand, previous), (commands.nextTrackCommand, next),
      (commands.skipBackwardCommand, skip), (commands.skipForwardCommand, skip),
      (commands.changePlaybackPositionCommand, session.canSeek),
      (commands.changePlaybackRateCommand, session.canChangeSpeed),
    ] {
      if command.isEnabled != enabled { command.isEnabled = enabled }
    }
  }

  enum Action {
    case play, pause, toggle, stop
    case seek(Double)
    case skip(Double)
    case step(Int)
    case speed(Double)
  }

  func perform(_ action: Action) -> MPRemoteCommandHandlerStatus {
    guard let session, let media = session.current else { return .noSuchContent }
    switch action {
    case .play: if session.isPaused { session.toggle() }
    case .pause: if !session.isPaused { session.toggle() }
    case .toggle: session.toggle()
    case .stop: session.close()
    case .seek(let time):
      guard session.canSeek, time.isFinite else { return .commandFailed }
      session.seek(to: min(session.duration, max(0, time)))
    case .skip(let delta):
      guard supportsTimeSkip(session, media: media) else { return .commandFailed }
      return perform(.seek(session.position + delta))
    case .step(let delta):
      guard media.isLive || media.type == "series", let index = session.queueIndex,
        session.queue?.items.indices.contains(index + delta) == true
      else { return .noSuchContent }
      session.step(delta)
    case .speed(let rate):
      guard session.canChangeSpeed, rate.isFinite, rate > 0 else { return .commandFailed }
      session.setSpeed(rate)
    }
    return .success
  }

  private func registerCommands() {
    removeCommands()
    commands.skipForwardCommand.preferredIntervals = [15]
    commands.skipBackwardCommand.preferredIntervals = [15]
    commands.changePlaybackRateCommand.supportedPlaybackRates = [
      0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3,
    ]
    func add(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> Action?) {
      command.isEnabled = true
      let token = command.addTarget { [weak self] event in
        guard let request = action(event) else { return .commandFailed }
        if Thread.isMainThread {
          return MainActor.assumeIsolated { self?.perform(request) ?? .noSuchContent }
        }
        return DispatchQueue.main.sync { self?.perform(request) ?? .noSuchContent }
      }
      registrations.append((command, token))
    }
    add(commands.playCommand) { _ in .play }
    add(commands.pauseCommand) { _ in .pause }
    add(commands.togglePlayPauseCommand) { _ in .toggle }
    add(commands.stopCommand) { _ in .stop }
    add(commands.nextTrackCommand) { _ in .step(1) }
    add(commands.previousTrackCommand) { _ in .step(-1) }
    add(commands.skipForwardCommand) { event in
      .skip((event as? MPSkipIntervalCommandEvent)?.interval ?? 15)
    }
    add(commands.skipBackwardCommand) { event in
      .skip(-((event as? MPSkipIntervalCommandEvent)?.interval ?? 15))
    }
    add(commands.changePlaybackPositionCommand) {
      ($0 as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
    }
    add(commands.changePlaybackRateCommand) {
      ($0 as? MPChangePlaybackRateCommandEvent).map { .speed(Double($0.playbackRate)) }
    }
  }

  private func removeCommands() {
    for (command, target) in registrations { command.removeTarget(target) }
    registrations.removeAll()
  }
}
