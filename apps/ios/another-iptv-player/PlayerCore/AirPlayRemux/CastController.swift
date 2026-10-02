import AVFoundation
import Combine
import Foundation
import UIKit

/// Source-time bookkeeping for a remux cast. The local HLS timeline starts at 0,
/// which corresponds to `offset` seconds inside the source content.
struct RemuxTimeline: Equatable {
  var offset: TimeInterval
  /// Duration of the source content when known (0 = unknown).
  var knownDuration: TimeInterval

  func sourceTime(fromLocal local: TimeInterval) -> TimeInterval {
    offset + local
  }

  func localTarget(forSource target: TimeInterval) -> TimeInterval {
    max(target - offset, 0)
  }

  /// Total duration to present: the real source duration when known, otherwise
  /// the growing written range (offset + local player duration).
  func totalDuration(localPlayerDuration: TimeInterval) -> TimeInterval {
    knownDuration > 0 ? knownDuration : offset + localPlayerDuration
  }
}

/// Why a cast engagement ended, or could not start. Carried through the single
/// `endCasting` exit (and the two early-failure paths) so the owner can tell the
/// user what happened instead of silently reloading the stream on the phone.
enum CastEndReason: Equatable {
  /// Explicit stop or cancel by the user.
  case userStopped
  /// The user moved on to other content before any AirPlay route existed.
  case contentChanged
  /// The AirPlay route went away and stayed away (receiver switched off, another
  /// output picked in the system route picker).
  case routeDropped
  /// The picker grace window ran out without a device being chosen.
  case noDeviceSelected
  /// The phone has no LAN IPv4 address the receiver could fetch from.
  case noWiFi
  /// The local HTTP server could not be started or reached.
  case localServerUnavailable
  /// The source refused or failed the remux connection.
  case sourceOpenFailed
  /// The source did not deliver a playable start in time.
  case sourceTooSlow
  /// No stream the receiver can play (codec / container).
  case incompatibleStreams
  /// The source failed after the cast was already running.
  case sourceLost
  /// The cast player item failed (the receiver could not play it).
  case receiverFailed
  /// The receiver took the route but never fetched anything from this phone
  /// (guest or client-isolated Wi-Fi, another subnet, a VPN blocking local traffic).
  case receiverUnreachable
  /// An AirPlay route is selected, but the receiver never took the picture: an
  /// AirPlay speaker, or a route that carries no video. The cast played on the
  /// phone with its sound on the route, which is not a cast.
  case routeHasNoVideo
  /// The device ran out of space for the local segments.
  case storageFull

  /// Endings the user caused or can see for themselves get no message: a notice
  /// for "you pressed stop" or "you switched the TV off" is noise.
  var isSilent: Bool {
    switch self {
    case .userStopped, .contentChanged, .routeDropped:
      return true
    case .noDeviceSelected, .noWiFi, .localServerUnavailable, .sourceOpenFailed,
         .sourceTooSlow, .incompatibleStreams, .sourceLost, .receiverFailed,
         .receiverUnreachable, .routeHasNoVideo, .storageFull:
      return false
    }
  }

  /// Localization key of the one-line notice; nil for silent reasons.
  var messageKey: String? {
    switch self {
    case .userStopped, .contentChanged, .routeDropped:
      return nil
    case .noDeviceSelected: return "player.airplay.notice.no_device"
    case .noWiFi: return "player.airplay.notice.no_wifi"
    case .localServerUnavailable: return "player.airplay.notice.no_local_server"
    case .sourceOpenFailed: return "player.airplay.notice.source_open_failed"
    case .sourceTooSlow: return "player.airplay.notice.source_too_slow"
    case .incompatibleStreams: return "player.airplay.notice.incompatible"
    case .sourceLost: return "player.airplay.notice.source_lost"
    case .receiverFailed: return "player.airplay.notice.receiver_failed"
    case .receiverUnreachable: return "player.airplay.notice.receiver_unreachable"
    case .routeHasNoVideo: return "player.airplay.notice.no_video_on_route"
    case .storageFull: return "player.airplay.notice.storage_full"
    }
  }
}

/// One published cast notice. `id` changes with every notice, so the same reason
/// twice in a row is still a change the UI can react to.
struct CastNotice: Equatable {
  let id: Int
  let reason: CastEndReason
  /// The cast ended by a failure while its AirPlay route stayed selected, and
  /// playback went back to the FFmpeg engine: the picture is on the phone again,
  /// but the engine's sound follows the route to the receiver. The owner says so
  /// next to the reason, so the hand-back is not a silent one.
  var soundStaysOnRoute = false
}

/// App-level AirPlay cast orchestrator. Owns the whole cast lifecycle — remux
/// session, cast player, route observation — as one explicit state machine.
/// The playback engine knows nothing about casting: it is stopped when a cast
/// engagement starts and reloaded (via `resumeDirectPlayback`) when it ends.
///
/// Invariants (each one was a field-fragility root cause before this existed):
/// - Single connection: while an engagement exists only the remux writer (or the
///   cast player, for natively playable URLs) touches the source URL; content
///   changes never warm up the phone-side player first.
/// - One AVPlayer per engagement: content changes swap the player item, never the
///   player, so the AirPlay route is not torn down and re-acquired on every zap.
/// - Single exit path: every failure/disconnect funnels through `endCasting`,
///   which always resumes direct playback — there is no state in which neither
///   the engine nor the cast player exists.
///   (One bounded exception: when a remux writer still holds the source at the
///   exit, the resume waits for it to close, for at most `resumeDrainCapSeconds`,
///   as one cancellable step that presents "loading"; see `beginResumeWait`.)
/// - No ambient triggers: casting starts only from the AirPlay button or an
///   explicit content-change continuation; the route observer can only end an
///   existing engagement (confirmed drop) or cancel the picker grace window.
final class CastController: ObservableObject {
  // MARK: - Types

  struct Content {
    var url: URL
    var isLive: Bool
    var userAgent: String?
    /// Source-time second playback should (re)start from.
    var startAt: TimeInterval
    /// Source duration when already known from the direct player (0 = unknown).
    var knownDuration: TimeInterval
    /// AVPlayer can play the URL natively — cast it directly, no remux session.
    var nativelyPlayable: Bool
    /// Playback was paused when the engagement began; start the cast paused too.
    var startPaused: Bool = false
    /// Selected external subtitle (SRT) to expose on the AirPlay target as an HLS WebVTT
    /// rendition. Only used on the remux path (TS/VOD); nil = cast without subtitles.
    var subtitleFileURL: URL? = nil
    var subtitleName: String? = nil
    var subtitleLanguage: String? = nil
  }

  private struct Pending {
    /// nil while waiting for a delayed retry (no session in flight).
    var session: AirPlayRemuxSession?
    var content: Content
    /// One delayed retry is allowed after a transient start failure (panel
    /// connection limits: dying connections need a few seconds to clear).
    var retryUsed: Bool
    /// Button-flow completion (opens the route picker on success). Carried in the
    /// state so every exit path — including a retry or endCasting — resolves it;
    /// an unresolved completion leaves the UI spinner stuck forever.
    var completion: ((Bool) -> Void)?
    /// The stopped session `session` waits on before it opens the source. Kept so
    /// a session that supersedes this one knows which of the two can still hold
    /// the connection (see `drainChoice`).
    var draining: AirPlayRemuxSession? = nil
    /// Experimental native live cast: the provider's HLS twin of `content.url`,
    /// loaded in the cast player once the stopped engine has had its second to let
    /// go of the source. nil for every remux start.
    var nativeTwinURL: URL? = nil
  }

  private struct Active {
    /// nil for natively playable content (cast player plays the URL directly).
    let session: AirPlayRemuxSession?
    var content: Content
    var timeline: RemuxTimeline
    /// AVPlayer can join a growing event playlist at its live edge; corrected once.
    var didCorrectLiveEdgeJoin = false
    /// Set while the cast player plays the provider's HLS twin instead of
    /// `content.url` (experimental native live cast). `content` keeps the original
    /// URL: the remux fallback and the resume on the phone both use that one.
    var nativeTwinURL: URL? = nil
  }

  /// A resume of direct playback that waits for the stopped remux writers to close
  /// their source connection (see `tearDownEngagement`).
  private struct PendingResume {
    var content: Content
    var at: TimeInterval
    /// Stopped sessions whose source connection was still open at the exit.
    let draining: [AirPlayRemuxSession]
    let startedAt: Date
  }

  private enum State {
    case idle
    /// Session starting; direct playback is already stopped; spinner presented.
    case preparing(Pending)
    case casting(Active)
    /// In-content seek refresh: `current`'s writer is already stopped (one source
    /// connection at a time); its item keeps playing the segments it wrote until
    /// `next` is ready.
    case refreshing(current: Active, next: Pending)

    /// For the log. The state itself is never interpolated into a message: its
    /// payload holds the content, and with it the stream URLs.
    var logName: String {
      switch self {
      case .idle: return "idle"
      case .preparing: return "preparing"
      case .casting: return "casting"
      case .refreshing: return "refreshing"
      }
    }
  }

  // MARK: - Published presentation

  /// True whenever an engagement exists — the owner presents cast state instead
  /// of engine state and routes transport calls here. It stays true for the few
  /// seconds after an engagement in which the resume of direct playback waits for
  /// the remux writer's connection to close (`isEngaged` is false then): the
  /// presentation is "loading" at the resume position, not the stopped engine's
  /// stale state.
  @Published private(set) var isPresenting = false
  @Published private(set) var position: TimeInterval = 0
  @Published private(set) var duration: TimeInterval = 0
  @Published private(set) var isPaused = false
  @Published private(set) var isBuffering = false
  @Published private(set) var isCompleted = false
  @Published private(set) var isSeekable = false
  @Published private(set) var isPlaybackEstablished = false
  @Published private(set) var isExternalPlaybackActive = false
  /// Bumped when `castVideoView` may point to a new view.
  @Published private(set) var surfaceRevision = 0
  /// True exactly while the state is `.preparing` (a session is being built, or its
  /// delayed retry is pending). Derived from the state machine in `transition`, so
  /// no dropped callback can leave the owner's "preparing" UI stuck.
  @Published private(set) var isPreparing = false
  /// True only while preparing a cast the user started from the AirPlay button
  /// (its completion is still pending). False for zaps, rebuilds and seek
  /// refreshes, which pass through `.preparing` as well: the owner offers Cancel
  /// on an active route only for the first kind. Published, because a content
  /// change takes the completion out of the state without any other published
  /// value changing, and the owner mirrors this on `objectWillChange`.
  @Published private(set) var isPreparingFromButton = false
  /// Why the last engagement ended or could not start; nil until something worth
  /// telling the user happened, and cleared when a new engagement begins. Silent
  /// reasons (see `CastEndReason.isSilent`) are never published.
  @Published private(set) var lastNotice: CastNotice?

  // MARK: - Owner hooks

  /// Stop the direct-playback engine (releases its source connection).
  var stopDirectPlayback: (() -> Void)?
  /// Resume direct playback of `content` at the given source position.
  var resumeDirectPlayback: ((Content, TimeInterval) -> Void)?
  /// Source-time tick while casting (drives the subtitle overlay).
  var onTimeTick: ((TimeInterval) -> Void)?
  private var ownerToken: UUID?

  var castVideoView: UIView? { castPlayer?.view }

  /// The engagement survives content changes; `VideoPlayerController.play`
  /// routes new content through `playContent` while this is true.
  var isEngaged: Bool {
    if case .idle = state { return false }
    return true
  }

  /// The current item goes through a remux session on this phone (being built,
  /// casting or refreshing). False for an item the receiver fetches by itself: a
  /// natively playable URL, or the provider's HLS twin of a live channel. The owner
  /// may let the phone lock only in the second case: for a remux cast the phone is
  /// the HTTP origin of the stream.
  var isRemuxing: Bool {
    switch state {
    case .idle: return false
    case let .preparing(pending): return pending.nativeTwinURL == nil
    case let .casting(active): return active.session != nil
    case .refreshing: return true
    }
  }

  // MARK: - Private state

  private var state: State = .idle
  private var castPlayer: AirPlayCastPlayer?
  /// An AirPlay route became active at some point during this engagement.
  private var routeWasActiveDuringEngagement = false
  private var routeDropConfirmWork: DispatchWorkItem?
  private var pickerGraceWork: DispatchWorkItem?
  private var retryWork: DispatchWorkItem?
  /// The wait before the provider's HLS twin is loaded (native live cast).
  private var nativeStartWork: DispatchWorkItem?
  /// The start watchdog of a native live cast, and what it has seen so far.
  private var nativeWatchdogWork: DispatchWorkItem?
  private var nativeStartProbe: NativeStartProbe?
  /// A resume of direct playback that is waiting for the remux writers to close,
  /// and the one work item that drives the wait. Any transition, a newer load of
  /// the owner (`cancelPendingResume`), a new engagement and `dispose` drop both.
  private var pendingResume: PendingResume?
  private var resumeWaitWork: DispatchWorkItem?
  /// The session a dropped resume wait was still waiting on. An engagement that
  /// starts right afterwards drains it before its own writer opens the source.
  private var lingeringDrain: AirPlayRemuxSession?
  /// Installed by an owner that left while its engagement stayed parked: releases
  /// the audio session that owner had activated (see `setParkedAudioSessionRelease`).
  private var parkedAudioSessionRelease: (@Sendable () -> Void)?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var isDisposed = false
  private var cancellables = Set<AnyCancellable>()
  private var noticeSerial = 0

  // MARK: - Cross-screen handoff

  /// PlayerView is screen-scoped, but an AirPlay AVPlayer must outlive navigation
  /// between player screens. The closing owner parks its live controller here;
  /// the next VideoPlayerController takes the SAME instance and swaps only the
  /// content item, preserving the external route and TV picture.
  private static var parkedCrossScreenController: CastController?

  /// Native AVPlayer external playback is owned by KSPlayer rather than this
  /// controller. When that screen closes, the AVPlayer disappears but iOS can
  /// leave the audio route on AirPlay. Remember that short handoff window so the
  /// next (usually FFmpeg/live) item is promoted into this cast pipeline instead
  /// of opening locally and sending audio only.
  private static var nativeExternalContinuationDeadline: Date?
  /// Suppresses a late marker from the outgoing controller after the incoming
  /// controller has already claimed the native AirPlay route. SwiftUI may create
  /// the new screen before calling `onDisappear` on the old one.
  private static var nativeExternalClaimDeadline: Date?

  static func markNativeExternalPlaybackForNextLoad() {
    if let claimedUntil = nativeExternalClaimDeadline, claimedUntil >= Date() {
      return
    }
    nativeExternalContinuationDeadline = Date().addingTimeInterval(30)
  }

  static func claimNativeExternalPlaybackFromActiveController() {
    nativeExternalContinuationDeadline = nil
    nativeExternalClaimDeadline = Date().addingTimeInterval(10)
  }

  static func takeNativeExternalPlaybackContinuation() -> Bool {
    guard let deadline = nativeExternalContinuationDeadline else { return false }
    nativeExternalContinuationDeadline = nil
    guard deadline >= Date() else { return false }
    // Do not strand normal playback in a cast prepare state if the user actually
    // disconnected while moving between screens.
    let routeIsActive = AVAudioSession.sharedInstance().currentRoute.outputs
      .contains { $0.portType == .airPlay }
    if routeIsActive {
      nativeExternalClaimDeadline = Date().addingTimeInterval(10)
    }
    return routeIsActive
  }

  static func takeCrossScreenHandoff() -> CastController? {
    guard let parked = parkedCrossScreenController else { return nil }
    parkedCrossScreenController = nil
    guard !parked.isDisposed, parked.isEngaged else {
      parked.dispose()
      return nil
    }
    return parked
  }

  /// Detaches screen-owned callbacks while playback continues on the TV. Route
  /// observation remains active; if AirPlay disconnects before another screen
  /// takes ownership, the normal endCasting path still tears everything down.
  func attachOwner(
    token: UUID,
    stopDirectPlayback: @escaping () -> Void,
    resumeDirectPlayback: @escaping (Content, TimeInterval) -> Void,
    onTimeTick: @escaping (TimeInterval) -> Void
  ) {
    // A resume still waiting belongs to the previous owner's content; the new
    // owner's hook must never be handed it.
    cancelPendingResume()
    ownerToken = token
    self.stopDirectPlayback = stopDirectPlayback
    self.resumeDirectPlayback = resumeDirectPlayback
    self.onTimeTick = onTimeTick
    clearCrossScreenHandoffIfNeeded()
    // A drop after finished content is confirmed only while nobody owns the
    // engagement. The new owner brings its own content, which re-arms route
    // watching; a confirmation still pending from the parked time would first
    // reload the finished item on the new screen.
    if !Self.shouldConfirmRouteDrop(contentCompleted: isCompleted, ownerAttached: true) {
      routeDropConfirmWork?.cancel()
      routeDropConfirmWork = nil
    }
  }

  /// Returns true when the caller must leave this controller alive: either an
  /// engagement was parked, or a newer screen has already taken ownership.
  func parkForCrossScreenHandoff(owner token: UUID) -> Bool {
    guard ownerToken == token else {
      return true
    }
    ownerToken = nil
    // Parking exists to keep a live AirPlay route (and the TV picture) across
    // screens. An engagement that never had one — still preparing, or playing the
    // local HLS during the picker grace — has nothing to keep: parked, it would
    // play with no player on screen and be inherited by the next stream as a
    // ghost cast. Returning false makes the owner dispose it.
    guard !isDisposed, isEngaged, hasRouteToPreserve else { return false }
    if let previous = Self.parkedCrossScreenController, previous !== self {
      previous.dispose()
    }
    stopDirectPlayback = nil
    resumeDirectPlayback = nil
    onTimeTick = nil
    Self.parkedCrossScreenController = self
    // The route may already be gone: a drop after the content finished was left
    // to the owner's auto-next countdown. That owner is leaving, so no route
    // change will come to end this engagement — confirm the drop now.
    if routeDropConfirmWork == nil, Self.parkingMustConfirmRouteDrop(
      contentCompleted: isCompleted,
      routeActiveNow: isAirPlayRouteActive,
      externalPlaybackActive: castPlayer?.isExternalPlaybackActive == true
    ) {
      scheduleRouteDropConfirm()
    }
    return true
  }

  /// Parking finished content whose route is no longer there: the drop that was
  /// ignored while an owner was attached has to be confirmed after all.
  static func parkingMustConfirmRouteDrop(
    contentCompleted: Bool,
    routeActiveNow: Bool,
    externalPlaybackActive: Bool
  ) -> Bool {
    contentCompleted && !routeActiveNow && !externalPlaybackActive
  }

  private func clearCrossScreenHandoffIfNeeded() {
    if Self.parkedCrossScreenController === self {
      Self.parkedCrossScreenController = nil
    }
  }

  /// The owner that just parked this controller hands over the release of the
  /// audio session it had activated: the parked cast plays through that session,
  /// so the owner's teardown leaves it active. If the engagement then ends while no
  /// screen owns it, `release` runs (off the main thread, shortly afterwards);
  /// otherwise other audio apps would never get their resume signal. Ignored unless
  /// the controller really is parked and ownerless. It is kept when a new owner
  /// attaches (that owner may leave again without ever activating the session), so
  /// `release` has to be safe to call late; the owner guards it with its session
  /// lease, which a newer activation invalidates.
  func setParkedAudioSessionRelease(_ release: @escaping @Sendable () -> Void) {
    guard !isDisposed, isEngaged, ownerToken == nil else { return }
    parkedAudioSessionRelease = release
  }

  /// Whether a parked owner's audio session release is installed (for tests).
  var hasParkedAudioSessionRelease: Bool { parkedAudioSessionRelease != nil }

  /// Whether an engagement that ended may give up the audio session: only when no
  /// screen owns the controller. With an owner, playback carries on in that screen.
  static func shouldReleaseAudioSession(ownerAttached: Bool, releaseInstalled: Bool) -> Bool {
    !ownerAttached && releaseInstalled
  }

  private func releaseParkedAudioSessionIfOwnerless() {
    guard Self.shouldReleaseAudioSession(
      ownerAttached: ownerToken != nil, releaseInstalled: parkedAudioSessionRelease != nil
    ), let release = parkedAudioSessionRelease else { return }
    parkedAudioSessionRelease = nil
    // Same short delay as the owner's own teardown: the cast player's audio output
    // goes away asynchronously, and a session that is still in use refuses to
    // deactivate.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
      release()
    }
  }

  /// The engagement holds (or held) an AirPlay route — the only thing worth
  /// carrying to another screen or another content item. One predicate for the
  /// three places that decide it: parking, sharing a live controller with a newly
  /// created screen, and a content change.
  var hasRouteToPreserve: Bool {
    Self.shouldPreserveEngagement(
      routeWasActive: routeWasActiveDuringEngagement,
      routeActiveNow: isAirPlayRouteActive,
      externalPlaybackActive: castPlayer?.isExternalPlaybackActive == true
    )
  }

  static func shouldPreserveEngagement(
    routeWasActive: Bool,
    routeActiveNow: Bool,
    externalPlaybackActive: Bool
  ) -> Bool {
    routeWasActive || routeActiveNow || externalPlaybackActive
  }

  init() {
    NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.handleRouteChange() }
      .store(in: &cancellables)
    // iOS reclaims the HTTP listener of a suspended app. Coming back, a running
    // remux cast is checked and repaired; this never starts an engagement.
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.repairLocalServerIfNeeded() }
      .store(in: &cancellables)
    // A cast that hangs and is then force-quit never reaches its teardown, where
    // the log of the engagement is saved. Leaving the foreground is the last
    // moment that is sure to run. Record-only: it starts and ends nothing.
    NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self, !self.isDisposed, self.isEngaged else { return }
        Self.persistSessionLog()
      }
      .store(in: &cancellables)
  }

  // MARK: - Session log

  /// Tags of the lines the cast files write (this controller, the remux session,
  /// its writer and the local server).
  static let sessionLogTags = ["AirPlayCast", "AirPlayRemux"]
  /// Where the lines of the last engagement are kept across launches.
  static let sessionLogKey = "airplay.lastSessionLog"

  /// Saves the recent cast lines, so a user who reports a failed cast after the
  /// app was relaunched still has something to copy. The lines are redacted when
  /// they are written (`Log`), and nothing leaves the device.
  private static func persistSessionLog() {
    Log.persistRecent(tags: sessionLogTags, key: sessionLogKey)
  }

  /// The session whose item the cast player shows; nil while preparing and for
  /// items the receiver fetches by itself.
  private var servingSession: AirPlayRemuxSession? {
    switch state {
    case let .casting(active): return active.session
    case let .refreshing(current, _): return current.session
    case .idle, .preparing: return nil
    }
  }

  /// Record-only: what the receiver fetched from a session that failed or is
  /// about to be stopped. Afterwards it is the only way to tell "the TV never
  /// connected" from "the TV fetched and rejected the stream".
  private func logReceiverFetches(of session: AirPlayRemuxSession?, _ context: String) {
    guard let session else { return }
    Log.info("AirPlayCast", "receiver fetches (\(context)): \(session.receiverFetchSummary)")
  }

  /// One line about a failed cast item. The message alone hides which layer
  /// failed (AVFoundation, CoreMedia, the URL loader), so the domain and code of
  /// the error and of the error underneath it are added. Pure function.
  static func logDescription(of error: Error) -> String {
    let ns = error as NSError
    var text = "\(ns.localizedDescription) [\(ns.domain) \(ns.code)"
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
      text += "; underlying \(underlying.domain) \(underlying.code)"
    }
    return text + "]"
  }

  // MARK: - Public API

  /// UHF-style flow behind the AirPlay button: stop the engine, build the local
  /// HLS session, start the cast player; `completion(true)` means the UI should
  /// open the system route picker now.
  /// Returns false when no engagement was started (direct playback is untouched
  /// and still the caller's to drive); true once the engine has been stopped —
  /// from then on every outcome, including failure, is resolved in here.
  ///
  /// `fromButton` is false for the one start that is not the AirPlay button: a
  /// content change that crosses over from native external playback to FFmpeg-only
  /// content. Its completion has nothing to open, so it is not carried in the
  /// state and the start does not count as a button flow (`isPreparingFromButton`).
  @discardableResult
  func startRemuxCast(
    content: Content, fromButton: Bool = true, completion: @escaping (Bool) -> Void
  ) -> Bool {
    guard !isDisposed, case .idle = state else {
      completion(false)
      return false
    }
    // Local checks first, while the phone is still playing: a cast that cannot
    // work (no LAN address, listener down) must not cost the user their picture
    // and an engine reload. Neither check touches the source connection.
    if let failure = AirPlayRemuxSession.preflight() {
      Log.error("AirPlayCast", "preflight failed (\(failure)); direct playback left untouched")
      publishNotice(Self.endReason(forPreflight: failure))
      completion(false)
      return false
    }
    // A VOD session keeps every segment it writes. With less free space than its
    // budget floor the cast would stop the picture only to end as "storage full"
    // moments later, so it is refused here, with the engine still playing.
    if !content.isLive,
       !Self.hasStorageForVODCast(availableCapacity: Self.availableStorageBytes()) {
      Log.error("AirPlayCast", "not enough free space for a VOD remux; direct playback left untouched")
      publishNotice(.storageFull)
      completion(false)
      return false
    }
    // A new engagement supersedes a resume that is still waiting; the session that
    // wait was for is drained by the new writer instead.
    let drain = takeResumeDrainTarget()
    clearNotice()
    stopDirectPlayback?()
    // Telefon oynatıcısının panel bağlantısı asenkron kapanır; yeni bağlantıyı
    // 1 sn geciktir (bağlantı-limitli panelde ilk açılış çakışması).
    beginRemuxSession(
      content: content, replacing: nil, retryUsed: false,
      openDelaySeconds: drain == nil ? 1.0 : 3.0, previousToDrain: drain,
      completion: fromButton ? completion : nil
    )
    return true
  }

  /// Free space of the volume the remux segments are written to; nil when the
  /// system does not say.
  private static func availableStorageBytes() -> Int64? {
    let values = try? LocalHTTPServer.shared.directory.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    )
    return values?.volumeAvailableCapacityForImportantUsage
  }

  /// Enough room to start a VOD remux cast? The session's own budget
  /// (`AirPlayRemuxSession.storageBudgetBytes`) never goes below
  /// `minimumStorageBudgetBytes`; a disk that cannot hold even that budget cannot
  /// hold the cast. Unknown free space (nil, or the 0 the system reports when it
  /// cannot tell) is not a reason to refuse.
  static func hasStorageForVODCast(availableCapacity: Int64?) -> Bool {
    guard let availableCapacity, availableCapacity > 0 else { return true }
    return availableCapacity
      >= AirPlayRemuxSession.storageBudgetBytes(availableCapacity: availableCapacity)
  }

  // MARK: - Native live cast (experimental, off by default)

  /// Same wait as the remux start: the stopped engine closes its source connection
  /// asynchronously.
  static let nativeStartDelaySeconds: TimeInterval = 1
  /// How long the provider's stream gets to show a moving picture before the cast
  /// falls back to the remux.
  static let nativeStartWatchdogSeconds: TimeInterval = 8

  /// AirPlay button flow for a live channel whose provider also serves HLS: the
  /// receiver is given `nativeURL` (the HLS twin of `content.url`, see
  /// `CastNativeURL`) and fetches it by itself, with no remux and no local server.
  /// Whether a panel's HLS output plays on an Apple TV is not established, so the
  /// attempt is watched: no moving picture within `nativeStartWatchdogSeconds`, or
  /// a failed item, falls back once to the normal remux start with the original
  /// URL and remembers the host (`CastNativeURL.rememberFailure`).
  ///
  /// Same contract as `startRemuxCast`: only ever called for an explicit AirPlay
  /// tap; false means nothing was started and direct playback is untouched; from
  /// true on, every outcome is resolved in here. `content` keeps the original URL,
  /// which is what a later exit resumes and what channel changes build on (they
  /// stay on the remux path).
  @discardableResult
  func startNativeLiveCast(
    content: Content, nativeURL: URL, completion: @escaping (Bool) -> Void
  ) -> Bool {
    guard !isDisposed, case .idle = state else {
      completion(false)
      return false
    }
    let drain = takeResumeDrainTarget()
    clearNotice()
    stopDirectPlayback?()
    var pending = Pending(
      session: nil, content: content, retryUsed: false, completion: completion
    )
    pending.nativeTwinURL = nativeURL
    transition(to: .preparing(pending))
    presentLoading(of: content)
    if isAirPlayRouteActive { noteRouteActive() }
    beginBackgroundHold()
    Log.info("AirPlayCast", "trying the provider's HLS stream for this live channel (experimental)")
    // One connection at a time: the twin is opened only after the engine (and a
    // remux writer that was still closing, if any) has let go of the source.
    let delay = drain == nil
      ? Self.nativeStartDelaySeconds
      : Self.resumeDrainCapSeconds + Self.resumeDrainSettleSeconds
    let work = DispatchWorkItem { [weak self] in self?.loadNativeTwin() }
    nativeStartWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    return true
  }

  private func loadNativeTwin() {
    nativeStartWork = nil
    guard !isDisposed, case let .preparing(pending) = state, pending.session == nil,
          let nativeURL = pending.nativeTwinURL
    else { return }
    let content = pending.content
    let player = ensureCastPlayer()
    player.load(
      url: nativeURL, startAt: nil, autoPlay: !content.startPaused,
      userAgent: content.userAgent, appliesTrackPreferences: true
    )
    // The cast player carries playback from here on, as in the native branch of
    // `playContent`.
    endBackgroundHold()
    var active = Active(
      session: nil, content: content,
      timeline: RemuxTimeline(offset: 0, knownDuration: content.knownDuration)
    )
    active.nativeTwinURL = nativeURL
    transition(to: .casting(active))
    presentLoading(of: content)
    pausedByTransportCall = content.startPaused
    armRouteWatch()
    armNativeWatchdog(limitSeconds: Self.nativeStartWatchdogSeconds)
    pending.completion?(true)
  }

  /// Progress of a native live cast, sampled once per `pollSeconds`. "Playing"
  /// means the item is ready and its time moved by at least `minimumAdvanceSeconds`
  /// between two samples; an item that is merely ready proves nothing (a panel can
  /// answer with a playlist whose segments never arrive).
  struct NativeStartProbe: Equatable {
    static let pollSeconds: TimeInterval = 1
    static let minimumAdvanceSeconds: TimeInterval = 0.5

    enum Verdict: Equatable {
      case keepWatching
      /// The picture moves: the attempt worked.
      case playing
      /// Not ready, or not moving, for the whole limit: use the remux instead.
      case fallBack
    }

    let limitSeconds: TimeInterval
    private(set) var elapsedSeconds: TimeInterval = 0
    /// Playback time at the previous sample that found the item ready.
    private(set) var lastReadyTime: TimeInterval?

    init(limitSeconds: TimeInterval) {
      self.limitSeconds = limitSeconds
    }

    mutating func sample(
      isReadyToPlay: Bool, currentTime: TimeInterval, isPaused: Bool
    ) -> Verdict {
      if isReadyToPlay {
        if let last = lastReadyTime, currentTime >= last + Self.minimumAdvanceSeconds {
          return .playing
        }
        lastReadyTime = currentTime
        // Paused by the user while ready: no progress is expected and none is
        // demanded, so this time does not count against the limit.
        if isPaused { return .keepWatching }
      }
      elapsedSeconds += Self.pollSeconds
      return elapsedSeconds >= limitSeconds ? .fallBack : .keepWatching
    }
  }

  /// Armed when the twin is loaded, and again when the receiver takes over (it
  /// fetches the stream from scratch then, with its own client). The work item
  /// dies with the state, like every other timer.
  private func armNativeWatchdog(limitSeconds: TimeInterval) {
    nativeWatchdogWork?.cancel()
    nativeStartProbe = NativeStartProbe(limitSeconds: limitSeconds)
    scheduleNativeWatchdogTick()
  }

  private func scheduleNativeWatchdogTick() {
    let work = DispatchWorkItem { [weak self] in self?.nativeWatchdogTick() }
    nativeWatchdogWork = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + NativeStartProbe.pollSeconds, execute: work
    )
  }

  private func nativeWatchdogTick() {
    nativeWatchdogWork = nil
    guard !isDisposed, case let .casting(active) = state, active.nativeTwinURL != nil,
          let castPlayer, var probe = nativeStartProbe
    else {
      nativeStartProbe = nil
      return
    }
    let verdict = probe.sample(
      isReadyToPlay: castPlayer.isReadyToPlay,
      currentTime: castPlayer.currentTime,
      isPaused: castPlayer.isPaused
    )
    nativeStartProbe = probe
    switch verdict {
    case .keepWatching:
      scheduleNativeWatchdogTick()
    case .playing:
      nativeStartProbe = nil
      Log.info("AirPlayCast", "the provider's HLS stream is playing")
    case .fallBack:
      fallBackFromNativeTwin(active, why: "no moving picture within \(Int(probe.limitSeconds))s")
    }
  }

  /// The native attempt did not work: remember the host, release the provider's
  /// stream and build the normal remux session for the ORIGINAL URL on the same
  /// cast player. Happens at most once per engagement, because the remux item has
  /// no twin; a remux failure then ends the cast through `endCasting`.
  private func fallBackFromNativeTwin(_ active: Active, why: String) {
    Log.error("AirPlayCast", "native live cast failed (\(why)); falling back to the remux")
    CastNativeURL.rememberFailure(for: active.content.url)
    // Dropping the item (not pausing it) is what closes its connections; the
    // player itself, and with it the route, stays.
    castPlayer?.unload()
    var content = active.content
    // The player has no item now, so its rate says nothing; what the user last
    // asked for decides.
    content.startPaused = pausedByTransportCall
    beginRemuxSession(
      content: content, replacing: nil, retryUsed: false,
      openDelaySeconds: Self.nativeStartDelaySeconds, completion: nil
    )
  }

  /// Continues a native external-playback route after its screen-scoped AVPlayer
  /// was torn down. Unlike the AirPlay button flow there is no picker completion:
  /// the route is already selected and only the video-bearing player must be
  /// re-established.
  func continueNativeExternalPlayback(with content: Content) {
    guard !isDisposed, case .idle = state else { return }
    // Supersedes a resume that is still waiting (see `startRemuxCast`).
    let drain = takeResumeDrainTarget()
    clearNotice()
    stopDirectPlayback?()
    if content.nativelyPlayable {
      let player = ensureCastPlayer()
      player.load(
        url: content.url,
        startAt: content.startAt > 0.5 ? content.startAt : nil,
        autoPlay: !content.startPaused,
        userAgent: content.userAgent,
        appliesTrackPreferences: true
      )
      // A superseded resume wait may have left its background hold; no remux
      // session will start here to release it.
      endBackgroundHold()
      transition(to: .casting(Active(
        session: nil,
        content: content,
        timeline: RemuxTimeline(offset: 0, knownDuration: content.knownDuration)
      )))
      presentLoading(of: content)
      armRouteWatch()
    } else {
      beginRemuxSession(
        content: content, replacing: nil, retryUsed: false,
        openDelaySeconds: drain == nil ? 1.0 : 3.0, previousToDrain: drain, completion: nil
      )
    }
  }

  /// Content change (zap, auto-next episode) while engaged: route the new content
  /// through the cast pipeline directly — the engine stays stopped.
  /// Returns false when the content was NOT taken and the caller must load it on
  /// the engine itself: the controller is idle, or the engagement never had a
  /// route (AirPlay tapped, then a zap before any device was chosen) and is ended
  /// here instead of being dragged along as a route-less ghost cast.
  @discardableResult
  func playContent(_ content: Content) -> Bool {
    guard !isDisposed, isEngaged else { return false }
    // A button completion still pending belongs to the superseded prepare. It is
    // taken out before the sessions are stopped and resolved with false — never
    // handed to the new session: its `true` would raise the device picker for
    // content the tap was not about (and re-pop it when a route already exists).
    // Left unresolved it strands the AirPlay button as a spinner.
    takePendingCompletion()?(false)
    switch Self.contentChangeDecision(hasRouteToPreserve: hasRouteToPreserve) {
    case .endEngagement:
      endCasting(resume: false, reason: .contentChanged)
      return false
    case .continueCasting:
      break
    }
    // The rebuild-loop guard is about one source: an error on the previous
    // content must not cost the new one its in-place rebuild.
    lastRuntimeRebuildAt = nil
    let outgoing = currentSession()
    logReceiverFetches(of: servingSession, "content change")
    stopAllSessions()
    if content.nativelyPlayable {
      castPlayer?.pause()
      let player = ensureCastPlayer()
      player.load(
        url: content.url,
        startAt: content.startAt > 0.5 ? content.startAt : nil,
        autoPlay: !content.startPaused,
        userAgent: content.userAgent,
        appliesTrackPreferences: true
      )
      // No remux session will start here to release a hold taken at the previous
      // item's end (or by a superseded prepare); the cast player carries on.
      endBackgroundHold()
      transition(to: .casting(Active(
        session: nil,
        content: content,
        timeline: RemuxTimeline(offset: 0, knownDuration: content.knownDuration)
      )))
      presentLoading(of: content)
      armRouteWatch()
    } else {
      // The old item is left PLAYING (not paused): a live AVPlayer item paused at
      // the edge of a now-static playlist relinquishes the external screen fast,
      // dropping the AirPlay route mid-zap. Its local segments persist (30s) so it
      // holds the TV until the new item swaps in. The new writer waits for the old
      // session's SOURCE connection to actually close before opening — matching why
      // the clean button rebuild is reliable (freed panel slot), not a blind delay.
      beginRemuxSession(
        content: content, replacing: nil, retryUsed: false,
        openDelaySeconds: 3.0, previousToDrain: outgoing, completion: nil
      )
    }
    return true
  }

  enum ContentChangeDecision: Equatable {
    /// No route was ever involved: end the engagement, the engine loads the content.
    case endEngagement
    /// A route exists or existed: the new content stays in the cast pipeline.
    case continueCasting
  }

  /// What a content change does to the engagement. Either way the superseded
  /// button completion resolves with false (see `playContent`).
  static func contentChangeDecision(hasRouteToPreserve: Bool) -> ContentChangeDecision {
    hasRouteToPreserve ? .continueCasting : .endEngagement
  }

  /// Removes the button completion from the pending state and returns it, so the
  /// caller resolves it exactly once and no later exit path can call it again.
  private func takePendingCompletion() -> ((Bool) -> Void)? {
    switch state {
    case var .preparing(pending):
      let completion = pending.completion
      pending.completion = nil
      state = .preparing(pending)  // direct assignment: pending timers must survive
      syncPreparingFromButton()
      return completion
    case .refreshing(let current, var next):
      let completion = next.completion
      next.completion = nil
      state = .refreshing(current: current, next: next)
      return completion
    case .idle, .casting:
      return nil
    }
  }

  /// The session currently holding the source connection (for drain-before-open).
  private func currentSession() -> AirPlayRemuxSession? {
    switch state {
    case .idle: return nil
    case let .preparing(pending): return drainTarget(superseding: pending) ?? pending.session
    case let .casting(active): return active.session
    case let .refreshing(current, next):
      return drainTarget(superseding: next) ?? current.session
    }
  }

  /// Which stopped session a writer that supersedes `pending` has to wait on.
  /// `previousToDrain` takes one session, while two can be closing: the in-flight
  /// one and the one it was itself waiting on.
  private func drainTarget(superseding pending: Pending) -> AirPlayRemuxSession? {
    switch Self.drainChoice(
      hasInFlightSession: pending.session != nil,
      inFlightDrainTargetClosed: pending.draining?.isSourceClosed ?? true
    ) {
    case .inFlightSession: return pending.session
    case .inFlightDrainTarget: return pending.draining
    }
  }

  enum DrainChoice: Equatable {
    /// The in-flight session may have opened the source: wait for it.
    case inFlightSession
    /// The in-flight session cannot have opened yet (or there is none): wait for
    /// the session it was waiting on.
    case inFlightDrainTarget
  }

  /// A writer opens the source only after the session it drains has closed (or
  /// its 3 s cap ran out). So while that session is still closing, the in-flight
  /// writer has not opened and returns from its wait as soon as it is cancelled:
  /// the connection to wait for is still the older one.
  static func drainChoice(
    hasInFlightSession: Bool,
    inFlightDrainTargetClosed: Bool
  ) -> DrainChoice {
    hasInFlightSession && inFlightDrainTargetClosed ? .inFlightSession : .inFlightDrainTarget
  }

  /// Ends the engagement deliberately and resumes direct playback.
  func stopCasting() {
    endCasting(resume: true, reason: .userStopped)
  }

  /// Owner teardown (player screen closing): stop everything, no resume.
  func dispose() {
    guard !isDisposed else { return }
    isDisposed = true
    ownerToken = nil
    clearCrossScreenHandoffIfNeeded()
    let pendingCompletion = takePendingCompletion()
    stopAllSessions()
    castPlayer?.dispose()
    castPlayer = nil
    // Also drops a resume that was still waiting: its owner is going away.
    transition(to: .idle)
    lingeringDrain = nil
    parkedAudioSessionRelease = nil
    endBackgroundHold()
    cancellables.removeAll()
    // Same rule as every other exit: a button completion is always resolved.
    pendingCompletion?(false)
  }

  // MARK: - Transport (routed here by the owner while presenting)

  func play() {
    // A paused cast may have lost its HTTP listener to a suspension, and resuming
    // is when the receiver starts fetching again. A repair that rebuilds the
    // session leaves the state in `.preparing`, where the latch below makes the
    // new session start playing.
    repairLocalServerIfNeeded()
    switch state {
    case var .preparing(pending):
      // Desired-state latch only: the cast player still holds the SUPERSEDED item;
      // playing it would resume the old content's buffered tail on the TV
      // (the field-reported old/new alternation). The new session honors the latch.
      pending.content.startPaused = false
      state = .preparing(pending)  // direct assignment: pending timers must survive
      if isPaused { isPaused = false }
    case .refreshing, .casting:
      latchRefreshPaused(false)
      guard let castPlayer else { return }
      pausedByTransportCall = false
      if isCompleted {
        castPlayer.seek(to: 0)
        if isCompleted { isCompleted = false }
      }
      seekToLiveEdgeIfBehind(castPlayer, trigger: "resuming")
      castPlayer.play()
    case .idle:
      latchPendingResumePaused(false)
    }
  }

  func pause() {
    switch state {
    case var .preparing(pending):
      pending.content.startPaused = true
      state = .preparing(pending)
      if !isPaused { isPaused = true }
    case .idle:
      latchPendingResumePaused(true)
    default:
      latchRefreshPaused(true)
      if castPlayer != nil { pausedByTransportCall = true }
      castPlayer?.pause()
    }
  }

  /// A play/pause while the resume of direct playback is waiting has no player
  /// to reach; it decides how that resume starts. Does nothing when idle with no
  /// resume pending.
  private func latchPendingResumePaused(_ paused: Bool) {
    guard var pending = pendingResume else { return }
    pending.content.startPaused = paused
    pendingResume = pending
    if isPaused != paused { isPaused = paused }
  }

  /// A play/pause during a seek refresh reaches the item that is still playing;
  /// the session being built was given the paused state of the moment it was
  /// requested and must follow, or the swap would undo the user's last tap.
  private func latchRefreshPaused(_ paused: Bool) {
    guard case .refreshing(let current, var next) = state else { return }
    next.content.startPaused = paused
    state = .refreshing(current: current, next: next)  // direct assignment: timers survive
  }

  func setRate(_ rate: Float) {
    castPlayer?.setRate(rate)
  }

  func setVolume(_ value: Double) {
    castPlayer?.setVolume(Float(min(max(value, 0), 125) / 100))
  }

  func seek(toSource target: TimeInterval) {
    let target = max(target, 0)
    switch state {
    case .idle:
      // A resume that is still waiting is re-aimed, like a preparing session.
      guard var pending = pendingResume, !pending.content.isLive else { return }
      pending.at = target
      pendingResume = pending
      if position != target { position = target }
    case var .preparing(pending):
      // Session still starting; remember the new target and restart from it once
      // ready would waste the buffered start — just re-aim the pending content.
      pending.content.startAt = target
      state = .preparing(pending)
      if position != target { position = target }
    case let .casting(active):
      seekWhileCasting(active, target: target)
    case let .refreshing(current, next):
      // Re-aim the refresh: drop the in-flight session, start over at the target.
      // Same rule as the first refresh: the new writer opens only once the
      // stopped session that can still hold the source connection has closed.
      let drain = drainTarget(superseding: next) ?? current.session
      next.session?.stop()
      var content = next.content
      content.startAt = target
      content.startPaused = rebuildStartsPaused(fallback: content.startPaused)
      if position != target { position = target }
      beginRemuxSession(
        content: content, replacing: current, retryUsed: next.retryUsed,
        openDelaySeconds: drain == nil ? 0 : 3.0, previousToDrain: drain, completion: nil
      )
    }
  }

  // MARK: - State machine core

  /// Single transition point: every pending timer belongs to the state that
  /// scheduled it and dies with it.
  /// `awaitingResume` is only passed by the exit path: the engagement is over, but
  /// the resume of direct playback will wait for the writers to close, and the
  /// "loading" presentation stays up meanwhile (see `beginResumeWait`).
  private func transition(to newState: State, awaitingResume: Bool = false) {
    routeDropConfirmWork?.cancel()
    routeDropConfirmWork = nil
    pickerGraceWork?.cancel()
    pickerGraceWork = nil
    retryWork?.cancel()
    retryWork = nil
    nativeStartWork?.cancel()
    nativeStartWork = nil
    nativeWatchdogWork?.cancel()
    nativeWatchdogWork = nil
    nativeStartProbe = nil
    externalWaitWork?.cancel()
    externalWaitWork = nil
    // A waiting resume belongs to the idle state it was scheduled in; whatever
    // comes next (a new engagement, dispose) supersedes it.
    dropResumeWait()
    let previousName = state.logName
    state = newState
    // Not for idle to idle (a controller that never cast being disposed): that
    // would put one line into the log for every player screen that closes.
    if previousName != "idle" || newState.logName != "idle" {
      Log.info("AirPlayCast", "state \(previousName) -> \(newState.logName)")
    }
    let presenting = isEngaged || awaitingResume
    if isPresenting != presenting { isPresenting = presenting }
    let preparing: Bool
    if case .preparing = newState { preparing = true } else { preparing = false }
    if isPreparing != preparing { isPreparing = preparing }
    syncPreparingFromButton()
    if isEngaged {
      rearmPickerSettleWhilePreparing()
    } else {
      routeWasActiveDuringEngagement = false
      externalPlaybackSeenDuringEngagement = false
      // What the route pickers reported belongs to the engagement that just ended.
      isPickerPresented = false
      pickerSettleDeadline = nil
    }
  }

  /// Follows the state: only a `.preparing` state that still carries the button
  /// flow's completion counts. Called from `transition` and from the one place
  /// that takes the completion out with a direct assignment.
  private func syncPreparingFromButton() {
    let fromButton: Bool
    if case let .preparing(pending) = state {
      fromButton = pending.completion != nil
    } else {
      fromButton = false
    }
    if isPreparingFromButton != fromButton { isPreparingFromButton = fromButton }
  }

  /// Single exit path for every failure/disconnect/deliberate stop. Always
  /// resumes direct playback when asked — regardless of which sub-state the
  /// engagement died in (this was the black-screen-wedge class of bugs).
  /// `reason` is published as a notice unless it is a silent one.
  private func endCasting(resume: Bool, reason: CastEndReason) {
    guard !isDisposed, isEngaged else { return }
    Log.info("AirPlayCast", "ending cast (\(reason))")
    let resumeInfo: (Content, TimeInterval)?
    let pendingCompletion: ((Bool) -> Void)?
    switch state {
    case .idle:
      resumeInfo = nil
      pendingCompletion = nil
    case let .preparing(pending):
      resumeInfo = (pending.content, pending.content.startAt)
      pendingCompletion = pending.completion
    case let .casting(active):
      // `startPaused` is stale here (it is only kept current while preparing or
      // refreshing): tell the resume hook whether the cast was paused, so a
      // paused cast does not start playing on the phone.
      var content = active.content
      content.startPaused = Self.resumeStartsPaused(
        castPaused: castPlayer?.isPaused ?? isPaused,
        pausedByTransportCall: pausedByTransportCall,
        secondsSincePauseObserved: pauseObservedAt.map { Date().timeIntervalSince($0) },
        isCompleted: isCompleted
      )
      resumeInfo = (content, position)
      pendingCompletion = nil
    case let .refreshing(_, next):
      // The seek target is where the user wants to be.
      resumeInfo = (next.content, next.content.startAt)
      pendingCompletion = next.completion
    }
    pendingCompletion?(false)
    tearDownEngagement(reason: reason, resume: resume ? resumeInfo : nil)
  }

  /// The teardown behind `endCasting` (and behind the one other place that has to
  /// take an engagement down, a session that could not even be created): stop
  /// everything, publish the reason, and hand playback back to the engine.
  ///
  /// The hand-back is not immediate when a remux writer may still hold the source:
  /// `stop()` only flags the writer, its connection closes later on its own queue,
  /// and a panel that allows one connection refuses the engine's open in between.
  /// The resume then waits for those writers (see `beginResumeWait`), as the start
  /// path and the zap path already do in the other direction.
  /// `alsoDraining`: a stopped session that is not part of the state any more.
  private func tearDownEngagement(
    reason: CastEndReason,
    resume: (Content, TimeInterval)?,
    alsoDraining extra: AirPlayRemuxSession? = nil
  ) {
    // Read before anything is stopped: disposing the cast player can flap the route.
    let routeActiveAtExit = isAirPlayRouteActive
    let castPlayerHeldSource = castPlayerHoldsSource
    var stopped = sessionsThatMayHoldSource()
    if let extra, !stopped.contains(where: { $0 === extra }) { stopped.append(extra) }
    resetEngagementBookkeeping()
    // The engagement ended while this controller is alive (failure, route drop,
    // user request) — a later screen must not resurrect it.
    clearCrossScreenHandoffIfNeeded()
    logReceiverFetches(of: servingSession, "cast ended")
    stopAllSessions()
    castPlayer?.dispose()
    castPlayer = nil
    bumpSurfaceRevision()
    var deferred: PendingResume?
    // With no owner hook there is nothing to resume, hence nothing to wait for.
    if let (content, at) = resume, resumeDirectPlayback != nil {
      let open = stopped.filter { !$0.isSourceClosed }
      switch Self.resumeDrainPlan(
        openSourceCount: open.count, castPlayerHeldSource: castPlayerHeldSource
      ) {
      case .resumeNow:
        break
      case .settleOnly, .pollThenSettle:
        deferred = PendingResume(content: content, at: at, draining: open, startedAt: Date())
      }
    }
    transition(to: .idle, awaitingResume: deferred != nil)
    // The engagement is over and its lines are complete: keep them for a report
    // made after the app was killed or relaunched. Every exit comes through here,
    // also a session that could not be created.
    Self.persistSessionLog()
    publishNotice(
      reason,
      soundStaysOnRoute: Self.exitLeavesSoundOnRoute(
        reason: reason,
        resumesDirectPlayback: resume != nil && resumeDirectPlayback != nil,
        routeActiveAtExit: routeActiveAtExit,
        resumesOnFFmpegEngine: resume.map { !$0.0.nativelyPlayable } ?? false
      )
    )
    if let deferred {
      beginResumeWait(deferred)
      return
    }
    endBackgroundHold()
    resetPresentation()
    releaseParkedAudioSessionIfOwnerless()
    if let (content, at) = resume {
      resumeDirectPlayback?(content, at)
    }
  }

  /// Publishes why a cast ended or could not start. Silent reasons publish
  /// nothing. The serial makes every notice a distinct value, which is this
  /// assignment's inequality guarantee.
  private func publishNotice(_ reason: CastEndReason, soundStaysOnRoute: Bool = false) {
    guard !reason.isSilent else { return }
    noticeSerial += 1
    lastNotice = CastNotice(
      id: noticeSerial, reason: reason, soundStaysOnRoute: soundStaysOnRoute
    )
  }

  /// Does the notice of an ended engagement have to say that the sound may stay
  /// on the receiver? A cast that fails with its AirPlay route still selected
  /// (a zap to a stream that cannot be cast, a rebuild that fails) hands the
  /// content back to the FFmpeg engine, which cannot send video: the picture
  /// returns to the phone while the audio keeps following the route. Without the
  /// remark that looks like a broken AirPlay. Not for silent reasons, not when
  /// nothing is resumed, and not for content the engine's own AVPlayer plays (it
  /// goes to the receiver with its picture).
  static func exitLeavesSoundOnRoute(
    reason: CastEndReason,
    resumesDirectPlayback: Bool,
    routeActiveAtExit: Bool,
    resumesOnFFmpegEngine: Bool
  ) -> Bool {
    !reason.isSilent && resumesDirectPlayback && routeActiveAtExit && resumesOnFFmpegEngine
  }

  // MARK: - Resume after the writers have closed

  /// Poll interval, upper bound and settle of the wait before direct playback
  /// resumes. The settle is the one `RemuxHLSWriter` leaves after a drained session
  /// before it opens the source itself.
  static let resumeDrainPollSeconds: TimeInterval = 0.05
  static let resumeDrainCapSeconds: TimeInterval = 3
  static let resumeDrainSettleSeconds: TimeInterval = 0.3

  enum ResumeDrainPlan: Equatable {
    /// Nothing can still hold the source: resume in the same turn, as before.
    case resumeNow
    /// The cast player itself read the source (a natively cast item); it has no
    /// "closed" signal to poll, so only the short settle is left.
    case settleOnly
    /// Poll the stopped writers until they report closed (or the cap), then settle.
    case pollThenSettle
  }

  /// How the hand-back to the engine is timed. A writer that failed (source error,
  /// failed open) is already closed and does not count as open.
  static func resumeDrainPlan(openSourceCount: Int, castPlayerHeldSource: Bool) -> ResumeDrainPlan {
    if openSourceCount > 0 { return .pollThenSettle }
    return castPlayerHeldSource ? .settleOnly : .resumeNow
  }

  enum ResumeDrainStep: Equatable {
    case poll
    /// Every writer has closed: one settle, then resume.
    case settle
    /// The cap ran out: resume now, there is no player in the meantime.
    case resume
  }

  static func resumeDrainStep(openSourceCount: Int, elapsedSeconds: TimeInterval) -> ResumeDrainStep {
    if openSourceCount <= 0 { return .settle }
    return elapsedSeconds >= resumeDrainCapSeconds ? .resume : .poll
  }

  /// The cast player plays the source URL itself (no remux session in between).
  private var castPlayerHoldsSource: Bool {
    guard castPlayer != nil, case let .casting(active) = state else { return false }
    return active.session == nil
  }

  /// Every session of the current state, stopped or about to be: the candidates
  /// for "may still hold the source connection".
  private func sessionsThatMayHoldSource() -> [AirPlayRemuxSession] {
    switch state {
    case .idle:
      return []
    case let .preparing(pending):
      return [pending.session, pending.draining].compactMap { $0 }
    case let .casting(active):
      return [active.session].compactMap { $0 }
    case let .refreshing(current, next):
      return [current.session, next.session, next.draining].compactMap { $0 }
    }
  }

  /// Starts the wait. The state is already `.idle` (the engagement is over and
  /// nothing can extend it), but the presentation stays with this controller and
  /// shows "loading" at the resume position, and the background hold is kept:
  /// neither the engine nor the cast player exists until the resume fires, which
  /// is at most the cap later.
  private func beginResumeWait(_ pending: PendingResume) {
    pendingResume = pending
    if position != pending.at { position = pending.at }
    if !isBuffering { isBuffering = true }
    if isCompleted { isCompleted = false }
    if isPaused != pending.content.startPaused { isPaused = pending.content.startPaused }
    if isSeekable { isSeekable = false }
    if isPlaybackEstablished { isPlaybackEstablished = false }
    if isExternalPlaybackActive { isExternalPlaybackActive = false }
    beginBackgroundHold()
    if pending.draining.isEmpty {
      scheduleResumeWait(after: Self.resumeDrainSettleSeconds) { [weak self] in
        self?.finishResumeWait()
      }
    } else {
      scheduleResumeWait(after: Self.resumeDrainPollSeconds) { [weak self] in
        self?.resumeDrainTick()
      }
    }
  }

  /// The one work item of the wait; scheduling the next step replaces it.
  private func scheduleResumeWait(after seconds: TimeInterval, _ step: @escaping () -> Void) {
    resumeWaitWork?.cancel()
    let work = DispatchWorkItem { step() }
    resumeWaitWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  private func resumeDrainTick() {
    guard !isDisposed, let pending = pendingResume else { return }
    let open = pending.draining.filter { !$0.isSourceClosed }.count
    switch Self.resumeDrainStep(
      openSourceCount: open, elapsedSeconds: Date().timeIntervalSince(pending.startedAt)
    ) {
    case .poll:
      scheduleResumeWait(after: Self.resumeDrainPollSeconds) { [weak self] in
        self?.resumeDrainTick()
      }
    case .settle:
      scheduleResumeWait(after: Self.resumeDrainSettleSeconds) { [weak self] in
        self?.finishResumeWait()
      }
    case .resume:
      Log.info("AirPlayCast", "remux writer still closing after \(Int(Self.resumeDrainCapSeconds))s; resuming anyway")
      finishResumeWait()
    }
  }

  private func finishResumeWait() {
    guard !isDisposed, let pending = pendingResume else { return }
    resumeWaitWork?.cancel()
    resumeWaitWork = nil
    pendingResume = nil
    if isPresenting != isEngaged { isPresenting = isEngaged }
    resetPresentation()
    endBackgroundHold()
    resumeDirectPlayback?(pending.content, pending.at)
  }

  /// Forgets a waiting resume without touching the presentation. What it was
  /// waiting on is kept for an engagement that starts right afterwards.
  private func dropResumeWait() {
    resumeWaitWork?.cancel()
    resumeWaitWork = nil
    guard let pending = pendingResume else { return }
    pendingResume = nil
    lingeringDrain = pending.draining.first { !$0.isSourceClosed }
  }

  /// For a new engagement: drops a waiting resume and returns the stopped session
  /// the new writer has to drain first (nil when there is none, or it has closed).
  private func takeResumeDrainTarget() -> AirPlayRemuxSession? {
    dropResumeWait()
    defer { lingeringDrain = nil }
    guard let session = lingeringDrain, !session.isSourceClosed else { return nil }
    return session
  }

  /// The owner is about to load something itself (new content, a retry): a resume
  /// that is still waiting must not fire afterwards, or it would load stale content
  /// over the newer one. Returns true when a resume was dropped; the caller's load
  /// then opens while the remux writer's connection may still be closing, which is
  /// what its one-shot post-cast reload is for.
  @discardableResult
  func cancelPendingResume() -> Bool {
    guard pendingResume != nil else { return false }
    dropResumeWait()
    if isPresenting != isEngaged { isPresenting = isEngaged }
    resetPresentation()
    endBackgroundHold()
    return true
  }

  /// A new engagement starts with a clean slate: a notice about the previous
  /// attempt must not linger over the new one.
  private func clearNotice() {
    if lastNotice != nil { lastNotice = nil }
  }

  /// Paused state for the content of an in-place rebuild (seek refresh, runtime
  /// rebuild). `Content.startPaused` is only kept current while `.preparing`;
  /// afterwards play/pause go straight to the cast player, so the player — not
  /// the stale flag — knows what the user last asked for.
  private func rebuildStartsPaused(fallback: Bool) -> Bool {
    castPlayer?.isPaused ?? fallback
  }

  private func stopAllSessions() {
    switch state {
    case .idle:
      break
    case let .preparing(pending):
      pending.session?.stop()
    case let .casting(active):
      active.session?.stop()
    case let .refreshing(current, next):
      current.session?.stop()
      next.session?.stop()
    }
  }

  // MARK: - Session lifecycle

  /// Starts a remux session for `content`. With `replacing` set (in-content seek
  /// refresh) the old item keeps playing what its session wrote until the new one
  /// is ready. The caller stops the old session first and passes it as
  /// `previousToDrain`: two writers never hold the source at the same time.
  private func beginRemuxSession(
    content: Content,
    replacing current: Active?,
    retryUsed: Bool,
    openDelaySeconds: Double = 0,
    previousToDrain: AirPlayRemuxSession? = nil,
    completion: ((Bool) -> Void)?
  ) {
    let session: AirPlayRemuxSession
    do {
      session = try AirPlayRemuxSession(
        sourceURL: content.url,
        startOffsetSeconds: content.startAt,
        isLive: content.isLive,
        userAgent: content.userAgent,
        // Refresh (user actively waiting at the scrubber): low buffer gate.
        // Fresh start: high buffer gate so playback starts with a cushion.
        minimumBufferSeconds: current == nil ? 12 : 5,
        openDelaySeconds: openDelaySeconds,
        previousToDrain: previousToDrain,
        subtitleFileURL: content.subtitleFileURL,
        subtitleName: content.subtitleName,
        subtitleLanguage: content.subtitleLanguage
      )
    } catch {
      // Rare (temp dir creation). Resume the REQUESTED content directly — the
      // stale state must not decide (it would resurrect the previous content),
      // and in the button flow the engine is already stopped: not resuming
      // would leave a black screen.
      Log.error("AirPlayCast", "session create failed: \(error.localizedDescription)")
      completion?(false)
      // Not through `endCasting` (its resume would come from the stale state), but
      // through the same teardown: the sessions stopped for this one may still be
      // closing, and the resume waits for them like every other exit.
      tearDownEngagement(
        reason: Self.endReason(for: error, duringStart: true),
        resume: (content, content.startAt),
        alsoDraining: previousToDrain
      )
      return
    }
    let pending = Pending(
      session: session, content: content, retryUsed: retryUsed, completion: completion,
      draining: previousToDrain
    )
    if let current {
      transition(to: .refreshing(current: current, next: pending))
    } else {
      transition(to: .preparing(pending))
      presentLoading(of: content)
    }
    if isAirPlayRouteActive { noteRouteActive() }
    beginBackgroundHold()
    session.onError = { [weak self, weak session] error in
      guard let self, let session else { return }
      self.handleSessionRuntimeError(session, error)
    }
    session.onStorageBudgetExceeded = { [weak self, weak session] in
      guard let self, let session else { return }
      self.handleStorageBudgetExceeded(session)
    }
    Log.info("AirPlayCast", "starting remux at \(Int(content.startAt))s for \(content.isLive ? "live" : "vod") content")
    session.start { [weak self, weak session] result in
      guard let self, let session, !self.isDisposed, self.isPendingSession(session) else {
        session?.stop()
        return
      }
      switch result {
      case let .success(localURL):
        self.sessionDidStart(session, localURL: localURL)
      case let .failure(error):
        self.handleSessionStartFailure(session, error: error)
      }
    }
  }

  private func isPendingSession(_ session: AirPlayRemuxSession) -> Bool {
    switch state {
    case let .preparing(pending):
      return pending.session === session
    case let .refreshing(_, next):
      return next.session === session
    case .idle, .casting:
      return false
    }
  }

  private func sessionDidStart(_ session: AirPlayRemuxSession, localURL: URL) {
    let content: Content
    let completion: ((Bool) -> Void)?
    switch state {
    case let .preparing(pending):
      content = pending.content
      completion = pending.completion
    case let .refreshing(current, next):
      current.session?.stop()
      content = next.content
      completion = next.completion
    case .idle, .casting:
      session.stop()
      return
    }
    endBackgroundHold()
    let player = ensureCastPlayer()
    player.load(
      url: localURL, startAt: nil, autoPlay: !content.startPaused,
      // A WebVTT rendition is only present when the writer added one (external subtitle,
      // TS/VOD path); turning it on here makes it show on the AirPlay target.
      preferredLegible: content.subtitleFileURL != nil
    )
    // The input seek may have failed on a non-seekable source: the writer then
    // remuxes from 0:00 and reports it — presenting the requested offset would
    // show one position while the TV plays another.
    let actualOffset = session.effectiveStartOffsetSeconds
    let timeline = RemuxTimeline(
      offset: actualOffset,
      knownDuration: content.knownDuration > 0
        ? content.knownDuration
        : session.sourceDurationSeconds
    )
    transition(to: .casting(Active(session: session, content: content, timeline: timeline)))
    Log.info(
      "AirPlayCast",
      "remux session ready (offset \(Int(actualOffset))s, \(content.isLive ? "live" : "vod"))"
    )
    // A live-edge seek issued on the previous item says nothing about this one:
    // its first fall-behind gets its own seek before a rebuild.
    liveEdgeSeekGraceUntil = nil
    if position != actualOffset { position = actualOffset }
    if isBuffering { isBuffering = false }
    // A paused start is the user's own pause carried over, not a side effect of
    // whatever ends the cast later (see `resumeStartsPaused`).
    pausedByTransportCall = content.startPaused
    armRouteWatch()
    // A session that starts while the receiver already has the route (zap,
    // rebuild) is fetched by the receiver from scratch, like the first one.
    if player.isExternalPlaybackActive { armReceiverWatchdog(for: session) }
    completion?(true)
    // A seek that arrived while preparing re-aimed `content.startAt`, but this
    // session was already remuxing from its original offset — chase the target.
    // Never chase when the input could not seek (it would loop rebuilding).
    if actualOffset == session.startOffsetSeconds,
       abs(content.startAt - session.startOffsetSeconds) > 2 {
      seek(toSource: content.startAt)
    }
  }

  private func handleSessionStartFailure(_ session: AirPlayRemuxSession, error: Error) {
    Log.error("AirPlayCast", "session start failed: \(error.localizedDescription)")
    session.stop()
    switch state {
    case let .preparing(pending) where pending.session === session:
      // One delayed retry for transient failures — panel connection limits clear
      // once the previous connections die. The button flow retries too (spinner
      // stays up via the carried completion): failing permanently on the first
      // collision was the field-reported first-start failure. The wait depends on
      // the cause (see `startRetryDelay`).
      switch Self.startFailureAction(retryUsed: pending.retryUsed, error: error) {
      case let .retry(retryDelay):
        var waiting = pending
        waiting.session = nil
        waiting.retryUsed = true
        transition(to: .preparing(waiting))
        let work = DispatchWorkItem { [weak self] in
          guard let self, !self.isDisposed,
                case let .preparing(p) = self.state, p.session == nil
          else { return }
          self.beginRemuxSession(
            content: p.content, replacing: nil, retryUsed: true, completion: p.completion
          )
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
      case let .endCast(reason):
        pending.completion?(false)
        var cleared = pending
        cleared.completion = nil  // resolved above; endCasting must not double-call
        // A writer that never ran never reports its source closed; the exit must
        // not wait for it.
        if !Self.startFailureLeavesWriter(error) { cleared.session = nil }
        transition(to: .preparing(cleared))
        endCasting(resume: true, reason: reason)
      }
    case let .refreshing(current, next) where next.session === session:
      // `current`'s writer was stopped when the refresh began (single source
      // connection), so there is no session to fall back to: snapping back to the
      // old position would present a cast that can no longer continue. Retry
      // once; after that end the cast, which resumes direct playback at the seek
      // target and tells the user why.
      switch Self.startFailureAction(retryUsed: next.retryUsed, error: error) {
      case let .retry(retryDelay):
        var waiting = next
        waiting.session = nil
        waiting.retryUsed = true
        transition(to: .refreshing(current: current, next: waiting))
        let work = DispatchWorkItem { [weak self] in
          guard let self, !self.isDisposed,
                case let .refreshing(c, n) = self.state, n.session == nil
          else { return }
          // Everything stopped earlier has had the whole retry delay to close.
          self.beginRemuxSession(
            content: n.content, replacing: c, retryUsed: true, completion: n.completion
          )
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
      case let .endCast(reason):
        next.completion?(false)
        var cleared = next
        cleared.completion = nil  // resolved above; endCasting must not double-call
        if !Self.startFailureLeavesWriter(error) { cleared.session = nil }
        state = .refreshing(current: current, next: cleared)  // direct: ends right below
        endCasting(resume: true, reason: reason)
      }
    default:
      break
    }
  }

  /// Did the failed start get as far as running its writer? `AirPlayRemuxSession`
  /// reports three failures before that point: the listener could not be started
  /// (an error of the listener, not of the session's own domain), no LAN
  /// address, and a listener that started but has no port (`listenerNotReady`).
  /// Such a session never opened the source and never reports it closed,
  /// so the resume after the cast must not poll it up to the cap. Every other
  /// failure comes from a writer that ran and unwinds when it is stopped.
  static func startFailureLeavesWriter(_ error: Error) -> Bool {
    if error is RemuxHLSWriter.RemuxError { return true }
    let ns = error as NSError
    guard ns.domain == AirPlayRemuxSession.errorDomain else { return false }
    return ns.code != AirPlayRemuxSession.ErrorCode.noLANAddress.rawValue
      && ns.code != AirPlayRemuxSession.ErrorCode.listenerNotReady.rawValue
  }

  enum StartFailureAction: Equatable {
    case retry(after: TimeInterval)
    case endCast(CastEndReason)
  }

  /// What a failed session start leads to. One rule for a first start, an
  /// in-place rebuild and a seek refresh: none of them has an older session that
  /// is still connected, so the choice is one delayed retry or the end of the cast.
  static func startFailureAction(retryUsed: Bool, error: Error) -> StartFailureAction {
    if !retryUsed, let delay = startRetryDelay(for: error) {
      return .retry(after: delay)
    }
    return .endCast(endReason(for: error, duringStart: true))
  }

  /// At most one in-place session rebuild per this interval; a second runtime
  /// error inside it ends the cast (prevents rebuild loops on a dead source).
  private var lastRuntimeRebuildAt: Date?

  /// Writer/source error after the session started serving.
  private func handleSessionRuntimeError(_ session: AirPlayRemuxSession, _ error: Error) {
    guard !isDisposed else { return }
    switch state {
    case let .casting(active) where active.session === session:
      // Live panel resets and VOD network hiccups are routine; tearing the whole
      // cast down for each one is the field-reported "picture cuts out". Rebuild
      // the session in place once; only a persistent failure ends the cast.
      Log.info("AirPlayCast", "session error: \(error.localizedDescription)")
      if !rebuildSessionInPlace(active, cause: .sourceError) {
        Log.error("AirPlayCast", "second session error within 30s: \(error.localizedDescription)")
        endCasting(resume: true, reason: Self.endReason(for: error, duringStart: false))
      }
    case let .refreshing(current, _) where current.session === session:
      // `current` was stopped when the refresh began; an error it reported just
      // before that changes nothing. Its item keeps playing what was written and
      // the refresh has its own failure handling.
      break
    default:
      break  // stale session; already superseded
    }
  }

  /// The volume is running low and the session's segment directory is worth
  /// releasing: start a fresh session at the current position, which releases the
  /// old directory whole.
  private func handleStorageBudgetExceeded(_ session: AirPlayRemuxSession) {
    guard !isDisposed, case let .casting(active) = state, active.session === session,
          Self.storageRebuildAllowed(
            contentCompleted: isCompleted,
            // A session whose own start seek was refused proves the source cannot
            // seek: a rebuild would restart the film at 0:00, so it is left playing.
            startSeekHonoured: session.effectiveStartOffsetSeconds == session.startOffsetSeconds,
            sourceCanSeek: session.sourceCanSeek
          )
    else { return }
    rebuildSessionInPlace(active, cause: .storageBudgetExceeded)
  }

  /// May a running VOD session be rebuilt at the current position to release its
  /// segments? The rebuild is a seek on the source. A session that started at
  /// 0:00 never attempted one, so its honoured start says nothing about whether
  /// the source can seek: the writer's own answer (`sourceCanSeek`) is required
  /// as well. This is the only voluntary rebuild of a cast that plays fine, so in
  /// doubt it does not run, and the cast goes on until the disk is really full.
  static func storageRebuildAllowed(
    contentCompleted: Bool,
    startSeekHonoured: Bool,
    sourceCanSeek: Bool
  ) -> Bool {
    !contentCompleted && startSeekHonoured && sourceCanSeek
  }

  enum RebuildCause: Equatable {
    /// Writer / source error while the session was serving.
    case sourceError
    /// The playhead of a live cast fell behind the served window.
    case fellBehindLiveWindow
    /// The local HTTP listener had to be restarted, or does not answer.
    case localServerLost
    /// The session's segments outgrew the storage budget.
    case storageBudgetExceeded
  }

  enum RuntimeRebuildDecision: Equatable {
    case rebuild(countsAgainstGuard: Bool)
    case endCast
  }

  static let runtimeRebuildGuardSeconds: TimeInterval = 30

  /// Whether a running session may be rebuilt in place. Only a source error is
  /// held to the rebuild-loop guard (a second one within the interval means the
  /// source is gone); the other causes repair something local while the source is
  /// healthy, so they neither count against the guard nor are stopped by it.
  static func runtimeRebuildDecision(
    cause: RebuildCause,
    secondsSinceLastGuardedRebuild: TimeInterval?
  ) -> RuntimeRebuildDecision {
    guard cause == .sourceError else { return .rebuild(countsAgainstGuard: false) }
    if let elapsed = secondsSinceLastGuardedRebuild, elapsed < runtimeRebuildGuardSeconds {
      return .endCast
    }
    return .rebuild(countsAgainstGuard: true)
  }

  /// The one in-place rebuild every runtime cause goes through: stop the session,
  /// keep the item playing (it holds the external screen), and let the new writer
  /// drain the old source connection before it reopens the panel. One retry is
  /// allowed. Returns false when the rebuild-loop guard refused; the caller then
  /// ends the cast.
  /// `startPaused`: only for a rebuild after the item failed. A failed item stops
  /// the player, so the player's rate no longer says what the user asked for.
  @discardableResult
  private func rebuildSessionInPlace(
    _ active: Active, cause: RebuildCause, startPaused: Bool? = nil
  ) -> Bool {
    switch Self.runtimeRebuildDecision(
      cause: cause,
      secondsSinceLastGuardedRebuild: lastRuntimeRebuildAt.map { Date().timeIntervalSince($0) }
    ) {
    case .endCast:
      return false
    case let .rebuild(countsAgainstGuard):
      if countsAgainstGuard { lastRuntimeRebuildAt = Date() }
    }
    Log.info("AirPlayCast", "rebuilding session in place (\(cause))")
    let outgoing = active.session
    logReceiverFetches(of: outgoing, "rebuild")
    outgoing?.stop()
    var content = active.content
    content.startAt = content.isLive ? 0 : position
    content.startPaused = startPaused ?? rebuildStartsPaused(fallback: content.startPaused)
    // Content that came in through a zap carries no duration of its own; keep the
    // one this session found so the scrubber does not drop to 0 while rebuilding.
    if content.knownDuration <= 0 { content.knownDuration = active.timeline.knownDuration }
    beginRemuxSession(
      content: content, replacing: nil, retryUsed: false,
      openDelaySeconds: 3.0, previousToDrain: outgoing, completion: nil
    )
    return true
  }

  /// Clears what belongs to one engagement and must not leak into the next.
  private func resetEngagementBookkeeping() {
    lastRuntimeRebuildAt = nil
    liveEdgeSeekGraceUntil = nil
    pausedByTransportCall = false
    pauseObservedAt = nil
    receiverWatchdogWork?.cancel()
    receiverWatchdogWork = nil
  }

  // MARK: - Local server repair

  /// iOS defuncts the listener of a suspended app, and a session's URLs carry the
  /// port they were minted with. Called when the app returns to the foreground,
  /// when play() resumes a cast and when the receiver resumes it by itself (the
  /// TV remote; see `handleCastStateChange`): the moments a cast that sat paused
  /// through a suspension is about to be fetched from again. It only repairs a
  /// running remux cast; it never starts or ends an engagement by itself.
  private func repairLocalServerIfNeeded() {
    guard !isDisposed, case let .casting(active) = state, let session = active.session,
          !isCompleted
    else { return }
    let server = LocalHTTPServer.shared
    if Self.localServerNeedsRebuild(portChanged: server.ensureRunning(), healthy: nil) {
      rebuildSessionInPlace(active, cause: .localServerLost)
      return
    }
    // The listener object can look alive after a suspension and still not accept
    // connections; only a request shows that.
    server.checkHealth { [weak self, weak session] healthy in
      guard let self, let session, !self.isDisposed,
            case let .casting(current) = self.state, current.session === session,
            Self.localServerNeedsRebuild(portChanged: false, healthy: healthy)
      else { return }
      // Give the server the chance to replace a listener the check found dead;
      // the rebuilt session mints its URLs from whatever port is current.
      _ = server.ensureRunning()
      self.rebuildSessionInPlace(current, cause: .localServerLost)
    }
  }

  /// A session's URLs are stale after a port change, and unreachable while the
  /// listener does not answer. `healthy` is nil while the check has not run.
  static func localServerNeedsRebuild(portChanged: Bool, healthy: Bool?) -> Bool {
    portChanged || healthy == false
  }

  enum CastItemFailureAction: Equatable {
    /// The item failed because the receiver lost the phone's listener, not
    /// because of the stream: rebuild the session on the listener that serves now.
    case rebuildInPlace
    /// The listener looks alive; only a request shows whether it answers.
    case probeListener
    /// The listener is healthy, so the failure is the receiver's (or the item
    /// is not served by this phone): end the cast, as before.
    case endCast
  }

  /// What a failed cast item leads to. iOS reclaims the listener of a suspended
  /// app; the receiver of a cast that sat paused through that then fetches from a
  /// dead port and fails the item, which used to end the cast. A listener that was
  /// not serving, came back on another port or does not answer is repaired with
  /// an in-place rebuild instead. A healthy listener always ends the cast, so an
  /// item that really cannot be played cannot loop through rebuilds.
  /// `healthy` is nil while the listener has not been probed.
  static func castItemFailureAction(
    isRemuxSession: Bool,
    contentCompleted: Bool,
    listenerWasServing: Bool,
    portChanged: Bool,
    healthy: Bool?
  ) -> CastItemFailureAction {
    guard isRemuxSession, !contentCompleted else { return .endCast }
    if !listenerWasServing || portChanged { return .rebuildInPlace }
    switch healthy {
    case nil: return .probeListener
    case true?: return .endCast
    case false?: return .rebuildInPlace
    }
  }

  // MARK: - Pause bookkeeping (cast exit)

  /// The last pause came from `pause()` on this controller, i.e. from the user.
  private var pausedByTransportCall = false
  /// When the cast player was first seen paused without such a call (TV remote,
  /// or the system pausing it as the route or the item goes away).
  private var pauseObservedAt: Date?

  /// A pause this recent when the cast ends is attributed to the ending itself:
  /// the route-drop confirmation alone takes 4 s.
  static let exitPauseAttributionSeconds: TimeInterval = 6

  /// Should direct playback resume paused after the cast ended? A cast the user
  /// paused must not start playing on the phone. But the cast player also stops
  /// by itself when its route or item goes away, moments before the cast ends:
  /// that is not the user's pause, and playback carries on as it did before.
  /// A finished item is "paused" at its end and resumes as before as well.
  static func resumeStartsPaused(
    castPaused: Bool,
    pausedByTransportCall: Bool,
    secondsSincePauseObserved: TimeInterval?,
    isCompleted: Bool
  ) -> Bool {
    guard castPaused, !isCompleted else { return false }
    if pausedByTransportCall { return true }
    guard let elapsed = secondsSincePauseObserved else { return false }
    return elapsed >= exitPauseAttributionSeconds
  }

  /// The same attribution for a session that is rebuilt after its item failed:
  /// the failure stops the player by itself, and only a pause of the user's is
  /// carried over to the rebuilt session.
  private var castPausedByUser: Bool {
    Self.resumeStartsPaused(
      castPaused: castPlayer?.isPaused ?? isPaused,
      pausedByTransportCall: pausedByTransportCall,
      secondsSincePauseObserved: pauseObservedAt.map { Date().timeIntervalSince($0) },
      isCompleted: isCompleted
    )
  }

  /// Follows the cast player's paused state for `resumeStartsPaused`.
  private func notePausedState(_ paused: Bool) {
    if paused {
      if pauseObservedAt == nil { pauseObservedAt = Date() }
    } else {
      pauseObservedAt = nil
      pausedByTransportCall = false
    }
  }

  // MARK: - Live edge (resume after a long pause)

  /// Set when a seek to the live edge is issued, by `play()` or by the time tick
  /// that finds a playing cast behind its window. While it is in the future the
  /// seek is still settling and the fell-behind handling holds off. Once it has
  /// passed it is the one-shot latch of that handling: a playhead that is still
  /// behind means the seek did not help, and the session is rebuilt; one that is
  /// back inside the window clears it (`liveEdgeSeekRecovered`), so a later
  /// fall-behind gets its seek again.
  private var liveEdgeSeekGraceUntil: Date?
  static let liveEdgeSeekGraceSeconds: TimeInterval = 3
  /// Distance kept from the end of the seekable range when rejoining live.
  static let liveEdgeMarginSeconds: TimeInterval = 2

  /// The playhead is before the first segment the playlist still serves.
  static func isBehindServedWindow(
    localTime: TimeInterval, windowStart: TimeInterval, windowEnd: TimeInterval
  ) -> Bool {
    windowEnd > 2 && localTime + 1 < windowStart
  }

  /// Where `play()` moves a live remux cast that was paused for longer than its
  /// sliding window; nil when the playhead is still inside the window. Seeking
  /// keeps the healthy writer and its source connection, where the fell-behind
  /// rebuild reconnects and waits for three new segments.
  static func liveResumeSeekTarget(
    localTime: TimeInterval, windowStart: TimeInterval, windowEnd: TimeInterval
  ) -> TimeInterval? {
    guard isBehindServedWindow(
      localTime: localTime, windowStart: windowStart, windowEnd: windowEnd
    ) else { return nil }
    return max(windowEnd - liveEdgeMarginSeconds, windowStart)
  }

  /// Should the time tick act (see `fellBehindAction`) because the playhead
  /// fell out of the served window? Not while paused (nothing is being fetched),
  /// and not while a live-edge seek is still settling.
  static func shouldSelfHeal(
    localTime: TimeInterval,
    windowStart: TimeInterval,
    windowEnd: TimeInterval,
    isPaused: Bool,
    liveEdgeSeekSettling: Bool
  ) -> Bool {
    guard !isPaused, !liveEdgeSeekSettling else { return false }
    return isBehindServedWindow(
      localTime: localTime, windowStart: windowStart, windowEnd: windowEnd
    )
  }

  enum FellBehindAction: Equatable {
    /// Live, first time: seek to the live edge. The writer, its source connection
    /// and the item stay; a receiver stall, a Wi-Fi hiccup or a pause lifted with
    /// the TV remote then costs a jump to live instead of a rebuild.
    case seekToLiveEdge
    /// Live, and the seek was tried: its grace ran out with the playhead still
    /// behind, so the session is rebuilt in place, as before.
    case rebuildSession
    /// VOD: seek again through the normal path.
    case reseek
  }

  /// What the time tick does for a playing cast whose playhead is behind the
  /// served window. `liveEdgeSeekTried`: the one-shot latch is set, i.e. a seek
  /// to the live edge was issued and the playhead has not been back inside the
  /// window since. The tick only gets here once that seek's grace has passed.
  static func fellBehindAction(isLive: Bool, liveEdgeSeekTried: Bool) -> FellBehindAction {
    guard isLive else { return .reseek }
    return liveEdgeSeekTried ? .rebuildSession : .seekToLiveEdge
  }

  /// Is the one-shot live-edge seek armed again? Yes once a seek that was tried
  /// has settled and the playhead is inside a known window. A window that is not
  /// reported yet (`windowEnd` near 0) proves nothing: clearing the latch on it
  /// would let a playhead that never recovered seek over and over.
  static func liveEdgeSeekRecovered(
    seekTried: Bool,
    seekSettling: Bool,
    localTime: TimeInterval,
    windowStart: TimeInterval,
    windowEnd: TimeInterval
  ) -> Bool {
    seekTried && !seekSettling && windowEnd > 2 && localTime + 1 >= windowStart
  }

  /// `trigger` only words the log line.
  private func seekToLiveEdgeIfBehind(_ castPlayer: AirPlayCastPlayer, trigger: String) {
    guard case let .casting(active) = state, active.session != nil, active.content.isLive
    else { return }
    let window = castPlayer.seekableRange
    guard let target = Self.liveResumeSeekTarget(
      localTime: castPlayer.currentTime, windowStart: window.start, windowEnd: window.end
    ) else { return }
    Log.info("AirPlayCast", "\(trigger) behind the live window; seeking to the live edge")
    liveEdgeSeekGraceUntil = Date().addingTimeInterval(Self.liveEdgeSeekGraceSeconds)
    castPlayer.seek(to: target)
  }

  // MARK: - Receiver reachability

  private var receiverWatchdogWork: DispatchWorkItem?
  static let receiverWatchdogSeconds: TimeInterval = 15

  enum ReceiverWatchdogVerdict: Equatable {
    case healthy
    /// Nothing can be concluded while paused: look again later.
    case waitLonger
    case unreachable
  }

  /// The receiver has the route, but has it reached this phone? One sign of life
  /// is enough: a request from a peer that is not this phone, or a moving
  /// playhead. Both missing while playback is wanted means the receiver cannot
  /// open a connection to the phone (client isolation, another subnet, a VPN).
  static func receiverWatchdogVerdict(
    receiverFetched: Bool,
    timeAdvanced: Bool,
    isPaused: Bool
  ) -> ReceiverWatchdogVerdict {
    if receiverFetched || timeAdvanced { return .healthy }
    return isPaused ? .waitLonger : .unreachable
  }

  /// Armed when external playback is active for a remux session. The work item
  /// belongs to `session`: it does nothing once another session is casting, so
  /// it needs no cancellation on state changes.
  private func armReceiverWatchdog(for session: AirPlayRemuxSession) {
    receiverWatchdogWork?.cancel()
    let baseline = castPlayer?.currentTime ?? 0
    let work = DispatchWorkItem { [weak self, weak session] in
      guard let self, let session, !self.isDisposed else { return }
      self.receiverWatchdogWork = nil
      guard case let .casting(active) = self.state, active.session === session,
            let castPlayer = self.castPlayer, castPlayer.isExternalPlaybackActive
      else { return }
      switch Self.receiverWatchdogVerdict(
        receiverFetched: session.lastReceiverFetchAt != nil,
        timeAdvanced: castPlayer.currentTime > baseline + 1,
        isPaused: castPlayer.isPaused
      ) {
      case .healthy:
        break
      case .waitLonger:
        self.armReceiverWatchdog(for: session)
      case .unreachable:
        Log.error("AirPlayCast", "receiver never fetched from this phone; ending cast")
        self.logReceiverFetches(of: session, "receiver unreachable")
        self.endCasting(resume: true, reason: .receiverUnreachable)
      }
    }
    receiverWatchdogWork = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.receiverWatchdogSeconds, execute: work
    )
  }

  /// Start failures worth one retry, and how long to wait first; nil = permanent.
  /// - Connection-limit collisions (input open refused, playlist never produced):
  ///   8 s, the time dying panel connections need to clear.
  /// - Video parameters unknown (the probe window held no keyframe): about 2 s.
  ///   Nothing has to clear; the next open simply lands elsewhere in the GOP.
  /// - Audio parameters unknown (no sample rate after probing): about 2 s, for
  ///   the same reason; the next probe starts on other packets.
  /// - Timestamp jump inside the start window (fMP4 path only): about 2 s as well.
  ///   The source restarted its clock; a fresh session starts on the new timeline.
  static func startRetryDelay(for error: Error) -> TimeInterval? {
    if let remuxError = error as? RemuxHLSWriter.RemuxError {
      switch remuxError {
      case .openInputFailed: return 8
      case .videoParametersUnknown, .audioParametersUnknown, .timestampDiscontinuity: return 2
      default: return nil
      }
    }
    let ns = error as NSError
    if ns.domain == AirPlayRemuxSession.errorDomain,
       ns.code == AirPlayRemuxSession.ErrorCode.playlistTimeout.rawValue {
      return 8
    }
    return nil
  }

  // MARK: - End reasons

  /// Maps a session / writer error onto the reason shown to the user.
  /// `duringStart` separates "never got going" from "died while casting".
  static func endReason(for error: Error, duringStart: Bool) -> CastEndReason {
    if let remuxError = error as? RemuxHLSWriter.RemuxError {
      switch remuxError {
      case .openInputFailed:
        return .sourceOpenFailed
      case .noCompatibleStreams:
        return .incompatibleStreams
      case .videoParametersUnknown, .audioParametersUnknown:
        // Still no keyframe in the probe window after the retry: the source did
        // not hand over a usable start in time. Another attempt may well work,
        // so this must not read as "cannot be cast".
        // The same holds for an audio stream that still has no sample rate.
        return .sourceTooSlow
      case let .openOutputFailed(code):
        return isOutOfSpace(avCode: code) ? .storageFull : .incompatibleStreams
      case let .writeFailed(code):
        // Only ENOSPC means a full disk; any other write failure is the muxer
        // rejecting the stream.
        if isOutOfSpace(avCode: code) { return .storageFull }
        return duringStart ? .incompatibleStreams : .sourceLost
      default:
        // readFailed and anything the writer adds later: a source problem.
        return duringStart ? .sourceOpenFailed : .sourceLost
      }
    }
    let ns = error as NSError
    if ns.domain == AirPlayRemuxSession.errorDomain {
      if ns.code == AirPlayRemuxSession.ErrorCode.noLANAddress.rawValue { return .noWiFi }
      if ns.code == AirPlayRemuxSession.ErrorCode.playlistTimeout.rawValue {
        return .sourceTooSlow
      }
      if ns.code == AirPlayRemuxSession.ErrorCode.localServerUnreachable.rawValue {
        return .localServerUnavailable
      }
      // A listener without a port is the phone's own server failing, not a
      // missing Wi-Fi address: it must not read as "connect to Wi-Fi".
      if ns.code == AirPlayRemuxSession.ErrorCode.listenerNotReady.rawValue {
        return .localServerUnavailable
      }
    }
    if isOutOfSpace(ns) { return .storageFull }
    // What is left at start time comes from the local side (listener start, the
    // session's temp directory); at runtime it is the source.
    return duringStart ? .localServerUnavailable : .sourceLost
  }

  static func endReason(
    forPreflight failure: AirPlayRemuxSession.PreflightFailure
  ) -> CastEndReason {
    if case .noLANAddress = failure { return .noWiFi }
    return .localServerUnavailable
  }

  /// FFmpeg reports errno values negated (AVERROR(ENOSPC)).
  private static func isOutOfSpace(avCode code: Int32) -> Bool {
    code == -ENOSPC || code == ENOSPC
  }

  private static func isOutOfSpace(_ error: NSError) -> Bool {
    if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
    if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
      return true
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isOutOfSpace(underlying)
    }
    return false
  }

  // MARK: - Cast player

  private func ensureCastPlayer() -> AirPlayCastPlayer {
    if let castPlayer { return castPlayer }
    let player = AirPlayCastPlayer()
    castPlayer = player
    bumpSurfaceRevision()
    player.onTime = { [weak self] time in self?.handleCastTime(time) }
    player.onStateChange = { [weak self] in self?.handleCastStateChange() }
    player.onError = { [weak self] error in self?.handleCastError(error) }
    player.onEnded = { [weak self] in self?.handleCastEnded() }
    return player
  }

  private func handleCastTime(_ time: TimeInterval) {
    // During a refresh the old player may still tick; ignore so the scrubber
    // stays pinned at the seek target.
    guard case let .casting(active) = state, let castPlayer else { return }
    let reported = active.session == nil ? time : active.timeline.sourceTime(fromLocal: time)
    if position != reported { position = reported }
    // The writer's VOD pacing gate follows the playback position.
    active.session?.updatePlaybackPosition(reported)
    let total = active.session == nil
      ? castPlayer.duration
      : active.timeline.totalDuration(localPlayerDuration: castPlayer.duration)
    if duration != total { duration = total }
    onTimeTick?(reported)
    guard active.session != nil else { return }
    // Self-heal: fell behind the served window (long pause on a live sliding
    // window, or the event playlist trimmed) — refresh the session in place.
    let window = castPlayer.seekableRange
    let liveEdgeSeekSettling = liveEdgeSeekGraceUntil.map { Date() < $0 } ?? false
    // A live-edge seek that brought the playhead back re-arms the one-shot.
    if Self.liveEdgeSeekRecovered(
      seekTried: liveEdgeSeekGraceUntil != nil, seekSettling: liveEdgeSeekSettling,
      localTime: time, windowStart: window.start, windowEnd: window.end
    ) {
      liveEdgeSeekGraceUntil = nil
    }
    if Self.shouldSelfHeal(
      localTime: time, windowStart: window.start, windowEnd: window.end,
      isPaused: castPlayer.isPaused,
      liveEdgeSeekSettling: liveEdgeSeekSettling
    ) {
      switch Self.fellBehindAction(
        isLive: active.content.isLive, liveEdgeSeekTried: liveEdgeSeekGraceUntil != nil
      ) {
      case .seekToLiveEdge:
        // Sets the latch and its grace; the next ticks hold off until it passes.
        seekToLiveEdgeIfBehind(castPlayer, trigger: "playing")
      case .rebuildSession:
        Log.info("AirPlayCast", "still behind the live window after the seek; refreshing session")
        liveEdgeSeekGraceUntil = nil
        // Same protection as every other in-place rebuild: the session is stopped
        // first (never orphan a writer that holds a panel connection), the new
        // writer drains it before opening, and a transient open failure gets its
        // one retry instead of ending the cast.
        rebuildSessionInPlace(active, cause: .fellBehindLiveWindow)
      case .reseek:
        Log.info("AirPlayCast", "fell behind served window; refreshing session")
        seek(toSource: reported)
      }
    }
  }

  private func handleCastStateChange() {
    guard let castPlayer else { return }
    let externalNow = castPlayer.isExternalPlaybackActive
    let externalJustActivated = externalNow && !isExternalPlaybackActive
    if isExternalPlaybackActive != externalNow {
      isExternalPlaybackActive = externalNow
      Log.info("AirPlayCast", "external playback \(externalNow ? "on" : "off")")
    }
    // The receiver took the picture: the wait for that is over, for the whole
    // engagement (see `armExternalWaitIfNeeded`).
    if externalNow { noteExternalPlaybackSeen() }
    notePausedState(castPlayer.isPaused)
    guard case var .casting(active) = state else { return }
    // From here on the receiver fetches the session from this phone by itself;
    // nothing else would notice a receiver that cannot reach it.
    if externalJustActivated, let session = active.session {
      armReceiverWatchdog(for: session)
    }
    // The receiver now opens the provider's HLS stream with its own client. That
    // it played on the phone says nothing about the receiver, so the attempt is
    // watched once more, with the time a receiver is given to start.
    if externalJustActivated, active.nativeTwinURL != nil {
      armNativeWatchdog(limitSeconds: Self.receiverWatchdogSeconds)
    }
    // AirPlay handoff: the Apple TV fetches the playlist ITSELF and performs its
    // own join — the phone-side player's earlier position corrections do not carry
    // over. EXT-X-START pins fresh joins to 0; this is the safety net for players
    // that ignore it AND it preserves an in-window position the user had seeked to.
    if externalJustActivated, active.session != nil, !active.content.isLive {
      let localExpected = active.timeline.localTarget(forSource: position)
      if abs(castPlayer.currentTime - localExpected) > 5 {
        Log.info("AirPlayCast", "correcting position after AirPlay handoff")
        castPlayer.seek(to: localExpected)
      }
    }
    let resumedNow = isPaused && !castPlayer.isPaused
    if isPaused != castPlayer.isPaused { isPaused = castPlayer.isPaused }
    if isBuffering != castPlayer.isBuffering { isBuffering = castPlayer.isBuffering }
    if castPlayer.isReadyToPlay {
      if !isPlaybackEstablished { isPlaybackEstablished = true }
      // Live is not seekable on either path that stands in for the source URL:
      // the remux window and the provider's HLS twin.
      let seekable = !(active.content.isLive
        && (active.session != nil || active.nativeTwinURL != nil))
      if isSeekable != seekable { isSeekable = seekable }
      // AVPlayer can treat a growing event playlist as live and join at its
      // edge; remuxed VOD must start from local 0 (the requested offset).
      if active.session != nil, !active.content.isLive, !active.didCorrectLiveEdgeJoin {
        active.didCorrectLiveEdgeJoin = true
        state = .casting(active)
        if castPlayer.currentTime > 3 {
          castPlayer.seek(to: 0)
        }
      }
    }
    // A paused cast started playing. `play()` runs the local-server repair for a
    // resume that comes through this controller; one made with the TV remote is
    // only seen here, and it is the same moment: the receiver starts fetching
    // again, possibly from a listener iOS reclaimed while the cast sat paused.
    // After `play()` this repeats the check, which costs one loopback request.
    // Last in this function: the repair may rebuild the session, and nothing
    // above may run on the state it leaves.
    if resumedNow { repairLocalServerIfNeeded() }
  }

  private func handleCastError(_ error: Error) {
    let detail = Self.logDescription(of: error)
    // During .preparing/.refreshing the loaded item is the SUPERSEDED one — its
    // failure (e.g. old session's deleted playlist 404ing into .failed) must not
    // abort the healthy new session.
    guard case let .casting(active) = state else {
      Log.error("AirPlayCast", "stale cast item error ignored during transition: \(detail)")
      return
    }
    // The provider's HLS twin failed (on the phone or on the receiver): the remux
    // of the original URL is the proven path, so the cast is not ended for it.
    if active.nativeTwinURL != nil {
      fallBackFromNativeTwin(active, why: "item failed: \(detail)")
      return
    }
    Log.error("AirPlayCast", "cast playback failed: \(detail)")
    logReceiverFetches(of: active.session, "item failed")
    // A remux item is served by this phone. If its listener is gone (reclaimed
    // while the app was suspended) the failure says nothing about the stream or
    // the receiver, and the session is rebuilt on the listener that serves now.
    let server = LocalHTTPServer.shared
    let isRemuxSession = active.session != nil
    var listenerWasServing = true
    var portChanged = false
    if isRemuxSession, !isCompleted {
      listenerWasServing = server.port > 0
      portChanged = server.ensureRunning()
    }
    // Read now: the failed item has stopped the player, and by the time a probe
    // answers that stop could pass for a pause of the user's.
    let startPaused = castPausedByUser
    switch Self.castItemFailureAction(
      isRemuxSession: isRemuxSession, contentCompleted: isCompleted,
      listenerWasServing: listenerWasServing, portChanged: portChanged, healthy: nil
    ) {
    case .rebuildInPlace:
      rebuildSessionInPlace(active, cause: .localServerLost, startPaused: startPaused)
    case .endCast:
      endCasting(resume: true, reason: .receiverFailed)
    case .probeListener:
      // The item stays failed for the moment the probe takes (the cast player
      // reports a failure once per item); every outcome below ends that.
      server.checkHealth { [weak self, weak session = active.session] healthy in
        guard let self, let session, !self.isDisposed,
              case let .casting(current) = self.state, current.session === session
        else { return }
        switch Self.castItemFailureAction(
          isRemuxSession: true, contentCompleted: self.isCompleted,
          listenerWasServing: true, portChanged: false, healthy: healthy
        ) {
        case .rebuildInPlace:
          // Give the server the chance to replace the listener the probe found
          // dead; the rebuilt session mints its URLs from whatever port is current.
          _ = server.ensureRunning()
          self.rebuildSessionInPlace(current, cause: .localServerLost, startPaused: startPaused)
        case .endCast, .probeListener:
          self.endCasting(resume: true, reason: .receiverFailed)
        }
      }
    }
  }

  private func handleCastEnded() {
    guard case .casting = state else { return }
    // Played to the end of the written playlist (ENDLIST): drives auto-next.
    if !isCompleted { isCompleted = true }
    if !isPaused { isPaused = true }
    // Nothing is playing any more, so background audio no longer keeps a locked
    // phone running, and the owner's auto-next countdown has yet to reach
    // `playContent`. Hold the process across that gap; the next session start,
    // `endCasting` or `dispose` releases it, and it expires by itself after a
    // film or a live item.
    beginBackgroundHold()
  }

  // MARK: - Seek helpers

  private func seekWhileCasting(_ active: Active, target: TimeInterval) {
    guard let castPlayer else { return }
    if active.session == nil {
      castPlayer.seek(to: target)
      if position != target { position = target }
      return
    }
    if active.content.isLive { return }  // live remux is not seekable
    let local = active.timeline.localTarget(forSource: target)
    let window = castPlayer.seekableRange
    if window.end > 2, local >= window.start + 1, local < window.end - 1 {
      castPlayer.seek(to: local)
      if position != target { position = target }
    } else {
      // Outside the written range: pin the scrubber at the target and rebuild
      // the session from there. The old writer is stopped FIRST and drained by
      // the new one: two connections to the same source is what single-connection
      // panels refuse. What it already wrote (up to 25 s ahead) stays on disk for
      // 30 s and keeps the TV playing meanwhile. Staying in `.refreshing` (not
      // `.preparing`) keeps duration and the established state on screen.
      if position != target { position = target }
      if !isBuffering { isBuffering = true }
      let outgoing = active.session
      logReceiverFetches(of: outgoing, "seek refresh")
      outgoing?.stop()
      var content = active.content
      content.startAt = target
      content.startPaused = rebuildStartsPaused(fallback: content.startPaused)
      beginRemuxSession(
        content: content, replacing: active, retryUsed: false,
        openDelaySeconds: 3.0, previousToDrain: outgoing, completion: nil
      )
    }
  }

  // MARK: - Route observation

  /// An AirPlay output is the current audio route. Read-only for the owner (it
  /// decides whether raising the device picker or offering Cancel makes sense);
  /// nothing outside this class may start or end an engagement from it.
  var isAirPlayRouteActive: Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs
      .contains { $0.portType == .airPlay }
  }

  /// The route observer has exactly two jobs: cancel a pending drop when the
  /// route comes back, and end the engagement when a drop is confirmed. It never
  /// starts anything. Drops are ignored while `.preparing`: stopping the direct
  /// player flaps the route by itself, and the prepare window has its own
  /// failure handling — acting on the echo of our own teardown was a root cause
  /// of the historical zap breakage.
  /// (A route that shows up under a cast that already plays also starts the wait
  /// for the receiver to take the picture, which again can only end the
  /// engagement; see `armExternalWaitIfNeeded`.)
  private func handleRouteChange() {
    guard !isDisposed, isEngaged else { return }
    if isAirPlayRouteActive {
      if routeDropConfirmWork != nil { Log.info("AirPlayCast", "route back") }
      routeDropConfirmWork?.cancel()
      routeDropConfirmWork = nil
      noteRouteActive()
      pickerGraceWork?.cancel()
      pickerGraceWork = nil
      pickerSettleDeadline = nil
      // Route changes come in bursts; a wait that is already running keeps its time.
      if externalWaitWork == nil { armExternalWaitIfNeeded() }
    } else if routeWasActiveDuringEngagement, routeDropConfirmWork == nil {
      switch state {
      case .casting, .refreshing:
        // Content finished: the TV may drop the route at the end of playback while
        // the 5s auto-next countdown runs. Acting on it would resurrect the ended
        // content at its final seconds (the field-reported old/new alternation) —
        // the countdown owns this window; the next content re-arms route watching.
        // A parked engagement has no owner, so no countdown and no next content:
        // there the drop is confirmed and acted on, or finished content would keep
        // the engagement (and the next screen's detour through it) forever.
        guard Self.shouldConfirmRouteDrop(
          contentCompleted: isCompleted, ownerAttached: ownerToken != nil
        ) else { break }
        scheduleRouteDropConfirm()
      case .idle, .preparing:
        break
      }
    }
  }

  /// After entering a presenting state with no active route: either the user has
  /// not picked a device yet (grace window — how long depends on what the route
  /// pickers reported, see `routeLessWaitSeconds`) or a drop is pending confirmation.
  private func armRouteWatch() {
    guard !isAirPlayRouteActive else {
      noteRouteActive()
      // A route alone is not a cast: the receiver still has to take the picture.
      armExternalWaitIfNeeded()
      return
    }
    if routeWasActiveDuringEngagement {
      scheduleRouteDropConfirm()
    } else {
      schedulePickerGrace(after: Self.routeLessWaitSeconds(
        pickerPresented: isPickerPresented,
        secondsUntilSettleDeadline: pickerSettleDeadline.map { $0.timeIntervalSinceNow }
      ))
    }
  }

  /// An AirPlay route is the current output: remember it for the engagement and,
  /// the first time, say so in the log.
  private func noteRouteActive() {
    guard !routeWasActiveDuringEngagement else { return }
    routeWasActiveDuringEngagement = true
    Log.info("AirPlayCast", "route active")
  }

  // MARK: - Route that never takes the picture

  /// The cast player reported external playback at some point in this
  /// engagement. From then on the route is known to carry video, and the wait
  /// below never runs again: a TV that drops out of external playback for a
  /// moment (a zap, a rebuild) must not be mistaken for a speaker.
  private var externalPlaybackSeenDuringEngagement = false
  private var externalWaitWork: DispatchWorkItem?
  /// How long a cast that plays with a route selected may stay off the receiver
  /// before it is ended. Long enough for a TV that has to wake up; not measured
  /// on a device.
  static let externalWaitSeconds: TimeInterval = 20

  enum ExternalWaitVerdict: Equatable {
    /// Nothing for this wait to do: the receiver has (or once had) the picture,
    /// the route is gone (the drop confirmation owns that), or nothing is casting.
    case standDown
    /// Nothing can be concluded yet: look again after another wait.
    case waitLonger
    /// The cast plays on the phone while its sound goes to the route, and the
    /// receiver never took the picture: end the engagement.
    case routeHasNoVideo
  }

  /// Is there an engagement this wait applies to? Only a cast that is playing
  /// (`.casting`; never while preparing or refreshing) with a route selected and
  /// a cast player that is not external and never was during this engagement.
  static func shouldArmExternalWait(
    isCasting: Bool,
    routeActiveNow: Bool,
    externalPlaybackActive: Bool,
    externalPlaybackSeen: Bool
  ) -> Bool {
    isCasting && routeActiveNow && !externalPlaybackActive && !externalPlaybackSeen
  }

  /// What the wait does when it runs out. An AirPlay speaker (the audio route
  /// cannot tell one from an Apple TV) takes the sound and never the picture, and
  /// no other exit covers "route active, never external": the engagement would
  /// last until the user deselects the speaker, with the cast-mode restrictions
  /// and nothing on screen to explain them. It is only ended on evidence that it
  /// plays on the phone: not while paused, not while the item is still loading or
  /// stalled (a hand-over in progress looks like that), and not while system UI
  /// covers the app (a TV asking for its AirPlay code).
  static func externalWaitVerdict(
    isCasting: Bool,
    routeActiveNow: Bool,
    externalPlaybackActive: Bool,
    externalPlaybackSeen: Bool,
    isPaused: Bool,
    isBuffering: Bool,
    appIsInactive: Bool
  ) -> ExternalWaitVerdict {
    guard shouldArmExternalWait(
      isCasting: isCasting, routeActiveNow: routeActiveNow,
      externalPlaybackActive: externalPlaybackActive,
      externalPlaybackSeen: externalPlaybackSeen
    ) else { return .standDown }
    if isPaused || isBuffering || appIsInactive { return .waitLonger }
    return .routeHasNoVideo
  }

  private var isCasting: Bool {
    if case .casting = state { return true }
    return false
  }

  private func noteExternalPlaybackSeen() {
    externalPlaybackSeenDuringEngagement = true
    externalWaitWork?.cancel()
    externalWaitWork = nil
  }

  /// Arms the one-shot wait when it applies (see `shouldArmExternalWait`). Its
  /// own work item: the picker wait is cancelled for good as soon as a route is
  /// active, which is exactly when this one has to run. `transition` cancels it,
  /// so it never runs across a state change; every entry into `.casting` arms it
  /// again through `armRouteWatch`. It can only end an engagement.
  private func armExternalWaitIfNeeded() {
    externalWaitWork?.cancel()
    externalWaitWork = nil
    guard !isDisposed else { return }
    let externalNow = castPlayer?.isExternalPlaybackActive == true
    // The player may already be external before its state change is delivered.
    if externalNow { externalPlaybackSeenDuringEngagement = true }
    guard Self.shouldArmExternalWait(
      isCasting: isCasting, routeActiveNow: isAirPlayRouteActive,
      externalPlaybackActive: externalNow,
      externalPlaybackSeen: externalPlaybackSeenDuringEngagement
    ) else { return }
    let work = DispatchWorkItem { [weak self] in self?.externalWaitExpired() }
    externalWaitWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.externalWaitSeconds, execute: work)
  }

  private func externalWaitExpired() {
    externalWaitWork = nil
    guard !isDisposed else { return }
    switch Self.externalWaitVerdict(
      isCasting: isCasting,
      routeActiveNow: isAirPlayRouteActive,
      externalPlaybackActive: castPlayer?.isExternalPlaybackActive == true,
      externalPlaybackSeen: externalPlaybackSeenDuringEngagement,
      isPaused: castPlayer?.isPaused ?? true,
      isBuffering: castPlayer?.isBuffering ?? true,
      appIsInactive: UIApplication.shared.applicationState == .inactive
    ) {
    case .standDown:
      break
    case .waitLonger:
      armExternalWaitIfNeeded()
    case .routeHasNoVideo:
      Log.error(
        "AirPlayCast",
        "route active for \(Int(Self.externalWaitSeconds))s but the receiver never took the picture; ending cast"
      )
      endCasting(resume: true, reason: .routeHasNoVideo)
    }
  }

  /// The settle a picker close armed belongs to the engagement, not to the state
  /// that happened to be current. `transition` cancels every timer, so after a
  /// transition that stays in `.preparing` (the delayed start retry, a rebuild)
  /// it is armed again with the time that is left. `.casting` is covered by
  /// `armRouteWatch`, which every entry into that state calls.
  private func rearmPickerSettleWhilePreparing() {
    guard case .preparing = state, !isPickerPresented, let deadline = pickerSettleDeadline,
          Self.shouldSettleAfterPickerClose(
            isEngaged: true,
            routeWasActive: routeWasActiveDuringEngagement,
            routeActiveNow: isAirPlayRouteActive,
            externalPlaybackActive: castPlayer?.isExternalPlaybackActive == true
          )
    else { return }
    schedulePickerGrace(after: Self.routeLessWaitSeconds(
      pickerPresented: false, secondsUntilSettleDeadline: deadline.timeIntervalSinceNow
    ))
  }

  /// AirPlay routes flap briefly when an external-playback AVPlayer elsewhere is
  /// torn down; act only on a drop that persists.
  private func scheduleRouteDropConfirm() {
    routeDropConfirmWork?.cancel()
    Log.info("AirPlayCast", "route dropped; confirming")
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.isDisposed else { return }
      self.routeDropConfirmWork = nil
      guard !self.isAirPlayRouteActive else { return }
      self.endCasting(resume: true, reason: .routeDropped)
    }
    routeDropConfirmWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
  }

  /// One work item for every "no device yet" wait — the fallback, the backstop
  /// while a picker is open and the settle after it closed — so a route
  /// activation (`handleRouteChange`) and every state transition cancel whichever
  /// one is running.
  private func schedulePickerGrace(
    after seconds: TimeInterval, deferredForInactiveApp: Bool = false
  ) {
    pickerGraceWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.isDisposed else { return }
      self.pickerGraceWork = nil
      switch Self.pickerGraceExpiry(
        isEngaged: self.isEngaged,
        routeActiveNow: self.isAirPlayRouteActive,
        externalPlaybackActive: self.castPlayer?.isExternalPlaybackActive == true,
        appIsInactive: UIApplication.shared.applicationState == .inactive,
        wasDeferred: deferredForInactiveApp
      ) {
      case .keepEngagement:
        break
      case let .recheck(after, deferred):
        self.schedulePickerGrace(after: after, deferredForInactiveApp: deferred)
      case .endEngagement:
        // The wait ran out with the app in front: a picker still flagged as open
        // is one whose close was never reported.
        self.isPickerPresented = false
        self.endCasting(resume: true, reason: .noDeviceSelected)
      }
    }
    pickerGraceWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  // MARK: - Route picker presentation

  /// A route picker reported opening and has not reported closing. Only set
  /// while engaged; a plain flag, not a counter, because a `willBegin` can come
  /// without its `didEnd` (the picker view is unmounted while its list is open).
  private var isPickerPresented = false

  /// Wait for a device when no picker ever reported opening (delegate callback
  /// lost, programmatic tap failed): the pre-delegate behaviour.
  static let pickerFallbackGraceSeconds: TimeInterval = 30
  /// While a picker is on screen the user may be choosing, waking a TV or typing
  /// its code, so the short waits are suspended. This long one only covers a
  /// close that is never reported; without it such an engagement had no exit.
  static let pickerOpenBackstopSeconds: TimeInterval = 120
  /// Route activation lags the dismissal (TV waking, connection setup). Ending
  /// sooner would reload the engine and leave its audio on a TV that connects a
  /// moment later, with the picture on the phone.
  /// 12 s is the lower bound the audit asked for (12 to 15 s): the device list
  /// opens on the AirPlay tap, so a user who takes longer to choose than the
  /// session takes to prepare lands here, and 8 s was short for a TV that has to
  /// wake up. Not measured on a device.
  static let pickerCloseSettleSeconds: TimeInterval = 12
  /// The settle for a picker that closes while the session is still being
  /// prepared. The device list now opens on the AirPlay tap, so this is the normal
  /// case: nothing plays yet, and a TV that has to wake up (or asks for its code)
  /// can need longer than the settle of a cast that already plays locally.
  static let pickerClosePreparingSettleSeconds: TimeInterval = 15
  /// What is left of a settle is never shorter than this when it is armed again
  /// (session ready, a transition inside `.preparing`): the route gets a last
  /// moment to show up, also when the prepare outlasted the settle.
  static let pickerCloseMinimumRemainingSeconds: TimeInterval = 2
  /// Poll interval while a wait is held back because the app is inactive.
  static let pickerInactiveRecheckSeconds: TimeInterval = 2

  /// When the settle armed by the last picker close runs out; nil when no picker
  /// closed without a route during this engagement (or one opened again, or a
  /// route showed up). Kept apart from the work item, which dies with every
  /// transition, so the wait survives the step from `.preparing` to `.casting`.
  private var pickerSettleDeadline: Date?

  /// Either route picker (the hidden one behind the AirPlay button, the visible
  /// system button) is about to show its device list. Never starts anything: it
  /// only stretches a wait that is already running.
  func pickerWillOpen() {
    guard !isDisposed, isEngaged else { return }
    isPickerPresented = true
    // The user is choosing again: an earlier close no longer counts.
    pickerSettleDeadline = nil
    Log.info("AirPlayCast", "route picker opened")
    // No wait running (still preparing, refreshing, or a route exists): the flag
    // alone decides what `armRouteWatch` arms next.
    guard pickerGraceWork != nil else { return }
    if case .preparing = state {
      // The only wait that runs while preparing is the settle of an earlier
      // close. Preparing has no backstop of its own (its failure handling ends
      // it); the one for an open picker is armed when the session is ready.
      pickerGraceWork?.cancel()
      pickerGraceWork = nil
      return
    }
    schedulePickerGrace(after: Self.pickerOpenBackstopSeconds)
  }

  /// The picker closed — after a choice or a cancel, the callback is the same.
  /// Never starts anything: with no route it replaces the long wait by a short
  /// settle, after which the engagement ends through `endCasting`.
  func pickerDidClose() {
    isPickerPresented = false
    // The user has just chosen (or kept) a device. A wait for the receiver to take
    // the picture that was already running gets its full time again: without this,
    // a TV picked a few seconds before the wait for a speaker runs out would be
    // ended as a route without video.
    if externalWaitWork != nil { armExternalWaitIfNeeded() }
    guard !isDisposed, Self.shouldSettleAfterPickerClose(
      isEngaged: isEngaged,
      routeWasActive: routeWasActiveDuringEngagement,
      routeActiveNow: isAirPlayRouteActive,
      externalPlaybackActive: castPlayer?.isExternalPlaybackActive == true
    ) else { return }
    let settle = Self.pickerCloseSettle(isPreparing: isPreparing)
    pickerSettleDeadline = Date().addingTimeInterval(settle)
    Log.info("AirPlayCast", "route picker closed without a route; settling for \(Int(settle))s")
    schedulePickerGrace(after: settle)
  }

  /// How long a route-less engagement waits for a device before it is ended.
  static func pickerGraceSeconds(pickerPresented: Bool) -> TimeInterval {
    pickerPresented ? pickerOpenBackstopSeconds : pickerFallbackGraceSeconds
  }

  /// The settle a picker close arms when no route exists: longer while the
  /// session is still being prepared than once the cast plays locally.
  static func pickerCloseSettle(isPreparing: Bool) -> TimeInterval {
    isPreparing ? pickerClosePreparingSettleSeconds : pickerCloseSettleSeconds
  }

  /// The wait a route-less engagement gets when its session is ready (or its
  /// timers are armed again after a transition).
  /// - A picker is on screen: the long backstop, in case its close is never reported.
  /// - A picker already closed without a route: what is left of the settle that
  ///   close armed (`secondsUntilSettleDeadline`, negative once it has passed), but
  ///   at least `pickerCloseMinimumRemainingSeconds`. Not the 30 s fallback: no
  ///   picker is on screen any more, so nothing could be chosen during it.
  /// - No picker ever reported: the fallback.
  static func routeLessWaitSeconds(
    pickerPresented: Bool,
    secondsUntilSettleDeadline: TimeInterval?
  ) -> TimeInterval {
    if pickerPresented { return pickerOpenBackstopSeconds }
    if let remaining = secondsUntilSettleDeadline {
      return max(remaining, pickerCloseMinimumRemainingSeconds)
    }
    return pickerFallbackGraceSeconds
  }

  /// A reported picker close starts the short settle only for an engagement
  /// that never had a route. One that had (or has) a route is owned by the drop
  /// confirmation: switching receivers in the picker drops the route briefly.
  static func shouldSettleAfterPickerClose(
    isEngaged: Bool,
    routeWasActive: Bool,
    routeActiveNow: Bool,
    externalPlaybackActive: Bool
  ) -> Bool {
    isEngaged && !shouldPreserveEngagement(
      routeWasActive: routeWasActive,
      routeActiveNow: routeActiveNow,
      externalPlaybackActive: externalPlaybackActive
    )
  }

  enum PickerGraceExpiry: Equatable {
    /// A route or external playback appeared, or nothing is engaged any more.
    case keepEngagement
    /// Look again after `after` seconds; `deferred` records that the app was
    /// inactive at this check.
    case recheck(after: TimeInterval, deferred: Bool)
    /// No device was chosen: end the engagement and resume direct playback.
    case endEngagement
  }

  /// What a picker wait does when it runs out. While the app is inactive system
  /// UI covers it — the device list itself, or the prompt for a TV's AirPlay
  /// code — so the engagement is not ended underneath; once the app is back in
  /// front the route gets one normal settle before the engagement ends.
  static func pickerGraceExpiry(
    isEngaged: Bool,
    routeActiveNow: Bool,
    externalPlaybackActive: Bool,
    appIsInactive: Bool,
    wasDeferred: Bool
  ) -> PickerGraceExpiry {
    guard isEngaged, !routeActiveNow, !externalPlaybackActive else { return .keepEngagement }
    if appIsInactive {
      return .recheck(after: pickerInactiveRecheckSeconds, deferred: true)
    }
    if wasDeferred {
      return .recheck(after: pickerCloseSettleSeconds, deferred: false)
    }
    return .endEngagement
  }

  /// A route drop after the content finished is left alone while an owner is
  /// attached (its auto-next countdown owns that window). With no owner — a
  /// parked engagement — nothing else would ever end it.
  static func shouldConfirmRouteDrop(contentCompleted: Bool, ownerAttached: Bool) -> Bool {
    !(contentCompleted && ownerAttached)
  }

  // MARK: - Presentation helpers

  private func presentLoading(of content: Content) {
    if position != content.startAt { position = content.startAt }
    if duration != content.knownDuration { duration = content.knownDuration }
    if !isBuffering { isBuffering = true }
    if isCompleted { isCompleted = false }
    if isPaused != content.startPaused { isPaused = content.startPaused }
    // Not established: the owner must present "loading", and auto-resume paths
    // (remote play, interruption end) must not think playback is running — they
    // would resume the superseded item on the TV.
    if isPlaybackEstablished { isPlaybackEstablished = false }
  }

  private func resetPresentation() {
    if position != 0 { position = 0 }
    if duration != 0 { duration = 0 }
    if isPaused { isPaused = false }
    if isBuffering { isBuffering = false }
    if isCompleted { isCompleted = false }
    if isSeekable { isSeekable = false }
    if isPlaybackEstablished { isPlaybackEstablished = false }
    if isExternalPlaybackActive { isExternalPlaybackActive = false }
  }

  private func bumpSurfaceRevision() {
    surfaceRevision += 1
  }

  // MARK: - Background hold

  /// The prepare window (engine stopped, cast not yet playing) has no audio and
  /// no playback keeping the process alive; a background task covers it if the
  /// user locks the screen mid-handover.
  private func beginBackgroundHold() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AirPlayCastPrepare") {
      [weak self] in
      self?.endBackgroundHold()
    }
  }

  private func endBackgroundHold() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
