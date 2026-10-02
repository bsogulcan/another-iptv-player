import AVFoundation
import Foundation
import UIKit

/// Thin AVPlayer wrapper that plays cast content (remuxed local HLS, or natively
/// playable source URLs) with external playback enabled. KSAVPlayer is deliberately
/// NOT used here: its synchronous track-playability check at readyToPlay races on
/// HLS and failed instantly with "VideoTracks are not even playable".
///
/// The player instance is long-lived: one AVPlayer per cast engagement, with
/// `load(url:)` swapping AVPlayerItems. Tearing down an external-playback AVPlayer
/// flaps the AirPlay route, so content changes must never recreate the player.
final class AirPlayCastPlayer: NSObject {
  final class View: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }

  let view = View()
  private let player = AVPlayer()
  private var item: AVPlayerItem?
  private var timeObserver: Any?
  private var playerObservations: [NSKeyValueObservation] = []
  private var itemObservation: NSKeyValueObservation?
  private var reportedError = false
  /// When the current item is a remux stream carrying an HLS WebVTT subtitle rendition,
  /// enable it (so it shows on the AirPlay target) once the item is ready. Cleared after
  /// the first selection so a later status change doesn't re-trigger it.
  private var selectLegibleOnReady = false
  /// The current item is a source the receiver plays by itself (not our remux): apply
  /// the saved audio / subtitle language once it is ready, as the engine does for its
  /// own AVPlayer. Cleared after the first pass.
  private var applyTrackPreferencesOnReady = false
  /// Error-log entries and stalls written to the log for the current item. Both are
  /// record-only and can repeat for as long as an item struggles, so each kind stops
  /// after `maximumRecordedEventsPerItem` lines: the log buffer is small and shared.
  private var recordedErrorLogEntries = 0
  private var recordedStalls = 0
  static let maximumRecordedEventsPerItem = 12

  var onTime: ((TimeInterval) -> Void)?
  var onStateChange: (() -> Void)?
  var onError: ((Error) -> Void)?
  /// Item reached its end (played up to ENDLIST) — drives "completed" state.
  var onEnded: (() -> Void)?

  var currentTime: TimeInterval {
    let t = player.currentTime().seconds
    return t.isFinite ? max(t, 0) : 0
  }

  /// Duration of the range written so far on a growing event playlist.
  var duration: TimeInterval {
    let d = item?.duration.seconds ?? 0
    return d.isFinite ? max(d, 0) : 0
  }

  /// Seekable window of a live(-looking) stream. `duration` can be indefinite on
  /// a growing playlist; in-window seek decisions use this instead.
  var seekableRange: (start: TimeInterval, end: TimeInterval) {
    var minStart = TimeInterval.greatestFiniteMagnitude
    var maxEnd: TimeInterval = 0
    for value in item?.seekableTimeRanges ?? [] {
      let range = value.timeRangeValue
      let start = range.start.seconds
      let end = range.end.seconds
      if start.isFinite { minStart = min(minStart, start) }
      if end.isFinite { maxEnd = max(maxEnd, end) }
    }
    return (minStart == .greatestFiniteMagnitude ? 0 : minStart, maxEnd)
  }

  var isPaused: Bool { player.rate == 0 }
  var isBuffering: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
  var isReadyToPlay: Bool { item?.status == .readyToPlay }
  var isExternalPlaybackActive: Bool { player.isExternalPlaybackActive }

  override init() {
    super.init()
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect

    playerObservations.append(player.observe(\.timeControlStatus) { [weak self] _, _ in
      DispatchQueue.main.async { self?.onStateChange?() }
    })
    playerObservations.append(player.observe(\.isExternalPlaybackActive) { [weak self] _, _ in
      DispatchQueue.main.async { self?.onStateChange?() }
    })
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 4), queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.onTime?(self.currentTime)
    }
  }

  /// Swaps the current item for a new URL. The AVPlayer (and with it the active
  /// AirPlay route) stays alive across loads.
  /// `userAgent` is for natively cast source URLs: panels that gate on User-Agent
  /// reject AVFoundation's default one, which failed the item and ended the cast
  /// although the same channel plays on the phone. Local remux URLs pass nil (the
  /// writer sends the header to the source itself).
  /// `appliesTrackPreferences` is for natively cast source URLs as well: the audio
  /// and subtitle language chosen on the engine is selected among the item's own
  /// renditions (a remux playlist carries one audio track and at most our rendition).
  func load(
    url: URL,
    startAt: TimeInterval?,
    autoPlay: Bool,
    preferredLegible: Bool = false,
    userAgent: String? = nil,
    appliesTrackPreferences: Bool = false
  ) {
    stopObservingCurrentItem()
    reportedError = false
    recordedErrorLogEntries = 0
    recordedStalls = 0
    selectLegibleOnReady = preferredLegible
    applyTrackPreferencesOnReady = appliesTrackPreferences
    var assetOptions: [String: Any] = [:]
    if let userAgent, !userAgent.isEmpty {
      // Public option (iOS 16+) that sets the User-Agent header field of the
      // asset's HTTP requests. Whether an AirPlay receiver repeats it on its own
      // fetches cannot be read from code; phone-side requests carry it.
      assetOptions[AVURLAssetHTTPUserAgentKey] = userAgent
    }
    let asset = AVURLAsset(url: url, options: assetOptions.isEmpty ? nil : assetOptions)
    let newItem = AVPlayerItem(asset: asset)
    item = newItem
    itemObservation = newItem.observe(\.status) { [weak self] observedItem, _ in
      DispatchQueue.main.async {
        guard let self, self.item === observedItem else { return }
        if observedItem.status == .failed, !self.reportedError {
          self.reportedError = true
          self.logErrorLogTail(of: observedItem, context: "item failed")
          self.onError?(
            observedItem.error
              ?? NSError(
                domain: "AirPlayCastPlayer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "cast item failed"]
              ))
        } else {
          if observedItem.status == .readyToPlay, self.selectLegibleOnReady {
            self.selectLegibleOnReady = false
            self.enableFirstLegibleOption(on: observedItem)
          }
          if observedItem.status == .readyToPlay, self.applyTrackPreferencesOnReady {
            self.applyTrackPreferencesOnReady = false
            self.applyTrackPreferences(to: observedItem)
          }
          self.onStateChange?()
        }
      }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(itemDidPlayToEnd(_:)),
      name: .AVPlayerItemDidPlayToEndTime, object: newItem
    )
    // An item that was playing and then cannot go on (the receiver lost the
    // phone, segments stopped arriving) can report this without its status ever
    // turning `.failed`; without it the cast would sit on a spinner.
    NotificationCenter.default.addObserver(
      self, selector: #selector(itemFailedToPlayToEnd(_:)),
      name: .AVPlayerItemFailedToPlayToEndTime, object: newItem
    )
    // Record only. A new error-log entry or a stall is routine on a cast that then
    // carries on, so neither may reach `onError` (its owner ends the cast): they are
    // written to the log, which is all that is left to read after a cast that hung.
    NotificationCenter.default.addObserver(
      self, selector: #selector(itemLoggedError(_:)),
      name: .AVPlayerItemNewErrorLogEntry, object: newItem
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(itemPlaybackStalled(_:)),
      name: .AVPlayerItemPlaybackStalled, object: newItem
    )
    player.replaceCurrentItem(with: newItem)
    if let startAt, startAt > 0.5 {
      player.seek(
        to: CMTime(seconds: startAt, preferredTimescale: 600),
        toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity
      )
    }
    if autoPlay {
      player.play()
    } else {
      // Explicit: replacing the item does not reset the rate, so a player that
      // was playing the previous item would start the new one by itself.
      player.pause()
    }
  }

  /// Turn on the (single) WebVTT subtitle rendition we added to the remux master, so it
  /// renders on the AirPlay target. Only called when we authored that rendition, so the
  /// first legible option is ours; a no-op if the group is absent (e.g. fMP4 skipped it).
  private func enableFirstLegibleOption(on item: AVPlayerItem) {
    let asset = item.asset
    Task { @MainActor in
      guard let group = try? await asset.loadMediaSelectionGroup(for: .legible),
            let option = group.options.first,
            self.item === item
      else { return }
      item.select(option, in: group)
    }
  }

  /// Selects the audio and subtitle rendition that match the saved track
  /// preferences, with the same matching the engine uses for its own tracks
  /// (`PlaybackTrackPreferences.pickAudio` / `pickSubtitle`). The rows are flagged
  /// as carrying synthetic titles, so only a language can match: a rendition's
  /// display name changes with the system language. No preference, or no rendition
  /// in that language, leaves AVPlayer's own choice alone.
  private func applyTrackPreferences(to item: AVPlayerItem) {
    let asset = item.asset
    Task { @MainActor in
      let preferences = PlaybackTrackPreferences.load()
      if let group = try? await asset.loadMediaSelectionGroup(for: .audible),
         self.item === item {
        let options = AVMediaSelectionGroup.playableMediaSelectionOptions(from: group.options)
        if let pick = PlaybackTrackPreferences.pickAudio(
          from: Self.trackRows(for: options), prefs: preferences
        ), options.indices.contains(pick) {
          item.select(options[pick], in: group)
        }
      }
      if let group = try? await asset.loadMediaSelectionGroup(for: .legible),
         self.item === item {
        // Forced-only renditions are not subtitles a viewer picks.
        let options = AVMediaSelectionGroup.mediaSelectionOptions(
          from: AVMediaSelectionGroup.playableMediaSelectionOptions(from: group.options),
          withoutMediaCharacteristics: [.containsOnlyForcedSubtitles]
        )
        let pick = PlaybackTrackPreferences.pickSubtitle(
          from: Self.trackRows(for: options), prefs: preferences
        )
        if let pick, options.indices.contains(pick) {
          item.select(options[pick], in: group)
        } else if pick == -1, group.allowsEmptySelection {
          // "Subtitles off" was chosen on the engine.
          item.select(nil, in: group)
        }
      }
    }
  }

  /// Rows for the preference matching: the id is the option's index.
  private static func trackRows(for options: [AVMediaSelectionOption]) -> [TrackMenuOption] {
    options.enumerated().map { index, option in
      TrackMenuOption(
        id: index,
        title: option.displayName,
        langCode: option.extendedLanguageTag ?? option.locale?.identifier,
        isSyntheticTitle: true
      )
    }
  }

  /// Stops listening to the current item (it is about to be replaced or dropped).
  private func stopObservingCurrentItem() {
    if let item {
      NotificationCenter.default.removeObserver(
        self, name: .AVPlayerItemDidPlayToEndTime, object: item
      )
      NotificationCenter.default.removeObserver(
        self, name: .AVPlayerItemFailedToPlayToEndTime, object: item
      )
      NotificationCenter.default.removeObserver(
        self, name: .AVPlayerItemNewErrorLogEntry, object: item
      )
      NotificationCenter.default.removeObserver(
        self, name: .AVPlayerItemPlaybackStalled, object: item
      )
    }
    itemObservation = nil
  }

  /// Drops the current item but keeps the player, and with it the AirPlay route.
  /// For an item that must stop reading its source before something else opens the
  /// same stream (a native item the remux fallback replaces): removing the item is
  /// what closes its connections; a pause would leave them open.
  func unload() {
    stopObservingCurrentItem()
    selectLegibleOnReady = false
    applyTrackPreferencesOnReady = false
    // A failure of the item being dropped must not be reported after the fact.
    reportedError = true
    item = nil
    player.replaceCurrentItem(with: nil)
  }

  @objc private func itemDidPlayToEnd(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let item = self.item,
            (notification.object as? AVPlayerItem) === item
      else { return }
      self.onEnded?()
    }
  }

  @objc private func itemFailedToPlayToEnd(_ notification: Notification) {
    let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
    DispatchQueue.main.async { [weak self] in
      // Same one-shot latch as the status observer: whichever of the two reports
      // the failure first, the owner hears about it once.
      guard let self, let item = self.item,
            (notification.object as? AVPlayerItem) === item,
            !self.reportedError
      else { return }
      self.reportedError = true
      self.logErrorLogTail(of: item, context: "item failed to play to its end")
      self.onError?(
        error
          ?? NSError(
            domain: "AirPlayCastPlayer", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "cast item failed to play to its end"]
          ))
    }
  }

  // MARK: - Record-only diagnostics

  /// A new entry in the current item's error log. Logged, never reported.
  @objc private func itemLoggedError(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let item = self.item,
            (notification.object as? AVPlayerItem) === item,
            self.recordedErrorLogEntries < Self.maximumRecordedEventsPerItem
      else { return }
      self.recordedErrorLogEntries += 1
      guard let entry = Self.errorLogTail(of: item, count: 1) else { return }
      let last = self.recordedErrorLogEntries == Self.maximumRecordedEventsPerItem
      Log.info(
        "AirPlayCast",
        "item error log: \(entry)" + (last ? " (further entries of this item are not logged)" : "")
      )
    }
  }

  /// The current item ran out of media to play. Logged, never reported: a stall
  /// that does not recover surfaces through the item's failure or the watchdogs.
  @objc private func itemPlaybackStalled(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let item = self.item,
            (notification.object as? AVPlayerItem) === item,
            self.recordedStalls < Self.maximumRecordedEventsPerItem
      else { return }
      self.recordedStalls += 1
      let last = self.recordedStalls == Self.maximumRecordedEventsPerItem
      Log.info(
        "AirPlayCast",
        "playback stalled at \(Int(self.currentTime))s (external playback "
          + (self.isExternalPlaybackActive ? "on" : "off") + ")"
          + (last ? " (further stalls of this item are not logged)" : "")
      )
    }
  }

  /// Writes the newest error-log entries of `item` to the log, just before its
  /// failure is reported: the reported error names the symptom, the entries usually
  /// name the request that caused it.
  private func logErrorLogTail(of item: AVPlayerItem, context: String) {
    guard let tail = Self.errorLogTail(of: item, count: 2) else {
      Log.info("AirPlayCast", "\(context); its error log is empty")
      return
    }
    Log.info("AirPlayCast", "\(context); last error log entries: \(tail)")
  }

  /// The newest `count` entries of the item's error log, oldest first, or nil when
  /// there are none.
  private static func errorLogTail(of item: AVPlayerItem, count: Int) -> String? {
    guard let events = item.errorLog()?.events, !events.isEmpty else { return nil }
    return events.suffix(count).map {
      describeErrorLogEvent(
        statusCode: $0.errorStatusCode, domain: $0.errorDomain, comment: $0.errorComment
      )
    }.joined(separator: "; ")
  }

  /// One error-log entry as text: domain, status code and the comment. The entry's
  /// URI and server address are left out on purpose: on a natively cast source they
  /// are the panel's, and this text ends up in bug reports. Pure function.
  static func describeErrorLogEvent(statusCode: Int, domain: String, comment: String?) -> String {
    let comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return comment.isEmpty ? "\(domain) \(statusCode)" : "\(domain) \(statusCode) (\(comment))"
  }

  func play() { player.play() }
  func pause() { player.pause() }

  func seek(to seconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
    player.seek(
      to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600),
      toleranceBefore: CMTime(seconds: 1, preferredTimescale: 600),
      toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
    ) { finished in
      completion?(finished)
    }
  }

  /// Rate changes only apply while playing; a rate set while paused must not
  /// resume playback (long-press 2x while paused used to un-pause the cast).
  func setRate(_ rate: Float) {
    if rate <= 0 {
      player.pause()
    } else if player.rate > 0 {
      player.rate = rate
    }
  }

  func setVolume(_ value: Float) {
    player.volume = min(max(value, 0), 1)
  }

  func dispose() {
    NotificationCenter.default.removeObserver(self)
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    playerObservations.removeAll()
    itemObservation = nil
    onTime = nil
    onStateChange = nil
    onError = nil
    onEnded = nil
    player.pause()
    player.replaceCurrentItem(with: nil)
    item = nil
    view.playerLayer.player = nil
  }
}
