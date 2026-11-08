import Foundation

/// The three aspect presentations the player cycles through. Named fixed ratios
/// (16:9/4:3/16:10) were removed: they only ever pillar/letter-boxed the source at
/// its natural ratio inside a forced frame — indistinguishable from Fit for most
/// content and misleading. Fit / Fill / Center covers the real intents (respect the
/// source, crop-to-fill the screen, or map 1:1) — same set AVPlayer/Infuse expose.
enum VideoAspectMode: String, CaseIterable {
  /// Aspect-fit: source shown at its natural ratio, letter/pillar-boxed to fit the screen.
  case fit
  /// Zoom-to-fill: source scaled to cover the whole screen at its natural ratio; overflow cropped.
  case fill
  /// 1:1 pixel mapping (downscaled only if it doesn't fit).
  case center

  var iconName: String {
    switch self {
    case .fit: return "rectangle.arrowtriangle.2.inward"
    case .fill: return "rectangle.arrowtriangle.2.outward"
    case .center: return "square.dashed"
    }
  }

  /// Localized name of the mode ("1:1" reads the same in every language).
  var title: String {
    switch self {
    case .fit: return L("player.aspect_fit")
    case .fill: return L("player.aspect_fill")
    case .center: return "1:1"
    }
  }

  var accessibilityLabel: String {
    "\(L("player.aspect.title")): \(title)"
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
