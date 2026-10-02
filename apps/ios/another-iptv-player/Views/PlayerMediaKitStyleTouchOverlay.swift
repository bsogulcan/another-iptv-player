import SwiftUI
import UIKit

/// Gesture recognizers live below SwiftUI's edge sliders, so taps can leak through the
/// transparent SwiftUI drag surface. Reject only the actual capsule frames; excluding a
/// full-height edge strip creates large tap/long-press dead zones.
struct PlayerEdgeSliderGestureExclusion {
  static let hitSlop: CGFloat = 8

  static func contains(
    _ point: CGPoint,
    in bounds: CGRect,
    trackSize: CGSize,
    leadingInset: CGFloat,
    trailingInset: CGFloat
  ) -> Bool {
    guard bounds.width > 0, bounds.height > 0,
          trackSize.width > 0, trackSize.height > 0 else {
      return false
    }

    let originY = bounds.midY - trackSize.height / 2
    let leadingRect = CGRect(
      x: bounds.minX + leadingInset,
      y: originY,
      width: trackSize.width,
      height: trackSize.height
    ).insetBy(dx: -hitSlop, dy: -hitSlop)
    let trailingRect = CGRect(
      x: bounds.maxX - trailingInset - trackSize.width,
      y: originY,
      width: trackSize.width,
      height: trackSize.height
    ).insetBy(dx: -hitSlop, dy: -hitSlop)

    return leadingRect.contains(point) || trailingRect.contains(point)
  }
}

struct PlayerSpeedHoldGesturePolicy {
  /// UIKit's default long-press tolerance. The earlier 80 pt let a slow pull-down
  /// (under ~105 pt/s) turn into a 2x hold before the 44 pt dismiss activation; at 10 pt
  /// a real drag fails the hold inside the 0.42 s press window.
  static let allowableMovement: CGFloat = 10

  /// Whether a new 2x hold may be armed. Live streams are excluded: 2x drains the small
  /// live buffer (fed at 1x) in a few seconds and stalls into buffering. The gate is
  /// "live", not "seekable" — catch-up and VOD served without range support report
  /// non-seekable yet play fine at 2x.
  static func canBegin(
    settingEnabled: Bool,
    isPlaying: Bool,
    isLiveStream: Bool,
    isDismissDragActive: Bool
  ) -> Bool {
    settingEnabled && isPlaying && !isLiveStream && !isDismissDragActive
  }

  static func recognizerEnabled(canBegin: Bool, isActive: Bool) -> Bool {
    canBegin || isActive
  }
}

/// Double-tap seeking on the outer sides of the picture. The single tap is never
/// delayed: it toggles the chrome at once, and a second tap on the same side within
/// `maximumInterval` takes that toggle back and seeks instead.
struct PlayerDoubleTapSeekPolicy {
  /// Physical sides: like the skip buttons, they are not mirrored in right-to-left UI.
  enum Side: Equatable {
    case backward
    case forward
  }

  enum TapAction: Equatable {
    case toggleChrome
    /// `undoChromeToggle` is true for the tap that turns a single tap into a seek:
    /// the chrome change made by the first tap has to be taken back.
    case seek(Side, undoChromeToggle: Bool)
  }

  /// Share of the width, from each edge, that counts as a seek zone.
  static let outerZoneFraction: CGFloat = 0.35
  /// Longest gap between the first and the second tap.
  static let maximumInterval: TimeInterval = 0.3
  /// Once a seek sequence runs, further taps on that side keep adding to it for a
  /// little longer than the first pair: repeated taps are slower than a double tap,
  /// and a late one would otherwise toggle the chrome in the middle of the sequence.
  static let continuationInterval: TimeInterval = 0.5
  static let jumpSeconds = 10

  static func side(atX x: CGFloat, width: CGFloat) -> Side? {
    guard width > 0, x >= 0, x <= width else { return nil }
    let zone = width * outerZoneFraction
    if x <= zone { return .backward }
    if x >= width - zone { return .forward }
    return nil
  }

  /// Seconds the side indicator shows: taps on the same side while it is up add to it.
  static func indicatorSeconds(showing: (side: Side, seconds: Int)?, tapped side: Side) -> Int {
    guard let showing, showing.side == side else { return jumpSeconds }
    return showing.seconds + jumpSeconds
  }

  /// Turns the stream of single taps into chrome toggles and seeks.
  struct Tracker: Equatable {
    private(set) var lastSide: Side?
    private(set) var lastTime: TimeInterval?
    private(set) var isSeeking = false

    /// `side` is nil for a tap in the centre. `seekEnabled` is false on live TV and on
    /// content that cannot seek; every tap is then a plain chrome toggle.
    mutating func register(side: Side?, at time: TimeInterval, seekEnabled: Bool) -> TapAction {
      if seekEnabled, let side, side == lastSide, let lastTime {
        let gap = time - lastTime
        let limit = isSeeking
          ? PlayerDoubleTapSeekPolicy.continuationInterval
          : PlayerDoubleTapSeekPolicy.maximumInterval
        if gap >= 0, gap <= limit {
          let undo = !isSeeking
          isSeeking = true
          self.lastTime = time
          return .seek(side, undoChromeToggle: undo)
        }
      }
      lastSide = side
      lastTime = time
      isSeeking = false
      return .toggleChrome
    }

    mutating func reset() {
      lastSide = nil
      lastTime = nil
      isSeeking = false
    }
  }
}

/// Fit and Fill as the first step of the pinch, like the system player: from 1x in Fit
/// a pinch out lands on Fill, from Fill a pinch in lands on Fit. Past Fill the zoom is
/// free, and so is the zoom below a Fill that is a deep crop (see `deepCropCoverScale`).
/// The aspect mode itself stays the caller's (persisted) value; this only decides.
struct PlayerPinchAspectSnapPolicy {
  enum Outcome: Equatable {
    /// Keep whatever zoom the pinch ended at (the behaviour without a snap).
    case freeZoom
    case snapToFill
    case snapToFit
    /// A pinch in from Fill that was let go too early: back to Fill.
    case returnToFill
  }

  /// Below this cover scale Fit and Fill look the same (16:9 video on a 16:9 screen);
  /// a mode switch would only rewrite the saved setting.
  static let minimumCoverScale: CGFloat = 1.03
  /// Zoom a pinch out from Fit has to pass before it counts as "go to Fill".
  static let fillSnapThreshold: CGFloat = 1.05
  /// How far past the cover scale a pinch may end and still land on Fill.
  static let fillSnapOvershoot: CGFloat = 1.12
  /// Above this cover scale Fill is a deep crop (a wide picture on a portrait screen):
  /// only a pinch that ends near it lands on Fill, and the zoom below stays free.
  static let deepCropCoverScale: CGFloat = 2
  /// Zoom (relative to Fill) a pinch in has to go below to land on Fit.
  static let fitSnapThreshold: CGFloat = 0.95
  static let restTolerance: CGFloat = 0.001

  /// Scale that makes the fitted picture cover the container. 1 while sizes are unknown.
  static func coverScale(fitted: CGSize, container: CGSize) -> CGFloat {
    guard fitted.width > 0, fitted.height > 0,
          container.width > 0, container.height > 0 else {
      return 1
    }
    return max(container.width / fitted.width, container.height / fitted.height)
  }

  /// Lowest zoom a pinch may reach. Only Fill at rest opens the range below 1 (down to
  /// the fitted picture); everywhere else 1x stays the floor.
  static func minimumZoom(
    mode: VideoAspectMode,
    committedZoom: CGFloat,
    coverScale: CGFloat
  ) -> CGFloat {
    guard mode == .fill,
          committedZoom <= 1 + restTolerance,
          coverScale >= minimumCoverScale else {
      return 1
    }
    return 1 / coverScale
  }

  /// With a small cover scale the fixed threshold lies below the floor of the pinch;
  /// halfway back to Fit is then enough.
  static func fitSnapLimit(coverScale: CGFloat) -> CGFloat {
    guard coverScale > 0 else { return fitSnapThreshold }
    return max(fitSnapThreshold, (1 + 1 / coverScale) / 2)
  }

  /// - Parameters:
  ///   - committedZoom: zoom before this pinch began.
  ///   - endZoom: zoom the pinch ended at, already clamped to the allowed range.
  ///   - cancelled: the recognizer was cancelled (system gesture, overlay disabled).
  ///     A cancelled pinch never changes the aspect mode.
  static func outcome(
    mode: VideoAspectMode,
    committedZoom: CGFloat,
    endZoom: CGFloat,
    coverScale: CGFloat,
    cancelled: Bool = false
  ) -> Outcome {
    guard coverScale >= minimumCoverScale else { return .freeZoom }
    switch mode {
    case .fit:
      guard !cancelled, abs(committedZoom - 1) <= restTolerance else { return .freeZoom }
      // A shallow crop is the first detent of the pinch. A deep one would swallow
      // the whole zoom range (the pinch stops at 4x), so it has a window of the same
      // relative width on both sides of the cover scale.
      let lower = coverScale > deepCropCoverScale
        ? coverScale / fillSnapOvershoot
        : fillSnapThreshold
      if endZoom > lower, endZoom <= coverScale * fillSnapOvershoot {
        return .snapToFill
      }
      return .freeZoom
    case .fill:
      // Below 1x is not a resting state in Fill: it resolves to Fit or back to Fill.
      guard endZoom < 1 - restTolerance else { return .freeZoom }
      if !cancelled, endZoom < fitSnapLimit(coverScale: coverScale) { return .snapToFit }
      return .returnToFill
    case .center:
      return .freeZoom
    }
  }
}

/// media-kit tarzı: kontroller **kapalıyken** tek parmak `UITapGestureRecognizer` ile göster (sürükleyerek kapatmayı
/// `touchesBegan` ile karıştırmaz). **Açıkken** gizleme yine tap; `UILongPressGestureRecognizer` (2x) ile
/// `require(toFail:)` sırası kullanılır.
/// VOD atlama ±15 sn, play/pause yanındaki SwiftUI düğmeleriyle.
/// Tüm pinch + pan (zoomluyken) bu UIKit container'ında; SwiftUI `.gesture` scaled-view'a
/// attached olduğunda koordinat sistemi bozuluyor ve outer dismiss gesture ile çakışıyor.
/// `hitTest` her zaman `super` döner — gesture recognizer'lar touch'ları yakalar, tap/pinch/pan
/// aynı anda `shouldRecognizeSimultaneouslyWith` ile konuşur.
final class PlayerMediaKitTouchContainerView: UIView, UIGestureRecognizerDelegate {
  fileprivate weak var coordinator: PlayerMediaKitStyleTouchOverlay.Coordinator?

  var videoZoomScale: CGFloat = 1 {
    didSet { videoPan.isEnabled = videoZoomScale > 1.02 }
  }
  /// The SwiftUI side turns interaction off when the pull-down / minimize morph starts.
  /// That is not a touch cancellation, so a pinch, pan or 2x hold under the fingers
  /// would never be told it is over: end it here.
  override var isUserInteractionEnabled: Bool {
    didSet {
      if oldValue, !isUserInteractionEnabled { cancelInFlightGestures() }
    }
  }
  /// Set at `.began`, cleared by whichever end arrives first (recognizer end,
  /// recognizer cancel or `cancelInFlightGestures`), so each gesture is ended once.
  private var isPinchInFlight = false
  private var isPanInFlight = false
  var enableSpeedHold: Bool = false
  var isSpeedHoldActive: Bool = false
  var isHideTapEnabled: Bool = true
  var edgeSliderTrackSize: CGSize = .zero
  var edgeSliderLeadingInset: CGFloat = 0
  var edgeSliderTrailingInset: CGFloat = 0

  fileprivate let centerView = MediaKitCenterPanel()
  private let videoPinch = UIPinchGestureRecognizer()
  private let videoPan = UIPanGestureRecognizer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isMultipleTouchEnabled = true
    isOpaque = false
    backgroundColor = .clear

    videoPinch.addTarget(self, action: #selector(handleVideoPinch(_:)))
    videoPinch.cancelsTouchesInView = false
    videoPinch.delegate = self
    addGestureRecognizer(videoPinch)

    videoPan.addTarget(self, action: #selector(handleVideoPan(_:)))
    videoPan.cancelsTouchesInView = false
    videoPan.delegate = self
    videoPan.minimumNumberOfTouches = 1
    videoPan.maximumNumberOfTouches = 1
    videoPan.isEnabled = false  // yalnızca zoomluyken aktif
    addGestureRecognizer(videoPan)

    addSubview(centerView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    centerView.frame = bounds
  }

  func bindToCoordinator(_ c: PlayerMediaKitStyleTouchOverlay.Coordinator) {
    coordinator = c
    centerView.coordinator = c
    syncPanels()
  }

  func syncPanels() {
    let show = coordinator?.showControls.wrappedValue ?? true
    centerView.configureRecognizers(
      showControls: show,
      enableSpeedHold: enableSpeedHold,
      isSpeedHoldActive: isSpeedHoldActive,
      isHideTapEnabled: isHideTapEnabled,
      edgeSliderTrackSize: edgeSliderTrackSize,
      edgeSliderLeadingInset: edgeSliderLeadingInset,
      edgeSliderTrailingInset: edgeSliderTrailingInset
    )
  }

  @objc private func handleVideoPinch(_ g: UIPinchGestureRecognizer) {
    switch g.state {
    case .began:
      isPinchInFlight = true
      let loc = g.location(in: self)
      coordinator?.onVideoPinchBegan(loc, bounds.size)
    case .changed:
      guard isPinchInFlight else { return }
      coordinator?.onVideoPinchChanged(g.scale)
    case .ended:
      guard isPinchInFlight else { return }
      isPinchInFlight = false
      coordinator?.onVideoPinchEnded()
    case .cancelled, .failed:
      // Same reset as a normal end (anchor cleared, zoom committed), reported
      // separately so an interrupted pinch cannot switch the aspect mode.
      guard isPinchInFlight else { return }
      isPinchInFlight = false
      coordinator?.onVideoPinchCancelled()
    default:
      break
    }
  }

  @objc private func handleVideoPan(_ g: UIPanGestureRecognizer) {
    switch g.state {
    case .began:
      isPanInFlight = true
    case .changed:
      guard isPanInFlight else { return }
      let t = g.translation(in: self)
      coordinator?.onVideoPanChanged(CGSize(width: t.x, height: t.y))
    case .ended, .cancelled, .failed:
      // A cancelled pan keeps what was dragged so far; the handler commits and clamps it.
      guard isPanInFlight else { return }
      isPanInFlight = false
      let t = g.translation(in: self)
      coordinator?.onVideoPanEnded(CGSize(width: t.x, height: t.y))
    default:
      break
    }
  }

  /// Ends every gesture that is still in flight, as if its recognizer had been
  /// cancelled. Later callbacks of those same touches are ignored by the in-flight flags.
  func cancelInFlightGestures() {
    let pinch = isPinchInFlight
    let pan = isPanInFlight
    let hold = centerView.takeSpeedHoldInFlight()
    guard pinch || pan || hold else { return }
    isPinchInFlight = false
    isPanInFlight = false
    let t = videoPan.translation(in: self)
    let translation = CGSize(width: t.x, height: t.y)
    // This runs inside a SwiftUI view update (`updateUIView`) and the handlers write
    // view state, so leave the update first.
    DispatchQueue.main.async { [weak coordinator] in
      guard let coordinator else { return }
      if pinch { coordinator.onVideoPinchCancelled() }
      if pan { coordinator.onVideoPanEnded(translation) }
      if hold { coordinator.requestSpeedHoldEndedFromUIKit() }
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

private final class MediaKitCenterPanel: UIView, UIGestureRecognizerDelegate {
  fileprivate weak var coordinator: PlayerMediaKitStyleTouchOverlay.Coordinator?

  private let showTap = UITapGestureRecognizer()
  private let hideTap = UITapGestureRecognizer()
  private let speedHold = UILongPressGestureRecognizer()
  /// A hold that has begun and not been ended yet; see `takeSpeedHoldInFlight`.
  private var isSpeedHoldInFlight = false
  private var controlsVisible = true
  private var edgeSliderTrackSize: CGSize = .zero
  private var edgeSliderLeadingInset: CGFloat = 0
  private var edgeSliderTrailingInset: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: .zero)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = true

    showTap.addTarget(self, action: #selector(showTapRecognized(_:)))
    showTap.numberOfTapsRequired = 1
    showTap.cancelsTouchesInView = false
    showTap.delegate = self
    addGestureRecognizer(showTap)

    hideTap.addTarget(self, action: #selector(hideTapRecognized(_:)))
    hideTap.numberOfTapsRequired = 1
    hideTap.cancelsTouchesInView = false
    hideTap.delegate = self
    addGestureRecognizer(hideTap)

    speedHold.addTarget(self, action: #selector(speedHoldRecognized(_:)))
    speedHold.minimumPressDuration = 0.42
    speedHold.allowableMovement = PlayerSpeedHoldGesturePolicy.allowableMovement
    speedHold.cancelsTouchesInView = false
    speedHold.delegate = self
    addGestureRecognizer(speedHold)

    showTap.require(toFail: speedHold)
    hideTap.require(toFail: speedHold)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configureRecognizers(
    showControls: Bool,
    enableSpeedHold: Bool,
    isSpeedHoldActive: Bool,
    isHideTapEnabled: Bool,
    edgeSliderTrackSize: CGSize,
    edgeSliderLeadingInset: CGFloat,
    edgeSliderTrailingInset: CGFloat
  ) {
    controlsVisible = showControls
    self.edgeSliderTrackSize = edgeSliderTrackSize
    self.edgeSliderLeadingInset = edgeSliderLeadingInset
    self.edgeSliderTrailingInset = edgeSliderTrailingInset
    showTap.isEnabled = !showControls && !isSpeedHoldActive
    // A second-finger tap on the video while the timeline is being dragged must not hide
    // the chrome: that unmounts the scrubber mid-drag and drops the seek.
    hideTap.isEnabled = showControls && !isSpeedHoldActive && isHideTapEnabled
    // Once the hold has begun, transient buffering must not disable (and therefore
    // cancel) the recognizer. The user's finger-up remains the single end condition.
    speedHold.isEnabled = PlayerSpeedHoldGesturePolicy.recognizerEnabled(
      canBegin: enableSpeedHold,
      isActive: isSpeedHoldActive
    )
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    // The 2x speed-hold must work from EVERY point, including over the edge sliders.
    // The sliders are drag-only (minimumDistance 8), so a stationary hold can never be
    // mistaken for a slider adjustment — there is nothing to exclude it from.
    if gestureRecognizer === speedHold { return true }
    // The edge sliders only exist while the chrome is visible; with controls hidden,
    // every point must remain a valid video gesture target. While visible, a single tap
    // over a slider capsule is still swallowed so it doesn't fight the slider drag.
    // Not while the chrome a side tap has just revealed is shielded: the capsules take
    // no touches then, and the second tap of a double tap has to arrive here.
    guard controlsVisible,
          ProcessInfo.processInfo.systemUptime >= (coordinator?.chromeTapShieldDeadline ?? 0)
    else { return true }
    return !PlayerEdgeSliderGestureExclusion.contains(
      touch.location(in: self),
      in: bounds,
      trackSize: edgeSliderTrackSize,
      leadingInset: edgeSliderLeadingInset,
      trailingInset: edgeSliderTrailingInset
    )
  }

  // Both taps stay plain single taps with no failure requirement on a double tap, so
  // the chrome reacts at once. The coordinator decides whether this tap completes a
  // double tap on a side zone; only then is the chrome toggle skipped. Taps on a
  // visible control never get here (SwiftUI takes them) and taps on a visible slider
  // capsule are rejected in `shouldReceive`, so neither can seek.
  @objc private func showTapRecognized(_ g: UITapGestureRecognizer) {
    guard let coordinator else { return }
    if coordinator.consumeTapAsSeek(atX: g.location(in: self).x, width: bounds.width) { return }
    coordinator.requestShowChromeFromUIKit()
  }

  @objc private func hideTapRecognized(_ g: UITapGestureRecognizer) {
    guard let coordinator else { return }
    if coordinator.consumeTapAsSeek(atX: g.location(in: self).x, width: bounds.width) { return }
    coordinator.requestHideChromeFromUIKit()
  }

  @objc private func speedHoldRecognized(_ g: UILongPressGestureRecognizer) {
    switch g.state {
    case .began:
      isSpeedHoldInFlight = true
      coordinator?.requestSpeedHoldBeganFromUIKit()
    case .ended, .cancelled, .failed:
      guard isSpeedHoldInFlight else { return }
      isSpeedHoldInFlight = false
      coordinator?.requestSpeedHoldEndedFromUIKit()
    default:
      break
    }
  }

  /// Hands the pending hold to the caller, which ends it; the recognizer's own end for
  /// the same touch is then ignored.
  func takeSpeedHoldInFlight() -> Bool {
    let inFlight = isSpeedHoldInFlight
    isSpeedHoldInFlight = false
    return inFlight
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

struct PlayerMediaKitStyleTouchOverlay: UIViewRepresentable {
  @Binding var showControls: Bool
  let isSeekDisabled: Bool
  let videoZoomScale: CGFloat
  let isSpeedHoldActive: Bool
  let isSpeedHoldEnabled: Bool
  let edgeSliderTrackSize: CGSize
  let edgeSliderLeadingInset: CGFloat
  let edgeSliderTrailingInset: CGFloat
  /// Disabled while the player is shrinking into / sitting in the mini card, so the
  /// UIKit tap/pinch/pan recognizers don't intercept touches meant for the mini chrome.
  var interactionEnabled: Bool = true
  /// False while the timeline is being scrubbed, so a tap on the video cannot hide the
  /// chrome (and with it the scrubber) under the dragging finger.
  var isHideTapEnabled: Bool = true
  /// True on seekable, non-live content: a second tap on the same outer side then seeks.
  var isDoubleTapSeekEnabled: Bool = false
  /// True while something drawn over the player (the live channel panel) is waiting for
  /// a tap on the video to close it: the tap then only runs `onVideoSurfaceTap` and
  /// leaves the chrome as it is.
  var isSurfaceTapExclusive: Bool = false
  let onResetTimer: () -> Void
  let onInvalidateTimer: () -> Void
  let onSpeedHoldBegan: () -> Void
  let onSpeedHoldEnded: () -> Void
  let onVideoPinchBegan: (CGPoint, CGSize) -> Void
  let onVideoPinchChanged: (CGFloat) -> Void
  let onVideoPinchEnded: () -> Void
  let onVideoPanChanged: (CGSize) -> Void
  let onVideoPanEnded: (CGSize) -> Void
  var onVideoSurfaceTap: (() -> Void)? = nil
  /// The pinch was cancelled instead of ended. Falls back to `onVideoPinchEnded`.
  var onVideoPinchCancelled: (() -> Void)? = nil
  var onDoubleTapSeek: ((PlayerDoubleTapSeekPolicy.Side) -> Void)? = nil
  /// A tap on a seek side is about to reveal the hidden chrome. It may be the first
  /// half of a double tap: the owner keeps the chrome from taking touches for
  /// `PlayerDoubleTapSeekPolicy.maximumInterval`, so the second tap lands here and not
  /// on a control that has just faded in under the finger.
  var onSideTapRevealsChrome: (() -> Void)? = nil

  func makeCoordinator() -> Coordinator {
    let coordinator = Coordinator(
      showControls: $showControls,
      onResetTimer: onResetTimer,
      onInvalidateTimer: onInvalidateTimer,
      onSpeedHoldBegan: onSpeedHoldBegan,
      onSpeedHoldEnded: onSpeedHoldEnded,
      onVideoPinchBegan: onVideoPinchBegan,
      onVideoPinchChanged: onVideoPinchChanged,
      onVideoPinchEnded: onVideoPinchEnded,
      onVideoPanChanged: onVideoPanChanged,
      onVideoPanEnded: onVideoPanEnded,
      onVideoSurfaceTap: onVideoSurfaceTap
    )
    coordinator.onVideoPinchCancelled = onVideoPinchCancelled ?? onVideoPinchEnded
    coordinator.isDoubleTapSeekEnabled = isDoubleTapSeekEnabled
    coordinator.isSurfaceTapExclusive = isSurfaceTapExclusive
    coordinator.onDoubleTapSeek = onDoubleTapSeek
    coordinator.onSideTapRevealsChrome = onSideTapRevealsChrome
    return coordinator
  }

  func makeUIView(context: Context) -> PlayerMediaKitTouchContainerView {
    let v = PlayerMediaKitTouchContainerView()
    v.bindToCoordinator(context.coordinator)
    return v
  }

  func updateUIView(_ uiView: PlayerMediaKitTouchContainerView, context: Context) {
    context.coordinator.showControls = $showControls
    context.coordinator.onResetTimer = onResetTimer
    context.coordinator.onInvalidateTimer = onInvalidateTimer
    context.coordinator.onSpeedHoldBegan = onSpeedHoldBegan
    context.coordinator.onSpeedHoldEnded = onSpeedHoldEnded
    context.coordinator.onVideoPinchBegan = onVideoPinchBegan
    context.coordinator.onVideoPinchChanged = onVideoPinchChanged
    context.coordinator.onVideoPinchEnded = onVideoPinchEnded
    context.coordinator.onVideoPanChanged = onVideoPanChanged
    context.coordinator.onVideoPanEnded = onVideoPanEnded
    context.coordinator.onVideoSurfaceTap = onVideoSurfaceTap
    context.coordinator.onVideoPinchCancelled = onVideoPinchCancelled ?? onVideoPinchEnded
    context.coordinator.isDoubleTapSeekEnabled = isDoubleTapSeekEnabled
    context.coordinator.isSurfaceTapExclusive = isSurfaceTapExclusive
    context.coordinator.onDoubleTapSeek = onDoubleTapSeek
    context.coordinator.onSideTapRevealsChrome = onSideTapRevealsChrome
    uiView.videoZoomScale = videoZoomScale
    uiView.enableSpeedHold = isSpeedHoldEnabled && !isSeekDisabled && videoZoomScale <= 1.02
    uiView.isSpeedHoldActive = isSpeedHoldActive
    uiView.isHideTapEnabled = isHideTapEnabled
    uiView.edgeSliderTrackSize = edgeSliderTrackSize
    uiView.edgeSliderLeadingInset = edgeSliderLeadingInset
    uiView.edgeSliderTrailingInset = edgeSliderTrailingInset
    uiView.isUserInteractionEnabled = interactionEnabled
    uiView.syncPanels()
    uiView.setNeedsLayout()
  }

  final class Coordinator: NSObject {
    var showControls: Binding<Bool>
    var onResetTimer: () -> Void
    var onInvalidateTimer: () -> Void
    var onSpeedHoldBegan: () -> Void
    var onSpeedHoldEnded: () -> Void
    var onVideoPinchBegan: (CGPoint, CGSize) -> Void
    var onVideoPinchChanged: (CGFloat) -> Void
    var onVideoPinchEnded: () -> Void
    var onVideoPanChanged: (CGSize) -> Void
    var onVideoPanEnded: (CGSize) -> Void
    var onVideoSurfaceTap: (() -> Void)?
    var onVideoPinchCancelled: () -> Void = {}
    var isDoubleTapSeekEnabled = false
    /// See `PlayerMediaKitStyleTouchOverlay.isSurfaceTapExclusive`.
    var isSurfaceTapExclusive = false
    var onDoubleTapSeek: ((PlayerDoubleTapSeekPolicy.Side) -> Void)?
    /// See `PlayerMediaKitStyleTouchOverlay.onSideTapRevealsChrome`.
    var onSideTapRevealsChrome: (() -> Void)?
    private var tapTracker = PlayerDoubleTapSeekPolicy.Tracker()
    /// Chrome visibility before the last single tap toggled it; what a double tap restores.
    private var chromeBeforeLastTap: Bool?
    /// Uptime until which the chrome revealed by a side tap takes no touches (the
    /// owner switches its hit testing off for the same time). Until then the surface
    /// taps also ignore the edge-slider capsules, which sit inside the seek zones.
    private(set) var chromeTapShieldDeadline: TimeInterval = 0

    init(
      showControls: Binding<Bool>,
      onResetTimer: @escaping () -> Void,
      onInvalidateTimer: @escaping () -> Void,
      onSpeedHoldBegan: @escaping () -> Void,
      onSpeedHoldEnded: @escaping () -> Void,
      onVideoPinchBegan: @escaping (CGPoint, CGSize) -> Void,
      onVideoPinchChanged: @escaping (CGFloat) -> Void,
      onVideoPinchEnded: @escaping () -> Void,
      onVideoPanChanged: @escaping (CGSize) -> Void,
      onVideoPanEnded: @escaping (CGSize) -> Void,
      onVideoSurfaceTap: (() -> Void)? = nil
    ) {
      self.showControls = showControls
      self.onResetTimer = onResetTimer
      self.onInvalidateTimer = onInvalidateTimer
      self.onSpeedHoldBegan = onSpeedHoldBegan
      self.onSpeedHoldEnded = onSpeedHoldEnded
      self.onVideoPinchBegan = onVideoPinchBegan
      self.onVideoPinchChanged = onVideoPinchChanged
      self.onVideoPinchEnded = onVideoPinchEnded
      self.onVideoPanChanged = onVideoPanChanged
      self.onVideoPanEnded = onVideoPanEnded
      self.onVideoSurfaceTap = onVideoSurfaceTap
    }

    private func runOnMain(_ body: @escaping () -> Void) {
      if Thread.isMainThread {
        body()
      } else {
        DispatchQueue.main.async(execute: body)
      }
    }

    private func setShowControlsAnimated(_ newValue: Bool) {
      // Cross-fade the chrome like the native player. Previously this was a hard cut
      // (Transaction.disablesAnimations) which made the `.opacity` transition inert.
      withAnimation(.easeInOut(duration: 0.28)) {
        showControls.wrappedValue = newValue
      }
    }

    /// Called for every single tap on the surface, before its chrome toggle. Returns
    /// true when the tap completed (or continued) a double-tap seek: the toggle of the
    /// first tap has been taken back and this tap must not toggle the chrome.
    /// Gesture actions arrive on the main thread.
    func consumeTapAsSeek(atX x: CGFloat, width: CGFloat) -> Bool {
      let side = PlayerDoubleTapSeekPolicy.side(atX: x, width: width)
      let seekEnabled = isDoubleTapSeekEnabled && onDoubleTapSeek != nil
      let now = ProcessInfo.processInfo.systemUptime
      let action = tapTracker.register(side: side, at: now, seekEnabled: seekEnabled)
      switch action {
      case .toggleChrome:
        chromeBeforeLastTap = showControls.wrappedValue
        // This tap is about to reveal the chrome and may be the first half of a
        // double tap: the controls that fade in under the finger must not take the
        // second one (see `onSideTapRevealsChrome`).
        if seekEnabled, side != nil, !showControls.wrappedValue, !isSurfaceTapExclusive {
          chromeTapShieldDeadline = now + PlayerDoubleTapSeekPolicy.maximumInterval
          onSideTapRevealsChrome?()
        }
        return false
      case .seek(let side, let undoChromeToggle):
        if undoChromeToggle, let previous = chromeBeforeLastTap,
           showControls.wrappedValue != previous {
          setShowControlsAnimated(previous)
          if !previous { onInvalidateTimer() }
        }
        chromeBeforeLastTap = nil
        // Keep visible controls up while the taps go on.
        if showControls.wrappedValue { onResetTimer() }
        onDoubleTapSeek?(side)
        return true
      }
    }

    func requestShowChromeFromUIKit() {
      runOnMain { [weak self] in
        guard let self else { return }
        // Read before the callback: it closes the panel, and the flag only follows
        // on the next view update.
        let exclusive = self.isSurfaceTapExclusive
        self.onVideoSurfaceTap?()
        // The tap closed the panel; it does not toggle the chrome as well.
        guard !exclusive else { return }
        guard !self.showControls.wrappedValue else { return }
        self.setShowControlsAnimated(true)
        self.onResetTimer()
      }
    }

    func requestHideChromeFromUIKit() {
      runOnMain { [weak self] in
        guard let self else { return }
        let exclusive = self.isSurfaceTapExclusive
        self.onVideoSurfaceTap?()
        guard !exclusive else { return }
        guard self.showControls.wrappedValue else { return }
        self.setShowControlsAnimated(false)
        self.onInvalidateTimer()
      }
    }

    func requestSpeedHoldBeganFromUIKit() {
      runOnMain { [weak self] in
        self?.onSpeedHoldBegan()
      }
    }

    func requestSpeedHoldEndedFromUIKit() {
      runOnMain { [weak self] in
        self?.onSpeedHoldEnded()
      }
    }
  }
}
